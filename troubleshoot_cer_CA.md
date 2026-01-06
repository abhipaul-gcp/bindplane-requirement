# Troubleshooting: Server Certificate and CA Bundle Mismatch

## Problem Description

You have a server certificate and CA bundle, but when verifying, you get errors indicating the certificate is not issued by the CA bundle.

**Common Error Messages:**
```
error 20 at 0 depth lookup:unable to get local issuer certificate
error 21 at 0 depth lookup:unable to verify the first certificate
Verify return code: 21 (unable to verify the first certificate)
```

---

## Diagnostic Steps

### Step 1: Identify Who Issued Your Server Certificate

```bash
# Show server certificate issuer (who signed it)
sudo openssl x509 -in /etc/bindplane/ssl/server.crt -noout -issuer
```

**Example Output:**
```
issuer=CN=Example Issuing CA, O=Example Corporation, C=US
```

**Key Information:** The CN (Common Name) tells you which CA issued this certificate.

---

### Step 2: Check What's in Your CA Bundle

```bash
# List all certificates in the CA bundle
sudo openssl crl2pkcs7 -nocrl -certfile /etc/bindplane/ssl/ca-bundle.crt | \
  openssl pkcs7 -print_certs -noout
```

**Example Output:**
```
subject=CN=Example Root CA, O=Example Corporation, C=US
issuer=CN=Example Root CA, O=Example Corporation, C=US

subject=CN=Example Issuing CA, O=Example Corporation, C=US
issuer=CN=Example Root CA, O=Example Corporation, C=US
```

**OR use this simpler command to see subjects only:**

```bash
# Extract each certificate and show subject
i=1
while openssl x509 -noout -subject 2>/dev/null; do
    echo "Certificate $i:"
    echo $i
    i=$((i+1))
done < /etc/bindplane/ssl/ca-bundle.crt
```

---

### Step 3: Match Issuer to CA Bundle

**The Rule:** Your server certificate's **issuer** must match the **subject** of one of the certificates in the CA bundle.

**Example - CORRECT Setup:**

Server Certificate:
```
subject=CN=bindplane.example.com
issuer=CN=Example Issuing CA, O=Example Corporation
```

CA Bundle:
```
Certificate 1:
  subject=CN=Example Issuing CA, O=Example Corporation  ← MATCHES!
  issuer=CN=Example Root CA

Certificate 2:
  subject=CN=Example Root CA
  issuer=CN=Example Root CA (self-signed)
```

✅ **Match Found:** Server cert issuer = Intermediate CA subject

---

## Common Mismatch Scenarios

### Scenario 1: CA Bundle Only Contains Root CA (Missing Intermediate)

**Symptoms:**
```bash
$ openssl verify -CAfile ca-bundle.crt server.crt
error 20 at 0 depth lookup:unable to get local issuer certificate
```

**What's Wrong:**

Server Certificate:
```
issuer=CN=Example Issuing CA  ← Issued by Intermediate CA
```

CA Bundle:
```
Certificate 1:
  subject=CN=Example Root CA  ← Only has Root CA, missing Intermediate!
```

**Solution:** Add the Intermediate CA certificate to the bundle

**Step-by-Step Fix:**

1. **Obtain the Intermediate CA certificate:**

   **From CA web interface:**
   - Download "Intermediate Certificate" or "Issuing CA Certificate"
   - Save as `intermediate.crt`

   **From certificate chain in server cert (if provided):**
   ```bash
   # If your CA gave you a full chain file
   # Extract intermediate (usually 2nd certificate)
   openssl x509 -in fullchain.crt -noout -subject
   ```

   **From Windows CA Server:**
   ```powershell
   # Export Intermediate CA certificate
   certutil -ca.cert 1 intermediate.cer
   certutil -encode intermediate.cer intermediate.crt
   ```

2. **Verify the intermediate certificate:**
   ```bash
   # Check this is the right intermediate
   openssl x509 -in intermediate.crt -noout -subject
   # Should show: subject=CN=Example Issuing CA
   ```

3. **Create correct CA bundle (Intermediate BEFORE Root):**
   ```bash
   # Correct order: Intermediate → Root
   sudo cat intermediate.crt root.crt > ca-bundle.crt

   # Verify bundle has 2 certificates
   grep -c "BEGIN CERTIFICATE" ca-bundle.crt
   # Output: 2
   ```

