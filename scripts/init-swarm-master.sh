#!/bin/bash

# required variables:
# $GLUSTER_VOLUME = container-data - implies the mount point of the gluster volume (/mnt/$GLUSTER_VOLUME)

parent_path=`dirname "$0"`
cp $parent_path/../server-files/etc/sysctl.d/80-docker.conf /etc/sysctl.d/80-docker.conf

export LOCALIP=`ip -o -4 addr show dev ens10 | cut -d' ' -f7 | cut -d'/' -f1`
docker swarm init --advertise-addr $LOCALIP

# put the token on the shared volume so nodes can join the swarm
docker swarm join-token worker -q > /mnt/$GLUSTER_VOLUME/join-token.txt

# shared, encrypted mesh network for all containers on all nodes
docker network create --opt encrypted --driver overlay traefik-net
