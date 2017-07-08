#!/bin/bash

#  Further infos here:
#  http://borgbackup.readthedocs.io/en/stable/quickstart.html
#  Infos for installation of borg:
#  https://www.thetutorial.de/?p=2012
#
# base script from here:
# https://thomas-leister.de/server-backups-mit-borg/

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

##
## Write output to logfile
##

exec > >(tee -i ${LOG})
exec 2>&1

echo "###### Starting backup on $(date) ######"


##
## Create list of installed software
##

dpkg --get-selections > /root/backup/software.list


##
## Create database dumps
##

echo "Creating database dumps ..."
/bin/bash /root/backup/dbdump.sh

##
## adjust the backup location in the gitlab.rb configuration
## run "gitlab-ctl reconfigure" after changes

echo "Creating gitlab db dump ..."
/opt/gitlab/bin/gitlab-rake gitlab:backup:create

##
## Sync backup data
##

echo "Syncing backup files ..."
# Backup all of /home and /var/www except a few
# excluded directories
borg create -v --stats --compression lzma,5     \
    "$REPOSITORY"::'{now:%Y-%m-%d}'               \
    /root/backup                                \
    /var/opt/gitlab/backups                     \
    /etc                                        \
    /var/vmail                                  \
    /var/www                                    \
    /var/scripts                                \
    /usr/share/GeoIP

echo "###### Finished backup on $(date) ######"


# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machine's archives also.
echo "Removing old backups ..."
borg prune -v --list "$REPOSITORY" --prefix '{hostname}-' \
    --keep-daily=7 --keep-weekly=4 --keep-monthly=6

echo "###### Finished removing old backups on $(date) ######"

##
## Send mail to admin
##

mailx -a "From: \"$HOST\" Backup <\"$HOST\">" -s "Backup | ""$HOST" $MAIL_RECIPIENT < $LOG
