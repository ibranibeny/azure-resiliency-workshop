# Azure Resiliency Workshop - Deployment Guide

## 📋 Prerequisites

Before starting the deployment, ensure you have:

1. **Azure CLI installed and logged in**
   ```bash
   # Install Azure CLI (if not installed)
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Login to Azure
   az login
   
   # Verify subscription
   az account show
   ```

2. **Bash shell environment**
   - WSL on Windows
   - Terminal on macOS/Linux
   - Azure Cloud Shell

3. **SSH key pair** (will be auto-generated if not exists)

---

## 🏗️ Architecture Overview

This workshop deploys a **Hub-Spoke Network Topology** with:

```
                        Azure Front Door
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    ┌─────────────────────┐       ┌─────────────────────┐
    │    Hub VNet SEA     │       │    Hub VNet IDC     │
    │   (10.0.0.0/16)     │       │   (10.10.0.0/16)    │
    │                     │       │                     │
    │  ┌───────────────┐  │       │  ┌───────────────┐  │
    │  │Azure Firewall │  │       │  │Azure Firewall │  │
    │  │  (DNAT Rules) │  │       │  │  (DNAT Rules) │  │
    │  └───────────────┘  │       │  └───────────────┘  │
    └─────────┬───────────┘       └─────────┬───────────┘
              │ VNet Peering                │ VNet Peering
              ▼                             ▼
    ┌─────────────────────┐       ┌─────────────────────┐
    │   Spoke VNet SEA    │       │   Spoke VNet IDC    │
    │   (10.1.0.0/16)     │       │   (10.2.0.0/16)     │
    │                     │       │                     │
    │  ┌───────────────┐  │       │  ┌───────────────┐  │
    │  │  VM (No PIP)  │──┼───────┼──│  VM (No PIP)  │  │
    │  └───────────────┘  │       │  └───────────────┘  │
    │                     │       │                     │
    │  ┌───────────────┐  │       │  ┌───────────────┐  │
    │  │   Azure SQL   │◄─┼───────┼─►│   Azure SQL   │  │
    │  │ Private EP    │  │       │  │ Private EP    │  │
    │  └───────────────┘  │       │  └───────────────┘  │
    └─────────────────────┘       └─────────────────────┘
    
    Southeast Asia                Indonesia Central
    (On-Prem Simulation)          (Azure Cloud)
```

---

## 🚀 Step-by-Step Deployment

### Step 1: Prepare Your Environment

1. Open terminal in WSL or Azure Cloud Shell:
   ```bash
   cd /mnt/c/Users/benyibrani/OneDrive\ -\ Microsoft/Documents/Learning/Workshop/Resiliency
   ```

2. Make scripts executable:
   ```bash
   chmod +x scripts/*.sh
   ```

### Step 2: Deploy Infrastructure

Run the infrastructure deployment script:

```bash
cd scripts
./01-deploy-infrastructure.sh
```

**What this creates:**
- **5 Resource Groups:**
  - Hub-SEA, Spoke-SEA
  - Hub-IDC, Spoke-IDC
  - Global (Azure SQL, Front Door)
- **2 Hub VNets** with Azure Firewall (Basic SKU)
- **2 Spoke VNets** with VNet Peering to Hubs
- **Route Tables** for traffic through Firewall
- **DNAT Rules** on Firewalls for HTTP traffic
- **Azure SQL Database** with Failover Groups and Private Endpoints
- **2 Ubuntu VMs** (private IPs only)
- **Azure Front Door** with Firewall public IPs as origins

**⏱️ Duration:** 20-30 minutes (Firewall deployment takes ~10 mins each)

**📝 Output:** Creates `deployment-output.txt` with all connection details

### Step 3: Wait for VMs to Initialize

The VMs use cloud-init to automatically install:
- Node.js 18
- PM2 (process manager)
- Nginx (reverse proxy)

Wait 5-10 minutes after infrastructure deployment completes.

**Verify VM is ready (via Azure Run Command):**
```bash
# Load configuration
source deployment-output.txt

# Check if Node.js is installed on Primary VM
az vm run-command invoke \
    --resource-group $RG_SPOKE_PRIMARY \
    --name $VM_PRIMARY \
    --command-id RunShellScript \
    --scripts "node --version"
```

### Step 4: Deploy the Application

```bash
./02-deploy-app.sh
```