4. **Test verification:**
   ```bash
   openssl verify -CAfile ca-bundle.crt server.crt
   # Expected: server.crt: OK
   ```

---

### Scenario 2: Wrong Intermediate CA in Bundle

**Symptoms:**
```bash
$ openssl verify -CAfile ca-bundle.crt server.crt
error 21 at 0 depth lookup:unable to verify the first certificate
```

**What's Wrong:**

Server Certificate:
```
issuer=CN=Issuing CA 2023
```

CA Bundle:
```
subject=CN=Issuing CA 2024  ← Different Issuing CA!
```

**This happens when:**
- CA renewed their intermediate certificate
- You have an old intermediate in the bundle
- You downloaded intermediate from wrong CA

**Solution:** Get the correct intermediate certificate

1. **Check server certificate serial number and authority info:**
   ```bash
   openssl x509 -in server.crt -noout -text | grep -A4 "Authority Information Access"
   ```

   **Example Output:**
   ```
   Authority Information Access:
       CA Issuers - URI:http://pki.example.com/issuing-ca.crt
   ```

2. **Download the correct intermediate:**
   ```bash
   # Download from URI in certificate
   curl -o intermediate.crt http://pki.example.com/issuing-ca.crt

   # Convert if needed (DER to PEM)
   openssl x509 -inform DER -in intermediate.crt -out intermediate.pem
   ```

3. **Verify this intermediate issued your server cert:**
   ```bash
   openssl verify -CAfile intermediate.pem server.crt
   # If intermediate is self-signed, will still fail but shows progress

   # Better: check issuer matches
   SERVER_ISSUER=$(openssl x509 -in server.crt -noout -issuer)
   INTER_SUBJECT=$(openssl x509 -in intermediate.pem -noout -subject)

   echo "Server issuer: $SERVER_ISSUER"
   echo "Intermediate subject: $INTER_SUBJECT"
   # Should match!
   ```

4. **Recreate CA bundle:**
   ```bash
   cat intermediate.pem root.crt > ca-bundle.crt
   openssl verify -CAfile ca-bundle.crt server.crt
   # Expected: OK
   ```

---

### Scenario 3: Certificate Chain in Wrong Order

**Symptoms:**
```bash
$ openssl verify -CAfile ca-bundle.crt server.crt
error 20 at 0 depth lookup:unable to get local issuer certificate
```

**What's Wrong:**

CA Bundle has certificates in wrong order:
```
Certificate 1: Root CA        ← Wrong order!
Certificate 2: Intermediate CA
```

**Correct order should be:**
```
Certificate 1: Intermediate CA  ← First
Certificate 2: Root CA          ← Second
```

**Solution:** Reverse certificate order

```bash
# Check current order (first cert shown)
openssl x509 -in ca-bundle.crt -noout -subject
# If shows Root CA, order is wrong

# Split bundle into separate files
csplit -f cert- ca-bundle.crt '/BEGIN CERTIFICATE/' '{*}'

# View each certificate
for f in cert-*; do
    if [ -s "$f" ] && grep -q "BEGIN CERTIFICATE" "$f"; then
        echo "File: $f"
        openssl x509 -in "$f" -noout -subject -issuer
        echo ""
    fi
done

# Recreate in correct order: Intermediate then Root
# Identify which file is intermediate (issuer != subject)
# Identify which file is root (issuer = subject)

cat cert-intermediate.pem cert-root.pem > ca-bundle-fixed.crt

# Test
openssl verify -CAfile ca-bundle-fixed.crt server.crt
```

---

### Scenario 4: Server Certificate from Different CA Entirely

**Symptoms:**
```bash
$ openssl verify -CAfile ca-bundle.crt server.crt
error 20/21
```

**What's Wrong:**

Server Certificate:
```
issuer=CN=DigiCert TLS RSA SHA256 2020 CA1
```

CA Bundle:
```
subject=CN=Internal Enterprise CA  ← Completely different CA!
```

**This happens when:**
- You used wrong server certificate file
- Server cert from public CA, bundle from internal CA
- Multiple CAs in organization, used wrong one

**Solution:** Match certificate and CA bundle

1. **Identify your server certificate's CA:**
   ```bash
   openssl x509 -in server.crt -noout -issuer
   ```

