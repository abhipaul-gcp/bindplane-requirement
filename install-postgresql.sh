#!/bin/bash
# PostgreSQL 16 Installation Script for BindPlane
# For RHEL 9.x offline installation (no internet required)
# Complete database server setup with resilient error handling
#
# This script can be safely re-run if interrupted - it will detect
# existing state and skip completed steps.

set -euo pipefail

PACKAGE_DIR="/tmp/bindplane-packages/management"
PGDATA="/var/lib/pgsql/16/data"
PGVERSION="16"

echo "=== PostgreSQL 16 Installation for BindPlane (Offline Mode) ==="
echo "Package directory: $PACKAGE_DIR"
echo ""

# Verify package directory exists
if [ ! -d "$PACKAGE_DIR" ]; then
  echo "ERROR: Package directory $PACKAGE_DIR does not exist!"
  exit 1
fi

# Verify required RPM files exist
echo "Verifying required PostgreSQL packages..."
REQUIRED_PACKAGES=(
  "postgresql16-libs-16"
  "postgresql16-16"
  "postgresql16-server-16"
  "postgresql16-contrib-16"
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! ls $PACKAGE_DIR/${pkg}.*.rpm 1> /dev/null 2>&1; then
    echo "ERROR: Required package ${pkg}.*.rpm not found in $PACKAGE_DIR"
    exit 1
  fi
done
echo "✓ All required packages found"

# Disable PostgreSQL modules (RHEL 9 specific)
echo ""
echo "Disabling PostgreSQL AppStream module..."
sudo dnf -qy module disable postgresql 2>/dev/null || true

# Install PostgreSQL 16 packages from local RPMs (no internet needed)
echo ""
echo "Installing PostgreSQL 16 packages from local RPMs..."

# Check if packages are already installed
if rpm -q postgresql16-server &>/dev/null; then
  echo "⚠ PostgreSQL 16 packages appear to be already installed"
  read -p "Do you want to reinstall/upgrade? (yes/NO): " REINSTALL

  if [ "$REINSTALL" = "yes" ]; then
    echo "Reinstalling PostgreSQL 16 packages..."
    sudo rpm -Uvh --force \
      $PACKAGE_DIR/postgresql16-libs-16.*.rpm \
      $PACKAGE_DIR/postgresql16-16.*.rpm \
      $PACKAGE_DIR/postgresql16-server-16.*.rpm \
      $PACKAGE_DIR/postgresql16-contrib-16.*.rpm
    echo "✓ PostgreSQL 16 packages reinstalled"
  else
    echo "Skipping package installation..."
  fi
else
  echo "Installing PostgreSQL 16 packages..."
  sudo rpm -ivh \
    $PACKAGE_DIR/postgresql16-libs-16.*.rpm \
    $PACKAGE_DIR/postgresql16-16.*.rpm \
    $PACKAGE_DIR/postgresql16-server-16.*.rpm \
    $PACKAGE_DIR/postgresql16-contrib-16.*.rpm
  echo "✓ PostgreSQL 16 packages installed"
fi

# Verify postgres user exists, create if needed
echo ""
if ! id postgres &>/dev/null; then
  echo "Creating postgres system user..."
  sudo useradd -r -m -d /var/lib/pgsql -s /bin/bash -c "PostgreSQL Server" postgres
  echo "✓ postgres system user created"
else
  echo "✓ postgres system user already exists"
fi

# Initialize PostgreSQL database cluster
echo ""
echo "Initializing PostgreSQL database cluster..."
if [ -f "$PGDATA/PG_VERSION" ]; then
  echo "⚠ Database cluster already initialized at $PGDATA"
  read -p "Do you want to reinitialize? This will DELETE all data! (yes/NO): " confirm
  if [ "$confirm" = "yes" ]; then
    sudo systemctl stop postgresql-16 || true
    sudo rm -rf $PGDATA
    # Use direct initdb command instead of postgresql-16-setup
    sudo mkdir -p $PGDATA
    sudo chown -R postgres:postgres /var/lib/pgsql/16
    sudo -u postgres /usr/pgsql-16/bin/initdb -D $PGDATA
    echo "✓ Database cluster reinitialized"
  else
    echo "Skipping initialization..."
  fi
else
  # Use direct initdb command instead of postgresql-16-setup to avoid PGDATA errors
  echo "Creating data directory..."
  sudo mkdir -p $PGDATA
  sudo chown -R postgres:postgres /var/lib/pgsql/16

  echo "Running initdb..."
  sudo -u postgres /usr/pgsql-16/bin/initdb -D $PGDATA
  echo "✓ Database cluster initialized"
fi

# Configure PostgreSQL for BindPlane
echo ""
echo "Configuring PostgreSQL settings for production workload..."

# Check if configuration already applied
if grep -q "BindPlane Production Configuration" $PGDATA/postgresql.conf 2>/dev/null; then
  echo "⚠ BindPlane configuration already exists in postgresql.conf"
  read -p "Do you want to reapply configuration? (yes/NO): " RECONFIG

  if [ "$RECONFIG" = "yes" ]; then
    # Restore from backup or create new
    if [ -f "$PGDATA/postgresql.conf.backup."* ]; then
      LATEST_BACKUP=$(ls -t $PGDATA/postgresql.conf.backup.* | head -1)
      sudo cp $LATEST_BACKUP $PGDATA/postgresql.conf
      echo "✓ Restored configuration from backup: $LATEST_BACKUP"
    fi
  else
    echo "Skipping configuration update..."
  fi
fi

# Backup original postgresql.conf if not already backed up
if [ ! -f "$PGDATA/postgresql.conf.original" ]; then
  sudo cp $PGDATA/postgresql.conf $PGDATA/postgresql.conf.original
fi
sudo cp $PGDATA/postgresql.conf $PGDATA/postgresql.conf.backup.$(date +%Y%m%d_%H%M%S)

# Apply production-grade PostgreSQL settings for 2 TB/day workload
sudo tee -a $PGDATA/postgresql.conf > /dev/null <<'EOF'

# ========================================
# BindPlane Production Configuration
# For 2 TB/day workload (8 GB RAM, 4 vCPU)
# ========================================

# Connection Settings
listen_addresses = 'localhost'          # Listen on localhost only (security)
port = 5432
max_connections = 100                   # BindPlane default

# Memory Settings (optimized for 8 GB RAM)
shared_buffers = 2GB                    # 25% of RAM
effective_cache_size = 6GB              # 75% of RAM
maintenance_work_mem = 512MB            # For VACUUM, CREATE INDEX
work_mem = 20MB                         # Per operation (100 connections max)

# WAL (Write-Ahead Log) Settings
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB
checkpoint_completion_target = 0.9

# Query Planner
random_page_cost = 1.1                  # Assume SSD storage
effective_io_concurrency = 200          # For SSD

# Logging (for production monitoring)
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%a.log'
log_truncate_on_rotation = on
log_rotation_age = 1d
log_rotation_size = 0
log_line_prefix = '%m [%p] %u@%d '
log_timezone = 'UTC'
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0

# Autovacuum (critical for BindPlane performance)
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05

# Timezone
timezone = 'UTC'

# Locale
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'

# Default encoding
default_text_search_config = 'pg_catalog.english'
EOF

echo "✓ PostgreSQL configuration updated"

# Create systemd service file if it doesn't exist
echo ""
echo "Setting up PostgreSQL systemd service..."
if [ ! -f /usr/lib/systemd/system/postgresql-16.service ]; then
  echo "Creating systemd service file..."
  sudo tee /usr/lib/systemd/system/postgresql-16.service > /dev/null <<'SERVICEEOF'
[Unit]
Description=PostgreSQL 16 database server
Documentation=https://www.postgresql.org/docs/16/static/
After=syslog.target
After=network.target

[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/pgsql/16/data
OOMScoreAdjust=-1000
ExecStart=/usr/pgsql-16/bin/postgres -D ${PGDATA}
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=infinity

[Install]
WantedBy=multi-user.target
SERVICEEOF

  sudo systemctl daemon-reload
  echo "✓ Systemd service file created"
else
  echo "✓ Systemd service file already exists"
fi

# Create tmpfiles.d configuration for /run/postgresql directory
echo ""
echo "Creating tmpfiles.d configuration for PostgreSQL runtime directory..."
sudo tee /usr/lib/tmpfiles.d/postgresql-16.conf > /dev/null <<'TMPFILESEOF'
# PostgreSQL runtime directory
d /run/postgresql 2775 postgres postgres - -
TMPFILESEOF
echo "✓ tmpfiles.d configuration created"

# Ensure /run/postgresql directory exists with correct permissions
echo "Creating PostgreSQL runtime directory..."
sudo mkdir -p /run/postgresql
sudo chown postgres:postgres /run/postgresql
sudo chmod 2775 /run/postgresql
echo "✓ PostgreSQL runtime directory configured"

# Enable and start PostgreSQL
echo ""
echo "Starting PostgreSQL service..."
sudo systemctl enable postgresql-16
sudo systemctl start postgresql-16
sudo systemctl status postgresql-16 --no-pager || true

# Wait for PostgreSQL to be ready
echo ""
echo "Waiting for PostgreSQL to be ready..."
sleep 3

# Verify PostgreSQL is actually running
if ! sudo systemctl is-active --quiet postgresql-16; then
  echo "ERROR: PostgreSQL service is not running!"
  echo "Please check the service status: sudo systemctl status postgresql-16"
  echo "Check logs: sudo journalctl -xeu postgresql-16.service"
  exit 1
fi

echo "✓ PostgreSQL is running"

# Check if bindplane database already exists
echo ""
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw bindplane; then
  echo "⚠  BindPlane database already exists"
  read -p "Do you want to recreate the database? This will DELETE all data! (yes/NO): " RECREATE_DB

  if [ "$RECREATE_DB" = "yes" ]; then
    echo "Dropping existing database and user..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS bindplane;" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS bindplane;" 2>/dev/null || true
    echo "✓ Existing database and user dropped"
    SKIP_DB_CREATION=false
  else
    echo "Skipping database creation..."
    SKIP_DB_CREATION=true
  fi
else
  SKIP_DB_CREATION=false
fi

# Create BindPlane database and user if not skipped
if [ "$SKIP_DB_CREATION" = false ]; then
  echo ""
  echo "Creating BindPlane database and user..."
  read -sp "Enter password for BindPlane database user: " BINDPLANE_DB_PASSWORD
  echo ""
  read -sp "Confirm password: " BINDPLANE_DB_PASSWORD_CONFIRM
  echo ""

  if [ "$BINDPLANE_DB_PASSWORD" != "$BINDPLANE_DB_PASSWORD_CONFIRM" ]; then
    echo "ERROR: Passwords do not match!"
    exit 1
  fi

  if [ -z "$BINDPLANE_DB_PASSWORD" ]; then
    echo "ERROR: Password cannot be empty!"
    exit 1
  fi

  # Create database and user with proper permissions
  sudo -u postgres psql << EOSQL
-- Create BindPlane database user with password
CREATE USER bindplane WITH PASSWORD '$BINDPLANE_DB_PASSWORD';

-- Create BindPlane database with UTF8 encoding
CREATE DATABASE bindplane ENCODING 'UTF8' TEMPLATE template0;

-- Grant CREATE privilege on database to bindplane user
GRANT CREATE ON DATABASE bindplane TO bindplane;

-- Connect to bindplane database
\c bindplane;

-- Grant all privileges on public schema
GRANT ALL PRIVILEGES ON SCHEMA public TO bindplane;

-- Grant privileges on all tables (for future tables)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO bindplane;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO bindplane;

-- Show databases
\l
EOSQL

  echo "✓ BindPlane database and user created"
else
  echo "✓ Using existing BindPlane database"
  # For existing database, we still need password for connection test later
  read -sp "Enter existing BindPlane database password for connection test: " BINDPLANE_DB_PASSWORD
  echo ""
fi

# Configure PostgreSQL authentication (pg_hba.conf)
echo ""
echo "Configuring PostgreSQL authentication..."

# Check if bindplane entry already exists in pg_hba.conf
if sudo grep -q "^host.*bindplane.*bindplane" $PGDATA/pg_hba.conf; then
  echo "✓ pg_hba.conf already configured for BindPlane"
else
  # Backup original pg_hba.conf
  sudo cp $PGDATA/pg_hba.conf $PGDATA/pg_hba.conf.backup.$(date +%Y%m%d_%H%M%S)

  # Add BindPlane authentication rules
  sudo tee -a $PGDATA/pg_hba.conf > /dev/null <<'EOF'

# BindPlane Management Server - Local access only
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    bindplane       bindplane       127.0.0.1/32            scram-sha-256
host    bindplane       bindplane       ::1/128                 scram-sha-256
EOF

  echo "✓ pg_hba.conf updated"
fi

# Restart PostgreSQL to apply authentication changes
echo ""
echo "Restarting PostgreSQL to apply configuration changes..."
sudo systemctl restart postgresql-16
sleep 3

# Test database connection
echo ""
echo "Testing BindPlane database connection..."
PGPASSWORD="$BINDPLANE_DB_PASSWORD" psql -h 127.0.0.1 -U bindplane -d bindplane -c "SELECT version();" > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "✓ Database connection test SUCCESSFUL"
else
  echo "✗ Database connection test FAILED"
  echo "Please check the configuration and try again."
  exit 1
fi

# Display PostgreSQL status
echo ""
echo "=== PostgreSQL Installation Complete ==="
echo ""
sudo systemctl status postgresql-16 --no-pager | head -15

echo ""
echo "PostgreSQL Configuration Summary:"
echo "  • Version: PostgreSQL 16"
echo "  • Listen Address: localhost (127.0.0.1)"
echo "  • Port: 5432"
echo "  • Database: bindplane"
echo "  • User: bindplane"
echo "  • Data Directory: $PGDATA"
echo "  • Configuration: $PGDATA/postgresql.conf"
echo "  • Authentication: $PGDATA/pg_hba.conf"
echo ""
echo "IMPORTANT: Save your database password securely!"
echo "You will need it for BindPlane configuration."
echo ""
echo "Next Step:"
echo "  Run: sudo bash install-linux.sh -f /tmp/bindplane-packages/management/bindplane-ee_linux_amd64.rpm --init"
echo ""
