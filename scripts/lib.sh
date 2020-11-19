#!/bin/bash

generatePassword() {
    openssl rand -hex 16
}

getLocalInterface() {
    # enp7s0 is specific to CPX servers, ens10 for CX servers
    if [[ $NODE_TYPE =~ "cpx" ]]; then
        echo "enp7s0"
    else
        echo "ens10"
    fi
}

getLocalIp() {
    local iface=$(getLocalInterface)
    ip -o -4 addr show dev $iface | cut -d' ' -f7 | cut -d'/' -f1
}

createBasicCredentials() {
    htpasswd -nb $1 `echo $2`
}

waitForFile() {
    echo -n "waiting till file $1 exists..."
    while [ ! -f $1 ]; do
        sleep 2
        echo -n "."
    done
    echo ""
}

# returns the ID of a container who's name contains the given pattern
getContainerIdByName() {
    docker ps -f "name=$1" -q
}

waitForContainer() {
    echo -n "waiting till container with name *$1* exists..."
    while [ -z `getContainerIdByName $1` ]; do
        sleep 2
        echo -n "."
    done
    echo ""
}

getSharedVolumeMount() {
    echo "/mnt/$SHARED_VOLUME_NAME"
}

getSharedVolumeLocalMount() {
    echo "/mnt/${SHARED_VOLUME_NAME}_local"
}

getAssistantVolumeMount() {
    echo "/mnt/$ASSISTANT_VOLUME_NAME"
}

########################
# (c) Bitnami - Apache License
# Retries a command a given number of times
# Arguments:
#   $1 - cmd (as a string)
#   $2 - max retries. Default: 12
#   $3 - sleep between retries (in seconds). Default: 5
# Returns:
#   Boolean
#########################
retry_while() {
    local cmd="${1:?cmd is missing}"
    local retries="${2:-12}"
    local sleep_time="${3:-5}"
    local return_value=1

    read -r -a command <<< "$cmd"
    for ((i = 1 ; i <= retries ; i+=1 )); do
        "${command[@]}" && return_value=0 && break
        sleep "$sleep_time"
    done
    return $return_value
}

# setup infrastructure for tasks that are run once after the next reboot
setupRunOnce() {
    mkdir -p /etc/local/runonce.d/ran
    cp $SETUP_SCRIPT_PATH/templates/usr/local/sbin/runonce.sh /usr/local/sbin/
    chmod ug+x /usr/local/sbin/runonce.sh
    echo "@reboot root /usr/local/sbin/runonce.sh 2>&1 >> /var/log/runonce.log" >> /etc/cron.d/runonce
}

prepareDockerConfig() {
    cp $SETUP_SCRIPT_PATH/templates/etc/sysctl.d/80-docker.conf /etc/sysctl.d/
}

prepareMariadbConfig() {
    local sharedMountPoint=$(getSharedVolumeMount)

    mkdir -p $sharedMountPoint/mariadb/config
    cp $SETUP_SCRIPT_PATH/templates/config/mariadb/my_custom.cnf $sharedMountPoint/mariadb/config/
}

prepareMariadbStorage() {
    local localMountPoint=$(getSharedVolumeLocalMount)
    mkdir -p $localMountPoint/mariadb

    # required for mariadb to start
    chown -R 1001:1001 $localMountPoint/mariadb
}

prepareDbSlaveStorage() {
    echo "preparing folders for the replication slave..."
    local mountPoint=$(getAssistantVolumeMount)
    
    mkdir -p $mountPoint/dbslave

    # required for mariadb to start
    chown -R 1001:1001 $mountPoint/dbslave
}

