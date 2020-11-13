#!/bin/bash

# required variables:
# $GLUSTER_VOLUME = container-data - name of the shared volume, implies the mount point
# $MASTER_IPV4_ADDRESS = 10.0.0.x - IP in the local range of the GlusterFS server
# $MASTER_NAME = hostname of the docker swarm master / gluster server

mkdir -p /mnt/$GLUSTER_VOLUME

# mounting via "ip:/volume" is not allowed -> use the hostname
echo "$MASTER_IPV4_ADDRESS $MASTER_NAME" >> /etc/hosts

# mount the shared volume now and also automatically after reboot
echo "$MASTER_NAME:/$GLUSTER_VOLUME /mnt/$GLUSTER_VOLUME glusterfs defaults,_netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=45 0 0" >> /etc/fstab

echo -n "waiting till mount of the shared volume succeeds..."
until mount.glusterfs $MASTER_NAME:/$GLUSTER_VOLUME /mnt/$GLUSTER_VOLUME 2> /dev/null
do
    sleep 5
    echo -n "."
done
echo ""
