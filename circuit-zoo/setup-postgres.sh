#!/bin/bash
# Configure Postgres for local network access from Odroid cluster
set -e

DESKTOP_IP="192.168.4.25"
LOCAL_NETWORK="192.168.0.0/16"

echo "=== Configuring Postgres for Local Network Access ==="
echo

# Find postgres config directory
PG_CONF_DIR=$(ls -d /etc/postgresql/*/main 2>/dev/null | head -1)
if [[ -z "$PG_CONF_DIR" ]]; then
    echo "Error: Could not find PostgreSQL config directory"
    exit 1
fi

echo "Found PostgreSQL config at: $PG_CONF_DIR"

# Backup configs
echo "Backing up configuration files..."
sudo cp "$PG_CONF_DIR/postgresql.conf" "$PG_CONF_DIR/postgresql.conf.backup.$(date +%Y%m%d)"
sudo cp "$PG_CONF_DIR/pg_hba.conf" "$PG_CONF_DIR/pg_hba.conf.backup.$(date +%Y%m%d)"

# Update listen_addresses in postgresql.conf
echo "Updating listen_addresses..."
if grep -q "^listen_addresses" "$PG_CONF_DIR/postgresql.conf"; then
    sudo sed -i "s/^listen_addresses.*/listen_addresses = 'localhost,$DESKTOP_IP'/" "$PG_CONF_DIR/postgresql.conf"
else
    sudo sed -i "s/^#listen_addresses.*/listen_addresses = 'localhost,$DESKTOP_IP'/" "$PG_CONF_DIR/postgresql.conf"
fi

# Add pg_hba.conf rule for local network (if not already present)
echo "Adding pg_hba.conf rule for local network..."
if ! grep -q "$LOCAL_NETWORK" "$PG_CONF_DIR/pg_hba.conf"; then
    # Add before the first "host" line
    sudo sed -i "/^# IPv4 local connections:/a host    samuel          samuel          $LOCAL_NETWORK          trust" "$PG_CONF_DIR/pg_hba.conf"
fi

# Restart postgres
echo "Restarting PostgreSQL..."
sudo systemctl restart postgresql

# Wait a moment for it to start
sleep 2

# Verify
echo
echo "Verifying configuration..."
echo "Listening on:"
ss -tlnp | grep 5432 || echo "  (check with: sudo ss -tlnp | grep 5432)"

echo
echo "Testing local connection..."
psql -d samuel -c "SELECT 'Postgres is working!' as status;" 2>/dev/null || echo "Local connection test failed"

echo
echo "=== Configuration Complete ==="
echo
echo "Postgres is now listening on $DESKTOP_IP:5432"
echo "Connections allowed from $LOCAL_NETWORK"
echo
echo "Test from a cluster node with:"
echo "  ssh admin@node1.local \"psql -h $DESKTOP_IP -U samuel -d samuel -c 'SELECT 1;'\""
