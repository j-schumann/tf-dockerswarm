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
  - libarray-unique-perl
  - libdbd-mysql-perl
  - libfile-slurp-perl
  - liblist-moreutils-perl
  - libmodule-install-perl
  - libmonitoring-plugin-perl
  - libnumber-format-perl
  - libreadonly-xs-perl
  - logrotate
  - m4
  - make
  - mc
  - monitoring-plugins
  - msmtp
  - msmtp-mta
  - nagios-plugins-contrib
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
 - export GLUSTER_VOLUME=${gluster_volume}
 - export LOCAL_IP_RANGE=${ip_range}
 - export MASTER_IPV4_ADDRESS=${master_ip}
 # load scripts & files from git, user-data can be limited to 16KB
 - git clone https://github.com/j-schumann/tf-dockerswarm.git /root/terraform-init
 - /root/terraform-init/scripts/setup-node.sh
 - echo "$LOCAL_IP_RANGE $GLUSTER_VOLUME $MASTER_IPV4_ADDRESS" >> /root/envvars

power_state:
  delay: "now"
  mode: reboot
  message: First reboot after cloud-init
  condition: True

final_message: "cloud-init finished after $UPTIME seconds"
