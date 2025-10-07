// Shared data structures for the Binance latency experiment

use serde::{Deserialize, Serialize};

/// Binance book ticker event structure
/// Matches the JSON format from Binance WebSocket bookTicker stream
#[derive(Debug, Clone, Deserialize)]
pub struct BinanceBookTickerEvent {
    #[serde(rename = "e")]
    pub event_type: String, // Event type ("bookTicker")

    #[serde(rename = "u")]
    pub update_id: i64, // Order book updateId

    #[serde(rename = "E")]
    pub event_time: i64, // Event time (milliseconds)

    #[serde(rename = "T")]
    pub transaction_time: i64, // Transaction time (milliseconds)

    #[serde(rename = "s")]
    pub symbol: String, // Symbol (BTCUSDT)

    #[serde(rename = "b")]
    pub best_bid_price: String, // Best bid price

    #[serde(rename = "B")]
    pub best_bid_qty: String, // Best bid quantity

    #[serde(rename = "a")]
    pub best_ask_price: String, // Best ask price

    #[serde(rename = "A")]
    pub best_ask_qty: String, // Best ask quantity
}

/// Event forwarded from Tokyo to Frankfurt
/// Contains original Binance data plus Tokyo timestamps
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ForwardedEvent {
    pub sequence_id: u64,             // Incrementing event ID for tracking
    pub tokyo_receive_timestamp: i64, // When Tokyo received from Binance (epoch nanos)
    pub binance_event_time: i64,      // Original Binance event time (E field)
    pub event_data: String,           // Raw JSON from Binance
}

/// Latency measurement for a single event
#[derive(Debug, Clone)]
pub struct LatencyMeasurement {
    pub sequence_id: u64,
    pub binance_event_time: i64,          // Binance timestamp (ms)
    pub tokyo_receive_time: Option<i64>,  // Only for AWS backbone mode (epoch nanos)
    pub frankfurt_receive_time: i64,      // Frankfurt arrival (epoch nanos)
    pub end_to_end_latency_ms: f64,       // Binance to Frankfurt
    pub backbone_latency_ms: Option<f64>, // Tokyo to Frankfurt (AWS backbone only)
}

impl LatencyMeasurement {
    /// Create a new latency measurement for baseline mode (direct Binance → Frankfurt)
    pub fn new_baseline(
        sequence_id: u64,
        binance_event_time: i64,
        frankfurt_receive_time: i64,
    ) -> Self {
        let end_to_end_latency_ms =
            (frankfurt_receive_time as f64 / 1_000_000.0) - binance_event_time as f64;

        Self {
            sequence_id,
            binance_event_time,
            tokyo_receive_time: None,
            frankfurt_receive_time,
            end_to_end_latency_ms,
            backbone_latency_ms: None,
        }
    }

    /// Create a new latency measurement for AWS backbone mode (Binance → Tokyo → Frankfurt)
    pub fn new_aws_backbone(
        sequence_id: u64,
        binance_event_time: i64,
        tokyo_receive_time: i64,
        frankfurt_receive_time: i64,
    ) -> Self {
        let end_to_end_latency_ms =
            (frankfurt_receive_time as f64 / 1_000_000.0) - binance_event_time as f64;
        let backbone_latency_ms =
            (frankfurt_receive_time - tokyo_receive_time) as f64 / 1_000_000.0;

        Self {
            sequence_id,
            binance_event_time,
            tokyo_receive_time: Some(tokyo_receive_time),
            frankfurt_receive_time,
            end_to_end_latency_ms,
            backbone_latency_ms: Some(backbone_latency_ms),
        }
    }

    /// Write measurements to CSV file
    pub fn write_to_csv(
        measurements: &[LatencyMeasurement],
        filepath: &str,
    ) -> Result<(), std::io::Error> {
        use std::io::Write;

        let mut file = std::fs::File::create(filepath)?;

        // Write CSV header
        writeln!(
            file,
            "sequence_id,binance_time,tokyo_time,frankfurt_time,latency_ms,backbone_latency_ms"
        )?;

        // Write each measurement
        for m in measurements {
            writeln!(
                file,
                "{},{},{},{},{:.3},{}",
                m.sequence_id,
                m.binance_event_time,
                m.tokyo_receive_time
                    .map_or(String::new(), |t| t.to_string()),
                m.frankfurt_receive_time,
                m.end_to_end_latency_ms,
                m.backbone_latency_ms
                    .map_or(String::new(), |l| format!("{:.3}", l))
            )?;
        }

        Ok(())
    }
}

