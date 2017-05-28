#!/bin/sh

if (test "$(whoami)" != "root"); then

        echo "You need to be root to start this"
        exit 1
fi

ACT_DATE=$(date '+%y-%m-%d')
ACT_TIME=$(date '+%H:%M')
EXP_DATE=$(date -v -2w '+%y-%m-%d')
ARCHIVE_PATH="/Backups/opendirectory"
ARCHIVE_NAME="OpenDirectory_Day_"
ARCHIVE_PASSWORD="123456"
MAIL_RECPT=admin@example.com,admin2@example.com
LOGFILE="$ARCHIVE_PATH/_opendirectory_archive-$ACT_DATE.log"
FAIL_MESSAGE="**** FAIL **** Opendirectory archive on $(hostname)!"
SUCCESS_MESSAGE="**** SUCCESS **** Opendirectory archive on $(hostname)!"

if [ ! -d "$ARCHIVE_PATH" ]; then

	mkdir -p "$ARCHIVE_PATH"
	echo "Creating archive_path $ARCHIVE_PATH" >> "$LOGFILE"
fi


CREATE_ARCHIVE() {

	echo " " >>"$LOGFILE"
	echo " " >>"$LOGFILE"
	echo "***** Archive_BACKUP $ACT_DATE *****" >>"$LOGFILE"
	echo "Settings are:" >>"$LOGFILE"
	echo "* ARCHIVE_PATH: $ARCHIVE_PATH" >>"$LOGFILE"
	echo "* MAIL RECEIPT: $MAIL_RECPT" >>"$LOGFILE"
	echo "* Test connection: " >>"$LOGFILE"

	if ! /usr/libexec/slapd -Tt >> "$LOGFILE" 2>&1; then

		sendMail "The Opendirectory archive couldn't be created, check the log message." "$MAIL_RECPT" "$LOGFILE"
		exit 1
	fi

	#if  $EXPECT_FILE "$ARCHIVE_PATH" "$ARCHIVE_PASSWORD" >> "$LOGFILE" 2>&1; then

	RUN_EXPECT=$(expect -c "
	set timeout 300
	spawn /usr/sbin/slapconfig -backupdb \"${ARCHIVE_PATH}/${ARCHIVE_NAME}${ACT_DATE}_${ACT_TIME}\"
	expect \"Enter archive password\"
	send \"$ARCHIVE_PASSWORD\r\"
	expect eof
	")
	export RUN_EXPECT
	echo "$RUN_EXPECT" >> "$LOGFILE" 2>&1

	if [ "$?" = "0" ]; then

      for file in ${ARCHIVE_PATH}/${ARCHIVE_NAME}${EXP_DATE}*.sparseimage; do

			if [ -e "$file" ]; then

				echo "$(date '+%c') -- deleting old backup" >> "$LOGFILE"
				echo "*** $(ls -l ${ARCHIVE_PATH}/${ARCHIVE_NAME}"${EXP_DATE}"*.sparseimage)" >> "$LOGFILE"
				rm ${ARCHIVE_PATH}/${ARCHIVE_NAME}${EXP_DATE}*.sparseimage
			fi
		done


		echo "*** $(date '+%c') -- Finished" >> "$LOGFILE"
		# Uncomment the line below if you want to use emailing and adjust the settings
		# echo "$SUCCESS_MESSAGE" | python /Library/Scripts/mailing.py $MAIL_RECPT "$SUCCESS_MESSAGE" "$LOGFILE"
		sendMail "$SUCCESS_MESSAGE" "$MAIL_RECPT" "$LOGFILE"
	else

		echo "$FAIL_MESSAGE" >> "$LOGFILE"
		echo "*** $(date '+%c') -- Finished" >> "$LOGFILE"
		# Uncomment the line below if you want to use emailing and adjust the settings
		# echo "$FAIL_MESSAGE" | python /Library/Scripts/mailing.py $MAIL_RECPT "$FAIL_MESSAGE" "$LOGFILE"
		sendMail "$FAIL_MESSAGE" "$MAIL_RECPT" "$LOGFILE"
    fi
}


sendMail() {

	MESSAGE="$1"
	MAIL_RECPT="$2"
	LOGFILE="$3"

	echo "$MESSAGE" | python /Library/Scripts/mailing.py $MAIL_RECPT "$MESSAGE" "$LOGFILE"
}

CREATE_ARCHIVE
