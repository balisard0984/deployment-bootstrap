#!/bin/bash
set -e

# Docker Installation Script
# Install Docker Engine for Ubuntu/Debian systems

echo "========================================"
echo "Docker Engine Installation Script"
echo "========================================"

# 1. Remove unofficial Docker packages
echo "1. Removing unofficial Docker packages..."
echo "   The following packages will be removed if present:"
echo "   docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "   Removing $pkg..."
        sudo apt-get remove -y $pkg
    else
        echo "   $pkg is not installed, skipping..."
    fi
done

# 2. Update system and install required packages
echo "2. Updating system and installing required packages..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 3. Create Docker GPG key directory
echo "3. Creating Docker GPG key directory..."
sudo install -m 0755 -d /etc/apt/keyrings

# 4. Download Docker official GPG key
echo "4. Downloading Docker official GPG key..."
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 5. Add Docker repository to Apt sources
echo "5. Adding Docker repository to Apt sources..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 6. Update package list
echo "6. Updating package list..."
sudo apt-get update

# 7. Install Docker Engine and related packages
echo "7. Installing Docker Engine and related packages..."
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# 8. Start and enable Docker service
echo "8. Starting and enabling Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# 9. Verify Docker installation
echo "9. Verifying Docker installation..."
docker_version=$(sudo docker --version)
compose_version=$(sudo docker compose version)

echo "========================================"
echo "Docker installation completed successfully!"
echo "========================================"
echo "Installed versions:"
echo "- $docker_version"
echo "- $compose_version"
echo ""
echo "Additional setup:"
echo "- To add current user to docker group:"
echo "  sudo usermod -aG docker \$USER"
echo "  (Logout/login required after this)"
echo ""
echo "========================================"