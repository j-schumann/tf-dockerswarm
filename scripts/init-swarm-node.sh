#!/bin/bash

# required variables:
# $GLUSTER_VOLUME = container-data - implies the mount point of the gluster volume (/mnt/$GLUSTER_VOLUME)
# $MASTER_IPV4_ADDRESS = 10.0.0.x - IP on the local network of the swarm master

cp ../server-files/etc/sysctl.d/80-docker.conf /etc/sysctl.d/80-docker.conf

docker swarm join --token `cat /mnt/$GLUSTER_VOLUME/join-token.txt` $MASTER_IPV4_ADDRESS:2377
