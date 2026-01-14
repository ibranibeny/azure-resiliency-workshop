#!/bin/bash

#############################################################################
# Azure Resiliency Workshop - Infrastructure Deployment Script
# 
# This script deploys the complete infrastructure for the resiliency demo:
# - Resource Groups in multiple regions
# - Virtual Networks
# - Azure SQL Database with Failover Groups for geo-replication
# - Virtual Machines with Node.js app
# - Azure Front Door for global load balancing
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
# - Bash shell (WSL, Linux, macOS, or Azure Cloud Shell)
#############################################################################

set -e  # Exit on error

# =============================================================================
# CONFIGURATION - Modify these variables as needed
# =============================================================================

# Subscription (uncomment and set if you have multiple subscriptions)
# SUBSCRIPTION_ID="your-subscription-id"

# Naming prefix for all resources
PREFIX="resiliency"
UNIQUE_SUFFIX=$(date +%s | tail -c 5)

# Regions
PRIMARY_REGION="southeastasia"
SECONDARY_REGION="indonesiacentral"
GLOBAL_REGION="eastus"  # For Front Door (global service)

# Resource Group Names
RG_HUB_PRIMARY="${PREFIX}-rg-hub-sea"
RG_SPOKE_PRIMARY="${PREFIX}-rg-spoke-sea"
RG_HUB_SECONDARY="${PREFIX}-rg-hub-idc"
RG_SPOKE_SECONDARY="${PREFIX}-rg-spoke-idc"
RG_GLOBAL="${PREFIX}-rg-global"

# Hub VNets
VNET_HUB_PRIMARY="${PREFIX}-vnet-hub-sea"
VNET_HUB_SECONDARY="${PREFIX}-vnet-hub-idc"

# Spoke VNets (renamed from original)
VNET_SPOKE_PRIMARY="${PREFIX}-vnet-spoke-sea"
VNET_SPOKE_SECONDARY="${PREFIX}-vnet-spoke-idc"
SUBNET_FRONTEND_PRIMARY="${PREFIX}-subnet-frontend-sea"
SUBNET_FRONTEND_SECONDARY="${PREFIX}-subnet-frontend-idc"
SUBNET_PE_PRIMARY="${PREFIX}-subnet-pe-sea"
SUBNET_PE_SECONDARY="${PREFIX}-subnet-pe-idc"
NSG_PRIMARY="${PREFIX}-nsg-sea"
NSG_SECONDARY="${PREFIX}-nsg-idc"

# Azure Firewall
FW_PRIMARY="${PREFIX}-fw-sea"
FW_SECONDARY="${PREFIX}-fw-idc"
FW_PIP_PRIMARY="${PREFIX}-fw-pip-sea"
FW_PIP_SECONDARY="${PREFIX}-fw-pip-idc"
FW_POLICY_PRIMARY="${PREFIX}-fw-policy-sea"
FW_POLICY_SECONDARY="${PREFIX}-fw-policy-idc"

# Route Tables
RT_SPOKE_PRIMARY="${PREFIX}-rt-spoke-sea"
RT_SPOKE_SECONDARY="${PREFIX}-rt-spoke-idc"

# Private DNS
PRIVATE_DNS_ZONE="privatelink.database.windows.net"

# Azure SQL Database
SQL_SERVER_PRIMARY="${PREFIX}-sql-sea-${UNIQUE_SUFFIX}"
SQL_SERVER_SECONDARY="${PREFIX}-sql-idc-${UNIQUE_SUFFIX}"
SQL_FAILOVER_GROUP="${PREFIX}-fog"
SQL_DATABASE="resiliency-db"
SQL_ADMIN_USER="sqladmin"
SQL_ADMIN_PASSWORD="Workshop2024SecurePass"  # Simple password without special chars for shell compatibility

# Virtual Machines
VM_PRIMARY="${PREFIX}-vm-sea"
VM_SECONDARY="${PREFIX}-vm-idc"
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
ADMIN_USERNAME="azureuser"

# Front Door
FRONTDOOR_NAME="${PREFIX}fd${UNIQUE_SUFFIX}"
FRONTDOOR_ENDPOINT="${PREFIX}-endpoint"

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

# =============================================================================
# SCRIPT START
# =============================================================================

print_header "Azure Resiliency Workshop - Infrastructure Deployment"
echo "Started at: $(date)"

# Set subscription if specified
if [ ! -z "$SUBSCRIPTION_ID" ]; then
    print_step "Setting subscription..."
    az account set --subscription "$SUBSCRIPTION_ID"
fi

print_info "Current subscription: $(az account show --query name -o tsv)"

# =============================================================================
# PHASE 1: Resource Groups
# =============================================================================

print_header "PHASE 1: Creating Resource Groups"

print_step "Creating Hub Resource Groups..."
az group create --name "$RG_HUB_PRIMARY" --location "$PRIMARY_REGION" --output none
print_success "Created $RG_HUB_PRIMARY"

az group create --name "$RG_HUB_SECONDARY" --location "$SECONDARY_REGION" --output none
print_success "Created $RG_HUB_SECONDARY"

print_step "Creating Spoke Resource Groups..."
az group create --name "$RG_SPOKE_PRIMARY" --location "$PRIMARY_REGION" --output none
print_success "Created $RG_SPOKE_PRIMARY"

az group create --name "$RG_SPOKE_SECONDARY" --location "$SECONDARY_REGION" --output none
print_success "Created $RG_SPOKE_SECONDARY"

print_step "Creating Global Resource Group..."
az group create --name "$RG_GLOBAL" --location "$GLOBAL_REGION" --output none
print_success "Created $RG_GLOBAL"

# =============================================================================
# PHASE 2: Hub VNets and Azure Firewall
# =============================================================================

print_header "PHASE 2: Creating Hub Networks and Firewall"

# Primary Hub VNet
print_step "Creating Hub VNet in $PRIMARY_REGION..."
az network vnet create \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "$VNET_HUB_PRIMARY" \
    --address-prefix "10.0.0.0/16" \
    --subnet-name "AzureFirewallSubnet" \
    --subnet-prefix "10.0.1.0/26" \
    --output none
