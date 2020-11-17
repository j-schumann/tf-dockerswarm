#cloud-config

apt:
  sources:
    docker.list:
      source: deb [arch=amd64] https://download.docker.com/linux/ubuntu $RELEASE stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

package_update: true
package_upgrade: true

packages:
  - bc
  - curl
  - docker-ce
  - docker-ce-cli
  - fail2ban
  - git
  - glusterfs-client
  - logrotate
  - m4
  - make
  - mc
  - msmtp
  - msmtp-mta
  - rsync
  - rsyslog
  - sudo
  - ufw
  - unattended-upgrades
  - unzip
  - wget

# create the docker group
groups:
  - docker

# Add default auto created user to docker group
system_info:
  default_user:
    groups: [docker]

users:
- name: jschumann
  gecos: Jakob Schumann
  lock_passwd: true
  shell: /bin/bash
  ssh-authorized-keys:
    - ${ssh_public_key}
  groups:
    - ubuntu
  sudo:
    - ALL=(ALL) NOPASSWD:ALL

runcmd:
 # set persistent env vars
 - echo 'CLUSTER_NAME_PREFIX="${cluster_name_prefix}"' >> /etc/environment
 - echo 'LOCAL_IP_RANGE="${ip_range}"' >> /etc/environment
 - echo 'MASTER_IPV4_ADDRESS="${master_ip}"' >> /etc/environment
 - echo 'NODE_TYPE="${node_type}"' >> /etc/environment
 - echo 'SETUP_SCRIPT_PATH="${setup_script_path}"' >> /etc/environment
 - echo 'SHARED_VOLUME_NAME="${shared_volume_name}"' >> /etc/environment
 - for env in $( cat /etc/environment ); do export $(echo $env | sed -e 's/"//g'); done
 # set env vars we only use during first boot
 - export MSMTP_HOST=${msmtp_host}
 - export MSMTP_USER=${msmtp_user}
 - export MSMTP_PASSWORD=${msmtp_password}
 # load scripts & files from git, user-data can be limited to 16KB
 - git clone https://github.com/j-schumann/tf-dockerswarm.git $SETUP_SCRIPT_PATH
 - $SETUP_SCRIPT_PATH/scripts/setup-node.sh

power_state:
  delay: "now"
  mode: reboot
  message: First reboot after cloud-init
  condition: True