**What this does:**
- Uses Azure VM Run Command (no SSH needed!)
- Creates environment-specific config for each region
- Deploys application files to both VMs
- Installs npm dependencies
- Starts application with PM2
- Configures auto-restart on boot

**⏱️ Duration:** 5-10 minutes

### Step 5: Verify Deployment

Check all endpoints via Firewall:

```bash
# Load configuration
source deployment-output.txt

# Check Primary VM via Firewall
curl http://$FW_PUBLIC_IP_PRIMARY/health

# Check Secondary VM via Firewall
curl http://$FW_PUBLIC_IP_SECONDARY/health

# Check Front Door
curl http://$FRONTDOOR_URL/health
```

All should return:
```json
{"status":"healthy","region":"...","timestamp":"..."}
```

### Step 6: Access Your Application

1. **Via Front Door (recommended):**
   - Open browser: `http://<your-frontdoor-url>.azurefd.net`
   - This is the URL you'll share with workshop attendees

2. **Via Firewall (for testing):**
   - Primary (SEA): `http://<firewall-sea-public-ip>`
   - Secondary (IDC): `http://<firewall-idc-public-ip>`

**Note:** VMs have no public IPs - all traffic goes through Firewall DNAT!

---

## 🎭 Running the Demo

### Using the Demo Helper

```bash
./03-demo-helper.sh
```

This provides an interactive menu for:
- Health checks (via Firewall endpoints)
- Starting/stopping VMs
- Triggering failover
- Running commands on VMs (via Azure Run Command)
- Viewing Front Door status

**Trigger Failover (Fast - App Stop via Azure Run Command):**
```bash
source deployment-output.txt

# Stop the app on Primary VM
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "sudo -u azureuser pm2 stop all"

# Wait 30-60 seconds for Front Door to detect failure
# Refresh browser - now served from Indonesia Central!
```

**Restore Primary:**
```bash
# Start the app on Primary VM
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "sudo -u azureuser pm2 start all"

# Front Door will detect healthy origin and switch back
```

**Trigger Failover (Slow - VM Stop):**
```bash
# Stop the entire VM
az vm stop --resource-group $RG_SPOKE_PRIMARY --name $VM_PRIMARY --no-wait

# Takes 1-2 minutes for VM to stop
# Front Door will failover
```

**Restore VM:**
```bash
az vm start --resource-group $RG_SPOKE_PRIMARY --name $VM_PRIMARY --no-wait
```

---

## 🔍 Demo Scenarios

### Scenario 1: Show Multi-Region Data Sync

1. Open two browser tabs:
   - Tab 1: `http://<firewall-sea-ip>` (Southeast Asia via Firewall)
   - Tab 2: `http://<firewall-idc-ip>` (Indonesia Central via Firewall)

2. Create a post in Tab 1

3. Refresh Tab 2 - post appears immediately!

4. **Explain:** Azure SQL Failover Group automatically replicates data across regions (RPO < 5 seconds)

### Scenario 2: Show Automatic Failover

1. Open browser to Front Door URL
2. Notice the region banner shows "Southeast Asia"
3. Stop the Primary VM app via Azure Run Command:
   ```bash
   az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
       --command-id RunShellScript --scripts "sudo -u azureuser pm2 stop all"
   ```
4. Wait 30-60 seconds
5. Refresh browser - region now shows "Indonesia Central"!
6. Create a new post - it still works!

**Key points:**
- Zero downtime for users
- Data persists in Azure SQL Database
- Automatic failover without manual intervention

### Scenario 3: Show Recovery

1. While traffic is on Secondary, restart Primary:
   ```bash
   az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
       --command-id RunShellScript --scripts "sudo -u azureuser pm2 start all"
   ```
2. Wait for Front Door health probe (~30 seconds)
3. Traffic returns to Primary (higher priority)
4. All posts created during failover are still visible (Azure SQL Failover Group sync)

---

## 📊 Architecture Explanation

### Hub-Spoke Network Topology
- **Hub VNet:** Contains Azure Firewall for centralized security
- **Spoke VNet:** Contains application VMs and Private Endpoints
- **VNet Peering:** Connects Hub and Spoke with traffic forwarding
- **Route Tables:** Forces all Spoke traffic through Firewall

### Azure Firewall (Basic SKU)
- **DNAT Rules:** Translates Firewall public IP to VM private IP
- **Network Rules:** Controls outbound traffic from VMs
- **Centralized Security:** All ingress/egress through Firewall

