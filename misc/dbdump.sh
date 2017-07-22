#!/bin/bash

DBUSER="mysqlbackup"
DBPASSWD="$(cat /root/webbackup/.dbpasswd)"
DBBAKPATH="/root/backup/dbdumps/"
DBHOST="localhost";
DBPORT="3306";
IGNOREDBS="
information_schema
performance_schema
mysql
test
"


# create DBBAKPATH if not existent
if [ ! -d "$DBBAKPATH" ]; then
  mkdir -p -v "$DBBAKPATH"
fi

echo "# Start backup of MYSQL"
### Get the list of available databases ###
DBS="$(mysql -u $DBUSER -p"$DBPASSWD" -h $DBHOST -P $DBPORT -Bse 'show databases')"

### Backup DBs ###
for db in $DBS
  do
    DUMP="yes";

    # check if database should be ignored it receives a now flag
    if [ "$IGNOREDBS" != "" ]; then
        for i in $IGNOREDBS
        do
            if [ "$db" == "$i" ]; then
                    DUMP="NO";
            fi
        done
    fi

    # backup databases which with a yes flag
    if [ "$DUMP" == "yes" ]; then
        echo "BACKING UP $db";
        if ! mysqldump --debug-info --add-drop-database --opt --lock-all-tables -u "$DBUSER" -p"$DBPASSWD" -h "$DBHOST" -P "$DBPORT" "$db" > "${DBBAKPATH}${db}"; then
            echo "Dump of $db failed!" ; exit 1
        fi
    fi
done;

echo "# End backup of MYSQL"
