variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair to use for EC2 instances"
  type        = string
}

variable "my_ip" {
  description = "Your IP address for SSH access"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]  
}

variable "private_subnet_cidrs" {
  description = "private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]  
}

variable "availability_zones" {
  description = "Availability zones for the VPC"
  type        = list(string)
}
