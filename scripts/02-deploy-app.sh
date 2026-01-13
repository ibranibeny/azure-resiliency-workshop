#!/bin/bash

#############################################################################
# Azure Resiliency Workshop - Application Deployment Script
# 
# This script deploys the Node.js social media application to both VMs
# Uses Azure CLI run-command since VMs have no public IPs (Hub-Spoke with Firewall)
#
# Prerequisites: 
# - Run 01-deploy-infrastructure.sh first
# - deployment-output.txt must exist
#############################################################################

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

# Load configuration from deployment output
if [ -f "deployment-output.txt" ]; then
    source deployment-output.txt
else
    echo "❌ Error: deployment-output.txt not found!"
    echo "Please run 01-deploy-infrastructure.sh first."
    exit 1
fi

# Application source directory
APP_DIR="../app"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo ""
    echo "============================================================================="
    echo " $1"
    echo "============================================================================="
}

print_step() {
    echo ""
    echo ">>> $1"
    echo ""
}

print_success() {
    echo "✅ $1"
}

print_info() {
    echo "ℹ️  $1"
}

print_warning() {
    echo "⚠️  $1"
}

# =============================================================================
# PREPARE APPLICATION CODE
# =============================================================================

print_header "Preparing Application for Deployment"

# Read app.js content
APP_JS=$(cat "$APP_DIR/app.js")
PACKAGE_JSON=$(cat "$APP_DIR/package.json")
INDEX_EJS=$(cat "$APP_DIR/views/index.ejs")

print_success "Application files loaded"

# =============================================================================
# DEPLOY TO PRIMARY VM (Southeast Asia)
# =============================================================================

print_header "Deploying to Primary VM (Southeast Asia)"

print_step "Deploying application via Azure CLI run-command..."
print_info "This uses Azure fabric to execute commands on VMs without public IP"

az vm run-command invoke \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --name "$VM_PRIMARY" \
    --command-id RunShellScript \
    --scripts "
# Create app directory
mkdir -p /var/www/social-media/views
cd /var/www/social-media

# Create package.json
cat > package.json << 'PKGJSON'
$PACKAGE_JSON
PKGJSON

# Create app.js
cat > app.js << 'APPJS'
$APP_JS
APPJS

# Create views directory and index.ejs
cat > views/index.ejs << 'INDEXEJS'
$INDEX_EJS
INDEXEJS

# Create .env file
cat > .env << ENVFILE
PORT=3000
REGION=Southeast Asia
REGION_COLOR=#28a745
SQL_SERVER=$SQL_LISTENER
SQL_DATABASE=$SQL_DATABASE
SQL_USER=$SQL_ADMIN_USER
SQL_PASSWORD=$SQL_ADMIN_PASSWORD
SQL_ENCRYPT=true
SQL_TRUST_SERVER_CERTIFICATE=false
ENVFILE

# Set permissions
chown -R azureuser:azureuser /var/www/social-media

# Install dependencies
cd /var/www/social-media
npm install

# Start with PM2
sudo -u azureuser bash -c 'cd /var/www/social-media && pm2 delete all 2>/dev/null || true'
sudo -u azureuser bash -c 'cd /var/www/social-media && pm2 start app.js --name social-media'
sudo -u azureuser bash -c 'pm2 save'

# Configure PM2 to start on boot
env PATH=\$PATH:/usr/bin pm2 startup systemd -u azureuser --hp /home/azureuser
sudo -u azureuser pm2 save

# Restart Nginx
systemctl restart nginx

echo 'Application deployed successfully!'
echo 'PM2 configured to auto-start on boot!'
" \
    --output table

print_success "Deployed to Southeast Asia VM"

# =============================================================================
# DEPLOY TO SECONDARY VM (Indonesia Central)
# =============================================================================

print_header "Deploying to Secondary VM (Indonesia Central)"

print_step "Deploying application via Azure CLI run-command..."

az vm run-command invoke \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --name "$VM_SECONDARY" \
    --command-id RunShellScript \
    --scripts "
# Create app directory
mkdir -p /var/www/social-media/views
cd /var/www/social-media

# Create package.json
cat > package.json << 'PKGJSON'
$PACKAGE_JSON
PKGJSON

# Create app.js
cat > app.js << 'APPJS'
$APP_JS
APPJS

