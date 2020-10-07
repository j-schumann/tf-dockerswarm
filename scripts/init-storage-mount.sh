#!/bin/bash

# required variables:
# $CLOUD_VOLUME_ID = 12345678 - Hetzner Cloud Volume ID, used to find the disk
# $STORAGE_MOUNT = /mnt/storage - mount point for the cloud volume

# mount the cloud volume now and automatically after reboot
mkdir -p $STORAGE_MOUNT
echo "/dev/disk/by-id/scsi-0HC_Volume_$CLOUD_VOLUME_ID $STORAGE_MOUNT xfs discard,nofail,defaults 0 0" >> /etc/fstab
mount -o discard,defaults /dev/disk/by-id/scsi-0HC_Volume_${volume_id} $STORAGE_MOUNT
