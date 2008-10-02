#/bin/bash

# CLEANFILEs are located in cauldron/data/cleaners

if [[ $# -lt 2  ]]
then
	echo ""
	echo "Usage: $0 iso_chroot cleaner(s)"
	echo ""
	echo "For each cleaner specified as an argument, cleans the"
	echo "files and directories listed therein from iso_chroot."
	echo "A cleaner is the ouput of 'gaze install \$SPELL' minus"
	echo "whatever you don't want removed."
	echo ""
	exit 1
fi >&2

# location of ISO chroot to clean from
ISOCHROOT="$1"
shift

for CLEANER in "$@"
do
	# Reverse sort ensures that the gaze install output we have lists files
	# before directories, so that directories can be cleaned using rmdir
	# after the files are cleaned first. This is safer, since it avoids the
	# mighty 'rm -fr' oopses.
	for i in $(sort -r "$CLEANFILE")
	do
		# test if current listing is a dir, should only be true after
		# the files under the dir are already cleaned
		if [[ -d "$i" ]]
		then
			# chroot and clean a directory using rmdir
			echo "Attempting to remove directory $i..."
			chroot "$ISOCHROOT" rmdir "$i"
		else
			# chroot and clean an individual file
			echo "Deleting $i"
			chroot "$ISOCHROOT" rm "$i"
		fi
	done
done
