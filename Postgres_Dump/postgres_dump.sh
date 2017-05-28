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
