#!/bin/sh
export BACKUPDIR=/mnt/backupspace/backups/config

if [ -f $BACKUPDIR/installed_packages.log ]
  then
    mv $BACKUPDIR/installed_packages.log $BACKUPDIR/installed_packages.log_"$(date +%F-%T)"
fi

dpkg --get-selections | grep -v deinstall >> $BACKUPDIR/installed_packages.log
