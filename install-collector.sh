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
echo "Creating ObservIQ collector service user..."
if ! id -u $SERVICE_USER >/dev/null 2>&1; then
  sudo useradd -r -m -d /var/lib/observiq-otel-collector -s /bin/false -c "ObservIQ Collector Service User" $SERVICE_USER
  echo "✓ Created $SERVICE_USER user"
else
  echo "✓ User $SERVICE_USER already exists"
fi

# Set permissions
echo "Setting permissions..."
sudo chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
sudo chmod +x $INSTALL_DIR/observiq-otel-collector

# Create SSL directory
sudo mkdir -p $INSTALL_DIR/ssl
sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/ssl

# Create storage directories for file_storage extension
echo "Creating storage directories..."
sudo mkdir -p /var/log/observiq-otel-collector
sudo chown $SERVICE_USER:$SERVICE_USER /var/log/observiq-otel-collector
sudo chmod 755 /var/log/observiq-otel-collector

sudo mkdir -p /var/lib/observiq-otel-collector/storage
sudo chown -R $SERVICE_USER:$SERVICE_USER /var/lib/observiq-otel-collector
sudo chmod 755 /var/lib/observiq-otel-collector/storage

sudo mkdir -p /storage
sudo chown -R $SERVICE_USER:$SERVICE_USER /storage
sudo chmod 755 /storage

# Create manager.yaml with unique agent ID
echo ""
echo "=== BindPlane OpAMP Configuration ==="
echo ""
MY_AGENT_ID=$(cat /proc/sys/kernel/random/uuid)
echo "Generated unique Agent ID: $MY_AGENT_ID"
echo ""

# Ask if user wants to provide BindPlane endpoint and secret key
read -p "Do you want to configure BindPlane endpoint and secret key now? (yes/no): " CONFIGURE_NOW

if [ "$CONFIGURE_NOW" = "yes" ]; then
    echo ""
    echo "Please provide the following information from your BindPlane server:"
    echo ""

    # Get endpoint
    read -p "Enter BindPlane OpAMP endpoint (e.g., ws://10.10.0.7:3001/v1/opamp): " OPAMP_ENDPOINT

    # Validate endpoint is not empty
    while [ -z "$OPAMP_ENDPOINT" ]; do
        echo "⚠️  Endpoint cannot be empty"
        read -p "Enter BindPlane OpAMP endpoint: " OPAMP_ENDPOINT
    done

    # Get secret key
    read -p "Enter BindPlane secret key: " SECRET_KEY

    # Validate secret key is not empty
    while [ -z "$SECRET_KEY" ]; do
        echo "⚠️  Secret key cannot be empty"
        read -p "Enter BindPlane secret key: " SECRET_KEY
    done

    echo ""
    echo "Configuration summary:"
    echo "  Endpoint: $OPAMP_ENDPOINT"
    echo "  Secret Key: ${SECRET_KEY:0:10}... (masked)"
    echo "  Agent ID: $MY_AGENT_ID"
    echo ""
else
    # Use default values
    OPAMP_ENDPOINT="ws://10.10.0.7:3001/v1/opamp"
    SECRET_KEY="YOUR_SECRET_KEY_HERE"
    echo ""
    echo "⚠️  Using default placeholder values."
    echo "   You will need to update manager.yaml manually after installation."
    echo ""
fi

# Create manager.yaml
echo "Creating manager.yaml configuration..."
sudo sh -c "cat > $INSTALL_DIR/manager.yaml <<EOF
endpoint: \"$OPAMP_ENDPOINT\"
secret_key: \"$SECRET_KEY\"
agent_id: \"$MY_AGENT_ID\"
EOF"

sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/manager.yaml
sudo chmod 644 $INSTALL_DIR/manager.yaml
echo "✓ Created manager.yaml with unique agent ID"

# Update logging configuration
echo "Configuring logging..."
sudo tee $INSTALL_DIR/logging.yaml > /dev/null <<'LOGEOF'
output_paths:
  - /var/log/observiq-otel-collector/collector.log
error_output_paths:
  - /var/log/observiq-otel-collector/collector-error.log
level: info
encoding: console
LOGEOF

sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/logging.yaml

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

