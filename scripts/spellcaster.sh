#!/bin/bash

# this script handles automatically casting all required spells into the ISO
# chroot, and also the casting and subsequent dispelling (with caches enabled)
# of the optional spells.

MYDIR="$(dirname $0)"
CAULDRONDIR="$MYDIR"/../data

function usage() {
  cat << EndUsage
Usage: $(basename $0) [-h] [-i ISO] [-s SYS] /path/to/target ARCHITECTURE

Casts the required and optional spells onto the ISO.
This script requires superuser privileges.

Required:
	/path/to/target
	    The location of the chroot directory you would like to have the
	    casting done in.

	ARCHITECTURE
	    The architecture you are building the ISO for. Although the spells
	    will largely be the same, there will be some differences,
	    particularly in the case of bootloaders. Defaults to "x86" if not
	    specified.

Options:
	-h  Shows this help information

	-i  Path to iso build directory (ISO). Defaults to /tmp/cauldron/iso.

	-s  Path to system build directory (SYS). Defaults to
	    /tmp/cauldron/system.
EndUsage
  exit 1
} >&2

function parse_options() {
	while getopts ":i:s:h" Option
	do
		case $Option in
			i ) ISODIR="${OPTARG%/}" ;;
			s ) SYSDIR="${OPTARG%/}" ;;
			h ) usage ;;
			* ) echo "Unrecognized option." >&2 && usage ;;
		esac
	done
	return $(($OPTIND - 1))
}

function priv_check() {
	local SELF="$0"

	if [[ $UID -ne 0 ]]
	then
		if [[ -x $(which sudo 2> /dev/null) ]]
		then
			exec sudo -H $SELF $*
		else
			echo "Please enter the root password."
			exec su -c "$SELF $*" root
		fi
	fi
}

function directory_check() {
	if [[ ! -d $1 ]]
	then
		mkdir -p $1
	fi
}

# check to make sure that the chroot has sorcery set to do caches
function sanity_check() {
	local config="$TARGET/etc/sorcery/local/config"
	local arch=
	local choice=

	# Ensure that TARGET is a directory
	[[ -d "$TARGET" ]] || {
		echo "$TARGET does not exist!"
		exit 3
	}

	# If ISODIR is not a directory, create it.
	directory_check "$ISODIR"

	# If ISODIR/var/cache/sorcery is not a directory, create it.
	directory_check "$ISODIR/var/cache/sorcery"

	# If ISODIR/var/spool/sorcery is not a directory, create it.
	directory_check "$ISODIR/var/spool/sorcery"

	# If SYSDIR is not a directory, create it.
	directory_check "$SYSDIR"

	# If SYSDIR/var/cache/sorcery is not a directory, create it.
	directory_check "$SYSDIR/var/cache/sorcery"

	# If SYSDIR/var/spool/sorcery is not a directory, create it.
	directory_check "$SYSDIR/var/spool/sorcery"

	if [[ -e "$config" ]]
	then
		arch="$(source "$config" &> /dev/null && echo $ARCHIVE)"
		if [[ -n $arch && $arch != "on" ]]
		then
			echo "Error! TARGET sorcery does not archive!" >&2
			echo -n "Set TARGET sorcery to archive? [yn]" >&2
			read -n1 choice
			echo ""

			if [[ $choice == 'y' ]]
			then
				. "$TARGET/var/lib/sorcery/modules/libstate"
				modify_config $config ARCHIVE on
			else
				echo "Archiving required, bailing out!"
				exit 2
			fi
		fi
	fi
}

