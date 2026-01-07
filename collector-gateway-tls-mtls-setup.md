# Collector to Gateway TLS/mTLS Setup Guide

This guide provides step-by-step instructions for configuring TLS and mTLS between ObservIQ collectors and BindPlane gateways for secure data forwarding.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Understanding the Flow](#understanding-the-flow)
- [Part 1: Gateway Certificate Setup](#part-1-gateway-certificate-setup)
- [Part 2: Collector Certificate Setup (mTLS)](#part-2-collector-certificate-setup-mtls)
- [Part 3: BindPlane UI Configuration](#part-3-bindplane-ui-configuration)
- [Part 4: Verification](#part-4-verification)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

---

## Overview

This guide covers configuring secure communication between collectors and BindPlane gateways using the **BindPlane Gateway** destination in BindPlane configurations.

### What Is a BindPlane Gateway?

A BindPlane gateway is an ObservIQ OpenTelemetry Collector configured to receive telemetry data from other collectors and forward it to final destinations (like backends, SIEM systems, or other gateways).

**Use Cases:**
- **Centralized Processing**: Aggregate logs from multiple collectors for centralized processing
- **Network Segmentation**: Collectors in restricted networks send data to a gateway in a DMZ
- **Load Balancing**: Distribute data processing across multiple gateway instances
- **Data Enrichment**: Apply processors at the gateway level before forwarding to backends

### Deployment Scenarios Covered

1. **TLS (Server Authentication)**: Gateway authenticates itself to collectors
2. **mTLS (Mutual Authentication)**: Both gateway and collectors authenticate each other

---

## Prerequisites

### Required Access

- Root or sudo access on gateway VM
- Root or sudo access on collector VMs
- Access to BindPlane UI
- `gcloud` CLI configured (for GCP deployments)

### Software Requirements

- ObservIQ OpenTelemetry Collector v1.88.1 or later (on both collectors and gateways)
- BindPlane v1.96.7 or later
- OpenSSL 1.1.1 or later

### Network Requirements

- Gateway accessible from collectors (typically port 4317 for OTLP/gRPC)
- BindPlane management server accessible from both collectors and gateways
- DNS or host file entries configured (optional but recommended)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              BindPlane Management Server                    │
│                   (10.10.0.17:3001)                         │
│                                                             │
│  • Manages all collector/gateway configurations            │
│  • Pushes destination settings via OpAMP                   │
│  • Provides UI for TLS/mTLS configuration                  │
│  • Certificate Authority (CA) for the infrastructure       │
│                                                             │
│  Certificate Storage: /etc/bindplane/ssl/                  │
│  • root.crt (BindPlane CA certificate - public)            │
│  • root.key (BindPlane CA private key - secret)            │
│  • server.crt (BindPlane server certificate)               │
│  • server.key (BindPlane server private key)               │
│  • client.crt (Gateway client certificate template)        │
│  • client.key (Gateway client private key template)        │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ WSS/TLS 1.3 (OpAMP)
            ┌───────────────┴──────────────┐
            │                              │
            ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│   Collector VM          │    │   Gateway VM            │
│   (10.20.0.5)           │    │   (10.10.0.18)          │
│                         │    │                         │
│  ObservIQ Collector     │    │  ObservIQ Collector     │
│  • Collects logs        │    │  (configured as         │
│  • Processes locally    │    │   gateway)              │
│  • Forwards to gateway  │────│                         │
│    via OTLP/gRPC        │TLS │  • Receives from        │
│    with TLS/mTLS        │mTLS│    collectors           │
│                         │4317│  • Aggregates data      │
│  Certificates:          │    │  • Forwards to backends │
│  /opt/observiq-otel-    │    │                         │
│   collector/ssl/        │    │  Certificates:          │
│  • root.crt (CA)        │    │  /opt/observiq-otel-    │
│  • collector-client.crt │    │   collector/ssl/        │
│    (for mTLS)           │    │  • root.crt (CA)        │
│  • collector-client.key │    │  • client.crt (server)  │
│    (for mTLS)           │    │  • client.key (server)  │
└─────────────────────────┘    └─────────────────────────┘
```

### Data Flow

1. **Management Plane (WSS/TLS 1.3)**:
   - Collectors ←→ BindPlane Management Server (port 3001)
   - Gateways ←→ BindPlane Management Server (port 3001)
   - Protocol: OpAMP over WebSocket Secure

2. **Data Plane (OTLP/gRPC with TLS/mTLS)**:
   - Collectors → Gateway (port 4317)
   - Protocol: OpenTelemetry Protocol over gRPC

---

## Understanding the Flow

### TLS Configuration (Server Authentication)

**Gateway acts as TLS server:**
1. Gateway presents its server certificate to connecting collectors
2. Collectors verify the gateway certificate using the CA certificate
3. Encrypted channel established (one-way authentication)

**Required Certificates:**
- **On Gateway**: Server certificate + private key + CA certificate
- **On Collector**: CA certificate only

### mTLS Configuration (Mutual Authentication)

**Both gateway and collectors authenticate:**
1. Gateway presents its server certificate to collectors
2. Collectors verify gateway certificate using CA
3. Collectors present their client certificates to gateway
4. Gateway verifies client certificates using CA
5. Encrypted channel established (two-way authentication)

**Required Certificates:**
- **On Gateway**: Server certificate + private key + CA certificate
- **On Collector**: Client certificate + private key + CA certificate

---

## Part 1: Gateway Certificate Setup

The gateway needs a server certificate to accept TLS connections from collectors.

### Step 1.1: Verify Gateway Certificates

First, check if certificates already exist from the WSS OpAMP implementation:

```bash
# SSH to gateway VM
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a

# Check for existing certificates
sudo ls -la /opt/observiq-otel-collector/ssl/
```

**Expected output:**
```
-rw-r--r--. 1 bdot bdot 1566 Dec 28 06:49 client.crt
-rw-------. 1 bdot bdot 1704 Dec 28 06:49 client.key
-rw-r--r--. 1 bdot bdot 1903 Dec 28 06:40 root.crt
```

**If certificates exist**, verify they are valid:

```bash
# Verify certificate details
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/client.crt \
  -noout -subject -issuer -dates

# Expected output:
# subject=CN=bindplane-collector-client, O=BindPlane, OU=Collectors
# issuer=CN=BindPlane CA, O=BindPlane, C=US
# notBefore=Dec 28 06:47:17 2025 GMT
# notAfter=Dec 28 06:47:17 2026 GMT
```

✅ **If certificates exist and are valid**, skip to [Step 1.3](#step-13-configure-gateway-as-otlp-receiver).

### Step 1.2: Generate Gateway Certificates (If Missing)

If certificates don't exist, generate them using the BindPlane CA:

```bash
# On BindPlane management server
gcloud compute ssh bindplane-mgmt-server-temp --zone asia-south1-a

cd /etc/bindplane/ssl

# Generate gateway server private key
sudo openssl genrsa -out gateway-server.key 2048

# Generate certificate signing request (CSR)
# Replace bindplane-gateway-vm-temp with your gateway hostname
# Replace 10.10.0.18 with your gateway IP
sudo openssl req -new \
  -key gateway-server.key \
  -out gateway-server.csr \
  -subj '/CN=bindplane-gateway-vm-temp/O=BindPlane/OU=Gateways' \
  -addext 'subjectAltName=DNS:bindplane-gateway-vm-temp,DNS:localhost,IP:10.10.0.18,IP:127.0.0.1'

# Sign with BindPlane CA (valid for 1 year)
sudo openssl x509 -req \
  -in gateway-server.csr \
  -CA root.crt \
  -CAkey root.key \
  -CAcreateserial \
  -out gateway-server.crt \
  -days 365 \
  -sha256 \
  -copy_extensions copy

# Verify certificate
sudo openssl x509 -in gateway-server.crt -noout -text | grep -A1 "Subject Alternative Name"
```

**Copy certificates to gateway VM:**

```bash
# On BindPlane management server, prepare for transfer
sudo cp gateway-server.crt gateway-server.key /tmp/
sudo chmod 644 /tmp/gateway-server.crt /tmp/gateway-server.key

# On your local machine or Cloud Shell
gcloud compute scp bindplane-mgmt-server-temp:/tmp/gateway-server.crt /tmp/gateway-server.crt --zone asia-south1-a
gcloud compute scp bindplane-mgmt-server-temp:/tmp/gateway-server.key /tmp/gateway-server.key --zone asia-south1-a
gcloud compute scp bindplane-mgmt-server-temp:/etc/bindplane/ssl/root.crt /tmp/bindplane-ca.crt --zone asia-south1-a

# Copy to gateway VM
gcloud compute scp /tmp/gateway-server.crt bindplane-gateway-vm-temp:/tmp/gateway-server.crt --zone asia-south1-a
gcloud compute scp /tmp/gateway-server.key bindplane-gateway-vm-temp:/tmp/gateway-server.key --zone asia-south1-a
gcloud compute scp /tmp/bindplane-ca.crt bindplane-gateway-vm-temp:/tmp/bindplane-ca.crt --zone asia-south1-a

# On gateway VM, move to SSL directory
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a --command \
  "sudo mkdir -p /opt/observiq-otel-collector/ssl && \
   sudo mv /tmp/gateway-server.crt /opt/observiq-otel-collector/ssl/client.crt && \
   sudo mv /tmp/gateway-server.key /opt/observiq-otel-collector/ssl/client.key && \
   sudo mv /tmp/bindplane-ca.crt /opt/observiq-otel-collector/ssl/root.crt && \
   sudo chown -R bdot:bdot /opt/observiq-otel-collector/ssl/ && \
   sudo chmod 644 /opt/observiq-otel-collector/ssl/client.crt && \
   sudo chmod 600 /opt/observiq-otel-collector/ssl/client.key && \
   sudo chmod 644 /opt/observiq-otel-collector/ssl/root.crt"
```

### Step 1.3: Configure Gateway as OTLP Receiver

The gateway needs to be configured to accept OTLP data from collectors. This is done via BindPlane UI:

**In BindPlane UI:**

1. Navigate to **Configurations** → Find or create the gateway configuration
2. Click **Add Destination** → Select **BindPlane Gateway** (or edit existing)
3. Configure as a **receiver** (not exporter):
   - The gateway receives data from collectors
   - The gateway then forwards to actual destinations (backends)

**Note:** The gateway's OTLP receiver is configured in the gateway's pipeline, not as a destination. The "BindPlane Gateway" destination is used on **collectors** to send data to the gateway.

---

## Part 2: Collector Certificate Setup (mTLS)

For mTLS, collectors need client certificates to authenticate to the gateway.

### Step 2.1: Check Collector CA Certificate

Collectors need the CA certificate to verify the gateway's server certificate:

```bash
# SSH to collector VM
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a

# Check if CA certificate exists
sudo ls -la /opt/observiq-otel-collector/ssl/root.crt
```

**If CA certificate exists:**
```bash
# Verify it's the correct BindPlane CA
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/root.crt \
  -noout -subject -issuer

# Expected: CN=BindPlane CA, O=BindPlane, C=US
```

**If CA certificate is missing:**

```bash
# Copy from BindPlane management server
gcloud compute scp bindplane-mgmt-server-temp:/etc/bindplane/ssl/root.crt \
  /tmp/bindplane-ca.crt --zone asia-south1-a

gcloud compute scp /tmp/bindplane-ca.crt kafka-collector-vm-temp:/tmp/bindplane-ca.crt \
  --zone asia-south1-a

gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "sudo mv /tmp/bindplane-ca.crt /opt/observiq-otel-collector/ssl/root.crt && \
   sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/root.crt && \
   sudo chmod 644 /opt/observiq-otel-collector/ssl/root.crt"
```

✅ **For TLS only (no mTLS), you're done with collector setup!** Skip to [Part 3](#part-3-bindplane-ui-configuration).

### Step 2.2: Generate Collector Client Certificates (mTLS Only)

For mTLS, each collector needs a unique client certificate.

**On BindPlane management server:**

```bash
gcloud compute ssh bindplane-mgmt-server-temp --zone asia-south1-a

cd /etc/bindplane/ssl

# Generate collector client private key
# Replace "kafka-collector-vm-temp" with your collector hostname
sudo openssl genrsa -out collector-kafka-client.key 2048

# Generate certificate signing request (CSR)
sudo openssl req -new \
  -key collector-kafka-client.key \
  -out collector-kafka-client.csr \
  -subj '/CN=kafka-collector-vm-temp/O=BindPlane/OU=Collectors'

# Sign with BindPlane CA (valid for 1 year)
sudo openssl x509 -req \
  -in collector-kafka-client.csr \
  -CA root.crt \
  -CAkey root.key \
  -CAcreateserial \
  -out collector-kafka-client.crt \
  -days 365 \
  -sha256

# Verify certificate
sudo openssl x509 -in collector-kafka-client.crt -noout -subject -issuer -dates
```

**Expected output:**
```
subject=CN=kafka-collector-vm-temp, O=BindPlane, OU=Collectors
issuer=CN=BindPlane CA, O=BindPlane, C=US
notBefore=Dec 28 10:XX:XX 2025 GMT
notAfter=Dec 28 10:XX:XX 2026 GMT
```

### Step 2.3: Copy Client Certificates to Collector (mTLS Only)

```bash
# On BindPlane management server, prepare for transfer
sudo cp collector-kafka-client.crt collector-kafka-client.key /tmp/
sudo chmod 644 /tmp/collector-kafka-client.crt /tmp/collector-kafka-client.key

# On your local machine or Cloud Shell
gcloud compute scp bindplane-mgmt-server-temp:/tmp/collector-kafka-client.crt \
  /tmp/collector-client.crt --zone asia-south1-a
gcloud compute scp bindplane-mgmt-server-temp:/tmp/collector-kafka-client.key \
  /tmp/collector-client.key --zone asia-south1-a

# Copy to collector VM
gcloud compute scp /tmp/collector-client.crt kafka-collector-vm-temp:/tmp/collector-client.crt \
  --zone asia-south1-a
gcloud compute scp /tmp/collector-client.key kafka-collector-vm-temp:/tmp/collector-client.key \
  --zone asia-south1-a

# On collector VM, move to SSL directory
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "sudo mv /tmp/collector-client.crt /opt/observiq-otel-collector/ssl/gateway-client.crt && \
   sudo mv /tmp/collector-client.key /opt/observiq-otel-collector/ssl/gateway-client.key && \
   sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/gateway-client.* && \
   sudo chmod 644 /opt/observiq-otel-collector/ssl/gateway-client.crt && \
   sudo chmod 600 /opt/observiq-otel-collector/ssl/gateway-client.key"
```

### Step 2.4: Verify Collector Certificates

```bash
# List all certificates on collector
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "ls -la /opt/observiq-otel-collector/ssl/"
```

**Expected output (TLS only):**
```
-rw-r--r--. 1 bdot bdot 1216 Dec 28 10:28 client-cert.pem          # Kafka client cert
-rw-------. 1 bdot bdot 1704 Dec 28 10:28 client-key.pem           # Kafka client key
-rw-r--r--. 1 bdot bdot 1188 Dec 28 10:18 kafka-ca.crt            # Kafka CA
-rw-r--r--. 1 bdot bdot 1903 Dec 28 07:18 root.crt                # BindPlane CA
```

**Expected output (mTLS):**
```
-rw-r--r--. 1 bdot bdot 1216 Dec 28 10:28 client-cert.pem          # Kafka client cert
-rw-------. 1 bdot bdot 1704 Dec 28 10:28 client-key.pem           # Kafka client key
-rw-r--r--. 1 bdot bdot 1566 Dec 28 10:XX gateway-client.crt       # Gateway client cert
-rw-------. 1 bdot bdot 1704 Dec 28 10:XX gateway-client.key       # Gateway client key
-rw-r--r--. 1 bdot bdot 1188 Dec 28 10:18 kafka-ca.crt            # Kafka CA
-rw-r--r--. 1 bdot bdot 1903 Dec 28 07:18 root.crt                # BindPlane CA
```

---

## Part 3: BindPlane UI Configuration

Configure the BindPlane Gateway destination in the collector's configuration.

### Step 3.1: Access BindPlane UI

1. Open browser: `http://YOUR_BINDPLANE_IP:3001`
2. Log in with your credentials
3. Navigate to **Configurations**

### Step 3.2: Configure BindPlane Gateway Destination (TLS)

For **TLS (server authentication only)**:

1. Click on your collector configuration (e.g., "collector")
2. In the **Destinations** section, click **Add Destination** or **Edit** existing gateway destination
3. Select **BindPlane Gateway** (gw) as the destination type

**Configuration Settings:**

```yaml
Destination Name: gw
Destination Type: BindPlane Gateway

# Basic Settings
# (Headers section - leave empty unless you need custom headers)
Name: (empty)
Value: (empty)

Compression: gzip
Timeout: 30

# Load Balancing
☐ Enable gRPC Load Balancing

# TLS Configuration
☑ Enable TLS

☐ Skip TLS Certificate Verification

TLS Certificate Authority File:
/opt/observiq-otel-collector/ssl/root.crt

Server Name Override: (empty or bindplane-gateway-vm-temp)

# Mutual TLS
☐ Mutual TLS

TLS Client Certificate File: (leave empty)

TLS Client Private Key File: (leave empty)

# Other Settings
☑ Drop Raw Copy
☑ Enable Batching
```

4. In the **Endpoint** section, add your gateway:
   - Click **Add Endpoint**
   - Enter: `https://10.10.0.18:4317` (replace with your gateway IP)
   - Or: `https://bindplane-gateway-vm-temp:4317` (if DNS configured)

5. Click **Save**

### Step 3.3: Configure BindPlane Gateway Destination (mTLS)

For **mTLS (mutual authentication)**:

1. Follow the same steps as TLS configuration above
2. **Enable Mutual TLS:**

```yaml
# TLS Configuration
☑ Enable TLS

☐ Skip TLS Certificate Verification

TLS Certificate Authority File:
/opt/observiq-otel-collector/ssl/root.crt

Server Name Override: (empty or bindplane-gateway-vm-temp)

# Mutual TLS
☑ Mutual TLS

TLS Client Certificate File:
/opt/observiq-otel-collector/ssl/gateway-client.crt

TLS Client Private Key File:
/opt/observiq-otel-collector/ssl/gateway-client.key
```

3. Click **Save**

### Step 3.4: Configure Gateway Source (Receiver Side)

For mTLS, the gateway must be configured to **require** client certificates when receiving data from collectors.

**In BindPlane UI:**

1. Navigate to the **gateway's configuration** (e.g., "GW" or "gateway-config")
2. In the **Sources** section, find or add **BindPlane Gateway** source
3. Click **Edit Source: Bindplane Gateway**

#### Gateway Source Configuration (TLS Only)

**For TLS (server authentication only):**

```yaml
Source Name: Bindplane Gateway
Source Type: BindPlane Gateway

# Basic Settings
Host: 0.0.0.0
gRPC Port: 4317
HTTP Port: 4318

# Advanced Section (expand)
Maximum Message Size: 20

☑ Enable TLS

Server Certificate File:
/opt/observiq-otel-collector/ssl/client.crt

Server Private Key:
/opt/observiq-otel-collector/ssl/client.key

☐ Mutual TLS  # Leave unchecked for TLS only

TLS Certificate Authority File:
(leave empty for TLS only)

# GRPC Timeout
☑ Enable GRPC Timeout
Max Idle Time: 60
Max Connection Age: 60
Max Connection Age Grace: 10
```

#### Gateway Source Configuration (mTLS)

**For mTLS (mutual authentication):**

```yaml
Source Name: Bindplane Gateway
Source Type: BindPlane Gateway

# Basic Settings
Host: 0.0.0.0
gRPC Port: 4317
HTTP Port: 4318

# Advanced Section (expand)
Maximum Message Size: 20

☑ Enable TLS

Server Certificate File:
/opt/observiq-otel-collector/ssl/client.crt

Server Private Key:
/opt/observiq-otel-collector/ssl/client.key

☑ Mutual TLS  # CHECK THIS for mTLS

TLS Certificate Authority File:
/opt/observiq-otel-collector/ssl/root.crt

# GRPC Timeout
☑ Enable GRPC Timeout
Max Idle Time: 60
Max Connection Age: 60
Max Connection Age Grace: 10
```

**Gateway Certificate Details:**

| File | Path | Purpose |
|------|------|---------|
| Server Cert | `/opt/observiq-otel-collector/ssl/client.crt` | Gateway's server certificate |
| Server Key | `/opt/observiq-otel-collector/ssl/client.key` | Gateway's server private key |
| CA Cert | `/opt/observiq-otel-collector/ssl/root.crt` | BindPlane CA (for verifying collector clients in mTLS) |

**Certificate Validation:**

```bash
# Verify gateway certificates exist
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a --command \
  "ls -la /opt/observiq-otel-collector/ssl/"

# Expected output:
# -rw-r--r--. 1 bdot bdot 1566 Dec 28 06:49 client.crt
# -rw-------. 1 bdot bdot 1704 Dec 28 06:49 client.key
# -rw-r--r--. 1 bdot bdot 1903 Dec 28 06:40 root.crt

# Verify server certificate details
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a --command \
  "sudo openssl x509 -in /opt/observiq-otel-collector/ssl/client.crt -noout -subject -issuer -dates"

# Expected output:
# subject=CN=bindplane-collector-client, O=BindPlane, OU=Collectors
# issuer=CN=BindPlane CA, O=BindPlane, C=US
# notBefore=Dec 28 06:47:17 2025 GMT
# notAfter=Dec 28 06:47:17 2026 GMT
```

**After saving the gateway source configuration**, the gateway's OTLP receiver will be configured with TLS/mTLS settings:

```bash
# SSH to gateway
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a

# Check gateway config for OTLP receiver TLS settings
sudo cat /opt/observiq-otel-collector/config.yaml | grep -A30 'receivers:' | grep -A20 'otlp:'

# Expected for TLS only:
# receivers:
#   otlp:
#     protocols:
#       grpc:
#         endpoint: 0.0.0.0:4317
#         tls:
#           cert_file: /opt/observiq-otel-collector/ssl/client.crt
#           key_file: /opt/observiq-otel-collector/ssl/client.key

# Expected for mTLS:
# receivers:
#   otlp:
#     protocols:
#       grpc:
#         endpoint: 0.0.0.0:4317
#         tls:
#           cert_file: /opt/observiq-otel-collector/ssl/client.crt
#           key_file: /opt/observiq-otel-collector/ssl/client.key
#           client_ca_file: /opt/observiq-otel-collector/ssl/root.crt
#           client_auth_type: RequireAndVerifyClientCert
```

### Step 3.5: Assign Configuration to Collector

1. Navigate to **Agents** in BindPlane UI
2. Find your collector (e.g., `kafka-collector-vm-temp`)
3. Click **Configure** or **Assign Configuration**
4. Select the configuration with the gateway destination
5. Click **Apply**

The collector will pull the new configuration via OpAMP and restart automatically.

---

## Part 4: Verification

### Step 4.1: Verify Collector Configuration

Wait 1-2 minutes for the collector to pull the configuration:

```bash
# Check collector is running
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "sudo systemctl status observiq-otel-collector --no-pager"

# View collector configuration (managed by BindPlane)
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "sudo cat /opt/observiq-otel-collector/config.yaml | grep -A30 'otlp/gw'"
```

**Expected configuration (TLS only):**
```yaml
exporters:
  otlp/gw:
    compression: gzip
    endpoint: https://10.10.0.18:4317
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 1000
    timeout: 30s
    tls:
      ca_file: /opt/observiq-otel-collector/ssl/root.crt
      insecure: false
      insecure_skip_verify: false
```

**Expected configuration (mTLS):**
```yaml
exporters:
  otlp/gw:
    compression: gzip
    endpoint: https://10.10.0.18:4317
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 1000
    timeout: 30s
    tls:
      ca_file: /opt/observiq-otel-collector/ssl/root.crt
      cert_file: /opt/observiq-otel-collector/ssl/gateway-client.crt
      key_file: /opt/observiq-otel-collector/ssl/gateway-client.key
      insecure: false
      insecure_skip_verify: false
```

### Step 4.2: Monitor Collector Logs

```bash
# Watch collector logs in real-time
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "sudo journalctl -u observiq-otel-collector -f"

# Look for successful connection messages (no TLS errors)
# Press Ctrl+C to exit
```

**Successful messages:**
- No `tls` errors
- No `certificate` errors
- No `connection refused` errors
- Exporter shows successful sends

**Error patterns (if something is wrong):**
- `tls: bad certificate` - Client certificate issue (mTLS)
- `x509: certificate signed by unknown authority` - CA certificate mismatch
- `connection refused` - Gateway not listening or firewall blocking
- `tls: first record does not look like a TLS handshake` - Protocol mismatch

### Step 4.3: Monitor Gateway Logs

```bash
# Watch gateway logs in real-time
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a --command \
  "sudo journalctl -u observiq-otel-collector -f"

# Look for incoming connections from collectors
# Press Ctrl+C to exit
```

**Successful messages:**
- OTLP receiver accepting connections
- No TLS handshake errors
- Data being processed and forwarded

### Step 4.4: Check Network Connection

```bash
# From collector, check connection to gateway
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "sudo ss -tnp | grep 10.10.0.18:4317"
```

**Expected output:**
```
ESTAB  0  0  10.20.0.5:54321  10.10.0.18:4317  users:(("observiq-otel-co",pid=...,fd=...))
```

### Step 4.5: Test TLS Handshake

```bash
# From collector, test TLS connection to gateway
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "openssl s_client -connect 10.10.0.18:4317 \
   -servername bindplane-gateway-vm-temp \
   -CAfile /opt/observiq-otel-collector/ssl/root.crt"

# Look for "Verify return code: 0 (ok)"
# Press Ctrl+C to exit
```

**For mTLS, test with client certificate:**

```bash
gcloud compute ssh kafka-collector-vm-temp --zone asia-south1-a --command \
  "openssl s_client -connect 10.10.0.18:4317 \
   -servername bindplane-gateway-vm-temp \
   -CAfile /opt/observiq-otel-collector/ssl/root.crt \
   -cert /opt/observiq-otel-collector/ssl/gateway-client.crt \
   -key /opt/observiq-otel-collector/ssl/gateway-client.key"

# Look for "Verify return code: 0 (ok)"
# Press Ctrl+C to exit
```

### Step 4.6: Verify Data Flow

Check that data is flowing from collector → gateway → backend:

**In BindPlane UI:**
1. Navigate to **Agents**
2. Check collector status (should show as connected)
3. Check gateway status (should show as connected)
4. Look for data flow metrics

**On gateway VM:**

```bash
# Check gateway config for pipeline
sudo cat /opt/observiq-otel-collector/config.yaml | grep -A10 'service:'

# Should show:
# service:
#   pipelines:
#     logs:
#       receivers: [otlp]  # Receiving from collectors
#       exporters: [...]    # Forwarding to backends
```

---

## Troubleshooting

### Issue 1: Connection Refused

**Symptoms:**
```
connection refused
dial tcp 10.10.0.18:4317: connect: connection refused
```

**Diagnosis:**
```bash
# Check if gateway is listening on port 4317
gcloud compute ssh bindplane-gateway-vm-temp --zone asia-south1-a --command \
  "sudo ss -tlnp | grep 4317"

# Check firewall rules
gcloud compute firewall-rules list --filter="name~otlp OR name~4317"
```

**Solution:**
1. Verify gateway service is running: `sudo systemctl status observiq-otel-collector`
2. Check gateway configuration has OTLP receiver enabled
3. Ensure firewall allows port 4317 from collector subnet
4. Verify correct gateway IP in collector configuration

### Issue 2: TLS Handshake Error

**Symptoms:**
```
tls: first record does not look like a TLS handshake
```

**Root Cause:** Protocol mismatch (HTTP vs HTTPS, or plain gRPC vs TLS gRPC)

**Solution:**
1. Ensure endpoint uses `https://` prefix: `https://10.10.0.18:4317`
2. Verify "Enable TLS" is checked in BindPlane UI
3. Check gateway OTLP receiver has TLS enabled

### Issue 3: Certificate Signed by Unknown Authority

**Symptoms:**
```
x509: certificate signed by unknown authority
```

**Root Cause:** CA certificate missing or doesn't match gateway's CA

**Diagnosis:**
```bash
# On collector, check CA certificate
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/root.crt -noout -subject

# On gateway, check server certificate issuer
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/client.crt -noout -issuer
```

**Solution:**
1. Ensure collector has the correct BindPlane CA certificate
2. Verify gateway certificate was signed by the same CA
3. Re-copy CA certificate from BindPlane management server

### Issue 4: Bad Certificate (mTLS)

**Symptoms:**
```
tls: bad certificate
remote error: tls: bad certificate
```

**Root Cause:** Client certificate not provided or doesn't match CA

**Diagnosis:**
```bash
# Verify client certificate exists
ls -la /opt/observiq-otel-collector/ssl/gateway-client.crt
ls -la /opt/observiq-otel-collector/ssl/gateway-client.key

# Verify client certificate issuer matches CA
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/gateway-client.crt -noout -issuer
```

**Solution:**
1. Ensure client certificate and key exist on collector
2. Verify file paths in BindPlane configuration
3. Check file permissions (cert: 644, key: 600)
4. Ensure "Mutual TLS" is checked in BindPlane UI
5. Verify gateway requires client certificates

### Issue 5: Certificate Hostname Mismatch

**Symptoms:**
```
x509: certificate is valid for localhost, 127.0.0.1, not 10.10.0.18
```

**Root Cause:** Gateway certificate doesn't include the IP/hostname used by collectors

**Diagnosis:**
```bash
# Check certificate Subject Alternative Names (SANs)
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/client.crt -noout -text | grep -A1 "Subject Alternative Name"
```

**Solution:**
1. Regenerate gateway certificate with correct SANs
2. Use **Server Name Override** in BindPlane UI to match a hostname in the certificate
3. Example: Set "Server Name Override" to `bindplane-gateway-vm-temp` if that's in the certificate

### Issue 6: Permission Denied

**Symptoms:**
```
permission denied
failed to load certificate
```

**Diagnosis:**
```bash
# Check file permissions and ownership
ls -la /opt/observiq-otel-collector/ssl/
```

**Solution:**
```bash
# Fix permissions on collector
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/root.crt
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/gateway-client.crt
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/gateway-client.key

sudo chmod 644 /opt/observiq-otel-collector/ssl/root.crt
sudo chmod 644 /opt/observiq-otel-collector/ssl/gateway-client.crt
sudo chmod 600 /opt/observiq-otel-collector/ssl/gateway-client.key

# Fix permissions on gateway
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/client.crt
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/client.key
sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/root.crt

sudo chmod 644 /opt/observiq-otel-collector/ssl/client.crt
sudo chmod 600 /opt/observiq-otel-collector/ssl/client.key
sudo chmod 644 /opt/observiq-otel-collector/ssl/root.crt
```

### Issue 7: Data Not Flowing

**Symptoms:**
- No errors in logs
- TLS connection successful
- But data not appearing at final destination

**Diagnosis:**
```bash
# Check gateway pipeline configuration
sudo cat /opt/observiq-otel-collector/config.yaml | grep -A20 'service:'

# Check for processors that might be dropping data
sudo journalctl -u observiq-otel-collector | grep -i 'drop\|reject\|error'
```

**Solution:**
1. Verify gateway pipeline includes OTLP receiver in `service.pipelines`
2. Check gateway exporters are configured and working
3. Verify data is reaching the gateway (check gateway metrics)
4. Review processors for filters that might drop data

---

## Security Best Practices

### Certificate Management

1. **Certificate Rotation**
   - Plan certificate renewal 30 days before expiration
   - Use longer validity periods for production (2-3 years)
   - Test rotation process in staging environment

2. **Certificate Distribution**
   - Use secure channels to distribute certificates (scp, encrypted storage)
   - Never commit private keys to version control
   - Automate certificate deployment using configuration management

3. **Certificate Revocation**
   - If a certificate is compromised, regenerate CA and all certificates
   - Remove old certificates from all systems
   - Update BindPlane configurations with new certificate paths

### Network Security

1. **Firewall Rules**
   - Restrict port 4317 to known collector IPs/subnets
   - Block public access to gateway OTLP endpoints
   - Use VPC firewall rules in cloud environments

2. **Network Segmentation**
   - Place gateways in DMZ or transit network
   - Use private IPs for collector-to-gateway communication
   - Consider VPN or private network connections

### Access Control

1. **Service Accounts**
   - Run collectors and gateways as dedicated users (bdot)
   - Limit sudo access to certificate directories
   - Use IAM roles in cloud environments

2. **File Permissions**
   ```bash
   # CA certificate (public): 644
   # Server certificate (public): 644
   # Client certificate (public): 644
   # Private keys (secret): 600
   # All files owner: bdot:bdot
   ```

### Monitoring and Alerting

1. **Certificate Expiration Monitoring**
   ```bash
   # Check certificate expiration (warn if <30 days)
   openssl x509 -in /opt/observiq-otel-collector/ssl/root.crt -noout -checkend 2592000
   # Exit code 0: OK, Exit code 1: WARNING
   ```

2. **Connection Monitoring**
   - Monitor collector-to-gateway connection status
   - Alert on TLS handshake failures
   - Track data flow metrics (throughput, drops)

3. **Security Auditing**
   - Log all TLS handshake failures
   - Monitor for unauthorized connection attempts
   - Review access logs regularly

---

## Configuration Reference

### Collector OTLP Exporter (TLS)

```yaml
exporters:
  otlp/gw:
    compression: gzip
    endpoint: https://10.10.0.18:4317
    timeout: 30s
    tls:
      ca_file: /opt/observiq-otel-collector/ssl/root.crt
      insecure: false
      insecure_skip_verify: false
```

### Collector OTLP Exporter (mTLS)

```yaml
exporters:
  otlp/gw:
    compression: gzip
    endpoint: https://10.10.0.18:4317
    timeout: 30s
    tls:
      ca_file: /opt/observiq-otel-collector/ssl/root.crt
      cert_file: /opt/observiq-otel-collector/ssl/gateway-client.crt
      key_file: /opt/observiq-otel-collector/ssl/gateway-client.key
      insecure: false
      insecure_skip_verify: false
```

### Gateway OTLP Receiver (TLS)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        tls:
          cert_file: /opt/observiq-otel-collector/ssl/client.crt
          key_file: /opt/observiq-otel-collector/ssl/client.key
```

### Gateway OTLP Receiver (mTLS)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        tls:
          cert_file: /opt/observiq-otel-collector/ssl/client.crt
          key_file: /opt/observiq-otel-collector/ssl/client.key
          client_ca_file: /opt/observiq-otel-collector/ssl/root.crt
          client_auth_type: RequireAndVerifyClientCert
```

---

## File Locations Summary

### BindPlane Management Server (10.10.0.17)

| File | Path | Permissions | Description |
|------|------|-------------|-------------|
| BindPlane CA Cert | `/etc/bindplane/ssl/root.crt` | 644 | Root CA certificate |
| BindPlane CA Key | `/etc/bindplane/ssl/root.key` | 600 | Root CA private key |
| Gateway Server Cert | `/etc/bindplane/ssl/gateway-server.crt` | 644 | Gateway server certificate |
| Gateway Server Key | `/etc/bindplane/ssl/gateway-server.key` | 600 | Gateway server key |
| Collector Client Cert | `/etc/bindplane/ssl/collector-*-client.crt` | 644 | Collector client certificates |
| Collector Client Key | `/etc/bindplane/ssl/collector-*-client.key` | 600 | Collector client keys |

### Gateway VM (10.10.0.18)

| File | Path | Permissions | Description |
|------|------|-------------|-------------|
| BindPlane CA Cert | `/opt/observiq-otel-collector/ssl/root.crt` | 644 | BindPlane CA certificate |
| Server Certificate | `/opt/observiq-otel-collector/ssl/client.crt` | 644 | Gateway server certificate |
| Server Private Key | `/opt/observiq-otel-collector/ssl/client.key` | 600 | Gateway server private key |
| Gateway Config | `/opt/observiq-otel-collector/config.yaml` | 644 | Generated by BindPlane |

### Collector VM (10.20.0.5)

| File | Path | Permissions | Description |
|------|------|-------------|-------------|
| BindPlane CA Cert | `/opt/observiq-otel-collector/ssl/root.crt` | 644 | BindPlane CA certificate |
| Client Certificate | `/opt/observiq-otel-collector/ssl/gateway-client.crt` | 644 | Collector client cert (mTLS) |
| Client Private Key | `/opt/observiq-otel-collector/ssl/gateway-client.key` | 600 | Collector client key (mTLS) |
| Collector Config | `/opt/observiq-otel-collector/config.yaml` | 644 | Generated by BindPlane |

---

## BindPlane UI Configuration Values

### TLS Configuration (Server Authentication)

```yaml
Destination: BindPlane Gateway (gw)
Endpoint: https://10.10.0.18:4317

Compression: gzip
Timeout: 30

☐ Enable gRPC Load Balancing

☑ Enable TLS
☐ Skip TLS Certificate Verification

TLS Certificate Authority File: /opt/observiq-otel-collector/ssl/root.crt
Server Name Override: (empty or bindplane-gateway-vm-temp)

☐ Mutual TLS
TLS Client Certificate File: (empty)
TLS Client Private Key File: (empty)
```

### mTLS Configuration (Mutual Authentication)

```yaml
Destination: BindPlane Gateway (gw)
Endpoint: https://10.10.0.18:4317

Compression: gzip
Timeout: 30

☐ Enable gRPC Load Balancing

☑ Enable TLS
☐ Skip TLS Certificate Verification

TLS Certificate Authority File: /opt/observiq-otel-collector/ssl/root.crt
Server Name Override: (empty or bindplane-gateway-vm-temp)

☑ Mutual TLS

TLS Client Certificate File: /opt/observiq-otel-collector/ssl/gateway-client.crt

TLS Client Private Key File: /opt/observiq-otel-collector/ssl/gateway-client.key
```

---

## Quick Commands Reference

### Check Certificate Validity

```bash
# On collector - check CA certificate
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/root.crt -noout -dates

# On collector - check client certificate (mTLS)
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/gateway-client.crt -noout -dates

# On gateway - check server certificate
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/client.crt -noout -dates
```

### Test TLS Connection

```bash
# From collector - test TLS to gateway
openssl s_client -connect 10.10.0.18:4317 \
  -CAfile /opt/observiq-otel-collector/ssl/root.crt

# From collector - test mTLS to gateway
openssl s_client -connect 10.10.0.18:4317 \
  -CAfile /opt/observiq-otel-collector/ssl/root.crt \
  -cert /opt/observiq-otel-collector/ssl/gateway-client.crt \
  -key /opt/observiq-otel-collector/ssl/gateway-client.key
```

### Monitor Logs

```bash
# Collector logs
sudo journalctl -u observiq-otel-collector -f

# Gateway logs
sudo journalctl -u observiq-otel-collector -f | grep -i 'otlp\|tls\|certificate'

# Check for TLS errors
sudo journalctl -u observiq-otel-collector --since '5 minutes ago' | grep -i 'tls\|certificate'
```

---

## Related Documentation

- [WSS Implementation Guide](./wss-secure-opamp-implementation.md) - OpAMP TLS between collectors and BindPlane
- [Kafka TLS/mTLS Setup](./kafka-tls-mtls-setup.md) - Kafka broker to collector TLS
- [WSS Quick Reference](./wss-quick-reference.md) - Common commands

---

**Last Updated:** 2025-12-28
**Version:** 1.0
**Status:** Production Ready ✅
