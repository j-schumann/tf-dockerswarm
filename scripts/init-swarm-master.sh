#!/bin/bash

# required variables:
# $ACME_MAIL = email address to register with letsencrypt
# $ADMIN_PASSWORD = basic auth password for admin services (PhpMyAdmin etc.)
# $DOCKER_HUB_USER = username for hub.docker.com
# $DOCKER_HUB_TOKEN = access token for hub.docker.com
# $GLUSTER_VOLUME = container-data - implies the mount point of the gluster volume (/mnt/$GLUSTER_VOLUME)
# $MYSQL_ROOT_PASSWORD = intial root password for mariadb/galera cluster 
# $NODE_TYPE = CX$$ | CPX$$ | CX$$-CEPH
# $PUBLIC_IP = IP address of the swarm master
# $STORAGE_MOUNT = /mnt/storage - directory to use for the volume brick, probably mount point of an attached cloud volume

parent_path=`dirname "$0"`
env_file="$parent_path/../stacks/.env"

# default directories for the container data
mkdir -p /mnt/$GLUSTER_VOLUME/{traefik,mariadb/config,nginx,logging/elastic,logging/config} $STORAGE_MOUNT/mariadb

# required for mariadb to start
chown -R 1001:1001 $STORAGE_MOUNT/mariadb

cp $parent_path/../server-files/etc/sysctl.d/80-docker.conf /etc/sysctl.d/
cp $parent_path/../server-files/config/mariadb/my_custom.cnf /mnt/$GLUSTER_VOLUME/mariadb/config/
cp $parent_path/../server-files/config/nginx/site.conf /mnt/$GLUSTER_VOLUME/nginx/
cp -R $parent_path/../server-files/config/logging /mnt/$GLUSTER_VOLUME/logging/config

# login to hub.docker.com to create the credentials file
echo $DOCKER_HUB_TOKEN | docker login --username $DOCKER_HUB_USER --password-stdin

# enp7s0 is specific to CPX servers, ens10 for CX servers
localInterface="ens10"
if [[ $NODE_TYPE =~ "cpx" ]]; then
  localInterface="enp7s0"
fi

export LOCALIP=`ip -o -4 addr show dev $localInterface | cut -d' ' -f7 | cut -d'/' -f1`
docker swarm init --advertise-addr $LOCALIP

# install docker-compose from github, ubuntu has an old version
curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# put the token on the shared volume so nodes can join the swarm
docker swarm join-token worker -q > /mnt/$GLUSTER_VOLUME/join-token.txt

# shared, encrypted mesh network for all containers on all nodes
docker network create --opt encrypted --driver overlay traefik-net

# basic auth password for PhpMyAdmin etc.
# @todo double-$ required for direct injection in main.yaml: | sed -e s/\\$/\\$\\$/g
ADMIN_CREDENTIALS=$(htpasswd -nb admin `echo $ADMIN_PASSOWRD`)

# prepare the .env file, the ENV variables are only set now in the cloud-init boot
sed -i \
    -e "s#ACME_MAIL#$ACME_MAIL#g" \
    -e "s#ADMIN_CREDENTIALS#$ADMIN_CREDENTIALS#g" \
    -e "s#GLUSTER_VOLUME#$GLUSTER_VOLUME#g" \
    -e "s#MYSQL_ROOT_PASSWORD#$MYSQL_ROOT_PASSWORD#g" \
    -e "s#PUBLIC_IP#$PUBLIC_IP#g" \
    -e "s#STORAGE_MOUNT#$STORAGE_MOUNT#g" \
    "$env_file"

# setup infrastructure for tasks that are run once after the next reboot
mkdir -p /etc/local/runonce.d/ran
cp $parent_path/../server-files/usr/local/sbin/runonce.sh /usr/local/sbin/
chmod ug+x /usr/local/sbin/runonce.sh
echo "@reboot root /usr/local/sbin/runonce.sh 2>&1 >> /var/log/runonce.log" >> /etc/cron.d/runonce

# we don't want to deploy the stack right now but only after the reboot
# triggered by cloud-init and an additional 5min wait time to give the nodes
# time to be ready & mount the Gluster volume, to spread the services on the nodes
echo "#!/bin/bash
sleep 300
/root/terraform-init/stacks/deploy-main.sh" >> /etc/local/runonce.d/deploy-main-stack.sh
chmod ug+x /etc/local/runonce.d/deploy-main-stack.sh
