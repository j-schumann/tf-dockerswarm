#!/bin/bash

echo "Setting up security..."
./init-security-master.sh

echo "Mounting the attached cloud volume..."
./init-storage-mount.sh

echo "Configuring the GlusterFS Server..."
./init-gluster-master.sh

echo "Creating the Docker Swearm..."
./init-swarm-master.sh
