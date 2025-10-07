#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VPC Peering vs Public Internet Test ===${NC}"
echo ""

# Load resource IDs
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    exit 1
fi

source $RESOURCE_FILE

# SSH key configuration
KEY_NAME="${KEY_NAME:-binance-latency-key}"
SSH_KEY="$HOME/.ssh/$KEY_NAME.pem"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "Tokyo Instance:"
echo "  Public IP: $TOKYO_PUBLIC_IP"
echo "  Private IP: $TOKYO_PRIVATE_IP"
echo ""
echo "Frankfurt Instance:"
echo "  Public IP: $FRANKFURT_PUBLIC_IP"
echo "  Private IP: $FRANKFURT_PRIVATE_IP"
echo ""

# Test 1: Ping via VPC Peering (private IPs)
echo -e "${BLUE}=== Test 1: Tokyo → Frankfurt via VPC Peering (Private Network) ===${NC}"
echo "Pinging Frankfurt private IP ($FRANKFURT_PRIVATE_IP) from Tokyo..."
echo ""

ssh $SSH_OPTS ec2-user@$TOKYO_PUBLIC_IP << EOF
echo "Running ping test via VPC peering..."
ping -c 10 $FRANKFURT_PRIVATE_IP | tail -n 2
echo ""
echo "Checking route to Frankfurt private IP:"
ip route get $FRANKFURT_PRIVATE_IP
EOF

echo ""
echo -e "${BLUE}=== Test 2: Tokyo → Frankfurt via Public Internet ===${NC}"
echo "Pinging Frankfurt public IP ($FRANKFURT_PUBLIC_IP) from Tokyo..."
echo ""

ssh $SSH_OPTS ec2-user@$TOKYO_PUBLIC_IP << EOF
echo "Running ping test via public internet..."
ping -c 10 $FRANKFURT_PUBLIC_IP | tail -n 2
echo ""
echo "Checking route to Frankfurt public IP:"
ip route get $FRANKFURT_PUBLIC_IP
EOF

echo ""
echo -e "${BLUE}=== Test 3: Frankfurt → Tokyo via VPC Peering (Private Network) ===${NC}"
echo "Pinging Tokyo private IP ($TOKYO_PRIVATE_IP) from Frankfurt..."
echo ""

ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP << EOF
echo "Running ping test via VPC peering..."
ping -c 10 $TOKYO_PRIVATE_IP | tail -n 2
echo ""
echo "Checking route to Tokyo private IP:"
ip route get $TOKYO_PRIVATE_IP
EOF

echo ""
echo -e "${BLUE}=== Test 4: Frankfurt → Tokyo via Public Internet ===${NC}"
echo "Pinging Tokyo public IP ($TOKYO_PUBLIC_IP) from Frankfurt..."
echo ""

ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP << EOF
echo "Running ping test via public internet..."
ping -c 10 $TOKYO_PUBLIC_IP | tail -n 2
echo ""
echo "Checking route to Tokyo public IP:"
ip route get $TOKYO_PUBLIC_IP
EOF

echo ""
echo -e "${GREEN}=== Verification: Check VPC Peering Routes ===${NC}"
echo ""

echo "Tokyo VPC Route Table:"
aws ec2 describe-route-tables \
    --route-table-ids $TOKYO_RT_ID \
    --region ap-northeast-1 \
    --query 'RouteTables[0].Routes[?VpcPeeringConnectionId!=`null`]' \
    --output table

echo ""
echo "Frankfurt VPC Route Table:"
aws ec2 describe-route-tables \
    --route-table-ids $FRANKFURT_RT_ID \
    --region eu-central-1 \
    --query 'RouteTables[0].Routes[?VpcPeeringConnectionId!=`null`]' \
    --output table

echo ""
echo -e "${GREEN}=== VPC Peering Status ===${NC}"
aws ec2 describe-vpc-peering-connections \
    --vpc-peering-connection-ids $PEERING_ID \
    --region ap-northeast-1 \
    --query 'VpcPeeringConnections[0].[VpcPeeringConnectionId,Status.Code,RequesterVpcInfo.CidrBlock,AccepterVpcInfo.CidrBlock]' \
    --output table

echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "- Private IP pings use VPC peering (AWS backbone)"
echo "- Public IP pings use public internet"
echo "- Compare the latencies to see which is faster"
echo "- Check 'ip route get' output to verify routing"
