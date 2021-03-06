#!/bin/bash
#
# Usage: cauldronchr.sh [-d /path/to/chroot] [CHROOT_CMD]
# assumes $CWD as chroot path and /bin/bash -l as CHROOT_CMD
# if not specified

CHROOT_DIR=
CHROOT_CMD=

function usage() {
	cat << EndUsage
Usage: $(basename $0) [-h] [-d /path/to/target] [CHROOT_CMD]
Chroots to target with mounts taken care of (proc, dev, etc.).
This script requires superuser privileges.

Options:
	-d /path/to/target
	    The target directory you would like to chroot to. Defaults to
	    current working directory.

	-h  Shows this help information

	CHROOT_CMD
	    Any arbitrary command you wish to run inside the chroot. Note that
	    you must specify an absolute path or the command will not likely be
	    found (a way around this would be to either set the path as part of
	    the command to execute, or to set the command to be /bin/bash -l
	    some_command_without_abs_path). Defaults to "/bin/bash".
EndUsage
	exit 1
} >&2

# dir to chroot to is either $1 or $CWD
while getopts ":d:h" Option
do
	case $Option in
		d ) CHROOT_DIR="$OPTARG" ;;
		h ) usage ;;
		* ) echo "Unrecognized option." >&2 && usage ;;
	esac
done
shift $(($OPTIND - 1))

SELF=$0

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

CHROOT_DIR="${CHROOT_DIR:-.}"
[[ $# -gt 0 ]] && CHROOT_CMD="$@"
CHROOT_CMD="${CHROOT_CMD:-/bin/bash}"
# If it's devtmpfs we need to do something differently. bind mounting seems to cause problems
if [[ "$(grep devtmpfs /proc/filesystems)" == "" ]]; then
	mount --bind /dev "$CHROOT_DIR"/dev &&
	mount --bind /dev/pts "$CHROOT_DIR"/dev/pts
else
	mount -t devtmpfs none "$CHROOT_DIR"/dev &&
	mount -t devpts none "$CHROOT_DIR"/dev/pts
fi &&
mount --bind /proc "$CHROOT_DIR"/proc &&

export CAULDRON_CHROOT="$CHROOT_DIR"
export PS1="[chroot]\u \w$ "

chroot "$CHROOT_DIR" $CHROOT_CMD

unset CAULDRON_CHROOT

umount "$CHROOT_DIR"/proc
umount "$CHROOT_DIR"/dev/pts
umount "$CHROOT_DIR"/dev
