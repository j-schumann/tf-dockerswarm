#!/bin/bash

# required variables:
# $LOCAL_IP_RANGE = 10.0.0.0/24 - which addesses to allow for access from other swarm machines
# $MYSQL_ROOT_PASSWORD = intial root password for mariadb/galera cluster 
# $NODE_TYPE = CX$$ | CPX$$ | CX$$-CEPH
# $PUBLIC_IP = IP address of the swarm master
# $SHARED_VOLUME_ID = 12345678 - Hetzner Cloud Volume ID, used to find the disk
# $SHARED_VOLUME_NAME = container-data - name for the glusterfs volume, will also be used for the mount point

. $SETUP_SCRIPT_PATH/scripts/lib.sh

# default setup
prepareBasicSecurity
prepareDockerConfig
setupMsmtp
setupRunOnce

# replace the automatically assigned IP of this server with the floating IP
setPublicIp $PUBLIC_IP

# requires prepareBasicSecurity 
setupSwarmMasterUfw
setupGlusterServerUfw

# mount the cloud volume so it is available for DB storage and Gluster
setupSharedVolume

# requires setupGlusterServerUfw + setupSharedVolume
setupGlusterServer

# requires all previous
setupSwarmMaster
