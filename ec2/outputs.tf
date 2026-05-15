output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "elastic_ip" {
  description = "Reserved static public IP — already bound to your Cloudflare A record"
  value       = aws_eip.app.public_ip
}

output "cloudflare_record" {
  description = "DNS record created in Cloudflare"
  value       = "${cloudflare_record.app.name} → ${aws_eip.app.public_ip}"
}

output "app_url" {
  description = "Public HTTPS URL for the CRUD app"
  value       = "https://${var.domain_name}"
}


output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.key_output_dir}/${var.key_name}.pem ubuntu@${aws_eip.app.public_ip}"
}
