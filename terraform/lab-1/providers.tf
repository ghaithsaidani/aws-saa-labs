terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.80" }
    http   = { source = "hashicorp/http", version = "~> 3.4" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    time   = { source = "hashicorp/time", version = "~> 0.12" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "my_ip" {
  description = "Your public IP. Leave empty to detect it."
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "Ubuntu 24.04 AMI. Leave empty to look it up."
  type        = string
  default     = ""
}

data "http" "my_ip" {
  count = var.my_ip == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  my_cidr = "${var.my_ip != "" ? var.my_ip : trimspace(data.http.my_ip[0].response_body)}/32"
  ami     = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
  az_a    = data.aws_availability_zones.available.names[0]
  az_b    = data.aws_availability_zones.available.names[1]
}

resource "random_id" "lab" {
  byte_length = 8
}

resource "aws_key_pair" "lab" {
  key_name   = "lab-key-${random_id.lab.hex}"
  public_key = file("${path.module}/lab-key.pem.pub")
}

output "region" {
  value = var.region
}

output "ctf_seed" {
  value = random_id.lab.hex
}
