#!/bin/bash
# Preparação da EC2: Docker + Compose + git. Roda uma única vez na criação.
set -euxo pipefail

apt-get update -y
apt-get install -y docker.io docker-compose-v2 git
systemctl enable --now docker
usermod -aG docker ubuntu
