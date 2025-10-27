# Terraform AWS Windows Domain Controller Demo

This Terraform module deploys a Windows Server 2025 domain controller with Active Directory Domain Services in a private subnet, accessible via AWS Systems Manager (SSM) and RDP.

## Features

- Windows Server 2025 domain controller with GUI
- Deployed in private subnet with NAT gateway access
- SSM and RDP access (RDP from your public IP)
- Automated AD DS promotion via user_data script
- Progress tracking via AWS Parameter Store
- Auto-generated secure passwords (24 characters, avoiding problematic special characters)
- VPC networking with public and private subnets
- Secure password storage in AWS Systems Manager Parameter Store
- IAM roles for SSM and Parameter Store access

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- AWS account with permissions to create:
  - VPC, subnets, NAT gateway, Internet Gateway
  - EC2 instances
  - IAM roles and policies
  - Security groups

## Usage

1. Clone this repository:

   ```bash
   git clone <repository-url>
   cd tf-aws-windows-dc-demo
   ```

2. Initialize Terraform:

   ```bash
   terraform init
   ```

3. Review and modify variables in `terraform.tfvars` (optional):

   ```hcl
   project_name          = "my-dc-demo"
   domain_name          = "corp.example.local"
   domain_netbios_name  = "CORP"
   dc_instance_type     = "t3.medium"
   ```

4. Deploy the infrastructure:

   ```bash
   terraform apply
   ```

5. Monitor DC setup progress (takes 10-15 minutes):

   ```bash
   watch -n 30 "aws ssm get-parameter --name /windows-dc/dc-setup --query 'Parameter.Value' --output text"
   ```

   The status will progress through: `pending` → `in-progress` → `success`

### Connecting to the Domain Controller

#### Via RDP (Remote Desktop Protocol)

1. Get RDP connection details:

   ```bash
   terraform output rdp_connection
   ```

2. Connect using your RDP client with the provided IP, username (Administrator), and password.

#### Via AWS Systems Manager Session Manager

1. Connect via SSM:

   ```bash
   aws ssm start-session --target $(terraform output -raw domain_controller_id) --region ap-southeast-2
   ```

**Note**: After DC promotion, SSM Session Manager may not work as it cannot create local users on a domain controller. Use RDP instead.

## Credentials

### Windows Administrator Password

The DC uses random 24-character passwords (avoiding problematic special characters for PowerShell compatibility). Passwords are stored securely in AWS Systems Manager Parameter Store:

```bash
# Retrieve Administrator password
terraform output -raw admin_password

# Retrieve safe mode password
terraform output -raw safe_mode_password
```

**Security**: Passwords are stored as SecureString in Parameter Store with KMS encryption. Terraform state contains plain text - keep it secure.

## Domain Information

Get domain details:

```bash
# Domain details
terraform output domain_name
terraform output domain_netbios_name

# DC instance information
terraform output domain_controller_id

# View DC setup progress
terraform output check_dc_setup_status
```

## Progress Tracking

Monitor DC setup progress via Parameter Store:

```bash
# Check current status
terraform output -raw check_dc_setup_status | bash

# The status will be one of:
# - pending: Initial state
# - in-progress: DC promotion in progress
# - success: DC promotion complete
```

View DC setup logs:

```bash
terraform output -raw view_logs_command | bash
```

## Architecture

```plaintext
┌─────────────────────────────────────────┐
│  VPC (10.0.0.0/16)                     │
│                                         │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ Public Sub  │  │ Public Sub  │      │
│  │ 10.0.1.0/24 │  │ 10.0.2.0/24 │      │
│  └─────────────┘  └─────────────┘      │
│         │                 │              │
│         └────────┬────────┘              │
│                  │                       │
│            ┌─────▼──────┐                │
│            │  Internet  │                │
│            │  Gateway   │                │
│            └─────┬──────┘                │
│                  │                       │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ Private Sub │  │ Private Sub │      │
│  │10.0.10.0/24 │  │10.0.11.0/24 │      │
│  └─────────────┘  └─────────────┘      │
│         │                                 │
│    ┌────▼────────────┐                   │
│    │ NAT Gateway     │                   │
│    │ (in Public Sub) │                   │
│    └────┬────────────┘                   │
│         │                                 │
│    ┌────▼──────┐                         │
│    │  Domain   │                         │
│    │ Controller│                         │
│    │ (DC01)    │                         │
│    └───────────┘                         │
└─────────────────────────────────────────┘
```

## Instance Configuration

- **Instance Type**: t3.medium (default, configurable)
- **AMI**: Latest Windows Server 2025 English Base
- **Storage**: Default EBS root volume
- **Network**: Private subnet, full VPC access
- **Access**: SSM Session Manager only

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

## Client Deployment

After the DC is deployed, you can deploy a client that automatically joins the domain:

```bash
cd client
terraform init
terraform apply
```

Monitor client domain join progress:

```bash
watch -n 30 "AWS_VAULT_BACKEND=pass aws-vault exec dev -- aws ssm get-parameter --name /windows-dc/client-join-domain --query 'Parameter.Value' --output text"
```

## Key Features

### Automated DC Setup

- AWS CLI installed automatically
- Passwords fetched from Parameter Store
- Progress tracking via Parameter Store
- Single log file: `C:\Windows\Temp\user-data.log`

### Password Management

- Passwords stored in Parameter Store with KMS encryption
- EC2 instances fetch passwords directly via IAM roles
- No passwords passed in user_data
- Passwords generated without problematic special characters ($, ?, |, \, etc.)

### Security

- RDP access limited to your public IP
- Private subnet deployment
- NAT gateway for internet access
- IAM roles for least privilege access

## Notes

- The domain controller takes 10-15 minutes to fully promote
- Client domain join takes 2-3 minutes after deployment
- RDP from your public IP is allowed for management
- All traffic from VPC is allowed to the domain controller for AD DS protocols
- The domain controller can access the internet via NAT gateway for Windows updates
- Passwords are generated without characters that cause PowerShell escaping issues

## Troubleshooting

### DC Setup Issues

Check DC setup status:

```bash
terraform output -raw check_dc_setup_status
```

View DC setup logs:

```bash
terraform output -raw view_logs_command
```

### Client Domain Join Issues

Check client join status:

```bash
cd client
terraform output -raw check_client_join_status
```

### Connection Issues

If you cannot connect via RDP:

1. Verify your public IP hasn't changed (the security group allows your IP)
2. Check instance is running and in "passed" status
3. Verify NAT gateway is working (instance needs internet access)
4. Check security group allows RDP from your IP

### AWS CLI Installation

AWS CLI is automatically installed on both DC and client instances. If you need to reinstall:

```powershell
$installer = New-Object System.Net.WebClient
$installer.DownloadFile("https://awscli.amazonaws.com/AWSCLIV2.msi", "$env:TEMP\AWSCLIV2.msi")
Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\AWSCLIV2.msi`" /quiet" -Wait
```

## License

See LICENSE file for details.