print_success "Created $VNET_HUB_PRIMARY"

# Add AzureFirewallManagementSubnet for Basic SKU
print_step "Adding AzureFirewallManagementSubnet in $PRIMARY_REGION..."
az network vnet subnet create \
    --resource-group "$RG_HUB_PRIMARY" \
    --vnet-name "$VNET_HUB_PRIMARY" \
    --name "AzureFirewallManagementSubnet" \
    --address-prefix "10.0.2.0/26" \
    --output none
print_success "Created AzureFirewallManagementSubnet in $VNET_HUB_PRIMARY"

# Secondary Hub VNet
print_step "Creating Hub VNet in $SECONDARY_REGION..."
az network vnet create \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "$VNET_HUB_SECONDARY" \
    --address-prefix "10.10.0.0/16" \
    --subnet-name "AzureFirewallSubnet" \
    --subnet-prefix "10.10.1.0/26" \
    --output none
print_success "Created $VNET_HUB_SECONDARY"

# Add AzureFirewallManagementSubnet for Basic SKU
print_step "Adding AzureFirewallManagementSubnet in $SECONDARY_REGION..."
az network vnet subnet create \
    --resource-group "$RG_HUB_SECONDARY" \
    --vnet-name "$VNET_HUB_SECONDARY" \
    --name "AzureFirewallManagementSubnet" \
    --address-prefix "10.10.2.0/26" \
    --output none
print_success "Created AzureFirewallManagementSubnet in $VNET_HUB_SECONDARY"

# Create Firewall Public IPs
print_step "Creating Firewall Public IPs..."
az network public-ip create \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "$FW_PIP_PRIMARY" \
    --sku Standard \
    --allocation-method Static \
    --output none
print_success "Created $FW_PIP_PRIMARY"

az network public-ip create \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "$FW_PIP_SECONDARY" \
    --sku Standard \
    --allocation-method Static \
    --output none
print_success "Created $FW_PIP_SECONDARY"

# Create Management Public IPs for Basic SKU Firewall
print_step "Creating Firewall Management Public IPs..."
az network public-ip create \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "${FW_PRIMARY}-mgmt-pip" \
    --sku Standard \
    --allocation-method Static \
    --output none
print_success "Created ${FW_PRIMARY}-mgmt-pip"

az network public-ip create \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "${FW_SECONDARY}-mgmt-pip" \
    --sku Standard \
    --allocation-method Static \
    --output none
print_success "Created ${FW_SECONDARY}-mgmt-pip"

# Create Firewall Policies
print_step "Creating Firewall Policies..."
az network firewall policy create \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "$FW_POLICY_PRIMARY" \
    --sku Basic \
    --output none
print_success "Created $FW_POLICY_PRIMARY"

az network firewall policy create \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "$FW_POLICY_SECONDARY" \
    --sku Basic \
    --output none
print_success "Created $FW_POLICY_SECONDARY"

# Create Azure Firewalls (Basic SKU - requires both data and management IP configurations)
print_step "Creating Azure Firewall in $PRIMARY_REGION..."
print_info "This may take 5-10 minutes..."
az network firewall create \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "$FW_PRIMARY" \
    --sku AZFW_VNet \
    --tier Basic \
    --vnet-name "$VNET_HUB_PRIMARY" \
    --firewall-policy "$FW_POLICY_PRIMARY" \
    --conf-name "data-ip-config" \
    --public-ip "$FW_PIP_PRIMARY" \
    --m-conf-name "mgmt-ip-config" \
    --m-public-ip "${FW_PRIMARY}-mgmt-pip" \
    --output none
print_success "Created $FW_PRIMARY"

print_step "Creating Azure Firewall in $SECONDARY_REGION..."
print_info "This may take 5-10 minutes..."
az network firewall create \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "$FW_SECONDARY" \
    --sku AZFW_VNet \
    --tier Basic \
    --vnet-name "$VNET_HUB_SECONDARY" \
    --firewall-policy "$FW_POLICY_SECONDARY" \
    --conf-name "data-ip-config" \
    --public-ip "$FW_PIP_SECONDARY" \
    --m-conf-name "mgmt-ip-config" \
    --m-public-ip "${FW_SECONDARY}-mgmt-pip" \
    --output none
print_success "Created $FW_SECONDARY"

# Get Firewall Private IPs (for route tables)
FW_PRIVATE_IP_PRIMARY=$(az network firewall show \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "$FW_PRIMARY" \
    --query "ipConfigurations[0].privateIPAddress" -o tsv)

FW_PRIVATE_IP_SECONDARY=$(az network firewall show \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "$FW_SECONDARY" \
    --query "ipConfigurations[0].privateIPAddress" -o tsv)

print_info "Firewall Private IP (SEA): $FW_PRIVATE_IP_PRIMARY"
print_info "Firewall Private IP (IDC): $FW_PRIVATE_IP_SECONDARY"

# Get Firewall Public IPs (for Front Door)
FW_PUBLIC_IP_PRIMARY=$(az network public-ip show \
    --resource-group "$RG_HUB_PRIMARY" \
    --name "$FW_PIP_PRIMARY" \
    --query "ipAddress" -o tsv)

FW_PUBLIC_IP_SECONDARY=$(az network public-ip show \
    --resource-group "$RG_HUB_SECONDARY" \
    --name "$FW_PIP_SECONDARY" \
    --query "ipAddress" -o tsv)

print_info "Firewall Public IP (SEA): $FW_PUBLIC_IP_PRIMARY"
print_info "Firewall Public IP (IDC): $FW_PUBLIC_IP_SECONDARY"

# =============================================================================
# PHASE 3: Spoke VNets and Subnets
# =============================================================================

print_header "PHASE 3: Creating Spoke Networks"

# Primary Spoke VNet
print_step "Creating Spoke VNet in $PRIMARY_REGION..."
az network vnet create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --name "$VNET_SPOKE_PRIMARY" \
    --address-prefix "10.1.0.0/16" \
    --subnet-name "$SUBNET_FRONTEND_PRIMARY" \
    --subnet-prefix "10.1.1.0/24" \
    --output none

