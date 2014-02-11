#!/bin/bash


if [ -z "$1" ];then
    echo Require new password for user granite access to granite database
    echo "Usage: $0 [granite-sql-password] [sql-admin-user] [sql-admin-password]"
    exit 1
fi

password=$1
SQLUSER=$2
SQLPASS=$3
RUNCMD="mysql"

if [ -n "$SQLUSER" ];then
    RUNCMD="mysql -u$SQLUSER -p$SQLPASS"
fi


$RUNCMD -e "CREATE DATABASE granite;GRANT ALL PRIVILEGES ON granite.* TO 'granite'@'%' IDENTIFIED BY '$password';GRANT ALL PRIVILEGES ON granite.* TO 'granite'@'localhost' IDENTIFIED BY '$password'"
if [ $? -gt 0 ];then
    echo Operation failed
else
    echo Operation success
fi