function prepare_target() {
	export rspells="rspells.$TYPE"
	export ispells="ispells.$TYPE"
	export ospells="ospells.$TYPE"

	# Copy resolv.conf so spell sources can be downloaded inside the TARGET
	cp -f "$TARGET"/etc/resolv.conf "$TARGET"/tmp/resolv.conf &&
		cp -f /etc/resolv.conf "$TARGET"/etc/resolv.conf

	# If using the linux spell copy the kernel config to TARGET sorcery
	grep -q '^linux$' "$CAULDRONDIR/$rspells" "$CAULDRONDIR/$ospells" &&
	cp "$CAULDRONDIR/config-2.6" "$TARGET/etc/sorcery/local/kernel.config"

	# Copy the list of spells needed for casting into the TARGET if casting
	cp "$CAULDRONDIR/rspells.$TYPE" "$TARGET"/rspells
	cp "$CAULDRONDIR/ispells.$TYPE" "$TARGET"/ispells
	cp "$CAULDRONDIR/ospells.$TYPE" "$TARGET"/ospells

	# Copy any spell-specific required options into the TARGET
	[[ -d "$TARGET"/etc/sorcery/local/depends/ ]] ||
		mkdir -p "$TARGET"/etc/sorcery/local/depends/
	cp "$CAULDRONDIR"/depends/* "$TARGET"/etc/sorcery/local/depends/

	# generate basesystem casting script inside of TARGET
	cat > "$TARGET"/build_spells.sh <<-'SPELLS'

	if [[ -n $CAULDRON_CHROOT && $# -eq 0 ]]
	then

		# If console-tools is found in TARGET, get rid of it to make
		# way for kbd
		[[ $(gaze -q installed console-tools) != "not installed" ]] &&
		dispel --orphan always console-tools

		# push the needed spells into the install queue
		cat rspells ispells ospells > /var/log/sorcery/queue/install

		# cast all the spells using the install queue and save the
		# return value to a log file
		/usr/sbin/cast --queue 2> /build_spells.log
		echo $? >> /build_spells.log

		# make a list of the caches to unpack for system
		for spell in $(</rspells)
		do
			gaze installed $spell &> /dev/null &&
			echo $spell-$(gaze -q installed $spell)
		done > /sys-list || exit 42

		# make a list of the caches to unpack for iso
		for spell in $(</ispells)
		do
			gaze installed $spell &> /dev/null &&
			echo $spell-$(gaze -q installed $spell)
		done > /iso-list || exit 42

		# make a list of the optional caches to unpack for iso
		for spell in $(</ospells)
		do
			gaze installed $spell &> /dev/null &&
			echo $spell-$(gaze -q installed $spell)
		done > /opt-list || exit 42
	fi
SPELLS

	chmod a+x "$TARGET"/build_spells.sh
}

function install_kernel() {
	local SRC=$1
	local DST=$2
	local kconfig=$3
	local version=$4
	local kernel=

	# Exit if DST undefined, otherwise we could damage the host system
	[[ -z $DST ]] && exit 12

	if grep -q '^linux:' "$SRC"/var/state/sorcery/packages
	then
		version=$(grep '^linux:' "$SRC"/var/state/sorcery/packages)
		version=${version##*:}
		kernel="$SRC"/boot/vmlinuz
		${kconfig:="$SRC"/etc/sorcery/local/kernel.config}
	fi

	# Try to autodetect the location of the kernel config based on whether
	# the linux spell was used or not.
	if [[ -z $kconfig ]]
	then
		if [[ -f "$SRC"/usr/src/linux/.config ]]
		then
			kconfig="$SRC/usr/src/linux/.config"
		elif [[ -f "$SRC"/boot/config ]]
		then
			kconfig="$SRC/boot/config"
		fi
	fi
	if [[ -z $kconfig ]] 
	then
		echo "Could not find $SRC kernel config!"
		exit 13
	fi

	# Try to autodetect the linux kernel version using kernel directory or
	# kernel config
	if [[ -z $version ]]
	then
		local modules="$SRC/lib/modules"
		modules="$(find "$modules" -mindepth 1 -maxdepth 1 -type d)"
		modules="$(echo "$modules" | sed 's#.*/##')"

		if [[ $(echo "$modules" | wc -l) -eq 1 ]]
		then
			version="$modules"
		elif [[ -h "$SRC"/usr/src/linux ]]
		then
			if readlink "$SRC"/usr/src/linux
			then
				version="$(readlink "$SRC"/usr/src/linux)"
				version="${version#linux-}"
			fi
		else
			version=$(grep 'version:' "$kconfig")
			version="${version##*version: }"
		fi
	fi
	if [[ -z $version ]] 
	then
		echo "Could not determine $SRC kernel version!"
		exit 14
	fi

	# Try to guess the location of the kernel itself
	if [[ -z $kernel ]]
	then
		if [[ -e "$SRC"/boot/vmlinuz ]]
		then
			kernel="$SRC/boot/vmlinuz"
		elif [[ -e "$SRC"/usr/src/linux/arch/i386/boot/bzImage ]]
		then
			kernel="$SRC/usr/src/linux/arch/i386/boot/bzImage"
		fi
	fi
	if [[ -z $kernel ]] 
	then
		echo "Could not find $SRC kernel image!"
		exit 15
	fi

	# Copy the kernel config and symlink
	cp -f "$kconfig" "$DST"/boot/config-$version
	ln -sf /boot/config-$version "$DST"/boot/config

	# Copy the kernel image
	cp -f "$kernel" "$DST"/boot/linux

	# Copy all kernel modules
	[[ -d "$DST"/lib/modules ]] || mkdir -p "$DST"/lib/modules
	cp -fr "$SRC"/lib/modules/$version "$DST"/lib/modules/
}

