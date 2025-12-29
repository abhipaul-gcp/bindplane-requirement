# BindPlane Enterprise Deployment - Pre-Implementation Requirements Document

**Document Version:** 1.0

**Target Platform:** RHEL 9.x (Hardened Enterprise Environment)
**Deployment Type:** On-Premises with Load-Balanced Architecture

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Infrastructure Overview](#infrastructure-overview)
3. [Offline Installation Packages](#offline-installation-packages)
4. [System Configuration Requirements](#system-configuration-requirements)
5. [Firewall Rules Matrix](#firewall-rules-matrix)
6. [Hardened RHEL 9 Considerations](#hardened-rhel-9-considerations)
7. [Network Load Balancer Configuration](#network-load-balancer-configuration)
8. [Certificate Requirements for TLS/mTLS](#certificate-requirements-for-tlsmtls)
9. [Active Directory Authentication](#active-directory-authentication)
10. [Pre-Installation Checklist](#pre-installation-checklist)
11. [Post-Installation Validation](#post-installation-validation)

---

## Executive Summary

This document outlines the complete requirements for deploying BindPlane in a hardened enterprise environment with the following architecture:

- **1 BindPlane Management Server** with PostgreSQL 16 database
- **3 Gateway Instances** behind Network Load Balancer (NLB)
- **3 Collector Instances** consuming from Kafka and forwarding to gateways
- **Full TLS/mTLS** encryption for all communication paths
- **Active Directory** integration for authentication
- **Offline installation** capability for air-gapped environments

---

## Infrastructure Overview

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                  Enterprise Network (On-Premises)               │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         BindPlane Management Server (RHEL 9)            │  │
│  │         IP: 10.10.0.17                                   │  │
│  │         PostgreSQL 16 Database (local)                   │  │
│  │         Ports: 3001 (OpAMP/WSS), 5432 (PostgreSQL)      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             │                                   │
│                             │ OpAMP/WSS (TLS 1.3)              │
│              ┌──────────────┴────────────────┐                 │
│              │                               │                  │
│  ┌───────────▼──────────┐       ┌───────────▼──────────────┐  │
│  │  Gateway Cluster (3) │       │  Collector Cluster (3+)  │  │
│  │                      │       │                          │  │
│  │  Network Load        │       │  IPs: 10.20.0.x         │  │
│  │  Balancer (NLB)      │◄──────│                          │  │
│  │  VIP: 10.10.0.10     │ OTLP  │  Consume from Kafka     │  │
│  │  Port: 4317 (gRPC)   │ mTLS  │  Forward to NLB         │  │
│  │                      │       │                          │  │
│  │  Backend Instances:  │       └──────────────────────────┘  │
│  │  - 10.10.0.11        │                                      │
│  │  - 10.10.0.12        │       ┌──────────────────────────┐  │
│  │  - 10.10.0.18        │       │  Kafka Broker Cluster    │  │
│  └──────────────────────┘       │  Ports: 9094 (SSL)       │  │
│                                 └──────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Active Directory (Authentication)                │  │
│  │         LDAP/LDAPS (Port 636)                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Component Specifications

| Component | Count | OS | vCPU | RAM | Disk | Role |
|-----------|-------|-----|------|-----|------|------|
| **BindPlane Management** | 1 | RHEL 9 | 4 | 8 GB | 100 GB | Management server, PostgreSQL 16, OpAMP server |
| **Gateway Instances** | 3 | RHEL 9 | 8 | 16 GB | 1 TB | OTLP relay, load distribution |
| **Collector Instances** | 3 | RHEL 9 | 8 | 16 GB | 1 TB| Data collection from Kafka, forwarding to gateways |
| **PostgreSQL Database** | 1 | - | - | - | - | Embedded in management server |
| **Network Load Balancer** | 1 | - | - | - | - | Gateway cluster load balancing |

---

## Offline Installation Packages

### Required for All Servers

All packages must be downloaded and transferred to on-premises environment before installation.

#### 1. BindPlane Management Server Packages

**Primary Software:**

```bash
# BindPlane Enterprise Edition (EE) Server
Package: bindplane-ee_v1.96.7-linux_amd64.rpm
Version: 1.96.7 (Enterprise Edition)
Size: ~382 MB
Download URL: https://storage.googleapis.com/bindplane-op-releases/bindplane/1.96.7/bindplane-ee_linux_amd64.rpm

# Direct download link (use wget or curl):
wget https://storage.googleapis.com/bindplane-op-releases/bindplane/1.96.7/bindplane-ee_linux_amd64.rpm -O bindplane-ee_v1.96.7-linux_amd64.rpm

# Or using curl:
curl -L "https://storage.googleapis.com/bindplane-op-releases/bindplane/1.96.7/bindplane-ee_linux_amd64.rpm" -o bindplane-ee_v1.96.7-linux_amd64.rpm
```

**PostgreSQL 16 Database:**

```bash
# PostgreSQL 16 Repository RPM
Package: pgdg-redhat-repo-latest.noarch.rpm
Download URL: https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# PostgreSQL 16 Server
Package: postgresql16-server-16.x.x86_64.rpm
Size: ~6 MB

# PostgreSQL 16 Client
Package: postgresql16-16.x.x86_64.rpm
Size: ~2 MB

# PostgreSQL 16 Libs
Package: postgresql16-libs-16.x.x86_64.rpm
Size: ~400 KB

# PostgreSQL 16 Contrib (optional utilities)
Package: postgresql16-contrib-16.x.x86_64.rpm
Size: ~700 KB
```

**Dependencies for PostgreSQL:**

```bash
# Common dependencies (download from RHEL repository or mirror)
libicu-<version>.el9.x86_64.rpm
lz4-<version>.el9.x86_64.rpm
```

**BindPlane Configuration Scripts:**

```bash
# Custom initialization scripts
bindplane-init.sh          # Initialize BindPlane configuration
postgresql-setup.sh        # PostgreSQL initialization
tls-cert-setup.sh         # TLS certificate deployment
```

#### 2. Gateway and Collector Packages

**ObservIQ OpenTelemetry Collector:**

```bash
# Main collector package
Package: observiq-otel-collector-v1.89.0-linux-amd64.tar.gz
Version: 1.89.0 (or latest)
Size: ~350 MB (compressed)
Download URL: https://github.com/observIQ/bindplane-otel-collector/releases/download/v1.89.0/observiq-otel-collector-v1.89.0-linux-amd64.tar.gz

Contents after extraction:
├── observiq-otel-collector    (~318 MB binary)
├── config.yaml
├── logging.yaml
├── manager.yaml.example
├── plugins/
│   ├── cisco_meraki_logs.so
│   ├── mongodb_logs.so
│   ├── oracle_logs.so
│   ├── sqlserver_logs.so
│   └── ... (100+ plugins)
├── updater
├── LICENSE
└── VERSION.txt
```

#### 3. OpenSSL and Certificate Tools

**Required for certificate generation and validation:**

```bash
# OpenSSL (usually pre-installed on RHEL 9)
Package: openssl-3.x.x.el9.x86_64.rpm
Size: ~1.2 MB

# OpenSSL libs
Package: openssl-libs-3.x.x.el9.x86_64.rpm
Size: ~2.5 MB

# CA certificates bundle
Package: ca-certificates-<version>.el9.noarch.rpm
Size: ~400 KB
```

#### 4. System Utilities

**Required for monitoring and troubleshooting:**

```bash
# Network tools
Package: net-tools-2.x.el9.x86_64.rpm
Package: bind-utils-9.x.el9.x86_64.rpm

# Process management
Package: htop-3.x.el9.x86_64.rpm
Package: lsof-4.x.el9.x86_64.rpm

# Text processing
Package: jq-1.x.el9.x86_64.rpm
```

### Package Transfer Instructions

**Step 1: Download all packages on internet-connected system:**

```bash
# Create package directory
mkdir -p /tmp/bindplane-packages/{management,gateway,collector,common}

# Download BindPlane EE server
cd /tmp/bindplane-packages/management
wget https://storage.googleapis.com/bindplane-op-releases/bindplane/1.96.7/bindplane-ee_linux_amd64.rpm -O bindplane-ee_v1.96.7-linux_amd64.rpm

# Download PostgreSQL
wget https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Download collector
cd /tmp/bindplane-packages/collector
wget https://github.com/observIQ/bindplane-otel-collector/releases/download/v1.89.0/observiq-otel-collector-v1.89.0-linux-amd64.tar.gz

# Create checksums
cd /tmp/bindplane-packages
find . -type f -exec sha256sum {} \; > SHA256SUMS
```

**Step 2: Create transfer archive:**

```bash
cd /tmp
tar -czf bindplane-packages-$(date +%Y%m%d).tar.gz bindplane-packages/
```

**Step 3: Transfer to on-premises environment:**

```bash
# Via secure media (USB, DVD) or secure file transfer
# Verify checksums after transfer:
cd /path/to/transferred/bindplane-packages
sha256sum -c SHA256SUMS
```

### Installation Scripts

#### Management Server Installation Script

**File:** `install-management-server.sh`

```bash
#!/bin/bash
# BindPlane Management Server Installation Script
# For RHEL 9.x offline installation

set -euo pipefail

PACKAGE_DIR="/opt/bindplane-packages/management"
INSTALL_USER="bindplane"
DATA_DIR="/var/lib/bindplane"
CONFIG_DIR="/etc/bindplane"

echo "=== BindPlane Management Server Installation ==="
echo "Package directory: $PACKAGE_DIR"

# Install PostgreSQL repository
echo "Installing PostgreSQL repository..."
sudo rpm -ivh $PACKAGE_DIR/pgdg-redhat-repo-latest.noarch.rpm || true

# Disable PostgreSQL modules (RHEL 9 specific)
sudo dnf -qy module disable postgresql

# Install PostgreSQL 16
echo "Installing PostgreSQL 16..."
sudo dnf install -y \
  $PACKAGE_DIR/postgresql16-libs-*.rpm \
  $PACKAGE_DIR/postgresql16-16.*.rpm \
  $PACKAGE_DIR/postgresql16-server-*.rpm \
  $PACKAGE_DIR/postgresql16-contrib-*.rpm

# Initialize PostgreSQL
echo "Initializing PostgreSQL database..."
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb

# Enable and start PostgreSQL
sudo systemctl enable postgresql-16
sudo systemctl start postgresql-16

# Configure PostgreSQL for BindPlane
echo "Configuring PostgreSQL..."
sudo -u postgres psql -c "CREATE DATABASE bindplane;"
sudo -u postgres psql -c "CREATE USER bindplane WITH ENCRYPTED PASSWORD 'CHANGE_ME';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE bindplane TO bindplane;"

# Update pg_hba.conf for local access
sudo tee -a /var/lib/pgsql/16/data/pg_hba.conf > /dev/null <<'EOF'
# BindPlane local access
host    bindplane       bindplane       127.0.0.1/32            scram-sha-256
host    bindplane       bindplane       ::1/128                 scram-sha-256
EOF

# Restart PostgreSQL
sudo systemctl restart postgresql-16

# Install BindPlane EE Server
echo "Installing BindPlane EE Server..."
sudo rpm -ivh $PACKAGE_DIR/bindplane-ee_v1.96.7-linux_amd64.rpm

# Create BindPlane directories
sudo mkdir -p $DATA_DIR $CONFIG_DIR/ssl

# Set ownership
sudo chown -R $INSTALL_USER:$INSTALL_USER $DATA_DIR $CONFIG_DIR

echo "=== Installation Complete ==="
echo "Next steps:"
echo "1. Configure TLS certificates in $CONFIG_DIR/ssl/"
echo "2. Update BindPlane configuration in $CONFIG_DIR/config.yaml"
echo "3. Start BindPlane service: sudo systemctl start bindplane"
```

#### Gateway/Collector Installation Script

**File:** `install-collector.sh`

```bash
#!/bin/bash
# ObservIQ Collector Installation Script
# For RHEL 9.x offline installation

set -euo pipefail

PACKAGE_DIR="/opt/bindplane-packages/collector"
INSTALL_DIR="/opt/observiq-otel-collector"
SERVICE_USER="bdot"

echo "=== ObservIQ Collector Installation ==="
echo "Package directory: $PACKAGE_DIR"

# Extract collector package
echo "Extracting collector package..."
cd $PACKAGE_DIR
tar -xzf observiq-otel-collector-v*.tar.gz

# Create installation directory
echo "Creating installation directory..."
sudo mkdir -p $INSTALL_DIR

# Copy files
echo "Copying files to $INSTALL_DIR..."
sudo cp observiq-otel-collector $INSTALL_DIR/
sudo cp config.yaml $INSTALL_DIR/
sudo cp logging.yaml $INSTALL_DIR/
sudo cp -r plugins $INSTALL_DIR/

# Create service user
echo "Creating service user..."
sudo useradd -r -s /bin/false $SERVICE_USER || true

# Set permissions
echo "Setting permissions..."
sudo chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
sudo chmod +x $INSTALL_DIR/observiq-otel-collector

# Create SSL directory
sudo mkdir -p $INSTALL_DIR/ssl
sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/ssl

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/observiq-otel-collector.service > /dev/null <<'EOF'
[Unit]
Description=observIQ OpenTelemetry Collector
After=network.target

[Service]
Type=simple
User=bdot
Group=bdot
WorkingDirectory=/opt/observiq-otel-collector
ExecStart=/opt/observiq-otel-collector/observiq-otel-collector --manager /opt/observiq-otel-collector/manager.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=55000

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/observiq-otel-collector

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

echo "=== Installation Complete ==="
echo "Next steps:"
echo "1. Configure manager.yaml for OpAMP connection"
echo "2. Deploy TLS certificates to $INSTALL_DIR/ssl/"
echo "3. Enable service: sudo systemctl enable observiq-otel-collector"
echo "4. Start service: sudo systemctl start observiq-otel-collector"
```

---

## System Configuration Requirements

### Apply to All Servers (Management, Gateway, Collector)

#### 1. File Descriptor Limits

**Requirement:** RHEL 9 defaults to 1024 open files, which is insufficient for production workloads.

**Target:** Increase `LimitNOFILE` to **55,000** for all BindPlane services.

**Implementation:**

**Option A: Configure in systemd service files (Recommended)**

The service files above already include `LimitNOFILE=55000`.

Verify after service is created:

```bash
# Check systemd limits for running service
sudo systemctl show observiq-otel-collector | grep LimitNOFILE

# Expected output:
# LimitNOFILE=55000
# LimitNOFILESoft=55000
```

**Option B: System-wide configuration**

Edit `/etc/security/limits.conf`:

```bash
sudo tee -a /etc/security/limits.conf > /dev/null <<'EOF'
# BindPlane file descriptor limits
bdot             soft    nofile          55000
bdot             hard    nofile          55000
bindplane        soft    nofile          55000
bindplane        hard    nofile          55000
postgres         soft    nofile          55000
postgres         hard    nofile          55000
EOF
```

**Verification:**

```bash
# After service starts, check actual limits
sudo -u bdot bash -c 'ulimit -Sn'  # Should show 55000
sudo -u bdot bash -c 'ulimit -Hn'  # Should show 55000

# Check running process limits
pgrep -u bdot observiq-otel-collector | xargs -I {} cat /proc/{}/limits | grep "open files"
```

#### 2. Antivirus & Security Exclusions

**Requirement:** Exclude BindPlane directories from real-time scanning to prevent performance degradation.

**Directories to Exclude:**

```bash
# BindPlane Management Server
/var/lib/bindplane/
/etc/bindplane/
/opt/bindplane/
/var/lib/pgsql/16/data/
/usr/pgsql-16/

# Gateway and Collector Instances
/opt/observiq-otel-collector/
/opt/observiq-otel-collector/plugins/
/opt/observiq-otel-collector/ssl/
/var/log/observiq-otel-collector/

# Temporary and cache directories
/tmp/bindplane/
/var/tmp/observiq/
```

**Processes to Exclude:**

```bash
# Binary executables
/opt/bindplane/bindplane
/opt/observiq-otel-collector/observiq-otel-collector
/usr/pgsql-16/bin/postgres

# By service user
bdot (all processes)
bindplane (all processes)
postgres (all processes)
```

**Network Ports to Exclude from Deep Packet Inspection:**

```bash
# BindPlane Management
TCP 3001 (OpAMP/WSS)
TCP 5432 (PostgreSQL - local only)
TCP 3000 (BindPlane UI - HTTPS)

# Gateways
TCP 4317 (OTLP gRPC)
TCP 4318 (OTLP HTTP)

# Collectors
TCP 9094 (Kafka SSL)
```

**Example for ClamAV:**

Edit `/etc/clamd.d/scan.conf`:

```bash
# Exclude BindPlane directories
ExcludePath ^/var/lib/bindplane/
ExcludePath ^/opt/observiq-otel-collector/
ExcludePath ^/var/lib/pgsql/16/data/
```

**Example for McAfee VirusScan Enterprise:**

```bash
# Via GUI: Exclude these paths from On-Access Scan
# Or via command line:
/opt/McAfee/VirusScanEnterprise/bin/scancfg --exclude /var/lib/bindplane/ --recursive
/opt/McAfee/VirusScanEnterprise/bin/scancfg --exclude /opt/observiq-otel-collector/ --recursive
```

#### 3. SELinux Configuration

**Recommended:** Keep SELinux in **enforcing** mode with custom policy.

**Option A: Custom SELinux Policy (Recommended)**

```bash
# Create custom policy for BindPlane
sudo tee /tmp/bindplane.te > /dev/null <<'EOF'
module bindplane 1.0;

require {
    type unconfined_service_t;
    type usr_t;
    type var_lib_t;
    class file { read write open getattr };
    class dir { read search open };
}

# Allow BindPlane to access required directories
allow unconfined_service_t usr_t:file { read open getattr };
allow unconfined_service_t var_lib_t:dir { read search open };
allow unconfined_service_t var_lib_t:file { read write open getattr };
EOF

# Compile and install policy
sudo checkmodule -M -m -o /tmp/bindplane.mod /tmp/bindplane.te
sudo semodule_package -o /tmp/bindplane.pp -m /tmp/bindplane.mod
sudo semodule -i /tmp/bindplane.pp
```

**Option B: Permissive Mode for BindPlane Services Only**

```bash
# Set permissive mode for specific services
sudo semanage permissive -a unconfined_service_t
```

**Option C: Disabled (Not Recommended)**

```bash
# Only if required by security policy
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

**Verification:**

```bash
# Check SELinux status
getenforce

# Check service contexts
ps -eZ | grep observiq-otel-collector
ls -Z /opt/observiq-otel-collector/
```

#### 4. Kernel Parameters

**For high-throughput environments:**

Edit `/etc/sysctl.d/99-bindplane.conf`:

```bash
sudo tee /etc/sysctl.d/99-bindplane.conf > /dev/null <<'EOF'
# Network buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Connection tracking
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576

# TCP settings
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 5000

# File handles
fs.file-max = 2097152
EOF

# Apply settings
sudo sysctl -p /etc/sysctl.d/99-bindplane.conf
```

---

## Firewall Rules Matrix

### Overview

All communication uses TLS/mTLS encryption. Firewall rules must allow encrypted traffic on specific ports.

### Management Server Firewall Rules

**Inbound Rules (Management Server: 10.10.0.17):**

| Source | Protocol | Port | Purpose | Required |
|--------|----------|------|---------|----------|
| Gateway instances (10.10.0.11-18) | TCP | 3001 | OpAMP/WSS (Management) | ✅ Yes |
| Collector instances (10.20.0.x) | TCP | 3001 | OpAMP/WSS (Management) | ✅ Yes |
| Administrator workstations | TCP | 3000 | BindPlane UI (HTTPS) | ✅ Yes |
| 127.0.0.1 (localhost) | TCP | 5432 | PostgreSQL (local only) | ✅ Yes |
| Any | TCP | 22 | SSH (Admin access) | Optional |

**Outbound Rules (Management Server: 10.10.0.17):**

| Destination | Protocol | Port | Purpose | Required |
|-------------|----------|------|---------|----------|
| AD Server | TCP | 636 | LDAPS (Authentication) | ✅ Yes (if using AD) |
| AD Server | TCP | 389 | LDAP (Authentication) | Optional |
| NTP Servers | UDP | 123 | Time synchronization | ✅ Yes |
| DNS Servers | UDP | 53 | Name resolution | ✅ Yes |

**Firewalld Configuration:**

```bash
# Management Server firewall rules
sudo firewall-cmd --permanent --add-port=3001/tcp  # OpAMP
sudo firewall-cmd --permanent --add-port=3000/tcp  # UI
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### Gateway Firewall Rules

**Inbound Rules (Gateway Instances: 10.10.0.11, 10.10.0.12, 10.10.0.18):**

| Source | Protocol | Port | Purpose | Required |
|--------|----------|------|---------|----------|
| NLB / Collector instances | TCP | 4317 | OTLP gRPC (mTLS) | ✅ Yes |
| NLB / Collector instances | TCP | 4318 | OTLP HTTP (mTLS) | Optional |
| Any | TCP | 22 | SSH (Admin access) | Optional |

**Outbound Rules (Gateway Instances):**

| Destination | Protocol | Port | Purpose | Required |
|-------------|----------|------|---------|----------|
| Management Server (10.10.0.17) | TCP | 3001 | OpAMP/WSS | ✅ Yes |
| SecOps/SIEM destination | TCP | Various | Log forwarding | ✅ Yes |
| NTP Servers | UDP | 123 | Time synchronization | ✅ Yes |
| DNS Servers | UDP | 53 | Name resolution | ✅ Yes |

**Firewalld Configuration:**

```bash
# Gateway firewall rules
sudo firewall-cmd --permanent --add-port=4317/tcp  # OTLP gRPC
sudo firewall-cmd --permanent --add-port=4318/tcp  # OTLP HTTP
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### Collector Firewall Rules

**Inbound Rules (Collector Instances: 10.20.0.x):**

| Source | Protocol | Port | Purpose | Required |
|--------|----------|------|---------|----------|
| Any | TCP | 22 | SSH (Admin access) | Optional |

**Outbound Rules (Collector Instances):**

| Destination | Protocol | Port | Purpose | Required |
|-------------|----------|------|---------|----------|
| Management Server (10.10.0.17) | TCP | 3001 | OpAMP/WSS | ✅ Yes |
| NLB (10.10.0.10) | TCP | 4317 | OTLP gRPC to Gateways | ✅ Yes |
| Kafka Brokers | TCP | 9094 | Kafka SSL (consume logs) | ✅ Yes |
| Kafka Brokers | TCP | 9092 | Kafka PLAINTEXT (optional) | Optional |
| NTP Servers | UDP | 123 | Time synchronization | ✅ Yes |
| DNS Servers | UDP | 53 | Name resolution | ✅ Yes |

**Firewalld Configuration:**

```bash
# Collector firewall rules (mostly outbound)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### Network Load Balancer Firewall Rules

**Inbound Rules (NLB VIP: 10.10.0.10):**

| Source | Protocol | Port | Purpose | Required |
|--------|----------|------|---------|----------|
| Collector instances (10.20.0.x) | TCP | 4317 | OTLP gRPC (forwarded to backends) | ✅ Yes |
| Collector instances (10.20.0.x) | TCP | 4318 | OTLP HTTP (forwarded to backends) | Optional |

**Backend Health Checks:**

| Source | Protocol | Port | Purpose | Required |
|--------|----------|------|---------|----------|
| NLB | TCP | 4317 | Gateway health check | ✅ Yes |

### Complete Firewall Matrix (All Communication Paths)

```
┌────────────────┐         ┌──────────────┐         ┌─────────────┐
│   Collectors   │────────▶│  NLB/Gateway │────────▶│   SecOps    │
│  (10.20.0.x)   │ 4317    │ (10.10.0.10) │         │             │
└────────────────┘         └──────────────┘         └─────────────┘
        │                         │
        │ 9094 (Kafka SSL)        │ 3001 (OpAMP)
        │                         │
        ▼                         ▼
┌────────────────┐         ┌──────────────┐         ┌─────────────┐
│  Kafka Broker  │         │  Management  │────────▶│  Active Dir │
│  (10.10.0.13)  │         │ (10.10.0.17) │ 636     │   (LDAPS)   │
└────────────────┘         └──────────────┘         └─────────────┘
                                  │
                                  │ 5432 (local)
                                  ▼
                           ┌──────────────┐
                           │  PostgreSQL  │
                           │  (embedded)  │
                           └──────────────┘
```

---

## Hardened RHEL 9 Considerations

### 1. FIPS Mode Compliance

If FIPS 140-2 mode is enabled on RHEL 9:

**Check FIPS status:**

```bash
fips-mode-setup --check
```

**BindPlane FIPS Considerations:**

- TLS 1.3 with FIPS-approved cipher suites
- Use RSA 2048-bit minimum (4096-bit recommended)
- SHA-256 or SHA-384 for signatures

**Approved Cipher Suites:**

```bash
# For OpAMP/WSS and OTLP/gRPC
TLS_AES_256_GCM_SHA384
TLS_AES_128_GCM_SHA256
TLS_CHACHA20_POLY1305_SHA256
```

**PostgreSQL FIPS Configuration:**

Edit `/var/lib/pgsql/16/data/postgresql.conf`:

```bash
ssl = on
ssl_ciphers = 'HIGH:!aNULL:!MD5'
ssl_min_protocol_version = 'TLSv1.2'
```

### 2. CIS Benchmark Compliance

**Apply CIS RHEL 9 Benchmark recommendations:**

**Required Modifications:**

1. **Disable unused services:**
   ```bash
   sudo systemctl disable cups bluetooth avahi-daemon
   ```

2. **Configure audit logging:**
   ```bash
   # Add BindPlane audit rules
   sudo tee /etc/audit/rules.d/bindplane.rules > /dev/null <<'EOF'
   # Monitor BindPlane configuration changes
   -w /etc/bindplane/ -p wa -k bindplane_config
   -w /opt/observiq-otel-collector/ -p wa -k collector_config
   -w /var/lib/bindplane/ -p wa -k bindplane_data
   EOF

   sudo augenrules --load
   ```

3. **SSH hardening:**
   ```bash
   # Edit /etc/ssh/sshd_config
   PermitRootLogin no
   PasswordAuthentication no
   PubkeyAuthentication yes
   Protocol 2
   ```

### 3. DISA STIG Compliance

**Security Technical Implementation Guide (STIG) requirements:**

**Service Account Restrictions:**

```bash
# Ensure service accounts cannot login interactively
sudo usermod -s /sbin/nologin bdot
sudo usermod -s /sbin/nologin bindplane
sudo usermod -s /sbin/nologin postgres

# Verify
getent passwd bdot bindplane postgres
```

**File Integrity Monitoring:**

```bash
# AIDE (Advanced Intrusion Detection Environment)
sudo yum install -y aide
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# Add BindPlane directories to AIDE config
sudo tee -a /etc/aide.conf > /dev/null <<'EOF'
# BindPlane monitoring
/etc/bindplane/ CONTENT_EX
/opt/observiq-otel-collector/ CONTENT_EX
/var/lib/bindplane/ CONTENT_EX
EOF

# Run daily checks
sudo aide --check
```

### 4. Privilege Escalation Prevention

**Restrict sudo access:**

```bash
# Only allow specific commands for BindPlane admin users
sudo visudo -f /etc/sudoers.d/bindplane

# Add:
bindplane-admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart observiq-otel-collector
bindplane-admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl status observiq-otel-collector
bindplane-admin ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u observiq-otel-collector
```

### 5. Log Retention and Rotation

**Configure logrotate for BindPlane logs:**

```bash
sudo tee /etc/logrotate.d/bindplane > /dev/null <<'EOF'
/var/log/observiq-otel-collector/*.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 bdot bdot
    sharedscripts
    postrotate
        /usr/bin/systemctl reload observiq-otel-collector > /dev/null 2>&1 || true
    endscript
}

/var/lib/bindplane/logs/*.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 bindplane bindplane
}
EOF
```

---

## Network Load Balancer Configuration

### NLB Overview

The Network Load Balancer distributes OTLP traffic from collectors across 3 gateway instances.

**Key Requirements:**

- **Type:** Layer 4 (TCP) load balancer
- **VIP:** 10.10.0.10
- **Port:** 4317 (OTLP gRPC)
- **Protocol:** TCP (TLS passthrough - no termination at LB)
- **Health Check:** TCP on port 4317

### NLB Configuration Specifications

#### 1. Frontend Configuration

```yaml
Virtual IP (VIP): 10.10.0.10
Protocol: TCP
Port: 4317
Load Balancing Algorithm: Least Connections (recommended)
Session Persistence: Source IP (5-minute timeout)
```

**Session Persistence:** Required to ensure collector → gateway connection stability for long-lived gRPC streams.

#### 2. Backend Pool Configuration

```yaml
Backend Pool Name: bindplane-gateway-pool

Members:
  - Name: bindplane-gateway-vm-1
    IP: 10.10.0.11
    Port: 4317
    Weight: 100

  - Name: bindplane-gateway-vm-2
    IP: 10.10.0.12
    Port: 4317
    Weight: 100

  - Name: bindplane-gateway-vm-3
    IP: 10.10.0.18
    Port: 4317
    Weight: 100
```

#### 3. Health Check Configuration

```yaml
Protocol: TCP
Port: 4317
Interval: 10 seconds
Timeout: 5 seconds
Unhealthy Threshold: 3 consecutive failures
Healthy Threshold: 2 consecutive successes
```

**Health Check Logic:**

The NLB performs a TCP SYN check to port 4317. A gateway is considered:
- **Healthy:** TCP connection succeeds (SYN-ACK received)
- **Unhealthy:** TCP connection fails or times out

#### 4. TLS/mTLS Considerations

**CRITICAL:** The NLB must operate in **TCP passthrough mode** (Layer 4).

**Why?**
- TLS/mTLS handshake occurs between collector and gateway
- Gateway presents certificate to collector
- NLB only forwards TCP packets without inspection

**Certificate Requirement:**

Gateway certificates **MUST include NLB VIP (10.10.0.10)** in Subject Alternative Names (SAN).

Example certificate SAN:
```
IP Address: 10.10.0.10   (NLB VIP - CRITICAL)
IP Address: 10.10.0.11   (gateway-vm-1)
IP Address: 10.10.0.12   (gateway-vm-2)
IP Address: 10.10.0.18   (gateway-vm-3)
```

Without NLB IP in SAN, collectors will fail TLS validation:
```
Error: x509: certificate is valid for 10.10.0.11, 10.10.0.12, 10.10.0.18, not 10.10.0.10
```

### Platform-Specific NLB Implementations

#### Option 1: HAProxy (On-Premises)

**Installation:**

```bash
sudo yum install -y haproxy
```

**Configuration:** `/etc/haproxy/haproxy.cfg`

```bash
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 10000

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client  300s
    timeout server  300s

frontend bindplane_gateway_frontend
    bind 10.10.0.10:4317
    mode tcp
    default_backend bindplane_gateway_backend

backend bindplane_gateway_backend
    mode tcp
    balance leastconn
    option tcp-check
    stick-table type ip size 1m expire 5m
    stick on src

    # Health checks
    tcp-check connect port 4317

    # Backend servers
    server gateway-vm-1 10.10.0.11:4317 check inter 10s fall 3 rise 2
    server gateway-vm-2 10.10.0.12:4317 check inter 10s fall 3 rise 2
    server gateway-vm-3 10.10.0.18:4317 check inter 10s fall 3 rise 2

# Statistics page (optional)
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 30s
    stats auth admin:CHANGE_PASSWORD
```

**Enable and start:**

```bash
sudo systemctl enable haproxy
sudo systemctl start haproxy

# Verify
sudo systemctl status haproxy
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock
```

#### Option 2: Nginx Stream (On-Premises)

**Installation:**

```bash
sudo yum install -y nginx nginx-mod-stream
```

**Configuration:** `/etc/nginx/nginx.conf`

```nginx
load_module /usr/lib64/nginx/modules/ngx_stream_module.so;

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 10000;
}

stream {
    log_format basic '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time';

    access_log /var/log/nginx/stream-access.log basic;

    upstream bindplane_gateway_backend {
        least_conn;

        # Backend servers
        server 10.10.0.11:4317 max_fails=3 fail_timeout=30s;
        server 10.10.0.12:4317 max_fails=3 fail_timeout=30s;
        server 10.10.0.18:4317 max_fails=3 fail_timeout=30s;
    }

    server {
        listen 10.10.0.10:4317;
        proxy_pass bindplane_gateway_backend;
        proxy_connect_timeout 5s;
        proxy_timeout 300s;
    }
}
```

**Enable and start:**

```bash
sudo systemctl enable nginx
sudo systemctl start nginx

# Verify
sudo systemctl status nginx
sudo ss -tlnp | grep 4317
```

#### Option 3: F5 BIG-IP (Enterprise)

**Configuration via TMSH:**

```bash
# Create pool
tmsh create ltm pool bindplane_gateway_pool \
  members add { \
    10.10.0.11:4317 \
    10.10.0.12:4317 \
    10.10.0.18:4317 \
  } \
  monitor tcp_half_open

# Create virtual server
tmsh create ltm virtual bindplane_gateway_vs \
  destination 10.10.0.10:4317 \
  ip-protocol tcp \
  pool bindplane_gateway_pool \
  profiles add { fastL4 }

tmsh save sys config
```

#### Option 4: Keepalived + LVS (High Availability)

For HA NLB setup with failover:

**Primary NLB Server Configuration:**

```bash
# /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass CHANGE_ME
    }
    virtual_ipaddress {
        10.10.0.10/24
    }
}

virtual_server 10.10.0.10 4317 {
    delay_loop 10
    lb_algo lc
    lb_kind NAT
    protocol TCP

    real_server 10.10.0.11 4317 {
        weight 100
        TCP_CHECK {
            connect_timeout 5
            connect_port 4317
        }
    }

    real_server 10.10.0.12 4317 {
        weight 100
        TCP_CHECK {
            connect_timeout 5
            connect_port 4317
        }
    }

    real_server 10.10.0.18 4317 {
        weight 100
        TCP_CHECK {
            connect_timeout 5
            connect_port 4317
        }
    }
}
```

### NLB Monitoring and Troubleshooting

**Health Check Verification:**

```bash
# Test TCP connection to NLB
nc -zv 10.10.0.10 4317

# Test from collector
openssl s_client -connect 10.10.0.10:4317 -CAfile /opt/observiq-otel-collector/ssl/root.crt

# Expected: Connection successful, TLS handshake completes
```

**Monitor Backend Health:**

```bash
# HAProxy
echo "show servers state" | sudo socat stdio /run/haproxy/admin.sock

# Check connection distribution
sudo netstat -an | grep :4317 | grep ESTABLISHED

# On each gateway, count active connections
for gw in 10.10.0.11 10.10.0.12 10.10.0.18; do
  echo "Gateway $gw:"
  ssh admin@$gw "sudo netstat -an | grep :4317 | grep ESTABLISHED | wc -l"
done
```

---

## Certificate Requirements for TLS/mTLS

### Overview

All communication in the BindPlane infrastructure uses TLS 1.3 or TLS 1.2 with mutual authentication (mTLS) for enhanced security.

**Certificate Authority Options:**

1. **Internal Enterprise CA** (Recommended for on-premises)
   - Microsoft AD Certificate Services
   - HashiCorp Vault PKI
   - OpenSSL-based internal CA

2. **Public CA** (For external-facing components)
   - DigiCert, GlobalSign, Let's Encrypt
   - Note: Most public CAs don't support private IPs in SAN

3. **Self-Signed CA** (Development/Testing only)

### Certificate Inventory

Total certificates required for full deployment:

| Component | Certificate Type | Quantity | Purpose |
|-----------|-----------------|----------|---------|
| **BindPlane Management** | Server | 1 | OpAMP/WSS server, HTTPS UI |
| **PostgreSQL** | Server | 1 | Database TLS (optional) |
| **Gateway Instances** | Server | 1 (shared) | OTLP receiver (NLB architecture) |
| **Collector Instances** | Client | 3+ | mTLS authentication to gateways |
| **Kafka Brokers** | Server | 3+ | Kafka SSL/TLS (external) |
| **Root CA** | CA Certificate | 1 | Trust anchor for all certificates |

**Total:** 1 Root CA + 6+ certificates (depending on collector/gateway count)

### 1. Root CA Certificate

**Purpose:** Trust anchor for the entire BindPlane infrastructure

**Type:** Certificate Authority (CA)

**Generation (Self-Signed CA):**

```bash
# Generate CA private key (4096-bit RSA)
openssl genrsa -out bindplane-ca.key 4096

# Generate self-signed CA certificate (valid 10 years)
openssl req -new -x509 -days 3650 -key bindplane-ca.key -out bindplane-ca.crt \
  -subj "/C=US/ST=California/L=San Francisco/O=Your Company/OU=IT Security/CN=BindPlane Internal CA"

# Verify
openssl x509 -in bindplane-ca.crt -noout -text
```

**Certificate Details:**

```
Subject:
  Common Name (CN): BindPlane Internal CA
  Organization (O): Your Company Name
  Organizational Unit (OU): IT Security
  Country (C): US
  State (ST): California
  Locality (L): San Francisco

Key Specifications:
  Algorithm: RSA
  Key Size: 4096 bits
  Signature: SHA-256

Validity:
  Valid From: YYYY-MM-DD
  Valid To: YYYY-MM-DD (10 years)

Extensions:
  Basic Constraints: CA:TRUE
  Key Usage: Certificate Sign, CRL Sign
```

**Deployment:**

Distribute `bindplane-ca.crt` to all servers:

```
/opt/observiq-otel-collector/ssl/root.crt     (Gateways & Collectors)
/etc/bindplane/ssl/root.crt                   (Management Server)
/var/lib/pgsql/16/data/root.crt              (PostgreSQL)
```

### 2. BindPlane Management Server Certificate

**Purpose:** Secure OpAMP/WSS communication and HTTPS UI

**Type:** Server Certificate (X.509 v3)

**Subject:**

```
Common Name (CN): bindplane.example.com
Organization (O): Your Company
Organizational Unit (OU): IT Operations
Locality (L): San Francisco
State (ST): California
Country (C): US
```

**Subject Alternative Names (SAN):**

```
DNS Names:
  - bindplane.example.com
  - bindplane-mgmt-server-temp.internal.example.com
  - bindplane.internal

IP Addresses:
  - 10.10.0.17 (management server IP)
  - X.X.X.X (external IP if accessible from internet)
```

**Key Specifications:**

```
Algorithm: RSA
Key Size: 4096 bits (recommended)
Signature Algorithm: SHA-256
```

**Extended Key Usage (EKU):**

```
- TLS Web Server Authentication (1.3.6.1.5.5.7.3.1)
- TLS Web Client Authentication (1.3.6.1.5.5.7.3.2)
```

**Validity:** 2 years (for Enterprise CA)

**OpenSSL Configuration File:**

`bindplane-server.conf`:

```ini
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = California
L = San Francisco
O = Your Company
OU = IT Operations
CN = bindplane.example.com

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE

[alt_names]
DNS.1 = bindplane.example.com
DNS.2 = bindplane-mgmt-server-temp.internal.example.com
DNS.3 = bindplane.internal
IP.1 = 10.10.0.17
```

**Generation:**

```bash
# Generate private key
openssl genrsa -out bindplane-server.key 4096

# Generate CSR
openssl req -new -key bindplane-server.key -out bindplane-server.csr \
  -config bindplane-server.conf

# Sign with CA (if using self-signed CA)
openssl x509 -req -in bindplane-server.csr \
  -CA bindplane-ca.crt -CAkey bindplane-ca.key -CAcreateserial \
  -out bindplane-server.crt -days 730 -sha256 \
  -extfile bindplane-server.conf -extensions v3_req

# Verify
openssl x509 -in bindplane-server.crt -noout -text
openssl verify -CAfile bindplane-ca.crt bindplane-server.crt
```

**Deployment:**

```bash
/etc/bindplane/ssl/server.crt
/etc/bindplane/ssl/server.key
/etc/bindplane/ssl/ca.crt  (root CA)
```

**File Permissions:**

```bash
sudo chown bindplane:bindplane /etc/bindplane/ssl/*
sudo chmod 644 /etc/bindplane/ssl/server.crt
sudo chmod 600 /etc/bindplane/ssl/server.key
sudo chmod 644 /etc/bindplane/ssl/ca.crt
```

### 3. Gateway Server Certificate (Load-Balanced)

**Purpose:** OTLP/gRPC receiver for collectors (behind NLB)

**Type:** Server Certificate (X.509 v3)

**CRITICAL REQUIREMENT:** Must include NLB VIP (10.10.0.10) in SAN

**Subject:**

```
Common Name (CN): gateway.example.com
Organization (O): Your Company
Organizational Unit (OU): Observability Platform
Locality (L): San Francisco
State (ST): California
Country (C): US
```

**Subject Alternative Names (SAN):**

```
DNS Names:
  - gateway.example.com
  - gateway-nlb.example.com
  - gateway-vm-1.example.com
  - gateway-vm-2.example.com
  - gateway-vm-3.example.com
  - *.gateway.example.com (wildcard for scaling)

IP Addresses (CRITICAL):
  - 10.10.0.10  (NLB VIP - MUST be included)
  - 10.10.0.11  (gateway-vm-1)
  - 10.10.0.12  (gateway-vm-2)
  - 10.10.0.18  (gateway-vm-3)
```

**Key Specifications:**

```
Algorithm: RSA
Key Size: 2048 bits minimum (4096 recommended)
Signature Algorithm: SHA-256
```

**Extended Key Usage (EKU):**

```
- TLS Web Server Authentication (1.3.6.1.5.5.7.3.1)
- TLS Web Client Authentication (1.3.6.1.5.5.7.3.2)
```

**Validity:** 1-2 years

**OpenSSL Configuration File:**

`gateway-nlb.conf`:

```ini
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = California
L = San Francisco
O = Your Company
OU = Observability Platform
CN = gateway.example.com

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE

[alt_names]
# NLB VIP - CRITICAL
IP.1 = 10.10.0.10

# Individual gateway IPs
IP.2 = 10.10.0.11
IP.3 = 10.10.0.12
IP.4 = 10.10.0.18

# DNS names
DNS.1 = gateway.example.com
DNS.2 = gateway-nlb.example.com
DNS.3 = gateway-vm-1.example.com
DNS.4 = gateway-vm-2.example.com
DNS.5 = gateway-vm-3.example.com
DNS.6 = *.gateway.example.com
```

**Generation:**

```bash
# Generate private key
openssl genrsa -out gateway-nlb.key 4096

# Generate CSR
openssl req -new -key gateway-nlb.key -out gateway-nlb.csr \
  -config gateway-nlb.conf

# Sign with CA
openssl x509 -req -in gateway-nlb.csr \
  -CA bindplane-ca.crt -CAkey bindplane-ca.key -CAcreateserial \
  -out gateway-nlb.crt -days 730 -sha256 \
  -extfile gateway-nlb.conf -extensions v3_req

# Verify NLB IP is in SAN
openssl x509 -in gateway-nlb.crt -noout -text | grep -A10 "Subject Alternative Name"
# MUST show: IP Address:10.10.0.10
```

**Deployment (same certificate to all 3 gateways):**

```bash
# Gateway VM 1
/opt/observiq-otel-collector/ssl/server.crt
/opt/observiq-otel-collector/ssl/server.key
/opt/observiq-otel-collector/ssl/root.crt

# Gateway VM 2
/opt/observiq-otel-collector/ssl/server.crt  (same cert)
/opt/observiq-otel-collector/ssl/server.key  (same key)
/opt/observiq-otel-collector/ssl/root.crt

# Gateway VM 3
/opt/observiq-otel-collector/ssl/server.crt  (same cert)
/opt/observiq-otel-collector/ssl/server.key  (same key)
/opt/observiq-otel-collector/ssl/root.crt
```

**File Permissions:**

```bash
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/*
sudo chmod 644 /opt/observiq-otel-collector/ssl/server.crt
sudo chmod 600 /opt/observiq-otel-collector/ssl/server.key
sudo chmod 644 /opt/observiq-otel-collector/ssl/root.crt
```

### 4. Collector Client Certificates (mTLS)

**Purpose:** Authenticate collectors to gateways (mutual TLS)

**Type:** Client Certificate (X.509 v3)

**Strategy:** Individual certificate per collector OR shared certificate for all collectors

**Subject (Individual):**

```
Common Name (CN): collector-01.example.com
Organization (O): Your Company
Organizational Unit (OU): Collectors
Locality (L): San Francisco
State (ST): California
Country (C): US
```

**Subject Alternative Names (SAN):**

```
DNS Names:
  - collector-01.example.com
  - kafka-collector-vm.internal.example.com

IP Addresses:
  - 10.20.0.3 (collector IP)
```

**Key Specifications:**

```
Algorithm: RSA
Key Size: 2048 bits
Signature Algorithm: SHA-256
```

**Extended Key Usage (EKU):**

```
- TLS Web Client Authentication (1.3.6.1.5.5.7.3.2)
```

**Validity:** 1 year

**OpenSSL Configuration File:**

`collector-client.conf`:

```ini
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = California
L = San Francisco
O = Your Company
OU = Collectors
CN = collector-01.example.com

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
basicConstraints = critical, CA:FALSE

[alt_names]
DNS.1 = collector-01.example.com
DNS.2 = kafka-collector-vm.internal.example.com
IP.1 = 10.20.0.3
```

**Generation:**

```bash
# Generate private key
openssl genrsa -out collector-client.key 2048

# Generate CSR
openssl req -new -key collector-client.key -out collector-client.csr \
  -config collector-client.conf

# Sign with CA
openssl x509 -req -in collector-client.csr \
  -CA bindplane-ca.crt -CAkey bindplane-ca.key -CAcreateserial \
  -out collector-client.crt -days 365 -sha256 \
  -extfile collector-client.conf -extensions v3_req

# Verify
openssl x509 -in collector-client.crt -noout -text
```

**Deployment:**

```bash
/opt/observiq-otel-collector/ssl/gateway-client.crt
/opt/observiq-otel-collector/ssl/gateway-client.key
/opt/observiq-otel-collector/ssl/root.crt
```

**File Permissions:**

```bash
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/gateway-client.*
sudo chmod 644 /opt/observiq-otel-collector/ssl/gateway-client.crt
sudo chmod 600 /opt/observiq-otel-collector/ssl/gateway-client.key
```

### 5. PostgreSQL Server Certificate (Optional)

**Purpose:** Encrypt PostgreSQL connections (if remote access required)

**Type:** Server Certificate (X.509 v3)

**Subject:**

```
Common Name (CN): postgres.example.com
Organization (O): Your Company
Organizational Unit (OU): Database Services
```

**Subject Alternative Names (SAN):**

```
DNS Names:
  - postgres.example.com
  - postgres.internal.example.com

IP Addresses:
  - 10.10.0.17 (if allowing remote connections)
```

**Deployment:**

```bash
/var/lib/pgsql/16/data/server.crt
/var/lib/pgsql/16/data/server.key
/var/lib/pgsql/16/data/root.crt
```

**PostgreSQL Configuration:**

Edit `/var/lib/pgsql/16/data/postgresql.conf`:

```bash
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'
ssl_min_protocol_version = 'TLSv1.2'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
```

### Certificate Summary Table

| Certificate | CN | SAN (Critical) | Key Size | Validity | Deployment Location |
|-------------|-----|----------------|----------|----------|---------------------|
| **Root CA** | BindPlane Internal CA | - | 4096 | 10 years | All servers: `/ssl/root.crt` |
| **Management Server** | bindplane.example.com | DNS: bindplane.example.com<br>IP: 10.10.0.17 | 4096 | 2 years | `/etc/bindplane/ssl/server.crt` |
| **Gateway (Shared)** | gateway.example.com | **IP: 10.10.0.10 (NLB)**<br>IP: 10.10.0.11, .12, .18<br>DNS: *.gateway.example.com | 4096 | 2 years | `/opt/observiq-otel-collector/ssl/server.crt` (all 3 gateways) |
| **Collector Client** | collector-01.example.com | DNS: collector-01.example.com<br>IP: 10.20.0.3 | 2048 | 1 year | `/opt/observiq-otel-collector/ssl/gateway-client.crt` |
| **PostgreSQL** | postgres.example.com | IP: 10.10.0.17 | 2048 | 2 years | `/var/lib/pgsql/16/data/server.crt` |

### Certificate Request Process for Enterprise CA

**Step 1: Generate all CSRs:**

```bash
# On management server
openssl req -new -key bindplane-server.key -out bindplane-server.csr \
  -config bindplane-server.conf

# For gateways (one CSR for shared cert)
openssl req -new -key gateway-nlb.key -out gateway-nlb.csr \
  -config gateway-nlb.conf

# For each collector
openssl req -new -key collector-client.key -out collector-client.csr \
  -config collector-client.conf
```

**Step 2: Submit CSRs to Enterprise CA:**

**Microsoft AD Certificate Services:**

```powershell
# Submit each CSR
certreq -submit -attrib "CertificateTemplate:EnterpriseWebServer" bindplane-server.csr
certreq -submit -attrib "CertificateTemplate:EnterpriseWebServer" gateway-nlb.csr
certreq -submit -attrib "CertificateTemplate:ClientAuthentication" collector-client.csr

# Retrieve certificates
certreq -retrieve <REQUEST_ID> bindplane-server.crt
certreq -retrieve <REQUEST_ID> gateway-nlb.crt
certreq -retrieve <REQUEST_ID> collector-client.crt
```

**Step 3: Verify all certificates:**

```bash
# Verify certificate chain
openssl verify -CAfile ca-bundle.crt bindplane-server.crt
openssl verify -CAfile ca-bundle.crt gateway-nlb.crt

# Verify SAN includes NLB IP (CRITICAL)
openssl x509 -in gateway-nlb.crt -noout -text | grep "10.10.0.10"
# Must show: IP Address:10.10.0.10
```

---

## Active Directory Authentication

### Overview

BindPlane supports LDAP/LDAPS authentication against Active Directory for user management.

**Benefits:**
- Centralized user management
- SSO integration
- Group-based access control
- Audit trail via AD logs

### AD Requirements

**1. Active Directory Server:**

```
AD Domain: example.com
AD Domain Controller: ad.example.com
LDAP Port: 389 (LDAP)
LDAPS Port: 636 (LDAP over SSL - REQUIRED)
```

**2. Service Account:**

Create a dedicated service account for BindPlane:

```
Username: svc-bindplane
Password: <strong password>
Group Membership: Domain Users
Permissions: Read access to Users and Groups OUs
```

**PowerShell commands to create service account:**

```powershell
# Create service account
New-ADUser -Name "svc-bindplane" `
  -SamAccountName "svc-bindplane" `
  -UserPrincipalName "svc-bindplane@example.com" `
  -AccountPassword (ConvertTo-SecureString "STRONG_PASSWORD" -AsPlainText -Force) `
  -Enabled $true `
  -PasswordNeverExpires $true `
  -CannotChangePassword $true `
  -Description "BindPlane LDAP Service Account"

# Grant read permissions
# Note: Default Domain Users group typically has sufficient read access
```

**3. AD Group for BindPlane Administrators:**

```powershell
# Create BindPlane admin group
New-ADGroup -Name "BindPlane-Admins" `
  -SamAccountName "BindPlane-Admins" `
  -GroupCategory Security `
  -GroupScope Global `
  -Description "BindPlane Platform Administrators"

# Add users to group
Add-ADGroupMember -Identity "BindPlane-Admins" -Members "john.doe", "jane.smith"
```

**4. LDAPS Certificate:**

Active Directory must have a valid certificate for LDAPS (port 636).

**Verify LDAPS is enabled:**

```bash
# From BindPlane server, test LDAPS connection
openssl s_client -connect ad.example.com:636 -showcerts

# Expected: Certificate presented, connection successful
```

**If LDAPS is not enabled, request certificate from CA and install on AD server:**

```powershell
# On AD server, request certificate
certreq -new -f ADCertRequest.inf ADCertRequest.req

# ADCertRequest.inf content:
[NewRequest]
Subject = "CN=ad.example.com"
KeySpec = 1
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
SMIME = False
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = PKCS10
KeyUsage = 0xa0

[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.1 ; Server Authentication

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=ad.example.com&"

# Submit to CA and install certificate
```

### BindPlane LDAP Configuration

**Configuration File:** `/etc/bindplane/config.yaml`

```yaml
server:
  # ... other server settings ...

ldap:
  # Enable LDAP authentication
  enabled: true

  # LDAPS endpoint (REQUIRED - use port 636 for SSL)
  url: "ldaps://ad.example.com:636"

  # Bind DN for service account
  bindDN: "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com"

  # Bind password for service account
  bindPassword: "STRONG_PASSWORD"

  # Base DN for user searches
  baseDN: "DC=example,DC=com"

  # User search filter
  # {0} will be replaced with the username entered at login
  userSearchFilter: "(&(objectClass=user)(sAMAccountName={0}))"

  # Attribute that contains the username
  usernameAttribute: "sAMAccountName"

  # Group search settings
  groupSearchBase: "DC=example,DC=com"
  groupSearchFilter: "(&(objectClass=group)(member={0}))"

  # Admin group DN
  # Users in this group will have full admin access
  adminGroupDN: "CN=BindPlane-Admins,OU=Groups,DC=example,DC=com"

  # TLS settings
  tls:
    # Verify AD server certificate
    insecureSkipVerify: false

    # Path to AD CA certificate (if using internal CA)
    caFile: "/etc/bindplane/ssl/ad-ca.crt"

```

### Alternative LDAP Configuration (Environment Variables)

For containerized deployments or security requirements:

```bash
# Set environment variables
export BINDPLANE_LDAP_ENABLED=true
export BINDPLANE_LDAP_URL="ldaps://ad.example.com:636"
export BINDPLANE_LDAP_BIND_DN="CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com"
export BINDPLANE_LDAP_BIND_PASSWORD="STRONG_PASSWORD"
export BINDPLANE_LDAP_BASE_DN="DC=example,DC=com"
export BINDPLANE_LDAP_USER_SEARCH_FILTER="(&(objectClass=user)(sAMAccountName={0}))"
export BINDPLANE_LDAP_USERNAME_ATTRIBUTE="sAMAccountName"
export BINDPLANE_LDAP_ADMIN_GROUP_DN="CN=BindPlane-Admins,OU=Groups,DC=example,DC=com"
```

### Testing LDAP Authentication

**1. Test LDAP bind with service account:**

```bash
# Install ldapsearch (if not already installed)
sudo yum install -y openldap-clients

# Test LDAPS connection and bind
ldapsearch -x -H ldaps://ad.example.com:636 \
  -D "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com" \
  -W \
  -b "DC=example,DC=com" \
  "(sAMAccountName=john.doe)"

# Expected: User entry returned
```

**2. Verify AD CA certificate trust:**

```bash
# Export AD server certificate
openssl s_client -connect ad.example.com:636 -showcerts < /dev/null 2>/dev/null | \
  sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > /tmp/ad-cert.pem

# Verify certificate
openssl x509 -in /tmp/ad-cert.pem -noout -text

# Copy to BindPlane config directory
sudo cp /tmp/ad-cert.pem /etc/bindplane/ssl/ad-ca.crt
sudo chown bindplane:bindplane /etc/bindplane/ssl/ad-ca.crt
sudo chmod 644 /etc/bindplane/ssl/ad-ca.crt
```

**3. Test authentication via BindPlane UI:**

```
1. Navigate to https://bindplane.example.com:3000
2. Enter AD credentials:
   Username: john.doe
   Password: <AD password>
3. Verify successful login
4. Check user appears in BindPlane → Users
```

### LDAP Troubleshooting

**Common Issues:**

**Issue 1: LDAPS connection fails**

```bash
# Error: "SSL: CONNECT_ERROR"

# Solution: Verify LDAPS is enabled on AD
nmap -p 636 ad.example.com

# Solution: Add AD CA certificate
openssl s_client -connect ad.example.com:636 -CAfile /etc/bindplane/ssl/ad-ca.crt
```

**Issue 2: Bind authentication fails**

```bash
# Error: "Invalid credentials"

# Verify service account credentials
ldapwhoami -x -H ldaps://ad.example.com:636 \
  -D "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com" \
  -W

# Check service account is not locked/disabled in AD
```

**Issue 3: User not found**

```bash
# Error: "User not found in directory"

# Verify user search filter and base DN
ldapsearch -x -H ldaps://ad.example.com:636 \
  -D "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com" \
  -W \
  -b "DC=example,DC=com" \
  "(sAMAccountName=john.doe)" \
  sAMAccountName

# Adjust baseDN or userSearchFilter in config.yaml if needed
```

**Issue 4: Admin access not granted**

```bash
# Verify user is member of admin group
ldapsearch -x -H ldaps://ad.example.com:636 \
  -D "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com" \
  -W \
  -b "CN=BindPlane-Admins,OU=Groups,DC=example,DC=com" \
  member

# Expected: User DN should appear in member attribute
```

### LDAP Security Best Practices

**1. Use LDAPS (port 636) only:**

```yaml
# GOOD
url: "ldaps://ad.example.com:636"

# BAD - unencrypted
url: "ldap://ad.example.com:389"
```

**2. Least privilege for service account:**

- Read-only access to Users and Groups OUs
- No unnecessary group memberships
- Strong password (20+ characters)
- Password never expires (prevent lockouts)

**3. Certificate validation:**

```yaml
tls:
  insecureSkipVerify: false  # Always verify certificates
  caFile: "/etc/bindplane/ssl/ad-ca.crt"
```

**4. Rotate service account password regularly:**

```powershell
# Every 90 days
Set-ADAccountPassword -Identity "svc-bindplane" -Reset -NewPassword (ConvertTo-SecureString "NEW_PASSWORD" -AsPlainText -Force)
```

**5. Monitor authentication logs:**

```bash
# BindPlane logs
sudo journalctl -u bindplane -f | grep "ldap\|authentication"

# AD logs (on domain controller)
# Event IDs: 4624 (successful logon), 4625 (failed logon)
```

---

## Pre-Installation Checklist

Use this checklist to ensure all requirements are met before deployment.

### Infrastructure Readiness

- [ ] **RHEL 9 servers provisioned** (1 management + 3 gateways + 3+ collectors)
- [ ] **Network connectivity verified** between all components
- [ ] **Static IP addresses assigned** to all servers
- [ ] **DNS resolution configured** (or /etc/hosts entries)
- [ ] **NTP synchronized** across all servers (`chronyc tracking`)
- [ ] **Disk space verified:**
  - Management: 100 GB available
  - Gateways/Collectors: 1 TB available
- [ ] **Memory requirements met:**
  - Management: 8 GB RAM minimum
  - Gateways/Collectors: 16 GB RAM minimum

### Network Requirements

- [ ] **Network Load Balancer configured:**
  - VIP: 10.10.0.10
  - Port: 4317 (TCP)
  - Health checks: TCP to backends on 4317
  - Session persistence: Source IP (5 min)
- [ ] **Firewall rules implemented** (see Firewall Rules Matrix)
- [ ] **Outbound internet access** (if not fully offline)
- [ ] **DNS servers accessible**
- [ ] **NTP servers accessible**

### Software Packages

- [ ] **All packages downloaded** and checksums verified
- [ ] **Package transfer to on-premises completed**
- [ ] **SHA256SUMS verified** after transfer
- [ ] **Installation scripts prepared**
- [ ] **Backup media created**

### System Configuration

- [ ] **SELinux policy reviewed** (enforcing mode with custom policy)
- [ ] **Firewalld enabled** and rules configured
- [ ] **File descriptor limits configured** (55,000)
- [ ] **Kernel parameters tuned** (`/etc/sysctl.d/99-bindplane.conf`)
- [ ] **Antivirus exclusions applied**
- [ ] **Service users created:** `bdot`, `bindplane`, `postgres`
- [ ] **Log rotation configured**
- [ ] **Audit logging enabled** (AIDE, auditd)

### Certificate Requirements

- [ ] **Root CA certificate generated** or obtained from Enterprise CA
- [ ] **Management server certificate generated:**
  - SAN includes: bindplane.example.com, 10.10.0.17
- [ ] **Gateway shared certificate generated:**
  - **SAN includes NLB IP: 10.10.0.10** ⚠️ CRITICAL
  - SAN includes gateway IPs: 10.10.0.11, 10.10.0.12, 10.10.0.18
- [ ] **Collector client certificates generated** (one per collector or shared)
- [ ] **PostgreSQL certificate generated** (if using TLS)
- [ ] **All certificates signed by CA**
- [ ] **Certificate chains validated** (`openssl verify`)
- [ ] **Certificates deployed to servers**
- [ ] **File permissions set correctly:**
  - Certificates: 644
  - Private keys: 600

### Active Directory Integration

- [ ] **AD server accessible** (port 636 LDAPS)
- [ ] **Service account created:** `svc-bindplane`
- [ ] **Admin group created:** `BindPlane-Admins`
- [ ] **LDAPS certificate verified** on AD server
- [ ] **AD CA certificate exported** and deployed to management server
- [ ] **LDAP bind tested** with service account
- [ ] **User search tested** with ldapsearch

### PostgreSQL Database

- [ ] **PostgreSQL 16 packages available**
- [ ] **PostgreSQL initialization planned**
- [ ] **Database credentials prepared** (strong password)
- [ ] **PostgreSQL TLS configuration** (if required)
- [ ] **Backup strategy defined**
- [ ] **pg_hba.conf** access rules defined

### Documentation

- [ ] **Network diagram created**
- [ ] **IP address allocation documented**
- [ ] **Certificate inventory spreadsheet created**
- [ ] **Service account credentials securely stored**
- [ ] **Installation runbook prepared**
- [ ] **Rollback procedure documented**

### Security & Compliance

- [ ] **FIPS mode requirements reviewed** (if applicable)
- [ ] **CIS Benchmark checklist completed**
- [ ] **DISA STIG compliance verified** (if applicable)
- [ ] **Change management approval obtained**
- [ ] **Security team approval for certificates**
- [ ] **Firewall change requests approved**

---

## Post-Installation Validation

After installation, perform these validation steps:

### 1. Service Health Checks

**Management Server:**

```bash
# BindPlane service status
sudo systemctl status bindplane

# PostgreSQL service status
sudo systemctl status postgresql-16

# Check listening ports
sudo ss -tlnp | grep -E '3001|3000|5432'

# Expected:
# 0.0.0.0:3001 (OpAMP)
# 0.0.0.0:3000 (UI)
# 127.0.0.1:5432 (PostgreSQL)
```

**Gateway Instances (all 3):**

```bash
# Collector service status
sudo systemctl status observiq-otel-collector

# Check listening port
sudo ss -tlnp | grep 4317

# Expected:
# 0.0.0.0:4317 (OTLP gRPC)
```

**Collector Instances (all):**

```bash
# Collector service status
sudo systemctl status observiq-otel-collector

# Check OpAMP connection
sudo journalctl -u observiq-otel-collector | grep "Successfully connected"

# Expected:
# "Successfully connected to OpAMP server"
```

### 2. TLS Certificate Validation

**Management Server:**

```bash
# Test OpAMP/WSS endpoint from collector
openssl s_client -connect 10.10.0.17:3001 \
  -servername bindplane.example.com \
  -CAfile /opt/observiq-otel-collector/ssl/root.crt

# Expected: Verify return code: 0 (ok)
```

**Gateway Cluster via NLB:**

```bash
# Test OTLP endpoint from collector
openssl s_client -connect 10.10.0.10:4317 \
  -CAfile /opt/observiq-otel-collector/ssl/root.crt

# CRITICAL: Verify certificate includes NLB IP
# Expected output should show:
# "Verify return code: 0 (ok)"
# Subject Alternative Name includes "IP Address:10.10.0.10"
```

### 3. NLB Health Checks

```bash
# HAProxy stats
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | grep bindplane_gateway_backend

# Expected: All 3 backends show "UP" status

# Check backend distribution
for gw in 10.10.0.11 10.10.0.12 10.10.0.18; do
  echo "Gateway $gw:"
  ssh admin@$gw "sudo netstat -an | grep :4317 | grep ESTABLISHED | wc -l"
done

# Expected: Connections distributed across all 3 gateways
```

### 4. Authentication Validation

**LDAP/AD Authentication:**

```bash
# Test LDAP bind
ldapwhoami -x -H ldaps://ad.example.com:636 \
  -D "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com" \
  -W

# Expected: User DN returned

# Test via UI
# 1. Navigate to https://bindplane.example.com:3000
# 2. Login with AD credentials
# 3. Verify successful authentication
```

### 5. Data Flow Validation

**End-to-End Test:**

```bash
# 1. Verify collector consuming from Kafka
ssh collector-01 "sudo journalctl -u observiq-otel-collector -n 100 | grep kafka"

# 2. Verify collector forwarding to gateway via NLB
ssh collector-01 "sudo netstat -an | grep 10.10.0.10:4317"

# 3. Verify gateway receiving data
ssh gateway-01 "sudo journalctl -u observiq-otel-collector -n 100 | grep otlp"

# 4. Check BindPlane UI for agent status
# Navigate to Agents → verify all agents connected
```

### 6. Performance Baseline

```bash
# Resource utilization on management server
top -b -n 1 | grep -E 'bindplane|postgres'
free -h
df -h

# Gateway resource utilization
ssh gateway-01 "top -b -n 1 | grep observiq-otel-collector"

# Collector resource utilization
ssh collector-01 "top -b -n 1 | grep observiq-otel-collector"
```

---

## Contact and Support

**For questions or issues during implementation:**

- **Documentation:** See /docs/ directory for detailed guides
- **Certificate Issues:** Refer to `enterprise-ca-certificate-requirements.md`
- **NLB Configuration:** Refer to `load-balanced-gateway-architecture.md`
- **Complete TLS Guide:** Refer to `complete-tls-configuration-guide.md`

---

**Document End**

---

## Appendix A: Quick Command Reference

### Certificate Generation Commands

```bash
# Generate Root CA
openssl genrsa -out bindplane-ca.key 4096
openssl req -new -x509 -days 3650 -key bindplane-ca.key -out bindplane-ca.crt

# Generate Server Certificate (with CSR)
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr -config server.conf
openssl x509 -req -in server.csr -CA bindplane-ca.crt -CAkey bindplane-ca.key \
  -CAcreateserial -out server.crt -days 730 -sha256 \
  -extfile server.conf -extensions v3_req

# Verify Certificate
openssl x509 -in server.crt -noout -text
openssl verify -CAfile bindplane-ca.crt server.crt
```

### Service Management Commands

```bash
# Management Server
sudo systemctl enable bindplane postgresql-16
sudo systemctl start bindplane postgresql-16
sudo systemctl status bindplane postgresql-16

# Gateway/Collector
sudo systemctl enable observiq-otel-collector
sudo systemctl start observiq-otel-collector
sudo systemctl status observiq-otel-collector

# Restart all services
sudo systemctl restart bindplane
sudo systemctl restart observiq-otel-collector
```

### Troubleshooting Commands

```bash
# Check service logs
sudo journalctl -u bindplane -f
sudo journalctl -u observiq-otel-collector -f
sudo journalctl -u postgresql-16 -f

# Check listening ports
sudo ss -tlnp | grep -E '3001|3000|4317|5432'

# Test connectivity
curl -k https://10.10.0.17:3000
nc -zv 10.10.0.10 4317
nc -zv ad.example.com 636

# Check certificate expiry
openssl x509 -in /etc/bindplane/ssl/server.crt -noout -dates
```

---

## Appendix B: Detailed Package Inventory

### Management Server Package List

| Package Name | Version | Size | Download URL | SHA256 Checksum |
|-------------|---------|------|--------------|-----------------|
| bindplane-ee_v1.96.7-linux_amd64.rpm | 1.96.7 | 50 MB | Google Cloud Storage | See SHA256SUMS |
| postgresql16-server | 16.x | 6 MB | PostgreSQL Yum Repo | See SHA256SUMS |
| postgresql16 | 16.x | 2 MB | PostgreSQL Yum Repo | See SHA256SUMS |
| postgresql16-libs | 16.x | 400 KB | PostgreSQL Yum Repo | See SHA256SUMS |
| postgresql16-contrib | 16.x | 700 KB | PostgreSQL Yum Repo | See SHA256SUMS |
| pgdg-redhat-repo | latest | 10 KB | PostgreSQL Official | See SHA256SUMS |

### Gateway/Collector Package List

| Package Name | Version | Size | Download URL | SHA256 Checksum |
|-------------|---------|------|--------------|-----------------|
| observiq-otel-collector | 1.89.0 | 350 MB | GitHub Releases | See SHA256SUMS |

### Dependencies

| Package Name | Version | Size | Required By |
|-------------|---------|------|-------------|
| libicu | Latest for RHEL 9 | 10 MB | PostgreSQL 16 |
| lz4 | Latest for RHEL 9 | 100 KB | PostgreSQL 16 |
| openssl | 3.x | 1.2 MB | All components |
| openssl-libs | 3.x | 2.5 MB | All components |
| ca-certificates | Latest | 400 KB | All components |

### Download Script

```bash
#!/bin/bash
# download-packages.sh - Download all BindPlane packages

set -euo pipefail

DOWNLOAD_DIR="/tmp/bindplane-packages"
BINDPLANE_VERSION="1.96.7"
COLLECTOR_VERSION="1.89.0"

echo "Creating download directories..."
mkdir -p $DOWNLOAD_DIR/{management,collector,common}

cd $DOWNLOAD_DIR

# BindPlane Management Server (Enterprise Edition)
echo "Downloading BindPlane EE Server v${BINDPLANE_VERSION}..."
cd management
wget "https://storage.googleapis.com/bindplane-op-releases/bindplane/${BINDPLANE_VERSION}/bindplane-ee_linux_amd64.rpm" -O "bindplane-ee_v${BINDPLANE_VERSION}-linux_amd64.rpm"

# PostgreSQL
echo "Downloading PostgreSQL 16..."
wget "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

# ObservIQ Collector
echo "Downloading ObservIQ Collector..."
cd ../collector
wget "https://github.com/observIQ/bindplane-otel-collector/releases/download/v${COLLECTOR_VERSION}/observiq-otel-collector-v${COLLECTOR_VERSION}-linux-amd64.tar.gz"

# Generate checksums
echo "Generating checksums..."
cd $DOWNLOAD_DIR
find . -type f -exec sha256sum {} \; > SHA256SUMS

echo "Download complete!"
echo "Packages located in: $DOWNLOAD_DIR"
echo "Checksum file: $DOWNLOAD_DIR/SHA256SUMS"
```

---

## Appendix C: BindPlane Configuration Examples

### Management Server Configuration

**File:** `/etc/bindplane/config.yaml`

```yaml
# BindPlane OP Server Configuration

# Server settings
server:
  # Bind address for web UI and API
  host: "0.0.0.0"

  # HTTPS port for web UI
  port: 3000

  # TLS configuration
  tls:
    # Enable TLS for web UI
    enabled: true
    certificate: "/etc/bindplane/ssl/server.crt"
    privateKey: "/etc/bindplane/ssl/server.key"
    # Minimum TLS version
    minVersion: "1.2"
    # Cipher suites (FIPS-compatible)
    cipherSuites:
      - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
      - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
      - "TLS_AES_256_GCM_SHA384"
      - "TLS_AES_128_GCM_SHA256"

# OpAMP server settings
opamp:
  # Bind address for OpAMP/WSS
  host: "0.0.0.0"

  # OpAMP port
  port: 3001

  # TLS configuration for OpAMP
  tls:
    enabled: true
    certificate: "/etc/bindplane/ssl/server.crt"
    privateKey: "/etc/bindplane/ssl/server.key"
    # Client certificate verification (optional mTLS)
    clientAuth: "VerifyClientCertIfGiven"
    clientCAs: "/etc/bindplane/ssl/ca.crt"

# Database configuration
database:
  # Database type
  type: "postgres"

  # PostgreSQL connection
  postgres:
    host: "127.0.0.1"
    port: 5432
    database: "bindplane"
    username: "bindplane"
    password: "CHANGE_ME"

    # SSL mode for PostgreSQL connection
    sslMode: "require"

    # Maximum connections
    maxConnections: 50

    # Connection pool settings
    maxIdleConnections: 10
    connectionMaxLifetime: "1h"

# LDAP/AD authentication
ldap:
  enabled: true
  url: "ldaps://ad.example.com:636"
  bindDN: "CN=svc-bindplane,OU=Service Accounts,DC=example,DC=com"
  bindPassword: "STRONG_PASSWORD"
  baseDN: "DC=example,DC=com"
  userSearchFilter: "(&(objectClass=user)(sAMAccountName={0}))"
  usernameAttribute: "sAMAccountName"
  groupSearchBase: "DC=example,DC=com"
  groupSearchFilter: "(&(objectClass=group)(member={0}))"
  adminGroupDN: "CN=BindPlane-Admins,OU=Groups,DC=example,DC=com"

  # TLS settings
  tls:
    insecureSkipVerify: false
    caFile: "/etc/bindplane/ssl/ad-ca.crt"

# Session configuration
sessions:
  # Session secret (generate with: openssl rand -base64 32)
  secret: "CHANGE_ME_RANDOM_SECRET"

  # Session timeout
  maxAge: "24h"

  # Secure cookies (HTTPS only)
  secure: true

# Logging configuration
logging:
  # Log level: debug, info, warn, error
  level: "info"

  # Log format: json, text
  format: "json"

  # Log output: stdout, file
  output: "file"

  # Log file path
  filePath: "/var/log/bindplane/server.log"

  # Log rotation
  maxSize: 100  # MB
  maxBackups: 10
  maxAge: 30  # days

# Telemetry (optional - for BindPlane internal metrics)
telemetry:
  enabled: false
  # Metrics endpoint
  metricsPort: 9090

# Feature flags
features:
  # Enable resource management
  resources: true

  # Enable agent labels
  labels: true

  # Enable configurations
  configurations: true
```

### Gateway Configuration (via BindPlane UI)

**Configuration Name:** `GW` (Gateway)

**Applied to:** Gateway instances (bindplane-gateway-vm-1, vm-2, vm-3)

**Sources:**

```yaml
# Source: BindPlane Gateway (OTLP Receiver)
name: "Bindplane Gateway"
type: "bindplane_gateway"

parameters:
  # Listen on all interfaces
  host: "0.0.0.0"

  # OTLP gRPC port
  grpc_port: 4317

  # OTLP HTTP port (optional)
  http_port: 4318

  # TLS configuration
  enable_tls: true
  tls_cert_file: "/opt/observiq-otel-collector/ssl/server.crt"
  tls_key_file: "/opt/observiq-otel-collector/ssl/server.key"

  # mTLS configuration (if enabled)
  enable_mtls: true
  tls_ca_file: "/opt/observiq-otel-collector/ssl/root.crt"

  # Maximum message size (MB)
  max_recv_msg_size_mib: 20

  # gRPC keepalive settings
  enable_grpc_keepalive: true
  grpc_keepalive_time: 60
  grpc_keepalive_timeout: 10
  grpc_keepalive_max_connection_idle: 60
  grpc_keepalive_max_connection_age: 60
  grpc_keepalive_max_connection_age_grace: 10
```

**Destinations:**

```yaml
# Destination: Forward to SecOps SIEM
name: "secops-siem"
type: "otlphttp"  # or "otlp" for gRPC

parameters:
  endpoint: "https://siem.example.com:4318"  # SecOps endpoint

  # TLS configuration
  enable_tls: true
  tls_ca_file: "/opt/observiq-otel-collector/ssl/secops-ca.crt"

  # Optional: Client certificate for mTLS
  enable_mtls: false
  # tls_cert_file: "/opt/observiq-otel-collector/ssl/gateway-client.crt"
  # tls_key_file: "/opt/observiq-otel-collector/ssl/gateway-client.key"

  # Retry configuration
  retry_enabled: true
  retry_initial_interval: "5s"
  retry_max_interval: "30s"
  retry_max_elapsed_time: "300s"

  # Queue configuration
  sending_queue_enabled: true
  sending_queue_size: 1000

  # Timeout
  timeout: "30s"
```

### Collector Configuration (via BindPlane UI)

**Configuration Name:** `kafka-collector`

**Applied to:** Collector instances (kafka-collector-vm, kafka-collector-vm-temp)

**Sources:**

```yaml
# Source: Kafka Consumer
name: "kafka-windows-logs"
type: "kafka"

parameters:
  # Kafka brokers
  brokers:
    - "10.10.0.13:9094"  # Kafka broker with SSL

  # Topic to consume
  topic: "windows-logs"

  # Consumer group
  group_id: "bindplane-collectors"

  # Authentication
  authentication: "sasl_ssl"

  # SASL mechanism
  sasl_mechanism: "PLAIN"
  sasl_username: "bindplane-consumer"
  sasl_password: "KAFKA_PASSWORD"

  # TLS configuration
  enable_tls: true
  tls_ca_file: "/opt/observiq-otel-collector/ssl/kafka-ca.crt"

  # mTLS (if Kafka requires client certificate)
  enable_mtls: true
  tls_cert_file: "/opt/observiq-otel-collector/ssl/client-cert.pem"
  tls_key_file: "/opt/observiq-otel-collector/ssl/client-key.pem"

  # Disable TLS verification (NOT recommended for production)
  insecure_skip_verify: false

  # Initial offset
  initial_offset: "latest"

  # Message parsing
  encoding: "json"
```

**Destinations:**

```yaml
# Destination: Forward to Gateway Cluster via NLB
name: "gw"
type: "bindplane_gateway"

parameters:
  # CRITICAL: Use NLB VIP, not individual gateway IPs
  endpoint: "https://10.10.0.10:4317"

  # TLS configuration
  enable_tls: true
  tls_ca_file: "/opt/observiq-otel-collector/ssl/root.crt"

  # Disable TLS verification (NOT recommended)
  insecure_skip_verify: false

  # mTLS configuration
  enable_mtls: true
  tls_cert_file: "/opt/observiq-otel-collector/ssl/gateway-client.crt"
  tls_key_file: "/opt/observiq-otel-collector/ssl/gateway-client.key"

  # Retry configuration
  retry_enabled: true
  retry_initial_interval: "5s"
  retry_max_interval: "30s"
  retry_max_elapsed_time: "300s"

  # Queue configuration
  sending_queue_enabled: true
  sending_queue_size: 5000

  # Timeout
  timeout: "30s"

  # Compression
  compression: "gzip"
```

### Manager Configuration (OpAMP Connection)

**File:** `/opt/observiq-otel-collector/manager.yaml`

```yaml
# OpAMP client configuration

# Management server endpoint
endpoint: "wss://10.10.0.17:3001/v1/opamp"

# Agent ID (unique per collector/gateway)
# Leave empty for auto-generation on first run
agent_id: ""

# Agent labels (for targeting configurations)
labels:
  environment: "production"
  role: "collector"  # or "gateway"
  location: "datacenter-1"
  zone: "asia-south1-a"

# TLS configuration
tls:
  # Enable TLS
  insecure_skip_verify: false

  # CA certificate for management server
  ca_file: "/opt/observiq-otel-collector/ssl/root.crt"

  # Optional: Client certificate for mTLS
  # cert_file: "/opt/observiq-otel-collector/ssl/client.crt"
  # key_file: "/opt/observiq-otel-collector/ssl/client.key"

# Secret key for configuration encryption (optional)
# Generate with: openssl rand -base64 32
secret_key: ""

# Collector binary path
collector_binary: "/opt/observiq-otel-collector/observiq-otel-collector"

# Storage directory for configurations
storage_directory: "/opt/observiq-otel-collector/storage"

# Logging
log_level: "info"
```

---

## Appendix D: Systemd Service Files

### BindPlane Management Server Service

**File:** `/etc/systemd/system/bindplane.service`

```ini
[Unit]
Description=BindPlane OP Management Server
Documentation=https://github.com/observIQ/bindplane-op
After=network.target postgresql-16.service
Requires=postgresql-16.service

[Service]
Type=simple
User=bindplane
Group=bindplane
WorkingDirectory=/var/lib/bindplane

# Environment variables
Environment="BINDPLANE_CONFIG_FILE=/etc/bindplane/config.yaml"
Environment="BINDPLANE_REMOTE_URL=https://10.10.0.17:3000"

# Start command
ExecStart=/opt/bindplane/bindplane serve --config /etc/bindplane/config.yaml

# Restart policy
Restart=on-failure
RestartSec=10s

# Resource limits
LimitNOFILE=55000
LimitNPROC=4096

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/bindplane /var/log/bindplane

# Capabilities
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
```

### PostgreSQL 16 Service Override

**File:** `/etc/systemd/system/postgresql-16.service.d/override.conf`

```ini
[Service]
# Increase file descriptor limit
LimitNOFILE=55000

# Memory limits (adjust based on available RAM)
MemoryLimit=4G

# Restart policy
Restart=on-failure
RestartSec=10s
```

### Gateway/Collector Service (Enhanced)

**File:** `/etc/systemd/system/observiq-otel-collector.service`

```ini
[Unit]
Description=observIQ OpenTelemetry Collector (%H)
Documentation=https://github.com/observIQ/observiq-otel-collector
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=bdot
Group=bdot
WorkingDirectory=/opt/observiq-otel-collector

# Start command (OpAMP managed mode)
ExecStart=/opt/observiq-otel-collector/observiq-otel-collector \
  --manager /opt/observiq-otel-collector/manager.yaml

# Restart policy
Restart=on-failure
RestartSec=5s
StartLimitBurst=3
StartLimitInterval=60s

# Resource limits
LimitNOFILE=55000
LimitNPROC=4096

# Memory limit (adjust based on collector workload)
MemoryMax=2G
MemoryHigh=1.8G

# CPU limit (optional)
# CPUQuota=200%

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/observiq-otel-collector

# Prevent privilege escalation
SecureBits=noroot-locked

# System call filtering (optional - may need adjustment)
# SystemCallFilter=@system-service
# SystemCallFilter=~@privileged @resources

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30s

# Environment variables
Environment="GODEBUG=madvdontneed=1"
Environment="GOMEMLIMIT=1800MiB"

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=observiq-otel-collector

[Install]
WantedBy=multi-user.target
```

---

## Appendix E: Firewall Configuration Scripts

### Management Server Firewall Setup

**File:** `setup-firewall-management.sh`

```bash
#!/bin/bash
# Firewall configuration for BindPlane Management Server
# Run with sudo

set -euo pipefail

echo "Configuring firewall for BindPlane Management Server..."

# Enable firewalld
systemctl enable firewalld
systemctl start firewalld

# Allow OpAMP/WSS (port 3001)
firewall-cmd --permanent --add-port=3001/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.0.0/24" port port="3001" protocol="tcp" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.0.0/24" port port="3001" protocol="tcp" accept'

# Allow BindPlane UI (port 3000)
firewall-cmd --permanent --add-port=3000/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="3000" protocol="tcp" accept'

# Allow SSH (port 22)
firewall-cmd --permanent --add-service=ssh

# PostgreSQL (localhost only - already restricted by pg_hba.conf)
# No firewall rule needed for localhost connections

# Reload firewall
firewall-cmd --reload

# Verify rules
echo "Firewall rules applied:"
firewall-cmd --list-all

echo "Management server firewall configuration complete!"
```

### Gateway Firewall Setup

**File:** `setup-firewall-gateway.sh`

```bash
#!/bin/bash
# Firewall configuration for BindPlane Gateway instances
# Run with sudo on each gateway

set -euo pipefail

echo "Configuring firewall for BindPlane Gateway..."

# Enable firewalld
systemctl enable firewalld
systemctl start firewalld

# Allow OTLP gRPC (port 4317)
firewall-cmd --permanent --add-port=4317/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.0.0/24" port port="4317" protocol="tcp" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.0.10/32" port port="4317" protocol="tcp" accept'

# Allow OTLP HTTP (port 4318) - optional
firewall-cmd --permanent --add-port=4318/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.0.0/24" port port="4318" protocol="tcp" accept'

# Allow SSH (port 22)
firewall-cmd --permanent --add-service=ssh

# Block all other inbound traffic (default deny)
firewall-cmd --permanent --set-default-zone=drop
firewall-cmd --permanent --zone=drop --add-interface=eth0

# Allow established connections
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Reload firewall
firewall-cmd --reload

# Verify rules
echo "Firewall rules applied:"
firewall-cmd --list-all

echo "Gateway firewall configuration complete!"
```

### Collector Firewall Setup

**File:** `setup-firewall-collector.sh`

```bash
#!/bin/bash
# Firewall configuration for BindPlane Collector instances
# Run with sudo on each collector

set -euo pipefail

echo "Configuring firewall for BindPlane Collector..."

# Enable firewalld
systemctl enable firewalld
systemctl start firewalld

# Collectors primarily make outbound connections
# Allow SSH (port 22)
firewall-cmd --permanent --add-service=ssh

# Block all other inbound traffic (default deny)
firewall-cmd --permanent --set-default-zone=drop
firewall-cmd --permanent --zone=drop --add-interface=eth0

# Allow established connections
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outbound to management server (OpAMP)
firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -d 10.10.0.17 -p tcp --dport 3001 -j ACCEPT

# Allow outbound to NLB/Gateway (OTLP)
firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -d 10.10.0.10 -p tcp --dport 4317 -j ACCEPT

# Allow outbound to Kafka brokers
firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -d 10.10.0.13 -p tcp --dport 9094 -j ACCEPT

# Allow DNS (port 53)
firewall-cmd --permanent --add-service=dns

# Allow NTP (port 123)
firewall-cmd --permanent --add-service=ntp

# Reload firewall
firewall-cmd --reload

# Verify rules
echo "Firewall rules applied:"
firewall-cmd --list-all

echo "Collector firewall configuration complete!"
```

---

## Appendix F: Certificate Generation Automation

### Complete Certificate Generation Script

**File:** `generate-all-certificates.sh`

```bash
#!/bin/bash
# Complete certificate generation script for BindPlane deployment
# Run on a secure system with OpenSSL installed

set -euo pipefail

# Configuration
CERT_DIR="./bindplane-certificates"
CA_DIR="$CERT_DIR/ca"
MGMT_DIR="$CERT_DIR/management"
GATEWAY_DIR="$CERT_DIR/gateway"
COLLECTOR_DIR="$CERT_DIR/collectors"

# Certificate details
COUNTRY="US"
STATE="California"
CITY="San Francisco"
ORG="Your Company"
CA_CN="BindPlane Internal CA"
MGMT_CN="bindplane.example.com"
GATEWAY_CN="gateway.example.com"

# IP addresses
MGMT_IP="10.10.0.17"
NLB_IP="10.10.0.10"
GATEWAY_IPS=("10.10.0.11" "10.10.0.12" "10.10.0.18")
COLLECTOR_IPS=("10.20.0.3" "10.20.0.5")

# Validity periods (days)
CA_VALIDITY=3650    # 10 years
SERVER_VALIDITY=730 # 2 years
CLIENT_VALIDITY=365 # 1 year

echo "=== BindPlane Certificate Generation Script ==="
echo "Creating directory structure..."

# Create directories
mkdir -p "$CA_DIR" "$MGMT_DIR" "$GATEWAY_DIR" "$COLLECTOR_DIR"

#############################################
# Step 1: Generate Root CA
#############################################

echo ""
echo "Step 1: Generating Root CA..."

# Generate CA private key
openssl genrsa -out "$CA_DIR/ca.key" 4096

# Generate CA certificate
openssl req -new -x509 -days $CA_VALIDITY \
  -key "$CA_DIR/ca.key" \
  -out "$CA_DIR/ca.crt" \
  -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=IT Security/CN=$CA_CN"

echo "✓ Root CA certificate generated: $CA_DIR/ca.crt"

# Verify CA
openssl x509 -in "$CA_DIR/ca.crt" -noout -text | grep -E "Subject:|Issuer:|Not"

#############################################
# Step 2: Generate Management Server Certificate
#############################################

echo ""
echo "Step 2: Generating Management Server Certificate..."

# Create OpenSSL config
cat > "$MGMT_DIR/openssl.conf" <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = IT Operations
CN = $MGMT_CN

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE

[alt_names]
DNS.1 = $MGMT_CN
DNS.2 = bindplane-mgmt-server-temp.internal.example.com
DNS.3 = bindplane.internal
IP.1 = $MGMT_IP
EOF

# Generate private key
openssl genrsa -out "$MGMT_DIR/server.key" 4096

# Generate CSR
openssl req -new \
  -key "$MGMT_DIR/server.key" \
  -out "$MGMT_DIR/server.csr" \
  -config "$MGMT_DIR/openssl.conf"

# Sign certificate
openssl x509 -req -in "$MGMT_DIR/server.csr" \
  -CA "$CA_DIR/ca.crt" \
  -CAkey "$CA_DIR/ca.key" \
  -CAcreateserial \
  -out "$MGMT_DIR/server.crt" \
  -days $SERVER_VALIDITY \
  -sha256 \
  -extfile "$MGMT_DIR/openssl.conf" \
  -extensions v3_req

echo "✓ Management server certificate generated: $MGMT_DIR/server.crt"

# Verify
openssl verify -CAfile "$CA_DIR/ca.crt" "$MGMT_DIR/server.crt"

#############################################
# Step 3: Generate Gateway Shared Certificate (NLB)
#############################################

echo ""
echo "Step 3: Generating Gateway Shared Certificate (with NLB IP)..."

# Create OpenSSL config with all gateway IPs and NLB IP
cat > "$GATEWAY_DIR/openssl.conf" <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = Observability Platform
CN = $GATEWAY_CN

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE

[alt_names]
# NLB VIP - CRITICAL
IP.1 = $NLB_IP

# Gateway instances
IP.2 = ${GATEWAY_IPS[0]}
IP.3 = ${GATEWAY_IPS[1]}
IP.4 = ${GATEWAY_IPS[2]}

# DNS names
DNS.1 = $GATEWAY_CN
DNS.2 = gateway-nlb.example.com
DNS.3 = gateway-vm-1.example.com
DNS.4 = gateway-vm-2.example.com
DNS.5 = gateway-vm-3.example.com
DNS.6 = *.gateway.example.com
EOF

# Generate private key
openssl genrsa -out "$GATEWAY_DIR/server.key" 4096

# Generate CSR
openssl req -new \
  -key "$GATEWAY_DIR/server.key" \
  -out "$GATEWAY_DIR/server.csr" \
  -config "$GATEWAY_DIR/openssl.conf"

# Sign certificate
openssl x509 -req -in "$GATEWAY_DIR/server.csr" \
  -CA "$CA_DIR/ca.crt" \
  -CAkey "$CA_DIR/ca.key" \
  -CAcreateserial \
  -out "$GATEWAY_DIR/server.crt" \
  -days $SERVER_VALIDITY \
  -sha256 \
  -extfile "$GATEWAY_DIR/openssl.conf" \
  -extensions v3_req

echo "✓ Gateway shared certificate generated: $GATEWAY_DIR/server.crt"

# Verify NLB IP is in SAN
echo "Verifying NLB IP ($NLB_IP) is in certificate SAN..."
if openssl x509 -in "$GATEWAY_DIR/server.crt" -noout -text | grep "$NLB_IP"; then
  echo "✓ NLB IP verified in certificate SAN"
else
  echo "✗ ERROR: NLB IP not found in certificate SAN!"
  exit 1
fi

# Verify certificate
openssl verify -CAfile "$CA_DIR/ca.crt" "$GATEWAY_DIR/server.crt"

#############################################
# Step 4: Generate Collector Client Certificates
#############################################

echo ""
echo "Step 4: Generating Collector Client Certificates..."

for i in "${!COLLECTOR_IPS[@]}"; do
  COLLECTOR_NUM=$((i + 1))
  COLLECTOR_IP="${COLLECTOR_IPS[$i]}"
  COLLECTOR_CERT_DIR="$COLLECTOR_DIR/collector-$COLLECTOR_NUM"

  mkdir -p "$COLLECTOR_CERT_DIR"

  echo "Generating certificate for collector-$COLLECTOR_NUM ($COLLECTOR_IP)..."

  # Create OpenSSL config
  cat > "$COLLECTOR_CERT_DIR/openssl.conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = Collectors
CN = collector-$COLLECTOR_NUM.example.com

[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
basicConstraints = critical, CA:FALSE

[alt_names]
DNS.1 = collector-$COLLECTOR_NUM.example.com
DNS.2 = kafka-collector-vm-$COLLECTOR_NUM.internal.example.com
IP.1 = $COLLECTOR_IP
EOF

  # Generate private key
  openssl genrsa -out "$COLLECTOR_CERT_DIR/client.key" 2048

  # Generate CSR
  openssl req -new \
    -key "$COLLECTOR_CERT_DIR/client.key" \
    -out "$COLLECTOR_CERT_DIR/client.csr" \
    -config "$COLLECTOR_CERT_DIR/openssl.conf"

  # Sign certificate
  openssl x509 -req -in "$COLLECTOR_CERT_DIR/client.csr" \
    -CA "$CA_DIR/ca.crt" \
    -CAkey "$CA_DIR/ca.key" \
    -CAcreateserial \
    -out "$COLLECTOR_CERT_DIR/client.crt" \
    -days $CLIENT_VALIDITY \
    -sha256 \
    -extfile "$COLLECTOR_CERT_DIR/openssl.conf" \
    -extensions v3_req

  # Verify
  openssl verify -CAfile "$CA_DIR/ca.crt" "$COLLECTOR_CERT_DIR/client.crt"

  echo "✓ Collector $COLLECTOR_NUM certificate generated"
done

#############################################
# Step 5: Create Deployment Packages
#############################################

echo ""
echo "Step 5: Creating deployment packages..."

# Copy CA certificate to all directories
cp "$CA_DIR/ca.crt" "$MGMT_DIR/root.crt"
cp "$CA_DIR/ca.crt" "$GATEWAY_DIR/root.crt"

for i in "${!COLLECTOR_IPS[@]}"; do
  COLLECTOR_NUM=$((i + 1))
  cp "$CA_DIR/ca.crt" "$COLLECTOR_DIR/collector-$COLLECTOR_NUM/root.crt"
done

# Create README files
cat > "$CERT_DIR/README.txt" <<EOF
BindPlane Certificate Package
==============================

This package contains all certificates for the BindPlane deployment.

Directory Structure:
- ca/           : Root CA certificate and private key
- management/   : Management server certificates
- gateway/      : Gateway shared certificate (for all 3 gateways)
- collectors/   : Individual collector client certificates

Deployment Instructions:
1. See pre-implementation-requirements.md for full deployment guide
2. Deploy certificates with correct permissions:
   - Certificates (.crt): 644
   - Private keys (.key): 600

CRITICAL:
- Gateway certificate MUST include NLB IP ($NLB_IP) in SAN
- All 3 gateways use the SAME certificate (gateway/server.crt)
- Collectors connect to NLB IP ($NLB_IP), not individual gateway IPs

Generated: $(date)
EOF

# Set proper permissions
chmod 600 "$CA_DIR/ca.key"
chmod 644 "$CA_DIR/ca.crt"
chmod 600 "$MGMT_DIR/server.key"
chmod 644 "$MGMT_DIR/server.crt"
chmod 600 "$GATEWAY_DIR/server.key"
chmod 644 "$GATEWAY_DIR/server.crt"

for i in "${!COLLECTOR_IPS[@]}"; do
  COLLECTOR_NUM=$((i + 1))
  chmod 600 "$COLLECTOR_DIR/collector-$COLLECTOR_NUM/client.key"
  chmod 644 "$COLLECTOR_DIR/collector-$COLLECTOR_NUM/client.crt"
done

#############################################
# Step 6: Generate Certificate Inventory
#############################################

echo ""
echo "Step 6: Generating certificate inventory..."

cat > "$CERT_DIR/certificate-inventory.txt" <<EOF
BindPlane Certificate Inventory
================================

Root CA:
  File: ca/ca.crt
  Subject: $CA_CN
  Validity: $CA_VALIDITY days ($(date -d "+$CA_VALIDITY days" +%Y-%m-%d))
  Key Size: 4096 bits

Management Server:
  Certificate: management/server.crt
  Private Key: management/server.key
  Subject: $MGMT_CN
  SAN: $MGMT_CN, $MGMT_IP
  Validity: $SERVER_VALIDITY days
  Key Size: 4096 bits
  Deployment: /etc/bindplane/ssl/

Gateway Shared Certificate:
  Certificate: gateway/server.crt
  Private Key: gateway/server.key
  Subject: $GATEWAY_CN
  SAN: $NLB_IP (NLB), ${GATEWAY_IPS[*]}, *.gateway.example.com
  Validity: $SERVER_VALIDITY days
  Key Size: 4096 bits
  Deployment: /opt/observiq-otel-collector/ssl/ (ALL 3 gateways)
  CRITICAL: Includes NLB IP $NLB_IP in SAN

Collector Client Certificates:
EOF

for i in "${!COLLECTOR_IPS[@]}"; do
  COLLECTOR_NUM=$((i + 1))
  COLLECTOR_IP="${COLLECTOR_IPS[$i]}"
  cat >> "$CERT_DIR/certificate-inventory.txt" <<EOF
  Collector $COLLECTOR_NUM:
    Certificate: collectors/collector-$COLLECTOR_NUM/client.crt
    Private Key: collectors/collector-$COLLECTOR_NUM/client.key
    Subject: collector-$COLLECTOR_NUM.example.com
    SAN: collector-$COLLECTOR_NUM.example.com, $COLLECTOR_IP
    Validity: $CLIENT_VALIDITY days
    Key Size: 2048 bits
    Deployment: /opt/observiq-otel-collector/ssl/gateway-client.crt
EOF
done

#############################################
# Step 7: Create Archive
#############################################

echo ""
echo "Step 7: Creating deployment archive..."

ARCHIVE_NAME="bindplane-certificates-$(date +%Y%m%d-%H%M%S).tar.gz"

tar -czf "$ARCHIVE_NAME" -C "$CERT_DIR" .

echo ""
echo "=== Certificate Generation Complete ==="
echo ""
echo "Certificates generated in: $CERT_DIR"
echo "Archive created: $ARCHIVE_NAME"
echo ""
echo "Next steps:"
echo "1. Securely transfer $ARCHIVE_NAME to on-premises environment"
echo "2. Extract and deploy certificates to respective servers"
echo "3. Verify NLB IP ($NLB_IP) is in gateway certificate SAN"
echo "4. Set correct file permissions (644 for certs, 600 for keys)"
echo ""
echo "See $CERT_DIR/README.txt for deployment instructions"
```

---

## Appendix G: Deployment Runbook

### Phase 1: Infrastructure Preparation (Day 1)

**Duration:** 4-6 hours

**Tasks:**

1. **Provision all RHEL 9 servers** (1-2 hours)
   - 1 Management server
   - 3 Gateway instances
   - 3 Collector instances

2. **Configure network** (1 hour)
   - Assign static IP addresses
   - Configure DNS or /etc/hosts
   - Verify connectivity between servers

3. **Install base packages** (1 hour)
   ```bash
   # On all servers
   sudo yum update -y
   sudo yum install -y net-tools bind-utils lsof htop jq
   ```

4. **Configure NTP** (30 minutes)
   ```bash
   # On all servers
   sudo timedatectl set-timezone America/Los_Angeles
   sudo chronyc sources
   ```

5. **Apply system hardening** (1-2 hours)
   - Configure SELinux
   - Set file descriptor limits
   - Configure firewalld rules
   - Apply kernel parameters

**Validation:**
```bash
# Verify connectivity
ping -c 3 10.10.0.17  # Management
ping -c 3 10.10.0.10  # NLB VIP
ping -c 3 ad.example.com  # Active Directory

# Verify time sync
chronyc tracking

# Verify firewall
firewall-cmd --list-all
```

---

### Phase 2: Certificate Generation (Day 1)

**Duration:** 2-3 hours

**Tasks:**

1. **Run certificate generation script** (30 minutes)
   ```bash
   ./generate-all-certificates.sh
   ```

2. **Verify all certificates** (30 minutes)
   ```bash
   # Verify NLB IP in gateway certificate
   openssl x509 -in gateway/server.crt -noout -text | grep "10.10.0.10"

   # Verify all certificate chains
   for cert in */server.crt */client.crt; do
     openssl verify -CAfile ca/ca.crt "$cert"
   done
   ```

3. **Transfer certificates to servers** (1 hour)
   ```bash
   # Extract archive on each server
   scp bindplane-certificates-*.tar.gz admin@10.10.0.17:/tmp/
   ```

4. **Deploy certificates** (1 hour)
   - Management: `/etc/bindplane/ssl/`
   - Gateways (all 3): `/opt/observiq-otel-collector/ssl/`
   - Collectors: `/opt/observiq-otel-collector/ssl/`

**Validation:**
```bash
# On each server, verify files and permissions
ls -la /etc/bindplane/ssl/
ls -la /opt/observiq-otel-collector/ssl/

# Verify certificate details
openssl x509 -in /etc/bindplane/ssl/server.crt -noout -subject -issuer -dates
```

---

### Phase 3: Network Load Balancer Setup (Day 2)

**Duration:** 2-4 hours

**Tasks:**

1. **Install NLB software** (HAProxy example) (30 minutes)
   ```bash
   sudo yum install -y haproxy
   ```

2. **Configure NLB** (1 hour)
   - Apply HAProxy configuration (see Appendix C)
   - Configure VIP (10.10.0.10)
   - Add backend servers (3 gateways)

3. **Configure health checks** (30 minutes)
   - TCP check on port 4317
   - Interval: 10 seconds
   - Threshold: 3 failures

4. **Start NLB service** (15 minutes)
   ```bash
   sudo systemctl enable haproxy
   sudo systemctl start haproxy
   ```

**Validation:**
```bash
# Verify NLB listening
sudo ss -tlnp | grep 10.10.0.10:4317

# Check backend health
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | grep bindplane_gateway_backend

# Test connectivity
nc -zv 10.10.0.10 4317
```

---

### Phase 4: BindPlane Management Server Installation (Day 2)

**Duration:** 3-4 hours

**Tasks:**

1. **Install PostgreSQL 16** (1 hour)
   ```bash
   cd /opt/bindplane-packages/management
   sudo rpm -ivh pgdg-redhat-repo-latest.noarch.rpm
   sudo dnf -qy module disable postgresql
   sudo dnf install -y postgresql16-server
   sudo /usr/pgsql-16/bin/postgresql-16-setup initdb
   sudo systemctl enable postgresql-16
   sudo systemctl start postgresql-16
   ```

2. **Configure PostgreSQL database** (30 minutes)

   **Official BindPlane PostgreSQL configuration:**

   Reference: https://docs.bindplane.com/deployment/virtual-machine/bindplane/postgresql/postgres-configuration

   ```bash
   sudo -u postgres psql
   ```

   ```sql
   CREATE USER "bindplane" WITH PASSWORD 'STRONG_PASSWORD';
   CREATE DATABASE "bindplane" ENCODING 'UTF8' TEMPLATE template0;
   GRANT CREATE ON DATABASE "bindplane" TO "bindplane";
   \c "bindplane";
   GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "bindplane";
   GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "bindplane";
   GRANT ALL PRIVILEGES ON SCHEMA public TO "bindplane";
   \q
   ```

3. **Install BindPlane EE Server** (30 minutes)
   ```bash
   cd /opt/bindplane-packages/management
   sudo rpm -ivh bindplane-ee_v1.96.7-linux_amd64.rpm
   ```

4. **Configure BindPlane** (1 hour)
   - Edit `/etc/bindplane/config.yaml`
   - Configure database connection
   - Configure TLS certificates
   - Configure LDAP/AD authentication

5. **Start BindPlane service** (30 minutes)
   ```bash
   sudo systemctl enable bindplane
   sudo systemctl start bindplane
   ```

**Validation:**
```bash
# Check service status
sudo systemctl status bindplane postgresql-16

# Check listening ports
sudo ss -tlnp | grep -E '3000|3001|5432'

# Test UI access
curl -k https://10.10.0.17:3000

# Test OpAMP endpoint
openssl s_client -connect 10.10.0.17:3001 -CAfile /etc/bindplane/ssl/ca.crt
```

---

### Phase 5: Gateway Installation (Day 3)

**Duration:** 2-3 hours (for all 3 gateways)

**Tasks:**

1. **Install collector on all gateways** (1 hour)
   ```bash
   # On each gateway
   cd /opt/bindplane-packages/collector
   tar -xzf observiq-otel-collector-*.tar.gz
   sudo mkdir -p /opt/observiq-otel-collector
   sudo cp observiq-otel-collector /opt/observiq-otel-collector/
   sudo cp -r plugins /opt/observiq-otel-collector/
   sudo useradd -r -s /bin/false bdot
   sudo chown -R bdot:bdot /opt/observiq-otel-collector
   ```

2. **Deploy certificates** (30 minutes)
   ```bash
   # Deploy SAME certificate to all 3 gateways
   scp gateway/server.crt gateway-vm-1:/opt/observiq-otel-collector/ssl/
   scp gateway/server.key gateway-vm-1:/opt/observiq-otel-collector/ssl/
   scp gateway/root.crt gateway-vm-1:/opt/observiq-otel-collector/ssl/
   # Repeat for gateway-vm-2 and gateway-vm-3
   ```

3. **Configure manager.yaml** (30 minutes)
   ```yaml
   endpoint: "wss://10.10.0.17:3001/v1/opamp"
   labels:
     role: "gateway"
   ```

4. **Create systemd service** (15 minutes)
   - Use service file from Appendix D

5. **Start gateway services** (15 minutes)
   ```bash
   sudo systemctl enable observiq-otel-collector
   sudo systemctl start observiq-otel-collector
   ```

**Validation:**
```bash
# On each gateway
sudo systemctl status observiq-otel-collector
sudo ss -tlnp | grep 4317
sudo journalctl -u observiq-otel-collector | grep "Successfully connected"

# Verify NLB health checks
echo "show servers state" | sudo socat stdio /run/haproxy/admin.sock
```

---

**END OF DOCUMENT**