# Add Private Endpoint subnet for Primary Region
az network vnet subnet create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --name "$SUBNET_PE_PRIMARY" \
    --address-prefix "10.1.2.0/24" \
    --output none

print_success "Created $VNET_SPOKE_PRIMARY with subnets"

# Secondary Spoke VNet
print_step "Creating Spoke VNet in $SECONDARY_REGION..."
az network vnet create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --name "$VNET_SPOKE_SECONDARY" \
    --address-prefix "10.2.0.0/16" \
    --subnet-name "$SUBNET_FRONTEND_SECONDARY" \
    --subnet-prefix "10.2.1.0/24" \
    --output none

# Add Private Endpoint subnet for Secondary Region
az network vnet subnet create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --vnet-name "$VNET_SPOKE_SECONDARY" \
    --name "$SUBNET_PE_SECONDARY" \
    --address-prefix "10.2.2.0/24" \
    --output none

print_success "Created $VNET_SPOKE_SECONDARY with subnets"

# =============================================================================
# PHASE 4: VNet Peering (Hub ↔ Spoke)
# =============================================================================

print_header "PHASE 4: Configuring VNet Peering"

# Get VNet Resource IDs
print_step "Getting VNet Resource IDs..."
HUB_PRIMARY_ID=$(az network vnet show -g "$RG_HUB_PRIMARY" -n "$VNET_HUB_PRIMARY" --query id -o tsv)
SPOKE_PRIMARY_ID=$(az network vnet show -g "$RG_SPOKE_PRIMARY" -n "$VNET_SPOKE_PRIMARY" --query id -o tsv)
HUB_SECONDARY_ID=$(az network vnet show -g "$RG_HUB_SECONDARY" -n "$VNET_HUB_SECONDARY" --query id -o tsv)
SPOKE_SECONDARY_ID=$(az network vnet show -g "$RG_SPOKE_SECONDARY" -n "$VNET_SPOKE_SECONDARY" --query id -o tsv)

# Primary Region Peering: Hub ↔ Spoke
print_step "Creating VNet peering: Hub-SEA ↔ Spoke-SEA..."
az network vnet peering create \
    --name "hub-to-spoke-sea" \
    --resource-group "$RG_HUB_PRIMARY" \
    --vnet-name "$VNET_HUB_PRIMARY" \
    --remote-vnet "$SPOKE_PRIMARY_ID" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --allow-gateway-transit \
    --output none

az network vnet peering create \
    --name "spoke-to-hub-sea" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --remote-vnet "$HUB_PRIMARY_ID" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --use-remote-gateways false \
    --output none

print_success "Created peering for Southeast Asia region"

# Secondary Region Peering: Hub ↔ Spoke
print_step "Creating VNet peering: Hub-IDC ↔ Spoke-IDC..."
az network vnet peering create \
    --name "hub-to-spoke-idc" \
    --resource-group "$RG_HUB_SECONDARY" \
    --vnet-name "$VNET_HUB_SECONDARY" \
    --remote-vnet "$SPOKE_SECONDARY_ID" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --allow-gateway-transit \
    --output none

az network vnet peering create \
    --name "spoke-to-hub-idc" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --vnet-name "$VNET_SPOKE_SECONDARY" \
    --remote-vnet "$HUB_SECONDARY_ID" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --use-remote-gateways false \
    --output none

print_success "Created peering for Indonesia Central region"

# =============================================================================
# PHASE 5: Route Tables (UDR) for Traffic through Firewall
# =============================================================================

print_header "PHASE 5: Creating Route Tables"

# Create Route Table for Primary Spoke
print_step "Creating Route Table for Southeast Asia Spoke..."
az network route-table create \
    --name "$RT_SPOKE_PRIMARY" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --location "$PRIMARY_REGION" \
    --disable-bgp-route-propagation true \
    --output none

# Route all internet traffic through Firewall
az network route-table route create \
    --name "route-to-internet" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --route-table-name "$RT_SPOKE_PRIMARY" \
    --address-prefix "0.0.0.0/0" \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_PRIVATE_IP_PRIMARY" \
    --output none

# Associate Route Table with Frontend Subnet
az network vnet subnet update \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --name "$SUBNET_FRONTEND_PRIMARY" \
    --route-table "$RT_SPOKE_PRIMARY" \
    --output none

print_success "Created and associated Route Table for Southeast Asia"

# Create Route Table for Secondary Spoke
print_step "Creating Route Table for Indonesia Central Spoke..."
az network route-table create \
    --name "$RT_SPOKE_SECONDARY" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --location "$SECONDARY_REGION" \
    --disable-bgp-route-propagation true \
    --output none

az network route-table route create \
    --name "route-to-internet" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --route-table-name "$RT_SPOKE_SECONDARY" \
    --address-prefix "0.0.0.0/0" \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_PRIVATE_IP_SECONDARY" \
    --output none

az network vnet subnet update \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --vnet-name "$VNET_SPOKE_SECONDARY" \
    --name "$SUBNET_FRONTEND_SECONDARY" \
    --route-table "$RT_SPOKE_SECONDARY" \
    --output none

print_success "Created and associated Route Table for Indonesia Central"

# =============================================================================
# PHASE 6: Network Security Groups
# =============================================================================

print_header "PHASE 6: Creating Network Security Groups"

print_step "Creating NSG for $PRIMARY_REGION Spoke..."
az network nsg create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --name "$NSG_PRIMARY" \
    --output none

# Allow HTTP from Firewall subnet
az network nsg rule create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --nsg-name "$NSG_PRIMARY" \
    --name "AllowHTTPFromFirewall" \
    --priority 100 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --source-address-prefixes "10.0.0.0/24" \
    --destination-port-ranges 80 \
    --output none

# Allow HTTPS from Firewall subnet
az network nsg rule create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --nsg-name "$NSG_PRIMARY" \
    --name "AllowHTTPSFromFirewall" \
    --priority 110 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --source-address-prefixes "10.0.0.0/24" \
    --destination-port-ranges 443 \
    --output none

