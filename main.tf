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
  name        = "swarmmaster"
  image       = var.os_image
  server_type = var.master_type
  location    = var.location
  user_data   = templatefile("${path.module}/user-data/master.tpl", {
    acme_mail           = var.acme_mail
    gluster_volume      = var.volume_name
    ip_range            = var.ip_range,
    mysql_root_password = var.mysql_root_password
    node_type           = var.master_type
    public_ip           = hcloud_floating_ip.public_ip.ip_address
    ssh_public_key      = hcloud_ssh_key.root.public_key,
    volume_id           = hcloud_volume.storage.id
  })
  ssh_keys    = [ hcloud_ssh_key.root.id ]
}

resource "hcloud_volume" "storage" {
  name     = var.volume_name
  location = var.location
  size     = var.volume_size
  format   = "xfs"
}

resource "hcloud_volume_attachment" "storage_attachment" {
  volume_id = hcloud_volume.storage.id
  server_id  = hcloud_server.master.id
  automount  = false
}

resource "hcloud_server_network" "master_network" {
  server_id  = hcloud_server.master.id
  subnet_id  = hcloud_network_subnet.subnet.id
}

resource "hcloud_floating_ip_assignment" "master_floating_ip" {
  floating_ip_id = hcloud_floating_ip.public_ip.id
  server_id      = hcloud_server.master.id
}

# Worker Setup
resource "hcloud_server" "node" {
  count       = var.node_count
  name        = "swarmnode-${count.index + 1}"
  image       = var.os_image
  server_type = var.node_type
  location    = var.location
  user_data   = templatefile("${path.module}/user-data/node.tpl", {
    gluster_volume = var.volume_name
    ip_range       = var.ip_range,
    node_type      = var.node_type
    master_ip      = hcloud_server_network.master_network.ip
    ssh_public_key = hcloud_ssh_key.root.public_key,
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