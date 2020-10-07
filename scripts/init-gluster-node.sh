#!/bin/bash

# required variables:
# $GLUSTER_VOLUME = container-data - name of the shared volume, implies the mount point
# $MASTER_IPV4_ADDRESS = 10.0.0.x - IP in the local range of the GlusterFS server

mkdir -p /mnt/$GLUSTER_VOLUME

# mounting via "ip:/volume" is not allowed -> use the hostname
# @todo customize master hostname?
echo "$MASTER_IPV4_ADDRESS swarmmaster" >> /etc/hosts

# mount the shared volume now and also automatically after reboot
# @todo customize master hostname?
echo "swarmmaster:/$GLUSTER_VOLUME /mnt/$GLUSTER_VOLUME glusterfs defaults,_netdev 0 0" >> /etc/fstab

echo -n "waiting till mount of the shared volume succeeds..."
until mount.glusterfs swarmmaster:/$GLUSTER_VOLUME /mnt/$GLUSTER_VOLUME 2> /dev/null
do
    sleep 5
    echo -n "."
done
echo ""
