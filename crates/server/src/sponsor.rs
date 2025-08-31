use crate::state::AppState;

use axum::{
    extract::{Json, State},
    response::IntoResponse,
};
use sui_sdk::types::transaction::{SenderSignedData, TransactionData};

pub async fn sponsor_tx(
    State(state): State<AppState>,
    Json(tx): Json<TransactionData>,
) -> impl IntoResponse {
    let TransactionData::V1(tx_data) = &tx;
    println!("tx_data: {:?}", tx_data);
    Json(format!("resp"))
}
