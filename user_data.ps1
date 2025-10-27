<powershell>
# DC Promotion Script
$ErrorActionPreference = 'Continue'

$domain = '${domain_name}'
$netbios = '${domain_netbios_name}'
$region = '${region}'

Start-Transcript -Path C:\Windows\Temp\user-data.log -Append
Write-Output "Starting DC setup at $(Get-Date)"
Write-Output "Hostname: $env:COMPUTERNAME"

# Install AWS CLI if not present
Write-Output "Ensuring AWS CLI is installed..."
$awsExe = "$env:ProgramFiles\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $awsExe)) {
    Write-Output "Installing AWS CLI..."
    $installer = New-Object System.Net.WebClient
    $installer.DownloadFile("https://awscli.amazonaws.com/AWSCLIV2.msi", "$env:TEMP\AWSCLIV2.msi")
    Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\AWSCLIV2.msi`" /quiet" -Wait -NoNewWindow
    Start-Sleep -Seconds 10
    Write-Output "AWS CLI installed"
} else {
    Write-Output "AWS CLI already installed"
}

# Update progress to Parameter Store
$progressParam = "/${project_name}/dc-setup"
try {
    & $awsExe ssm put-parameter --name $progressParam --value "in-progress" --type "String" --overwrite --region $region 2>&1 | Out-Null
    Write-Output "Progress updated to Parameter Store: in-progress"
} catch {
    Write-Output "Warning: Could not update progress to Parameter Store: $_"
}

# Get passwords from Parameter Store
Write-Output "Fetching passwords from Parameter Store..."

$safeModeParam = "/${project_name}/dc/safe-mode-password"
$adminParam = "/${project_name}/dc/admin-password"

try {
    $safeModePassword = (& $awsExe ssm get-parameter --name $safeModeParam --region $region --with-decryption --query 'Parameter.Value' --output text).Trim()
    $adminPassword = (& $awsExe ssm get-parameter --name $adminParam --region $region --with-decryption --query 'Parameter.Value' --output text).Trim()

    if ([string]::IsNullOrWhiteSpace($safeModePassword) -or [string]::IsNullOrWhiteSpace($adminPassword)) {
        Write-Output "ERROR: Failed to retrieve passwords from Parameter Store"
        & $awsExe ssm put-parameter --name $progressParam --value "failed: password retrieval" --type "String" --overwrite --region $region 2>&1 | Out-Null
        exit 1
    }

    Write-Output "Passwords retrieved from Parameter Store"
} catch {
    Write-Output "ERROR retrieving passwords: $_"
    & $awsExe ssm put-parameter --name $progressParam --value "failed: password retrieval error" --type "String" --overwrite --region $region 2>&1 | Out-Null
    exit 1
}

# Step 1: Set local Administrator password FIRST
Write-Output "Setting local Administrator password..."
$adminUser = [ADSI]"WinNT://./Administrator,user"
$adminUser.SetPassword($adminPassword)
$adminUser.PasswordExpired = 0
$adminUser.SetInfo()
Write-Output "Local Admin password set (never expires)"

# Step 2: Install AD DS
Write-Output "Installing AD DS..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Write-Output "AD DS installed"

# Step 3: Promote to DC
Write-Output "Promoting to DC..."
Import-Module ADDSDeployment
$securePass = ConvertTo-SecureString -String $safeModePassword -AsPlainText -Force

Install-ADDSForest `
  -DomainName $domain `
  -DomainNetbiosName $netbios `
  -InstallDns `
  -SafeModeAdministratorPassword $securePass `
  -Force `
  -NoRebootOnCompletion:$true

Write-Output "DC promotion complete at $(Get-Date)"

# Update progress to success before reboot
try {
    & $awsExe ssm put-parameter --name $progressParam --value "success" --type "String" --overwrite --region $region 2>&1 | Out-Null
    Write-Output "Progress updated to Parameter Store: success"
} catch {
    Write-Output "Warning: Could not update progress to success: $_"
}

Write-Output "Rebooting..."
Stop-Transcript
Restart-Computer -Force
</powershell>
