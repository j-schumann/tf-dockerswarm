#!/bin/bash

parent_path=$(dirname "$0")

# stack deploy does not support env-files, so prepare the config using docker-compose first...
docker stack deploy main --with-registry-auth -c <(/usr/local/bin/docker-compose -f $parent_path/main.yaml --env-file $parent_path/.env config)
