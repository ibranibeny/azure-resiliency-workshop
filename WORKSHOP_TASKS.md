# Azure Resiliency Workshop - Task List

## Workshop Overview
**Scenario:** Simulate disaster recovery/failover between:
- **Primary (On-Prem Simulation):** Southeast Asia
- **Secondary (Azure Cloud):** Indonesia Central

**Goal:** When the frontend in Southeast Asia is turned off, Azure Front Door automatically switches traffic to Indonesia Central, with Azure SQL Database data automatically synchronized via Failover Groups.

---

## Application Overview

### Simple Social Media App (Node.js)

A lightweight social media application built with **Node.js + Express** to demonstrate:
- **CRUD Operations** - Create, Read, Update, Delete posts
- **Multi-Region Data Sync** - Azure SQL Failover Groups (auto-replication)
- **Failover Testing** - Azure Front Door health probes

#### Technology Stack
| Component | Technology |
|-----------|------------|
| Runtime | Node.js 18 LTS |
| Framework | Express.js 4.x |
| Database | Azure SQL Database (with Failover Groups) |
| SQL Driver | mssql (Tedious) |
| Template Engine | EJS |
| Process Manager | PM2 |
| Reverse Proxy | Nginx |

#### Application Features

| Feature | API Endpoint | Description |
|---------|--------------|-------------|
| **Create Post** | `POST /api/posts` | Submit new post with username & message |
| **Read Posts** | `GET /api/posts` | Retrieve all posts (sorted by timestamp) |
| **Update Post** | `PUT /api/posts/:id` | Edit existing post message |
| **Delete Post** | `DELETE /api/posts/:id` | Remove a specific post |
| **Clear All** | `DELETE /api/posts` | Delete all posts (demo reset) |
| **Health Check** | `GET /health` | Front Door probe endpoint |
| **Region Info** | `GET /api/region` | Current serving region |

#### Demo Workflow
```
┌─────────────────────────────────────────────────────────────────────────┐
│                         WORKSHOP DEMO FLOW                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. CREATE POST (Southeast Asia)                                        │
│     └─► User submits "Hello World!" via web form                        │
│         └─► POST /api/posts → Azure SQL (Primary via Failover Group)    │
│                                                                         │
│  2. AUTO-SYNC (Azure SQL Failover Group)                                │
│     └─► SQL replicates to Indonesia Central (~5 seconds RPO)            │
│         └─► Both regions now have the same data                         │
│                                                                         │
│  3. UPDATE POST (Any Region)                                            │
│     └─► User edits message via "Edit" button                            │
│         └─► PUT /api/posts/:id → SQL syncs via geo-replication          │
│                                                                         │
│  4. SIMULATE FAILURE (Stop SEA App)                                     │
│     └─► Stop Nginx/PM2 on Southeast Asia VM                             │
│         └─► Front Door detects unhealthy (30-60 sec)                    │
│                                                                         │
│  5. AUTOMATIC FAILOVER                                                  │
│     └─► Front Door routes to Indonesia Central                          │
│         └─► Region banner changes to "Indonesia Central"                │
│         └─► All posts visible (synced data)                             │
│                                                                         │
│  6. CREATE/UPDATE DURING FAILOVER                                       │
│     └─► User creates new post in Indonesia Central                      │
│         └─► Data saved to Azure SQL (now primary after failover)        │
│                                                                         │
│  7. RECOVERY (Restart SEA App)                                          │
│     └─► Start Nginx/PM2 on Southeast Asia VM                            │
│         └─► Front Door detects healthy                                  │
│         └─► Traffic returns to SEA (primary)                            │
│         └─► All posts from failover are visible (synced!)               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Key Files
```
app/
├── app.js              # Main Express application
├── package.json        # Node.js dependencies
├── .env.example        # Environment variables template
├── views/
│   └── index.ejs       # Frontend UI (Bootstrap 5)
└── public/
    └── favicon.ico     # App icon
```

#### Environment Variables
```bash
# Server Configuration
PORT=3000
REGION="Southeast Asia"           # or "Indonesia Central"
REGION_COLOR="#28a745"            # Green for SEA, Blue for IDC

