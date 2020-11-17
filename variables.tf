# Set the variable value in *.tfvars file
# or using the -var="hcloud_token=..." CLI option
variable "hcloud_token" {}

# further variables that hold credentials/private data and have no defaults 
variable "acme_mail" {}
variable "admin_password" {}
variable "docker_hub_user" {}
variable "docker_hub_token" {}
variable "elastic_password" {}
variable "msmtp_host" {}
variable "msmtp_user" {}
variable "msmtp_password" {}
variable "mysql_root_password" {}

# variables to customize the cluster
variable "cluster_name_prefix" {
    default = "swarm"
}

variable "master_type" {
    default = "cx21"
}

variable "node_type" {
    default = "cx11"
}

variable "node_count" {
    default = "1"
}

variable "location" {
    default = "fsn1"
}

variable "shared_volume_size" {
    default = "10"
}

variable "assistant_volume_size" {
    default = "10"
}

# variables that probably dont need to be modified
variable "ip_range" {
    default = "10.0.0.0/24"
}

variable "shared_volume_name" {
    default = "shared-data"
}

variable "assistant_volume_name" {
    default = "assistant-data"
}

variable "os_image" {
    default = "ubuntu-20.04"
}

variable "setup_script_path" {
    default = "/root/setup"
}