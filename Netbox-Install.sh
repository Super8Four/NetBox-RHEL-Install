#!/bin/bash

# Prompt for SQL password
read -s -p "Enter SQL password for netbox user: " sql_password
echo

# Prompt for web server choice
read -p "Choose a web server (Nginx/Apache): " web_server

# Check if Redis is installed and running
if ! command -v redis-cli &> /dev/null || ! redis-cli ping &> /dev/null; then
    echo "ERROR: Redis is not installed or not running. Please install and configure Redis before running this script."
    exit 1
fi

# Install packages with dnf
sudo dnf install -y postgresql-server redis gcc libxml2-devel libxslt-devel libffi-devel libpq-devel openssl-devel redhat-rpm-config git python3 python3-pip python3-devel

# Initialize and start PostgreSQL
sudo postgresql-setup --initdb
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create the netbox database and user
sudo -u postgres psql << EOF
CREATE DATABASE netbox;
CREATE USER netbox WITH PASSWORD '${sql_password}';
ALTER DATABASE netbox OWNER TO netbox;
EOF

# Start and enable Redis
sudo systemctl start redis
sudo systemctl enable redis

# Check Redis connection
if ! redis-cli ping &> /dev/null; then
    echo "ERROR: Failed to connect to Redis. Please check Redis installation and configuration."
    exit 1
fi

# Clone NetBox repository
sudo git clone -b master --depth 1 https://github.com/netbox-community/netbox.git /opt/netbox/netbox

# Create netbox system group and user
sudo groupadd --system netbox
sudo adduser --system -g netbox netbox

# Set ownership permissions
sudo chown --recursive netbox /opt/netbox/netbox/media/
sudo chown --recursive netbox /opt/netbox/netbox/reports/
sudo chown --recursive netbox /opt/netbox/netbox/scripts/

# Copy configuration file
sudo cp /opt/netbox/netbox/netbox/configuration_example.py /opt/netbox/netbox/netbox/configuration.py

# Generate secret key
sudo python3 /opt/netbox/netbox/generate_secret_key.py > /opt/netbox/netbox/netbox/secret_key.py

# Update ALLOWED_HOSTS
sudo sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/" /opt/netbox/netbox/netbox/configuration.py

# Update DATABASE configuration
sudo sed -i "s/'NAME': 'netbox',/'NAME': 'netbox',\n    'USER': 'netbox',\n    'PASSWORD': '${sql_password}',\n    'HOST': 'localhost',\n    'PORT': '',\n    'CONN_MAX_AGE': 300,/" /opt/netbox/netbox/netbox/configuration.py

# Update REDIS configuration
sudo sed -i "s/'HOST': 'localhost',/'HOST': 'localhost',\n        'PORT': 6379,\n        'PASSWORD': '',\n        'DATABASE': 0,\n        'SSL': False,/" /opt/netbox/netbox/netbox/configuration.py
sudo sed -i "s/'HOST': 'localhost',/'HOST': 'localhost',\n        'PORT': 6379,\n        'PASSWORD': '',\n        'DATABASE': 1,\n        'SSL': False,/" /opt/netbox/netbox/netbox/configuration.py

# Add django-storages to local_requirements.txt
sudo sh -c "echo 'django-storages' >> /opt/netbox/local_requirements.txt"

# Activate virtual environment and change directory
source /opt/netbox/venv/bin/activate
cd /opt/netbox/netbox

# Create superuser
python3 manage.py createsuperuser

# Configure the chosen web server
if [[ $web_server =~ ^[Nn](ginx)?$ ]]; then
    # Install Nginx
    sudo dnf install -y nginx

    # Copy Nginx configuration file
    sudo cp /opt/netbox/contrib/nginx.conf /etc/nginx/sites-available/netbox

    # Enable Nginx configuration
    sudo ln -s /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/netbox

    # Restart Nginx
    sudo systemctl restart nginx
else
    # Install Apache
    sudo dnf install -y httpd

    # Copy Apache configuration file
    sudo cp /opt/netbox/contrib/apache.conf /etc/httpd/conf.d/netbox.conf

    # Enable required Apache modules
    sudo dnf install -y mod_ssl
    sudo a2enmod ssl proxy proxy_http headers rewrite

    # Enable the NetBox site
    sudo a2ensite netbox

    # Restart Apache
    sudo systemctl restart httpd
fi

# Run NetBox upgrade script
sudo /opt/netbox/upgrade.sh