# Azure SQL Connection (uses Failover Group listener endpoint)
SQL_SERVER=your-failover-group.database.windows.net
SQL_DATABASE=socialMediaDB
SQL_USER=sqladmin
SQL_PASSWORD=your-secure-password
SQL_ENCRYPT=true
SQL_TRUST_SERVER_CERTIFICATE=false
```

---

## Architecture Diagram

```
                                    ┌─────────────────┐
                                    │  Azure Front    │
                                    │     Door        │
                                    └────────┬────────┘
                                             │
                    ┌────────────────────────┴────────────────────────┐
                    │                                                 │
                    ▼                                                 ▼
┌───────────────────────────────────────┐       ┌───────────────────────────────────────┐
│         SOUTHEAST ASIA HUB            │       │        INDONESIA CENTRAL HUB          │
│            10.0.0.0/16                │       │            10.10.0.0/16               │
│  ┌─────────────────────────────────┐  │       │  ┌─────────────────────────────────┐  │
│  │  AzureFirewallSubnet            │  │       │  │  AzureFirewallSubnet            │  │
│  │  10.0.1.0/26                    │  │       │  │  10.10.1.0/26                   │  │
│  │  ┌───────────────────────────┐  │  │       │  │  ┌───────────────────────────┐  │  │
│  │  │   Azure Firewall (Basic)  │  │  │       │  │  │   Azure Firewall (Basic)  │  │  │
│  │  │   Public IP: fw-pip-sea   │  │  │       │  │  │   Public IP: fw-pip-idc   │  │  │
│  │  │   DNAT → 10.1.1.x:80      │  │  │       │  │  │   DNAT → 10.2.1.x:80      │  │  │
│  │  └───────────────────────────┘  │  │       │  │  └───────────────────────────┘  │  │
│  └─────────────────────────────────┘  │       │  └─────────────────────────────────┘  │
└──────────────────┬────────────────────┘       └──────────────────┬────────────────────┘
                   │ VNet Peering                                  │ VNet Peering
                   ▼                                               ▼
┌───────────────────────────────────────┐       ┌───────────────────────────────────────┐
│       SOUTHEAST ASIA SPOKE            │       │      INDONESIA CENTRAL SPOKE          │
│        (On-Prem Simulation)           │       │         (Azure Cloud)                 │
│            10.1.0.0/16                │       │            10.2.0.0/16                │
│                                       │       │                                       │
│  ┌─────────────────────────────────┐  │       │  ┌─────────────────────────────────┐  │
│  │  Frontend Subnet (10.1.1.0/24) │  │       │  │  Frontend Subnet (10.2.1.0/24) │  │
│  │  ┌───────────────────────────┐  │  │       │  │  ┌───────────────────────────┐  │  │
│  │  │   Frontend VM (Node.js)   │  │  │       │  │  │   Frontend VM (Node.js)   │  │  │
│  │  │   No Public IP            │  │  │       │  │  │   No Public IP            │  │  │
│  │  └─────────────┬─────────────┘  │  │       │  │  └─────────────┬─────────────┘  │  │
│  └────────────────┼────────────────┘  │       │  └────────────────┼────────────────┘  │
│  ┌────────────────▼────────────────┐  │       │  ┌────────────────▼────────────────┐  │
│  │  PE Subnet (10.1.2.0/24)       │  │       │  │  PE Subnet (10.2.2.0/24)       │  │
│  │  ┌───────────────────────────┐  │  │       │  │  ┌───────────────────────────┐  │  │
│  │  │  Private Endpoint         │  │  │       │  │  │  Private Endpoint         │  │  │
│  │  │  (Azure SQL)             │  │  │       │  │  │  (Azure SQL)             │  │  │
│  │  └─────────────┬─────────────┘  │  │       │  │  └─────────────┬─────────────┘  │  │
│  └────────────────┼────────────────┘  │       │  └────────────────┼────────────────┘  │
└───────────────────┼───────────────────┘       └───────────────────┼───────────────────┘
                    │                                               │
                    │         ┌─────────────────────────┐           │
                    │         │  Azure SQL Database   │           │
                    └────────►│  (Failover Group)     │◄──────────┘
                              │  SEA (Primary) → IDC  │
                              │  (Auto Geo-Replicate) │
                              └─────────────────────────┘
