# VPC Peering Setup Guide

This guide provides detailed step-by-step instructions for manually setting up VPC peering between Tokyo and Frankfurt regions for the Binance latency experiment.

## Overview

VPC Peering allows private network connectivity between two VPCs, even across different AWS regions. Traffic stays on AWS's private backbone network and doesn't traverse the public internet.

**Our Setup**:
- **Tokyo VPC**: 10.0.0.0/16 (ap-northeast-1)
- **Frankfurt VPC**: 10.1.0.0/16 (eu-central-1)
- **Peering Connection**: Inter-region peering between the two VPCs

## Prerequisites

- AWS CLI configured with appropriate credentials
- Permissions to create VPCs, subnets, and peering connections
- Both VPCs must have non-overlapping CIDR blocks

## Step 1: Create VPCs

### 1.1 Create Tokyo VPC

Using AWS CLI:

```bash
# Create Tokyo VPC
TOKYO_VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region ap-northeast-1 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=binance-tokyo-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "Tokyo VPC ID: $TOKYO_VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $TOKYO_VPC_ID \
  --enable-dns-hostnames \
  --region ap-northeast-1

# Create subnet
TOKYO_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $TOKYO_VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ap-northeast-1a \
  --region ap-northeast-1 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=binance-tokyo-subnet}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Tokyo Subnet ID: $TOKYO_SUBNET_ID"

# Create internet gateway
TOKYO_IGW_ID=$(aws ec2 create-internet-gateway \
  --region ap-northeast-1 \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=binance-tokyo-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

# Attach internet gateway to VPC
aws ec2 attach-internet-gateway \
  --vpc-id $TOKYO_VPC_ID \
  --internet-gateway-id $TOKYO_IGW_ID \
  --region ap-northeast-1

# Get route table ID
TOKYO_RTB_ID=$(aws ec2 describe-route-tables \
  --region ap-northeast-1 \
  --filters "Name=vpc-id,Values=$TOKYO_VPC_ID" \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

# Add route to internet gateway
aws ec2 create-route \
  --route-table-id $TOKYO_RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $TOKYO_IGW_ID \
  --region ap-northeast-1

echo "Tokyo Route Table ID: $TOKYO_RTB_ID"
```

Using AWS Console:

1. Navigate to **VPC Console** → Select **ap-northeast-1** region
2. Click **Create VPC**
3. Configure:
   - Name: `binance-tokyo-vpc`
   - IPv4 CIDR: `10.0.0.0/16`
   - Tenancy: Default
4. Click **Create VPC**
5. Select the VPC → **Actions** → **Edit DNS hostnames** → Enable
6. Go to **Subnets** → **Create subnet**
   - VPC: Select `binance-tokyo-vpc`
   - Name: `binance-tokyo-subnet`
   - Availability Zone: `ap-northeast-1a`
   - IPv4 CIDR: `10.0.1.0/24`
7. Go to **Internet Gateways** → **Create internet gateway**
   - Name: `binance-tokyo-igw`
   - Attach to `binance-tokyo-vpc`
8. Go to **Route Tables** → Select the main route table for the VPC
   - **Routes** tab → **Edit routes** → **Add route**
   - Destination: `0.0.0.0/0`
   - Target: Select the internet gateway

### 1.2 Create Frankfurt VPC

Using AWS CLI:

```bash
# Create Frankfurt VPC
FRANKFURT_VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --region eu-central-1 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=binance-frankfurt-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "Frankfurt VPC ID: $FRANKFURT_VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $FRANKFURT_VPC_ID \
  --enable-dns-hostnames \
  --region eu-central-1

# Create subnet
FRANKFURT_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $FRANKFURT_VPC_ID \
  --cidr-block 10.1.1.0/24 \
  --availability-zone eu-central-1a \
  --region eu-central-1 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=binance-frankfurt-subnet}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Frankfurt Subnet ID: $FRANKFURT_SUBNET_ID"

# Create internet gateway
FRANKFURT_IGW_ID=$(aws ec2 create-internet-gateway \
  --region eu-central-1 \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=binance-frankfurt-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

# Attach internet gateway to VPC
aws ec2 attach-internet-gateway \
  --vpc-id $FRANKFURT_VPC_ID \
  --internet-gateway-id $FRANKFURT_IGW_ID \
  --region eu-central-1

# Get route table ID
FRANKFURT_RTB_ID=$(aws ec2 describe-route-tables \
  --region eu-central-1 \
  --filters "Name=vpc-id,Values=$FRANKFURT_VPC_ID" \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

# Add route to internet gateway
aws ec2 create-route \
  --route-table-id $FRANKFURT_RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $FRANKFURT_IGW_ID \
  --region eu-central-1

echo "Frankfurt Route Table ID: $FRANKFURT_RTB_ID"
```

