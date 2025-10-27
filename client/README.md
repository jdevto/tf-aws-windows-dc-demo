# Client (Domain Member)

This directory contains the Terraform configuration for a Windows client that automatically joins the domain created by the DC setup.

## Prerequisites

- The main DC infrastructure must be deployed and ready
- Parameter Store parameters must exist:
  - `/windows-dc/dc/admin-password` (SecureString)
  - `/windows-dc/dc/domain-name` (String)

## Deployment

1. From the root directory, deploy the DC first:

   ```bash
   cd ..
   terraform init
   terraform apply
   ```

2. Wait for DC to be ready (check Parameter Store: `/windows-dc/dc-setup` should be "success")

3. Deploy the client:

   ```bash
   cd client
   terraform init
   terraform apply
   ```

4. Monitor client domain join progress:

   ```bash
   watch -n 30 "aws ssm get-parameter --name /windows-dc/client-join-domain --query 'Parameter.Value' --output text"
   ```

## Resources Created

- Client EC2 instance (Windows Server 2025 with GUI)
- Security group allowing:
  - RDP from your public IP
  - All AD DS traffic from/to DC
  - Internet access via egress rules
- IAM role with SSM and Parameter Store read/write permissions
- Parameter Store for progress tracking: `/windows-dc/client-join-domain`
- Automatically joins the domain on first boot

## Features

### Automated Domain Join

- AWS CLI installed automatically
- Password fetched from Parameter Store
- Domain name fetched from Parameter Store
- Automatically joins to Active Directory
- Progress tracking via Parameter Store
- Single log file: `C:\Windows\Temp\user-data.log`

### Progress Tracking

The client updates its progress in Parameter Store:

- `pending`: Initial state
- `in-progress`: AWS CLI installed, fetching parameters
- `success`: Successfully joined domain
- `failed: <reason>`: Domain join failed with error details

### Access

- **RDP**: From your public IP (configured in security group)
- **SSM**: Via AWS Systems Manager Session Manager

## Usage

After deployment:

1. Get client connection details:

   ```bash
   terraform output client_private_ip
   terraform output -raw check_client_join_status
   ```

2. Connect via RDP using the Administrator password (same as DC)

## Verification

Check if the client joined the domain successfully:

```bash
# From DC via RDP or SSM
Get-ADComputer -Filter * | Select-Object Name,DNSHostName,Enabled
```

You should see both the DC and the client listed.

## Troubleshooting

### Domain Join Failed

Check the client join status:

```bash
terraform output -raw check_client_join_status
```

View client setup logs:

```bash
# Get client instance ID
terraform output client_id

# View logs via SSM
aws ssm send-command \
  --instance-ids $(terraform output -raw client_id) \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Get-Content C:\\Windows\\Temp\\user-data.log -Tail 50"]' \
  --region ap-southeast-2
```

### Common Issues

1. **Parameter Store not accessible**: Verify IAM role has `ssm:GetParameter` permissions
2. **Domain not reachable**: Wait for DC to be fully ready
3. **Password incorrect**: Check DC admin password in Parameter Store
4. **DNS not resolving**: Verify VPC DHCP options point to DC
