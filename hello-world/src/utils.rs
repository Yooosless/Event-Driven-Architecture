use crate::models::AppState;
use crate::models::InternalLogItem;
use crate::models::MessageInput;
use crate::models::MetricsOutput;
use crate::models::MetricsRow;
use actix_web::{HttpRequest, HttpResponse, Responder, get, post, web};
use sqlx::postgres::PgPool;
use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::sync::mpsc::{Receiver, Sender, channel};
use tracing::{error, info};
pub type LogChannelSender = Sender<InternalLogItem>;
pub type LogChannelReceiver = Receiver<InternalLogItem>;
use crate::bulk_test::run_background_consumer;

pub fn initialize_logging_pipeline(
    pool: PgPool,
    metrics_handle: Arc<AtomicU64>,
) -> LogChannelSender {
    info!("Initializing core async Tokio channel infrastructure...");

    let (tx, rx): (LogChannelSender, LogChannelReceiver) = channel(50000);

    tokio::spawn(async move {
        run_background_consumer(rx, pool, metrics_handle).await;
    });

    tx
}

#[get("/")]
pub async fn index() -> impl Responder {
    info!("GET / - Serving generic multi-box telemetry UI");
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(include_str!("index.html"))
}

#[post("/send")]
pub async fn send_message(
    state: web::Data<AppState>,
    req: HttpRequest,
    form: web::Json<MessageInput>,
) -> impl Responder {
    let source = req
        .headers()
        .get("X-Source")
        .and_then(|val| val.to_str().ok())
        .unwrap_or("EC2")
        .to_uppercase();

    let formatted_string = form.message.clone();
    if formatted_string.trim().is_empty() {
        return HttpResponse::BadRequest().json("Empty payloads rejected");
    }

    info!(id = %form.id, source = %source, "POST /send - Writing active payload directly to AWS RDS...");

    let insert_result = sqlx::query(
        "INSERT INTO central_logs (message_id, source_infra, log_message) VALUES ($1, $2, $3)",
    )
    .bind(&form.id)
    .bind(&source)
    .bind(&formatted_string)
    .execute(&state.db_pool)
    .await;

    match insert_result {
        Ok(_) => HttpResponse::Ok().json("Message processed and saved to RDS successfully!"),
        Err(err) => {
            error!("Failed to persist log in RDS: {}", err);
            HttpResponse::InternalServerError().json("Database persistence failure")
        }
    }
}

#[get("/receive")]
pub async fn receive_messages(state: web::Data<AppState>) -> impl Responder {
    // Captures currently active rows, groups them for the counter cards, and marks them inactive
    let metrics_query = sqlx::query_as::<_, MetricsRow>(
        "WITH targeted_rows AS (
            SELECT id, source_infra 
            FROM central_logs 
            WHERE active = true
         ),
         update_phase AS (
            UPDATE central_logs
            SET active = false
            WHERE id IN (SELECT id FROM targeted_rows)
         )
         SELECT source_infra, COUNT(*) as record_count 
         FROM targeted_rows 
         GROUP BY source_infra",
    )
    .fetch_all(&state.db_pool)
    .await;

    let current_metric = state.latest_pipeline_time_ms.load(Ordering::Relaxed);

    match metrics_query {
        Ok(rows) => {
            let mut counts = BTreeMap::new();
            counts.insert("EC2".to_string(), 0);
            counts.insert("ECS".to_string(), 0);
            counts.insert("EKS".to_string(), 0);

            for row in rows {
                counts.insert(row.source_infra, row.record_count);
            }

            HttpResponse::Ok().json(MetricsOutput {
                counts,
                pipeline_time_ms: current_metric,
            })
        }
        Err(err) => {
            error!(
                "Database transactional metric group extraction error: {}",
                err
            );
            HttpResponse::InternalServerError().body("Failed to process aggregate telemetry logs")
        }
    }
}
