use clap::Parser;
use futures_util::StreamExt;
use shared::{BinanceBookTickerEvent, ExperimentResults, ForwardedEvent, LatencyMeasurement};
use std::collections::HashSet;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::net::TcpListener;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[derive(Parser, Debug)]
#[command(name = "frankfurt-receiver")]
#[command(about = "Frankfurt receiver for Binance latency experiment")]
struct Args {
    /// Mode: baseline or aws-backbone
    #[arg(long, default_value = "baseline")]
    mode: String,

    /// Duration to collect data in seconds
    #[arg(long, default_value = "60")]
    duration: u64,

    /// Output file path for results (JSON)
    #[arg(long, default_value = "results.json")]
    output: String,

    /// CSV output file path for raw measurements (optional)
    #[arg(long)]
    csv_output: Option<String>,

    /// Binance WebSocket URL (baseline mode only)
    #[arg(
        long,
        default_value = "wss://stream.binance.com:9443/ws/btcusdt@bookTicker"
    )]
    binance_url: String,

    /// Listen port (aws-backbone mode only)
    #[arg(long, default_value = "8080")]
    port: u16,
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    println!("Frankfurt Receiver starting...");
    println!("Mode: {}", args.mode);
    println!("Duration: {} seconds", args.duration);
    println!("Output file: {}", args.output);

    match args.mode.as_str() {
        "baseline" => {
            if let Err(e) = run_baseline_mode(&args).await {
                eprintln!("Error in baseline mode: {}", e);
                std::process::exit(1);
            }
        }
        "aws-backbone" => {
            if let Err(e) = run_aws_backbone_mode(&args).await {
                eprintln!("Error in AWS backbone mode: {}", e);
                std::process::exit(1);
            }
        }
        _ => {
            eprintln!(
                "Invalid mode: {}. Must be 'baseline' or 'aws-backbone'",
                args.mode
            );
            std::process::exit(1);
        }
    }
}

async fn run_baseline_mode(args: &Args) -> Result<(), Box<dyn std::error::Error>> {
    println!("Connecting to Binance WebSocket: {}", args.binance_url);

    // Connect to Binance WebSocket
    let (ws_stream, _) = connect_async(&args.binance_url).await?;
    println!("Connected to Binance WebSocket");

    let (_write, mut read) = ws_stream.split();

    let mut measurements = Vec::new();
    let mut sequence_id = 0u64;
    let start_time = std::time::Instant::now();
    let duration = Duration::from_secs(args.duration);

    println!("Collecting data for {} seconds...", args.duration);

    // Receive messages with timeout
    loop {
        let elapsed = start_time.elapsed();
        if elapsed >= duration {
            println!("Duration reached, stopping collection");
            break;
        }

        let remaining = duration - elapsed;
        match timeout(remaining, read.next()).await {
            Ok(Some(Ok(msg))) => {
                // Record timestamp immediately upon receiving message
                let frankfurt_receive_time =
                    SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos() as i64;

                if let Message::Text(text) = msg {
                    // Parse JSON to validate format
                    if let Ok(_event) = serde_json::from_str::<BinanceBookTickerEvent>(&text) {
                        // Calculate latency
                        // Note: Since bookTicker stream doesn't include timestamps,
                        // we use frankfurt_receive_time as both the event time and receive time
                        // This means baseline mode measures near-zero latency, but that's expected
                        // since we're receiving directly from Binance
                        let measurement = LatencyMeasurement::new_baseline(
                            sequence_id,
                            frankfurt_receive_time / 1_000_000, // Convert nanos to millis for consistency
                            frankfurt_receive_time,
                        );

                        measurements.push(measurement);
                        sequence_id += 1;

                        if sequence_id % 100 == 0 {
                            // Calculate stats for last 100 measurements
                            let recent: Vec<f64> = measurements
                                .iter()
                                .rev()
                                .take(100)
                                .map(|m| m.end_to_end_latency_ms)
                                .collect();
                            let avg = recent.iter().sum::<f64>() / recent.len() as f64;
                            println!(
                                "Collected {} measurements | Last 100 avg: {:.2} ms",
                                sequence_id, avg
                            );
                        }
                    }
                }
            }
            Ok(Some(Err(e))) => {
                eprintln!("WebSocket error: {}", e);
                break;
            }
            Ok(None) => {
                println!("WebSocket connection closed");
                break;
            }
            Err(_) => {
                println!("Timeout reached");
                break;
            }
        }
    }

    println!(
        "Collection complete. Total measurements: {}",
        measurements.len()
    );

    // Write CSV output if requested (before consuming measurements)
    if let Some(csv_path) = &args.csv_output {
        LatencyMeasurement::write_to_csv(&measurements, csv_path)?;
        println!("Raw measurements written to {}", csv_path);
    }

    // Calculate and output results
    let results = ExperimentResults::from_measurements(
        "baseline".to_string(),
        measurements,
        0, // No packet loss tracking in baseline mode
    );

    // Write results to file
    let results_json = serde_json::to_string_pretty(&results)?;
    std::fs::write(&args.output, results_json)?;
    println!("Results written to {}", args.output);

    // Print summary to console
    println!("\n=== Experiment Results ===");
    println!("Setup: {}", results.setup_type);
    println!("Samples: {}", results.sample_count);
    println!("Average latency: {:.2} ms", results.avg_latency_ms);
    println!("Median latency: {:.2} ms", results.median_latency_ms);
    println!("P95 latency: {:.2} ms", results.p95_latency_ms);
    println!("P99 latency: {:.2} ms", results.p99_latency_ms);
    println!("Min latency: {:.2} ms", results.min_latency_ms);
    println!("Max latency: {:.2} ms", results.max_latency_ms);
    println!("Jitter (stddev): {:.2} ms", results.jitter_stddev_ms);

    Ok(())
}

