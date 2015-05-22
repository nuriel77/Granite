#!/bin/bash


USER=$1
PARTITION=$2

if [ -z "$1" ] || [ -z "$2" ];then
    echo Usage: $0 username partition
    exit 1
fi

/opt/slurm/bin/scontrol show res|grep Users=$USER -B1|grep -q PartitionName=$PARTITION
if [ $? -gt 0 ];then
    /opt/slurm/bin/scontrol create reservation starttime=now duration=infinite user=$USER flags=maint,ignore_jobs partition=$PARTITION
    ERR=$?
    if [ $ERR -gt 0 ];then
        echo "Error: $ERR"
        exit $ERR
    else
        echo "Reservation created OK"
        exit 0
    fi
else
    echo "Reservation already exists"
    exit 0
fi
