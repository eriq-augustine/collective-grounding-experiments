#!/bin/bash

if [[ $UID != 0 ]]; then
    echo "Run as root/sudo."
    exit 1
fi

echo "Clearing Postgres-related caches."

# Do an extra restart so we can guarentee all connections are closed.
systemctl stop postgresql.service
systemctl start postgresql.service

dropdb -U postgres psl
systemctl stop postgresql.service

# Page cache, dentries, and inodes.
sync; echo 3 > /proc/sys/vm/drop_caches

systemctl start postgresql.service
createdb -U postgres psl

wait
