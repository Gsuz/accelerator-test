#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VPC Peering Setup Script ===${NC}"
echo "This script creates VPC peering between Tokyo and Frankfurt"
echo ""

# Load resource IDs from VPC setup
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    echo "Please run setup-vpc.sh first"
    exit 1
fi

source $RESOURCE_FILE

# Regions
TOKYO_REGION="ap-northeast-1"
FRANKFURT_REGION="eu-central-1"

# Peering configuration
PEERING_NAME="tokyo-frankfurt-peering"

echo "Tokyo VPC: $TOKYO_VPC_ID"
echo "Frankfurt VPC: $FRANKFURT_VPC_ID"
echo ""

echo -e "${YELLOW}Creating VPC peering connection...${NC}"

# Create VPC peering connection from Tokyo to Frankfurt
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
    --vpc-id $TOKYO_VPC_ID \
    --peer-vpc-id $FRANKFURT_VPC_ID \
    --peer-region $FRANKFURT_REGION \
    --region $TOKYO_REGION \
    --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=$PEERING_NAME}]" \
    --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
    --output text)

echo -e "${GREEN}✓ VPC peering connection created: $PEERING_ID${NC}"

# Wait a moment for the peering connection to be available
sleep 3

echo -e "${YELLOW}Accepting VPC peering connection in Frankfurt...${NC}"

# Accept the peering connection in Frankfurt region
aws ec2 accept-vpc-peering-connection \
    --vpc-peering-connection-id $PEERING_ID \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ VPC peering connection accepted${NC}"

# Wait for peering connection to become active
echo -e "${YELLOW}Waiting for peering connection to become active...${NC}"
aws ec2 wait vpc-peering-connection-exists \
    --vpc-peering-connection-ids $PEERING_ID \
    --region $TOKYO_REGION

sleep 5

echo -e "${GREEN}✓ VPC peering connection is active${NC}"
echo ""

echo -e "${YELLOW}Updating Tokyo route table...${NC}"

# Add route to Frankfurt VPC in Tokyo route table (or replace if exists)
if aws ec2 describe-route-tables \
    --route-table-ids $TOKYO_RT_ID \
    --region $TOKYO_REGION \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='10.1.0.0/16']" \
    --output text | grep -q "10.1.0.0/16"; then
    echo "Route already exists, replacing..."
    aws ec2 replace-route \
        --route-table-id $TOKYO_RT_ID \
        --destination-cidr-block 10.1.0.0/16 \
        --vpc-peering-connection-id $PEERING_ID \
        --region $TOKYO_REGION
else
    aws ec2 create-route \
        --route-table-id $TOKYO_RT_ID \
        --destination-cidr-block 10.1.0.0/16 \
        --vpc-peering-connection-id $PEERING_ID \
        --region $TOKYO_REGION
fi

echo -e "${GREEN}✓ Tokyo route table updated (10.1.0.0/16 → $PEERING_ID)${NC}"

echo -e "${YELLOW}Updating Frankfurt route table...${NC}"

# Add route to Tokyo VPC in Frankfurt route table (or replace if exists)
if aws ec2 describe-route-tables \
    --route-table-ids $FRANKFURT_RT_ID \
    --region $FRANKFURT_REGION \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='10.0.0.0/16']" \
    --output text | grep -q "10.0.0.0/16"; then
    echo "Route already exists, replacing..."
    aws ec2 replace-route \
        --route-table-id $FRANKFURT_RT_ID \
        --destination-cidr-block 10.0.0.0/16 \
        --vpc-peering-connection-id $PEERING_ID \
        --region $FRANKFURT_REGION
else
    aws ec2 create-route \
        --route-table-id $FRANKFURT_RT_ID \
        --destination-cidr-block 10.0.0.0/16 \
        --vpc-peering-connection-id $PEERING_ID \
        --region $FRANKFURT_REGION
fi

echo -e "${GREEN}✓ Frankfurt route table updated (10.0.0.0/16 → $PEERING_ID)${NC}"
echo ""

# Append peering ID to resource file
echo "" >> $RESOURCE_FILE
echo "PEERING_ID=$PEERING_ID" >> $RESOURCE_FILE

echo -e "${GREEN}=== VPC Peering Setup Complete ===${NC}"
echo ""
echo "Peering Connection ID: $PEERING_ID"
echo ""
echo "Route configuration:"
echo "  Tokyo → Frankfurt: 10.1.0.0/16 via $PEERING_ID"
echo "  Frankfurt → Tokyo: 10.0.0.0/16 via $PEERING_ID"
echo ""
echo -e "${YELLOW}Next step: Run setup-ec2.sh to launch EC2 instances${NC}"
