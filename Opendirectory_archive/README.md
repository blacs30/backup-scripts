# Setup of Opendirectory Daily Archive of macOS Server

The base command is very simple which is needed for a backup.  
_This is tested with macOS 12 and Server 5.2_

**Create the Archive/Backup**  
Create root session  
`sudo -s`  
Run the command to create the archive, the export location is the Desktop.  
`sudo /usr/sbin/slapconfig -backupdb ~/Desktop`


**Restore OpenDirectory from archive**  
Start a root session  
`sudo -s`

Run this command to import the archive, adjust the path to the archive if needed.  
Execute the script this way:
`sudo /usr/sbin/slapconfig -restoredb ~/Desktop/Opendirectory.sparseimage`


#### Shell Script
I want the archive happening every day to be able to restore the opendirectory in case anything happens.
The base script is the same as my postgres dump script.

This is what the script looks like and what it does:
- it sets a few variables:
  - backup directory
  - log file, actual date and time for the name of the backup
  - expire date, is set to 2w, used for deletion of backups that match that date
- check if slapd test is running through without error, otherwise the export will be aborted
- in case the backup folder doesn't exist it will be created
- then it's doing the backup
- after that it's checking for expired backups and deleting them
- in case of an error it is logged as well as all other executed commands
- if required the log can be mailed (or the backup itself, any file), my mailing.py script is used in this case

```shell
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
```
I have saved that file in /Library/Scripts/opendirectory_archive.sh


#### Create LaunchDaemon file

This is the plist for the LaunchDaemon which I place in in this location:  
/Library/LaunchDaemons/com.lisowski.opendirectory_archive.plist

It will run every day at 2am.

and activate with this command:  
`sudo launchctl load -w /Library/LaunchDaemons/com.lisowski.opendirectory_archive.plist`

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>Label</key>
        <string>com.lisowski.opendirectory_archive</string>
        <key>ProgramArguments</key>
        <array>
                <string>/Library/Scripts/opendirectory_archive.sh</string>
        </array>
        <key>StartCalendarInterval</key>
        <dict>
            <key>Hour</key>
            <integer>02</integer>
            <key>Minute</key>
            <integer>00</integer>
        </dict>
        <key>RunAtLoad</key>
        <false/>
</dict>
</plist>

```

Credit for the idea of using expect from
- [practiceofcode.com](http://www.practiceofcode.com/post/36837763894/open-directory-7-day-rotating-backup-script)
