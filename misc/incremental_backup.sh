#!/bin/bash
# Script fuer inkrementelles Backup mit 30 taegigem Vollbackup
# https://wiki.ubuntuusers.de/Skripte/inkrementelles_Backup/
# http://forums.vpslink.com/howtos/1920-incremental-backups-gnu-tar.html

LOG_FILE=/tmp/incremental_backuplog.txt
exec &> $LOG_FILE
echo "
#
#
# Backup start at " "$(date)"

### Einstellungen ##
BACKUPDIR="media/backup"           ## Pfad zum Backupverzeichnis
CONFIG_DB_BACKUPDIR="media/confdbbackup"
TMP_MYSQLDB_BACKUP_DIR="tmp/mysqlbackup"
ROTATEDIR="media/backup/rotate"    ## Pfad wo die Backups nach 30 Tagen konserviert werden
ROTATEDIR_CONFIGDB="media/confdbbackup/rotate"    ## Pfad wo die Backups nach 30 Tagen konserviert werden
TIMESTAMP="timestamp.dat"          ## Zeitstempel
SOURCE="home/user"                 ## Verzeichnis(se) welche(s) gesichert werden soll(en)
SOURCE_CONF_DB="$TMP_MYSQLDB_BACKUP_DIR home/user"                 ## Verzeichnis(se) welche(s) gesichert werden soll(en)
DATUM="$(date +%d-%m-%Y)"                                                       ## Datumsformat einstellen
ZEIT="$(date +%H:%M)"                                                           ## Zeitformat einstellen
MOUNT_DEVICE=NFS_SERVER_IP:/NFS_SHARE;
MOUNT_POINT=/root/snapshot;
INPROGRESS_FILE="$MOUNT_POINT/backup.inprogress";
ID=/usr/bin/id;
MYID="$$"
GZIPCHECK=();
ADMIN_MAIL=mail@example.com
### MYSQL Setup ###
NOWFILE=$(date +"%Y-%m-%d-%Hh-%Mm");
MUSER="mysqlbackup";
MPASS="mysqlpass";
MHOST="localhost";
MPORT="3306";
IGNOREDB="
information_schema
mysql
test
"

### Verzeichnisse/Dateien welche nicht gesichert werden sollen ! Achtung keinen Zeilenumbruch ! ##
EXCLUDE="--exclude=home/user/Filme --exclude=home/user/Musik --exclude=home/user/Spiele --exclude=home/user/.VirtualBox  --exclude=home/user/.local/share/Trash"
EXCLUDE_CONF_DB="--exclude=home/user/Filme --exclude=home/user/Musik --exclude=home/user/Spiele --exclude=home/user/.VirtualBox  --exclude=home/user/.local/share/Trash"

# make sure we're running as root
if (( $($ID -u) != 0 )); then { echo "$ID, Sorry, must be root.  Exiting..."; exit; } fi
MOUNT_RO_STATUS=$(grep -F -c 'root/snapshot nfs ro,' /proc/mounts)
if [ "$MOUNT_RO_STATUS" -eq "1" ];
        then
        echo "$ID, Mounted read only - remount rw"
        # attempt to remount the RW mount point as RW; else abort
        if ! mount -o remount,rw $MOUNT_DEVICE $MOUNT_POINT ; then
        {
                echo "$ID, snapshot: could not remount $MOUNT_POINT readwrite";
                exit;
        }
        fi;
[[ -f $INPROGRESS_FILE ]] && rm -f $INPROGRESS_FILE
fi
echo $MYID >> $INPROGRESS_FILE
chmod 600 $INPROGRESS_FILE

### Wechsel in root damit die Pfade stimmen ##
cd / || return

### Create backup dir ###
  if [ ! -d $TMP_MYSQLDB_BACKUP_DIR ]; then
    if mkdir -p $TMP_MYSQLDB_BACKUP_DIR; then
          :
      else
          echo "Couldn't create folder. Check folder permissions and/or disk quota!"
      fi
  else
   :
  fi