# Allow SSH from Hub (for management via Bastion/Jumpbox)
az network nsg rule create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --nsg-name "$NSG_PRIMARY" \
    --name "AllowSSHFromHub" \
    --priority 120 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --source-address-prefixes "10.0.0.0/16" \
    --destination-port-ranges 22 \
    --output none

print_success "Created $NSG_PRIMARY with rules"

print_step "Creating NSG for $SECONDARY_REGION Spoke..."
az network nsg create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --name "$NSG_SECONDARY" \
    --output none

az network nsg rule create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --nsg-name "$NSG_SECONDARY" \
    --name "AllowHTTPFromFirewall" \
    --priority 100 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --source-address-prefixes "10.10.0.0/24" \
    --destination-port-ranges 80 \
    --output none

az network nsg rule create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --nsg-name "$NSG_SECONDARY" \
    --name "AllowHTTPSFromFirewall" \
    --priority 110 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --source-address-prefixes "10.10.0.0/24" \
    --destination-port-ranges 443 \
    --output none

az network nsg rule create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --nsg-name "$NSG_SECONDARY" \
    --name "AllowSSHFromHub" \
    --priority 120 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --source-address-prefixes "10.10.0.0/16" \
    --destination-port-ranges 22 \
    --output none

print_success "Created $NSG_SECONDARY with rules"

# Associate NSGs with Spoke subnets
print_step "Associating NSGs with Spoke subnets..."
az network vnet subnet update \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --name "$SUBNET_FRONTEND_PRIMARY" \
    --network-security-group "$NSG_PRIMARY" \
    --output none

az network vnet subnet update \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --vnet-name "$VNET_SPOKE_SECONDARY" \
    --name "$SUBNET_FRONTEND_SECONDARY" \
    --network-security-group "$NSG_SECONDARY" \
    --output none

print_success "NSGs associated with Spoke subnets"

# =============================================================================
# PHASE 7: Azure SQL Database with Failover Groups
# =============================================================================

print_header "PHASE 7: Creating Azure SQL Database with Failover Groups"

# Create Primary SQL Server (Southeast Asia) - in Spoke RG for Private Endpoint
print_step "Creating Primary SQL Server: $SQL_SERVER_PRIMARY"
print_info "This may take 2-3 minutes..."

az sql server create \
    --name "$SQL_SERVER_PRIMARY" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --location "$PRIMARY_REGION" \
    --admin-user "$SQL_ADMIN_USER" \
    --admin-password "$SQL_ADMIN_PASSWORD" \
    --enable-public-network true \
    --output none

print_success "Created Primary SQL Server: $SQL_SERVER_PRIMARY"

# Create Secondary SQL Server (Indonesia Central) - in Spoke RG for Private Endpoint
print_step "Creating Secondary SQL Server: $SQL_SERVER_SECONDARY"

az sql server create \
    --name "$SQL_SERVER_SECONDARY" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --location "$SECONDARY_REGION" \
    --admin-user "$SQL_ADMIN_USER" \
    --admin-password "$SQL_ADMIN_PASSWORD" \
    --enable-public-network true \
    --output none

print_success "Created Secondary SQL Server: $SQL_SERVER_SECONDARY"

# Note: SQL firewall rules are not needed when using Private Endpoints
# Public network access will be disabled after Private Endpoints are created

# Create Database on Primary Server
print_step "Creating Database: $SQL_DATABASE"

az sql db create \
    --name "$SQL_DATABASE" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --server "$SQL_SERVER_PRIMARY" \
    --edition "GeneralPurpose" \
    --family "Gen5" \
    --capacity 2 \
    --compute-model "Provisioned" \
    --output none

print_success "Created Database: $SQL_DATABASE"

# Create Failover Group
print_step "Creating Failover Group: $SQL_FAILOVER_GROUP"
print_info "This may take 3-5 minutes..."

az sql failover-group create \
    --name "$SQL_FAILOVER_GROUP" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --server "$SQL_SERVER_PRIMARY" \
    --partner-server "$SQL_SERVER_SECONDARY" \
    --partner-resource-group "$RG_SPOKE_SECONDARY" \
    --add-db "$SQL_DATABASE" \
    --failover-policy Automatic \
    --grace-period 60 \
    --output none

print_success "Created Failover Group with automatic failover"

# Get Failover Group listener endpoint
SQL_LISTENER="${SQL_FAILOVER_GROUP}.database.windows.net"
print_info "Failover Group Listener: $SQL_LISTENER"

# =============================================================================
# PHASE 7.1: Private DNS Zone for Azure SQL
# =============================================================================

print_step "Creating Private DNS Zone: $PRIVATE_DNS_ZONE"
az network private-dns zone create \
    --resource-group "$RG_GLOBAL" \
    --name "$PRIVATE_DNS_ZONE" \
    --output none

print_success "Created Private DNS Zone"

# Link DNS Zone to Spoke VNets
print_step "Linking Private DNS Zone to Spoke VNets..."
az network private-dns link vnet create \
    --resource-group "$RG_GLOBAL" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "dns-link-spoke-sea" \
    --virtual-network "$SPOKE_PRIMARY_ID" \
    --registration-enabled false \
    --output none

az network private-dns link vnet create \
    --resource-group "$RG_GLOBAL" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "dns-link-spoke-idc" \
    --virtual-network "$SPOKE_SECONDARY_ID" \
    --registration-enabled false \
    --output none

print_success "Private DNS Zone linked to both Spoke VNets"

# =============================================================================
# PHASE 7.2: Private Endpoints for Azure SQL
# =============================================================================

print_header "PHASE 7.2: Creating Private Endpoints for Azure SQL"

# Get SQL Server IDs
SQL_SERVER_PRIMARY_ID=$(az sql server show --name "$SQL_SERVER_PRIMARY" --resource-group "$RG_SPOKE_PRIMARY" --query id -o tsv)
SQL_SERVER_SECONDARY_ID=$(az sql server show --name "$SQL_SERVER_SECONDARY" --resource-group "$RG_SPOKE_SECONDARY" --query id -o tsv)