2. **Find the correct CA bundle for this issuer:**

   **If Public CA (DigiCert, GlobalSign, etc.):**
   ```bash
   # Download CA bundle from CA's website
   # DigiCert: https://www.digicert.com/kb/digicert-root-certificates.htm
   # GlobalSign: https://www.globalsign.com/en/support/

   # OR extract from certificate's AIA extension
   openssl x509 -in server.crt -noout -text | \
     grep -A2 "Authority Information Access"
   ```

   **If Internal CA:**
   - Contact your PKI team
   - Export from certificate management system
   - Get from CA server directly

3. **Replace CA bundle with correct one:**
   ```bash
   cp correct-ca-bundle.crt /etc/bindplane/ssl/ca-bundle.crt
   openssl verify -CAfile /etc/bindplane/ssl/ca-bundle.crt server.crt
   ```

---

## Complete Verification Workflow

### Step-by-Step Verification Process

```bash
# 1. Check server certificate details
echo "=== SERVER CERTIFICATE ==="
openssl x509 -in /etc/bindplane/ssl/server.crt -noout -subject -issuer -dates

# 2. Check CA bundle details
echo ""
echo "=== CA BUNDLE CERTIFICATES ==="
openssl crl2pkcs7 -nocrl -certfile /etc/bindplane/ssl/ca-bundle.crt | \
  openssl pkcs7 -print_certs -noout

# 3. Verify chain
echo ""
echo "=== CHAIN VERIFICATION ==="
openssl verify -CAfile /etc/bindplane/ssl/ca-bundle.crt \
  /etc/bindplane/ssl/server.crt
```

**Expected Output:**
```
=== SERVER CERTIFICATE ===
subject=CN=bindplane.example.com, O=Example Corp
issuer=CN=Example Issuing CA, O=Example Corp
notBefore=Jan  6 00:00:00 2026 GMT
notAfter=Jan  6 00:00:00 2027 GMT

=== CA BUNDLE CERTIFICATES ===
subject=CN=Example Issuing CA, O=Example Corp
issuer=CN=Example Root CA, O=Example Corp

subject=CN=Example Root CA, O=Example Corp
issuer=CN=Example Root CA, O=Example Corp

=== CHAIN VERIFICATION ===
/etc/bindplane/ssl/server.crt: OK
```

---

## Building CA Bundle from Scratch

If you're unsure what should be in your CA bundle, follow this process:

### Method 1: From Certificate Chain File

Some CAs provide a full chain file (e.g., `fullchain.pem`):

```bash
# View all certificates in chain
openssl crl2pkcs7 -nocrl -certfile fullchain.pem | \
  openssl pkcs7 -print_certs -text | less

# Split into individual certificates
csplit -f cert- fullchain.pem '/BEGIN CERTIFICATE/' '{*}'

# Identify each certificate
for f in cert-*; do
    if [ -s "$f" ] && grep -q "BEGIN" "$f"; then
        echo "=== $f ==="
        openssl x509 -in "$f" -noout -subject -issuer
        echo ""
    fi
done

# Create CA bundle (exclude server cert, include intermediates and root)
# Usually cert-00 is server cert (skip it)
cat cert-01 cert-02 > ca-bundle.crt
```

### Method 2: From Separate Certificate Files

If you have separate files:

```bash
# Files you should have:
# - server.crt (server certificate)
# - intermediate.crt (intermediate CA)
# - root.crt (root CA)

# Create CA bundle (Intermediate + Root)
cat intermediate.crt root.crt > ca-bundle.crt

# Verify
openssl verify -CAfile ca-bundle.crt server.crt
```

### Method 3: Download from Certificate AIA Extension

```bash
# Extract CA download URL from server certificate
openssl x509 -in server.crt -noout -text | grep -A4 "Authority Information Access"

# Example output:
# CA Issuers - URI:http://pki.example.com/intermediate.crt

# Download intermediate
wget http://pki.example.com/intermediate.crt -O intermediate.der

# Convert to PEM
openssl x509 -inform DER -in intermediate.der -out intermediate.crt

# Get root CA (usually from CA's website)
wget http://pki.example.com/root.crt

# Create bundle
cat intermediate.crt root.crt > ca-bundle.crt
```

---

## Testing Your Fix

After fixing the CA bundle, run these tests:

### Test 1: OpenSSL Verify
```bash
openssl verify -CAfile /etc/bindplane/ssl/ca-bundle.crt \
  /etc/bindplane/ssl/server.crt
```
**Expected:** `/etc/bindplane/ssl/server.crt: OK`

