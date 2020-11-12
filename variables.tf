# Set the variable value in *.tfvars file
# or using the -var="hcloud_token=..." CLI option
variable "hcloud_token" {}

variable "acme_mail" {}

variable "mysql_root_password" {}

variable "os_image" {
    default = "ubuntu-20.04"
}

variable "master_type" {
    default = "cpx21"
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