# Create views directory and index.ejs
cat > views/index.ejs << 'INDEXEJS'
$INDEX_EJS
INDEXEJS

# Create .env file
cat > .env << ENVFILE
PORT=3000
REGION=Indonesia Central
REGION_COLOR=#007bff
SQL_SERVER=$SQL_LISTENER
SQL_DATABASE=$SQL_DATABASE
SQL_USER=$SQL_ADMIN_USER
SQL_PASSWORD=$SQL_ADMIN_PASSWORD
SQL_ENCRYPT=true
SQL_TRUST_SERVER_CERTIFICATE=false
ENVFILE

# Set permissions
chown -R azureuser:azureuser /var/www/social-media

# Install dependencies
cd /var/www/social-media
npm install

# Start with PM2
sudo -u azureuser bash -c 'cd /var/www/social-media && pm2 delete all 2>/dev/null || true'
sudo -u azureuser bash -c 'cd /var/www/social-media && pm2 start app.js --name social-media'
sudo -u azureuser bash -c 'pm2 save'

# Configure PM2 to start on boot
env PATH=\$PATH:/usr/bin pm2 startup systemd -u azureuser --hp /home/azureuser
sudo -u azureuser pm2 save

# Restart Nginx
systemctl restart nginx

echo 'Application deployed successfully!'
echo 'PM2 configured to auto-start on boot!'
" \
    --output table

print_success "Deployed to Indonesia Central VM"

# =============================================================================
# VERIFICATION
# =============================================================================

print_header "Verifying Deployments"

print_step "Testing Primary VM via Firewall (Southeast Asia)..."
sleep 10  # Wait for app to start

if curl -s --connect-timeout 15 "http://$FW_PUBLIC_IP_PRIMARY/health" | grep -q "healthy"; then
    print_success "Primary VM is healthy (via Firewall)"
else
    print_warning "Primary VM health check pending (may need more time for cloud-init)"
fi

print_step "Testing Secondary VM via Firewall (Indonesia Central)..."
if curl -s --connect-timeout 15 "http://$FW_PUBLIC_IP_SECONDARY/health" | grep -q "healthy"; then
    print_success "Secondary VM is healthy (via Firewall)"
else
    print_warning "Secondary VM health check pending (may need more time for cloud-init)"
fi

print_step "Testing Front Door..."
sleep 5
if curl -s --connect-timeout 30 "http://$FRONTDOOR_URL/health" | grep -q "healthy"; then
    print_success "Front Door is routing correctly"
else
    print_warning "Front Door may need 2-3 minutes to propagate"
fi

# =============================================================================
# SUMMARY
# =============================================================================

print_header "DEPLOYMENT COMPLETE!"

echo ""
echo "🌐 ACCESS YOUR APPLICATION"
echo "============================================================================="
echo ""
echo "Via Front Door (recommended):"
echo "  http://$FRONTDOOR_URL"
echo ""
echo "Via Firewall (Direct):"
echo "  Primary (SEA):   http://$FW_PUBLIC_IP_PRIMARY"
echo "  Secondary (IDC): http://$FW_PUBLIC_IP_SECONDARY"
echo ""
echo "Health Endpoints:"
echo "  Primary:   http://$FW_PUBLIC_IP_PRIMARY/health"
echo "  Secondary: http://$FW_PUBLIC_IP_SECONDARY/health"
echo "  Front Door: http://$FRONTDOOR_URL/health"
echo ""
echo "============================================================================="
echo ""
echo "📝 DEMO COMMANDS"
echo "============================================================================="
echo ""
echo "Stop Primary VM (trigger failover):"
echo "  az vm stop --resource-group $RG_SPOKE_PRIMARY --name $VM_PRIMARY --no-wait"
echo ""
echo "Start Primary VM (restore):"
echo "  az vm start --resource-group $RG_SPOKE_PRIMARY --name $VM_PRIMARY --no-wait"
echo ""
echo "Stop app only (faster failover demo):"
echo "  az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \\"
echo "    --command-id RunShellScript --scripts 'sudo -u azureuser pm2 stop all'"
echo ""
echo "Start app:"
echo "  az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \\"
echo "    --command-id RunShellScript --scripts 'sudo -u azureuser pm2 start all'"
echo ""
echo "============================================================================="

print_success "Application deployment complete!"
echo ""
echo "Completed at: $(date)"
