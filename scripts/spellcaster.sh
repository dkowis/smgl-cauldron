#!/bin/bash

# this script handles automatically casting all required spells into the ISO
# chroot, and also the casting and subsequent dispelling (with caches enabled)
# of the optional spells.

MYDIR="$(dirname $0)"
CAULDRONDIR="$MYDIR"/../data

function usage() {
  cat << EndUsage
Usage: $(basename $0) [-hbcnq] [-i ISO] [-s SYS] /path/to/target ARCHITECTURE

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
	-b  Build only (don't generate the ISO and SYS trees). Ignores the -i
	    and -s flags. Conflicts with -n.

	-c  Generate a basesystem chroot (causes -i to be ignored, only SYS is
	    used).

	-h  Shows this help information

	-i  Path to iso build directory (ISO). Defaults to /tmp/cauldron/iso.

	-s  Path to system build directory (SYS). Defaults to
	    /tmp/cauldron/system.

	-n  Don't process the build tree. Instead, generate target trees using
	    an already existing build tree. This is useful if you already have
	    all the caches, but you need to regenerate your ISO and SYS trees
	    (or a basesystem chroot tree) if something went wrong during later
	    processing. Conflicts with -b.

	-q  Suppress output messages. Defaults to off (output shown on STDERR).

	-v  Enable VOYEUR in the build sorcery. By default build compilation is
	    silent (VOYEUR=off). This option allows you to see the compilations
	    as they happen in the build chroot.
EndUsage
  exit 1
} >&2

function parse_options() {
	while getopts ":bci:s:nqvh" Option
	do
		case $Option in
			b ) BUILDONLY="yes" ;;
			c ) CHROOT="yes" ;;
			i ) ISODIR="${OPTARG%/}" ;;
			s ) SYSDIR="${OPTARG%/}" ;;
			n ) NOBUILD="yes" ;;
			q ) QUIET="yes" ;;
			v ) VOYEUR="yes" ;;
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