# Create Private Endpoint for Primary SQL Server
print_step "Creating Private Endpoint for Primary SQL Server..."
az network private-endpoint create \
    --name "pe-sql-sea" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --subnet "$SUBNET_PE_PRIMARY" \
    --private-connection-resource-id "$SQL_SERVER_PRIMARY_ID" \
    --group-id "sqlServer" \
    --connection-name "pe-sql-sea-connection" \
    --output none

print_success "Created Private Endpoint: pe-sql-sea"

# Create Private Endpoint for Secondary SQL Server
print_step "Creating Private Endpoint for Secondary SQL Server..."
az network private-endpoint create \
    --name "pe-sql-idc" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --vnet-name "$VNET_SPOKE_SECONDARY" \
    --subnet "$SUBNET_PE_SECONDARY" \
    --private-connection-resource-id "$SQL_SERVER_SECONDARY_ID" \
    --group-id "sqlServer" \
    --connection-name "pe-sql-idc-connection" \
    --output none

print_success "Created Private Endpoint: pe-sql-idc"

# Get Private IP addresses from Private Endpoints
PE_IP_PRIMARY=$(az network private-endpoint show \
    --name "pe-sql-sea" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)

PE_IP_SECONDARY=$(az network private-endpoint show \
    --name "pe-sql-idc" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)

print_info "Private Endpoint IP (SEA): $PE_IP_PRIMARY"
print_info "Private Endpoint IP (IDC): $PE_IP_SECONDARY"

# Create DNS A records in Private DNS Zone
print_step "Creating DNS A records in Private DNS Zone..."

# Primary SQL Server DNS record
az network private-dns record-set a create \
    --name "$SQL_SERVER_PRIMARY" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --resource-group "$RG_GLOBAL" \
    --output none 2>/dev/null || true

az network private-dns record-set a add-record \
    --record-set-name "$SQL_SERVER_PRIMARY" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --resource-group "$RG_GLOBAL" \
    --ipv4-address "$PE_IP_PRIMARY" \
    --output none

print_success "Created DNS record: $SQL_SERVER_PRIMARY -> $PE_IP_PRIMARY"

# Secondary SQL Server DNS record
az network private-dns record-set a create \
    --name "$SQL_SERVER_SECONDARY" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --resource-group "$RG_GLOBAL" \
    --output none 2>/dev/null || true

az network private-dns record-set a add-record \
    --record-set-name "$SQL_SERVER_SECONDARY" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --resource-group "$RG_GLOBAL" \
    --ipv4-address "$PE_IP_SECONDARY" \
    --output none

print_success "Created DNS record: $SQL_SERVER_SECONDARY -> $PE_IP_SECONDARY"

# Failover Group listener DNS record (points to primary)
az network private-dns record-set a create \
    --name "$SQL_FAILOVER_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --resource-group "$RG_GLOBAL" \
    --output none 2>/dev/null || true

az network private-dns record-set a add-record \
    --record-set-name "$SQL_FAILOVER_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --resource-group "$RG_GLOBAL" \
    --ipv4-address "$PE_IP_PRIMARY" \
    --output none

print_success "Created DNS record: $SQL_FAILOVER_GROUP -> $PE_IP_PRIMARY"

# Disable public network access on SQL servers
print_step "Disabling public network access on SQL servers..."
az sql server update \
    --name "$SQL_SERVER_PRIMARY" \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --enable-public-network false \
    --output none

az sql server update \
    --name "$SQL_SERVER_SECONDARY" \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --enable-public-network false \
    --output none

print_success "Disabled public network access on SQL servers"

print_success "SQL setup complete with Private Endpoints"
print_info "SQL Failover Group Listener: $SQL_LISTENER"
print_info "SQL Admin User: $SQL_ADMIN_USER"
print_info "SQL Admin Password: $SQL_ADMIN_PASSWORD"
print_info "Private Endpoint IP (SEA): $PE_IP_PRIMARY"
print_info "Private Endpoint IP (IDC): $PE_IP_SECONDARY"

# =============================================================================
# PHASE 8: Virtual Machines (No Public IP - Access via Firewall DNAT)
# =============================================================================

print_header "PHASE 8: Creating Virtual Machines"

# Create cloud-init script for VM configuration
print_step "Preparing cloud-init configuration..."

cat > /tmp/cloud-init-sea.yaml << 'CLOUDINIT'
#cloud-config
package_update: true
package_upgrade: true

packages:
  - nginx
  - git

runcmd:
  # Install Node.js 18
  - curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  - apt-get install -y nodejs
  
  # Install PM2 globally
  - npm install -g pm2
  
  # Create app directory
  - mkdir -p /var/www/social-media
  - chown -R azureuser:azureuser /var/www/social-media
  
  # Configure Nginx
  - |
    cat > /etc/nginx/sites-available/default << 'NGINX'
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
  - systemctl restart nginx
  - systemctl enable nginx

final_message: "Cloud-init completed at $UPTIME seconds"
CLOUDINIT

cat > /tmp/cloud-init-idc.yaml << 'CLOUDINIT'
#cloud-config
package_update: true
package_upgrade: true

packages:
  - nginx
  - git

runcmd:
  # Install Node.js 18
  - curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  - apt-get install -y nodejs
  
  # Install PM2 globally
  - npm install -g pm2
  
  # Create app directory
  - mkdir -p /var/www/social-media
  - chown -R azureuser:azureuser /var/www/social-media
  
  # Configure Nginx
  - |
    cat > /etc/nginx/sites-available/default << 'NGINX'
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
  - systemctl restart nginx
  - systemctl enable nginx

final_message: "Cloud-init completed at $UPTIME seconds"
CLOUDINIT

# Create Primary VM (Southeast Asia) - NO Public IP
print_step "Creating VM in $PRIMARY_REGION: $VM_PRIMARY (no public IP)"
print_info "This may take 2-3 minutes..."

az vm create \
    --resource-group "$RG_SPOKE_PRIMARY" \
    --name "$VM_PRIMARY" \
    --image "$VM_IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --generate-ssh-keys \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --subnet "$SUBNET_FRONTEND_PRIMARY" \
    --nsg "" \
    --public-ip-address "" \
    --custom-data /tmp/cloud-init-sea.yaml \
    --output none