Using AWS Console:

1. Navigate to **VPC Console** → Select **eu-central-1** region
2. Click **Create VPC**
3. Configure:
   - Name: `binance-frankfurt-vpc`
   - IPv4 CIDR: `10.1.0.0/16`
   - Tenancy: Default
4. Click **Create VPC**
5. Select the VPC → **Actions** → **Edit DNS hostnames** → Enable
6. Go to **Subnets** → **Create subnet**
   - VPC: Select `binance-frankfurt-vpc`
   - Name: `binance-frankfurt-subnet`
   - Availability Zone: `eu-central-1a`
   - IPv4 CIDR: `10.1.1.0/24`
7. Go to **Internet Gateways** → **Create internet gateway**
   - Name: `binance-frankfurt-igw`
   - Attach to `binance-frankfurt-vpc`
8. Go to **Route Tables** → Select the main route table for the VPC
   - **Routes** tab → **Edit routes** → **Add route**
   - Destination: `0.0.0.0/0`
   - Target: Select the internet gateway

## Step 2: Create VPC Peering Connection

### 2.1 Create Peering Connection (Requester Side)

Using AWS CLI:

```bash
# Create peering connection from Tokyo (requester) to Frankfurt (accepter)
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $TOKYO_VPC_ID \
  --peer-vpc-id $FRANKFURT_VPC_ID \
  --peer-region eu-central-1 \
  --region ap-northeast-1 \
  --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=tokyo-frankfurt-peering}]' \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

echo "Peering Connection ID: $PEERING_ID"
```

Using AWS Console:

1. Navigate to **VPC Console** in **Tokyo region (ap-northeast-1)**
2. Go to **Peering Connections** → **Create Peering Connection**
3. Configure:
   - Name: `tokyo-frankfurt-peering`
   - VPC (Requester): Select `binance-tokyo-vpc`
   - Account: My account
   - Region: Another region
   - Select region: `eu-central-1`
   - VPC (Accepter): Enter Frankfurt VPC ID
4. Click **Create Peering Connection**
5. Note the **Peering Connection ID** (format: `pcx-xxxxxxxxx`)

### 2.2 Accept Peering Connection (Accepter Side)

Using AWS CLI:

```bash
# Accept peering connection in Frankfurt
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region eu-central-1

# Wait for peering to become active
aws ec2 describe-vpc-peering-connections \
  --vpc-peering-connection-ids $PEERING_ID \
  --region eu-central-1 \
  --query 'VpcPeeringConnections[0].Status.Code' \
  --output text
```

Using AWS Console:

1. Navigate to **VPC Console** in **Frankfurt region (eu-central-1)**
2. Go to **Peering Connections**
3. You should see a pending peering connection request
4. Select the peering connection
5. Click **Actions** → **Accept Request**
6. Confirm acceptance
7. Wait for status to change from `pending-acceptance` to `active`

### 2.3 Verify Peering Connection

```bash
# Check peering status in Tokyo
aws ec2 describe-vpc-peering-connections \
  --vpc-peering-connection-ids $PEERING_ID \
  --region ap-northeast-1

# Check peering status in Frankfurt
aws ec2 describe-vpc-peering-connections \
  --vpc-peering-connection-ids $PEERING_ID \
  --region eu-central-1
```

Expected output should show `"Code": "active"` in the Status field.

## Step 3: Update Route Tables

### 3.1 Add Route in Tokyo VPC

Using AWS CLI:

```bash
# Add route to Frankfurt VPC CIDR via peering connection
aws ec2 create-route \
  --route-table-id $TOKYO_RTB_ID \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-northeast-1

# Verify route was added
aws ec2 describe-route-tables \
  --route-table-ids $TOKYO_RTB_ID \
  --region ap-northeast-1 \
  --query 'RouteTables[0].Routes'
```

Using AWS Console:

1. Navigate to **VPC Console** in **Tokyo region**
2. Go to **Route Tables**
3. Select the route table for `binance-tokyo-vpc`
4. Click **Routes** tab → **Edit routes**
5. Click **Add route**
6. Configure:
   - Destination: `10.1.0.0/16` (Frankfurt VPC CIDR)
   - Target: Select **Peering Connection** → Select `tokyo-frankfurt-peering`
7. Click **Save changes**

### 3.2 Add Route in Frankfurt VPC

Using AWS CLI:

