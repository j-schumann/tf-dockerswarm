#!/bin/bash

parent_path=`dirname "$0"`

echo "Setting up security..."
$parent_path/init-security-master.sh

echo "Mounting the attached cloud volume..."
$parent_path/init-storage-mount.sh

echo "Configuring the GlusterFS Server..."
$parent_path/init-gluster-master.sh

echo "Creating the Docker Swearm..."
$parent_path/init-swarm-master.sh
