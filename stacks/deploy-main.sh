#!/bin/bash

parent_path=$(dirname "$0")

# stack deploy does not support env-files, so prepare the config using docker-compose first...
docker stack deploy main --with-registry-auth -c <(/usr/local/bin/docker-compose -f $SETUP_SCRIPT_PATH/stacks/main.yaml --env-file $SETUP_SCRIPT_PATH/stacks/.env config)
