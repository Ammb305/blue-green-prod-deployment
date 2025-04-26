provider "aws" {
  region = var.region 
}

data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["Blue-Green VPC"]
  }
}

# Create separate security groups for each service
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SSH access from my IP"
  }

  # Jenkins web interface
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Jenkins web UI access"
  }

  # Jenkins agent communication
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Jenkins agent communication"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-sg"
  }
}

resource "aws_security_group" "sonarqube_sg" {
  name        = "sonarqube-sg"
  description = "Security group for SonarQube server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SSH access from my IP"
  }

  # SonarQube web interface
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SonarQube web UI access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sonarqube-sg"
  }
}

resource "aws_security_group" "nexus_sg" {
  name        = "nexus-sg"
  description = "Security group for Nexus repository server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SSH access from my IP"
  }

  # Nexus web interface
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Nexus web UI access"
  }

  # Docker registry (if needed)
  ingress {
    from_port   = 8082
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Docker registry ports"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nexus-sg"
  }
}

# AMI for Ubuntu 22.04
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical's AWS account ID
}

# Jenkins Server with enhanced security
resource "aws_instance" "jenkins_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.medium"
  key_name               = var.key_name
  subnet_id              = element(aws_subnet.public_subnets[*].id, 0)
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true
  
  
  # Enforce IMDSv2 to prevent SSRF attacks
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  
  root_block_device {
    encrypted   = true
    volume_size = 30
    volume_type = "gp3"
    tags = {
      Name = "jenkins-root-volume"
    }
  }

  tags = {
    Name        = "Jenkins-Server"
    Environment = "Production"
    Service     = "CI/CD"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update system packages and apply security patches
              sudo apt update && sudo apt upgrade -y
              
              # Install required dependencies
              sudo apt install -y fontconfig openjdk-21-jre
              
              # Install Jenkins
              sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
                https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
              echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
                https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
                /etc/apt/sources.list.d/jenkins.list > /dev/null
              sudo apt update
              sudo apt install -y jenkins
              
              # Create dedicated user for Jenkins
              if [ $(getent passwd jenkins) ]; then
                echo "Jenkins user already exists"
              else
                sudo useradd -r -d /var/lib/jenkins -s /bin/false jenkins
              fi
              
              # Set proper file permissions
              sudo chown -R jenkins:jenkins /var/lib/jenkins
              
              # Configure basic firewall
              sudo apt install -y ufw
              sudo ufw default deny incoming
              sudo ufw default allow outgoing
              sudo ufw allow ssh
              sudo ufw allow 8080/tcp
              sudo ufw --force enable
              
              # Start Jenkins service
              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              EOF
}

# SonarQube Server with enhanced security
resource "aws_instance" "sonarqube_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.medium"
  key_name               = var.key_name
  subnet_id              = element(aws_subnet.public_subnets[*].id, 1)
  vpc_security_group_ids = [aws_security_group.sonarqube_sg.id]
  associate_public_ip_address = true

  # Enforce IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  
  root_block_device {
    encrypted   = true
    volume_size = 30
    volume_type = "gp3"
    tags = {
      Name = "sonarqube-root-volume"
    }
  }

  tags = {
    Name        = "SonarQube-Server"
    Environment = "Production"
    Service     = "Code Analysis"
  }
user_data = <<-EOF
              #!/bin/bash
              # Update system packages and apply security patches
              sudo apt update && sudo apt upgrade -y
              
              # Install Docker
              sudo apt install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              
              # Add current user to the Docker group
              sudo usermod -aG docker ubuntu
              
              # Pull the SonarQube Docker image
              sudo docker pull sonarqube:latest
              
              # Run SonarQube as a Docker container
              sudo docker run -d --name sonarqube \
                -p 9000:9000 \
                -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
                sonarqube:latest
              
              # Configure basic firewall
              sudo apt install -y ufw
              sudo ufw default deny incoming
              sudo ufw default allow outgoing
              sudo ufw allow ssh
              sudo ufw allow 9000/tcp
              sudo ufw --force enable
              EOF
}

# Nexus Server with enhanced security
resource "aws_instance" "nexus_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.medium"
  key_name               = var.key_name
  subnet_id              = element(aws_subnet.public_subnets[*].id, 0)
  vpc_security_group_ids = [aws_security_group.nexus_sg.id]
  associate_public_ip_address = true
  
  
  # Enforce IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  
  root_block_device {
    encrypted   = true
    volume_size = 30  
    volume_type = "gp3"
    tags = {
      Name = "nexus-root-volume"
    }
  }

  tags = {
    Name        = "Nexus-Server"
    Environment = "Production"
    Service     = "Artifact Repository"
  }
}