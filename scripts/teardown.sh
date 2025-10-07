#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Infrastructure Teardown Script ===${NC}"
echo "This script will delete all AWS resources created for the experiment"
echo ""

# Load resource IDs
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    echo "No resources to clean up"
    exit 0
fi

source $RESOURCE_FILE

# Regions
TOKYO_REGION="ap-northeast-1"
FRANKFURT_REGION="eu-central-1"

echo "This will delete the following resources:"
echo ""
echo "Tokyo:"
echo "  - EC2 Instance: $TOKYO_INSTANCE_ID"
echo "  - Security Group: $TOKYO_SG_ID"
echo "  - VPC: $TOKYO_VPC_ID"
echo ""
echo "Frankfurt:"
echo "  - EC2 Instance: $FRANKFURT_INSTANCE_ID"
echo "  - Security Group: $FRANKFURT_SG_ID"
echo "  - VPC: $FRANKFURT_VPC_ID"
echo ""
echo "VPC Peering: $PEERING_ID"
echo ""

read -p "Are you sure you want to delete all resources? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Teardown cancelled"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting teardown...${NC}"
echo ""

# Terminate Tokyo EC2 instance
if [ ! -z "$TOKYO_INSTANCE_ID" ]; then
    echo -e "${YELLOW}Terminating Tokyo EC2 instance...${NC}"
    aws ec2 terminate-instances \
        --instance-ids $TOKYO_INSTANCE_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to terminate Tokyo instance${NC}"
    echo -e "${GREEN}✓ Tokyo instance termination initiated${NC}"
fi

# Terminate Frankfurt EC2 instance
if [ ! -z "$FRANKFURT_INSTANCE_ID" ]; then
    echo -e "${YELLOW}Terminating Frankfurt EC2 instance...${NC}"
    aws ec2 terminate-instances \
        --instance-ids $FRANKFURT_INSTANCE_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to terminate Frankfurt instance${NC}"
    echo -e "${GREEN}✓ Frankfurt instance termination initiated${NC}"
fi

# Wait for instances to terminate
if [ ! -z "$TOKYO_INSTANCE_ID" ]; then
    echo -e "${YELLOW}Waiting for Tokyo instance to terminate...${NC}"
    aws ec2 wait instance-terminated \
        --instance-ids $TOKYO_INSTANCE_ID \
        --region $TOKYO_REGION || echo -e "${RED}Timeout waiting for Tokyo instance${NC}"
    echo -e "${GREEN}✓ Tokyo instance terminated${NC}"
fi

if [ ! -z "$FRANKFURT_INSTANCE_ID" ]; then
    echo -e "${YELLOW}Waiting for Frankfurt instance to terminate...${NC}"
    aws ec2 wait instance-terminated \
        --instance-ids $FRANKFURT_INSTANCE_ID \
        --region $FRANKFURT_REGION || echo -e "${RED}Timeout waiting for Frankfurt instance${NC}"
    echo -e "${GREEN}✓ Frankfurt instance terminated${NC}"
fi

echo ""

# Delete VPC peering connection
if [ ! -z "$PEERING_ID" ]; then
    echo -e "${YELLOW}Deleting VPC peering connection...${NC}"
    aws ec2 delete-vpc-peering-connection \
        --vpc-peering-connection-id $PEERING_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to delete peering connection${NC}"
    echo -e "${GREEN}✓ VPC peering connection deleted${NC}"
    sleep 5
fi

echo ""

# Delete Tokyo resources
echo -e "${YELLOW}Deleting Tokyo resources...${NC}"

# Delete security group
if [ ! -z "$TOKYO_SG_ID" ]; then
    aws ec2 delete-security-group \
        --group-id $TOKYO_SG_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to delete Tokyo security group${NC}"
    echo -e "${GREEN}✓ Tokyo security group deleted${NC}"
fi

# Detach and delete internet gateway
if [ ! -z "$TOKYO_IGW_ID" ] && [ ! -z "$TOKYO_VPC_ID" ]; then
    aws ec2 detach-internet-gateway \
        --internet-gateway-id $TOKYO_IGW_ID \
        --vpc-id $TOKYO_VPC_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to detach Tokyo IGW${NC}"
    
    aws ec2 delete-internet-gateway \
        --internet-gateway-id $TOKYO_IGW_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to delete Tokyo IGW${NC}"
    echo -e "${GREEN}✓ Tokyo internet gateway deleted${NC}"
fi