```bash
# Add route to Tokyo VPC CIDR via peering connection
aws ec2 create-route \
  --route-table-id $FRANKFURT_RTB_ID \
  --destination-cidr-block 10.0.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region eu-central-1

# Verify route was added
aws ec2 describe-route-tables \
  --route-table-ids $FRANKFURT_RTB_ID \
  --region eu-central-1 \
  --query 'RouteTables[0].Routes'
```

Using AWS Console:

1. Navigate to **VPC Console** in **Frankfurt region**
2. Go to **Route Tables**
3. Select the route table for `binance-frankfurt-vpc`
4. Click **Routes** tab → **Edit routes**
5. Click **Add route**
6. Configure:
   - Destination: `10.0.0.0/16` (Tokyo VPC CIDR)
   - Target: Select **Peering Connection** → Select `tokyo-frankfurt-peering`
7. Click **Save changes**

## Step 4: Configure Security Groups

### 4.1 Create Tokyo Security Group

Using AWS CLI:

```bash
# Create security group for Tokyo EC2
TOKYO_SG_ID=$(aws ec2 create-security-group \
  --group-name binance-tokyo-sg \
  --description "Security group for Tokyo forwarder" \
  --vpc-id $TOKYO_VPC_ID \
  --region ap-northeast-1 \
  --query 'GroupId' \
  --output text)

# Allow SSH from anywhere (restrict to your IP in production)
aws ec2 authorize-security-group-ingress \
  --group-id $TOKYO_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-1

# Allow outbound HTTPS for Binance WebSocket
aws ec2 authorize-security-group-egress \
  --group-id $TOKYO_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-1

# Allow outbound TCP 8080 to Frankfurt VPC
aws ec2 authorize-security-group-egress \
  --group-id $TOKYO_SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 10.1.0.0/16 \
  --region ap-northeast-1

echo "Tokyo Security Group ID: $TOKYO_SG_ID"
```

Using AWS Console:

1. Navigate to **EC2 Console** in **Tokyo region**
2. Go to **Security Groups** → **Create security group**
3. Configure:
   - Name: `binance-tokyo-sg`
   - Description: `Security group for Tokyo forwarder`
   - VPC: Select `binance-tokyo-vpc`
4. **Inbound rules**:
   - Type: SSH, Port: 22, Source: 0.0.0.0/0 (or your IP)
5. **Outbound rules**:
   - Type: HTTPS, Port: 443, Destination: 0.0.0.0/0
   - Type: Custom TCP, Port: 8080, Destination: 10.1.0.0/16
6. Click **Create security group**

### 4.2 Create Frankfurt Security Group

Using AWS CLI:

```bash
# Create security group for Frankfurt EC2
FRANKFURT_SG_ID=$(aws ec2 create-security-group \
  --group-name binance-frankfurt-sg \
  --description "Security group for Frankfurt receiver" \
  --vpc-id $FRANKFURT_VPC_ID \
  --region eu-central-1 \
  --query 'GroupId' \
  --output text)

# Allow SSH from anywhere (restrict to your IP in production)
aws ec2 authorize-security-group-ingress \
  --group-id $FRANKFURT_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region eu-central-1

# Allow inbound TCP 8080 from Tokyo VPC
aws ec2 authorize-security-group-ingress \
  --group-id $FRANKFURT_SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 10.0.0.0/16 \
  --region eu-central-1

# Allow outbound HTTPS for Binance WebSocket (baseline mode)
aws ec2 authorize-security-group-egress \
  --group-id $FRANKFURT_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region eu-central-1

echo "Frankfurt Security Group ID: $FRANKFURT_SG_ID"
```

Using AWS Console:

1. Navigate to **EC2 Console** in **Frankfurt region**
2. Go to **Security Groups** → **Create security group**
3. Configure:
   - Name: `binance-frankfurt-sg`
   - Description: `Security group for Frankfurt receiver`
   - VPC: Select `binance-frankfurt-vpc`
4. **Inbound rules**:
   - Type: SSH, Port: 22, Source: 0.0.0.0/0 (or your IP)
   - Type: Custom TCP, Port: 8080, Source: 10.0.0.0/16
5. **Outbound rules**:
   - Type: HTTPS, Port: 443, Destination: 0.0.0.0/0
6. Click **Create security group**

## Step 5: Test Connectivity

### 5.1 Launch Test EC2 Instances

Launch minimal instances to test connectivity:

