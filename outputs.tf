output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "domain_controller_id" {
  description = "Instance ID of the domain controller"
  value       = aws_instance.domain_controller.id
}


output "domain_name" {
  description = "Active Directory domain name"
  value       = var.domain_name
}

output "domain_netbios_name" {
  description = "NetBIOS name of the Active Directory domain"
  value       = var.domain_netbios_name
}

output "safe_mode_password" {
  description = "Safe mode administrator password for Directory Services Restore Mode"
  value       = random_password.safe_mode_password.result
  sensitive   = true
}

output "admin_password" {
  description = "Windows Administrator password (for RDP)"
  value       = random_password.admin_password.result
  sensitive   = true
}

output "rdp_connection" {
  description = "RDP connection information"
  value = {
    ip_address = aws_instance.domain_controller.private_ip
    username   = "Administrator"
    password   = random_password.admin_password.result
  }
  sensitive = true
}

output "view_logs_command" {
  description = "Command to view DC setup logs via SSM"
  value       = "aws ssm send-command --instance-ids ${aws_instance.domain_controller.id} --document-name 'AWS-RunPowerShellScript' --parameters 'commands=[\"Get-Content C:\\Windows\\Temp\\user-data.log -Tail 50\"]'"
}

output "check_dc_setup_status" {
  description = "Command to check DC setup progress from Parameter Store"
  value       = "aws ssm get-parameter --name /${var.project_name}/dc-setup --query 'Parameter.Value' --output text"
}

output "dc_setup_status_parameter" {
  description = "Parameter Store name for DC setup progress"
  value       = aws_ssm_parameter.dc_setup_progress.name
}
