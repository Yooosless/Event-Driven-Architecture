use std::time::Duration;
use serde::Serialize;
use tokio::time::sleep;
use uuid::Uuid;
use tracing::{info, error};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};
use sqlx::postgres::PgPoolOptions;

// AWS SDK Imports
use aws_sdk_s3::primitives::ByteStream;

#[derive(Serialize)]    
struct MessagePayload {
    id: String,
    message: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let aws_config = aws_config::load_from_env().await;
    let s3_client = aws_sdk_s3::Client::new(&aws_config);

    let s3_bucket_name = std::env::var("AWS_S3_BUCKET_NAME")
        .unwrap_or_else(|_| "afridi-poc-bucket".to_string());

    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL environment variable must be set");

    let infra_source = std::env::var("INFRA_SOURCE").unwrap_or_else(|_| "EC2".to_string());
    info!(source = %infra_source, bucket = %s3_bucket_name, "Background Engine initializing with S3 Role + RDS...");

    let pool = PgPoolOptions::new()
        .max_connections(3)
        .connect(&database_url)
        .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS central_logs (
            id SERIAL PRIMARY KEY,
            message_id TEXT NOT NULL,
            source_infra TEXT NOT NULL,
            s3_location TEXT NOT NULL,
            active BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )"
    ).execute(&pool).await?;

    let mut counter = 1;

    loop {
        let random_id = Uuid::new_v4().to_string();
        let current_message = format!("Why are you like this #{}", counter);
        
        let log_data = MessagePayload {
            id: random_id.clone(),
            message: current_message,
        };

        let yaml_string = match serde_yaml::to_string(&log_data) {
            Ok(yaml) => yaml,
            Err(e) => {
                error!(run = counter, "Failed to serialize log metadata to YAML: {}", e);
                continue;
            }
        };

        let s3_object_key = format!("{}/{}.yaml", infra_source, random_id);
        let s3_payload_bytes = ByteStream::from(yaml_string.into_bytes());

        info!(run = counter, key = %s3_object_key, "Streaming YAML file layout to S3...");
        let s3_upload = s3_client
            .put_object()
            .bucket(&s3_bucket_name)
            .key(&s3_object_key)
            .body(s3_payload_bytes)
            .content_type("application/x-yaml")
            .send()
            .await;

        match s3_upload {
            Ok(_) => {
                info!(run = counter, "YAML file saved to S3. Recording location pointer inside RDS...");

                let db_result = sqlx::query(
                    "INSERT INTO central_logs (message_id, source_infra, s3_location) VALUES ($1, $2, $3)"
                )
                .bind(&random_id)
                .bind(&infra_source)
                .bind(&s3_object_key) 
                .execute(&pool)
                .await;

                match db_result {
                    Ok(_) => info!(run = counter, "S3 YAML pointer successfully stored."),
                    Err(db_err) => error!("Postgres path pointer registration failed: {}", db_err),
                }
            }
            Err(s3_err) => {
                error!("AWS S3 Resource rejection: {}. Ensure your Terraform profile applied successfully.", s3_err);
            }
        }

        counter += 1;
        sleep(Duration::from_millis(200)).await; 
    }
}