# Delete route table (custom ones, not main)
if [ ! -z "$TOKYO_RT_ID" ]; then
    # Disassociate route table from subnet first
    TOKYO_ASSOC_ID=$(aws ec2 describe-route-tables \
        --route-table-ids $TOKYO_RT_ID \
        --region $TOKYO_REGION \
        --query 'RouteTables[0].Associations[?SubnetId!=`null`].RouteTableAssociationId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$TOKYO_ASSOC_ID" ]; then
        aws ec2 disassociate-route-table \
            --association-id $TOKYO_ASSOC_ID \
            --region $TOKYO_REGION > /dev/null || true
    fi
    
    aws ec2 delete-route-table \
        --route-table-id $TOKYO_RT_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to delete Tokyo route table${NC}"
    echo -e "${GREEN}✓ Tokyo route table deleted${NC}"
fi

# Delete subnet
if [ ! -z "$TOKYO_SUBNET_ID" ]; then
    aws ec2 delete-subnet \
        --subnet-id $TOKYO_SUBNET_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to delete Tokyo subnet${NC}"
    echo -e "${GREEN}✓ Tokyo subnet deleted${NC}"
fi

# Delete VPC
if [ ! -z "$TOKYO_VPC_ID" ]; then
    aws ec2 delete-vpc \
        --vpc-id $TOKYO_VPC_ID \
        --region $TOKYO_REGION > /dev/null || echo -e "${RED}Failed to delete Tokyo VPC${NC}"
    echo -e "${GREEN}✓ Tokyo VPC deleted${NC}"
fi

echo ""

# Delete Frankfurt resources
echo -e "${YELLOW}Deleting Frankfurt resources...${NC}"

# Delete security group
if [ ! -z "$FRANKFURT_SG_ID" ]; then
    aws ec2 delete-security-group \
        --group-id $FRANKFURT_SG_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to delete Frankfurt security group${NC}"
    echo -e "${GREEN}✓ Frankfurt security group deleted${NC}"
fi

# Detach and delete internet gateway
if [ ! -z "$FRANKFURT_IGW_ID" ] && [ ! -z "$FRANKFURT_VPC_ID" ]; then
    aws ec2 detach-internet-gateway \
        --internet-gateway-id $FRANKFURT_IGW_ID \
        --vpc-id $FRANKFURT_VPC_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to detach Frankfurt IGW${NC}"
    
    aws ec2 delete-internet-gateway \
        --internet-gateway-id $FRANKFURT_IGW_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to delete Frankfurt IGW${NC}"
    echo -e "${GREEN}✓ Frankfurt internet gateway deleted${NC}"
fi

# Delete route table
if [ ! -z "$FRANKFURT_RT_ID" ]; then
    # Disassociate route table from subnet first
    FRANKFURT_ASSOC_ID=$(aws ec2 describe-route-tables \
        --route-table-ids $FRANKFURT_RT_ID \
        --region $FRANKFURT_REGION \
        --query 'RouteTables[0].Associations[?SubnetId!=`null`].RouteTableAssociationId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$FRANKFURT_ASSOC_ID" ]; then
        aws ec2 disassociate-route-table \
            --association-id $FRANKFURT_ASSOC_ID \
            --region $FRANKFURT_REGION > /dev/null || true
    fi
    
    aws ec2 delete-route-table \
        --route-table-id $FRANKFURT_RT_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to delete Frankfurt route table${NC}"
    echo -e "${GREEN}✓ Frankfurt route table deleted${NC}"
fi

# Delete subnet
if [ ! -z "$FRANKFURT_SUBNET_ID" ]; then
    aws ec2 delete-subnet \
        --subnet-id $FRANKFURT_SUBNET_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to delete Frankfurt subnet${NC}"
    echo -e "${GREEN}✓ Frankfurt subnet deleted${NC}"
fi

# Delete VPC
if [ ! -z "$FRANKFURT_VPC_ID" ]; then
    aws ec2 delete-vpc \
        --vpc-id $FRANKFURT_VPC_ID \
        --region $FRANKFURT_REGION > /dev/null || echo -e "${RED}Failed to delete Frankfurt VPC${NC}"
    echo -e "${GREEN}✓ Frankfurt VPC deleted${NC}"
fi

echo ""
echo -e "${GREEN}=== Teardown Complete ===${NC}"
echo ""
echo "All resources have been deleted"
echo ""

# Optionally remove the resource file
read -p "Delete vpc-resources.txt file? (yes/no): " DELETE_FILE
if [ "$DELETE_FILE" = "yes" ]; then
    rm -f $RESOURCE_FILE
    echo "Resource file deleted"
fi