```

### Traffic Flow:
1. **User** → Azure Front Door (Global)
2. **Front Door** → Firewall Public IP (DNAT)
3. **Firewall DNAT** → Frontend VM (Private IP)
4. **Frontend VM** → Private Endpoint → Azure SQL (via Failover Group listener)

### Key Security Features:
- ✅ **Hub-Spoke Topology** - Network segmentation
- ✅ **Azure Firewall** - Centralized traffic inspection & DNAT
- ✅ **No Public IPs on VMs** - All traffic through Firewall
- ✅ **Private Endpoints** - Azure SQL accessible only via private IP
- ✅ **Failover Groups** - Automatic geo-replication & failover
- ✅ **VNet Peering** - Hub-to-Spoke connectivity
- ✅ **Route Tables (UDR)** - Force traffic through Firewall

---

## Phase 1: Azure Infrastructure Setup

### Task 1.1: Create Resource Groups
- [ ] Create Resource Group: `rg-resiliency-hub-sea` (Southeast Asia - Hub)
- [ ] Create Resource Group: `rg-resiliency-spoke-sea` (Southeast Asia - Spoke)
- [ ] Create Resource Group: `rg-resiliency-hub-idc` (Indonesia Central - Hub)
- [ ] Create Resource Group: `rg-resiliency-spoke-idc` (Indonesia Central - Spoke)
- [ ] Create Resource Group: `rg-resiliency-global` (for Front Door)

### Task 1.2: Setup Hub Virtual Networks
- [ ] Create Hub VNet in Southeast Asia: `vnet-hub-sea` (10.0.0.0/16)
  - [ ] AzureFirewallSubnet: (10.0.1.0/26) - Required name for Firewall
- [ ] Create Hub VNet in Indonesia Central: `vnet-hub-idc` (10.10.0.0/16)
  - [ ] AzureFirewallSubnet: (10.10.1.0/26) - Required name for Firewall

### Task 1.3: Setup Spoke Virtual Networks
- [ ] Create Spoke VNet in Southeast Asia: `vnet-spoke-sea` (10.1.0.0/16)
  - [ ] Subnet for VM: `subnet-frontend-sea` (10.1.1.0/24)
  - [ ] Subnet for Private Endpoints: `subnet-pe-sea` (10.1.2.0/24)
- [ ] Create Spoke VNet in Indonesia Central: `vnet-spoke-idc` (10.2.0.0/16)
  - [ ] Subnet for VM: `subnet-frontend-idc` (10.2.1.0/24)
  - [ ] Subnet for Private Endpoints: `subnet-pe-idc` (10.2.2.0/24)

### Task 1.4: Setup VNet Peering
- [ ] Create VNet Peering: Hub-SEA ↔ Spoke-SEA
  - [ ] Allow forwarded traffic
  - [ ] Allow gateway transit (from Hub)
- [ ] Create VNet Peering: Hub-IDC ↔ Spoke-IDC
  - [ ] Allow forwarded traffic
  - [ ] Allow gateway transit (from Hub)

### Task 1.5: Setup Azure Firewall (Basic SKU)
- [ ] Create Firewall Public IP: `fw-pip-sea` (Southeast Asia)
- [ ] Create Azure Firewall: `fw-sea` (Southeast Asia)
  - [ ] SKU: Basic
  - [ ] VNet: `vnet-hub-sea`
- [ ] Create Firewall Public IP: `fw-pip-idc` (Indonesia Central)
- [ ] Create Azure Firewall: `fw-idc` (Indonesia Central)
  - [ ] SKU: Basic
  - [ ] VNet: `vnet-hub-idc`

### Task 1.6: Configure DNAT Rules
- [ ] Create DNAT Rule (SEA): External:80 → VM Private IP:80
- [ ] Create DNAT Rule (IDC): External:80 → VM Private IP:80

### Task 1.7: Setup Route Tables (UDR)
- [ ] Create Route Table for Spoke-SEA
  - [ ] Route: 0.0.0.0/0 → Firewall Private IP
  - [ ] Associate with Frontend Subnet
- [ ] Create Route Table for Spoke-IDC
  - [ ] Route: 0.0.0.0/0 → Firewall Private IP
  - [ ] Associate with Frontend Subnet

### Task 1.8: Setup Private DNS Zone
- [ ] Create Private DNS Zone: `privatelink.database.windows.net`
- [ ] Link DNS Zone to Spoke-SEA VNet
- [ ] Link DNS Zone to Spoke-IDC VNet

---

## Phase 2: Azure SQL Database Setup (with Failover Groups)

### Task 2.1: Create SQL Servers
- [ ] Create Primary SQL Server: `sql-resiliency-sea` (Southeast Asia)
  - [ ] Admin: `sqladmin`
  - [ ] Disable Public Network Access
- [ ] Create Secondary SQL Server: `sql-resiliency-idc` (Indonesia Central)
  - [ ] Admin: `sqladmin` (same credentials)
  - [ ] Disable Public Network Access

### Task 2.2: Create Failover Group
- [ ] Create Failover Group: `fg-resiliency-workshop`
  - [ ] Primary: `sql-resiliency-sea`
  - [ ] Secondary: `sql-resiliency-idc`
  - [ ] Read/Write Failover Policy: Automatic
  - [ ] Grace Period: 60 minutes
  - [ ] Listener Endpoint: `fg-resiliency-workshop.database.windows.net`

### Task 2.3: Create Private Endpoints
- [ ] Create Private Endpoint in Southeast Asia VNet
  - [ ] Target: Primary SQL Server
  - [ ] Subnet: `subnet-pe-sea`
  - [ ] Integrate with Private DNS Zone
- [ ] Create Private Endpoint in Indonesia Central VNet
  - [ ] Target: Secondary SQL Server
  - [ ] Subnet: `subnet-pe-idc`
  - [ ] Integrate with Private DNS Zone

### Task 2.4: Create Database and Tables
- [ ] Create Database: `socialMediaDB` (General Purpose, 2 vCores)
- [ ] Create Table: `posts`
  ```sql
  CREATE TABLE posts (
      id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
      userId NVARCHAR(50) NOT NULL,
      username NVARCHAR(100) NOT NULL,
      message NVARCHAR(500) NOT NULL,
      timestamp DATETIME2 DEFAULT GETUTCDATE(),
      region NVARCHAR(50),
      updatedAt DATETIME2 NULL,
      updatedRegion NVARCHAR(50) NULL
  );
  ```

### Task 2.5: Insert Sample Data
- [ ] Insert sample posts data (SQL INSERT)

---

## 📘 Understanding Azure SQL Database Architecture

### Concept 1: SQL Database Sync Between On-Prem (SEA) and Cloud (IDC)

In this workshop, we simulate **On-Prem (Southeast Asia)** and **Cloud (Indonesia Central)**. Azure SQL uses **Failover Groups** to synchronize data:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    HOW DATA SYNCHRONIZATION WORKS                        │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────┐          ┌─────────────────────┐               │
│  │  PRIMARY SQL SERVER │          │ SECONDARY SQL SERVER│               │
│  │  (Southeast Asia)   │ ──────►  │ (Indonesia Central) │               │
│  │  - Read/Write       │ Async    │  - Read Only        │               │
│  │  - All writes here  │ Geo-Rep  │  - Auto-synced      │               │
│  └─────────────────────┘          └─────────────────────┘               │
│                                                                          │
│  SYNC MECHANISM: Azure SQL Failover Groups                               │
│  ─────────────────────────────────────────────                           │
│  • Asynchronous geo-replication (RPO < 5 seconds)                        │
│  • Data automatically replicated to secondary                            │
│  • No application code changes required                                  │
│  • Transaction log shipped continuously                                  │
│                                                                          │
│  WORKFLOW:                                                               │
│  1. App writes to PRIMARY (SEA) via Failover Group listener              │
│  2. SQL commits transaction on PRIMARY                                   │
│  3. Transaction log shipped to SECONDARY (IDC) asynchronously            │
│  4. SECONDARY replays transaction log (~1-5 seconds delay)               │
│  5. Data now available in both regions                                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key Configuration in Script:**
```bash
# Create Failover Group for automatic sync
az sql failover-group create \
    --name "$SQL_FAILOVER_GROUP" \
    --server "$SQL_SERVER_PRIMARY" \              # SEA (On-Prem simulation)
    --partner-server "$SQL_SERVER_SECONDARY" \    # IDC (Cloud)
    --add-db "$SQL_DATABASE" \
    --failover-policy Automatic \                 # Auto-failover enabled
    --grace-period 60                             # Wait 60 min before auto-failover