prepareLogging() {
    local assistantMountPoint=$(getAssistantVolumeMount)
    mkdir -p $assistantMountPoint/logging/{config,elastic}

    # required for elasticsearch to start
    chown -R 1000:1000 $assistantMountPoint/logging/elastic

    cp -R $SETUP_SCRIPT_PATH/templates/config/logging/* $assistantMountPoint/logging/config/

    # set the password in the config now so we don't need to restart the container    
    sed -i \
        -e "s#ELASTIC_PASSWORD#$ELASTIC_PASSWORD#g" \
        "$assistantMountPoint/logging/config/pipeline/logstash.conf"

    # create a password and set it in the config now so we don't need to restart the container
    # also store it in plaintext so we can set it in the container after reboot
    local kibanaPW=$(generatePassword)
    echo $kibanaPW > $assistantMountPoint/logging/kibana.pw
    sed -i \
        -e "s#KIBANA_PASSWORD#$kibanaPW#g" \
        "$assistantMountPoint/logging/config/kibana.yml"

    # create a password and set it in the config now so we don't need to restart the container
    # also store it in plaintext so we can set it in the container after reboot
    local logstashPW=$(generatePassword)
    echo $logstashPW > $assistantMountPoint/logging/logstash.pw
    sed -i \
        -e "s#LOGSTASH_PASSWORD#$logstashPW#g" \
        "$assistantMountPoint/logging/config/logstash.yml"
}

prepareBasicSecurity() {
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    cp $SETUP_SCRIPT_PATH/templates/usr/local/sbin/fail2ban-status.sh /usr/local/sbin/fail2ban-status.sh
    cp $SETUP_SCRIPT_PATH/templates/etc/ufw/applications.d/* /etc/ufw/applications.d/
    
    ufw allow OpenSSH
    
    # protocol ESP is required for Docker swarm on master & nodes 
    ufw allow proto esp from $LOCAL_IP_RANGE to any

    ufw --force enable
}

setPublicIp() {
    echo "Setting the IP $1 as default..."
    cp $SETUP_SCRIPT_PATH/templates/etc/netplan/60-floating-ip.yaml /etc/netplan/
    sed -i "s/PUBLIC_IP/$1/g" /etc/netplan/60-floating-ip.yaml
    # don't use "netplan apply", the final cloud-init reboot is enough,
    # it causes loss of the ens10/enp7s0 interface... 
}

# to send emails from cron jobs etc to external mail address
setupMsmtp() {
    echo "configuring MSMTP to send status mails to external mailbox..."
    cp $SETUP_SCRIPT_PATH/templates/etc/msmtprc /etc/
    sed -i \
        -e "s#MSMTP_HOST#$MSMTP_HOST#g" \
        -e "s#MSMTP_USER#$MSMTP_USER#g" \
        -e "s#MSMTP_PASSWORD#$MSMTP_PASSWORD#g" \
        "/etc/msmtprc"
}

# allow ports for swarm management, requires ufw config from prepareBasicSecurity
setupSwarmMasterUfw() {
    echo "configuring UFW to allow Docker swarm management..."

    ufw allow from $LOCAL_IP_RANGE to any app "Docker Manager"
}

# allow ports for swarm, requires ufw config from prepareBasicSecurity
setupSwarmNodeUfw() {
    echo "configuring UFW to allow Docker swarm participation..."

    ufw allow from $LOCAL_IP_RANGE to any app "Docker Node"
}

setupGlusterServerUfw() {
    echo "configuring UFW to allow Gluster management..."
    ufw allow from $LOCAL_IP_RANGE to any app Gluster
}

# mount the cloud volume now and automatically after reboot
setupSharedVolume() {
    echo "mounting the attached cloud storage $SHARED_VOLUME_NAME ($SHARED_VOLUME_ID)"
    local mountPoint=$(getSharedVolumeLocalMount)
    mkdir -p $mountPoint

    echo "/dev/disk/by-id/scsi-0HC_Volume_$SHARED_VOLUME_ID $mountPoint xfs discard,nofail,defaults 0 0" >> /etc/fstab
    mount -o discard,defaults /dev/disk/by-id/scsi-0HC_Volume_$SHARED_VOLUME_ID $mountPoint
}

# mount the cloud volume now and automatically after reboot
setupAssistantVolume() {
    echo "mounting the attached cloud storage $ASSISTANT_VOLUME_NAME ($ASSISTANT_VOLUME_ID)"
    local mountPoint=$(getAssistantVolumeMount)
    mkdir -p $mountPoint

    echo "/dev/disk/by-id/scsi-0HC_Volume_$ASSISTANT_VOLUME_ID $mountPoint xfs discard,nofail,defaults 0 0" >> /etc/fstab
    mount -o discard,defaults /dev/disk/by-id/scsi-0HC_Volume_$ASSISTANT_VOLUME_ID $mountPoint
}

setupGlusterServer() {
    echo "setting up GlusterFS server..."

    local brickPath=$(getSharedVolumeLocalMount)/bricks/1
    local mountPoint=$(getSharedVolumeMount)

    # activate the gluster server using the cloud volume
    systemctl enable glusterd.service
    systemctl start glusterd.service

    # to re-use an existing brick on the storage in a new gluster volume
    # we have to reset it and only keep the data
    if [ -d $brickPath ]; then
        "found an old volume, cleaning up for re-use..."
        setfattr -x trusted.glusterfs.volume-id $brickPath
        setfattr -x trusted.gfid $brickPath
        rm -rf $brickPath/.glusterfs

        # prevent the nodes receiving an old token
        # if one exists from previous setups
        rm $brickPath/join-token.txt 2> /dev/null
    fi

    mkdir -p $brickPath $mountPoint

    # create the volume in the given path, hostname is required, "localhost" is not allowed
    gluster volume create $SHARED_VOLUME_NAME `hostname`:$brickPath

    # @todo create wildcard format from $LOCAL_IP_RANGE
    gluster volume set $SHARED_VOLUME_NAME auth.allow 10.0.0.*

    gluster volume start $SHARED_VOLUME_NAME

    # mount now and also automatically after reboot
    mount.glusterfs localhost:/$SHARED_VOLUME_NAME $mountPoint
    echo "localhost:$SHARED_VOLUME_NAME $mountPoint glusterfs defaults,_netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=15,backupvolfile-server=localhost 0 0" >> /etc/fstab
}

setupGlusterClient() {
    local sharedMountPoint=$(getSharedVolumeMount)
    local masterName=${CLUSTER_NAME_PREFIX}master

    mkdir -p $sharedMountPoint

    # mounting via "ip:/volume" is not allowed -> use the hostname
    echo "$MASTER_IPV4_ADDRESS $masterName" >> /etc/hosts

    # mount the shared volume now and also automatically after reboot
    echo "$masterName:/$SHARED_VOLUME_NAME $sharedMountPoint glusterfs defaults,_netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=45 0 0" >> /etc/fstab

    echo -n "waiting till mount of the shared volume succeeds..."
    until mount.glusterfs $masterName:/$SHARED_VOLUME_NAME $sharedMountPoint 2> /dev/null
    do
        sleep 5
        echo -n "."
    done
    echo ""
}

setupSwarmMaster() {
    echo "Creating the Docker Swarm..."

    local env_file="$SETUP_SCRIPT_PATH/stacks/.env"
    local localMountPoint=$(getSharedVolumeLocalMount)
    local sharedMountPoint=$(getSharedVolumeMount)
    local assistantMountPoint=$(getAssistantVolumeMount)

    # default directories for the container data
    mkdir -p $sharedMountPoint/{traefik,nginx}
    cp $SETUP_SCRIPT_PATH/templates/config/nginx/site.conf $sharedMountPoint/nginx/

    prepareMariadbConfig
    prepareMariadbStorage
    
    # login to hub.docker.com to create the credentials file
    # @todo check if variables are both set, so this is done optionally
    docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_TOKEN

    # initialize swarm, advertise on local interface
    docker swarm init --advertise-addr `getLocalIp`

    # install docker-compose from github, ubuntu has an old version
    # @todo update to newest version, 1.27 has bug with limits.cpus type
    curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # put the token on the shared volume so nodes can join the swarm
    docker swarm join-token worker -q > $sharedMountPoint/join-token.txt

    # shared, encrypted mesh network for all containers on all nodes
    docker network create --opt encrypted --driver overlay traefik-net

    # basic auth password for PhpMyAdmin etc.
    # @todo double-$ required for direct injection in main.yaml: | sed -e s/\\$/\\$\\$/g
    local adminCredentials=$(createBasicCredentials admin $ADMIN_PASSWORD)

    # prepare the .env file, some ENV variables are only set now in the cloud-init boot
    sed -i \
        -e "s#=ACME_MAIL#=$ACME_MAIL#g" \
        -e "s#=ADMIN_CREDENTIALS#=$ADMIN_CREDENTIALS#g" \
        -e "s#=ASSISTANT_VOLUME#=$assistantMountPoint#g" \
        -e "s#CLUSTER_NAME_PREFIX#$CLUSTER_NAME_PREFIX#g" \
        -e "s#=ELASTIC_PASSWORD#=$ELASTIC_PASSWORD#g" \
        -e "s#=MYSQL_ROOT_PASSWORD#=$MYSQL_ROOT_PASSWORD#g" \
        -e "s#=PUBLIC_IP#=$PUBLIC_IP#g" \
        -e "s#=SHARED_VOLUME#=$sharedMountPoint#g" \
        -e "s#=SHARED_VOLUME_LOCAL#=$localMountPoint#g" \
        "$env_file"

    # we don't want to deploy the stack right now but only after the reboot
    # triggered by cloud-init and an additional 5min wait time to give the nodes
    # time to be ready & mount the Gluster volume, to spread the services on the nodes
    echo "#!/bin/bash
    sleep 300
    $SETUP_SCRIPT_PATH/stacks/deploy-main.sh" >> /etc/local/runonce.d/deploy-main-stack.sh
    chmod ug+x /etc/local/runonce.d/deploy-main-stack.sh
}

setupSwarmNode() {
    echo "Joining the Docker Swarm..."
    local sharedMountPoint=$(getSharedVolumeMount)

    waitForFile $sharedMountPoint/join-token.txt
    docker swarm join --token `cat $sharedMountPoint/join-token.txt` $MASTER_IPV4_ADDRESS:2377
}

setupSwarmAssistant() {
    prepareDbSlaveStorage
    prepareLogging

    # this runs right after we joined the swarm, the elastic container will
    # probably not be right up, we also need to reboot -> delay until after
    # reboot & until the container runs
    echo "#!/bin/bash
    . $SETUP_SCRIPT_PATH/scripts/lib.sh
    setElasticPasswords $ELASTIC_PASSWORD" >> /etc/local/runonce.d/set-elastic-passwords.sh
    chmod ug+x /etc/local/runonce.d/set-elastic-passwords.sh   
}

# $1 - elastic bootstrap pw
setElasticPasswords() {
    local assistantMountPoint=$(getAssistantVolumeMount)
    local kibanaPW=$(cat $assistantMountPoint/logging/kibana.pw)
    local logstashPW=$(cat $assistantMountPoint/logging/logstash.pw)

    waitForContainer "es-logging"
    local elasticContainer=$(getContainerIdByName "es-logging")

    echo "setting passwords for elastic search users..."
    echo "using elastic:$1, kibana:$kibanaPW and logstash_system:$logstashPW"
    docker exec -it $elasticContainer curl -XPOST -H "Content-Type: application/json" http://localhost:9200/_security/user/kibana/_password -d "{ \"password\": \"$kibanaPw\" }" --user "elastic:$1"
    docker exec -it $elasticContainer curl -XPOST -H "Content-Type: application/json" http://localhost:9200/_security/user/logstash_system/_password -d "{ \"password\": \"$logstashPw\" }" --user "elastic:$1"
    docker exec -it $elasticContainer curl -XPOST -H "Content-Type: application/json" http://localhost:9200/_security/user/elastic/_password -d "{ \"password\": \"$ELASTIC_PASSWORD\" }" --user "elastic:$1"

    rm $assistantMountPoint/logging/kibana.pw $assistantMountPoint/logging/logstash.pw

    waitForContainer "kibana"
    local kibanaContainer=$(getContainerIdByName "kibana")
    docker exec -it $kibanaContainer curl -XPOST -D- -H "Content-Type: application/json" http://localhost:5601/api/saved_objects/index-pattern -H 'kbn-version: 7.10.0' -d '{"attributes":{"title":"logstash-*","timeFieldName":"@timestamp"}}' --user "elastic:$1"
}
