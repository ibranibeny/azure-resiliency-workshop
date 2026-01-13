#!/bin/bash

#############################################################################
# Azure Resiliency Workshop - Demo Helper Script
# 
# Quick commands for the workshop demonstration
# Hub-Spoke Architecture with Azure Firewall - No direct VM access
#############################################################################

# Load configuration
if [ -f "deployment-output.txt" ]; then
    source deployment-output.txt
else
    echo "❌ Error: deployment-output.txt not found!"
    exit 1
fi

show_menu() {
    clear
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║       Azure Resiliency Workshop - Demo Control Panel (Hub-Spoke)           ║"
    echo "╠════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                            ║"
    echo "║  Current Status:                                                           ║"
    echo "║  ─────────────────────────────────────────────────────────────────────     ║"
    echo "║  Front Door:     http://$FRONTDOOR_URL"
    echo "║  Firewall (SEA): $FW_PUBLIC_IP_PRIMARY → VM $VM_PRIMARY_PRIVATE_IP"
    echo "║  Firewall (IDC): $FW_PUBLIC_IP_SECONDARY → VM $VM_SECONDARY_PRIVATE_IP"
    echo "║                                                                            ║"
    echo "╠════════════════════════════════════════════════════════════════════════════╣"
    echo "║  DEMO OPTIONS:                                                             ║"
    echo "║  ─────────────────────────────────────────────────────────────────────     ║"
    echo "║  1) Check health of all endpoints                                          ║"
    echo "║  2) Open application in browser (Front Door)                               ║"
    echo "║  3) Open Primary via Firewall (SEA)                                        ║"
    echo "║  4) Open Secondary via Firewall (IDC)                                      ║"
    echo "║  ─────────────────────────────────────────────────────────────────────     ║"
    echo "║  5) 🔴 STOP Primary App (Trigger Failover)                                 ║"
    echo "║  6) 🟢 START Primary App (Restore)                                         ║"
    echo "║  7) 🔴 STOP Primary VM (Slower Failover)                                   ║"
    echo "║  8) 🟢 START Primary VM                                                    ║"
    echo "║  ─────────────────────────────────────────────────────────────────────     ║"
    echo "║  9) Run command on Primary VM                                              ║"
    echo "║  10) Run command on Secondary VM                                           ║"
    echo "║  11) View Front Door origin health status                                  ║"
    echo "║  12) View VM status                                                        ║"
    echo "║  ─────────────────────────────────────────────────────────────────────     ║"
    echo "║  0) Exit                                                                   ║"
    echo "║                                                                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    read -p "Select option: " choice
}

check_health() {
    echo ""
    echo "Checking health endpoints..."
    echo ""
    
    echo "Primary VM via Firewall (Southeast Asia):"
    HEALTH_SEA=$(curl -s --connect-timeout 10 "http://$FW_PUBLIC_IP_PRIMARY/health" 2>/dev/null)
    if [ -n "$HEALTH_SEA" ]; then
        echo "  $HEALTH_SEA"
    else
        echo "  ❌ Not responding"
    fi
    echo ""
    
    echo "Secondary VM via Firewall (Indonesia Central):"
    HEALTH_IDC=$(curl -s --connect-timeout 10 "http://$FW_PUBLIC_IP_SECONDARY/health" 2>/dev/null)
    if [ -n "$HEALTH_IDC" ]; then
        echo "  $HEALTH_IDC"
    else
        echo "  ❌ Not responding"
    fi
    echo ""
    
    echo "Front Door:"
    HEALTH_FD=$(curl -s --connect-timeout 15 "http://$FRONTDOOR_URL/health" 2>/dev/null)
    if [ -n "$HEALTH_FD" ]; then
        echo "  $HEALTH_FD"
    else
        echo "  ❌ Not responding"
    fi
    echo ""
    
    read -p "Press Enter to continue..."
}

stop_primary_app() {
    echo ""
    echo "🔴 Stopping application on Primary VM (via Azure Run Command)..."
    echo ""
    az vm run-command invoke \
        --resource-group "$RG_SPOKE_PRIMARY" \
        --name "$VM_PRIMARY" \
        --command-id RunShellScript \
        --scripts "sudo -u azureuser pm2 stop all" \
        --output table
    echo ""
    echo "✅ Primary app stopped!"
    echo "⏳ Front Door will detect failure in 30-60 seconds and failover to Secondary."
    echo ""
    read -p "Press Enter to continue..."
}

start_primary_app() {
    echo ""
    echo "🟢 Starting application on Primary VM (via Azure Run Command)..."
    echo ""
    az vm run-command invoke \
        --resource-group "$RG_SPOKE_PRIMARY" \
        --name "$VM_PRIMARY" \
        --command-id RunShellScript \
        --scripts "sudo -u azureuser pm2 start all" \
        --output table
    echo ""
    echo "✅ Primary app started!"
    echo "⏳ Front Door will detect healthy origin and route traffic back."
    echo ""
    read -p "Press Enter to continue..."
}