```

---

### Concept 2: How Application Points to SQL During Failover

The **Failover Group Listener Endpoint** provides a **single connection string** that automatically redirects to the current primary:

```
┌──────────────────────────────────────────────────────────────────────────┐
│              FAILOVER GROUP LISTENER ENDPOINT                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CONNECTION STRING (Never changes!):                                     │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  Server: fg-resiliency-workshop.database.windows.net               │ │
│  │  (This is the LISTENER endpoint - not individual server names)    │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  NORMAL OPERATION:                                                       │
│  ─────────────────                                                       │
│  App ──► fg-xxx.database.windows.net ──► sql-sea.database.windows.net   │
│                    (Listener)                  (Primary)                 │
│                                                                          │
│  DURING/AFTER FAILOVER:                                                  │
│  ──────────────────────                                                  │
│  App ──► fg-xxx.database.windows.net ──► sql-idc.database.windows.net   │
│                    (Listener)                  (New Primary)             │
│                                                                          │
│  ✅ APP CODE NEVER CHANGES!                                              │
│  ✅ APP ALWAYS USES SAME CONNECTION STRING                               │
│  ✅ AZURE HANDLES REDIRECTION AUTOMATICALLY                              │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**App Configuration (.env):**
```bash
# CORRECT: Use Failover Group Listener (auto-redirects during failover)
SQL_SERVER=fg-resiliency-workshop.database.windows.net

# WRONG: Don't use individual server names (won't failover automatically)
# SQL_SERVER=sql-resiliency-sea.database.windows.net   ❌ Don't do this!
```