### Azure Front Door
- **Health Probes:** Checks `/health` on Firewall public IPs every 30 seconds
- **Priority Routing:** 
  - Priority 1 (Primary): Firewall SEA Public IP
  - Priority 2 (Secondary): Firewall IDC Public IP
- **Automatic Failover:** When primary fails health checks, traffic goes to secondary

### Azure SQL Failover Group
- **Primary Server:** Southeast Asia (read/write)
- **Secondary Server:** Indonesia Central (read replica)
- **Private Endpoints:** No public access, connected via Spoke VNets
- **Automatic Failover:** Enabled with 60-minute grace period
- **Failover Listener:** Single connection endpoint for transparent failover
- **RPO:** < 5 seconds for geo-replication

### Application Design
- **No Public IP:** VMs only have private IPs
- **Health Endpoint:** Returns region info for monitoring
- **Region Indicator:** Visual banner showing current serving region
- **Post Form:** Demonstrates write operations and data sync

---

## 💰 Cost Considerations

| Resource | SKU | Est. Cost/Hour |
|----------|-----|----------------|
| VM (x2) | Standard_B2s | ~$0.10/hr |
| Azure Firewall (x2) | Basic | ~$0.50/hr |
| Azure SQL (x2) | General Purpose | ~$0.04/hr |
| Front Door | Standard | ~$0.05/hr |
| VNet, NSG, PIP | - | ~$0.05/hr |
| **Total** | | **~$0.95/hr** |

**⚠️ IMPORTANT:** Delete all resources after workshop to avoid charges!

---

## 🧹 Cleanup

After the workshop, delete all resources:

```bash
./04-cleanup.sh
```

Or manually:
```bash
az group delete --name resiliency-hub-sea --yes --no-wait
az group delete --name resiliency-spoke-sea --yes --no-wait
az group delete --name resiliency-hub-idc --yes --no-wait
az group delete --name resiliency-spoke-idc --yes --no-wait
az group delete --name resiliency-global --yes --no-wait
```

---

## 🔧 Troubleshooting

### VM not responding via Firewall
```bash
source deployment-output.txt

# Check VM is running
az vm get-instance-view -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --query "instanceView.statuses[1].displayStatus"

# Check PM2 status via Run Command
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "pm2 status"

# Check app logs
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "pm2 logs social-media --lines 20"

# Check Nginx status
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "systemctl status nginx"
```

### Firewall DNAT not working
```bash
# Check Firewall is running
az network firewall show -g $RG_HUB_PRIMARY -n $FW_PRIMARY \
    --query "provisioningState"

# Check DNAT rules exist
az network firewall policy rule-collection-group list \
    --policy-name $FW_POLICY_PRIMARY -g $RG_HUB_PRIMARY \
    --query "[].name"
```

### Front Door not failing over
- Check health probe path is `/health`
- Verify probe interval (30 seconds)
- Check origin is using Firewall public IP
- Wait for probe cycles (3-4 failed probes needed)

### Azure SQL connection issues
- Verify Private Endpoint is connected
- Check Private DNS Zone is linked to Spoke VNet
- Verify SQL_SERVER, SQL_USER, SQL_PASSWORD in `.env`
- Check Failover Group listener endpoint is accessible

### Application not starting
```bash
# Run on VM via Run Command
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript \
    --scripts "cd /var/www/social-media && cat .env && npm install && node app.js"
```

---

## 📁 File Structure

```
Resiliency/
├── WORKSHOP_TASKS.md          # Task checklist
├── DEPLOYMENT_GUIDE.md        # This file
├── app/                       # Node.js application
│   ├── package.json
│   ├── app.js
│   ├── .env.example
│   ├── views/
│   │   └── index.ejs
│   └── public/
└── scripts/                   # Deployment scripts
    ├── 01-deploy-infrastructure.sh
    ├── 02-deploy-app.sh
    ├── 03-demo-helper.sh
    ├── 04-cleanup.sh
    └── vm-setup.sh
```

---

## ✅ Success Criteria

Your deployment is successful when:

- [ ] All 5 Resource Groups created (Hub×2, Spoke×2, Global)
- [ ] Azure Firewalls running with DNAT rules
- [ ] VMs respond via Firewall public IPs
- [ ] Application loads via Front Door URL
- [ ] Region banner shows correct region
- [ ] Posts can be created and saved
- [ ] Posts sync between regions in < 1 second
- [ ] Stopping Primary app triggers failover to Secondary
- [ ] Traffic returns to Primary when restored
