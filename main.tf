variable region {}
variable cidr_block {}
variable cidr_block_public {}
variable cidr_block_private {}
variable availability_zone {}
variable ip_eth0 {}
variable ip_eth1 {}
variable ip_eth2 {}
variable ip_eth3 {}
variable ami {}
variable instance_type {}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.41.0"
    }
  }
}

# configuration le provider AWS
provider "aws" {
  region = var.region
}

# création d'un vpc
resource "aws_vpc" "vpc-k8s-wp" {
    cidr_block = var.cidr_block
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = {
        Name = "vpc-k8s-wp"
    }
}

# création d'un sous-réseau public
resource "aws_subnet" "subnet-public-k8s-wp" {
    vpc_id = aws_vpc.vpc-k8s-wp.id
    cidr_block = var.cidr_block_public
    availability_zone = var.availability_zone
    map_public_ip_on_launch = true
    tags = {
        Name = "subnet-public-k8s-wp"
    }
}

# cration d'un sous-réseau privé
resource "aws_subnet" "subnet-private-k8s-wp" {
    vpc_id = aws_vpc.vpc-k8s-wp.id
    cidr_block = var.cidr_block_private
    availability_zone = var.availability_zone
    map_public_ip_on_launch = false
    tags = {
        Name = "subnet-private-k8s-wp"
    }
}

# création d'une gateway
resource "aws_internet_gateway" "igw-k8s-wp" {

    vpc_id = aws_vpc.vpc-k8s-wp.id
    tags = {
        Name = "igw-k8s-wp"
    }
}

# création d'une table de routage pour le réseau public
resource "aws_route_table" "tbr-public-k8s-wp" {

    vpc_id = aws_vpc.vpc-k8s-wp.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw-k8s-wp.id
    }

    tags = {
        Name = "tbr--public-k8s-wp"
    }
}

# création d'une table de routage pour le réseau privé
resource "aws_route_table" "tbr-private-k8s-wp" {

    vpc_id = aws_vpc.vpc-k8s-wp.id

    route {
        cidr_block = var.cidr_block
        gateway_id = "local"
    }

    tags = {
        Name = "tbr-private-k8s-wp"
    }
}

# associer la table de rouatge avec le sous-réseau public
resource "aws_route_table_association" "tbr-associer-subnet-pubic-k8s-wp" {
    subnet_id = aws_subnet.subnet-public-k8s-wp.id
    route_table_id = aws_route_table.tbr-public-k8s-wp.id
}

# associer la table de rouatge avec le sous-réseau privé
resource "aws_route_table_association" "tbr-associer-subnet-private-k8s-wp" {
    subnet_id = aws_subnet.subnet-private-k8s-wp.id
    route_table_id = aws_route_table.tbr-private-k8s-wp.id
}

# création d'un groupe de sécurité pour le réseau public
resource "aws_security_group" "gs-k8s-wp" {
    vpc_id = aws_vpc.vpc-k8s-wp.id

    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "gs-k8s-wp"
        Description = "gs-k8s-wp pour le reseau public"
    }
}

# création d'un groupe de sécurité privé
resource "aws_security_group" "gs-k8s-wp-private" {
    vpc_id = aws_vpc.vpc-k8s-wp.id

    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 6443
        to_port = 6443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "gs-k8s-wp-private"
        Description = "gs-k8s-wp pour le reseau private"
    }
}

# Création d'une adresse IP élastique pour le master
resource "aws_eip" "elastic_ip" {
  domain = "vpc"
}

# Création d'une adresse IP élastique pour le worker
resource "aws_eip" "elastic_ip-2" {
  domain = "vpc"
}

# Création d'une interface réseau pour le sous-réseau public avec l'adresse IP élastique
resource "aws_network_interface" "eth0" {
  subnet_id = aws_subnet.subnet-public-k8s-wp.id
  private_ips = [var.ip_eth0]
  security_groups = [aws_security_group.gs-k8s-wp.id]
}

resource "aws_eip_association" "elastic_ip_assoc" {
  network_interface_id = aws_network_interface.eth0.id
  allocation_id = aws_eip.elastic_ip.id
}

# Création d'une interface réseau pour le sous-réseau privé
resource "aws_network_interface" "eth1" {
  subnet_id = aws_subnet.subnet-private-k8s-wp.id
  private_ips = [var.ip_eth1]
  security_groups = [aws_security_group.gs-k8s-wp-private.id]
}

# création d'une instance EC2 - Master
resource "aws_instance" "ec2-master" {
    ami = var.ami 
    instance_type = var.instance_type
    key_name = "cle-k8s-wp"

    network_interface {
        network_interface_id = aws_network_interface.eth0.id
        device_index = 0
    }

    network_interface {
        network_interface_id = aws_network_interface.eth1.id
        device_index = 1
    }

    tags = {
        Name = "ec2-master"
    }
}

# Création d'une interface réseau pour le sous-réseau public avec l'adresse IP élastique 2
resource "aws_network_interface" "eth2" {
  subnet_id = aws_subnet.subnet-public-k8s-wp.id
  private_ips = [var.ip_eth2]
  security_groups = [aws_security_group.gs-k8s-wp.id]
}

resource "aws_eip_association" "elastic_ip_assoc-2" {
  network_interface_id = aws_network_interface.eth2.id
  allocation_id = aws_eip.elastic_ip-2.id
}

# Création d'une interface réseau pour le sous-réseau privé
resource "aws_network_interface" "eth3" {
  subnet_id = aws_subnet.subnet-private-k8s-wp.id
  private_ips = [var.ip_eth3]
  security_groups = [aws_security_group.gs-k8s-wp-private.id]
}

# création d'une instance EC2 - Worker
resource "aws_instance" "ec2-worker" {
    ami = var.ami
    instance_type = var.instance_type
    key_name = "cle-k8s-wp"

    network_interface {
        network_interface_id = aws_network_interface.eth2.id
        device_index = 0
    }

    network_interface {
        network_interface_id = aws_network_interface.eth3.id
        device_index = 1
    }

    tags = {
        Name = "ec2-worker"
    }
}

