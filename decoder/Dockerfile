FROM python:3.12-alpine

RUN apk add --no-cache libpcap iproute2 tcpdump
RUN pip install --no-cache-dir scapy

WORKDIR /app
COPY ospf_bgp_decoder.py ./

ENTRYPOINT ["python3"]