/// Results of a latency experiment
#[derive(Debug, Clone, Serialize)]
pub struct ExperimentResults {
    pub setup_type: String, // "baseline" or "aws-backbone"
    pub sample_count: usize,
    pub events_lost: usize, // Missing sequence IDs

    // End-to-end latency (Binance → Frankfurt)
    pub avg_latency_ms: f64,
    pub median_latency_ms: f64,
    pub p95_latency_ms: f64,
    pub p99_latency_ms: f64,
    pub min_latency_ms: f64,
    pub max_latency_ms: f64,

    // Jitter (variance in latency)
    pub jitter_stddev_ms: f64,

    // AWS backbone specific (Tokyo → Frankfurt)
    pub backbone_avg_latency_ms: Option<f64>,
    pub backbone_median_latency_ms: Option<f64>,
}

impl ExperimentResults {
    /// Calculate statistics from a vector of latency measurements
    pub fn from_measurements(
        setup_type: String,
        measurements: Vec<LatencyMeasurement>,
        events_lost: usize,
    ) -> Self {
        let sample_count = measurements.len();

        if sample_count == 0 {
            return Self {
                setup_type,
                sample_count: 0,
                events_lost,
                avg_latency_ms: 0.0,
                median_latency_ms: 0.0,
                p95_latency_ms: 0.0,
                p99_latency_ms: 0.0,
                min_latency_ms: 0.0,
                max_latency_ms: 0.0,
                jitter_stddev_ms: 0.0,
                backbone_avg_latency_ms: None,
                backbone_median_latency_ms: None,
            };
        }

        // Sort latencies for percentile calculations
        let mut latencies: Vec<f64> = measurements
            .iter()
            .map(|m| m.end_to_end_latency_ms)
            .collect();
        latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());

        // Calculate statistics
        let avg_latency_ms = latencies.iter().sum::<f64>() / sample_count as f64;
        let median_latency_ms = Self::percentile(&latencies, 0.50);
        let p95_latency_ms = Self::percentile(&latencies, 0.95);
        let p99_latency_ms = Self::percentile(&latencies, 0.99);
        let min_latency_ms = latencies[0];
        let max_latency_ms = latencies[sample_count - 1];

        // Calculate jitter (standard deviation)
        let variance = latencies
            .iter()
            .map(|l| {
                let diff = l - avg_latency_ms;
                diff * diff
            })
            .sum::<f64>()
            / sample_count as f64;
        let jitter_stddev_ms = variance.sqrt();

        // Calculate backbone statistics if available
        let backbone_latencies: Vec<f64> = measurements
            .iter()
            .filter_map(|m| m.backbone_latency_ms)
            .collect();

        let (backbone_avg_latency_ms, backbone_median_latency_ms) =
            if !backbone_latencies.is_empty() {
                let mut sorted_backbone = backbone_latencies.clone();
                sorted_backbone.sort_by(|a, b| a.partial_cmp(b).unwrap());

                let avg = sorted_backbone.iter().sum::<f64>() / sorted_backbone.len() as f64;
                let median = Self::percentile(&sorted_backbone, 0.50);
                (Some(avg), Some(median))
            } else {
                (None, None)
            };

        Self {
            setup_type,
            sample_count,
            events_lost,
            avg_latency_ms,
            median_latency_ms,
            p95_latency_ms,
            p99_latency_ms,
            min_latency_ms,
            max_latency_ms,
            jitter_stddev_ms,
            backbone_avg_latency_ms,
            backbone_median_latency_ms,
        }
    }

    /// Calculate percentile from sorted data
    fn percentile(sorted_data: &[f64], percentile: f64) -> f64 {
        let len = sorted_data.len();
        if len == 0 {
            return 0.0;
        }
        if len == 1 {
            return sorted_data[0];
        }

        let index = percentile * (len - 1) as f64;
        let lower = index.floor() as usize;
        let upper = index.ceil() as usize;
        let weight = index - lower as f64;

        sorted_data[lower] * (1.0 - weight) + sorted_data[upper] * weight
    }
}
