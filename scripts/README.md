# Infrastructure Setup Scripts

This directory contains scripts to automate the AWS infrastructure setup for the Binance latency experiment.

## Prerequisites

1. **AWS CLI** installed and configured with appropriate credentials
2. **Rust toolchain** installed (for building binaries)
3. **SSH key pair** created in AWS (both Tokyo and Frankfurt regions)
4. Set the `KEY_NAME` environment variable to your SSH key pair name:
   ```bash
   export KEY_NAME=your-key-name
   ```

## Setup Order

Run the scripts in this order:

### 1. VPC Setup
```bash
./setup-vpc.sh
```
Creates VPCs in Tokyo (10.0.0.0/16) and Frankfurt (10.1.0.0/16) with subnets, internet gateways, and route tables.

### 2. VPC Peering Setup
```bash
./setup-vpc-peering.sh
```
Establishes VPC peering connection between Tokyo and Frankfurt, and updates route tables.

### 3. EC2 Instance Launch
```bash
./setup-ec2.sh
```
Launches EC2 instances (t3.micro) in both regions with appropriate security groups.

### 4. NTP Configuration
```bash
./setup-ntp.sh
```
Installs and configures chrony NTP on both instances for accurate time synchronization.

### 5. Application Deployment
```bash
./deploy.sh
```
Builds Rust binaries and deploys them with configuration files to both EC2 instances.

## Running Experiments

### Baseline Experiment
SSH to Frankfurt instance and run:
```bash
./frankfurt-receiver frankfurt-baseline-config.json
```

### AWS Backbone Experiment
1. SSH to Frankfurt instance and run:
   ```bash
   ./frankfurt-receiver frankfurt-backbone-config.json
   ```

2. In another terminal, SSH to Tokyo instance and run:
   ```bash
   ./tokyo-forwarder tokyo-config.json
   ```

## Retrieving Results

After experiments complete, download results from Frankfurt:
```bash
scp -i ~/.ssh/$KEY_NAME.pem ec2-user@<frankfurt-ip>:~/results-*.json .
scp -i ~/.ssh/$KEY_NAME.pem ec2-user@<frankfurt-ip>:~/results-*.csv .
```

## Cleanup

When finished, tear down all infrastructure:
```bash
./teardown.sh
```

This will delete all EC2 instances, VPC peering connections, VPCs, and associated resources.

## Resource Tracking

All resource IDs are saved to `vpc-resources.txt` for reference and use by subsequent scripts.

## Troubleshooting

- If SSH connection fails, wait 2-3 minutes after EC2 launch for instances to fully initialize
- Verify NTP sync with: `ssh ec2-user@<instance-ip> 'chronyc tracking'`
- Check security group rules if connectivity issues occur
- Ensure AWS CLI has permissions for EC2, VPC operations in both regions
