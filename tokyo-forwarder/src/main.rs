use futures_util::StreamExt;
use shared::{BinanceBookTickerEvent, ForwardedEvent};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use tokio::time::{sleep, Duration};
use tokio_tungstenite::{connect_async, tungstenite::Message};

/// Configuration for the Tokyo forwarder
#[derive(Debug, Clone)]
struct Config {
    binance_ws_url: String,
    frankfurt_ip: String,
    frankfurt_port: u16,
    reconnect_max_delay_secs: u64,
}

impl Config {
    fn from_args() -> Self {
        let args: Vec<String> = std::env::args().collect();

        // Default configuration
        let mut config = Config {
            binance_ws_url: "wss://stream.binance.com:9443/ws/btcusdt@bookTicker".to_string(),
            frankfurt_ip: "10.1.1.10".to_string(),
            frankfurt_port: 8080,
            reconnect_max_delay_secs: 30,
        };

        // Parse command-line arguments
        let mut i = 1;
        while i < args.len() {
            match args[i].as_str() {
                "--binance-url" => {
                    if i + 1 < args.len() {
                        config.binance_ws_url = args[i + 1].clone();
                        i += 2;
                    } else {
                        eprintln!("Error: --binance-url requires a value");
                        std::process::exit(1);
                    }
                }
                "--frankfurt-ip" => {
                    if i + 1 < args.len() {
                        config.frankfurt_ip = args[i + 1].clone();
                        i += 2;
                    } else {
                        eprintln!("Error: --frankfurt-ip requires a value");
                        std::process::exit(1);
                    }
                }
                "--frankfurt-port" | "--port" => {
                    if i + 1 < args.len() {
                        config.frankfurt_port = args[i + 1].parse().unwrap_or_else(|_| {
                            eprintln!("Error: Invalid port number");
                            std::process::exit(1);
                        });
                        i += 2;
                    } else {
                        eprintln!("Error: --frankfurt-port requires a value");
                        std::process::exit(1);
                    }
                }
                "--max-delay" => {
                    if i + 1 < args.len() {
                        config.reconnect_max_delay_secs =
                            args[i + 1].parse().unwrap_or_else(|_| {
                                eprintln!("Error: Invalid max delay");
                                std::process::exit(1);
                            });
                        i += 2;
                    } else {
                        eprintln!("Error: --max-delay requires a value");
                        std::process::exit(1);
                    }
                }
                "--help" | "-h" => {
                    println!("Tokyo Forwarder - Binance WebSocket to Frankfurt forwarder");
                    println!("\nUsage: tokyo-forwarder [OPTIONS]");
                    println!("\nOptions:");
                    println!("  --binance-url <URL>       Binance WebSocket URL (default: wss://stream.binance.com:9443/ws/btcusdt@bookTicker)");
                    println!(
                        "  --frankfurt-ip <IP>       Frankfurt EC2 private IP (default: 10.1.1.10)"
                    );
                    println!("  --frankfurt-port <PORT>   Frankfurt receiver port (default: 8080)");
                    println!("  --max-delay <SECONDS>     Max reconnection delay (default: 30)");
                    println!("  --help, -h                Show this help message");
                    std::process::exit(0);
                }
                _ => {
                    eprintln!("Error: Unknown argument: {}", args[i]);
                    eprintln!("Use --help for usage information");
                    std::process::exit(1);
                }
            }
        }

        config
    }
}

#[tokio::main]
async fn main() {
    let config = Config::from_args();

    println!("Tokyo Forwarder starting...");
    println!("Binance WebSocket: {}", config.binance_ws_url);
    println!(
        "Frankfurt target: {}:{}",
        config.frankfurt_ip, config.frankfurt_port
    );

    let sequence_counter = Arc::new(AtomicU64::new(0));

    loop {
        if let Err(e) = run_forwarder(config.clone(), sequence_counter.clone()).await {
            eprintln!("Forwarder error: {}. Restarting...", e);
            sleep(Duration::from_secs(5)).await;
        }
    }
}

