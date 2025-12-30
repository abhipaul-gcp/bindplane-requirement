#!/bin/bash
# Complete uninstallation script for BindPlane Management Server and PostgreSQL
# WARNING: This will remove ALL BindPlane data, configurations, and database

set -euo pipefail

echo "======================================"
echo "BindPlane Management Server Uninstallation"
echo "======================================"
echo ""
echo "⚠️  WARNING: This will completely remove:"
echo "  - BindPlane server and all configurations"
echo "  - PostgreSQL 16 and ALL databases"
echo "  - All collected telemetry data"
echo "  - All user accounts and settings"
echo ""

# Confirmation prompt
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
read -p "Create a database backup before uninstalling? (yes/no): " BACKUP
if [ "$BACKUP" = "yes" ]; then
    BACKUP_FILE="/tmp/bindplane_backup_$(date +%Y%m%d_%H%M%S).sql"
    echo "Creating database backup..."
    sudo -u postgres pg_dump bindplane > "$BACKUP_FILE" 2>/dev/null || echo "⚠️  Backup failed or database doesn't exist"
    if [ -f "$BACKUP_FILE" ]; then
        echo "✓ Backup saved to: $BACKUP_FILE"
    fi
fi

echo ""
echo "1. Stopping BindPlane service..."
echo "--------------------------------------"
if systemctl is-active --quiet bindplane 2>/dev/null; then
    sudo systemctl stop bindplane
    echo "✓ BindPlane service stopped"
fi

if systemctl is-enabled --quiet bindplane 2>/dev/null; then
    sudo systemctl disable bindplane
    echo "✓ BindPlane service disabled"
fi

echo ""
echo "2. Stopping PostgreSQL service..."
echo "--------------------------------------"
if systemctl is-active --quiet postgresql-16 2>/dev/null; then
    sudo systemctl stop postgresql-16
    echo "✓ PostgreSQL stopped"
fi

if systemctl is-enabled --quiet postgresql-16 2>/dev/null; then
    sudo systemctl disable postgresql-16
    echo "✓ PostgreSQL disabled"
fi

echo ""
echo "3. Removing BindPlane RPM package..."
echo "--------------------------------------"
if rpm -q bindplane-ee >/dev/null 2>&1; then
    sudo rpm -e bindplane-ee
    echo "✓ BindPlane package removed"
else
    echo "BindPlane package not installed"
fi

echo ""
echo "4. Removing PostgreSQL packages..."
echo "--------------------------------------"
if rpm -q postgresql16-server >/dev/null 2>&1; then
    sudo dnf remove -y postgresql16* pgdg-redhat-repo 2>/dev/null || \
    sudo rpm -e postgresql16-server postgresql16-contrib postgresql16 postgresql16-libs 2>/dev/null
    echo "✓ PostgreSQL packages removed"
else
    echo "PostgreSQL packages not installed"
fi

echo ""
echo "5. Removing BindPlane directories..."
echo "--------------------------------------"
sudo rm -rf /var/lib/bindplane
sudo rm -rf /etc/bindplane
sudo rm -rf /opt/bindplane
echo "✓ BindPlane directories removed"

echo ""
echo "6. Removing PostgreSQL data directory..."
echo "--------------------------------------"
sudo rm -rf /var/lib/pgsql
echo "✓ PostgreSQL data removed"

echo ""
echo "7. Removing systemd service files..."
echo "--------------------------------------"
sudo rm -f /etc/systemd/system/bindplane.service
sudo rm -f /usr/lib/systemd/system/postgresql-16.service
sudo systemctl daemon-reload
sudo systemctl reset-failed
echo "✓ Service files removed"

echo ""
echo "8. Removing service users..."
echo "--------------------------------------"

# Remove bindplane user
if id bindplane >/dev/null 2>&1; then
    sudo pkill -u bindplane || true
    sleep 2
    sudo userdel -r bindplane 2>/dev/null || sudo userdel bindplane
    echo "✓ Removed user 'bindplane'"
fi

# Remove postgres user
if id postgres >/dev/null 2>&1; then
    sudo pkill -u postgres || true
    sleep 2
    sudo userdel -r postgres 2>/dev/null || sudo userdel postgres
    echo "✓ Removed user 'postgres'"
fi

echo ""
echo "9. Removing package directory (optional)..."
echo "--------------------------------------"
if [ -d /opt/bindplane-packages/management ]; then
    read -p "Remove package directory? (yes/no): " REMOVE_PKG
    if [ "$REMOVE_PKG" = "yes" ]; then
        sudo rm -rf /opt/bindplane-packages/management
        echo "✓ Removed package directory"
    fi
fi

echo ""
echo "10. Cleaning up PostgreSQL repository..."
echo "--------------------------------------"
if [ -f /etc/yum.repos.d/pgdg-redhat-all.repo ]; then
    sudo rm -f /etc/yum.repos.d/pgdg-redhat-all.repo
    echo "✓ Removed PostgreSQL repository"
fi

echo ""
echo "======================================"
echo "Uninstallation Complete!"
echo "======================================"
echo ""
echo "The following have been removed:"
echo "  ✓ BindPlane server and configuration"
echo "  ✓ PostgreSQL 16 and all databases"
echo "  ✓ All service users (bindplane, postgres)"
echo "  ✓ All data directories"
echo ""
if [ -f "$BACKUP_FILE" ]; then
    echo "Database backup saved at: $BACKUP_FILE"
    echo ""
fi
echo "You can now perform a fresh installation if needed."
echo ""