**Failover Types:**

| Type | Trigger | Behavior |
|------|---------|----------|
| **Automatic** | SQL Server outage detected | Waits grace period (60 min), then fails over |
| **Manual (Planned)** | Admin initiated | Immediate, no data loss, for maintenance |
| **Manual (Forced)** | Admin initiated | Immediate, possible data loss, for disasters |

**Manual Failover Command:**
```bash
# Force failover to secondary (Indonesia Central becomes new primary)
az sql failover-group set-primary \
    --name "$SQL_FAILOVER_GROUP" \
    --resource-group "$RG_GLOBAL" \
    --server "$SQL_SERVER_SECONDARY"
```

---

### Concept 3: Azure SQL as PaaS - VNet Integration via Private Endpoints

Azure SQL Database is a **Platform-as-a-Service (PaaS)** - it runs on Microsoft-managed infrastructure, NOT inside your VNet. You secure access using **Private Endpoints**:

```
┌──────────────────────────────────────────────────────────────────────────┐
│            AZURE SQL (PaaS) + PRIVATE ENDPOINT ARCHITECTURE              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    AZURE SQL DATABASE (PaaS)                       │ │
│  │  ┌─────────────────────┐      ┌─────────────────────┐             │ │
│  │  │ SQL Server SEA      │      │ SQL Server IDC      │             │ │
│  │  │ (Microsoft Managed) │◄────►│ (Microsoft Managed) │             │ │
│  │  │ Public Access: OFF  │      │ Public Access: OFF  │             │ │
│  │  └──────────┬──────────┘      └──────────┬──────────┘             │ │
│  │             │                            │                         │ │
│  │             │    Failover Group Sync     │                         │ │
│  └─────────────┼────────────────────────────┼─────────────────────────┘ │
│                │                            │                           │
│    ┌───────────▼───────────┐    ┌───────────▼───────────┐              │
│    │   PRIVATE ENDPOINT    │    │   PRIVATE ENDPOINT    │              │
│    │   pe-sql-sea          │    │   pe-sql-idc          │              │
│    │   IP: 10.1.2.4        │    │   IP: 10.2.2.4        │              │
│    └───────────┬───────────┘    └───────────┬───────────┘              │
│                │                            │                           │
│    ┌───────────▼───────────┐    ┌───────────▼───────────┐              │
│    │   YOUR VNET (SEA)     │    │   YOUR VNET (IDC)     │              │
│    │   Spoke: 10.1.0.0/16  │    │   Spoke: 10.2.0.0/16  │              │
│    │                       │    │                       │              │
│    │   VM (10.1.1.4) ──────┼────┼───► VM (10.2.1.4)     │              │
│    │        │              │    │         │             │              │
│    │        ▼              │    │         ▼             │              │
│    │   Connects via        │    │   Connects via        │              │
│    │   Private DNS Zone    │    │   Private DNS Zone    │              │
│    └───────────────────────┘    └───────────────────────┘              │
│                                                                          │
│   PRIVATE DNS ZONE: privatelink.database.windows.net                     │
│   ─────────────────────────────────────────────────                      │
│   sql-resiliency-sea.database.windows.net → 10.1.2.4 (Private IP)       │
│   sql-resiliency-idc.database.windows.net → 10.2.2.4 (Private IP)       │
│   fg-resiliency-workshop.database.windows.net → (Listener endpoint)     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Why Private Endpoints?**

| Without Private Endpoint | With Private Endpoint |
|-------------------------|----------------------|
| Traffic goes over public internet | Traffic stays in Azure backbone |
| SQL has public IP exposed | SQL has NO public IP |
| Need firewall IP rules | Access only from your VNet |
| Less secure | Enterprise-grade security |

**Key Configuration in Script:**
```bash
# 1. Create SQL Server with public access DISABLED
az sql server create \
    --name "$SQL_SERVER_PRIMARY" \
    --enable-public-network false    # ← No public IP!

