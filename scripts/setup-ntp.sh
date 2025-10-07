#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== NTP Setup Script ===${NC}"
echo "This script configures chrony NTP on both EC2 instances"
echo ""

# Load resource IDs
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    echo "Please run setup-vpc.sh and setup-ec2.sh first"
    exit 1
fi

source $RESOURCE_FILE

# Check if instance IPs are available
if [ -z "$TOKYO_PUBLIC_IP" ] || [ -z "$FRANKFURT_PUBLIC_IP" ]; then
    echo -e "${RED}Error: Instance IPs not found in $RESOURCE_FILE${NC}"
    echo "Please run setup-ec2.sh first"
    exit 1
fi

# SSH key configuration
KEY_NAME="${KEY_NAME:-binance-latency-key}"
SSH_KEY="$HOME/.ssh/$KEY_NAME.pem"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    echo "Please ensure your SSH key is available"
    exit 1
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "Tokyo Instance: $TOKYO_PUBLIC_IP"
echo "Frankfurt Instance: $FRANKFURT_PUBLIC_IP"
echo ""

# Function to setup NTP on an instance
setup_ntp() {
    local HOST=$1
    local NAME=$2
    
    echo -e "${YELLOW}Setting up NTP on $NAME instance...${NC}"
    
    # Install chrony
    ssh $SSH_OPTS ec2-user@$HOST "sudo yum install -y chrony" || {
        echo -e "${RED}Failed to install chrony on $NAME${NC}"
        return 1
    }
    
    # Start and enable chrony service
    ssh $SSH_OPTS ec2-user@$HOST "sudo systemctl start chronyd && sudo systemctl enable chronyd" || {
        echo -e "${RED}Failed to start chrony on $NAME${NC}"
        return 1
    }
    
    # Wait for chrony to sync
    echo -e "${YELLOW}Waiting for time synchronization on $NAME...${NC}"
    sleep 5
    
    # Force immediate sync
    ssh $SSH_OPTS ec2-user@$HOST "sudo chronyc makestep" || true
    
    sleep 3
    
    echo -e "${GREEN}✓ NTP configured on $NAME${NC}"
}

# Function to verify NTP sync
verify_ntp() {
    local HOST=$1
    local NAME=$2
    
    echo -e "${YELLOW}Verifying NTP sync on $NAME...${NC}"
    
    # Get tracking info
    TRACKING=$(ssh $SSH_OPTS ec2-user@$HOST "chronyc tracking" 2>/dev/null || echo "Failed")
    
    if [ "$TRACKING" = "Failed" ]; then
        echo -e "${RED}✗ Failed to get NTP status on $NAME${NC}"
        return 1
    fi
    
    echo "$TRACKING"
    
    # Check if synchronized
    if echo "$TRACKING" | grep -q "Leap status.*Normal"; then
        echo -e "${GREEN}✓ $NAME is synchronized${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ $NAME may not be fully synchronized yet${NC}"
        return 0
    fi
}

# Setup NTP on Tokyo instance
setup_ntp "$TOKYO_PUBLIC_IP" "Tokyo"
echo ""

# Setup NTP on Frankfurt instance
setup_ntp "$FRANKFURT_PUBLIC_IP" "Frankfurt"
echo ""

# Wait a bit for sync to stabilize
echo -e "${YELLOW}Waiting for NTP synchronization to stabilize...${NC}"
sleep 10
echo ""

# Verify NTP sync on both instances
echo -e "${GREEN}=== NTP Verification ===${NC}"
echo ""

echo "Tokyo Instance:"
verify_ntp "$TOKYO_PUBLIC_IP" "Tokyo"
echo ""

echo "Frankfurt Instance:"
verify_ntp "$FRANKFURT_PUBLIC_IP" "Frankfurt"
echo ""

echo -e "${GREEN}=== NTP Setup Complete ===${NC}"
echo ""
echo -e "${YELLOW}Important: NTP synchronization may take a few minutes to fully stabilize${NC}"
echo "You can verify sync status at any time by running:"
echo "  ssh $SSH_OPTS ec2-user@$TOKYO_PUBLIC_IP 'chronyc tracking'"
echo "  ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP 'chronyc tracking'"
echo ""
echo -e "${YELLOW}Next step: Run deploy.sh to build and deploy the Rust applications${NC}"