echo "
#
# Start backup of MYSQL
#
" | tee -a $LOG_FILE
  ### Get the list of available databases ###
  DBS="$(mysql -u $MUSER -p$MPASS -h $MHOST -P $MPORT -Bse 'show databases')"

  ### Backup DBs ###
  for db in $DBS
  do
      DUMP="yes";
      if [ "$IGNOREDB" != "" ]; then
          for i in $IGNOREDB
          do
              if [ "$db" == "$i" ]; then
                      DUMP="NO";
              fi
          done
      fi

      if [ "$DUMP" == "yes" ]; then
          FILE="$TMP_MYSQLDB_BACKUP_DIR/$NOWFILE-$db.sql.gz";
          echo "BACKING UP $db";
          if mysqldump --debug-info --add-drop-database --opt --lock-all-tables -u $MUSER -p$MPASS -h $MHOST -P $MPORT "$db" | gzip > "$FILE"; then
              if gunzip -t "$FILE"; then
                  GZIPCHECK+=(1);
                  ls -alh "$FILE";
              else
                  GZIPCHECK+=(0);
                  echo "Exit, gzip test failed.";
              fi
          else
              echo "Dump of $db failed!"
          fi
      fi
  done;

  ### Check if gzip test for all files was ok ###
  CHECKOUTS=${#GZIPCHECK[@]};
  for  ((i=0; i < CHECKOUTS; i++)); do
      CHECKSUM=$(( CHECKSUM + ${GZIPCHECK[${i}]} ));
  done

  ### If all files check out, delete the oldest dir ###
  if [ "$CHECKSUM" == "$CHECKOUTS" ]; then
      echo "All files checked out ok. MYSQLDUMP successful.";
  else
      echo "Dispatching Karl, he's an Expert";
      ### Send mail with contents of logfile ###
      echo "MYSQLDUMP ERROR Backuplog" | mutt -s "MYSQLDUMP ERROR Backuplog" $ADMIN_MAIL -a $LOG_FILE
  fi

### Backupverzeichnis anlegen ##
mkdir -p ${BACKUPDIR}
mkdir -p ${CONFIG_DB_BACKUPDIR}

### Test ob Backupverzeichnis existiert und Mail an Admin bei fehlschlagen ##
if [ ! -d "${BACKUPDIR}" ] || [ ! -d "${CONFIG_DB_BACKUPDIR}" ] ; then

mail -s "Backupverzeichnis nicht vorhanden!" $ADMIN_MAIL <<EOM
Hallo Admin,
das Backup am ${DATUM} konnte nicht erstellt werden. Das Verzeichnis ${BACKUPDIR} oder ${CONFIG_DB_BACKUPDIR} wurde nicht gefunden und konnte auch nicht angelegt werden.
Mit freundlichem Gruss Backupscript
EOM

exit 1
fi

### Alle Variablen einlesen und letzte Backupdateinummer herausfinden ##
set -- ${BACKUPDIR}/backup-???.tgz
lastname=${!#}
backupnr=${lastname##*backup-}
backupnr=${backupnr%%.*}
backupnr=${backupnr//\?/0}
backupnr=$((10#${backupnr}))

### Backupdateinummer automatisch um +1 bis maximal 30 erhoehen ##
if [ "$(backupnr++)" -ge 30 ]; then
mkdir -p ${ROTATEDIR}/"${DATUM}"-"${ZEIT}"

### Test ob Rotateverzeichnis existiert und Mail an Admin bei fehlschlagen ##
if [ ! -d "${ROTATEDIR}/${DATUM}-${ZEIT}" ]; then

mail -s "Rotateverzeichnis nicht vorhanden!" $ADMIN_MAIL <<EOM
Hallo Admin,
die alten Backups konnten am ${DATUM} nicht verschoben werden. Das Verzeichnis ${ROTATEDIR} wurde nicht gefunden und konnte auch nicht angelegt werden.
Mit freundlichem Gruss Backupscript
EOM

exit 1
else
mv ${BACKUPDIR}/* ${ROTATEDIR}/"${DATUM}"-"${ZEIT}"
retval=$?
### Abfragen ob das Backupverschieben erfolgreich war ##
if [ $retval -ne 0 ]; then
mail -s "Backupverschieben von ${BACKUPDIR} fehlerhaft!" $ADMIN_MAIL <<EOM
Hallo Admin,
die alten Backups konnte am ${DATUM} nicht verschoben werden.
Value was $retval
Mit freundlichem Gruss Backupscript
EOM

exit 1
else

mail -s "Backupverschieben erfolgreich" $ADMIN_MAIL <<EOM
Hallo Admin,
die alten Backups wurde am ${DATUM} erfolgreich nach ${ROTATEDIR}/${DATUM}-${ZEIT} verschoben.
Mit freundlichem Gruss Backupscript
EOM
fi

### die Backupnummer wieder auf 1 stellen ##
backupnr=1
fi
fi

backupnr=000${backupnr}
backupnr=${backupnr: -3}
filename=backup-${backupnr}.tgz

### Nun wird das eigentliche Backup ausgefuehrt ##
SOURCE_SUCCESS=Successful
echo "
#
# Start backup of ${SOURCE}
#
" | tee -a $LOG_FILE
if ! tar -cpvvzf ${BACKUPDIR}/${filename} -g ${BACKUPDIR}/${TIMESTAMP} ${SOURCE} "${EXCLUDE}" | tee -a $LOG_FILE; then
SOURCE_SUCCESS=fehlerhaft
echo "Backup (${SOURCE}) war fehlerhaft!" | mutt -s "Backup (${SOURCE}) war fehlerhaft!" $ADMIN_MAIL -a $LOG_FILE
fi

### Alle Variablen einlesen und letzte Backupdateinummer herausfinden ##
set -- ${CONFIG_DB_BACKUPDIR}/backup-???.tgz
lastname=${!#}
backupnr=${lastname##*backup-}
backupnr=${backupnr%%.*}
backupnr=${backupnr//\?/0}
backupnr=$(10#"${backupnr}")

### Backupdateinummer automatisch um +1 bis maximal 30 erhoehen ##
if [ "$(backupnr++)" -ge 30 ]; then
mkdir -p ${ROTATEDIR_CONFIGDB}/"${DATUM}"-"${ZEIT}"

### Test ob Rotateverzeichnis existiert und Mail an Admin bei fehlschlagen ##
if [ ! -d "${ROTATEDIR_CONFIGDB}/${DATUM}-${ZEIT}" ]; then

mail -s "Rotateverzeichnis nicht vorhanden!" $ADMIN_MAIL <<EOM
Hallo Admin,
die alten Backups konnten am ${DATUM} nicht verschoben werden. Das Verzeichnis ${ROTATEDIR_CONFIGDB} wurde nicht gefunden und konnte auch nicht angelegt werden.
Mit freundlichem Gruss Backupscript
EOM

exit 1
else

mv ${CONFIG_DB_BACKUPDIR}/* ${ROTATEDIR_CONFIGDB}/"${DATUM}"-"${ZEIT}"
retval=$?
### Abfragen ob das Backupverschieben erfolgreich war ##
if [ $retval -ne 0 ]; then
mail -s "Backupverschieben for ${CONFIG_DB_BACKUPDIR} fehlerhaft!" $ADMIN_MAIL <<EOM
Hallo Admin,
die alten Backups konnte am ${DATUM} nicht verschoben werden.
Value was $retval
Mit freundlichem Gruss Backupscript
EOM
exit 1
else
mail -s "Backupverschieben erfolgreich" $ADMIN_MAIL <<EOM
Hallo Admin,
die alten Backups wurde am ${DATUM} erfolgreich nach ${ROTATEDIR}/${DATUM}-${ZEIT} verschoben.
Mit freundlichem Gruss Backupscript
EOM
fi

### die Backupnummer wieder auf 1 stellen ##
backupnr=1
fi
fi

backupnr=000${backupnr}
backupnr=${backupnr: -3}
filename=backup-${backupnr}.tgz

SOURCE_CONF_DB_SUCCESS=Successful
echo "
#
# Start backup of ${SOURCE_CONF_DB}
#
" | tee -a $LOG_FILE
if ! tar -cpvvzf ${CONFIG_DB_BACKUPDIR}/${filename} -g ${CONFIG_DB_BACKUPDIR}/${TIMESTAMP} "${SOURCE_CONF_DB}" "${EXCLUDE_CONF_DB}" | tee -a $LOG_FILE; then
SOURCE_CONF_DB_SUCCESS=fehlerhaft
echo "Backup (${SOURCE_CONF_DB}) war fehlerhaft!" | mutt -s "Backup (${SOURCE_CONF_DB}) war fehlerhaft!" $ADMIN_MAIL -a $LOG_FILE
fi

echo "

#
# End backup of at $(date)
#

" | tee -a $LOG_FILE &&

echo "Backup (${SOURCE}) war $SOURCE_SUCCESS und (${SOURCE_CONF_DB}) war $SOURCE_CONF_DB_SUCCESS" | mutt -s "Backup (${SOURCE}) war $SOURCE_SUCCESS und (${SOURCE_CONF_DB}) war $SOURCE_CONF_DB_SUCCESS" $ADMIN_MAIL -a $LOG_FILE


# remove temporary mysql exports
rm -rf $TMP_MYSQLDB_BACKUP_DIR
rm -rf $LOG_FILE
# remove entry in progress file
sed -i "/.*$MYID.*/d" $INPROGRESS_FILE
# count lines in file
ACTIVE_SYNCS=$(wc -l $INPROGRESS_FILE | awk '{print $1}')
if [[ $ACTIVE_SYNCS -ge 1 ]]
        then
        echo "Other syncs are still running - don't remount ro"
        echo "$ID, Other syncs are still running - don't remount ro" | mutt -s "$ID, Other syncs are still running - don't remount ro" $ADMIN_MAIL
else
  # delete inprogress file now
  rm -f $INPROGRESS_FILE
  # now remount the RW snapshot mountpoint as readonly
  if ! mount -o remount,ro $MOUNT_DEVICE $MOUNT_POINT ; then
  	{
          echo "snapshot: could not remount, $MOUNT_POINT is in use"
          echo "$ID, snapshot: could not remount, $MOUNT_POINT is in use" | mutt -s "$ID, snapshot: could not remount, $MOUNT_POINT is in use" $ADMIN_MAIL
          exit
  	}
	fi
fi
