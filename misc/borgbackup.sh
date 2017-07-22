#!/bin/bash

#  Further infos here:
#  http://borgbackup.readthedocs.io/en/stable/quickstart.html
#  Infos for installation of borg:
#  https://www.thetutorial.de/?p=2012
#
# base script from here:
# https://thomas-leister.de/server-backups-mit-borg/
#
# quick start with most helpfull commands
# http://borgbackup.readthedocs.io/en/stable/quickstart.html


# use sshfs to mount the remote share
# restrict the usage on the remote server
# with these settings in the authorized_key file:
# no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty


# add this backup as a cronjob
# crontab -e
# @daily /root/backup/borgbackup.sh

BORG_PASSPHRASE=$(cat /root/webbackup/.borgpw)
export BORG_PASSPHRASE
LOG="/root/backup.log"
HOST=$(hostname)
REPOSITORY=/root/webbackup/${HOST}/backup
MAIL_RECIPIENT=admin@example.com
# mailing only for errors
MAILING=0
ERRORS=0

##
## Write output to logfile
##

exec > >(tee -i ${LOG})
exec 2>&1

echo "###### Starting backup on $(date) ######"


##
## Increase the error counter if an error is found
##
add_error(){
ERRORS=$((ERRORS + 1))
echo "Increased ERRORS"
echo "Current ERRORS: $ERRORS"
}


##
## Create list of installed software
##

dpkg --get-selections > /root/backup/software.list


##
## Create database dumps
##


echo "Creating database dumps ..."
if ! /bin/bash /root/backup/dbdump.sh ;
    then
            add_error
fi

##
## adjust the backup location in the gitlab.rb configuration
## run "gitlab-ctl reconfigure" after changes

echo "Creating gitlab db dump ..."
if ! /opt/gitlab/bin/gitlab-rake gitlab:backup:create ;
    then
            add_error
fi

##
## Sync backup data
##

echo "Syncing backup files ..."
# Backup all of /home and /var/www except a few
# excluded directories
if ! borg create -v --stats --compression lzma,5     \
    "$REPOSITORY"::'{now:%Y-%m-%d}'               \
    /root/backup                                \
    /var/opt/gitlab/backups                     \
    /etc                                        \
    /var/vmail                                  \
    /var/www                                    \
    /var/scripts                                \
    /usr/share/GeoIP ;
    then
            add_error
    else
            echo "###### Finished backup on $(date) ######"
fi




# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machine's archives also.
echo "Removing old backups ..."
if ! borg prune -v --list "$REPOSITORY" --prefix '{hostname}-' \
    --keep-daily=7 --keep-weekly=4 --keep-monthly=6 ;
    then
    add_error
else
    echo "###### Finished removing old backups on $(date) ######"
fi



##
## Send mail to admin
##

if [ !  "$MAILING" = "0" ] && [ ! "$ERRORS" = "0" ]; then
    mailx -a "From: \"$HOST\" Backup <\"$HOST\">" -s "Backup ERROR | ""$HOST" $MAIL_RECIPIENT < $LOG
fi
