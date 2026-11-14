variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for project resources"
  type        = string
  default     = "muchtodo"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "Your public IP address in CIDR notation, restricted to /32"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_ssh_cidr)) && endswith(var.allowed_ssh_cidr, "/32")
    error_message = "Provide a valid IPv4 CIDR containing a single IP address, ending in /32."
  }
}

variable "key_pair_name" {
  description = "AWS EC2 key pair used for SSH access"
  type        = string
  default     = "semester3-cloud-key"
}