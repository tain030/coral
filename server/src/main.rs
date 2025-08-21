// === 외부 모듈 임포트 ===
use anyhow::Result;
use axum::{
    Router,
    extract::{Json, State},
    response::IntoResponse,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use sui_sdk::{
    SuiClient, SuiClientBuilder,
    types::{base_types::SuiAddress, crypto::SuiKeyPair, transaction::TransactionData},
};
use tokio::net::TcpListener;

// === 표준 라이브러리 임포트 ===
use std::env;
use std::net::SocketAddr;
use std::sync::Arc;

// === 내부 모듈 임포트 ===
use crate::sponsor::*;
use crate::state::AppState;

pub mod sponsor;
pub mod state;

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    dotenvy::dotenv().ok();

    let sponsor_private_key =
        env::var("SPONSOR_PRIVATE_KEY").expect("SPONSOR_PRIVATE_KEY must be set in .env file");

    let sponsor_key =
        SuiKeyPair::decode(&sponsor_private_key).expect("Failed to parse SPONSOR_PRIVATE_KEY");
    println!("sponsor key: {:?}", sponsor_key.public());

    let sui_client = SuiClientBuilder::default().build_testnet().await?;
    let state = AppState {
        sponsor_key: Arc::new(sponsor_key),
        sui_client: Arc::new(sui_client),
    };

    let listener = TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], 3000))).await?;
    let app = Router::new()
        .route("/health", get(health))
        .route("/sponsor", post(sponsor_tx))
        .with_state(state);

    axum::serve(listener, app).await?;

    Ok(())
}

async fn health() -> &'static str {
    "OK"
}
