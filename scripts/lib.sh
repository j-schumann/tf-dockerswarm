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
    echo -n "waiting till container with name '$1' exists..."
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

######################
# Setup infrastructure for tasks that are run once after the next reboot,
# executed on all cluster servers.
######################
setupRunOnce() {
    mkdir -p /etc/local/runonce.d/ran
    cp $SETUP_SCRIPT_PATH/templates/usr/local/sbin/runonce.sh /usr/local/sbin/
    chmod ug+x /usr/local/sbin/runonce.sh
    echo "@reboot root /usr/local/sbin/runonce.sh 2>&1 >> /var/log/runonce.log" >> /etc/cron.d/runonce
}

######################
# Executed on all cluster servers for general docker config / optimization
######################
prepareDockerConfig() {
    cp $SETUP_SCRIPT_PATH/templates/etc/sysctl.d/80-docker.conf /etc/sysctl.d/
}

######################
# Executed before deploying the stack, creates the config file used by the 
# DB server on the swarm master and the replication slave on the swarm assistant.
######################
prepareMariadbConfig() {
    local sharedMountPoint=$(getSharedVolumeMount)

    mkdir -p $sharedMountPoint/mariadb/config
    cp $SETUP_SCRIPT_PATH/templates/config/mariadb/my_custom.cnf $sharedMountPoint/mariadb/config/
}

######################
# Executed before deploying the stack, creates the data folder for the DB master.
######################
prepareMariadbStorage() {
    local localMountPoint=$(getSharedVolumeLocalMount)
    mkdir -p $localMountPoint/mariadb

    # required for mariadb to start
    chown -R 1001:1001 $localMountPoint/mariadb
}

######################
# Executed before joining the swarm, creates the data folder for the replication slave.
######################
prepareDbSlaveStorage() {
    echo "preparing folders for the replication slave..."
    local mountPoint=$(getAssistantVolumeMount)
    
    mkdir -p $mountPoint/dbslave

    # required for mariadb to start
    chown -R 1001:1001 $mountPoint/dbslave
}