print_success "Created $VM_PRIMARY (private IP only)"

# Create Secondary VM (Indonesia Central) - NO Public IP
print_step "Creating VM in $SECONDARY_REGION: $VM_SECONDARY (no public IP)"
print_info "This may take 2-3 minutes..."

az vm create \
    --resource-group "$RG_SPOKE_SECONDARY" \
    --name "$VM_SECONDARY" \
    --image "$VM_IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --generate-ssh-keys \
    --vnet-name "$VNET_SPOKE_SECONDARY" \
    --subnet "$SUBNET_FRONTEND_SECONDARY" \
    --nsg "" \
    --public-ip-address "" \
    --custom-data /tmp/cloud-init-idc.yaml \
    --output none

print_success "Created $VM_SECONDARY (private IP only)"

# Get VM Private IPs (for DNAT rules)
VM_PRIMARY_PRIVATE_IP=$(az vm show -g "$RG_SPOKE_PRIMARY" -n "$VM_PRIMARY" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv | \
    xargs -I {} az network nic show --ids {} --query "ipConfigurations[0].privateIPAddress" -o tsv)

VM_SECONDARY_PRIVATE_IP=$(az vm show -g "$RG_SPOKE_SECONDARY" -n "$VM_SECONDARY" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv | \
    xargs -I {} az network nic show --ids {} --query "ipConfigurations[0].privateIPAddress" -o tsv)

print_info "Primary VM Private IP (Southeast Asia): $VM_PRIMARY_PRIVATE_IP"
print_info "Secondary VM Private IP (Indonesia Central): $VM_SECONDARY_PRIVATE_IP"

# =============================================================================
# PHASE 9: Azure Firewall DNAT Rules
# =============================================================================

print_header "PHASE 9: Configuring Firewall DNAT Rules"

# Create DNAT Rule Collection for Primary Firewall (SEA)
print_step "Adding DNAT rules to Primary Firewall (SEA)..."

az network firewall policy rule-collection-group create \
    --name "dnat-rules" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --priority 100 \
    --output none

az network firewall policy rule-collection-group collection add-nat-collection \
    --name "nat-web-traffic" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --rule-collection-group-name "dnat-rules" \
    --collection-priority 100 \
    --action DNAT \
    --rule-name "allow-http" \
    --source-addresses "*" \
    --destination-addresses "$FW_PUBLIC_IP_PRIMARY" \
    --destination-ports 80 \
    --ip-protocols TCP \
    --translated-address "$VM_PRIMARY_PRIVATE_IP" \
    --translated-port 80 \
    --output none

print_success "Added DNAT rules for Primary Firewall"

# Create DNAT Rule Collection for Secondary Firewall (IDC)
print_step "Adding DNAT rules to Secondary Firewall (IDC)..."

az network firewall policy rule-collection-group create \
    --name "dnat-rules" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --priority 100 \
    --output none

az network firewall policy rule-collection-group collection add-nat-collection \
    --name "nat-web-traffic" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --rule-collection-group-name "dnat-rules" \
    --collection-priority 100 \
    --action DNAT \
    --rule-name "allow-http" \
    --source-addresses "*" \
    --destination-addresses "$FW_PUBLIC_IP_SECONDARY" \
    --destination-ports 80 \
    --ip-protocols TCP \
    --translated-address "$VM_SECONDARY_PRIVATE_IP" \
    --translated-port 80 \
    --output none

print_success "Added DNAT rules for Secondary Firewall"

# Add Network Rules to allow outbound traffic from VMs
print_step "Adding network rules for outbound traffic..."

az network firewall policy rule-collection-group create \
    --name "network-rules" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --priority 200 \
    --output none

# Allow all outbound traffic (for internet access during npm install, etc.)
az network firewall policy rule-collection-group collection add-filter-collection \
    --name "allow-outbound" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --rule-collection-group-name "network-rules" \
    --collection-priority 100 \
    --action Allow \
    --rule-name "allow-all-tcp-outbound" \
    --rule-type NetworkRule \
    --source-addresses "10.1.0.0/16" \
    --destination-addresses "*" \
    --destination-ports "1-65535" \
    --ip-protocols TCP \
    --output none

# Add UDP outbound rule for DNS/NTP
az network firewall policy rule-collection-group collection rule add \
    --name "allow-all-udp-outbound" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --rule-collection-group-name "network-rules" \
    --collection-name "allow-outbound" \
    --rule-type NetworkRule \
    --source-addresses "10.1.0.0/16" \
    --destination-addresses "*" \
    --destination-ports "1-65535" \
    --ip-protocols UDP \
    --output none

# Add specific SQL outbound rules (port 1433 + redirect ports 11000-11999)
print_step "Adding SQL outbound rules for Azure SQL connectivity..."
az network firewall policy rule-collection-group collection add-filter-collection \
    --name "allow-sql-outbound" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --rule-collection-group-name "network-rules" \
    --collection-priority 110 \
    --action Allow \
    --rule-name "allow-sql-1433" \
    --rule-type NetworkRule \
    --source-addresses "10.1.0.0/16" \
    --destination-addresses "Sql" \
    --destination-ports "1433" \
    --ip-protocols TCP \
    --output none

az network firewall policy rule-collection-group collection rule add \
    --name "allow-sql-redirect" \
    --policy-name "$FW_POLICY_PRIMARY" \
    --resource-group "$RG_HUB_PRIMARY" \
    --rule-collection-group-name "network-rules" \
    --collection-name "allow-sql-outbound" \
    --rule-type NetworkRule \
    --source-addresses "10.1.0.0/16" \
    --destination-addresses "Sql" \
    --destination-ports "11000-11999" \
    --ip-protocols TCP \
    --output none

print_success "Added SQL outbound rules for SEA firewall"

az network firewall policy rule-collection-group create \
    --name "network-rules" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --priority 200 \
    --output none

