FROM debian:jessie
RUN apt-get update && apt-get upgrade -y && apt-get install tinc -y
ADD qtinc /root/qtinc