async fn run_aws_backbone_mode(args: &Args) -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting AWS backbone mode");
    println!("Listening on port: {}", args.port);

    // Bind TCP listener to configured port
    let listener = TcpListener::bind(format!("0.0.0.0:{}", args.port)).await?;
    println!("TCP listener bound to 0.0.0.0:{}", args.port);

    // Accept connection from Tokyo forwarder
    println!("Waiting for connection from Tokyo forwarder...");
    let (socket, addr) = listener.accept().await?;
    println!("Accepted connection from: {}", addr);

    let mut reader = BufReader::new(socket);
    let mut measurements = Vec::new();
    let mut received_sequence_ids = HashSet::new();
    let start_time = std::time::Instant::now();
    let duration = Duration::from_secs(args.duration);

    println!("Collecting data for {} seconds...", args.duration);

    let mut line = String::new();

    // Receive events with timeout
    loop {
        let elapsed = start_time.elapsed();
        if elapsed >= duration {
            println!("Duration reached, stopping collection");
            break;
        }

        let remaining = duration - elapsed;
        line.clear();

        match timeout(remaining, reader.read_line(&mut line)).await {
            Ok(Ok(0)) => {
                println!("Connection closed by Tokyo forwarder");
                break;
            }
            Ok(Ok(_)) => {
                // Record Frankfurt arrival timestamp immediately
                let frankfurt_receive_time =
                    SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos() as i64;

                // Deserialize ForwardedEvent
                if let Ok(event) = serde_json::from_str::<ForwardedEvent>(line.trim()) {
                    // Track sequence ID
                    received_sequence_ids.insert(event.sequence_id);

                    // Calculate latencies
                    let measurement = LatencyMeasurement::new_aws_backbone(
                        event.sequence_id,
                        event.binance_event_time,
                        event.tokyo_receive_timestamp,
                        frankfurt_receive_time,
                    );

                    measurements.push(measurement);

                    if received_sequence_ids.len() % 100 == 0 {
                        // Calculate stats for last 100 measurements
                        let recent_e2e: Vec<f64> = measurements
                            .iter()
                            .rev()
                            .take(100)
                            .map(|m| m.end_to_end_latency_ms)
                            .collect();
                        let recent_backbone: Vec<f64> = measurements
                            .iter()
                            .rev()
                            .take(100)
                            .filter_map(|m| m.backbone_latency_ms)
                            .collect();

                        let avg_e2e = recent_e2e.iter().sum::<f64>() / recent_e2e.len() as f64;
                        let avg_backbone = if !recent_backbone.is_empty() {
                            recent_backbone.iter().sum::<f64>() / recent_backbone.len() as f64
                        } else {
                            0.0
                        };

                        println!(
                            "Collected {} measurements | Last 100 avg - E2E: {:.2} ms, Backbone: {:.2} ms",
                            received_sequence_ids.len(), avg_e2e, avg_backbone
                        );
                    }
                } else {
                    eprintln!("Failed to parse ForwardedEvent: {}", line.trim());
                }
            }
            Ok(Err(e)) => {
                eprintln!("TCP read error: {}", e);
                break;
            }
            Err(_) => {
                println!("Timeout reached");
                break;
            }
        }
    }

    println!(
        "Collection complete. Total measurements: {}",
        measurements.len()
    );

    // Detect packet loss by checking for gaps in sequence IDs
    let events_lost = if !received_sequence_ids.is_empty() {
        let min_seq = *received_sequence_ids.iter().min().unwrap();
        let max_seq = *received_sequence_ids.iter().max().unwrap();
        let expected_count = (max_seq - min_seq + 1) as usize;
        let actual_count = received_sequence_ids.len();
        expected_count - actual_count
    } else {
        0
    };

    if events_lost > 0 {
        println!(
            "Warning: {} events lost (gaps in sequence IDs)",
            events_lost
        );
    }

    // Write CSV output if requested (before consuming measurements)
    if let Some(csv_path) = &args.csv_output {
        LatencyMeasurement::write_to_csv(&measurements, csv_path)?;
        println!("Raw measurements written to {}", csv_path);
    }

    // Calculate and output results
    let results =
        ExperimentResults::from_measurements("aws-backbone".to_string(), measurements, events_lost);

    // Write results to file
    let results_json = serde_json::to_string_pretty(&results)?;
    std::fs::write(&args.output, results_json)?;
    println!("Results written to {}", args.output);

    // Print summary to console
    println!("\n=== Experiment Results ===");
    println!("Setup: {}", results.setup_type);
    println!("Samples: {}", results.sample_count);
    println!("Events lost: {}", results.events_lost);
    println!("Average latency: {:.2} ms", results.avg_latency_ms);
    println!("Median latency: {:.2} ms", results.median_latency_ms);
    println!("P95 latency: {:.2} ms", results.p95_latency_ms);
    println!("P99 latency: {:.2} ms", results.p99_latency_ms);
    println!("Min latency: {:.2} ms", results.min_latency_ms);
    println!("Max latency: {:.2} ms", results.max_latency_ms);
    println!("Jitter (stddev): {:.2} ms", results.jitter_stddev_ms);

    if let Some(backbone_avg) = results.backbone_avg_latency_ms {
        println!("\n=== AWS Backbone Latency (Tokyo → Frankfurt) ===");
        println!("Average backbone latency: {:.2} ms", backbone_avg);
        if let Some(backbone_median) = results.backbone_median_latency_ms {
            println!("Median backbone latency: {:.2} ms", backbone_median);
        }
    }

    Ok(())
}
