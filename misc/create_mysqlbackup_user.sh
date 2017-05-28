#!/bin/bash
SHUF=$(shuf -i 13-15 -n 1)
export SHUF
export MYSQLBACKUPUSER=mysqlbackup
MYSQLBACKUPUSERPASS=$(< /dev/urandom tr -dc "a-zA-Z0-9@#*=" | head -c${1:-$(shuf -i 13-15 -n 1)};echo;)
export MYSQLBACKUPUSERPASS
export MYSQL_ROOT_PASS=securerootpass

#create sql file with create and grant scripts for mysqlbackupuser
echo "create sql file with create and grant scripts for mysqlbackupuser"
echo "CREATE USER '$MYSQLBACKUPUSER'@'localhost' IDENTIFIED BY '$MYSQLBACKUPUSERPASS';
GRANT RELOAD ON *.* TO '$MYSQLBACKUPUSER'@'localhost';
GRANT CREATE, INSERT, DROP, UPDATE ON mysql.backup_progress TO '$MYSQLBACKUPUSER'@'localhost';
GRANT CREATE, INSERT, SELECT, DROP, UPDATE ON mysql.backup_history TO '$MYSQLBACKUPUSER'@'localhost';
GRANT REPLICATION CLIENT ON *.* TO '$MYSQLBACKUPUSER'@'localhost';
GRANT SUPER ON *.* TO '$MYSQLBACKUPUSER'@'localhost';
GRANT PROCESS ON *.* TO '$MYSQLBACKUPUSER'@'localhost';
GRANT LOCK TABLES, SELECT, CREATE, ALTER ON *.* TO '$MYSQLBACKUPUSER'@'localhost';
GRANT CREATE, INSERT, DROP, UPDATE ON mysql.backup_sbt_history TO '$MYSQLBACKUPUSER'@'localhost';
quit" >> /var/scripts/create_mysql_backupuser.sql

# run sql file to create mysqlbackupuser
echo "run sql file to create mysqlbackupuser"
cat sql_backupuser.sql | mysql -u root -p$MYSQL_ROOT_PASS
