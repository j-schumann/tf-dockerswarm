#!/bin/bash

# required variables:
# $LOCAL_IP_RANGE = 10.0.0.0/24 - which addesses to allow for access from other swarm machines

sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
ufw allow OpenSSH

# protocol ESP is required for swarm
ufw allow proto esp from $LOCAL_IP_RANGE to any

ufw allow from $LOCAL_IP_RANGE to any app "Docker Node"

ufw enable
