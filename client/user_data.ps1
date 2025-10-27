<powershell>
# Client Domain Join Script
$ErrorActionPreference = 'Continue'

Start-Transcript -Path C:\Windows\Temp\user-data.log -Append
Write-Output "Starting client setup at $(Get-Date)"
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

# Get region from instance metadata
try {
    $regionUri = "http://169.254.169.254/latest/meta-data/placement/region"
    $region = (Invoke-WebRequest -Uri $regionUri -UseBasicParsing).Content.Trim()
    Write-Output "Region retrieved: $region"
} catch {
    # Fallback to ap-southeast-2 if metadata is not available
    $region = "ap-southeast-2"
    Write-Output "Failed to retrieve region, using default: $region"
}
$progressParam = "/windows-dc/client-join-domain"

# Update progress to Parameter Store
Write-Output "Updating progress to in-progress..."
try {
    & $awsExe ssm put-parameter --name $progressParam --value "in-progress" --type "String" --overwrite --region $region 2>&1 | Out-Null
    Write-Output "Progress updated to Parameter Store: in-progress"
} catch {
    Write-Output "Warning: Could not update progress to Parameter Store: $_"
}

# Get password from Parameter Store
$parameterName = "/windows-dc/dc/admin-password"
Write-Output "Fetching password from Parameter Store: $parameterName in region: $region"

try {
    $password = (& $awsExe ssm get-parameter --name $parameterName --region $region --with-decryption --query 'Parameter.Value' --output text).Trim()

    if ([string]::IsNullOrWhiteSpace($password)) {
        Write-Output "ERROR: Failed to retrieve password from Parameter Store"
        & $awsExe ssm put-parameter --name $progressParam --value "failed: password retrieval" --type "String" --overwrite --region $region 2>&1 | Out-Null
        exit 1
    }

    Write-Output "Password retrieved from Parameter Store"
} catch {
    Write-Output "ERROR retrieving password: $_"
    & $awsExe ssm put-parameter --name $progressParam --value "failed: password retrieval error" --type "String" --overwrite --region $region 2>&1 | Out-Null
    exit 1
}

# Get domain name from Parameter Store
$domainParameter = "/windows-dc/dc/domain-name"
try {
    $domain = (& $awsExe ssm get-parameter --name $domainParameter --region $region --query 'Parameter.Value' --output text).Trim()

    if ([string]::IsNullOrWhiteSpace($domain)) {
        Write-Output "ERROR: Failed to retrieve domain name from Parameter Store"
        & $awsExe ssm put-parameter --name $progressParam --value "failed: domain name retrieval" --type "String" --overwrite --region $region 2>&1 | Out-Null
        exit 1
    }

    Write-Output "Domain name retrieved: $domain"
} catch {
    Write-Output "ERROR retrieving domain name: $_"
    & $awsExe ssm put-parameter --name $progressParam --value "failed: domain name retrieval error" --type "String" --overwrite --region $region 2>&1 | Out-Null
    exit 1
}

# Join to domain
Write-Output "Joining to domain: $domain"
try {
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential("$domain\Administrator", $securePassword)

    Add-Computer -DomainName $domain -Credential $credential -Force -ErrorAction Stop
    Write-Output "Successfully joined domain"

    # Update progress to success before reboot
    try {
        & $awsExe ssm put-parameter --name $progressParam --value "success" --type "String" --overwrite --region $region 2>&1 | Out-Null
        Write-Output "Progress updated to Parameter Store: success"
    } catch {
        Write-Output "Warning: Could not update progress to success: $_"
    }
} catch {
    Write-Output "ERROR joining domain: $_"
    & $awsExe ssm put-parameter --name $progressParam --value "failed: domain join error" --type "String" --overwrite --region $region 2>&1 | Out-Null
    exit 1
}

Write-Output "Rebooting..."
Stop-Transcript
Restart-Computer -Force
</powershell>