# Security hardening with write access to required paths
# ReadWritePaths is critical for BindPlane OpAMP to remotely update manager.yaml
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/observiq-otel-collector /var/log/observiq-otel-collector /var/lib/observiq-otel-collector /storage

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
echo "Enabling service to start on boot..."
sudo systemctl enable observiq-otel-collector

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "✓ Collector installed successfully"
echo "✓ manager.yaml created with unique agent ID: $MY_AGENT_ID"
echo "✓ Service enabled to start on boot"
echo ""

# Show different next steps based on configuration choice
if [ "$CONFIGURE_NOW" = "yes" ]; then
    echo "Configuration Summary:"
    echo "  Endpoint: $OPAMP_ENDPOINT"
    echo "  Agent ID: $MY_AGENT_ID"
    echo ""
    echo "Next steps:"
    echo "1. Start the collector service:"
    echo "   sudo systemctl start observiq-otel-collector"
    echo ""
    echo "2. Verify the service status:"
    echo "   sudo systemctl status observiq-otel-collector"
    echo ""
    echo "3. Check that the collector appears in BindPlane UI:"
    echo "   Navigate to your BindPlane server and verify the agent is connected"
    echo ""
    echo "4. View real-time logs:"
    echo "   sudo journalctl -u observiq-otel-collector -f"
    echo ""
    echo "5. (Optional) Deploy TLS certificates to $INSTALL_DIR/ssl/"
else
    echo "⚠️  Configuration Required:"
    echo ""
    echo "Next steps:"
    echo "1. Update manager.yaml with your BindPlane endpoint and secret key:"
    echo "   sudo nano $INSTALL_DIR/manager.yaml"
    echo ""
    echo "   Get these values from BindPlane UI:"
    echo "   - Navigate to: Settings → Installation"
    echo "   - Copy the endpoint (ws://YOUR_SERVER:3001/v1/opamp)"
    echo "   - Copy the secret key"
    echo ""
    echo "2. Start the collector service:"
    echo "   sudo systemctl start observiq-otel-collector"
    echo ""
    echo "3. Verify the service status:"
    echo "   sudo systemctl status observiq-otel-collector"
    echo ""
    echo "4. Check logs for connection status:"
    echo "   sudo journalctl -u observiq-otel-collector -f"
fi
echo ""
echo "Troubleshooting:"
echo "  View configuration: cat $INSTALL_DIR/manager.yaml"
echo "  Check permissions: ls -la $INSTALL_DIR/"
if [ "$CONFIGURE_NOW" = "yes" ]; then
    # Extract hostname and port from endpoint
    MGMT_HOST=$(echo "$OPAMP_ENDPOINT" | sed -E 's|^wss?://([^:/]+).*|\1|')
    MGMT_PORT=$(echo "$OPAMP_ENDPOINT" | sed -E 's|^wss?://[^:]+:([0-9]+).*|\1|')
    OPAMP_PATH=$(echo "$OPAMP_ENDPOINT" | sed -E 's|^wss?://[^/]+(/.*)|\1|')

    # Determine HTTP protocol based on WebSocket protocol
    if [[ "$OPAMP_ENDPOINT" == wss://* ]]; then
        HTTP_PROTOCOL="https"
    else
        HTTP_PROTOCOL="http"
    fi

    echo "  Test TCP connectivity: nc -zv $MGMT_HOST ${MGMT_PORT:-3001} || telnet $MGMT_HOST ${MGMT_PORT:-3001}"
    echo "  Test OpAMP endpoint: curl -v $HTTP_PROTOCOL://$MGMT_HOST:${MGMT_PORT:-3001}${OPAMP_PATH} 2>&1 | grep -i 'connected\\|upgrade'"
    echo "  Check service logs: sudo journalctl -u observiq-otel-collector -n 50 --no-pager"
else
    echo "  Test TCP connectivity: nc -zv 10.10.0.7 3001 || telnet 10.10.0.7 3001"
    echo "  Test OpAMP endpoint: curl -v http://10.10.0.7:3001/v1/opamp 2>&1 | grep -i 'connected\\|upgrade'"
    echo "  Check service logs: sudo journalctl -u observiq-otel-collector -n 50 --no-pager"
fi
echo ""
