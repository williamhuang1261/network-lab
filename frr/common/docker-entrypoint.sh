#!/bin/sh
set -e

# snmpd's own daemonizing fork exits 1 in this container environment;
# run it in foreground and background it from the shell instead.
snmpd -f -Lf /var/log/snmpd.log -c /etc/snmp/snmpd.conf &

exec /sbin/tini -- /usr/lib/frr/docker-start
