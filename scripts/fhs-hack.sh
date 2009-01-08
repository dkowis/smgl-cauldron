#!/bin/bash
#
# WARNING: THIS FILE IS A HACKED VERSION OF THE smgl-fhs INSTALL SCRIPT!
# this file should not be used once smgl-fhs can properly install all the
# necessary directories via sorcery
#

INSTALL_ROOT="${INSTALL_ROOT:-$1}"
INSTALL_ROOT="${INSTALL_ROOT%/}"

if [[ -z $INSTALL_ROOT ]]
then
  echo "No INSTALL_ROOT defined! You must pass an argument!"
  exit 2
fi

root="0"
games="60"
mail="8"
utmp="43"

function  fhs_mkdir()
{
  install  -d  -o ${3:-root}  -g ${4:-root}  -m ${2:-0755}  "$INSTALL_ROOT"/$1
}

#
# http://www.pathname.com/fhs/2.2/fhs-3.html
#
for  root_directory  in  bin  etc  boot  dev  home  lib  mnt  opt  sbin  \
                         usr  var
do
  fhs_mkdir  $root_directory
done  &&

fhs_mkdir tmp 1777  &&

#
# http://www.pathname.com/fhs/2.2/fhs-6.1.html
# in the linux specific section, /proc is indeed mentioned
#
fhs_mkdir proc &&

#
# http://www.pathname.com/fhs/2.2/fhs-3.7.html
#
for  etc_directory  in  opt  X11  sgml
do
  fhs_mkdir  etc/$etc_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-3.9.html
#
for  lib_directory  in  modules
do
  fhs_mkdir  lib/$lib_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-4.html
#
for  usr_directory  in  X11R6  bin  include  lib  local  sbin  share  src
do
  fhs_mkdir  usr/$usr_directory
done  &&

#
# For games
#
#create_group  games  &&
fhs_mkdir  usr/games  0750  $root  $games  &&

#
# http://www.pathname.com/fhs/2.2/fhs-4.6.html
#
for  include_directory  in  bsd
do
  fhs_mkdir  usr/include/$include_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-4.9.html
#
for  local_directory  in  bin  games  include  lib  man  sbin  share  src
do
  fhs_mkdir  usr/local/$local_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-4.11.html
#
for  share_directory  in  dict  doc  games  info  locale  man  misc  nls  \
                          sgml  terminfo  tmac  zoneinfo
do
  fhs_mkdir  usr/share/$share_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-4.11.html (4.11.5.2)
#
for  man_directory in 1 2 3 4 5 6 7 8
do
  fhs_mkdir  usr/share/man/man$man_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-4.4.html
#
for  X11_subdir in lib include
do
  fhs_mkdir  usr/X11R6/$X11_subdir
done  &&

for  X11_directory  in  bin  lib/X11  include/X11
do
  fhs_mkdir  usr/$X11_directory &&
  ln  -sf  /usr/$X11_directory \
           "$INSTALL_ROOT"/usr/X11R6/$X11_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-5.html
#
for  var_directory  in  account  cache  crash  games  lib  lock  log  \
                        opt  run  spool  yp
do
  fhs_mkdir  var/$var_directory
done  &&

#
# This is the permission set I have on mine
#
fhs_mkdir var/tmp  1777  &&

#
# http://www.pathname.com/fhs/2.2/fhs-5.5.html
#
for  cache_directory  in  fonts  man  www
do
  fhs_mkdir  var/cache/$cache_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-5.14.html
#
for  spool_directory  in  lpd  mqueue  news  rwho  uucp
do
  fhs_mkdir  var/spool/$spool_directory
done  &&

#create_group mail &&
fhs_mkdir  var/spool/mail  3775 $root $mail &&

#
# http://www.pathname.com/fhs/2.2/fhs-5.11.html
#
if  [ ! -e "$INSTALL_ROOT"/var/mail ]
then
  ln  -sf  spool/mail         \
           "$INSTALL_ROOT"/var/mail
fi &&

#
# http://www.pathname.com/fhs/2.2/fhs-5.8.html
#
for  varlib_directory  in  hwclock  misc  xdm
do
  fhs_mkdir  var/lib/$varlib_directory
done  &&

#
# http://www.pathname.com/fhs/2.2/fhs-3.13.html
#
# Doesn't mention permissions, but usually you don't want other users
# able to access a different users folders, so why would root be different?
#
fhs_mkdir  root  0750

for  file  in  "$INSTALL_ROOT"/var/run/utmp  "$INSTALL_ROOT"/var/log/wtmp
do
  if  test  !  -e  $file; then
    touch  $file
  fi  &&
  chmod  664   $file  &&
  chgrp  $utmp  $file
done
