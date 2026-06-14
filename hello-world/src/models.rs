use serde::Serialize;
use std::collections::BTreeMap; 
use std::time::Instant;
use std::sync::Arc;
use std::sync::atomic::AtomicU64;
use sqlx::postgres::PgPool;

#[derive(Debug, Clone)]
pub struct InternalLogItem {
    pub message_id: String,
    pub source_infra: String,
    pub log_message: String,
    pub wave_start: Instant, 
}

#[derive(serde::Deserialize, Debug)] 
pub struct MessageInput {
    pub id: String,
    pub message: String,
}

#[derive(sqlx::FromRow, Debug)]
pub struct MetricsRow {
    pub source_infra: String,
    pub record_count: i64,
}

#[derive(Serialize)]
pub struct MetricsOutput {
    pub counts: BTreeMap<String, i64>,
    pub pipeline_time_ms: u64, 
}

#[derive(serde::Deserialize)]
pub struct BulkInput {
    pub record_count: usize,
}

#[derive(Serialize)]
pub struct BulkOutput {
    pub message: String,
    pub records_queued: usize,
    pub time_taken_ms: u128,
}

pub struct AppState {
    pub db_pool: PgPool,
    pub latest_pipeline_time_ms: Arc<AtomicU64>,
}