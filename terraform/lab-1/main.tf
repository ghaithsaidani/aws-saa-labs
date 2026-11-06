resource "aws_vpc" "main" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = false
  enable_dns_hostnames = false
  tags                 = { Name = "lab1-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "lab1-igw" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.30.1.0/24"
  availability_zone = local.az_a
  tags              = { Name = "public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.30.11.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = { Name = "private-subnet" }
}

resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id
  tags                   = { Name = "main-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "public-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-rt" }
}

resource "aws_route" "private_upper" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "128.0.0.0/1"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "Bastion and NAT"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_cidr]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.30.12.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.30.0.0/16"]
  }
}

resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "Application server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.30.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = local.ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.lab.key_name
  subnet_id                   = aws_subnet.public.id
  private_ip                  = "10.30.1.10"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  source_dest_check           = true
  tags                        = { Name = "bastion" }

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = <<-SCRIPT
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf
    until command -v iptables >/dev/null; do
      apt-get update; apt-get install -y iptables || sleep 15
    done
    IFACE=$(ip route show default | awk '{print $5}')
    iptables -t nat -A POSTROUTING -s 10.30.11.0/24 -o "$IFACE" -j MASQUERADE
  SCRIPT
}

resource "aws_instance" "app" {
  ami                         = local.ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.lab.key_name
  subnet_id                   = aws_subnet.private.id
  private_ip                  = "10.30.11.10"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.app.id]
  tags                        = { Name = "app" }

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = <<-SCRIPT
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    OPTS="-o Acquire::http::Timeout=5 -o Acquire::https::Timeout=5 -o Acquire::Retries=0"
    until apt-get update $OPTS && apt-get install -y $OPTS -o DPkg::Lock::Timeout=120 apache2; do
      echo "apt failed, retrying"
      sleep 15
    done
    echo "app online" > /var/www/html/index.html
  SCRIPT
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "bastion_id" {
  value = aws_instance.bastion.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}
