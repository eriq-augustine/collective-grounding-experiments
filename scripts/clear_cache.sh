#!/bin/bash

function clear_cache_docker() {
    echo "Clearing Postgres-related caches (in Docker)."

    # Do an extra restart so we can guarentee all ections are closed.
    service postgresql stop
    service postgresql start

    dropdb -U postgres psl
    service postgresql stop

    # Page cache, dentries, and inodes.
    sync; echo 3 > /proc/sys/vm/drop_caches

    service postgresql start
    createdb -U postgres psl
}

function clear_cache() {
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
}

wait

function main() {
    if [[ $# -ne 0 ]]; then
        echo "USAGE: $0"
        exit 1
    fi

    trap exit SIGINT

    if [[ $UID != 0 ]]; then
        echo "Run as root/sudo."
        exit 1
    fi

    if [[ -f /.dockerenv ]]; then
        clear_cache_docker
    else
        clear_cache
    fi

    wait
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

