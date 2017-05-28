# Setup of Postgres Daily Backup for Services of macOS Server

The base command is quite simple which is needed for a backup.  
_This is tested with macOS 12 and Server 5.2_

**Create the Dump/Backup**  
Create root session  
`sudo -s`  
Run the command to create the backup, the dump will be in /Backups/postgresql.  
`sudo -u _devicemgr /Applications/Server.app/Contents/ServerRoot/usr/bin/pg_dump -h /Library/Server/ProfileManager/Config/var/PostgreSQL devicemgr_v2m0 -b -F c -Z 9 -f /Backups/postgresql/profileManager.pgdump`


**Restore the Profile Manager**  
Start a root session  
`sudo -s`

Run this command to import the backup, the dump will be read from the Desktop.  
Wipe the database before the restore. I do both, run the wipeDB.sh and drop then manually all data with the below SQL script.  
Without the manual deletion of all data I had double entries for devices, users and groups which I don't want after a restore.  
`/Applications/Server.app/Contents/ServerRoot/usr/share/devicemgr/backend/wipeDB.sh`

Save this script in a file, e.g. _remove_data.sql_  
Execute the script this way:
`cat remove_data.sql | sudo -u _devicemgr /Applications/Server.app/Contents/ServerRoot/usr/bin/psql -h /Library/Server/ProfileManager/Config/var/PostgreSQL devicemgr_v2m0`

```sql
do
$$
declare
  l_stmt text;
begin
  select 'truncate ' || string_agg(format('%I.%I', schemaname, tablename), ',')
    into l_stmt
  from pg_tables
  where schemaname in ('public');

  execute l_stmt;
end;
$$
```

Now run the restore command:
`sudo -u _devicemgr /Applications/Server.app/Contents/ServerRoot/usr/bin/pg_restore -h /Library/Server/ProfileManager/Config/var/PostgreSQL -d devicemgr_v2m0 -c -v /Backups/postgresql/profileManager.pgdump`


#### Shell Script
The base of the shell script is from Archetrix from Apple discussions, link below.
I modified it to a function with 3 parameters and adapted it to work now with the latest version of Server 5.2.

This is what the script looks like and what it does:
- it sets a few variables:
  - path to the psql bin
  - backup directory
  - log file, compresion, actual date and time for the name of the backup
  - expire date, is set to 2w, used for deletion of backups that match that date
  - connection settings
- it loops through all databases (but it only contains the general postgres and the specified application database)
- it vacuums the databases
- then it's doing the backup
- after that it's checking for expired backups and deleting them
- in case of an error it is logged as well as all other executed commands
- if required the log can be mailed (or the backup itself, any file), my mailing.py script is used in this case

```shell
#!/bin/sh
if (test "$(whoami)" != "root") then
        echo "You need to be root to start this"
        exit 1
fi

PG_BIN="sudo -u _devicemgr /Applications/Server.app/Contents/ServerRoot/usr/bin"
BACKUP_DIR="/Backups/postgres"
COMPRESSION="9"
ACT_DATE=$(date '+%y-%m-%d')
ACT_TIME=$(date '+%H:%M')
EXP_DATE=$(date -v -2w '+%y-%m-%d')
LOGFILE=$BACKUP_DIR"/_pg_dump-$ACT_DATE.log"

DO_BACKUP() {

PG_FILE="$1"
PG_DATABASE="$2"
MAIL_RECPT="$3"

PG_CON="-h $PG_FILE -d $PG_DATABASE"
BACKUP_OPTIONS="$PG_CON -b -v -C -F c -Z $COMPRESSION"
VACUUM_OPTIONS="$PG_CON -eq"

echo " " >>"$LOGFILE"
echo " " >>"$LOGFILE"
echo "***** DB_BACKUP $ACT_DATE *****" >>"$LOGFILE"
echo "Settings are:" >>"$LOGFILE"
echo "* POSTGRESQL: $PG_BIN" >>"$LOGFILE"
echo "* DATABASE SOCKET: $PG_FILE" >>"$LOGFILE"
echo "* DATABASE NAME: $PG_DATABASE" >>"$LOGFILE"
echo "* MAIL RECEIPT: $MAIL_RECPT" >>"$LOGFILE"

echo "* Test connection: " >>"$LOGFILE"

if ! $PG_BIN/psql $PG_CON -lt >>"$LOGFILE"  2>&1 ; then
  #if [ "$?" != "0" ]; then
  # some error occured right from the beginning
  sendMail "The Postgredump couldn't be created, check log; the message $1" "$MAIL_RECPT" "$LOGFILE"
  exit 1
fi

for db in $($PG_BIN/psql $PG_CON -lt | sed /\eof/p | grep -v = | awk {'print $1'})
  do
    FAIL_MESSAGE="**** FAIL **** Database $db backup on $(hostname)!"
    SUCCESS_MESSAGE="**** SUCCESS **** Database $db backup on $(hostname)!"

# vacuum
    if [ "X" = "X$db" ]; then
          continue;
    fi

    echo "$(date '+%c')"" -- vacuuming database $db" >> "$LOGFILE"

    if $PG_BIN/vacuumdb $VACUUM_OPTIONS >> "$LOGFILE"
      then
      echo "OK!" >> "$LOGFILE"
          sleep 1
    else
      echo "No Vacuum in database $db!" >> "$LOGFILE"
    fi

    # backup
    echo "$(date '+%c')"" -- backing up database $db" >>"$LOGFILE"

    if  $PG_BIN/pg_dump $BACKUP_OPTIONS -f $BACKUP_DIR/"$db"-"$ACT_DATE"-"$ACT_TIME".pgdump >> "$LOGFILE"
    then
      for file in "$BACKUP_DIR"/"$db"-"$EXP_DATE"*.pgdump
      do

      if [ -e "$file" ]; then
        echo "$(date '+%c') -- deleting old backup" >> "$LOGFILE"
        echo "*** $(ls -l $BACKUP_DIR/$db-$EXP_DATE*.pgdump)" >> "$LOGFILE"
        rm $BACKUP_DIR/"$db"-"$EXP_DATE"*.pgdump
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
  done
}

sendMail() {

MESSAGE="$1"
MAIL_RECPT="$2"
LOGFILE="$3"

echo "$MESSAGE" | python /Library/Scripts/mailing.py $MAIL_RECPT "$MESSAGE" "$LOGFILE"
}

DO_BACKUP "/Library/Server/ProfileManager/Config/var/PostgreSQL" "devicemgr_v2m0" admin@example.com,admin2@example.com
```
I have saved that file in /Library/Scripts/postgres_dump.sh


#### Create LaunchDaemon file

This is the plist for the LaunchDaemon which I place in in this location:  
/Library/LaunchDaemons/com.lisowski.postgres_dump.plist

It will run every day at 1am.

and activate with this command:  
`sudo launchctl load -w /Library/LaunchDaemons/com.lisowski.postgres_dump.plist`

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>Label</key>
        <string>com.lisowski.postgres_dump</string>
        <key>ProgramArguments</key>
        <array>
                <string>/Library/Scripts/postgres_dump.sh</string>
        </array>
        <key>StartCalendarInterval</key>
        <dict>
            <key>Hour</key>
            <integer>01</integer>
            <key>Minute</key>
            <integer>00</integer>
        </dict>
        <key>RunAtLoad</key>
        <false/>
</dict>
</plist>
```

Most credit goes to these pages:
- [twistedmac.com](http://www.twistedmac.com/index.php/28-mac-os-x-server/36-backup-profile-manager-database)
- Archetrix post on [discussions.apple.com](https://discussions.apple.com/thread/3227951?start=0&tstart=0)
