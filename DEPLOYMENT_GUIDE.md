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
    │  │  VM (No PIP)  │  │       │  │  VM (No PIP)  │  │
    │  └───────────────┘  │       │  └───────────────┘  │
    │                     │       │                     │
    │  ┌───────────────┐  │       │  ┌───────────────┐  │
    │  │Private Endpoint│ │       │  │Private Endpoint│ │
    │  │  pe-sql-sea   │  │       │  │  pe-sql-idc   │  │
    │  └───────┬───────┘  │       │  └───────┬───────┘  │
    └──────────┼──────────┘       └──────────┼──────────┘
               │                             │
               ▼                             ▼
    ┌─────────────────────────────────────────────────────┐
    │          Azure SQL with Failover Group              │
    │   ┌─────────────────┐      ┌─────────────────┐      │
    │   │ Primary (SEA)   │◄────►│ Secondary (IDC) │      │
    │   └─────────────────┘      └─────────────────┘      │
    │   Public Access: DISABLED (Private Endpoints only)  │
    │   Connection: via Failover Group Listener           │
    └─────────────────────────────────────────────────────┘
    
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
  - Global (Front Door, Private DNS Zone)
- **2 Hub VNets** with Azure Firewall (Basic SKU)
- **2 Spoke VNets** with VNet Peering to Hubs
- **Route Tables** for traffic through Firewall
- **DNAT Rules** on Firewalls for HTTP traffic
- **Azure SQL Database** with Failover Groups and **Private Endpoints**
- **Private DNS Zone** (`privatelink.database.windows.net`) linked to Spoke VNets
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

## 🔍 Post-Deployment Verification

After deployment, run these verification steps to ensure everything is working:

### Step 1: Verify VMs are Running
```bash
source deployment-output.txt

# Check VM status
az vm get-instance-view -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY --query "instanceView.statuses[1].displayStatus" -o tsv
az vm get-instance-view -g $RG_SPOKE_SECONDARY -n $VM_SECONDARY --query "instanceView.statuses[1].displayStatus" -o tsv
```
Expected: `VM running` for both VMs

### Step 2: Verify SQL Configuration
```bash
# Check SQL failover group
az sql failover-group show -g $RG_SPOKE_PRIMARY -s $SQL_SERVER_PRIMARY -n $SQL_FAILOVER_GROUP --query "replicationRole" -o tsv
```
Expected: `Primary`

### Step 3: Verify .env File on VMs
```bash
# Check Primary VM
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "cat /var/www/social-media/.env" \
    --query "value[0].message" -o tsv
```
Expected output should show:
- `SQL_SERVER=resiliency-fog.database.windows.net`
- `SQL_DATABASE=resiliency-db`
- `SQL_USER=sqladmin`
- `SQL_PASSWORD=Workshop2024SecurePass`

### Step 4: Verify Application Health
```bash
# Check via Firewall
curl -s http://$FW_PUBLIC_IP_PRIMARY/health | jq
curl -s http://$FW_PUBLIC_IP_SECONDARY/health | jq
```
Expected: `{"status":"healthy","region":"...","database":"connected",...}`

### Step 5: Verify Data Replication
1. Open `http://$FW_PUBLIC_IP_PRIMARY` in browser
2. Create a test post
3. Open `http://$FW_PUBLIC_IP_SECONDARY` in browser
4. Verify the post appears (should be near-instant)

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
- **Public Network Access:** DISABLED (using Private Endpoints)
- **Private Endpoints:** One in each Spoke VNet's PE subnet
- **Private DNS Zone:** `privatelink.database.windows.net` linked to both Spoke VNets
- **Connection Mode:** Via Failover Group Listener endpoint (`resiliency-fog.database.windows.net`)
- **Automatic Failover:** Enabled with 60-minute grace period
- **RPO:** < 5 seconds for geo-replication
- **Database Name:** `resiliency-db`
- **Admin User:** `sqladmin`

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

**Check SQL connectivity from VM:**
```bash
source deployment-output.txt

# Check .env file has correct SQL settings
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "cat /var/www/social-media/.env"
```

