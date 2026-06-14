use actix_web::{ post, web, HttpRequest, HttpResponse, Responder};
use std::time::{Instant, Duration};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tracing::{error, info};
use sqlx::postgres::PgPool;
use tokio::sync::mpsc::{ Sender, Receiver};
 use crate::models::InternalLogItem;

 use crate::models::BulkOutput;
 use crate::models::BulkInput;
 use crate::models::AppState;
pub type LogChannelSender = Sender<InternalLogItem>;
pub type LogChannelReceiver = Receiver<InternalLogItem>;


#[post("/bulk-send")]
pub async fn bulk_send_message(
    state: web::Data<AppState>,
    tx: web::Data<LogChannelSender>,
    req: HttpRequest, 
    form: web::Json<BulkInput>
) -> impl Responder {
    let source = req.headers()
        .get("X-Source")
        .and_then(|val| val.to_str().ok())
        .unwrap_or("ECS")
        .to_uppercase();

    let count = form.record_count;
    
    state.latest_pipeline_time_ms.store(0, Ordering::Relaxed);

    let wave_start = Instant::now();
    let tx_clone = tx.get_ref().clone();
    let source_clone = source.clone();

    tokio::spawn(async move {
        for i in 1..=count {
            let log_item = InternalLogItem {
                message_id: uuid::Uuid::new_v4().to_string(),
                source_infra: source_clone.clone(),
                log_message: format!("Concurrent async system simulation telemetry message #{}", i),
                wave_start, 
            };

            if let Err(e) = tx_clone.send(log_item).await {
                error!("Background generator failed to queue item on the belt: {}", e);
                break;
            }
        }
        info!("Background generation complete. Successfully queued all {} items.", count);
    });

    HttpResponse::Accepted().json(BulkOutput {
        message: "Asynchronous background ingestion pipeline activated successfully.".to_string(),
        records_queued: count,
        time_taken_ms: 0,
    })
}


pub async fn run_background_consumer(
    mut receiver: LogChannelReceiver, 
    pool: PgPool, 
    metrics_handle: Arc<AtomicU64>
) {
    info!("Background infrastructure consumer task active and listening...");
    
    let mut buffer = Vec::with_capacity(2000);
    let max_batch_size = 100; 
    
    let mut ticker = tokio::time::interval(Duration::from_secs(2));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            Some(log_item) = receiver.recv() => {
                buffer.push(log_item);
                if buffer.len() >= max_batch_size {
                    flush_buffer_to_rds(&mut buffer, &pool, &metrics_handle).await;
                }
            }
            _ = ticker.tick() => {
                if !buffer.is_empty() {
                    flush_buffer_to_rds(&mut buffer, &pool, &metrics_handle).await;
                }
            }
            else => break,
        }
    }
}


async fn flush_buffer_to_rds(
    buffer: &mut Vec<InternalLogItem>, 
    pool: &PgPool, 
    metrics_handle: &Arc<AtomicU64>
) {
    let batch_wave_start = buffer.first().map(|item| item.wave_start);

    for item in buffer.iter() {
        let write_result = sqlx::query(
            "INSERT INTO central_logs (message_id, source_infra, log_message) VALUES ($1, $2, $3)"
        )
        .bind(&item.message_id)
        .bind(&item.source_infra)
        .bind(&item.log_message)
        .execute(pool)
        .await;

        if let Err(e) = write_result {
            error!("Failed to persist individual log record: {}", e);
        } else if let Some(start_time) = batch_wave_start {
            // Keep updating the atomic timer variable after every single individual insertion
            let total_elapsed = start_time.elapsed().as_millis() as u64;
            metrics_handle.store(total_elapsed, Ordering::Relaxed);
        }
    }

    buffer.clear();
}