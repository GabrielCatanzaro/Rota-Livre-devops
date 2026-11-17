# Infraestrutura do MVP Tapa Buraco no AWS Academy (Learner Lab).
# state e terraform.tfvars ficam FORA do repositório (ver .gitignore).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.regiao
}

# VPC padrão da conta (o Learner Lab não permite criar redes complexas)
data "aws_vpc" "padrao" {
  default = true
}

# Ubuntu 24.04 LTS mais recente
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "mvp" {
  name        = "tapa-buraco-mvp"
  description = "Tapa Buraco: app publico; SSH e portas admin so para o IP do time"
  vpc_id      = data.aws_vpc.padrao.id

  # MVP público para o avaliador
  ingress {
    description = "HTTP publico (MVP)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Portas administrativas NUNCA abertas para 0.0.0.0/0
  ingress {
    description = "SSH apenas do IP do time"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip_admin]
  }

  ingress {
    description = "Grafana apenas do IP do time"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.ip_admin]
  }

  ingress {
    description = "Prometheus apenas do IP do time"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.ip_admin]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mvp" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.tipo_instancia
  key_name               = var.chave_ssh # "vockey" já existe no Learner Lab
  vpc_security_group_ids = [aws_security_group.mvp.id]
  user_data              = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }

  tags = {
    Name    = "tapa-buraco-mvp"
    Projeto = "GS-CitizenTech"
  }
}

# IP fixo: sobrevive a stop/start do Learner Lab entre sessões
resource "aws_eip" "mvp" {
  instance = aws_instance.mvp.id
  tags = {
    Name = "tapa-buraco-eip"
  }
}
