#!/bin/bash

# stack deploy does not support env-files, so prepare the config using docker-compose first...
docker stack deploy main -c < $(docker-compose -f main.yaml --env-file .env config)