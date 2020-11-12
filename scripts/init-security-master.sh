#!/bin/bash

# required variables:
# $LOCAL_IP_RANGE = 10.0.0.0/24 - which addesses to allow for access from other swarm machines

sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config

parent_path=`dirname "$0"`
cp $parent_path/../server-files/usr/local/sbin/fail2ban-status.sh /usr/local/sbin/fail2ban-status.sh
cp $parent_path/../server-files/etc/ufw/applications.d/* /etc/ufw/applications.d/

cp $parent_path/../server-files/etc/msmtprc /etc/
sed -i \
    -e "s#MSMTP_HOST#$MSMTP_HOST#g" \
    -e "s#MSMTP_USER#$MSMTP_USER#g" \
    -e "s#MSMTP_PASSWORD#$MSMTP_PASSWORD#g" \
    "/etc/msmtprc"

ufw allow OpenSSH

# protocol ESP is required for swarm
ufw allow proto esp from $LOCAL_IP_RANGE to any

ufw allow from $LOCAL_IP_RANGE to any app "Docker Manager"
ufw allow from $LOCAL_IP_RANGE to any app Gluster

ufw --force enable
