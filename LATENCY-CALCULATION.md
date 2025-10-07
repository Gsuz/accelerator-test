# Latency Calculation Explained

## Data Flow

### Binance bookTicker Stream
Binance sends book ticker updates in real-time whenever the best bid/ask changes:

```json
{
  "e": "bookTicker",
  "u": 400900217,       // order book updateId
  "E": 1568014460893,   // Event time (milliseconds since epoch)
  "T": 1568014460891,   // Transaction time (milliseconds)
  "s": "BNBUSDT",
  "b": "25.35190000",   // best bid price
  "B": "31.21000000",   // best bid qty
  "a": "25.36520000",   // best ask price
  "A": "40.66000000"    // best ask qty
}
```

**Key field: `E` (Event time)** - This is when Binance created the event (in milliseconds)

**Why bookTicker?**
- Real-time updates (not aggregated)
- High frequency (updates whenever best bid/ask changes)
- Includes timestamps (E and T fields)
- Perfect for measuring latency

## Baseline Mode (Direct: Binance → Frankfurt)

### Timeline:
1. **T1**: Binance creates event at time `E` (e.g., 1736265482136 ms)
2. **T2**: Frankfurt receives event and records `frankfurt_receive_time` (in nanoseconds)

### Latency Calculation:
```
end_to_end_latency_ms = (frankfurt_receive_time / 1,000,000) - E
```

**Example:**
- Binance event time (E): `1736265482136` ms
- Frankfurt receive time: `1736265482186000000` ns = `1736265482186` ms
- **Latency = 1736265482186 - 1736265482136 = 50 ms**

This measures:
- Network latency from Binance servers to Frankfurt
- WebSocket processing time
- Any buffering/queuing delays

## AWS Backbone Mode (Binance → Tokyo → Frankfurt)

### Timeline:
1. **T1**: Binance creates event at time `E` (e.g., 1736265482136 ms)
2. **T2**: Tokyo receives event and records `tokyo_receive_timestamp` (in nanoseconds)
3. **T3**: Tokyo forwards to Frankfurt via VPC peering
4. **T4**: Frankfurt receives and records `frankfurt_receive_time` (in nanoseconds)

### Latency Calculations:

**End-to-End Latency (Binance → Frankfurt):**
```
end_to_end_latency_ms = (frankfurt_receive_time / 1,000,000) - E
```

**AWS Backbone Latency (Tokyo → Frankfurt):**
```
backbone_latency_ms = (frankfurt_receive_time - tokyo_receive_timestamp) / 1,000,000
```

**Example:**
- Binance event time (E): `1736265482136` ms
- Tokyo receive time: `1736265482156000000` ns = `1736265482156` ms
- Frankfurt receive time: `1736265482186000000` ns = `1736265482186` ms

**Results:**
- **End-to-End Latency** = 1736265482186 - 1736265482136 = **50 ms**
- **Backbone Latency** = (1736265482186000000 - 1736265482156000000) / 1,000,000 = **30 ms**

This tells us:
- Total latency from Binance to Frankfurt: 50 ms
- Latency added by AWS backbone routing: 30 ms
- Implied Binance → Tokyo latency: 50 - 30 = 20 ms

## Expected Results

### Baseline Mode (Frankfurt Direct)
- **Expected latency**: 40-80 ms
- Measures: Binance (likely Singapore/Tokyo) → Frankfurt direct internet path

### AWS Backbone Mode
- **Expected end-to-end**: 40-80 ms (similar to baseline)
- **Expected backbone latency**: 10-30 ms (Tokyo → Frankfurt via AWS private network)

### Key Insight
If AWS backbone latency is significantly lower than the difference in end-to-end latencies, it proves that AWS's private network is faster than the public internet for inter-region communication.

## Timestamp Precision

- **Binance event time (E)**: Milliseconds (1000 ms = 1 second)
- **Tokyo/Frankfurt receive times**: Nanoseconds (1,000,000,000 ns = 1 second)
- **Reported latencies**: Milliseconds with 2 decimal places (0.01 ms precision)

## Common Issues

### Issue: Near-zero latency (~0.5 ms)
**Cause**: Using old bookTicker stream format without timestamps, or not parsing the E field
**Solution**: Use bookTicker stream with E field parsing (now fixed)

### Issue: Negative latency
**Cause**: Clock skew between Binance servers and EC2 instances
**Solution**: Run NTP sync on EC2 instances (setup-ntp.sh)

### Issue: Very high latency (>500 ms)
**Cause**: Network congestion, packet loss, or routing issues
**Solution**: Check network connectivity, security groups, VPC peering
