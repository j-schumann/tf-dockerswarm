#!/bin/bash

echo "Setting up security..."
./init-security-node.sh

echo "Mounting the GlusterFS volume..."
./init-gluster-node.sh

echo "Joininging the Docker Swearm..."
./init-swarm-node.sh
