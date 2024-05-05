#!/bin/bash 

docker build -t hh_discord_app .
docker save hh_discord_app:latest | ssh -C root@37.221.193.242 "docker load"
ssh root@37.221.193.242 "cd /opt/hh_discord_app; docker compose up -d"