stop_primary_vm() {
    echo ""
    echo "🔴 Stopping Primary VM (this may take 1-2 minutes)..."
    az vm stop --resource-group "$RG_SPOKE_PRIMARY" --name "$VM_PRIMARY" --no-wait
    echo ""
    echo "✅ VM stop command sent!"
    echo "⏳ VM will stop shortly. Front Door will failover to Secondary."
    echo ""
    read -p "Press Enter to continue..."
}

start_primary_vm() {
    echo ""
    echo "🟢 Starting Primary VM (this may take 2-3 minutes)..."
    az vm start --resource-group "$RG_SPOKE_PRIMARY" --name "$VM_PRIMARY" --no-wait
    echo ""
    echo "✅ VM start command sent!"
    echo "⏳ VM will start shortly. Then traffic will return to Primary."
    echo ""
    read -p "Press Enter to continue..."
}

run_command_primary() {
    echo ""
    read -p "Enter command to run on Primary VM: " cmd
    echo ""
    echo "Running command: $cmd"
    echo ""
    az vm run-command invoke \
        --resource-group "$RG_SPOKE_PRIMARY" \
        --name "$VM_PRIMARY" \
        --command-id RunShellScript \
        --scripts "$cmd" \
        --output table
    echo ""
    read -p "Press Enter to continue..."
}

run_command_secondary() {
    echo ""
    read -p "Enter command to run on Secondary VM: " cmd
    echo ""
    echo "Running command: $cmd"
    echo ""
    az vm run-command invoke \
        --resource-group "$RG_SPOKE_SECONDARY" \
        --name "$VM_SECONDARY" \
        --command-id RunShellScript \
        --scripts "$cmd" \
        --output table
    echo ""
    read -p "Press Enter to continue..."
}

view_frontdoor_health() {
    echo ""
    echo "Checking Front Door origin health..."
    echo ""
    az afd origin-group show \
        --origin-group-name "og-frontend" \
        --profile-name "$FRONTDOOR_NAME" \
        --resource-group "$RG_GLOBAL" \
        --query "{HealthProbe: healthProbeSettings, LoadBalancing: loadBalancingSettings}" \
        --output table
    echo ""
    echo "Origin status:"
    az afd origin list \
        --origin-group-name "og-frontend" \
        --profile-name "$FRONTDOOR_NAME" \
        --resource-group "$RG_GLOBAL" \
        --query "[].{Name: name, HostName: hostName, Priority: priority, Weight: weight, Enabled: enabledState}" \
        --output table
    echo ""
    read -p "Press Enter to continue..."
}

view_vm_status() {
    echo ""
    echo "VM Status:"
    echo ""
    echo "Primary VM (Southeast Asia):"
    az vm get-instance-view \
        --resource-group "$RG_SPOKE_PRIMARY" \
        --name "$VM_PRIMARY" \
        --query "{Name: name, Status: instanceView.statuses[1].displayStatus}" \
        --output table
    echo ""
    echo "Secondary VM (Indonesia Central):"
    az vm get-instance-view \
        --resource-group "$RG_SPOKE_SECONDARY" \
        --name "$VM_SECONDARY" \
        --query "{Name: name, Status: instanceView.statuses[1].displayStatus}" \
        --output table
    echo ""
    read -p "Press Enter to continue..."
}

# Main loop
while true; do
    show_menu
    
    case $choice in
        1) check_health ;;
        2) echo "Opening Front Door URL..."; xdg-open "http://$FRONTDOOR_URL" 2>/dev/null || start "http://$FRONTDOOR_URL" 2>/dev/null || open "http://$FRONTDOOR_URL" 2>/dev/null || echo "Please open: http://$FRONTDOOR_URL"; read -p "Press Enter..." ;;
        3) echo "Opening Primary via Firewall..."; xdg-open "http://$FW_PUBLIC_IP_PRIMARY" 2>/dev/null || start "http://$FW_PUBLIC_IP_PRIMARY" 2>/dev/null || open "http://$FW_PUBLIC_IP_PRIMARY" 2>/dev/null || echo "Please open: http://$FW_PUBLIC_IP_PRIMARY"; read -p "Press Enter..." ;;
        4) echo "Opening Secondary via Firewall..."; xdg-open "http://$FW_PUBLIC_IP_SECONDARY" 2>/dev/null || start "http://$FW_PUBLIC_IP_SECONDARY" 2>/dev/null || open "http://$FW_PUBLIC_IP_SECONDARY" 2>/dev/null || echo "Please open: http://$FW_PUBLIC_IP_SECONDARY"; read -p "Press Enter..." ;;
        5) stop_primary_app ;;
        6) start_primary_app ;;
        7) stop_primary_vm ;;
        8) start_primary_vm ;;
        9) run_command_primary ;;
        10) run_command_secondary ;;
        11) view_frontdoor_health ;;
        12) view_vm_status ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