```bash
# Get Amazon Linux 2023 AMI ID for Tokyo
TOKYO_AMI=$(aws ec2 describe-images \
  --region ap-northeast-1 \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

# Launch Tokyo instance
TOKYO_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $TOKYO_AMI \
  --instance-type t3.micro \
  --key-name binance-experiment \
  --security-group-ids $TOKYO_SG_ID \
  --subnet-id $TOKYO_SUBNET_ID \
  --associate-public-ip-address \
  --region ap-northeast-1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=binance-tokyo-forwarder}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

# Get Amazon Linux 2023 AMI ID for Frankfurt
FRANKFURT_AMI=$(aws ec2 describe-images \
  --region eu-central-1 \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

# Launch Frankfurt instance
FRANKFURT_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $FRANKFURT_AMI \
  --instance-type t3.micro \
  --key-name binance-experiment \
  --security-group-ids $FRANKFURT_SG_ID \
  --subnet-id $FRANKFURT_SUBNET_ID \
  --associate-public-ip-address \
  --region eu-central-1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=binance-frankfurt-receiver}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

# Wait for instances to be running
aws ec2 wait instance-running --instance-ids $TOKYO_INSTANCE_ID --region ap-northeast-1
aws ec2 wait instance-running --instance-ids $FRANKFURT_INSTANCE_ID --region eu-central-1

# Get private IPs
TOKYO_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids $TOKYO_INSTANCE_ID \
  --region ap-northeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

FRANKFURT_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids $FRANKFURT_INSTANCE_ID \
  --region eu-central-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

echo "Tokyo Private IP: $TOKYO_PRIVATE_IP"
echo "Frankfurt Private IP: $FRANKFURT_PRIVATE_IP"
```

### 5.2 Test Ping Connectivity

```bash
# Get Tokyo public IP
TOKYO_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $TOKYO_INSTANCE_ID \
  --region ap-northeast-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# SSH to Tokyo and ping Frankfurt private IP
ssh -i ~/.ssh/binance-experiment ec2-user@$TOKYO_PUBLIC_IP "ping -c 4 $FRANKFURT_PRIVATE_IP"
```

Expected output:
```
PING 10.1.1.X (10.1.1.X) 56(84) bytes of data.
64 bytes from 10.1.1.X: icmp_seq=1 ttl=254 time=230 ms
64 bytes from 10.1.1.X: icmp_seq=2 ttl=254 time=229 ms
64 bytes from 10.1.1.X: icmp_seq=3 ttl=254 time=230 ms
64 bytes from 10.1.1.X: icmp_seq=4 ttl=254 time=229 ms
```

### 5.3 Test TCP Connectivity

```bash
# Get Frankfurt public IP
FRANKFURT_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $FRANKFURT_INSTANCE_ID \
  --region eu-central-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Start a simple TCP listener on Frankfurt
ssh -i ~/.ssh/binance-experiment ec2-user@$FRANKFURT_PUBLIC_IP "nc -l 8080" &

# From Tokyo, test connection
ssh -i ~/.ssh/binance-experiment ec2-user@$TOKYO_PUBLIC_IP "echo 'test' | nc $FRANKFURT_PRIVATE_IP 8080"
```

If successful, you should see "test" appear on the Frankfurt terminal.

## Troubleshooting

### Issue: Peering Connection Stuck in "Pending Acceptance"

**Cause**: Peering connection not accepted in the accepter region

**Solution**:
1. Switch to Frankfurt region in AWS Console
2. Go to VPC → Peering Connections
3. Select the pending connection and accept it
4. Or use CLI: `aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEERING_ID --region eu-central-1`

### Issue: Cannot Ping Between VPCs

**Possible Causes**:
1. Route tables not updated
2. Security groups blocking ICMP
3. Peering connection not active

**Solutions**:

1. **Verify peering is active**:
   ```bash
   aws ec2 describe-vpc-peering-connections \
     --vpc-peering-connection-ids $PEERING_ID \
     --region ap-northeast-1 \
     --query 'VpcPeeringConnections[0].Status.Code'
   ```
   Should return: `"active"`

2. **Verify routes exist**:
   ```bash
   # Tokyo route table
   aws ec2 describe-route-tables \
     --route-table-ids $TOKYO_RTB_ID \
     --region ap-northeast-1 \
     --query 'RouteTables[0].Routes[?DestinationCidrBlock==`10.1.0.0/16`]'
   
   # Frankfurt route table
   aws ec2 describe-route-tables \
     --route-table-ids $FRANKFURT_RTB_ID \
     --region eu-central-1 \
     --query 'RouteTables[0].Routes[?DestinationCidrBlock==`10.0.0.0/16`]'
   ```

