provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "root" {
  name = "devops"
  public_key = file("${path.module}/ssh/key.pub")
}

# Network Setup
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
  user_data   = templatefile("${path.module}/user-data/master.tpl", {})
  ssh_keys    = [ hcloud_ssh_key.root.id ]
}

resource "hcloud_volume" "storage" {
  name     = "container-data"
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

# Worker Setup
resource "hcloud_server" "node" {
  count       = var.node_count
  name        = "swarmnode-${count.index + 1}"
  image       = var.os_image
  server_type = var.node_type
  location    = var.location
  user_data   = templatefile("${path.module}/user-data/node.tpl", {})
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
