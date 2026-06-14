mod utils;
mod models;
mod bulk_test;
use actix_web::{web, App, HttpServer};
use std::sync::Arc;
use std::sync::atomic::AtomicU64;
use tracing::info;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};
use sqlx::postgres::PgPoolOptions;
use crate::models::AppState;
use crate::utils::{
    index, initialize_logging_pipeline, receive_messages, send_message,
};
use crate::bulk_test::{bulk_send_message};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres_user:SuperSecurePassword123@localhost:5432/messaging_db".to_string());

    info!("Initializing connection pool to AWS RDS PostgreSQL Instance...");
    
    let pool = PgPoolOptions::new()
        .max_connections(100)
        .connect(&database_url)
        .await
        .expect("Critical: Unable to establish link to central AWS RDS engine");

    let shared_metrics_atomic = Arc::new(AtomicU64::new(0));

    let tx = initialize_logging_pipeline(pool.clone(), shared_metrics_atomic.clone());

    let central_state = web::Data::new(AppState {
        db_pool: pool,
        latest_pipeline_time_ms: shared_metrics_atomic,
    });

    let channel_sender_data = web::Data::new(tx); 

    info!("Starting persistent microservice aggregator engine at http://0.0.0.0:8080");
    
    HttpServer::new(move || {
        App::new()
            .app_data(central_state.clone()) 
            .app_data(channel_sender_data.clone()) 
            .service(index)
            .service(send_message)
            .service(receive_messages)
            .service(bulk_send_message)
    })
    .bind(("0.0.0.0", 8080))?
    .run()
    .await
}