async fn run_forwarder(
    config: Config,
    sequence_counter: Arc<AtomicU64>,
) -> Result<(), Box<dyn std::error::Error>> {
    // Connect to Frankfurt TCP endpoint
    let mut tcp_stream = connect_to_frankfurt(&config).await?;
    println!(
        "Connected to Frankfurt at {}:{}",
        config.frankfurt_ip, config.frankfurt_port
    );

    // Connect to Binance WebSocket
    let mut ws_stream = connect_to_binance(&config).await?;
    println!("Connected to Binance WebSocket");

    // Process messages
    while let Some(msg_result) = ws_stream.next().await {
        match msg_result {
            Ok(Message::Text(text)) => {
                // Record timestamp immediately upon receiving message
                let tokyo_receive_timestamp = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos() as i64;

                // Parse the Binance event to get timestamp
                match serde_json::from_str::<BinanceBookTickerEvent>(&text) {
                    Ok(event) => {
                        // Assign sequence ID
                        let sequence_id = sequence_counter.fetch_add(1, Ordering::SeqCst);

                        // Create forwarded event with Binance's event time
                        let forwarded_event = ForwardedEvent {
                            sequence_id,
                            tokyo_receive_timestamp,
                            binance_event_time: event.event_time, // Use Binance's event time (milliseconds)
                            event_data: text,
                        };

                        // Serialize and send to Frankfurt
                        match serde_json::to_string(&forwarded_event) {
                            Ok(json) => {
                                let message = format!("{}\n", json);
                                if let Err(e) = tcp_stream.write_all(message.as_bytes()).await {
                                    eprintln!(
                                        "Failed to send to Frankfurt: {}. Reconnecting...",
                                        e
                                    );
                                    tcp_stream = reconnect_to_frankfurt(&config).await?;
                                    // Retry sending
                                    tcp_stream.write_all(message.as_bytes()).await?;
                                }
                            }
                            Err(e) => {
                                eprintln!("Failed to serialize forwarded event: {}", e);
                            }
                        }
                    }
                    Err(e) => {
                        eprintln!("Failed to parse Binance event: {}", e);
                    }
                }
            }
            Ok(Message::Close(_)) => {
                println!("WebSocket closed by server. Reconnecting...");
                ws_stream = reconnect_to_binance(&config).await?;
            }
            Ok(_) => {
                // Ignore other message types (Binary, Ping, Pong)
            }
            Err(e) => {
                eprintln!("WebSocket error: {}. Reconnecting...", e);
                ws_stream = reconnect_to_binance(&config).await?;
            }
        }
    }

    Ok(())
}

async fn connect_to_binance(
    config: &Config,
) -> Result<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
    Box<dyn std::error::Error>,
> {
    println!("Connecting to Binance WebSocket...");
    let (ws_stream, _) = connect_async(&config.binance_ws_url).await?;
    Ok(ws_stream)
}

async fn reconnect_to_binance(
    config: &Config,
) -> Result<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
    Box<dyn std::error::Error>,
> {
    let mut delay = 1;
    loop {
        println!(
            "Attempting to reconnect to Binance WebSocket (delay: {}s)...",
            delay
        );
        sleep(Duration::from_secs(delay)).await;

        match connect_to_binance(config).await {
            Ok(stream) => {
                println!("Successfully reconnected to Binance WebSocket");
                return Ok(stream);
            }
            Err(e) => {
                eprintln!("Reconnection failed: {}", e);
                delay = std::cmp::min(delay * 2, config.reconnect_max_delay_secs);
            }
        }
    }
}

async fn connect_to_frankfurt(config: &Config) -> Result<TcpStream, Box<dyn std::error::Error>> {
    println!(
        "Connecting to Frankfurt at {}:{}...",
        config.frankfurt_ip, config.frankfurt_port
    );
    let addr = format!("{}:{}", config.frankfurt_ip, config.frankfurt_port);
    let stream = TcpStream::connect(&addr).await?;
    Ok(stream)
}

async fn reconnect_to_frankfurt(config: &Config) -> Result<TcpStream, Box<dyn std::error::Error>> {
    let mut delay = 1;
    loop {
        println!(
            "Attempting to reconnect to Frankfurt (delay: {}s)...",
            delay
        );
        sleep(Duration::from_secs(delay)).await;

        match connect_to_frankfurt(config).await {
            Ok(stream) => {
                println!("Successfully reconnected to Frankfurt");
                return Ok(stream);
            }
            Err(e) => {
                eprintln!("Reconnection failed: {}", e);
                delay = std::cmp::min(delay * 2, config.reconnect_max_delay_secs);
            }
        }
    }
}