######################
# Creates folders used for the ELK stack on the swarm assistant. Generates
# passwords for the elasticsearch uses and updates the credentials in the
# config files for the containers. This is executed before joining the swarm
# so all mount points are available and the config is up-to-date so no container
# restart is required.
# The generated passwords are stored on disk so they can be set after the first
# reboot and when the elastic container is up.
######################
prepareLogging() {
    local assistantMountPoint=$(getAssistantVolumeMount)
    mkdir -p $assistantMountPoint/logging/{config,elastic}

    # required for elasticsearch to start
    chown -R 1000:1000 $assistantMountPoint/logging/elastic

    cp -R $SETUP_SCRIPT_PATH/templates/config/logging/* $assistantMountPoint/logging/config/

    # create a password and set it in the config now so we don't need to restart the container
    # also store it in plaintext so we can set it in the container after reboot
    local elasticPW=$(generatePassword)
    echo $elasticPW > $assistantMountPoint/logging/elastic.pw
    sed -i \
        -e "s#ELASTIC_PASSWORD#$elasticPW#g" \
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

prepareBackup() {
    local assistantMountPoint=$(getAssistantVolumeMount)

    cp -R $SETUP_SCRIPT_PATH/templates/config/backup $assistantMountPoint/
    
    // we don't want to set the BACKUP_TARGET in the env file, it would be visible to docker
    // and the swarm master, set it here in the config before running the container
    sed -i "s/BACKUP_TARGET/$BACKUP_TARGET/g" $assistantMountPoint/backup/database/data/conf
    sed -i "s/BACKUP_TARGET/$BACKUP_TARGET/g" $assistantMountPoint/backup/files/data/conf
}

######################
# Enables the UFW with basic rules, denies root login and prepares some config/scripts.
######################
prepareBasicSecurity() {
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    cp $SETUP_SCRIPT_PATH/templates/usr/local/sbin/fail2ban-status.sh /usr/local/sbin/fail2ban-status.sh
    cp $SETUP_SCRIPT_PATH/templates/etc/ufw/applications.d/* /etc/ufw/applications.d/

    # UFW's defaults are to deny all incoming connections and allow all outgoing connections.
    ufw allow OpenSSH

    # protocol ESP is required for Docker swarm on master & nodes 
    ufw allow proto esp from $LOCAL_IP_RANGE to any

    ufw --force enable
}

######################
# Replaces the auto-assigned IP with the given floating IP, which can be protected
# so it does not change with a "terraform apply"
#
# params:
# $1 - floating/public IP to use for the current machine
######################
setPublicIp() {
    echo "Setting the IP $1 as default..."
    cp $SETUP_SCRIPT_PATH/templates/etc/netplan/60-floating-ip.yaml /etc/netplan/
    sed -i "s/PUBLIC_IP/$1/g" /etc/netplan/60-floating-ip.yaml
    # don't use "netplan apply", the final cloud-init reboot is enough,
    # it causes loss of the ens10/enp7s0 interface... 
}

######################
# Initialize MSMTP to send emails from cron jobs etc to external mail address.
######################
setupMsmtp() {
    echo "configuring MSMTP to send status mails to external mailbox..."
    cp $SETUP_SCRIPT_PATH/templates/etc/msmtprc /etc/
    sed -i \
        -e "s#MSMTP_HOST#$MSMTP_HOST#g" \
        -e "s#MSMTP_USER#$MSMTP_USER#g" \
        -e "s#MSMTP_PASSWORD#$MSMTP_PASSWORD#g" \
        "/etc/msmtprc"

    systemctl enable msmtpd
    systemctl start msmtpd
}

######################
# Allow ports for swarm management, requires ufw config from prepareBasicSecurity.
######################
setupSwarmMasterUfw() {
    echo "configuring UFW to allow Docker swarm management..."

    ufw allow from $LOCAL_IP_RANGE to any app "Docker Manager"
}

######################
# Allow ports for swarm, requires ufw config from prepareBasicSecurity.
######################
setupSwarmNodeUfw() {
    echo "configuring UFW to allow Docker swarm participation..."

    ufw allow from $LOCAL_IP_RANGE to any app "Docker Node"
}

######################
# Allow all cluster servers to access our volumes, requires ufw config from
# prepareBasicSecurity.
######################
setupGlusterServerUfw() {
    echo "configuring UFW to allow Gluster management..."
    ufw allow from $LOCAL_IP_RANGE to any app Gluster
}

######################
# Mounts the cloud volume for the shared data now and automatically after reboot.
######################
setupSharedVolume() {
    echo "mounting the attached cloud storage $SHARED_VOLUME_NAME ($SHARED_VOLUME_ID)"
    local mountPoint=$(getSharedVolumeLocalMount)
    mkdir -p $mountPoint

    echo "/dev/disk/by-id/scsi-0HC_Volume_$SHARED_VOLUME_ID $mountPoint xfs discard,nofail,defaults 0 0" >> /etc/fstab
    mount -o discard,defaults /dev/disk/by-id/scsi-0HC_Volume_$SHARED_VOLUME_ID $mountPoint
}

######################
# Mounts the attached cloud volume for assistant specific data (elasticsearch
# for logging, dbslave for backup including binlog) now and for automatic mount
# after reboot.
######################
setupAssistantVolume() {
    echo "mounting the attached cloud storage $ASSISTANT_VOLUME_NAME ($ASSISTANT_VOLUME_ID)"
    local mountPoint=$(getAssistantVolumeMount)
    mkdir -p $mountPoint

    echo "/dev/disk/by-id/scsi-0HC_Volume_$ASSISTANT_VOLUME_ID $mountPoint xfs discard,nofail,defaults 0 0" >> /etc/fstab
    mount -o discard,defaults /dev/disk/by-id/scsi-0HC_Volume_$ASSISTANT_VOLUME_ID $mountPoint
}

######################
# Initializes the sharing of the attached cloud volume via GlusterFS with
# the other cluster servers.
######################
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

######################
# Executed on the swarm nodes & assistant to access the Gluster volume
# with the shared container data & config
######################
setupGlusterClient() {
    local sharedMountPoint=$(getSharedVolumeMount)
    local masterName=${CLUSTER_NAME_PREFIX}master

    mkdir -p $sharedMountPoint

    # mounting via "ip:/volume" is not allowed -> use the hostname
    echo "$MASTER_IPV4_ADDRESS $masterName" >> /etc/hosts

    # mount the shared volume now and also automatically when accessed
    echo "$masterName:/$SHARED_VOLUME_NAME $sharedMountPoint glusterfs defaults,_netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=45 0 0" >> /etc/fstab

    echo -n "waiting till mount of the shared volume succeeds..."
    until mount.glusterfs $masterName:/$SHARED_VOLUME_NAME $sharedMountPoint 2> /dev/null
    do
        sleep 5
        echo -n "."
    done
    echo ""
}

######################
# Runs only on the swarm master, initializes the all shared folders in the
# Gluster volume, creates the shared network & the Docker swarm.
# Updates the .env template with credentials & calculated paths and schedules
# the deployment of the main stack after the first reboot.
######################
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
        -e "s#=ADMIN_CREDENTIALS#=$adminCredentials#g" \
        -e "s#=ASSISTANT_VOLUME#=$assistantMountPoint#g" \
        -e "s#CLUSTER_NAME_PREFIX#$CLUSTER_NAME_PREFIX#g" \
        -e "s#=ELASTIC_PASSWORD#=$ELASTIC_PASSWORD#g" \
        -e "s#=MYSQL_ROOT_PASSWORD#=$MYSQL_ROOT_PASSWORD#g" \
        -e "s#=PUBLIC_IP#=$PUBLIC_IP#g" \
        -e "s#=SHARED_VOLUME#=$sharedMountPoint#g" \
        -e "s#=VOLUME_LOCAL#=$localMountPoint#g" \
        "$env_file"

    # we don't want to deploy the stack right now but only after the reboot
    # triggered by cloud-init and an additional 5min wait time to give the nodes
    # time to be ready & mount the Gluster volume, to spread the services on the nodes
    echo "#!/bin/bash
    sleep 300
    $SETUP_SCRIPT_PATH/stacks/deploy-main.sh" >> /etc/local/runonce.d/deploy-main-stack.sh
    chmod ug+x /etc/local/runonce.d/deploy-main-stack.sh
}

######################
# Runs on swarm nodes and the swarm assistant.
# Simply joins the Docker swarm, depends on the shared Gluster volume to be
# available.
######################
setupSwarmNode() {
    echo "Joining the Docker Swarm..."
    local sharedMountPoint=$(getSharedVolumeMount)

    waitForFile $sharedMountPoint/join-token.txt
    docker swarm join --token `cat $sharedMountPoint/join-token.txt` $MASTER_IPV4_ADDRESS:2377
}

######################
# Runs after setupSwarmNode to trigger additional tasks only for the assistant.
######################
setupSwarmAssistant() {
    # this runs right after we joined the swarm, the elastic container will
    # probably not be right up, we also need to reboot -> delay until after
    # reboot & until the container runs
    echo "#!/bin/bash
    . $SETUP_SCRIPT_PATH/scripts/lib.sh
    sleep 180 # give the machine some time to start Docker etc
    initLoggingContainers $ELASTIC_PASSWORD" >> /etc/local/runonce.d/set-elastic-passwords.sh
    chmod ug+x /etc/local/runonce.d/set-elastic-passwords.sh   
}


######################
# $1 username
# $2 new password
# $3 current elastic pw
######################
setElasticPassword() {
    local elasticContainer=$(getContainerIdByName "es-logging")
    docker exec -t $elasticContainer curl -XPOST -H "Content-Type: application/json" \
        http://localhost:9200/_security/user/$1/_password \
        -d "{ \"password\": \"$2\" }" --user "elastic:$3" --fail \
        >/dev/null && echo "success" || echo "error"
}

######################
# $1 current elastic pw
######################
initKibana() {
    local kibanaContainer=$(getContainerIdByName "kibana")

    # @todo kbn-version header is required and must match the Kibana version
    # @todo error "http://... No such file or directory" - why cant the URL go on a new line, it works in the function above?
    docker exec -t $kibanaContainer curl -XPOST -H "Content-Type: application/json" http://localhost:5601/api/saved_objects/index-pattern \
        -d '{"attributes":{"title":"logstash-*","timeFieldName":"@timestamp"}}' \
        -H 'kbn-version: 7.7.1' --user "elastic:$1" --fail \
        >/dev/null && echo "success" || echo "error"
}

######################
# Executed via runonce after the swarm assistant reboots.
# Uses the previously configured passwords (@see prepareLogging) to set the
# passwords inside the elasticsearch container. Also creates the first index
# pattern in Kibana.
#
# params:
# $1 - elastic bootstrap pw
######################
initLoggingContainers() {
    local assistantMountPoint=$(getAssistantVolumeMount)
    local elasticPW=$(cat $assistantMountPoint/logging/elastic.pw)
    local kibanaPW=$(cat $assistantMountPoint/logging/kibana.pw)
    local logstashPW=$(cat $assistantMountPoint/logging/logstash.pw)

    waitForContainer "es-logging"

    echo -n "setting kibana user pw..."
    while [ "success" != "$(setElasticPassword kibana $kibanaPW $1)" ]; do
        sleep 10
        echo -n "."
    done
    echo ""

    echo -n "setting logstash user pw..."
    while [ "success" != "$(setElasticPassword logstash_system $logstashPW $1)" ]; do
        sleep 10
        echo -n "."
    done
    echo ""

    echo -n "setting elastic user pw..."
    while [ "success" != "$(setElasticPassword elastic $elasticPW $1)" ]; do
        sleep 10
        echo -n "."
    done
    echo ""

    waitForContainer "kibana"

    echo -n "setting kibana index pattern..."
    while [ "success" != "$(initKibana $elasticPW)" ]; do
        sleep 10
        echo -n "."
    done
    echo ""

    printf "Subject: new ES credentials\nThe new Elasticsearch credentials on $(hostname) are: elastic // $elasticPW" | /usr/sbin/sendmail root

    # remove the PW files, the PWs are still readable in the config files
    # the ELASTIC_PASSWORD ist still in /etc/local/runonce.d/ran but outdated,
    # it was only used for bootstrapping
    rm $assistantMountPoint/logging/{elastic,kibana,logstash}.pw
}