az network firewall policy rule-collection-group collection add-filter-collection \
    --name "allow-outbound" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --rule-collection-group-name "network-rules" \
    --collection-priority 100 \
    --action Allow \
    --rule-name "allow-all-tcp-outbound" \
    --rule-type NetworkRule \
    --source-addresses "10.2.0.0/16" \
    --destination-addresses "*" \
    --destination-ports "1-65535" \
    --ip-protocols TCP \
    --output none

# Add UDP outbound rule for DNS/NTP
az network firewall policy rule-collection-group collection rule add \
    --name "allow-all-udp-outbound" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --rule-collection-group-name "network-rules" \
    --collection-name "allow-outbound" \
    --rule-type NetworkRule \
    --source-addresses "10.2.0.0/16" \
    --destination-addresses "*" \
    --destination-ports "1-65535" \
    --ip-protocols UDP \
    --output none

# Add SQL outbound rules for IDC firewall
az network firewall policy rule-collection-group collection add-filter-collection \
    --name "allow-sql-outbound" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --rule-collection-group-name "network-rules" \
    --collection-priority 110 \
    --action Allow \
    --rule-name "allow-sql-1433" \
    --rule-type NetworkRule \
    --source-addresses "10.2.0.0/16" \
    --destination-addresses "Sql" \
    --destination-ports "1433" \
    --ip-protocols TCP \
    --output none

az network firewall policy rule-collection-group collection rule add \
    --name "allow-sql-redirect" \
    --policy-name "$FW_POLICY_SECONDARY" \
    --resource-group "$RG_HUB_SECONDARY" \
    --rule-collection-group-name "network-rules" \
    --collection-name "allow-sql-outbound" \
    --rule-type NetworkRule \
    --source-addresses "10.2.0.0/16" \
    --destination-addresses "Sql" \
    --destination-ports "11000-11999" \
    --ip-protocols TCP \
    --output none

print_success "Added SQL outbound rules for IDC firewall"
print_success "Added network rules for outbound traffic"

# =============================================================================
# PHASE 10: Azure Front Door
# =============================================================================

print_header "PHASE 10: Creating Azure Front Door"

print_step "Creating Front Door profile: $FRONTDOOR_NAME"

# Create Front Door profile (Standard tier)
az afd profile create \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --sku Standard_AzureFrontDoor \
    --output none

print_success "Created Front Door profile"

# Create endpoint
print_step "Creating Front Door endpoint..."
az afd endpoint create \
    --endpoint-name "$FRONTDOOR_ENDPOINT" \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --enabled-state Enabled \
    --output none

print_success "Created Front Door endpoint"

# Create origin group with health probe
print_step "Creating origin group with health probe..."
az afd origin-group create \
    --origin-group-name "og-frontend" \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --probe-path "/health" \
    --probe-protocol Http \
    --probe-request-type GET \
    --probe-interval-in-seconds 30 \
    --sample-size 4 \
    --successful-samples-required 3 \
    --additional-latency-in-milliseconds 50 \
    --output none

print_success "Created origin group"

# Add primary origin (Southeast Asia via Firewall) - Priority 1
print_step "Adding primary origin (Southeast Asia via Firewall)..."
az afd origin create \
    --origin-name "origin-sea" \
    --origin-group-name "og-frontend" \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --host-name "$FW_PUBLIC_IP_PRIMARY" \
    --origin-host-header "$FW_PUBLIC_IP_PRIMARY" \
    --http-port 80 \
    --https-port 443 \
    --priority 1 \
    --weight 1000 \
    --enabled-state Enabled \
    --output none

print_success "Added primary origin (via Firewall: $FW_PUBLIC_IP_PRIMARY)"

# Add secondary origin (Indonesia Central via Firewall) - Priority 2
print_step "Adding secondary origin (Indonesia Central via Firewall)..."
az afd origin create \
    --origin-name "origin-idc" \
    --origin-group-name "og-frontend" \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --host-name "$FW_PUBLIC_IP_SECONDARY" \
    --origin-host-header "$FW_PUBLIC_IP_SECONDARY" \
    --http-port 80 \
    --https-port 443 \
    --priority 2 \
    --weight 1000 \
    --enabled-state Enabled \
    --output none

print_success "Added secondary origin (via Firewall: $FW_PUBLIC_IP_SECONDARY)"

# Create route
print_step "Creating route..."
az afd route create \
    --route-name "route-default" \
    --endpoint-name "$FRONTDOOR_ENDPOINT" \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --origin-group "og-frontend" \
    --supported-protocols Http Https \
    --patterns "/*" \
    --forwarding-protocol HttpOnly \
    --https-redirect Disabled \
    --link-to-default-domain Enabled \
    --output none

print_success "Created route"

# Get Front Door endpoint URL
FRONTDOOR_URL=$(az afd endpoint show \
    --endpoint-name "$FRONTDOOR_ENDPOINT" \
    --profile-name "$FRONTDOOR_NAME" \
    --resource-group "$RG_GLOBAL" \
    --query hostName -o tsv)

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

print_header "DEPLOYMENT COMPLETE!"

