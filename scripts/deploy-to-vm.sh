#!/bin/bash
# Deploy app to Azure VMs using run-command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/../app"

# Check if we're in the right directory
if [[ ! -f "$APP_DIR/app.js" ]]; then
    echo "❌ Cannot find app.js. Please run from project root."
    exit 1
fi

# Encode files
echo "🔧 Encoding app files..."
APP_JS_B64=$(base64 -w 0 "$APP_DIR/app.js")
PKG_JSON_B64=$(base64 -w 0 "$APP_DIR/package.json")
INDEX_EJS_B64=$(base64 -w 0 "$APP_DIR/views/index.ejs")

# SQL Failover Group endpoint
SQL_SERVER="resiliency-fog.database.windows.net"
SQL_DATABASE="socialMediaDB"
SQL_USER="sqladmin"
SQL_PASSWORD='Workshop2024!SecurePass'

# Function to deploy to a VM
deploy_to_vm() {
    local RG=$1
    local VM_NAME=$2
    local REGION_NAME=$3
    local REGION_COLOR=$4
    
    echo ""
    echo "======================================================"
    echo "🚀 Deploying to $VM_NAME in $RG"
    echo "======================================================"
    
    az vm run-command invoke \
        --resource-group "$RG" \
        --name "$VM_NAME" \
        --command-id RunShellScript \
        --scripts "
#!/bin/bash
set -e

APP_DIR=/var/www/social-media
mkdir -p \$APP_DIR/views \$APP_DIR/public

echo '>>> Writing app.js...'
echo '$APP_JS_B64' | base64 -d > \$APP_DIR/app.js

echo '>>> Writing package.json...'
echo '$PKG_JSON_B64' | base64 -d > \$APP_DIR/package.json

echo '>>> Writing views/index.ejs...'
echo '$INDEX_EJS_B64' | base64 -d > \$APP_DIR/views/index.ejs

echo '>>> Creating .env file...'
cat > \$APP_DIR/.env << 'ENVEOF'
PORT=3000
REGION=$REGION_NAME
REGION_COLOR=$REGION_COLOR
SQL_SERVER=$SQL_SERVER
SQL_DATABASE=$SQL_DATABASE
SQL_USER=$SQL_USER
SQL_PASSWORD=$SQL_PASSWORD
SQL_ENCRYPT=true
SQL_TRUST_SERVER_CERTIFICATE=false
ENVEOF

cd \$APP_DIR
chown -R azureuser:azureuser .

echo '>>> Installing npm dependencies...'
npm install --production 2>&1

echo '>>> Starting app with PM2...'
export HOME=/root
pm2 delete social-media 2>/dev/null || true
pm2 start app.js --name social-media --update-env
pm2 save

echo '>>> Deployment Complete!'
pm2 list
" \
        --query "value[0].message" -o tsv
    
    echo "✅ $VM_NAME deployment complete"
}

# Deploy to SEA VM
deploy_to_vm "resiliency-rg-spoke-sea" "resiliency-vm-sea" "SEA (Southeast Asia)" "#28a745"

# Deploy to IDC VM
deploy_to_vm "resiliency-rg-spoke-idc" "resiliency-vm-idc" "IDC (India Central)" "#007bff"

echo ""
echo "======================================================"
echo "🎉 ALL DEPLOYMENTS COMPLETE!"
echo "======================================================"
echo ""
echo "🌐 Access URLs:"
echo "  Front Door: http://resiliency-endpoint-geggbbd9fwf3e0d2.b01.azurefd.net"
echo "  SEA Direct: http://4.194.178.252"
echo "  IDC Direct: http://48.193.41.131"
echo ""
