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
    - ${hcloud_ssh_key.root.public_key}
  groups:
    - ubuntu
  sudo:
    - ALL=(ALL) NOPASSWD:ALL

runcmd:
 - export LOCAL_IP_RANGE=${var.ip_range}
 - export GLUSTER_VOLUME=container-data
 - export CLOUD_VOLUME_ID=${hcloud_volume.storage.id}
 - export STORAGE_MOUNT=/mnt/storage
 - git clone https://github.com/j-schumann/tf-dockerswarm.git /root/terraform-init
 - echo "$LOCAL_IP_RANGE $GLUSTER_VOLUME $CLOUD_VOLUME_ID $STORAGE_MOUNT" >> /root/envvars

power_state:
  delay: "now"
  mode: reboot
  message: First reboot after cloud-init
  condition: True

final_message: "cloud-init finished after $UPTIME seconds"
