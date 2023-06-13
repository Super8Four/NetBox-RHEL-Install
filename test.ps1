# Prompt for SQL password
$sql_password = Read-Host -Prompt "Enter SQL password for netbox user" -AsSecureString
$sql_password_text = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sql_password))

# Prompt for web server choice
$web_server = Read-Host -Prompt "Choose a web server (IIS/Apache)"

# Install required packages
Write-Host "Installing packages..."
$packages = "postgresql-server", "redis", "gcc", "libxml2-devel", "libxslt-devel", "libffi-devel", "libpq-devel", "openssl-devel", "git", "python3", "python3-pip", "python3-devel"
foreach ($package in $packages) {
    Start-Process -Wait -FilePath "dnf" -ArgumentList "install", "-y", $package
}

# Initialize and start PostgreSQL
Write-Host "Initializing and starting PostgreSQL..."
Start-Process -Wait -FilePath "postgresql-setup" -ArgumentList "--initdb"
Start-Service "postgresql"
Set-Service "postgresql" -StartupType "Automatic"

# Create the netbox database and user
Write-Host "Creating database and user..."
$psql_cmd = "CREATE DATABASE netbox; CREATE USER netbox WITH PASSWORD '$sql_password_text'; ALTER DATABASE netbox OWNER TO netbox;"
Start-Process -Wait -FilePath "psql" -ArgumentList "-U", "postgres", "-c", $psql_cmd

# Start and enable Redis
Write-Host "Starting and enabling Redis..."
Start-Service "redis"
Set-Service "redis" -StartupType "Automatic"

# Check Redis connection
if (-not (Test-Connection "localhost" -Port 6379 -Quiet)) {
    Write-Host "ERROR: Failed to connect to Redis. Please check Redis installation and configuration."
    exit 1
}

# Clone NetBox repository
Write-Host "Cloning NetBox repository..."
git clone -b master --depth 1 https://github.com/netbox-community/netbox.git C:\opt\netbox\netbox

# Create netbox system user
Write-Host "Creating netbox system user..."
$netbox_user = New-LocalUser -Name "netbox" -NoPassword -UserMayNotChangePassword -PasswordNeverExpires -AccountNeverExpires -UserType "Service"

# Set ownership permissions
Write-Host "Setting ownership permissions..."
icacls "C:\opt\netbox\netbox\media\" /setowner "netbox" /T /C /Q
icacls "C:\opt\netbox\netbox\reports\" /setowner "netbox" /T /C /Q
icacls "C:\opt\netbox\netbox\scripts\" /setowner "netbox" /T /C /Q

# Copy configuration file
Write-Host "Copying configuration file..."
Copy-Item -Path "C:\opt\netbox\netbox\netbox\configuration_example.py" -Destination "C:\opt\netbox\netbox\netbox\configuration.py" -Force

# Generate secret key
Write-Host "Generating secret key..."
$secret_key = python3 "C:\opt\netbox\netbox\generate_secret_key.py"
$secret_key | Out-File -FilePath "C:\opt\netbox\netbox\netbox\secret_key.py"

# Update ALLOWED_HOSTS
Write-Host "Updating ALLOWED_HOSTS..."
(Get-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py") | ForEach-Object {
    $_ -replace "^ALLOWED_HOSTS = .*", "ALLOWED_HOSTS = ['*']"
} | Set-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py"

# Update DATABASE configuration
Write-Host "Updating DATABASE configuration..."
(Get-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py") | ForEach-Object {
    $_ -replace "'NAME': 'netbox',", "'NAME': 'netbox',`n    'USER': 'netbox',`n    'PASSWORD': '$sql_password_text',`n    'HOST': 'localhost',`n    'PORT': '',`n    'CONN_MAX_AGE': 300,"
} | Set-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py"

# Update REDIS configuration
Write-Host "Updating REDIS configuration..."
(Get-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py") | ForEach-Object {
    $_ -replace "'HOST': 'localhost',", "'HOST': 'localhost',`n        'PORT': 6379,`n        'PASSWORD': '',`n        'DATABASE': 0,`n        'SSL': False,"
} | Set-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py"
(Get-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py") | ForEach-Object {
    $_ -replace "'HOST': 'localhost',", "'HOST': 'localhost',`n        'PORT': 6379,`n        'PASSWORD': '',`n        'DATABASE': 1,`n        'SSL': False,"
} | Set-Content -Path "C:\opt\netbox\netbox\netbox\configuration.py"

# Add django-storages to local_requirements.txt
Write-Host "Adding django-storages to local_requirements.txt..."
Add-Content -Path "C:\opt\netbox\local_requirements.txt" -Value "django-storages"

# Activate virtual environment and change directory
Write-Host "Activating virtual environment and changing directory..."
Set-Location "C:\opt\netbox\netbox"
python3 manage.py createsuperuser

# Configure the chosen web server
if ($web_server -eq "IIS") {
    # Install IIS
    Write-Host "Installing IIS..."
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools -Restart

    # Install URL Rewrite Module
    Write-Host "Installing URL Rewrite Module..."
    $url_rewrite_package = "https://download.microsoft.com/download/C/8/5/C8591D48-54D8-4A98-ADB4-AB7206F7D38E/rewrite_amd64_en-US.msi"
    $url_rewrite_installer = "C:\opt\netbox\rewrite_amd64_en-US.msi"
    Invoke-WebRequest -Uri $url_rewrite_package -OutFile $url_rewrite_installer
    Start-Process -Wait -FilePath "msiexec.exe" -ArgumentList "/i", "`"$url_rewrite_installer`"", "/quiet"
    Remove-Item -Path $url_rewrite_installer

    # Configure IIS site
    Write-Host "Configuring IIS site..."
    $site_name = "NetBox"
    $site_path = "C:\opt\netbox\netbox"
    $app_pool_name = "NetBoxAppPool
