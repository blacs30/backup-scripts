#!/usr/bin/env sh
# create a cron enry to call this script every x minutes / hours
# 30/* * * * * /root/backup/mount_sshfs.sh

check_cmd="$(mount | grep -c webbackup)"
LOG="/root/mount_sshfs.log"
HOST=$(hostname)
MAIL_RECIPIENT=admin@example.com

##
## Write output to logfile
##

if [ "$check_cmd" -ne "1" ]; then
   if sshfs webbackup@example.com:/mnt/data/webbackup /root/webbackup 2>/dev/null; then
        echo "webbackup successfully mounted again at $(date)." | tee $LOG
    else
        echo "webbackup not available, sending mail to admin." | tee $LOG
        mailx -a "From: \"$HOST\" <\"$HOST\">" -s "Mounting webbackup | ""$HOST" $MAIL_RECIPIENT < $LOG
    fi
fi

