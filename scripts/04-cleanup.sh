#!/bin/bash

#############################################################################
# Azure Resiliency Workshop - Cleanup Script
# 
# This script removes all resources created by the workshop
# Hub-Spoke Architecture with 5 Resource Groups
# WARNING: This will permanently delete all resources!
#############################################################################

set -e

# Load configuration
if [ -f "deployment-output.txt" ]; then
    source deployment-output.txt
else
    echo "❌ Error: deployment-output.txt not found!"
    echo "Will attempt to delete default resource groups..."
    RG_HUB_PRIMARY="resiliency-rg-hub-sea"
    RG_SPOKE_PRIMARY="resiliency-rg-spoke-sea"
    RG_HUB_SECONDARY="resiliency-rg-hub-idc"
    RG_SPOKE_SECONDARY="resiliency-rg-spoke-idc"
    RG_GLOBAL="resiliency-rg-global"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║           ⚠️  WARNING: RESOURCE CLEANUP                                    ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                            ║"
echo "║  This will DELETE the following resource groups and ALL their resources:  ║"
echo "║                                                                            ║"
echo "║  Hub-Spoke Architecture:                                                   ║"
echo "║    - $RG_HUB_PRIMARY (Hub - Southeast Asia)"
echo "║    - $RG_SPOKE_PRIMARY (Spoke - Southeast Asia)"
echo "║    - $RG_HUB_SECONDARY (Hub - Indonesia Central)"
echo "║    - $RG_SPOKE_SECONDARY (Spoke - Indonesia Central)"
echo "║    - $RG_GLOBAL (Global Resources)"
echo "║                                                                            ║"
echo "║  This action CANNOT be undone!                                             ║"
echo "║                                                                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

read -p "Are you sure you want to delete all resources? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Delete resource groups (this deletes all resources within them)
echo "Deleting Hub Resource Groups..."
echo "  - $RG_HUB_PRIMARY..."
az group delete --name "$RG_HUB_PRIMARY" --yes --no-wait 2>/dev/null || echo "    (may not exist)"

echo "  - $RG_HUB_SECONDARY..."
az group delete --name "$RG_HUB_SECONDARY" --yes --no-wait 2>/dev/null || echo "    (may not exist)"

echo ""
echo "Deleting Spoke Resource Groups..."
echo "  - $RG_SPOKE_PRIMARY..."
az group delete --name "$RG_SPOKE_PRIMARY" --yes --no-wait 2>/dev/null || echo "    (may not exist)"

echo "  - $RG_SPOKE_SECONDARY..."
az group delete --name "$RG_SPOKE_SECONDARY" --yes --no-wait 2>/dev/null || echo "    (may not exist)"

echo ""
echo "Deleting Global Resource Group..."
echo "  - $RG_GLOBAL..."
az group delete --name "$RG_GLOBAL" --yes --no-wait 2>/dev/null || echo "    (may not exist)"

echo ""
echo "✅ Cleanup initiated!"
echo ""
echo "Resource groups are being deleted in the background."
echo "This may take 5-10 minutes to complete."
echo ""
echo "You can check progress in the Azure Portal under Resource Groups."
echo ""

# Clean up local files
rm -f deployment-output.txt 2>/dev/null
rm -f app.tar.gz 2>/dev/null

echo "Local configuration files cleaned up."
echo ""
echo "Cleanup complete!"
