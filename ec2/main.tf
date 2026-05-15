# ── Cloudflare DNS ───────────────────────────────────────────────────────────
resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.dns_record_name
  content = aws_eip.app.public_ip
  type    = "A"
  ttl     = 120   # 2 min — short TTL so DNS propagates quickly after first deploy
  proxied = false  # DNS-only: Nginx + Let's Encrypt handle TLS end-to-end
}

# ── AMI ──────────────────────────────────────────────────────────────────────
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

# ── SSH Key Pair ──────────────────────────────────────────────────────────────
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "app" {
  key_name_prefix = "${var.key_name}-"
  public_key      = tls_private_key.ssh.public_key_openssh

  lifecycle {
    create_before_destroy = true
  }
}

# Private key saved locally so you can SSH into the instance
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${var.key_output_dir}/${var.key_name}.pem"
  file_permission = "0400"
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "app" {
  name_prefix = "assignment1-app-sg-"
  description = "Allow SSH, HTTP, and Node.js app traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (Nginx reverse proxy)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "assignment1-app-sg"
    Project = "assignment1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Elastic IP ───────────────────────────────────────────────────────────────
# Reserves a static public IP — free while associated with a running instance.
resource "aws_eip" "app" {
  domain = "vpc"

  tags = {
    Name    = "assignment1-eip"
    Project = "assignment1"
  }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.app.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  # Free tier: up to 30 GB gp2
  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    db_name              = var.db_name
    db_user              = var.db_user
    db_password          = var.db_password
    cloudflare_api_token = var.cloudflare_api_token
    domain_name          = var.domain_name
    certbot_email        = var.certbot_email
  })

  # Ensure instance profile can be replaced without destroying
  user_data_replace_on_change = false

  tags = {
    Name    = "assignment1-nodejs-crud"
    Project = "assignment1"
  }
}