**Verify SQL Listener is reachable:**
```bash
# Install sqlcmd and test connection (run on VM)
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript \
    --scripts "apt-get install -y mssql-tools && /opt/mssql-tools/bin/sqlcmd -S $SQL_LISTENER -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -d $SQL_DATABASE -Q 'SELECT 1'"
```

**If SQL connection fails, check:**

1. **VMs are running** (not deallocated):
   ```bash
   az vm start -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY
   az vm start -g $RG_SPOKE_SECONDARY -n $VM_SECONDARY
   ```

2. **SQL Server firewall rules include Azure Firewall IPs:**
   ```bash
   # Check firewall rules
   az sql server firewall-rule list -g $RG_SPOKE_PRIMARY -s $SQL_SERVER_PRIMARY -o table
   
   # Add if missing (replace with actual Firewall IPs from deployment-output.txt)
   az sql server firewall-rule create -g $RG_SPOKE_PRIMARY -s $SQL_SERVER_PRIMARY \
       -n AllowFirewallSEA --start-ip-address <FW_PUBLIC_IP_PRIMARY> --end-ip-address <FW_PUBLIC_IP_PRIMARY>
   ```

3. **SQL public network access is enabled:**
   ```bash
   az sql server update -g $RG_SPOKE_PRIMARY -n $SQL_SERVER_PRIMARY \
       --enable-public-network true
   ```

4. **Azure Firewall allows outbound SQL traffic:**
   - Port 1433 (SQL)
   - Ports 11000-11999 (SQL redirect mode)
   - Destination: `Sql` service tag

5. **Reset SQL password if needed:**
   ```bash
   az sql server update -g $RG_SPOKE_PRIMARY -n $SQL_SERVER_PRIMARY \
       --admin-password "Workshop2024SecurePass"
   az sql server update -g $RG_SPOKE_SECONDARY -n $SQL_SERVER_SECONDARY \
       --admin-password "Workshop2024SecurePass"
   ```

### Application not starting
```bash
# Run on VM via Run Command
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript \
    --scripts "cd /var/www/social-media && cat .env && npm install && node app.js"
```

---

## � Known Issues and Fixes (from Debugging Session)

This section documents issues encountered during deployment and their solutions.

### Issue 1: SQL Database Name Mismatch
**Symptom:** App shows "Cannot read properties of undefined" or SQL connection errors
**Cause:** Mismatch between database name in script (`socialMediaDB`) and actual database (`resiliency-db`)
**Fix:** Ensure `SQL_DATABASE=resiliency-db` in both the infrastructure script and the `.env` file on VMs

### Issue 2: SQL Password Shell Escaping
**Symptom:** SQL authentication fails despite correct password in script
**Cause:** Special characters (`!`, `@`, `$`) in password cause issues in bash/zsh heredocs
**Fix:** Use alphanumeric password: `Workshop2024SecurePass`

### Issue 3: VM Deallocated State
**Symptom:** No response from Firewall endpoints, health checks fail
**Cause:** VMs stopped/deallocated to save costs but not restarted
**Fix:** 
```bash
az vm start -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY
az vm start -g $RG_SPOKE_SECONDARY -n $VM_SECONDARY
```

### Issue 4: SQL Public Network Access Disabled
**Symptom:** SQL connection timeout from VMs
**Cause:** Public network access set to false, Private DNS not resolving correctly
**Fix:** Enable public access with firewall rules:
```bash
az sql server update -g $RG_SPOKE_PRIMARY -n $SQL_SERVER_PRIMARY --enable-public-network true
az sql server update -g $RG_SPOKE_SECONDARY -n $SQL_SERVER_SECONDARY --enable-public-network true
```

