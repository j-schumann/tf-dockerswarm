provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "root" {
  name = "devops"
  public_key = file("${path.module}/ssh/key.pub")
}

# Network Setup
resource "hcloud_floating_ip" "public_ip" {
  type          = "ipv4"
  name          = "public-ip"
  home_location = var.location
}

resource "hcloud_network" "network" {
  name     = "network-1"
  ip_range = var.ip_range
}

resource "hcloud_network_subnet" "subnet" {
  network_id   = hcloud_network.network.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.ip_range
}

# Master Setup
resource "hcloud_server" "master" {
  name        = "${var.cluster_name_prefix}master"
  image       = var.os_image
  server_type = var.master_type
  location    = var.location
  user_data   = templatefile("${path.module}/user-data/master.tpl", {
    acme_mail             = var.acme_mail
    admin_password        = var.admin_password
    assistant_volume_name = var.assistant_volume_name
    cluster_name_prefix   = var.cluster_name_prefix
    docker_hub_user       = var.docker_hub_user
    docker_hub_token      = var.docker_hub_token
    ip_range              = var.ip_range
    msmtp_host            = var.msmtp_host
    msmtp_user            = var.msmtp_user
    msmtp_password        = var.msmtp_password
    mysql_root_password   = var.mysql_root_password
    node_count            = var.node_count
    node_type             = var.master_type
    public_ip             = hcloud_floating_ip.public_ip.ip_address
    setup_script_path     = var.setup_script_path
    shared_volume_id      = hcloud_volume.shared_volume.id
    shared_volume_name    = var.shared_volume_name
    ssh_public_key        = hcloud_ssh_key.root.public_key
  })
  ssh_keys    = [ hcloud_ssh_key.root.id ]
}

resource "hcloud_volume" "shared_volume" {
  name     = var.shared_volume_name
  location = var.location
  size     = var.shared_volume_size
  format   = "xfs"
}

resource "hcloud_volume_attachment" "shared_volume_attachment" {
  volume_id = hcloud_volume.shared_volume.id
  server_id = hcloud_server.master.id
  automount = false
}

resource "hcloud_server_network" "master_network" {
  server_id  = hcloud_server.master.id
  subnet_id  = hcloud_network_subnet.subnet.id
}

resource "hcloud_floating_ip_assignment" "master_floating_ip" {
  floating_ip_id = hcloud_floating_ip.public_ip.id
  server_id      = hcloud_server.master.id
}

# Assistant Setup
resource "hcloud_server" "assistant" {
  name        = "${var.cluster_name_prefix}assistant"
  image       = var.os_image
  server_type = var.node_type
  location    = var.location
  user_data   = templatefile("${path.module}/user-data/assistant.tpl", {
    assistant_volume_id   = hcloud_volume.assistant_volume.id
    assistant_volume_name = var.assistant_volume_name
    cluster_name_prefix   = var.cluster_name_prefix
    elastic_password      = var.elastic_password
    ip_range              = var.ip_range
    master_ip             = hcloud_server_network.master_network.ip
    msmtp_host            = var.msmtp_host
    msmtp_user            = var.msmtp_user
    msmtp_password        = var.msmtp_password
    node_type             = var.node_type
    setup_script_path     = var.setup_script_path
    shared_volume_name    = var.shared_volume_name
    ssh_public_key        = hcloud_ssh_key.root.public_key
  })
  ssh_keys    = [ hcloud_ssh_key.root.id ] 
}

resource "hcloud_volume" "assistant_volume" {
  name     = var.assistant_volume_name
  location = var.location
  size     = var.assistant_volume_size
  format   = "xfs"
}

resource "hcloud_volume_attachment" "assistant_volume_attachment" {
  volume_id = hcloud_volume.assistant_volume.id
  server_id = hcloud_server.assistant.id
  automount = false
}

resource "hcloud_server_network" "assistant_network" {
  server_id = hcloud_server.assistant.id
  subnet_id = hcloud_network_subnet.subnet.id
}

# Worker Setup
resource "hcloud_server" "node" {
  count       = var.node_count
  name        = "${var.cluster_name_prefix}node-${count.index + 1}"
  image       = var.os_image
  server_type = var.node_type
  location    = var.location
  user_data   = templatefile("${path.module}/user-data/node.tpl", {
    cluster_name_prefix = var.cluster_name_prefix
    ip_range            = var.ip_range
    master_ip           = hcloud_server_network.master_network.ip
    msmtp_host          = var.msmtp_host
    msmtp_user          = var.msmtp_user
    msmtp_password      = var.msmtp_password
    node_type           = var.node_type
    setup_script_path   = var.setup_script_path
    shared_volume_name  = var.shared_volume_name
    ssh_public_key      = hcloud_ssh_key.root.public_key
  })
  ssh_keys    = [ hcloud_ssh_key.root.id ] 
}

resource "hcloud_server_network" "node_network" {
  count     = var.node_count
  server_id = hcloud_server.node[count.index].id
  subnet_id = hcloud_network_subnet.subnet.id
}

output "master_ipv4" {
  description = "Swarmmaster IP address"
  value = hcloud_server.master.ipv4_address
}
output "assistant_ipv4" {
  description = "Swarmassistant IP address"
  value = hcloud_server.assistant.ipv4_address
}

output "node_ips" {
  value = {
    for server in hcloud_server.node :
    server.name => server.ipv4_address
  }
}

output "public_ipv4" {
  description = "Public IP address"
  value = hcloud_floating_ip.public_ip.ip_address
}