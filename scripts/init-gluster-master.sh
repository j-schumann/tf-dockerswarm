#!/bin/bash

# required variables:
# $LOCAL_IP_RANGE = 10.0.0.0/24 - which addresses to allow to access the shared volume
# $STORAGE_MOUNT = /mnt/storage - directory to use for the volume brick, probably mount point of an attached cloud volume
# $GLUSTER_VOLUME = container-data - name for the glusterfs volume, will also be used for the mount point

# activate the gluster server using the cloud volume
systemctl enable glusterd.service
systemctl start glusterd.service
mkdir -p $STORAGE_MOUNT/bricks/1 /mnt/$GLUSTER_VOLUME
gluster volume create $GLUSTER_VOLUME swarmmaster:$STORAGE_MOUNT/bricks/1

# @todo create wildcard format from $LOCAL_IP_RANGE
gluster volume set $GLUSTER_VOLUME auth.allow 10.0.0.*

gluster volume start $GLUSTER_VOLUME

# mount now and also automatically after reboot
# @todo customize hostname?
mount.glusterfs swarmmaster:/$GLUSTER_VOLUME /mnt/$GLUSTER_VOLUME
echo "localhost:container-data /mnt/$GLUSTER_VOLUME glusterfs defaults,_netdev,backupvolfile-server=localhost 0 0" >> /etc/fstab
