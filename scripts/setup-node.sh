#!/bin/bash

# required variables:
# $MASTER_IPV4_ADDRESS = 10.0.0.x - IP in the local range of the GlusterFS server
# $MASTER_NAME = hostname of the docker swarm master / gluster server

. $SETUP_SCRIPT_PATH/scripts/lib.sh

# default setup
prepareBasicSecurity
prepareDockerConfig
setupMsmtp
setupRunOnce

# node specific
setupSwarmNodeUfw
setupGlusterClient

# requires all previous
setupSwarmNode
