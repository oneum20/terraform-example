terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = "us-east-2"
}

locals {
    az_len = length(data.aws_availability_zones.available.names)
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
    availability_zone   = data.aws_availability_zones.available.names[count.index % local.az_len]   
}

resource "aws_subnet" "subnet_app" {
    count = length(var.subnet_cidrs.app)

    cidr_block          = var.subnet_cidrs.app[count.index]
    vpc_id              = aws_vpc.vpc1.id
    availability_zone   = data.aws_availability_zones.available.names[count.index % local.az_len]
}

resource "aws_subnet" "subnet_db" {
    count = length(var.subnet_cidrs.db)

    cidr_block          = var.subnet_cidrs.db[count.index]
    vpc_id              = aws_vpc.vpc1.id
    availability_zone   = data.aws_availability_zones.available.names[count.index % local.az_len]
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
resource "aws_lb_target_group" "tg" {
    name        = "tf-app-lb-tg"
    port        = 80
    protocol    = "HTTP"
    vpc_id      = aws_vpc.vpc1.id
}

resource "aws_autoscaling_attachment" "asg_atch" {
  autoscaling_group_name = aws_autoscaling_group.asg1.id
  lb_target_group_arn    = aws_lb_target_group.tg.arn
}

resource "aws_lb" "alb"{
    name                = "tf-app-lb"
    internal            = false
    load_balancer_type  = "application"
    security_groups     = [aws_security_group.sg_alb.id]
    subnets             = [for o in aws_subnet.subnet_public : o.id]
}

resource "aws_lb_listener" "lb_lnr1" {
    load_balancer_arn   = aws_lb.alb.arn
    port                = 80
    protocol            = "HTTP"


    default_action {
        type                = "forward"
        target_group_arn    = aws_lb_target_group.tg.arn
    }
}

# EIP
resource "aws_eip" "eip1" {
  domain = "vpc"
}


# ASG
resource "aws_launch_template" "app" {
    name_prefix             = "app"
    image_id                = "ami-09f85f3aaae282910"
    instance_type           = "t2.micro"
    vpc_security_group_ids  = [aws_security_group.sg_example_app.id]

    user_data               = "${base64encode(data.template_file.bootstrap.rendered)}"
    
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "asg1" {
    max_size            = 5
    min_size            = 1
    desired_capacity    = 3

    vpc_zone_identifier = [for o in aws_subnet.subnet_app : o.id]

    launch_template {
        id      = aws_launch_template.app.id
        version = aws_launch_template.app.latest_version
    }
}

resource "aws_ec2_instance_connect_endpoint" "endpt" {
    subnet_id = aws_subnet.subnet_app[0].id
}

# Scaling Policy
resource "aws_autoscaling_policy" "scale_down" {
    name                   = "tf_scale_down"
    autoscaling_group_name = aws_autoscaling_group.asg1.name
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = -1
    cooldown               = 120
}
resource "aws_autoscaling_policy" "scale_up" {
    name                   = "tf_scale_down"
    autoscaling_group_name = aws_autoscaling_group.asg1.name
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = 1
    cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "scale_down" {
    alarm_description   = "Monitors CPU utilization for Terramino ASG"
    alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
    alarm_name          = "tf_scale_down"
    comparison_operator = "LessThanOrEqualToThreshold"
    namespace           = "AWS/EC2"
    metric_name         = "CPUUtilization"
    threshold           = "10"
    evaluation_periods  = "2"
    period              = "120"
    statistic           = "Average"

    dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.asg1.name
    }
}

resource "aws_cloudwatch_metric_alarm" "scale_up" {
    alarm_description   = "Monitors CPU utilization for Terramino ASG"
    alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
    alarm_name          = "tf_scale_up"
    comparison_operator = "GreaterThanThreshold"
    namespace           = "AWS/EC2"
    metric_name         = "CPUUtilization"
    threshold           = "10"
    evaluation_periods  = "2"
    period              = "120"
    statistic           = "Average"

    dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.asg1.name
    }
}

# RDS for Aurora

# ElastiCache



# //////////////////////
# Data
# //////////////////////

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
data "aws_availability_zones" "available" {
  state = "available"
}

data "template_file" "bootstrap" {
    template = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl enable httpd
              sudo systemctl start httpd
              EOF
}