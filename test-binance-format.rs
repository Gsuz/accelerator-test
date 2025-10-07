// Quick test to see what Binance actually sends
use tokio_tungstenite::connect_async;
use futures_util::StreamExt;

#[tokio::main]
async fn main() {
    let url = "wss://stream.binance.com:9443/ws/btcusdt@bookTicker";
    println!("Connecting to: {}", url);
    
    let (ws_stream, _) = connect_async(url).await.expect("Failed to connect");
    println!("Connected! Waiting for first 3 messages...\n");
    
    let (_write, mut read) = ws_stream.split();
    
    for i in 0..3 {
        if let Some(Ok(msg)) = read.next().await {
            if let tokio_tungstenite::tungstenite::Message::Text(text) = msg {
                println!("=== Message {} ===", i + 1);
                println!("{}", text);
                println!();
            }
        }
    }
}
