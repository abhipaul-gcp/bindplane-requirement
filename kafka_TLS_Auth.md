# Kafka TLS Implementation Guide - Production Deployment

**Document Version:** 1.0
**Date:** 2025-12-30
**Environment:** secops-1-462509
**Implementation Type:** TLS Authentication for Kafka Stream

---

## Table of Contents

1. [Overview](#overview)
2. [Environment Details](#environment-details)
3. [Implementation Steps](#implementation-steps)
4. [Part 1: Kafka Broker TLS Configuration](#part-1-kafka-broker-tls-configuration)
5. [Part 2: Collector Agent TLS Configuration](#part-2-collector-agent-tls-configuration)
6. [Part 3: BindPlane UI Configuration](#part-3-bindplane-ui-configuration)
7. [Part 4: Verification](#part-4-verification)
8. [Rollback Procedure](#rollback-procedure)
9. [Troubleshooting](#troubleshooting)

---

## Overview

This document provides the exact commands to implement **TLS authentication** between BindPlane collector agents and Kafka brokers in your production environment.

### What This Implements

- **TLS encryption** for Kafka consumer connections (port 9094)
- **Server certificate verification** (collector verifies Kafka broker identity)
- **Dual listener support** (maintains port 9092 for backward compatibility)
- **High availability** configuration for multiple collectors

### Security Level

- **Authentication Type:** TLS (Server Authentication)
- **Encryption:** TLS 1.2/1.3
- **Certificate Validation:** Enabled
- **mTLS:** Not configured (optional future enhancement)

---

## Environment Details

### Infrastructure

| **Component** | **VM Name** | **Internal IP** | **Zone** | **Purpose** |
|---------------|-------------|-----------------|----------|-------------|
| Kafka Broker | `kafka-broker-vm` | 10.10.0.13 | asia-south1-a | Kafka server with TLS |
| Collector | `kafka-collector-vm` | 10.20.0.3 | asia-south1-a | ObservIQ collector agent |
| Management Server | `mgmt-server-vm` | 10.10.0.7 | asia-south1-a | BindPlane management |

### Network Configuration

- **Kafka PLAINTEXT Port:** 9092 (existing, maintained)
- **Kafka SSL/TLS Port:** 9094 (new, to be configured)
- **Kafka Controller Port:** 9093 (internal)
- **BindPlane OpAMP Port:** 3001

### Prerequisites Checklist

- [ ] Root/sudo access to kafka-broker-vm
- [ ] Root/sudo access to kafka-collector-vm
- [ ] Access to BindPlane UI (http://34.8.129.193:3001 or :8080)
- [ ] Firewall rules allow port 9094 between collector and broker
- [ ] Backup of current Kafka configuration created

---

## Implementation Steps

### Timeline

- **Part 1 (Kafka Broker):** ~20 minutes
- **Part 2 (Collector Agent):** ~10 minutes
- **Part 3 (BindPlane UI):** ~5 minutes
- **Part 4 (Verification):** ~10 minutes
- **Total Estimated Time:** ~45 minutes

### Downtime Assessment

- **Kafka Broker Restart:** ~30 seconds
- **Collector Restart:** Automatic via BindPlane (no manual restart)
- **Impact:** Minimal - existing PLAINTEXT connections remain active

---

## Part 1: Kafka Broker TLS Configuration

### Step 1.1: SSH to Kafka Broker

```bash
# Connect to Kafka broker via IAP
gcloud compute ssh kafka-broker-vm \
  --zone=asia-south1-a \
  --tunnel-through-iap \
  --project=secops-1-462509
```

### Step 1.2: Generate Root CA Certificate

```bash
# Create SSL directory
sudo mkdir -p /opt/kafka/ssl
cd /opt/kafka/ssl

# Generate CA private key (4096-bit RSA)
sudo openssl genrsa -out ca-key 4096

# Generate self-signed CA certificate (valid for 1 year)
sudo openssl req -x509 -new -nodes \
  -key ca-key \
  -sha256 \
  -days 365 \
  -out ca-cert \
  -subj '/CN=Kafka-CA-SecOps/O=SecOps/C=IN'

# Verify CA certificate
sudo openssl x509 -in ca-cert -noout -text | head -20
```

**Expected Output:**
```
Certificate:
    Data:
        Version: 3 (0x2)
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN=Kafka-CA-SecOps, O=SecOps, C=IN
        Subject: CN=Kafka-CA-SecOps, O=SecOps, C=IN
```

✅ **Checkpoint:** CA certificate created successfully

---

### Step 1.3: Create Server Keystore

```bash
cd /opt/kafka/ssl

# Generate server keystore with SAN entries
# IMPORTANT: Include both hostname and IP in SAN
sudo keytool -keystore kafka.server.keystore.jks \
  -alias localhost \
  -keyalg RSA \
  -validity 365 \
  -genkey \
  -storepass kafkaSecOps2025 \
  -keypass kafkaSecOps2025 \
  -dname 'CN=kafka-broker-vm, OU=SecOps, O=SecOps, L=Mumbai, ST=MH, C=IN' \
  -ext SAN=dns:kafka-broker-vm,dns:kafka-broker-vm.asia-south1-a.c.secops-1-462509.internal,dns:localhost,ip:10.10.0.13,ip:127.0.0.1

# Verify keystore
sudo keytool -list -v -keystore kafka.server.keystore.jks -storepass kafkaSecOps2025 | head -30
```

**Expected Output:**
```
Alias name: localhost
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=kafka-broker-vm, OU=SecOps, O=SecOps, L=Mumbai, ST=MH, C=IN
```

✅ **Checkpoint:** Server keystore created with proper SAN entries

---

### Step 1.4: Sign Server Certificate with CA

```bash
cd /opt/kafka/ssl

# Export certificate signing request
sudo keytool -keystore kafka.server.keystore.jks \
  -alias localhost \
  -certreq \
  -file cert-file \
  -storepass kafkaSecOps2025

# Sign the CSR with CA
sudo openssl x509 -req \
  -in cert-file \
  -CA ca-cert \
  -CAkey ca-key \
  -CAcreateserial \
  -out cert-signed \
  -days 365 \
  -sha256

# Import CA certificate into keystore
sudo keytool -keystore kafka.server.keystore.jks \
  -alias CARoot \
  -importcert \
  -file ca-cert \
  -storepass kafkaSecOps2025 \
  -noprompt

# Import signed certificate into keystore
sudo keytool -keystore kafka.server.keystore.jks \
  -alias localhost \
  -importcert \
  -file cert-signed \
  -storepass kafkaSecOps2025 \
  -noprompt

# Verify keystore now has certificate chain
sudo keytool -list -v -keystore kafka.server.keystore.jks -storepass kafkaSecOps2025 | grep "Certificate chain length"
```

**Expected Output:**
```
Certificate chain length: 2
```

✅ **Checkpoint:** Server certificate signed and imported successfully

---

### Step 1.5: Create Server Truststore

```bash
cd /opt/kafka/ssl

# Create truststore and import CA certificate
sudo keytool -keystore kafka.server.truststore.jks \
  -alias CARoot \
  -importcert \
  -file ca-cert \
  -storepass kafkaSecOps2025 \
  -noprompt

# Verify truststore
sudo keytool -list -v -keystore kafka.server.truststore.jks -storepass kafkaSecOps2025
```

**Expected Output:**
```
Keystore contains 1 entry
Alias name: caroot
Entry type: trustedCertEntry
```

✅ **Checkpoint:** Server truststore created successfully

---

### Step 1.6: Set File Permissions

```bash
cd /opt/kafka/ssl

# Set ownership to Kafka user
sudo chown -R kafka:kafka /opt/kafka/ssl

# Secure private keys (600)
sudo chmod 600 ca-key
sudo chmod 600 kafka.server.keystore.jks

# Public certificates (644)
sudo chmod 644 ca-cert
sudo chmod 644 kafka.server.truststore.jks
sudo chmod 644 cert-signed

# Verify permissions
ls -la /opt/kafka/ssl/
```

**Expected Output:**
```
-rw-------. 1 kafka kafka 3272 Dec 30 ca-key
-rw-r--r--. 1 kafka kafka 1188 Dec 30 ca-cert
-rw-------. 1 kafka kafka 5432 Dec 30 kafka.server.keystore.jks
-rw-r--r--. 1 kafka kafka 1256 Dec 30 kafka.server.truststore.jks
```

✅ **Checkpoint:** File permissions set correctly

---

### Step 1.7: Backup Kafka Configuration

```bash
# Create backup with timestamp
sudo cp /opt/kafka/config/kraft/server.properties \
     /opt/kafka/config/kraft/server.properties.backup.$(date +%Y%m%d_%H%M%S)

# Verify backup
ls -lh /opt/kafka/config/kraft/server.properties.backup.*
```

✅ **Checkpoint:** Configuration backed up successfully

---

### Step 1.8: Configure Kafka for Dual Listeners

```bash
# Add SSL configuration to Kafka
sudo tee -a /opt/kafka/config/kraft/server.properties > /dev/null <<'EOF'

# ==================== TLS/SSL Configuration ====================
# Added: 2025-12-30
# Purpose: Enable TLS encryption for collector connections

# Dual Listener Configuration
listeners=PLAINTEXT://:9092,SSL://:9094,CONTROLLER://:9093
advertised.listeners=PLAINTEXT://10.10.0.13:9092,SSL://10.10.0.13:9094
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL

# SSL Keystore Configuration
ssl.keystore.location=/opt/kafka/ssl/kafka.server.keystore.jks
ssl.keystore.password=kafkaSecOps2025
ssl.key.password=kafkaSecOps2025

# SSL Truststore Configuration
ssl.truststore.location=/opt/kafka/ssl/kafka.server.truststore.jks
ssl.truststore.password=kafkaSecOps2025

# Client Authentication (none = TLS only, required = mTLS)
ssl.client.auth=none

# TLS Protocol Versions (TLS 1.2 and 1.3 only)
ssl.enabled.protocols=TLSv1.2,TLSv1.3

# Cipher Suites (strong ciphers only)
ssl.cipher.suites=TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256
EOF

# Verify configuration was added
sudo tail -30 /opt/kafka/config/kraft/server.properties
```

✅ **Checkpoint:** SSL configuration added to server.properties

---

### Step 1.9: Verify Configuration Syntax

```bash
# Check for duplicate listener entries
sudo grep -n "^listeners=" /opt/kafka/config/kraft/server.properties

# If you see duplicate entries, keep only the last one (with SSL)
# Edit the file to remove the old PLAINTEXT-only listener line
```

**Action Required:** If there are duplicate `listeners=` entries, edit the file:

```bash
sudo nano /opt/kafka/config/kraft/server.properties

# Find and comment out the old line:
# listeners=PLAINTEXT://10.10.0.13:9092,CONTROLLER://10.10.0.13:9093

# Keep only the new line:
listeners=PLAINTEXT://:9092,SSL://:9094,CONTROLLER://:9093
```

✅ **Checkpoint:** Configuration syntax verified

---

### Step 1.10: Restart Kafka Broker

```bash
# Restart Kafka service
sudo systemctl restart kafka

# Wait for startup
sleep 10

# Check service status
sudo systemctl status kafka --no-pager

# Verify all three ports are listening
sudo ss -tlnp | grep java | grep -E ":(9092|9093|9094)"
```

**Expected Output:**
```
LISTEN 0  50   *:9092   *:*   users:(("java",pid=12345,...))
LISTEN 0  50   *:9094   *:*   users:(("java",pid=12345,...))
LISTEN 0  50   *:9093   *:*   users:(("java",pid=12345,...))
```

✅ **Checkpoint:** Kafka broker restarted with TLS enabled

---

### Step 1.11: Test TLS Connection

```bash
# Test TLS handshake on port 9094
openssl s_client -connect localhost:9094 \
  -servername kafka-broker-vm \
  -CAfile /opt/kafka/ssl/ca-cert 2>&1 | head -30

# Look for successful TLS handshake
# Press Ctrl+C to exit after seeing the certificate details
```

**Expected Output:**
```
CONNECTED(00000003)
depth=1 CN = Kafka-CA-SecOps, O = SecOps, C = IN
verify return:1
depth=0 CN = kafka-broker-vm, OU = SecOps, O = SecOps, L = Mumbai, ST = MH, C = IN
verify return:1
---
Certificate chain
 0 s:CN = kafka-broker-vm, OU = SecOps, O = SecOps, L = Mumbai, ST = MH, C = IN
   i:CN = Kafka-CA-SecOps, O = SecOps, C = IN
---
Server certificate
...
Verify return code: 0 (ok)
```

✅ **Checkpoint:** TLS connection test successful

---

### Step 1.12: Check Kafka Logs

```bash
# Check Kafka logs for SSL startup messages
sudo journalctl -u kafka -n 100 --no-pager | grep -i ssl

# Look for successful SSL listener startup
```

**Expected Messages:**
```
INFO Successfully started SSL listener on port 9094
INFO Created SSL socket
```

✅ **Checkpoint:** Part 1 Complete - Kafka Broker TLS Configured

---

## Part 2: Collector Agent TLS Configuration

### Step 2.1: Copy CA Certificate from Broker

**On your local machine or Cloud Shell:**

```bash
# Copy CA certificate from broker to local machine
gcloud compute scp kafka-broker-vm:/opt/kafka/ssl/ca-cert \
  /tmp/kafka-ca.crt \
  --zone asia-south1-a \
  --tunnel-through-iap \
  --project=secops-1-462509

# Verify certificate was copied
ls -lh /tmp/kafka-ca.crt
openssl x509 -in /tmp/kafka-ca.crt -noout -subject -issuer -dates
```

**Expected Output:**
```
subject=CN=Kafka-CA-SecOps, O=SecOps, C=IN
issuer=CN=Kafka-CA-SecOps, O=SecOps, C=IN
notBefore=Dec 30 XX:XX:XX 2025 GMT
notAfter=Dec 30 XX:XX:XX 2026 GMT
```

✅ **Checkpoint:** CA certificate copied to local machine

---

### Step 2.2: Copy CA Certificate to Collector

```bash
# Copy to collector VM
gcloud compute scp /tmp/kafka-ca.crt \
  kafka-collector-vm:/tmp/kafka-ca.crt \
  --zone asia-south1-a \
  --tunnel-through-iap \
  --project=secops-1-462509

# SSH to collector and move certificate to SSL directory
gcloud compute ssh kafka-collector-vm \
  --zone=asia-south1-a \
  --tunnel-through-iap \
  --project=secops-1-462509
```

**On collector VM:**

```bash
# Create SSL directory if it doesn't exist
sudo mkdir -p /opt/observiq-otel-collector/ssl

# Move certificate to SSL directory
sudo mv /tmp/kafka-ca.crt /opt/observiq-otel-collector/ssl/

# Set proper ownership (check collector user)
# User might be 'observiq' or 'bdot'
sudo chown observiq:observiq /opt/observiq-otel-collector/ssl/kafka-ca.crt 2>/dev/null || \
  sudo chown bdot:bdot /opt/observiq-otel-collector/ssl/kafka-ca.crt

# Set permissions
sudo chmod 644 /opt/observiq-otel-collector/ssl/kafka-ca.crt

# Verify certificate
sudo openssl x509 -in /opt/observiq-otel-collector/ssl/kafka-ca.crt -noout -subject -issuer -dates
```

**Expected Output:**
```
subject=CN=Kafka-CA-SecOps, O=SecOps, C=IN
issuer=CN=Kafka-CA-SecOps, O=SecOps, C=IN
notBefore=Dec 30 XX:XX:XX 2025 GMT
notAfter=Dec 30 XX:XX:XX 2026 GMT
```

✅ **Checkpoint:** CA certificate installed on collector

---

### Step 2.3: Verify Collector Service User

```bash
# Check which user runs the collector service
ps aux | grep observiq-otel-collector | grep -v grep

# Check SSL directory permissions
ls -la /opt/observiq-otel-collector/ssl/
```

**Expected Output:**
```
-rw-r--r--. 1 observiq observiq 1188 Dec 30 kafka-ca.crt
```

or

```
-rw-r--r--. 1 bdot bdot 1188 Dec 30 kafka-ca.crt
```

✅ **Checkpoint:** Part 2 Complete - Collector CA Certificate Installed

---

## Part 3: BindPlane UI Configuration

### Step 3.1: Access BindPlane UI

1. Open your browser
2. Navigate to: **http://34.8.129.193:3001** (production) or **http://34.8.129.193:8080** (temp)
3. Log in with your credentials

---

### Step 3.2: Configure Kafka Stream Source with TLS

#### Navigate to Sources

1. Click **Sources** in the left navigation menu
2. Click **Add Source** (or edit existing Kafka Stream source)
3. Select **Kafka Stream** as source type

#### Basic Configuration

Fill in the following fields:

| **Field** | **Value** |
|-----------|-----------|
| **Source Name** | `Kafka Windows Logs - TLS` |
| **Brokers** | `10.10.0.13:9094` |
| **Topic** | `windows-logs` (or your topic name) |
| **Consumer Group ID** | `production-windows-logs-consumers` |
| **Client ID** | `collector-${agent.id}` |
| **Encoding** | `json` |
| **Initial Offset** | `latest` |

#### TLS Configuration

Enable and configure TLS:

| **Field** | **Value** | **Notes** |
|-----------|-----------|-----------|
| **Enable TLS** | ☑ **Checked** | Enable TLS encryption |
| **Skip TLS Certificate Verification** | ☐ **Unchecked** | Verify server certificate |
| **TLS Certificate Authority File** | `/opt/observiq-otel-collector/ssl/kafka-ca.crt` | Path on collector |
| **Mutual TLS Client Certificate File** | **(leave empty)** | Not needed for TLS-only |
| **TLS Client Private Key File** | **(leave empty)** | Not needed for TLS-only |

#### Advanced Settings (Optional)

| **Field** | **Value** |
|-----------|-----------|
| **Session Timeout** | `10s` |
| **Heartbeat Interval** | `3s` |

#### Save Configuration

1. Click **Save** or **Apply**
2. Note the configuration ID for reference

✅ **Checkpoint:** Kafka Stream source configured with TLS

---

### Step 3.3: Assign Configuration to Collector

1. Navigate to **Agents** in the left menu
2. Find your collector agent: `kafka-collector-vm` or by internal IP `10.20.0.3`
3. Select the agent
4. Click **Configure** or **Apply Configuration**
5. Select the configuration containing your Kafka Stream TLS source
6. Click **Apply** or **Deploy**

**Expected Behavior:**
- Agent status will show "Configuration Pending"
- After 30-60 seconds, status changes to "Connected"
- Configuration version increments

✅ **Checkpoint:** Configuration assigned to collector

---

### Step 3.4: Monitor Configuration Deployment

1. Stay on the **Agents** page
2. Watch the agent status
3. Wait for status to change from "Configuration Pending" to "Connected"
4. Check the "Last Seen" timestamp updates

**Typical Timeline:**
- 0-30 seconds: Configuration pushed via OpAMP
- 30-60 seconds: Collector applies configuration and restarts receiver
- 60-90 seconds: Collector connects to Kafka with TLS

✅ **Checkpoint:** Part 3 Complete - BindPlane Configuration Applied

---

## Part 4: Verification

### Step 4.1: Verify Collector Configuration

**SSH to collector:**

```bash
gcloud compute ssh kafka-collector-vm \
  --zone=asia-south1-a \
  --tunnel-through-iap \
  --project=secops-1-462509
```

**Check applied configuration:**

```bash
# View Kafka receiver configuration
sudo cat /opt/observiq-otel-collector/config.yaml | grep -A25 'kafka/'

# Look for TLS settings
sudo cat /opt/observiq-otel-collector/config.yaml | grep -A10 'tls:'
```

**Expected Configuration:**
```yaml
kafka/windows_logs_tls:
  brokers:
    - 10.10.0.13:9094
  client_id: collector-abc123def456
  group_id: production-windows-logs-consumers
  initial_offset: latest
  logs:
    encoding: json
  session_timeout: 10s
  heartbeat_interval: 3s
  tls:
    ca_file: /opt/observiq-otel-collector/ssl/kafka-ca.crt
    insecure_skip_verify: false
  topic: windows-logs
```

✅ **Checkpoint:** Configuration applied correctly

---

### Step 4.2: Monitor Collector Logs

```bash
# Watch collector logs in real-time
sudo journalctl -u observiq-otel-collector -f
```

**✅ Successful Messages:**
```
INFO    Kafka receiver started successfully
INFO    Connected to Kafka broker: 10.10.0.13:9094
INFO    Joined consumer group: production-windows-logs-consumers
INFO    Assigned partitions: [0, 1, 2]
INFO    TLS connection established
INFO    Successfully consuming from topic: windows-logs
```

**❌ Error Messages to Watch:**
```
ERROR   TLS handshake failed
ERROR   x509: certificate signed by unknown authority
ERROR   Connection refused to 10.10.0.13:9094
ERROR   Failed to join consumer group
```

Press `Ctrl+C` when you see successful connection messages.

✅ **Checkpoint:** Collector connected successfully with TLS

---

### Step 4.3: Verify Consumer Group on Kafka Broker

**SSH to Kafka broker:**

```bash
gcloud compute ssh kafka-broker-vm \
  --zone=asia-south1-a \
  --tunnel-through-iap \
  --project=secops-1-462509
```

**List consumer groups:**

```bash
# List all consumer groups
/opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --list

# Describe your consumer group
/opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group production-windows-logs-consumers
```

**Expected Output:**
```
GROUP                               TOPIC         PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG  CONSUMER-ID                    HOST
production-windows-logs-consumers   windows-logs  0          1250            1250            0    collector-abc123def456         /10.20.0.3
production-windows-logs-consumers   windows-logs  1          1250            1250            0    collector-abc123def456         /10.20.0.3
production-windows-logs-consumers   windows-logs  2          1250            1250            0    collector-abc123def456         /10.20.0.3
```

**What to Check:**
- ✅ Consumer group exists
- ✅ Collector is listed (CONSUMER-ID matches `client_id`)
- ✅ All partitions are assigned
- ✅ LAG is 0 or low (collector is keeping up)
- ✅ HOST shows collector IP: 10.20.0.3

✅ **Checkpoint:** Consumer group active and consuming

---

### Step 4.4: Verify Network Connection

**On collector:**

```bash
# Test network connectivity to port 9094
nc -zv 10.10.0.13 9094

# Test TLS handshake (will fail without client cert validation, but shows TLS works)
openssl s_client -connect 10.10.0.13:9094 \
  -CAfile /opt/observiq-otel-collector/ssl/kafka-ca.crt \
  -servername kafka-broker-vm 2>&1 | grep "Verify return code"
```

**Expected Output:**
```
Connection to 10.10.0.13 9094 port [tcp/*] succeeded!
Verify return code: 0 (ok)
```

✅ **Checkpoint:** Network and TLS connectivity verified

---

### Step 4.5: Test Message Flow

**On Kafka broker:**

```bash
# Check if topic exists
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list | grep windows-logs

# Send a test message
echo '{"event":"TLS_TEST","timestamp":"'$(date -Iseconds)'","source":"manual"}' | \
  /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 \
    --topic windows-logs
```

**On collector:**

```bash
# Watch logs for the test message
sudo journalctl -u observiq-otel-collector -n 50 | grep -i "TLS_TEST"
```

**Expected:** You should see the test message being processed.

✅ **Checkpoint:** Message flow verified end-to-end

---

### Step 4.6: Check Firewall Rules

**Verify port 9094 is allowed:**

```bash
# On Kafka broker
sudo firewall-cmd --list-all | grep -E "(9092|9094)"

# If port 9094 not listed, add it:
# sudo firewall-cmd --permanent --add-port=9094/tcp
# sudo firewall-cmd --reload
```

**Expected Output:**
```
ports: 9092/tcp 9094/tcp
```

✅ **Checkpoint:** Firewall configured correctly

---

### Step 4.7: Final Health Check

**Create a verification checklist:**

```bash
# On Kafka broker
echo "=== Kafka Broker Health Check ==="
echo "1. Kafka service status:"
sudo systemctl is-active kafka

echo "2. Port 9094 listening:"
sudo ss -tlnp | grep :9094 && echo "✅ Yes" || echo "❌ No"

echo "3. SSL certificates valid:"
sudo openssl x509 -in /opt/kafka/ssl/ca-cert -noout -dates | grep "notAfter"

echo "4. Consumer groups active:"
/opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --list | wc -l
```

**On collector:**

```bash
echo "=== Collector Health Check ==="
echo "1. Collector service status:"
sudo systemctl is-active observiq-otel-collector

echo "2. CA certificate present:"
ls -lh /opt/observiq-otel-collector/ssl/kafka-ca.crt && echo "✅ Yes" || echo "❌ No"

echo "3. Recent logs (no errors):"
sudo journalctl -u observiq-otel-collector --since "5 minutes ago" | grep -i error | wc -l
echo "(Should be 0 or minimal)"
```

✅ **Checkpoint:** Part 4 Complete - Full Verification Successful

---

## Rollback Procedure

If you encounter issues and need to rollback:

### Rollback Step 1: Restore Kafka Configuration

**On Kafka broker:**

```bash
# Find your backup
ls -lh /opt/kafka/config/kraft/server.properties.backup.*

# Restore the backup (choose the most recent)
sudo cp /opt/kafka/config/kraft/server.properties.backup.YYYYMMDD_HHMMSS \
     /opt/kafka/config/kraft/server.properties

# Restart Kafka
sudo systemctl restart kafka

# Verify rollback
sudo systemctl status kafka --no-pager
sudo ss -tlnp | grep java
```

### Rollback Step 2: Remove TLS from BindPlane

1. Navigate to BindPlane UI
2. Go to **Sources**
3. Edit the Kafka Stream source
4. **Uncheck** "Enable TLS"
5. Change broker address back to `10.10.0.13:9092`
6. Save and apply to agents

### Rollback Step 3: Verify

```bash
# On collector, verify configuration reverted
sudo cat /opt/observiq-otel-collector/config.yaml | grep -A15 'kafka/'

# Should show port 9092 and no TLS configuration
```

---

## Troubleshooting

### Issue 1: Kafka Won't Start After TLS Configuration

**Symptoms:**
```
ERROR Failed to start Kafka service
```

**Solutions:**

1. **Check Kafka logs:**
   ```bash
   sudo journalctl -u kafka -n 100 --no-pager
   ```

2. **Common causes:**
   - Duplicate `listeners=` entries in server.properties
   - Incorrect file paths in SSL configuration
   - Wrong file permissions

3. **Fix duplicate listeners:**
   ```bash
   sudo grep -n "^listeners=" /opt/kafka/config/kraft/server.properties
   # Comment out old entries, keep only SSL configuration
   ```

4. **Verify SSL file paths:**
   ```bash
   sudo grep "ssl\." /opt/kafka/config/kraft/server.properties
   # Ensure all paths point to /opt/kafka/ssl/
   ```

---

### Issue 2: Collector Can't Connect to Kafka

**Symptoms:**
```
ERROR Connection refused to 10.10.0.13:9094
```

**Solutions:**

1. **Verify Kafka is listening on 9094:**
   ```bash
   # On broker
   sudo ss -tlnp | grep :9094
   ```

2. **Check firewall:**
   ```bash
   # On broker
   sudo firewall-cmd --list-all | grep 9094
   ```

3. **Test connectivity from collector:**
   ```bash
   # On collector
   nc -zv 10.10.0.13 9094
   ```

4. **Check VPC firewall rules (GCP):**
   ```bash
   gcloud compute firewall-rules list --filter="name~kafka" --format="table(name,allowed,sourceRanges)"
   ```

---

### Issue 3: TLS Certificate Verification Failed

**Symptoms:**
```
ERROR x509: certificate signed by unknown authority
```

**Solutions:**

1. **Verify CA cert on collector:**
   ```bash
   sudo ls -la /opt/observiq-otel-collector/ssl/kafka-ca.crt
   ```

2. **Compare fingerprints:**
   ```bash
   # On broker
   sudo openssl x509 -in /opt/kafka/ssl/ca-cert -noout -fingerprint

   # On collector
   sudo openssl x509 -in /opt/observiq-otel-collector/ssl/kafka-ca.crt -noout -fingerprint

   # Should match!
   ```

3. **Re-copy CA certificate if different**

---

### Issue 4: Consumer Group Not Visible

**Symptoms:**
```
Consumer group 'production-windows-logs-consumers' not found
```

**Solutions:**

1. **Wait 30-60 seconds** (collector needs time to connect)

2. **Check collector logs:**
   ```bash
   sudo journalctl -u observiq-otel-collector -n 100 | grep -i kafka
   ```

3. **Verify group_id in configuration:**
   ```bash
   sudo cat /opt/observiq-otel-collector/config.yaml | grep group_id
   ```

4. **Restart collector if needed:**
   ```bash
   sudo systemctl restart observiq-otel-collector
   ```

---

### Issue 5: High Consumer Lag

**Symptoms:**
```
LAG column shows increasing values
```

**Solutions:**

1. **Check collector is running:**
   ```bash
   sudo systemctl status observiq-otel-collector
   ```

2. **Increase partitions (if needed):**
   ```bash
   /opt/kafka/bin/kafka-topics.sh \
     --bootstrap-server localhost:9092 \
     --alter \
     --topic windows-logs \
     --partitions 6
   ```

3. **Add more collectors** to distribute load

---

## Post-Implementation Checklist

### Immediate (Day 1)

- [ ] Kafka broker listening on port 9094 with TLS
- [ ] Collector connected via TLS (port 9094)
- [ ] Consumer group active with LAG = 0
- [ ] Test messages flowing successfully
- [ ] No errors in Kafka logs
- [ ] No errors in collector logs
- [ ] BindPlane UI shows agent as "Connected"

### Short-term (Week 1)

- [ ] Monitor consumer group lag daily
- [ ] Check certificate expiration dates
- [ ] Document any issues encountered
- [ ] Create monitoring alerts for consumer lag
- [ ] Backup SSL certificates to secure location

### Long-term (Month 1)

- [ ] Set up certificate rotation procedure
- [ ] Consider implementing mTLS for higher security
- [ ] Add additional collectors for HA if needed
- [ ] Review and optimize Kafka partition count
- [ ] Schedule certificate renewal (before expiry)

---

## Certificate Expiration Tracking

### Current Certificates

| **Certificate** | **Location** | **Expiration Date** | **Renewal Due** |
|----------------|--------------|---------------------|-----------------|
| CA Certificate | `/opt/kafka/ssl/ca-cert` | 2026-12-30 | 2026-11-30 |
| Server Certificate | Kafka keystore | 2026-12-30 | 2026-11-30 |

### Renewal Procedure

**When to renew:** 30 days before expiration

**Steps:**
1. Generate new certificates following Part 1, Steps 1.2-1.5
2. Update Kafka keystore
3. Copy new CA cert to all collectors
4. Restart Kafka broker
5. Restart collector services (or wait for automatic config pull)
6. Verify connections

---

## Support and Escalation

### Log Locations

| **Component** | **Log Location** | **Command** |
|--------------|------------------|-------------|
| Kafka Broker | systemd journal | `sudo journalctl -u kafka -f` |
| Collector | systemd journal | `sudo journalctl -u observiq-otel-collector -f` |
| Kafka Server Log | File | `tail -f /opt/kafka/logs/server.log` |

### Key Files Reference

| **File** | **Path** | **Purpose** |
|----------|----------|-------------|
| Kafka Config | `/opt/kafka/config/kraft/server.properties` | Main Kafka configuration |
| CA Certificate (Broker) | `/opt/kafka/ssl/ca-cert` | Root CA for TLS |
| Server Keystore | `/opt/kafka/ssl/kafka.server.keystore.jks` | Kafka server identity |
| CA Certificate (Collector) | `/opt/observiq-otel-collector/ssl/kafka-ca.crt` | CA for verification |
| Collector Config | `/opt/observiq-otel-collector/config.yaml` | Collector configuration |

### Useful Commands

```bash
# Check Kafka broker TLS listener
sudo ss -tlnp | grep :9094

# Test TLS handshake
openssl s_client -connect 10.10.0.13:9094 -CAfile /opt/kafka/ssl/ca-cert

# List consumer groups
/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# Describe consumer group
/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group GROUP_ID

# Watch collector logs
sudo journalctl -u observiq-otel-collector -f | grep -i kafka

# Check certificate expiration
sudo openssl x509 -in /opt/kafka/ssl/ca-cert -noout -dates
```

---

## Appendix: Configuration Examples

### Complete Kafka Stream Source Configuration (YAML)

```yaml
receivers:
  kafka/windows_logs_tls:
    brokers:
      - "10.10.0.13:9094"
    topic: "windows-logs"
    group_id: "production-windows-logs-consumers"
    client_id: "collector-${agent.id}"
    logs:
      encoding: json
    initial_offset: latest
    session_timeout: 10s
    heartbeat_interval: 3s
    tls:
      ca_file: "/opt/observiq-otel-collector/ssl/kafka-ca.crt"
      insecure_skip_verify: false

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

exporters:
  chronicle/SecOps:
    endpoint: "https://malachiteingestion-pa.googleapis.com"
    customer_id: "YOUR_CUSTOMER_ID"
    credentials: |
      {GOOGLE_CLOUD_SERVICE_ACCOUNT_JSON}
    log_type: "WINEVTLOG"
    compression: "gzip"

service:
  pipelines:
    logs/kafka_windows:
      receivers: [kafka/windows_logs_tls]
      processors: [batch]
      exporters: [chronicle/SecOps]
```

### Kafka Server Properties (Relevant TLS Section)

```properties
# Dual Listener Configuration
listeners=PLAINTEXT://:9092,SSL://:9094,CONTROLLER://:9093
advertised.listeners=PLAINTEXT://10.10.0.13:9092,SSL://10.10.0.13:9094
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL

# SSL Configuration
ssl.keystore.location=/opt/kafka/ssl/kafka.server.keystore.jks
ssl.keystore.password=kafkaSecOps2025
ssl.key.password=kafkaSecOps2025
ssl.truststore.location=/opt/kafka/ssl/kafka.server.truststore.jks
ssl.truststore.password=kafkaSecOps2025
ssl.client.auth=none
ssl.enabled.protocols=TLSv1.2,TLSv1.3
ssl.cipher.suites=TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256
```

---

## Document History

| **Version** | **Date** | **Author** | **Changes** |
|------------|----------|------------|-------------|
| 1.0 | 2025-12-30 | Claude Code | Initial implementation guide created |

---

**End of Implementation Guide**

For questions or issues, refer to the Troubleshooting section or check the logs using the commands provided in the Support and Escalation section.
