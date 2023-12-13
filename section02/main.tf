terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = "us-east-2"
}


# //////////////////////
# Variable
# //////////////////////

variable "vpc_cidr" {
    type    = string
    default = "172.16.0.0/16"
}
variable "subnet_cidrs" {
    type = map(list(string))

    default = {        
        app    : ["172.16.0.0/24", "172.16.1.0/24"],
        db     : ["172.16.2.0/24", "172.16.3.0/24"],
        public : ["172.16.4.0/24", "172.16.5.0/24"]
    }
}
variable "rds_username" {
    type = string
}
variable "rds_password" {
    type = string
}


# //////////////////////
# Resource
# //////////////////////

# VPC
resource "aws_vpc" "vpc1" {
    cidr_block              = var.vpc_cidr
    enable_dns_hostnames    = true
}

# Subnet
resource "aws_subnet" "subnet_public" {
    count = length(var.subnet_cidrs.public)

    cidr_block          = var.subnet_cidrs.public[count.index]
    vpc_id              = aws_vpc.vpc1.id
    availability_zone   = data.aws_availability_zones.available.names[count.index]    
}

resource "aws_subnet" "subnet_app" {
    count = length(var.subnet_cidrs.app)

    cidr_block          = var.subnet_cidrs.app[count.index]
    vpc_id              = aws_vpc.vpc1.id
    availability_zone   = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "subnet_db" {
    count = length(var.subnet_cidrs.db)

    cidr_block          = var.subnet_cidrs.db[count.index]
    vpc_id              = aws_vpc.vpc1.id
    availability_zone   = data.aws_availability_zones.available.names[count.index]
}

resource "aws_nat_gateway" "ngt1" {
    allocation_id = aws_eip.eip1.id
    subnet_id     = aws_subnet.subnet_public[0].id

    tags = {
        Name = "gw NAT"
    }

    depends_on = [aws_internet_gateway.igw1]
}

# IGW
resource "aws_internet_gateway" "igw1" {
    vpc_id = aws_vpc.vpc1.id
}

# Route Table
resource "aws_route_table" "rt_public" {
    vpc_id = aws_vpc.vpc1.id

    route{
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw1.id
    }
}
resource "aws_route_table" "rt_app" {
    vpc_id = aws_vpc.vpc1.id

    route{
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.ngt1.id
    }
}

resource "aws_route_table_association" "rta_public" {
    subnet_id       = each.value.id
    route_table_id  = aws_route_table.rt_public.id

    for_each = { for k, v in aws_subnet.subnet_public : k => v}
}

resource "aws_route_table_association" "rta_app" {
    subnet_id       = each.value.id
    route_table_id  = aws_route_table.rt_app.id

    for_each = { for k, v in aws_subnet.subnet_app : k => v}
}

# Security Group
resource "aws_security_group" "sg_alb" {
    name    = "security-group-alb"
    vpc_id  = aws_vpc.vpc1.id

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "sg_ssh" {
    name = "security-group-ssh"
    vpc_id = aws_vpc.vpc1.id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

}

resource "aws_security_group" "sg_example_app" {
    name    = "security-group-example-app"
    vpc_id  = aws_vpc.vpc1.id

    ingress {
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        security_groups = [aws_security_group.sg_alb.id]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# ELB
resource "aws_lb_target_group" "lb_tg1" {
    name        = "alb-target-group1"
    port        = 80
    protocol    = "HTTP"
    vpc_id      = aws_vpc.vpc1.id
}

resource "aws_lb_target_group_attachment" "lb_tg_at1" {
    for_each = {
        for k, v in aws_instance.example_app : k => v
    }

    target_group_arn    = aws_lb_target_group.lb_tg1.arn
    target_id           = each.value.id
    port                = 80
}

resource "aws_lb" "lb1" {
    name                = "lb-example"
    internal            = false
    load_balancer_type  = "application"
    security_groups     = [ aws_security_group.sg_alb.id ]
    subnets             = [for o in aws_subnet.subnet_public : o.id]

    
}

resource "aws_lb_listener" "lb_lnr1" {
    load_balancer_arn = aws_lb.lb1.arn
    port = "80"
    protocol = "HTTP"

    default_action {
      type = "forward"
      target_group_arn = aws_lb_target_group.lb_tg1.arn
    }
}

# EIP
resource "aws_eip" "eip1" {
  domain = "vpc"
}


# EC2
resource "aws_instance" "example_app" {
    count                   = 3 
    ami                     = "ami-09f85f3aaae282910"
    instance_type           = "t3.medium"
    subnet_id               = aws_subnet.subnet_app[0].id
    vpc_security_group_ids  = [aws_security_group.sg_ssh.id, 
                                aws_security_group.sg_example_app.id]
    
    tags = {
        Name = "example-app-${count.index}"
    }

    user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl enable httpd
              sudo systemctl start httpd
              EOF
}
resource "aws_ec2_instance_connect_endpoint" "endpt1" {
    subnet_id = aws_subnet.subnet_app[0].id
}

# RDS
resource "aws_db_subnet_group" "default" {
    name       = "main"
    subnet_ids = [for o in aws_subnet.subnet_db : o.id]
}

resource "aws_db_instance" "default" {
    allocated_storage    = 10
    db_name              = "mydb"
    engine               = "mysql"
    engine_version       = "5.7"
    instance_class       = "db.t3.micro"
    username             = var.rds_username
    password             = var.rds_password
    parameter_group_name = "default.mysql5.7"
    skip_final_snapshot  = true
    multi_az             = true
    db_subnet_group_name = aws_db_subnet_group.default.name
}


# S3
# CloudFront





# //////////////////////
# Data
# //////////////////////

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
data "aws_availability_zones" "available" {
  state = "available"
}