function msg() {
	if [[ -z $QUIET ]]
	then
		echo $1 >&2
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
	local choice=

	# Ensure that TARGET is a directory
	[[ -d "$TARGET" ]] || {
		echo "$TARGET does not exist!"
		exit 3
	}

	if [[ -z $NOBUILD ]]
	then
		# nuke the TARGET /etc and install a clean /etc
		rm -fr "$TARGET"/etc/*
		"$MYDIR"/add-sauce.sh -o -s "$TARGET"

		if [[ -z $CHROOT ]]
		then
			# make sure that either the linux spell is being used or that the
			# kernel sources are available for building
			if ! grep -q '^linux$' "$CAULDRONDIR/rspells.$TYPE"
			then
				if [[ -d "$TARGET"/usr/src/linux ]]
				then
					if [[ ! -s "$TARGET"/usr/src/linux ]]
					then
						echo "Couldn't find "$TARGET" kernel config!"
						exit 2
					fi
				else
					echo "Cannot find the $TARGET kernel!"
					echo "Either place the kernel sources and kernel config in $TARGET"
					echo "or add the linux spell to the list of rspells."
					exit 2
				fi
			fi
		fi

	fi

	if [[ -z $BUILDONLY ]]
	then
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
	fi
}

function prepare_target() {
	export rspells="rspells.$TYPE"
	export ispells="ispells.$TYPE"
	export ospells="ospells.$TYPE"
	local SPOOL="$TARGET/tmp"
	local SORCERY="sorcery-stable.tar.bz2"
	local SORCERYDIR="$TARGET/usr/src/sorcery"
	local LOGS="$TARGET/var/log/sorcery"

	# make sure the TARGET has a clean /tmp
	rm -fr "$TARGET"/tmp/*

	# download sorcery source if we don't already have it
	if [[ ! -f "$SPOOL"/$SORCERY ]]
	then
		(
			cd "$SPOOL"
			wget http://download.sourcemage.org/sorcery/$SORCERY
		)
	fi

	# unpack sorcery into TARGET
	msg "Installing sorcery in build directory..."
	tar jxf "$SPOOL"/$SORCERY -C "$TARGET/usr/src"

	# ensure absolute path for install dir
	local installdir="$TARGET"
	[[ $installdir != /* ]] && installdir="$PWD/$TARGET"

	# install sorcery into TARGET
	pushd "$SORCERYDIR" &> /dev/null
	./install "$installdir"
	popd &> /dev/null

	# set up the build sorcery for the correct values
	# this includes arch, archive=on, preserve=off, and setting the prompt
	# delay to 0 so that there is no prompting (automated build)
	case $TYPE in
		"x86"	) arch="i486"
			;;
		"x86_64") arch="x86_64"
			;;
		"ppc"	) arch="g3"
			;;
	esac

	cat > "$TARGET"/set_sorcery.sh <<-CONFIGURE
		#!/bin/bash
		source /etc/sorcery/config
		modify_config /etc/sorcery/local/config ARCHITECTURE $arch
		modify_config /etc/sorcery/local/config ARCHIVE on
		modify_config /etc/sorcery/local/config PRESERVE off
		modify_config /etc/sorcery/local/config PROMPT_DELAY 0
    #I want more compiles
    modify_config /etc/sorcery/local/compile_config MAKE_NJOBS 7
	CONFIGURE

	# silent compiles by default
	# but if -v passed as option then turn VOYEUR on
	if [[ $VOYEUR != "yes" ]]
	then
		echo "modify_config /etc/sorcery/local/config VOYEUR off" >> "$TARGET"/set_sorcery.sh
	else
		echo "modify_config /etc/sorcery/local/config VOYEUR on" >> "$TARGET"/set_sorcery.sh
	fi

	chmod a+x "$TARGET"/set_sorcery.sh &&
	msg "Configuring build sorcery"
	"$MYDIR"/cauldronchr.sh -d "$TARGET" /set_sorcery.sh &&
	rm -f "$TARGET"/set_sorcery.sh

	# Copy resolv.conf so spell sources can be downloaded inside the TARGET
	cp -f "$TARGET"/etc/resolv.conf "$TARGET"/tmp/resolv.conf &&
		cp -f /etc/resolv.conf "$TARGET"/etc/resolv.conf

	# clean out any old sorcery logs in TARGET
	for logfile in "$LOGS"/activity "$LOGS"/queue/install
	do
		rm -f $logfile
	done

	# nuke any existing sorcery state information in the build dir
	rm -fr "$installdir/var/state/sorcery/*"

	# If building for an ISO (instead of a basesystem chroot) and using the
	# linux spell, copy the kernel config to TARGET sorcery
	if [[ -z $CHROOT ]]
	then
		grep -q '^linux$' "$CAULDRONDIR/$rspells" "$CAULDRONDIR/$ospells" &&
		cp "$CAULDRONDIR/config-2.6" "$TARGET/etc/sorcery/local/kernel.config"
	fi

	# Copy the list of spells needed for casting into the TARGET if casting
	cp "$CAULDRONDIR/rspells.$TYPE" "$TARGET"/rspells
	if [[ -z $CHROOT ]]
	then
		cp "$CAULDRONDIR/ispells.$TYPE" "$TARGET"/ispells
		cp "$CAULDRONDIR/ospells.$TYPE" "$TARGET"/ospells
	fi

	# Copy any spell-specific required options into the TARGET
	[[ -d "$TARGET"/etc/sorcery/local/depends/ ]] ||
		mkdir -p "$TARGET"/etc/sorcery/local/depends/
	cp "$CAULDRONDIR"/depends/* "$TARGET"/etc/sorcery/local/depends/
	cat "$CAULDRONDIR"/sorcery.depends > "$TARGET"/var/state/sorcery/depends

	# generate basesystem casting script inside of TARGET
	cat > "$TARGET"/build_spells.sh <<-'SPELLS'

	function msg() {
		if [[ -z $QUIET ]]
		then
			echo $1 >&2
		fi
	}

	if [[ -n $CAULDRON_CHROOT && $# -eq 0 ]]
	then

		SPOOL=/tmp
		stable="stable.tar.bz2"
		codex="/var/lib/sorcery/codex"
		grimoire='GRIMOIRE_DIR[0]=/var/lib/sorcery/codex/stable'
		index="/etc/sorcery/local/grimoire"
		
		# update to latest stable grimoire
		(
			cd "$SPOOL"
			wget http://download.sourcemage.org/codex/$stable
		)
		msg "Updating build grimoire"
		[[ -d "$codex" ]] && mv "$codex" "${codex}.old"
		mkdir -p "$codex" &&
		tar xf "$SPOOL"/$stable -C "$codex"/ &&
		[[ -d "${codex}.old" ]] && rm -fr "${codex}.old"
		echo "$grimoire" > "$index" &&
		scribe reindex

		# If console-tools is found in TARGET, get rid of it to make
		# way for kbd
		[[ $(gaze -q installed console-tools) != "not installed" ]] &&
		dispel --orphan always console-tools

		# push the needed spells into the install queue
		cat rspells ispells ospells > /var/log/sorcery/queue/install

		# cast all the spells using the install queue and save the
		# return value to a log file
		/usr/sbin/cast --compile --queue 2> /build_spells.log
		echo $? >> /build_spells.log

		# make a list of the caches to unpack for system
		for spell in $(</rspells)
		do
			gaze installed $spell &> /dev/null &&
			echo $spell-$(gaze -q installed $spell)
		done > /sys-list || exit 42
SPELLS
	if [[ -z $CHROOT ]]
	then
		# add iso and optional spells to casting script inside TARGET
		cat >> "$TARGET"/build_spells.sh <<-'SPELLS'


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
SPELLS
	fi
	# close off the basesystem casting script
	echo "fi" >> "$TARGET"/build_spells.sh

	chmod a+x "$TARGET"/build_spells.sh
	# export the QUIET variable so subshells (like build_spells) can make
	# use of it
	export QUIET
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
		kconfig=${kconfig:-"$SRC"/etc/sorcery/local/kernel.config}
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
		local kmodules="$SRC/lib/modules"
		kmodules="$(find "$kmodules" -mindepth 1 -maxdepth 1 -type d)"
		kmodules="$(echo "$kmodules" | sed 's#.*/##')"

		if [[ -n $kmodules && $(echo "$kmodules" | wc -l) -eq 1 ]]
		then
			version="$kmodules"
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
		else
			# Getting kernel architecture from ISO architecture
			. $CAULDRONDIR/kernel_archs
			kernel_arch=karch_$TYPE

			if [[ -e "$SRC"/usr/src/linux/arch/"${!kernel_arch:-${TYPE}}"/boot/bzImage ]]
			then
				kernel="$SRC/usr/src/linux/arch/${!kernel_arch:-${TYPE}}/boot/bzImage"
			fi
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

	# unpack the sys caches into SYSDIR
	msg "Installing caches into SYSDIR"
	for cache in $(<"$TARGET"/sys-list)
	do
		msg ".. unpacking $cache"
		tar xjf "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 -C "$SYSDIR"/
	done

	# perform smgl-fhs hack on SYSDIR
	msg "Performing smgl-fhs hack on SYSDIR"
	"$MYDIR"/fhs-hack.sh "$SYSDIR"

	# add the necessary and basic files to SYSDIR
	msg "Running add-sauce.sh on SYSDIR"
	"$MYDIR"/add-sauce.sh -o -s "$SYSDIR"

	# download sorcery source if we don't already have it
	if [[ ! -f "$SPOOL"/$SORCERY ]]
	then
		(
			cd "$SPOOL"
			wget http://download.sourcemage.org/sorcery/$SORCERY
		)
	fi

	# unpack sorcery into TARGET
	msg "Installing sorcery in SYSDIR"
	tar jxf "$SPOOL"/$SORCERY -C "$TARGET/usr/src"

	# ensure absolute path for install dir
	local installdir="$SYSDIR"
	[[ $installdir != /* ]] && installdir="$PWD/$SYSDIR"

	# install sorcery into SYSDIR
	pushd "$SORCERYDIR" &> /dev/null
	./install "$installdir"
	popd &> /dev/null

	# download grimoire source if we don't already have it
	if [[ ! -f "$SPOOL"/$stable ]]
	then
		(
			cd "$SPOOL"
			wget http://download.sourcemage.org/codex/$stable
		)
	fi

	# install the stable grimoire used for build into SYSDIR
	msg "Installing grimoire ${stable%.tar.bz2} into SYSDIR"
	[[ -d "$syscodex" ]] && rm -fr "$syscodex"
	mkdir -p $syscodex &&
	tar xf "$SPOOL"/$stable -C "$syscodex"/ &&
	mv "$syscodex"/${stable%.tar.bz2} "$syscodex"/stable &&
	echo "$grimoire" > "$index" &&

	msg "Reindexing SYSDIR codex"
	"$MYDIR"/cauldronchr.sh -d "$SYSDIR" /usr/sbin/scribe reindex

	# generate the depends and packages info for sorcery to use
	cat > "$SYSDIR"/tablets.sh <<-"TABLETS"
		#!/bin/bash
		tablet="/var/state/sorcery/tablet"
		packages="/var/state/sorcery/packages"
		depends="/var/state/sorcery/depends"

		rm -f "$depends" "$packages"
		. /etc/sorcery/config &&
		for spell in "$tablet"/*
		do
			for date in "$spell"/*
			do
				tablet_get_version "$date" ver &&
				tablet_get_status "$date" stat &&
				echo "${spell##*/}:${date##*/}:$stat:$ver" >> "$packages"
				tablet_get_depends "$date" dep &&
				[[ -f "$dep" ]] && cat "$dep" >> "$depends"
			done
		done &&
		sort -u -o "$depends" "$depends" &&
		sort -u -o "$packages" "$packages"
	TABLETS

	msg "Generating SYSDIR tablet info"
	chmod a+x "$SYSDIR"/tablets.sh &&
	"$MYDIR"/cauldronchr.sh -d "$SYSDIR" /tablets.sh &&
	rm -f "$SYSDIR"/tablets.sh

	# populate /dev with static device nodes
	cat > "$SYSDIR/makedev" <<-"DEV"
		#!/bin/bash
		cd /dev
		/sbin/MAKEDEV generic
	DEV

	msg "Making static device nodes in SYSDIR"
	chmod a+x "$SYSDIR/makedev"
	chroot "$SYSDIR" /makedev
	rm -f "$SYSDIR/makedev"

	# ensure the existence of /dev/initctl
	msg "Ensuring /dev/initctl exists in SYSDIR"
	chroot "$SYSDIR" mkfifo -m 0600 /dev/initctl
}

function setup_iso() {
	local GVERS="$TARGET/var/lib/sorcery/codex/stable/VERSION"

	# copy the iso caches over and unpack their contents
	msg "Unpacking ISO caches in ISODIR"
	for cache in $(<"$TARGET"/iso-list)
	do
		msg ".. unpacking and copying $cache"
		tar xjf "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 -C "$ISODIR"/
		cp "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 "$ISODIR"/var/cache/sorcery/
	done

	# copy (only!) the optional caches over
	msg "Copying optional caches to ISODIR"
	for cache in $(<"$TARGET"/opt-list)
	do
		msg ".. copying $cache"
		cp "$TARGET"/var/cache/sorcery/$cache*.tar.bz2 "$ISODIR"/var/cache/sorcery/
	done

	# perform smgl-fhs hack on ISODIR
	msg "Performing smgl-fhs hack on ISODIR"
	"$MYDIR"/fhs-hack.sh "$ISODIR"

	# install the kernel into ISODIR
	msg "Installing kernel into ISODIR"
	install_kernel "$TARGET" "$ISODIR"

	# add the necessary and basic files to ISODIR
	msg "Running add-sauce.sh on ISODIR"
	"$MYDIR"/add-sauce.sh -o -i "$ISODIR"

	# add the rspells list to the ISO for later reference
	cp -f "$CAULDRONDIR/rspells.$TYPE" "$ISODIR"/usr/share/smgl.install/rspells

	# save the grimoire version used for building everything to ISODIR for reference
	msg "Saving grimoire version to ISODIR"
	cp -f $GVERS "$ISODIR"/etc/grimoire_version

	# populate /dev with static device nodes
	cat > "$ISODIR/makedev" <<-"DEV"
		#!/bin/bash
		cd /dev
		/sbin/MAKEDEV generic
	DEV

	msg "Generating static device nodes in ISODIR"
	chmod a+x "$ISODIR/makedev"
	chroot "$ISODIR" /makedev
	rm -f "$ISODIR/makedev"

	# ensure the existence of /dev/initctl
	msg "Ensuring /dev/initctl exists in ISODIR"
	chroot "$ISODIR" mkfifo -m 0600 /dev/initctl
}

function clean_target() {
	# Restore resolv.conf, the first rm is needed in case something
	# installs a hardlink (like ppp)
	if [[ -f "$TARGET/tmp/resolv.conf" ]]
	then
		# rm the real resolv.conf first, needed because ppp makes a symlink
		rm -f "$TARGET/etc/resolv.conf"
		cp -f "$TARGET/tmp/resolv.conf" "$TARGET/etc/resolv.conf" &&
		rm -f "$TARGET/tmp/resolv.conf"
	fi

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

[[ -z $NOBUILD ]] && prepare_target

# chroot and build all of the spells inside the TARGET
[[ -z $NOBUILD ]] && "$MYDIR/cauldronchr.sh" -d "$TARGET" /build_spells.sh

if [[ -z $BUILDONLY ]]
then
	# unpack sys caches and set up sorcery into SYSDIR
	setup_sys
	touch "$SYSDIR"/etc/ld.so.conf
	"$MYDIR/cauldronchr.sh" -d "$SYSDIR" /sbin/ldconfig

	if [[ -z $CHROOT ]]
	then
		# unpack iso caches and copy iso and optional caches into ISODIR
		setup_iso
		touch "$SYSDIR"/etc/ld.so.conf
		"$MYDIR/cauldronchr.sh" -d "$ISODIR" /sbin/ldconfig
	fi
fi

# Keep a clean kitchen, wipes up the leftovers from the preparation step
[[ -z $NOBUILD ]] && clean_target
