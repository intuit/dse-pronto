#!/bin/bash

#set -x

# update the server_encryption section
java_home=$(dirname $(dirname $(/usr/sbin/alternatives --list | awk '{ if ($1 == "java" && $2 == "auto") print $3 }')))
file=${java_home}/lib/management/jmxremote.access
cp "$file" "$file.bak"
lead='^monitorRole   readonly'
tail='^controlRole   readwrite'
sed -e "/$lead/,/$tail/{ /$lead/{p;
    r ./jmxremote_access.config
    }; /$tail/p;
    d
   }" <"$file.bak"  > "$file"
