terraform {
  required_version = ">= 0.12"
}


variable "vpc_cidr" {
  default = "172.16.0.0/16"
}

variable "subnet1_cidr" {
  default = "172.16.0.0/24"
}

provider "aws" {
  region = "us-east-2"
}

# VPC
resource "aws_vpc" "vpc1" {
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = "true"
    # enable_dns_support = "true
}

# Subnet
resource "aws_subnet" "subnet1" {
    cidr_block = var.subnet1_cidr
    vpc_id = aws_vpc.vpc1.id
    availability_zone = data.aws_availability_zones.available.names[0]
}

# IGW
resource "aws_internet_gateway" "igw1" {
    vpc_id = aws_vpc.vpc1.id
}

# Route Table
resource "aws_route_table" "rt1" {
    vpc_id = aws_vpc.vpc1.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw1.id
    }
}

resource "aws_route_table_association" "route-subnet1" {
  subnet_id = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt1.id
}

# Security Group
resource "aws_security_group" "sg1" {
    name = "example-app"
    vpc_id = aws_vpc.vpc1.id
    
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

}



# EC2
resource "aws_instance" "example_app" {
  ami = "ami-09f85f3aaae282910"
  instance_type = "t3.medium"
  subnet_id = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.sg1.id]
}

resource "aws_ec2_instance_connect_endpoint" "endpit1" {
  subnet_id = aws_subnet.subnet1.id
}

# EIP

# //////////////////////
# Data
# //////////////////////

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
data "aws_availability_zones" "available" {
  state = "available"
}