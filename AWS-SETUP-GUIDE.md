# AWS Setup Guide

Quick reference for setting up AWS infrastructure for the Binance Latency Experiment.

## Prerequisites

1. **AWS CLI installed and configured**
   ```bash
   aws --version  # Should be v2.x or later
   aws configure  # Set up credentials
   ```

2. **Sufficient AWS permissions**
   - EC2: Full access
   - VPC: Full access
   - Ability to create resources in `ap-northeast-1` (Tokyo) and `eu-central-1` (Frankfurt)

## Step-by-Step Setup

### 1. Create SSH Key Pair

**This is required before running any other setup scripts!**

```bash
./scripts/create-keypair.sh
```

This creates:
- Key pair named `binance-latency-key` in both AWS regions
- Private key file at `~/.ssh/binance-latency-key.pem`
- Proper permissions (400) on the key file

**Troubleshooting**:

If you get "key pair already exists" error:
```bash
# Delete existing key pairs
aws ec2 delete-key-pair --key-name binance-latency-key --region ap-northeast-1
aws ec2 delete-key-pair --key-name binance-latency-key --region eu-central-1

# Delete local key file
rm ~/.ssh/binance-latency-key.pem

# Run create script again
./scripts/create-keypair.sh
```

### 2. Create VPCs

```bash
./scripts/setup-vpc.sh
```

This creates:
- Tokyo VPC (10.0.0.0/16) with public subnet (10.0.1.0/24)
- Frankfurt VPC (10.1.0.0/16) with public subnet (10.1.1.0/24)
- Internet gateways for both VPCs
- Route tables with internet access
- Security groups allowing necessary traffic

**Expected output**:
```
✓ Tokyo VPC created: vpc-xxxxx
✓ Frankfurt VPC created: vpc-xxxxx
```

### 3. Set Up VPC Peering

```bash
./scripts/setup-vpc-peering.sh
```

This creates:
- VPC peering connection between Tokyo and Frankfurt
- Routes in both VPCs to reach the peer VPC
- Accepts the peering connection

**Expected output**:
```
✓ VPC peering connection created: pcx-xxxxx
✓ Routes configured
```

### 4. Launch EC2 Instances

```bash
./scripts/setup-ec2.sh
```

This creates:
- Tokyo EC2 instance (t3.micro, Amazon Linux 2023)
- Frankfurt EC2 instance (t3.micro, Amazon Linux 2023)
- Uses the key pair created in step 1

**Expected output**:
```
✓ Tokyo instance launched: i-xxxxx
  Public IP: xx.xx.xx.xx
  Private IP: 10.0.1.xx

✓ Frankfurt instance launched: i-xxxxx
  Public IP: xx.xx.xx.xx
  Private IP: 10.1.1.xx
```

**Important**: Save these IP addresses! You'll need them for:
- SSH access (public IPs)
- Configuration files (private IPs)

### 5. Deploy Applications

```bash
./scripts/deploy.sh
```

This:
- Copies binaries to both EC2 instances
- Sets executable permissions
- Verifies deployment

**Note**: You may need to wait 1-2 minutes after launching instances before deploying.

## Common Issues and Solutions

### Issue: "InvalidKeyPair.NotFound"

**Error message**:
```
The key pair 'binance-latency-key' does not exist
```

**Solution**:
Run the key pair creation script first:
```bash
./scripts/create-keypair.sh
```

### Issue: "UnauthorizedOperation"

**Error message**:
```
You are not authorized to perform this operation
```

**Solution**:
Check your AWS credentials and permissions:
```bash
# Verify credentials are configured
aws sts get-caller-identity

# Check if you can list EC2 instances
aws ec2 describe-instances --region ap-northeast-1
```

### Issue: "VPC limit exceeded"

**Error message**:
```
VpcLimitExceeded: The maximum number of VPCs has been reached
```

**Solution**:
Delete unused VPCs or request a limit increase:
```bash
# List all VPCs
aws ec2 describe-vpcs --region ap-northeast-1
aws ec2 describe-vpcs --region eu-central-1

# Delete unused VPCs (be careful!)
aws ec2 delete-vpc --vpc-id vpc-xxxxx --region ap-northeast-1
```

### Issue: "Cannot connect to EC2 instance"

**Error message**:
```
ssh: connect to host xx.xx.xx.xx port 22: Connection refused
```

**Solutions**:
1. Wait 1-2 minutes for instance to fully boot
2. Verify security group allows SSH (port 22) from your IP
3. Check you're using the correct key file:
   ```bash
   ssh -i ~/.ssh/binance-latency-key.pem ec2-user@<public-ip>
   ```

### Issue: "Permission denied (publickey)"

**Error message**:
```
Permission denied (publickey,gssapi-keyex,gssapi-with-mic)
```

**Solutions**:
1. Check key file permissions:
   ```bash
   chmod 400 ~/.ssh/binance-latency-key.pem
   ```
2. Verify you're using the correct username (`ec2-user` for Amazon Linux)
3. Ensure you're using the correct key file