### Test 2: Full Chain Display
```bash
openssl verify -CAfile /etc/bindplane/ssl/ca-bundle.crt \
  -verbose -show_chain /etc/bindplane/ssl/server.crt
```
**Expected:** Shows full chain from server → intermediate → root

### Test 3: Live TLS Connection
```bash
openssl s_client -connect 10.10.0.17:3001 \
  -CAfile /etc/bindplane/ssl/ca-bundle.crt \
  -servername bindplane.example.com < /dev/null 2>&1 | \
  grep "Verify return"
```
**Expected:** `Verify return code: 0 (ok)`

### Test 4: Restart BindPlane and Check Logs
```bash
sudo systemctl restart bindplane
sudo journalctl -u bindplane -n 50 --no-pager | grep -i "tls\|certificate\|error"
```
**Expected:** No TLS-related errors

---

## Quick Reference: Certificate Chain Requirements

### For Self-Signed CA Setup
```
CA Bundle Contents:
└── Root CA (self-signed)
```

### For Intermediate CA Setup (Most Common)
```
CA Bundle Contents:
├── Intermediate CA (issued by Root)
└── Root CA (self-signed)
```

### For Multiple Intermediate CAs
```
CA Bundle Contents:
├── Intermediate CA 2 (issued by Intermediate 1)
├── Intermediate CA 1 (issued by Root)
└── Root CA (self-signed)
```

**Chain Validation Rule:**
```
Server Cert Issuer = Intermediate 2 Subject
Intermediate 2 Issuer = Intermediate 1 Subject
Intermediate 1 Issuer = Root Subject
Root Issuer = Root Subject (self-signed)
```

---

## Still Having Issues?

### Run Complete Diagnostic

```bash
# Save this as debug_cert.sh and run it
cat > /tmp/debug_cert.sh << 'EOF'
#!/bin/bash
echo "=== Server Certificate Details ==="
openssl x509 -in /etc/bindplane/ssl/server.crt -noout -text | \
  grep -A2 "Issuer:\|Subject:\|Not Before\|Not After\|Authority Information"

echo ""
echo "=== CA Bundle Certificate Count ==="
grep -c "BEGIN CERTIFICATE" /etc/bindplane/ssl/ca-bundle.crt

echo ""
echo "=== CA Bundle Certificates ==="
csplit -s -f /tmp/ca- /etc/bindplane/ssl/ca-bundle.crt '/BEGIN CERTIFICATE/' '{*}'
i=1
for f in /tmp/ca-*; do
    if [ -s "$f" ] && grep -q "BEGIN" "$f"; then
        echo "--- Certificate $i ---"
        openssl x509 -in "$f" -noout -subject -issuer 2>/dev/null || echo "Invalid cert"
        i=$((i+1))
    fi
done
rm -f /tmp/ca-*

echo ""
echo "=== Chain Verification ==="
openssl verify -CAfile /etc/bindplane/ssl/ca-bundle.crt \
  /etc/bindplane/ssl/server.crt 2>&1

echo ""
echo "=== Match Check ==="
SERVER_ISSUER=$(openssl x509 -in /etc/bindplane/ssl/server.crt -noout -issuer | sed 's/issuer=//')
echo "Server certificate issued by: $SERVER_ISSUER"
echo ""
echo "CA bundle contains:"
csplit -s -f /tmp/ca- /etc/bindplane/ssl/ca-bundle.crt '/BEGIN CERTIFICATE/' '{*}'
for f in /tmp/ca-*; do
    if [ -s "$f" ] && grep -q "BEGIN" "$f"; then
        SUBJECT=$(openssl x509 -in "$f" -noout -subject 2>/dev/null | sed 's/subject=//')
        echo "  - $SUBJECT"
        if [ "$SERVER_ISSUER" = "$SUBJECT" ]; then
            echo "    ✓ MATCHES server issuer!"
        fi
    fi
done
rm -f /tmp/ca-*
EOF

bash /tmp/debug_cert.sh
```

**Send this output when requesting help.**

---

## Related Documentation

- **[Verify TLS Certificates](./VERIFY_TLS_CERTIFICATES.md)** - Quick verification commands
- **[WSS Intermediate CA Implementation](./wss-intermediate-ca-implementation.md)** - Full setup guide
- **[Troubleshooting Section](./wss-intermediate-ca-implementation.md#troubleshooting)** - More troubleshooting scenarios

---

**Last Updated:** 2026-01-06
**Version:** 1.0
