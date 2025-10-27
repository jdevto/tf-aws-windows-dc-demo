output "client_id" {
  description = "Instance ID of the client"
  value       = aws_instance.client.id
}

output "client_private_ip" {
  description = "Private IP of the client"
  value       = aws_instance.client.private_ip
}

output "check_client_join_status" {
  description = "Command to check client domain join progress from Parameter Store"
  value       = "aws ssm get-parameter --name /windows-dc/client-join-domain --query 'Parameter.Value' --output text"
}

output "client_join_status_parameter" {
  description = "Parameter Store name for client domain join progress"
  value       = aws_ssm_parameter.client_join_progress.name
}
