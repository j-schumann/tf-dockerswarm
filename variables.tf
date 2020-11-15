# Set the variable value in *.tfvars file
# or using the -var="hcloud_token=..." CLI option
variable "hcloud_token" {}

# further variables that hold credentials etc and have no defaults 
variable "acme_mail" {}
variable "admin_password" {}
variable "docker_hub_user" {}
variable "docker_hub_token" {}
variable "msmtp_host" {}
variable "msmtp_user" {}
variable "msmtp_password" {}
variable "mysql_root_password" {}

# variables to customize the cluster
variable "os_image" {
    default = "ubuntu-20.04"
}

variable "name_prefix" {
    default = "swarm"
}

variable "master_type" {
    default = "cx21"
}

variable "node_type" {
    default = "cx11"
}

variable "node_count" {
    default = "2"
}

variable "location" {
    default = "fsn1"
}

variable "ip_range" {
    default = "10.0.0.0/24"
}

variable "volume_name" {
    default = "container-data"
}

variable "volume_size" {
    default = "10"
}
