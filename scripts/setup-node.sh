#!/bin/bash

parent_path=`dirname "$0"`

echo "Setting up security..."
$parent_path/init-security-node.sh

echo "Mounting the GlusterFS volume..."
$parent_path/init-gluster-node.sh

echo "Joininging the Docker Swearm..."
$parent_path/init-swarm-node.sh
