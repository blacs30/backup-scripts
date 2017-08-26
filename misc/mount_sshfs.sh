#!/usr/bin/env sh
# create a cron enry to call this script every x minutes / hours
# 30/* * * * * /root/backup/mount_sshfs.sh

# set -x

check_cmd="$(mount | grep -c webbackup)"
LOG="/root/mount_sshfs.log"
HOST=$(hostname)
MAIL_RECIPIENT=admin@example.com
MOUNT_URL='sshfs webbackup@example.com:/mnt/data/webbackup'
MOUNT_PATH=/root/webbackup

##
## Write output to logfile
##

mount() {
    if  ${MOUNT_URL} ${MOUNT_PATH} 2>/dev/null; then

        echo "webbackup successfully mounted again at $(date)." | tee $LOG
        return 0
    else

        echo "webbackup not available, sending mail to admin." | tee $LOG
        mailx -a "From: \"$HOST\" <\"$HOST\">" -s "Mounting webbackup | ""$HOST" $MAIL_RECIPIENT < $LOG
        exit 1
    fi
}

unmount() {
    if ! umount ${MOUNT_PATH} 2>/dev/null; then

        echo "webbackup could not be unmount at $(date)." | tee $LOG
        return 1
    fi
}

checkmount() {
     if ! ls ${MOUNT_PATH}  > /dev/null 2>&1; then

           echo "ERROR while reading from mounted drive at $(date)." | tee $LOG
           echo "Trying to remount at $(date)." | tee $LOG
           unmount
           mount
        fi
}

if [ "$check_cmd" -ne "1" ]; then

  mount
  checkmount
else

    checkmount
fi