# 2. Create Private Endpoint in your VNet's PE Subnet
az network private-endpoint create \
    --name "pe-sql-sea" \
    --vnet-name "$VNET_SPOKE_PRIMARY" \
    --subnet "$SUBNET_PE_PRIMARY" \           # PE Subnet: 10.1.2.0/24
    --private-connection-resource-id "$SQL_SERVER_PRIMARY_ID" \
    --group-id "sqlServer"

# 3. Create Private DNS Zone for name resolution
az network private-dns zone create \
    --name "privatelink.database.windows.net"

# 4. Link DNS Zone to your VNets
az network private-dns link vnet create \
    --zone-name "privatelink.database.windows.net" \
    --virtual-network "$SPOKE_VNet_ID"

# 5. Register Private Endpoint IP in DNS Zone (automatic via DNS Zone Group)
az network private-endpoint dns-zone-group create \
    --endpoint-name "pe-sql-sea" \
    --name "sql-dns-zone-group" \
    --private-dns-zone "$PRIVATE_DNS_ZONE_ID"
```

**Summary - PaaS vs IaaS:**

| Aspect | Azure SQL (PaaS) | SQL on VM (IaaS) |
|--------|-----------------|------------------|
| **Location** | Microsoft managed infrastructure | Inside your VNet |
| **Management** | Automatic patching, backups | You manage everything |
| **VNet Integration** | Via Private Endpoints | Direct (VM has NIC in VNet) |
| **Scaling** | Instant, no downtime | Manual, requires VM resize |
| **Geo-Replication** | Built-in Failover Groups | Manual Always On setup |
| **Cost** | Pay per DTU/vCore | Pay for VM + storage + license |

---

## Phase 3: Frontend VM Setup

### Task 3.1: Create VM in Southeast Asia
- [ ] Create VM: `vm-frontend-sea`
  - [ ] Image: Ubuntu 22.04 LTS
  - [ ] Size: Standard_B2s
  - [ ] Public IP: Yes (for direct access testing)
  - [ ] NSG: Allow HTTP (80), HTTPS (443), SSH (22)
- [ ] Install Node.js (v18 LTS)
- [ ] Install PM2 for process management
- [ ] Install Nginx as reverse proxy

### Task 3.2: Create VM in Indonesia Central
- [ ] Create VM: `vm-frontend-idc`
  - [ ] Image: Ubuntu 22.04 LTS
  - [ ] Size: Standard_B2s
  - [ ] Public IP: Yes (for direct access testing)
  - [ ] NSG: Allow HTTP (80), HTTPS (443), SSH (22)
- [ ] Install Node.js (v18 LTS)
- [ ] Install PM2 for process management
- [ ] Install Nginx as reverse proxy

---

## Phase 4: Node.js Application Development

### Task 4.1: Create Social Media App Structure
- [ ] Initialize Node.js project
- [ ] Install dependencies:
  - [ ] express
  - [ ] mssql (SQL Server driver)
  - [ ] dotenv
  - [ ] ejs (for templating)
  - [ ] uuid

### Task 4.2: Create Application Files
- [ ] Create `app.js` - Main application entry
- [ ] Create `routes/` - API routes
- [ ] Create `views/` - EJS templates
- [ ] Create `public/` - Static assets (CSS, JS)
- [ ] Create `.env` - Environment configuration

### Task 4.3: Implement Features
- [ ] Home page showing all posts
- [ ] Simple form to create new post
  - [ ] Fields: Username, Message, Timestamp
- [ ] Display region indicator (show which region is serving)
- [ ] Real-time post list update
- [ ] Health check endpoint (`/health`)

### Task 4.4: Deploy Application
- [ ] Deploy to Southeast Asia VM
- [ ] Deploy to Indonesia Central VM
- [ ] Configure PM2 to auto-restart
- [ ] Configure Nginx reverse proxy
- [ ] Test both deployments independently

---

## Phase 5: Azure Front Door Setup

### Task 5.1: Create Front Door Profile
- [ ] Create Front Door: `fd-resiliency-workshop`
  - [ ] Tier: Standard or Premium
  - [ ] Create custom domain (optional)

### Task 5.2: Configure Origin Groups
- [ ] Create Origin Group: `og-frontend`
  - [ ] Health Probe:
    - [ ] Path: `/health`
    - [ ] Protocol: HTTP
    - [ ] Interval: 30 seconds
  - [ ] Load Balancing:
    - [ ] Sample Size: 4
    - [ ] Successful Samples Required: 3

### Task 5.3: Add Origins
- [ ] Add Origin 1: Southeast Asia VM
  - [ ] Priority: 1 (Primary)
  - [ ] Weight: 1000
- [ ] Add Origin 2: Indonesia Central VM
  - [ ] Priority: 2 (Secondary/Failover)
  - [ ] Weight: 1000

### Task 5.4: Configure Routes
- [ ] Create Route: `route-default`
  - [ ] Domains: Front Door endpoint
  - [ ] Origin Group: `og-frontend`
  - [ ] Patterns: `/*`
  - [ ] Forwarding Protocol: HTTP Only (for demo)

---

## Phase 6: Testing & Validation

### Task 6.1: Test Normal Operation
- [ ] Access application via Front Door URL
- [ ] Verify traffic goes to Southeast Asia (Primary)
- [ ] Create a new post via the form
- [ ] Verify post appears immediately

### Task 6.2: Test Azure SQL Failover Group Sync
- [ ] Create post from Southeast Asia endpoint
- [ ] Directly access Indonesia Central endpoint
- [ ] Verify post is synced automatically via Failover Group
- [ ] Check sync latency (should be < 5 seconds for RPO)

### Task 6.3: Test Failover
- [ ] Stop the application on Southeast Asia VM
  ```bash
  sudo systemctl stop nginx
  # or
  pm2 stop all
  ```
- [ ] Wait for Front Door health probe to detect failure (~30-60 seconds)
- [ ] Verify Front Door switches to Indonesia Central
- [ ] Create a new post
- [ ] Verify post is saved to Azure SQL Database
- [ ] Restart Southeast Asia VM
- [ ] Verify Front Door switches back to primary
- [ ] Verify new posts are synced

---

## Phase 7: Workshop Demo Script

### Demo 1: Show Architecture
- [ ] Explain the architecture diagram
- [ ] Show both regions in Azure Portal
- [ ] Show Azure SQL Failover Group settings

### Demo 2: Normal Operation
- [ ] Access app via Front Door
- [ ] Show which region is serving (region indicator)
- [ ] Create a post
- [ ] Refresh to show post saved

### Demo 3: Data Sync Demo
- [ ] Open two browser tabs:
  - [ ] Tab 1: App via Southeast Asia direct IP
  - [ ] Tab 2: App via Indonesia Central direct IP
- [ ] Create post in Tab 1
- [ ] Refresh Tab 2 to show auto-sync
- [ ] Explain Azure SQL Failover Group geo-replication

### Demo 4: Failover Demo
- [ ] Show Front Door health status (healthy)
- [ ] Stop Southeast Asia VM/App
- [ ] Show Front Door detecting unhealthy origin
- [ ] Refresh app - traffic now served from Indonesia Central
- [ ] Create post to prove app still works
- [ ] Restart Southeast Asia VM
- [ ] Show traffic returns to primary

---

## Phase 8: Cleanup (Post-Workshop)

### Task 8.1: Resource Cleanup
- [ ] Delete Resource Group: `rg-resiliency-sea`
- [ ] Delete Resource Group: `rg-resiliency-idc`
- [ ] Delete Resource Group: `rg-resiliency-global`
- [ ] Verify all resources deleted to avoid charges

---

## Appendix A: Sample Data

### Sample Posts JSON
```json
[
  {
    "id": "post-001",
    "userId": "user-001",
    "username": "john_doe",
    "message": "Hello from the resiliency workshop!",
    "timestamp": "2026-01-13T10:00:00Z",
    "region": "Southeast Asia"
  },
  {
    "id": "post-002",
    "userId": "user-002",
    "username": "jane_smith",
    "message": "Testing Azure SQL sync!",
    "timestamp": "2026-01-13T10:05:00Z",
    "region": "Southeast Asia"
  }
]
```

### Sample Users JSON
```json
[
  {
    "id": "user-001",
    "username": "john_doe",
    "email": "john@example.com",
    "createdAt": "2026-01-13T09:00:00Z"
  },
  {
    "id": "user-002",
    "username": "jane_smith",
    "email": "jane@example.com",
    "createdAt": "2026-01-13T09:30:00Z"
  }
]
```

---

## Appendix B: Estimated Costs

| Resource | SKU | Est. Cost/Hour |
|----------|-----|----------------|
| VM (x2) | Standard_B2s | ~$0.05/hr each |
| APIM (x2) | Developer | ~$0.07/hr each |
| Azure SQL | General Purpose (S0) | ~$0.02/hr each |
| Front Door | Standard | ~$0.05/hr |
| **Total** | | **~$0.54/hr** |

*Note: Costs are estimates. Delete resources after workshop to minimize charges.*

---

## Appendix C: Useful Commands

### VM Setup Commands
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2
sudo npm install -g pm2

# Install Nginx
sudo apt install -y nginx

# Clone/Deploy app
cd /var/www
git clone <your-repo-url> social-media-app
cd social-media-app
npm install

# Start with PM2
pm2 start app.js --name "social-media"
pm2 save
pm2 startup
```

### Nginx Configuration
```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### Stop/Start Commands for Demo
```bash
# Stop app (simulate failure)
sudo systemctl stop nginx
# or
pm2 stop all

# Start app (restore)
sudo systemctl start nginx
# or
pm2 start all
```

---

## Workshop Timeline (Suggested)

| Time | Activity |
|------|----------|
| 0:00 - 0:15 | Introduction & Architecture Overview |
| 0:15 - 0:45 | Setup Phase 1-3 (Infrastructure + Azure SQL) |
| 0:45 - 1:15 | Setup Phase 4-5 (VMs + Application) |
| 1:15 - 1:30 | Break |
| 1:30 - 2:00 | Setup Phase 6 (Front Door) |
| 2:00 - 2:30 | Testing & Validation |
| 2:30 - 3:00 | Demo & Q&A |

---

## Success Criteria

✅ Both regions serve the same application  
✅ Azure SQL Failover Group syncs data between regions (RPO < 5 seconds)  
✅ Front Door detects Southeast Asia failure  
✅ Traffic automatically failovers to Indonesia Central  
✅ New posts created during failover are preserved  
✅ Traffic returns to primary when Southeast Asia recovers  
