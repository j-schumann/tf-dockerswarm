#!/bin/bash

# required variables:
# $ACME_MAIL = email address to register with letsencrypt
# $GLUSTER_VOLUME = container-data - implies the mount point of the gluster volume (/mnt/$GLUSTER_VOLUME)
# $MYSQL_ROOT_PASSWORD = intial root password for mariadb/galera cluster 
# $PUBLIC_IP = IP address of the swarm master

parent_path=`dirname "$0"`
env_file="$parent_path/../stacks/.env"

cp $parent_path/../server-files/etc/sysctl.d/80-docker.conf /etc/sysctl.d/80-docker.conf

# enp7s0 is specific to CPX servers, ens10 for CX servers
export LOCALIP=`ip -o -4 addr show dev ens10 | cut -d' ' -f7 | cut -d'/' -f1`
docker swarm init --advertise-addr $LOCALIP

# put the token on the shared volume so nodes can join the swarm
docker swarm join-token worker -q > /mnt/$GLUSTER_VOLUME/join-token.txt

# shared, encrypted mesh network for all containers on all nodes
docker network create --opt encrypted --driver overlay traefik-net

mkdir -p /mnt/$GLUSTER_VOLUME/{traefik,database0/config,database0/db,database1/config,database1/db}

sed -i \
    -e "s#PUBLIC_IP#$PUBLIC_IP#g" \
    -e "s#ACME_MAIL#$ACME_MAIL#g" \
    -e "s#GLUSTER_VOLUME#$GLUSTER_VOLUME#g" \
    -e "s#MYSQL_ROOT_PASSWORD#$MYSQL_ROOT_PASSWORD#g" \
    "$env_file"

# stack deploy does not support env-files, so prepare the config using docker-compose first...
docker stack deploy traefik -c <(docker-compose -f $parent_path/../stacks/traefik.yaml --env-file $env_file config)
