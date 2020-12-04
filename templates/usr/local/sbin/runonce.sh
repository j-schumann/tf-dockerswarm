#!/bin/sh

mkdir -p /etc/local/runonce.d/ran

for file in /etc/local/runonce.d/*
do
    if [ ! -f "$file" ]
    then
        continue
    fi
    $file 2>&1
    filename=$(basename $file)
    mv "$file" "/etc/local/runonce.d/ran/$filename.$(date +%Y%m%dT%H%M%S)"
    logger -t runonce -p local3.info "$file"
done