3. **Check security groups allow ICMP**:
   ```bash
   # Add ICMP to Tokyo security group
   aws ec2 authorize-security-group-egress \
     --group-id $TOKYO_SG_ID \
     --protocol icmp \
     --port -1 \
     --cidr 10.1.0.0/16 \
     --region ap-northeast-1
   
   # Add ICMP to Frankfurt security group
   aws ec2 authorize-security-group-ingress \
     --group-id $FRANKFURT_SG_ID \
     --protocol icmp \
     --port -1 \
     --cidr 10.0.0.0/16 \
     --region eu-central-1
   ```

### Issue: TCP Connection Refused

**Possible Causes**:
1. Security groups not allowing TCP port 8080
2. No listener on destination port
3. Route tables incorrect

**Solutions**:

1. **Verify security group rules**:
   ```bash
   # Check Tokyo outbound rules
   aws ec2 describe-security-groups \
     --group-ids $TOKYO_SG_ID \
     --region ap-northeast-1 \
     --query 'SecurityGroups[0].IpPermissionsEgress'
   
   # Check Frankfurt inbound rules
   aws ec2 describe-security-groups \
     --group-ids $FRANKFURT_SG_ID \
     --region eu-central-1 \
     --query 'SecurityGroups[0].IpPermissions'
   ```

2. **Test with netcat**:
   ```bash
   # On Frankfurt, start listener
   nc -l 8080
   
   # On Tokyo, connect
   nc $FRANKFURT_PRIVATE_IP 8080
   ```

3. **Check if port is listening**:
   ```bash
   # On Frankfurt
   sudo netstat -tlnp | grep 8080
   ```

### Issue: High Latency Over Peering

**Expected Latency**: 220-250ms between Tokyo and Frankfurt

**Possible Causes**:
1. Network congestion
2. Instance type too small (CPU throttling)
3. Not using enhanced networking

**Solutions**:

1. **Use enhanced networking instance types**: t3.micro or larger
2. **Check instance CPU credits**: `aws cloudwatch get-metric-statistics`
3. **Test at different times**: Network latency varies by time of day
4. **Use placement groups**: For lower latency within same AZ (not applicable for inter-region)

### Issue: VPC CIDR Overlap

**Error**: "VPC CIDR blocks overlap"

**Cause**: Both VPCs have overlapping IP ranges

**Solution**:
- VPCs must have non-overlapping CIDR blocks
- Tokyo: 10.0.0.0/16
- Frankfurt: 10.1.0.0/16
- If you need to change, delete and recreate VPCs with different CIDRs

### Issue: Route Already Exists

**Error**: "Route already exists"

**Cause**: Route to destination CIDR already exists in route table

**Solution**:
```bash
# Delete existing route
aws ec2 delete-route \
  --route-table-id $TOKYO_RTB_ID \
  --destination-cidr-block 10.1.0.0/16 \
  --region ap-northeast-1

# Recreate with correct target
aws ec2 create-route \
  --route-table-id $TOKYO_RTB_ID \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-northeast-1
```

## Verification Checklist

Before running the experiment, verify:

- [ ] Both VPCs created with correct CIDR blocks
- [ ] Subnets created in each VPC
- [ ] Internet gateways attached to both VPCs
- [ ] VPC peering connection status is "active"
- [ ] Route tables updated with peering routes in both VPCs
- [ ] Security groups allow SSH (port 22)
- [ ] Security groups allow HTTPS (port 443) outbound for Binance
- [ ] Tokyo security group allows TCP 8080 outbound to Frankfurt CIDR
- [ ] Frankfurt security group allows TCP 8080 inbound from Tokyo CIDR
- [ ] EC2 instances launched in correct subnets
- [ ] Instances have public IPs for SSH access
- [ ] Can ping Frankfurt private IP from Tokyo instance
- [ ] Can establish TCP connection on port 8080

## Cost Optimization

- **Use t3.micro instances**: Sufficient for this experiment (~$0.01/hour each)
- **Delete resources when not in use**: Run teardown script after experiments
- **Inter-region data transfer**: ~$0.02/GB for VPC peering traffic
- **Estimated cost**: $0.50-$2.00 for a 1-hour experiment

## Additional Resources

- [AWS VPC Peering Documentation](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html)
- [VPC Peering Limitations](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html#vpc-peering-limitations)
- [Inter-Region VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html)
- [VPC Peering Pricing](https://aws.amazon.com/vpc/pricing/)

## Summary

This guide walked through:
1. Creating VPCs in Tokyo and Frankfurt regions
2. Setting up inter-region VPC peering
3. Configuring route tables for cross-VPC communication
4. Setting up security groups for the experiment
5. Testing connectivity between regions
6. Troubleshooting common issues

You're now ready to deploy the Binance latency experiment applications and run the comparison tests.