### Issue 5: Missing SQL Firewall Rules
**Symptom:** SQL connection refused even with public access enabled
**Cause:** SQL Server firewall doesn't allow Azure Firewall IPs
**Fix:** Add firewall rules for both Azure Firewall public IPs:
```bash
az sql server firewall-rule create -g $RG_SPOKE_PRIMARY -s $SQL_SERVER_PRIMARY \
    -n AllowFirewallPrimary --start-ip-address <FW_IP_SEA> --end-ip-address <FW_IP_SEA>
az sql server firewall-rule create -g $RG_SPOKE_PRIMARY -s $SQL_SERVER_PRIMARY \
    -n AllowFirewallSecondary --start-ip-address <FW_IP_IDC> --end-ip-address <FW_IP_IDC>
```

### Issue 6: Missing Azure Firewall Outbound SQL Rules
**Symptom:** DNS resolves but TCP connection times out on port 1433
**Cause:** Azure Firewall blocking outbound SQL traffic (needs ports 1433 and 11000-11999)
**Fix:** Add network rules to firewall policies:
```bash
# Add to both firewall policies - SQL port 1433
az network firewall policy rule-collection-group collection add-filter-collection \
    --policy-name <FW_POLICY> -g <RG_HUB> \
    --rcg-name DefaultNetworkRuleCollectionGroup \
    --name "AllowSqlOutbound" --action Allow \
    --rule-type NetworkRule \
    --rule-name "allow-sql-1433" \
    --source-addresses "10.0.0.0/8" \
    --destination-addresses Sql \
    --destination-ports 1433 \
    --ip-protocols TCP

# Add SQL redirect ports 11000-11999
az network firewall policy rule-collection-group collection rule add \
    --policy-name <FW_POLICY> -g <RG_HUB> \
    --rcg-name DefaultNetworkRuleCollectionGroup \
    --collection-name "AllowSqlOutbound" \
    --rule-type NetworkRule \
    --name "allow-sql-redirect" \
    --source-addresses "10.0.0.0/8" \
    --destination-addresses Sql \
    --destination-ports "11000-11999" \
    --ip-protocols TCP
```

### Issue 7: .env Variables Not Expanded
**Symptom:** `.env` file on VM shows literal `$SQL_LISTENER` instead of actual value
**Cause:** Heredoc in `02-deploy-app.sh` used quoted delimiter (`'ENVFILE'`) preventing variable expansion
**Fix:** Use unquoted heredoc delimiter: `<< ENVFILE` instead of `<< 'ENVFILE'`

### Quick Verification Commands

```bash
source deployment-output.txt

# 1. Check VMs are running
az vm get-instance-view -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY --query "instanceView.statuses[1].displayStatus"
az vm get-instance-view -g $RG_SPOKE_SECONDARY -n $VM_SECONDARY --query "instanceView.statuses[1].displayStatus"

# 2. Check .env file content
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript --scripts "cat /var/www/social-media/.env"

# 3. Check SQL connectivity
az vm run-command invoke -g $RG_SPOKE_PRIMARY -n $VM_PRIMARY \
    --command-id RunShellScript \
    --scripts "node -e \"const sql=require('mssql'); sql.connect({server:'$SQL_LISTENER',database:'$SQL_DATABASE',user:'$SQL_ADMIN_USER',password:'$SQL_ADMIN_PASSWORD',options:{encrypt:true}}).then(()=>console.log('Connected!')).catch(e=>console.error(e.message))\""

# 4. Check app health
curl -s http://$FW_PUBLIC_IP_PRIMARY/health
curl -s http://$FW_PUBLIC_IP_SECONDARY/health
```

---

## �📁 File Structure

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
- [ ] Azure Firewalls running with DNAT rules (HTTP) and outbound rules (SQL)
- [ ] Azure SQL Failover Group created with both servers showing "Online"
- [ ] SQL Server firewall rules include Azure Firewall public IPs
- [ ] VMs respond via Firewall public IPs (`curl http://<firewall-ip>/health`)
- [ ] Application shows "Database: Azure SQL (Connected)" on homepage
- [ ] Application loads via Front Door URL
- [ ] Region banner shows correct region
- [ ] Posts can be created and saved to Azure SQL
- [ ] Posts sync between regions in < 1 second (via Failover Group)
- [ ] Stopping Primary app triggers failover to Secondary
- [ ] Traffic returns to Primary when restored
