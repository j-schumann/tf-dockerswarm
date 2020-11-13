#!/bin/bash

# required variables:
# $PUBLIC_IP = IP address of the swarm master

parent_path=`dirname "$0"`

echo "Setting the floating IP $PUBLIC_IP as default..."
cp $parent_path/../server-files/etc/netplan/60-floating-ip.yaml /etc/netplan/
sed -i "s/PUBLIC_IP/$PUBLIC_IP/g" /etc/netplan/60-floating-ip.yaml
# don't use "netplan apply", the final cloud-init reboot is enough,
# it causes loss of the ens10/enp7s0 interface... 

echo "Setting up security..."
$parent_path/init-security-master.sh

echo "Mounting the attached cloud volume..."
$parent_path/init-storage-mount.sh

echo "Configuring the GlusterFS Server..."
$parent_path/init-gluster-master.sh

echo "Creating the Docker Swarm..."
$parent_path/init-swarm-master.sh