echo ""
echo "📋 RESOURCE SUMMARY - Hub-Spoke Architecture"
echo "============================================================================="
echo ""
echo "Resource Groups:"
echo "  - $RG_HUB_PRIMARY (Hub - $PRIMARY_REGION)"
echo "  - $RG_SPOKE_PRIMARY (Spoke - $PRIMARY_REGION)"
echo "  - $RG_HUB_SECONDARY (Hub - $SECONDARY_REGION)"
echo "  - $RG_SPOKE_SECONDARY (Spoke - $SECONDARY_REGION)"
echo "  - $RG_GLOBAL (Global Resources)"
echo ""
echo "Hub VNets & Firewalls:"
echo "  - Hub SEA: $VNET_HUB_PRIMARY (10.0.0.0/16)"
echo "    - Firewall: $FW_PRIMARY (Public IP: $FW_PUBLIC_IP_PRIMARY)"
echo "  - Hub IDC: $VNET_HUB_SECONDARY (10.10.0.0/16)"
echo "    - Firewall: $FW_SECONDARY (Public IP: $FW_PUBLIC_IP_SECONDARY)"
echo ""
echo "Spoke VNets:"
echo "  - Spoke SEA: $VNET_SPOKE_PRIMARY (10.1.0.0/16)"
echo "  - Spoke IDC: $VNET_SPOKE_SECONDARY (10.2.0.0/16)"
echo ""
echo "Azure SQL Database:"
echo "  - Primary Server: $SQL_SERVER_PRIMARY ($PRIMARY_REGION)"
echo "  - Secondary Server: $SQL_SERVER_SECONDARY ($SECONDARY_REGION)"
echo "  - Failover Group: $SQL_FAILOVER_GROUP"
echo "  - Listener Endpoint: $SQL_LISTENER"
echo "  - Database: $SQL_DATABASE"
echo "  - Admin User: $SQL_ADMIN_USER"
echo "  - 🔒 Public Access: DISABLED (using Private Endpoints)"
echo "  - Private Endpoint IP (SEA): $PE_IP_PRIMARY"
echo "  - Private Endpoint IP (IDC): $PE_IP_SECONDARY"
echo ""
echo "Virtual Machines (Private IPs only - access via Firewall DNAT):"
echo "  - Primary (SEA): $VM_PRIMARY (Private: $VM_PRIMARY_PRIVATE_IP)"
echo "  - Secondary (IDC): $VM_SECONDARY (Private: $VM_SECONDARY_PRIVATE_IP)"
echo ""
echo "Azure Front Door:"
echo "  - URL: https://$FRONTDOOR_URL"
echo "  - Origins: Firewall Public IPs (DNAT to VMs)"
echo ""
echo "============================================================================="
echo ""

# Save configuration to file
cat > deployment-output.txt << EOF
# Azure Resiliency Workshop - Deployment Output
# Hub-Spoke Architecture with Azure Firewall
# Generated: $(date)

## Resource Groups
RG_HUB_PRIMARY=$RG_HUB_PRIMARY
RG_SPOKE_PRIMARY=$RG_SPOKE_PRIMARY
RG_HUB_SECONDARY=$RG_HUB_SECONDARY
RG_SPOKE_SECONDARY=$RG_SPOKE_SECONDARY
RG_GLOBAL=$RG_GLOBAL

## Hub VNets & Firewalls
VNET_HUB_PRIMARY=$VNET_HUB_PRIMARY
FW_PRIMARY=$FW_PRIMARY
FW_PUBLIC_IP_PRIMARY=$FW_PUBLIC_IP_PRIMARY
FW_PRIVATE_IP_PRIMARY=$FW_PRIVATE_IP_PRIMARY

VNET_HUB_SECONDARY=$VNET_HUB_SECONDARY
FW_SECONDARY=$FW_SECONDARY
FW_PUBLIC_IP_SECONDARY=$FW_PUBLIC_IP_SECONDARY
FW_PRIVATE_IP_SECONDARY=$FW_PRIVATE_IP_SECONDARY

## Spoke VNets
VNET_SPOKE_PRIMARY=$VNET_SPOKE_PRIMARY
VNET_SPOKE_SECONDARY=$VNET_SPOKE_SECONDARY

## Azure SQL Database
SQL_SERVER_PRIMARY=$SQL_SERVER_PRIMARY
SQL_SERVER_SECONDARY=$SQL_SERVER_SECONDARY
SQL_FAILOVER_GROUP=$SQL_FAILOVER_GROUP
SQL_LISTENER=$SQL_LISTENER
SQL_DATABASE=$SQL_DATABASE
SQL_ADMIN_USER=$SQL_ADMIN_USER
SQL_ADMIN_PASSWORD=$SQL_ADMIN_PASSWORD
SQL_ACCESS_MODE="Private Endpoints (public access disabled)"
PE_IP_PRIMARY=$PE_IP_PRIMARY
PE_IP_SECONDARY=$PE_IP_SECONDARY

## Virtual Machines (Private IPs - No Public Access)
VM_PRIMARY=$VM_PRIMARY
VM_PRIMARY_PRIVATE_IP=$VM_PRIMARY_PRIVATE_IP
VM_SECONDARY=$VM_SECONDARY
VM_SECONDARY_PRIVATE_IP=$VM_SECONDARY_PRIVATE_IP
ADMIN_USERNAME=$ADMIN_USERNAME

## Front Door
FRONTDOOR_NAME=$FRONTDOOR_NAME
FRONTDOOR_URL=$FRONTDOOR_URL

## Quick Commands
#
# Access Application via Front Door:
# curl http://$FRONTDOOR_URL
#
# Access Primary VM via Firewall Public IP:
# curl http://$FW_PUBLIC_IP_PRIMARY
#
# Access Secondary VM via Firewall Public IP:
# curl http://$FW_PUBLIC_IP_SECONDARY
#
# Stop Primary VM (for failover demo):
# az vm stop --resource-group $RG_SPOKE_PRIMARY --name $VM_PRIMARY --no-wait
#
# Start Primary VM:
# az vm start --resource-group $RG_SPOKE_PRIMARY --name $VM_PRIMARY --no-wait
#
# Stop Secondary VM:
# az vm stop --resource-group $RG_SPOKE_SECONDARY --name $VM_SECONDARY --no-wait
#
# Start Secondary VM:
# az vm start --resource-group $RG_SPOKE_SECONDARY --name $VM_SECONDARY --no-wait
#
# Note: VMs have no public IPs. SSH requires Azure Bastion or VPN connection to Hub VNet.
EOF

print_success "Configuration saved to deployment-output.txt"
print_info "IMPORTANT: Please wait 3-5 minutes for VMs to complete initialization"
print_info "Then run the app deployment script: ./02-deploy-app.sh"
print_info ""
print_info "NOTE: VMs have no public IPs. To SSH, you need:"
print_info "  1. Deploy Azure Bastion in the Hub VNet, OR"
print_info "  2. Add SSH DNAT rules to the Firewall, OR"
print_info "  3. Connect via VPN/ExpressRoute"

echo ""
echo "Completed at: $(date)"
