# NTP Setup Guide for EC2 Instances

## Why NTP is Critical

For accurate cross-region latency measurements, both Tokyo and Frankfurt EC2 instances must have synchronized system clocks. Without NTP, clock drift can introduce measurement errors of hundreds of milliseconds.

## Installation and Configuration

### Install chrony (Amazon Linux 2023 / Amazon Linux 2)

```bash
sudo yum install -y chrony
```

### Configure chrony

Edit `/etc/chrony.conf`:

```bash
sudo nano /etc/chrony.conf
```

Use AWS Time Sync Service (recommended for EC2):

```
# Use AWS Time Sync Service
server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4

# Allow system clock to be stepped in the first three updates
makestep 1.0 3

# Enable kernel synchronization
rtcsync

# Log measurements
logdir /var/log/chrony
```

### Start and enable chrony

```bash
sudo systemctl start chronyd
sudo systemctl enable chronyd
```

### Verify synchronization

Check sync status:
```bash
chronyc tracking
```

Expected output should show:
- Reference ID: 169.254.169.123 (AWS Time Sync)
- Stratum: 3 or 4
- System time offset: < 10ms

Check sources:
```bash
chronyc sources -v
```

The AWS Time Sync Service should show as the active source with `*` indicator.

## Validation Before Experiments

Before running latency experiments, verify both instances are synchronized:

```bash
# Check offset from reference
chronyc tracking | grep "System time"

# Should show offset < 10ms
```

If offset is large (> 50ms), wait a few minutes for chrony to stabilize, or force a step:

```bash
sudo chronyc makestep
```

## Troubleshooting

### Clock not syncing

1. Check chrony is running:
   ```bash
   sudo systemctl status chronyd
   ```

2. Check network connectivity to AWS Time Sync:
   ```bash
   ping 169.254.169.123
   ```

3. Check chrony logs:
   ```bash
   sudo journalctl -u chronyd -n 50
   ```

### Large time offset

If system time is very wrong, chrony may refuse to step. Force it:

```bash
sudo chronyc makestep
```

Then verify:
```bash
chronyc tracking
```
