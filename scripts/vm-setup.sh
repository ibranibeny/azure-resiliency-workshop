#!/bin/bash

#############################################################################
# Azure Resiliency Workshop - Manual VM Setup Script
# 
# Run this script directly on the VM if cloud-init didn't complete properly
# 
# Usage: 
#   curl -sSL https://raw.githubusercontent.com/.../vm-setup.sh | bash
#   or
#   Copy this script to VM and run: chmod +x vm-setup.sh && ./vm-setup.sh
#############################################################################

set -e

echo "============================================"
echo "  VM Setup Script - Resiliency Workshop"
echo "============================================"
echo ""

# Update system
echo ">>> Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo ">>> Installing required packages..."
sudo apt install -y nginx git curl

# Install Node.js 18
echo ">>> Installing Node.js 18..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify Node.js installation
echo ">>> Node.js version:"
node --version
echo ">>> npm version:"
npm --version

# Install PM2 globally
echo ">>> Installing PM2..."
sudo npm install -g pm2

# Create application directory
echo ">>> Creating application directory..."
sudo mkdir -p /var/www/social-media
sudo chown -R $USER:$USER /var/www/social-media

# Configure Nginx
echo ">>> Configuring Nginx..."
sudo tee /etc/nginx/sites-available/default > /dev/null << 'NGINX'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINX

# Test and restart Nginx
echo ">>> Testing Nginx configuration..."
sudo nginx -t

echo ">>> Restarting Nginx..."
sudo systemctl restart nginx
sudo systemctl enable nginx

# Verify Nginx is running
echo ">>> Nginx status:"
sudo systemctl status nginx --no-pager

echo ""
echo "============================================"
echo "  ✅ VM Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Upload your application to /var/www/social-media"
echo "2. Create .env file with configuration"
echo "3. Run: cd /var/www/social-media && npm install"
echo "4. Run: pm2 start app.js --name social-media"
echo "5. Run: pm2 save && pm2 startup"
echo ""
