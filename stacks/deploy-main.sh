#!/bin/bash

parent_path=$(dirname "$0")
# stack deploy does not support env-files, so prepare the config using docker-compose first...
docker stack deploy main -c <(docker-compose -f $parent_path/main.yaml --env-file $parent_path/.env config)