function setup_sys() {
	local SPOOL="$TARGET/tmp"
	local SORCERY="sorcery-stable.tar.bz2"
	local SORCERYDIR="$TARGET/usr/src/sorcery"

	local gvers=$(head -n1 "$TARGET"/var/lib/sorcery/codex/stable/VERSION)
	local stable="stable-${gvers%-*}.tar.bz2"
	local syscodex="$SYSDIR/var/lib/sorcery/codex"
	local grimoire='GRIMOIRE_DIR[0]=/var/lib/sorcery/codex/stable'
	local index="$SYSDIR/etc/sorcery/local/grimoire"

	local tablet="$SYSDIR/var/state/sorcery/tablet"
	local packages="$SYSDIR/var/state/sorcery/packages"
	local depends="$SYSDIR/var/state/sorcery/depends"

	# unpack the sys caches into SYSDIR
	for cache in $(<"$TARGET"/sys-list)
	do
		tar xjf "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 -C "$SYSDIR"/
	done

	# download sorcery source
	(
		cd "$SPOOL"
		wget http://download.sourcemage.org/sorcery/$SORCERY
	)

	# unpack and install sorcery into SYSDIR
	tar jxf "$SPOOL"/$SORCERY -C "$TARGET/usr/src"
	pushd "$SORCERYDIR" &> /dev/null
	./install "$SYSDIR"
	popd &> /dev/null

	# install the stable grimoire used for build into SYSDIR
	(
		cd "$SPOOL"
		wget http://download.sourcemage.org/codex/$stable
	)
	echo "Installing grimoire ${stable%.tar.bz2} ..."
	[[ -d "$syscodex" ]] || mkdir -p $syscodex &&
	tar jxf "$SPOOL"/$stable -C "$syscodex"/ &&
	mv "$syscodex"/${stable%.tar.bz2} "$syscodex"/stable
	echo "$grimoire" > "$index"
	"$MYDIR"/cauldronchr.sh -d "$SYSDIR" /usr/sbin/scribe reindex

	# generate the depends and packages info for sorcery to use
	rm -f "$depends" "$packages"
	. "$SYSDIR"/etc/sorcery/config
	for spell in "$tablet"/*
	do
		for date in "$spell"/*
		do
			tablet_get_version $date ver
			tablet_get_status $date stat
			tablet_get_depends $date dep
			echo "${spell##*/}:${date##*/}:$stat:$ver" >> "$packages"
			cat "$dep" >> "$depends"
		done
	done
	sort -u -o "$depends" "$depends"
	sort -u -o "$packages" "$packages"

	# populate /dev with static device nodes
	cat > "$SYSDIR/makedev" <<-"DEV"
		#!/bin/bash
		cd /dev
		/sbin/MAKEDEV generic
DEV
	chmod a+x "$SYSDIR/makedev"
	chroot "$SYSDIR" /makedev
	rm -f "$SYSDIR/makedev"

	# ensure the existence of /dev/initctl
	chroot "$SYSDIR" mkfifo -m 0600 /dev/initctl
}

function setup_iso() {
	local GVERS="$TARGET/var/lib/sorcery/stable/VERSION"

	# copy the iso caches over and unpack their contents
	for cache in $(<"$TARGET"/iso-list)
	do
		tar xjf "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 -C "$ISODIR"/
		cp "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 "$ISODIR"/var/cache/sorcery/
	done

	# copy (only!) the optional caches over
	for cache in $(<"$TARGET"/opt-list)
	do
		cp "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 "$ISODIR"/var/cache/sorcery/
	done

	# install the kernel into ISODIR
	install_kernel "$TARGET" "$ISODIR"

	# save the grimoire version used for building everything to ISODIR for reference
	cp -f $GVERS "$ISODIR"/etc/grimoire_version

	# populate /dev with static device nodes
	cat > "$ISODIR/makedev" <<-"DEV"
		#!/bin/bash
		cd /dev
		/sbin/MAKEDEV generic
DEV
	chmod a+x "$ISODIR/makedev"
	chroot "$ISODIR" /makedev
	rm -f "$ISODIR/makedev"

	# ensure the existence of /dev/initctl
	chroot "$ISODIR" mkfifo -m 0600 /dev/initctl
}

function clean_target() {
	# Restore resolv.conf, the first rm is needed in case something
	# installs a hardlink (like ppp)
	rm -f "$TARGET/etc/resolv.conf" &&
	cp -f "$TARGET/tmp/resolv.conf" "$TARGET/etc/resolv.conf" &&
	rm -f "$TARGET/tmp/resolv.conf"

	# Clean up the target
	rm -f "$TARGET/build_spells.sh"
}

# main()
priv_check $*

parse_options $*
shift $?

[[ $# -lt 1 ]] && usage
TARGET="${1%/}"
shift

[[ $# -gt 0 ]] && TYPE="$1"
TYPE="${TYPE:-x86}"

ISODIR="${ISODIR:-/tmp/cauldron/iso}"
SYSDIR="${SYSDIR:-/tmp/cauldron/sys}"

# ensure full pathnames
if [[ $(dirname "$ISODIR") == "." ]]
then
	ISODIR="$(pwd)/$ISODIR"
fi
if [[ $(dirname "$SYSDIR") == "." ]]
then
	SYSDIR="$(pwd)/$SYSDIR"
fi

sanity_check

prepare_target

# chroot and build all of the spells inside the TARGET
"$MYDIR/cauldronchr.sh" -d "$TARGET" /build_spells.sh

# unpack sys caches and set up sorcery into SYSDIR
setup_sys
touch "$SYSDIR"/etc/ld.so.conf
"$MYDIR/cauldronchr.sh" -d "$SYSDIR" /sbin/ldconfig

# unpack iso caches and copy iso and optional caches into ISODIR
setup_iso
touch "$SYSDIR"/etc/ld.so.conf
"$MYDIR/cauldronchr.sh" -d "$ISODIR" /sbin/ldconfig

# Keep a clean kitchen, wipes up the leftovers from the preparation step
clean_target
