variable "instance_type" {
  description = "EC2 instance type (t3.micro is free tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name for the AWS key pair"
  type        = string
  default     = "assignment1-key"
}

variable "db_name" {
  description = "MySQL database name for the CRUD app"
  type        = string
  default     = "node_crud"
}

variable "db_user" {
  description = "MySQL application user"
  type        = string
  default     = "nodeapp"
}

variable "db_password" {
  description = "MySQL application user password"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permission"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the domain"
  type        = string
}

variable "domain_name" {
  description = "Full domain/subdomain for the app (e.g. crud.yourdomain.com) — used for Nginx and Certbot"
  type        = string
}

variable "dns_record_name" {
  description = "Record name relative to the zone root (e.g. 'assignment1' for assignment1.example.com, '@' for root domain)"
  type        = string
}

variable "certbot_email" {
  description = "Email address for Let's Encrypt expiry notifications"
  type        = string
  default     = "admin@example.com"
}

variable "key_output_dir" {
  description = "Directory where the SSH private key file will be written"
  type        = string
  default     = "."
}