### Issue: "VPC peering connection failed"

**Error message**:
```
VPC peering connection is in failed state
```

**Solutions**:
1. Check VPC CIDR blocks don't overlap
2. Verify both VPCs exist
3. Delete and recreate the peering connection:
   ```bash
   ./scripts/teardown.sh
   ./scripts/setup-vpc.sh
   ./scripts/setup-vpc-peering.sh
   ```

## Verification Steps

After setup, verify everything is working:

### 1. Verify VPCs

```bash
# Tokyo VPC
aws ec2 describe-vpcs --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=binance-tokyo-vpc"

# Frankfurt VPC
aws ec2 describe-vpcs --region eu-central-1 \
  --filters "Name=tag:Name,Values=binance-frankfurt-vpc"
```

### 2. Verify VPC Peering

```bash
aws ec2 describe-vpc-peering-connections \
  --region ap-northeast-1 \
  --filters "Name=status-code,Values=active"
```

Should show status: `active`

### 3. Verify EC2 Instances

```bash
# Tokyo instance
aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=binance-tokyo-forwarder" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]'

# Frankfurt instance
aws ec2 describe-instances --region eu-central-1 \
  --filters "Name=tag:Name,Values=binance-frankfurt-receiver" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]'
```

Both should show state: `running`

### 4. Test SSH Access

```bash
# Tokyo
ssh -i ~/.ssh/binance-latency-key.pem ec2-user@<tokyo-public-ip> "echo 'Tokyo OK'"

# Frankfurt
ssh -i ~/.ssh/binance-latency-key.pem ec2-user@<frankfurt-public-ip> "echo 'Frankfurt OK'"
```

### 5. Test VPC Peering Connectivity

From Tokyo instance, ping Frankfurt private IP:
```bash
ssh -i ~/.ssh/binance-latency-key.pem ec2-user@<tokyo-public-ip>
ping -c 3 <frankfurt-private-ip>
```

Should show successful ping responses.

## Cost Management

### Estimated Costs

- **EC2 instances**: 2 × t3.micro × $0.0104/hour = ~$0.02/hour
- **VPC peering data transfer**: $0.02/GB (inter-region)
- **Internet data transfer**: $0.09/GB (outbound)

**Total for 1-hour experiment**: ~$0.50 - $2.00

### Cost Optimization

1. **Use t3.micro instances** (included in free tier for first 12 months)
2. **Stop instances when not in use**:
   ```bash
   aws ec2 stop-instances --instance-ids i-xxxxx --region ap-northeast-1
   ```
3. **Terminate instances after experiments**:
   ```bash
   ./scripts/teardown.sh
   ```

### Monitor Costs

Check AWS Cost Explorer or use:
```bash
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE
```

## Cleanup

When finished, remove all resources:

```bash
./scripts/teardown.sh
```

This deletes:
- EC2 instances
- VPC peering connection
- VPCs and all associated resources
- Security groups
- Internet gateways

**Verify cleanup**:
```bash
# Check for remaining instances
aws ec2 describe-instances --region ap-northeast-1 \
  --query 'Reservations[].Instances[?State.Name!=`terminated`]'

aws ec2 describe-instances --region eu-central-1 \
  --query 'Reservations[].Instances[?State.Name!=`terminated`]'

# Check for remaining VPCs
aws ec2 describe-vpcs --region ap-northeast-1 \
  --query 'Vpcs[?IsDefault==`false`]'

aws ec2 describe-vpcs --region eu-central-1 \
  --query 'Vpcs[?IsDefault==`false`]'
```

## Quick Reference Commands

```bash
# Complete setup from scratch
./scripts/create-keypair.sh
./scripts/setup-vpc.sh
./scripts/setup-vpc-peering.sh
./scripts/setup-ec2.sh
./scripts/deploy.sh

# Get instance IPs
aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=binance-tokyo-forwarder" \
  --query 'Reservations[].Instances[].[PublicIpAddress,PrivateIpAddress]' \
  --output text

aws ec2 describe-instances --region eu-central-1 \
  --filters "Name=tag:Name,Values=binance-frankfurt-receiver" \
  --query 'Reservations[].Instances[].[PublicIpAddress,PrivateIpAddress]' \
  --output text

# SSH to instances
ssh -i ~/.ssh/binance-latency-key.pem ec2-user@<public-ip>

# Complete teardown
./scripts/teardown.sh

# Delete key pair
aws ec2 delete-key-pair --key-name binance-latency-key --region ap-northeast-1
aws ec2 delete-key-pair --key-name binance-latency-key --region eu-central-1
rm ~/.ssh/binance-latency-key.pem
```

## Next Steps

After successful setup:

1. Review [README.md](README.md) for running experiments
2. Check [TESTING.md](TESTING.md) for local testing
3. Run baseline experiment
4. Run AWS backbone experiment
5. Compare results
6. Clean up resources

## Support

If you encounter issues not covered here:

1. Check AWS Service Health Dashboard
2. Review CloudWatch logs
3. Verify security group rules
4. Check VPC route ta