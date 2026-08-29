FROM frrouting/frr:latest

RUN apk add --no-cache net-snmp net-snmp-tools

COPY snmpd.conf /etc/snmp/snmpd.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
