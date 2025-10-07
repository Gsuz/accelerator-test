use clap::Parser;
use futures_util::StreamExt;
use shared::{BinanceBookTickerEvent, ExperimentResults, ForwardedEvent, LatencyMeasurement};
use std::collections::HashSet;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

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
        default_value = "wss://stream.binance.com:9443/ws/btcusdt@aggTrade"
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

    // Per-second tracking
    let mut last_second_report = std::time::Instant::now();
    let mut events_this_second = 0u64;
    let mut latencies_this_second = Vec::new();

    println!("Collecting data for {} seconds...", args.duration);
    println!("Time | Events/s | Avg Latency | Min | Max");
    println!("-----|----------|-------------|-----|-----");

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
                    // Debug: Print first message to see format
                    if sequence_id == 0 {
                        println!("First message received: {}", text);
                    }

                    // Parse JSON to get Binance event with timestamp
                    match serde_json::from_str::<BinanceBookTickerEvent>(&text) {
                        Ok(event) => {
                            // Calculate latency using Binance's event time (E field)
                            // event_time is in milliseconds, frankfurt_receive_time is in nanoseconds
                            let measurement = LatencyMeasurement::new_baseline(
                                sequence_id,
                                event.event_time, // Binance event time in milliseconds
                                frankfurt_receive_time,
                            );

                            // Track for per-second stats
                            events_this_second += 1;
                            latencies_this_second.push(measurement.end_to_end_latency_ms);

                            measurements.push(measurement);
                            sequence_id += 1;

                            // Report stats every second
                            if last_second_report.elapsed() >= Duration::from_secs(1) {
                                if !latencies_this_second.is_empty() {
                                    let avg = latencies_this_second.iter().sum::<f64>()
                                        / latencies_this_second.len() as f64;
                                    let min = latencies_this_second
                                        .iter()
                                        .cloned()
                                        .fold(f64::INFINITY, f64::min);
                                    let max = latencies_this_second
                                        .iter()
                                        .cloned()
                                        .fold(f64::NEG_INFINITY, f64::max);

                                    let elapsed_secs = start_time.elapsed().as_secs();
                                    println!(
                                        "{:>4}s | {:>8} | {:>9.2} ms | {:>3.0} | {:>3.0}",
                                        elapsed_secs, events_this_second, avg, min, max
                                    );
                                }

                                // Reset counters
                                events_this_second = 0;
                                latencies_this_second.clear();
                                last_second_report = std::time::Instant::now();
                            }
                        }
                        Err(e) => {
                            if sequence_id < 5 {
                                eprintln!("Failed to parse message: {}", e);
                                eprintln!("Message was: {}", text);
                            }
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
    println!("Starting AWS backbone mode (UDP)");
    println!("Listening on port: {}", args.port);

    // Bind UDP socket to configured port
    let socket = tokio::net::UdpSocket::bind(format!("0.0.0.0:{}", args.port)).await?;
    println!("UDP socket bound to 0.0.0.0:{}", args.port);
    println!("Waiting for data from Tokyo forwarder...");

    let mut buf = vec![0u8; 65536]; // Max UDP packet size
    let mut measurements = Vec::new();
    let mut received_sequence_ids = HashSet::new();
    let start_time = std::time::Instant::now();
    let duration = Duration::from_secs(args.duration);

    // Per-second tracking
    let mut last_second_report = std::time::Instant::now();
    let mut events_this_second = 0u64;
    let mut e2e_latencies_this_second = Vec::new();
    let mut backbone_latencies_this_second = Vec::new();

    println!("Collecting data for {} seconds...", args.duration);
    println!("Time | Events/s | E2E Latency | Backbone | Min E2E | Max E2E");
    println!("-----|----------|-------------|----------|---------|--------");

    // Receive events with timeout
    loop {
        let elapsed = start_time.elapsed();
        if elapsed >= duration {
            println!("Duration reached, stopping collection");
            break;
        }

        let remaining = duration - elapsed;

        match timeout(remaining, socket.recv_from(&mut buf)).await {
            Ok(Ok((len, _addr))) => {
                // Record Frankfurt arrival timestamp immediately
                let frankfurt_receive_time =
                    SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos() as i64;

                // Parse the received data
                let data = &buf[..len];
                if let Ok(data_str) = std::str::from_utf8(data) {
                    // Deserialize ForwardedEvent
                    if let Ok(event) = serde_json::from_str::<ForwardedEvent>(data_str) {
                        // Track sequence ID
                        received_sequence_ids.insert(event.sequence_id);

                        // Calculate latencies
                        let measurement = LatencyMeasurement::new_aws_backbone(
                            event.sequence_id,
                            event.binance_event_time,
                            event.tokyo_receive_timestamp,
                            frankfurt_receive_time,
                        );

                        // Track for per-second stats
                        events_this_second += 1;
                        e2e_latencies_this_second.push(measurement.end_to_end_latency_ms);
                        if let Some(backbone) = measurement.backbone_latency_ms {
                            backbone_latencies_this_second.push(backbone);
                        }

                        measurements.push(measurement);

                        // Report stats every second
                        if last_second_report.elapsed() >= Duration::from_secs(1) {
                            if !e2e_latencies_this_second.is_empty() {
                                let avg_e2e = e2e_latencies_this_second.iter().sum::<f64>()
                                    / e2e_latencies_this_second.len() as f64;
                                let min_e2e = e2e_latencies_this_second
                                    .iter()
                                    .cloned()
                                    .fold(f64::INFINITY, f64::min);
                                let max_e2e = e2e_latencies_this_second
                                    .iter()
                                    .cloned()
                                    .fold(f64::NEG_INFINITY, f64::max);

                                let avg_backbone = if !backbone_latencies_this_second.is_empty() {
                                    backbone_latencies_this_second.iter().sum::<f64>()
                                        / backbone_latencies_this_second.len() as f64
                                } else {
                                    0.0
                                };

                                let elapsed_secs = start_time.elapsed().as_secs();
                                println!(
                                    "{:>4}s | {:>8} | {:>9.2} ms | {:>6.2} ms | {:>7.0} | {:>7.0}",
                                    elapsed_secs,
                                    events_this_second,
                                    avg_e2e,
                                    avg_backbone,
                                    min_e2e,
                                    max_e2e
                                );
                            }

                            // Reset counters
                            events_this_second = 0;
                            e2e_latencies_this_second.clear();
                            backbone_latencies_this_second.clear();
                            last_second_report = std::time::Instant::now();
                        }
                    } else {
                        eprintln!("Failed to parse ForwardedEvent");
                    }
                } else {
                    eprintln!("Failed to parse UTF-8");
                }
            }
            Ok(Err(e)) => {
                eprintln!("UDP recv error: {}", e);
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
