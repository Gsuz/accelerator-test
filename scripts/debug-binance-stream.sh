#!/bin/bash
# Debug script to see what Binance is actually sending

echo "Connecting to Binance WebSocket to see raw events..."
echo "Will capture 5 events and then exit"
echo ""

timeout 10 websocat "wss://stream.binance.com:9443/ws/btcusdt@bookTicker" 2>/dev/null | head -n 5 | jq .
