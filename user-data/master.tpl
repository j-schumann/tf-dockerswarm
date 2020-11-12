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
  - glusterfs-server
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
 - echo 'ACME_MAIL="${acme_mail}"' >> /etc/environment
 - echo 'CLOUD_VOLUME_ID="${volume_id}"' >> /etc/environment
 - echo 'GLUSTER_VOLUME="${gluster_volume}"' >> /etc/environment
 - echo 'LOCAL_IP_RANGE="${ip_range}"' >> /etc/environment
 - echo 'NODE_TYPE="${node_type}"' >> /etc/environment
 - echo 'PUBLIC_IP="${public_ip}"' >> /etc/environment
 - echo 'STORAGE_MOUNT="/mnt/storage"' >> /etc/environment
 - set -a; source /etc/environment; set +a;
 - export ADMIN_PASSWORD=${admin_password}
 - export MSMTP_HOST=${msmtp_host}
 - export MSMTP_USER=${msmtp_user}
 - export MSMTP_PASSWORD=${msmtp_password}
 - export MYSQL_ROOT_PASSWORD=${mysql_root_password}
 # load scripts & files from git, user-data can be limited to 16KB
 - git clone https://github.com/j-schumann/tf-dockerswarm.git /root/terraform-init
 - /root/terraform-init/scripts/setup-master.sh

power_state:
  delay: "now"
  mode: reboot
  message: First reboot by cloud-init
  condition: True
