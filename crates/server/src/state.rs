use std::sync::Arc;
use sui_sdk::{SuiClient, types::crypto::SuiKeyPair};

#[derive(Clone)]
pub struct AppState {
    pub sponsor_key: Arc<SuiKeyPair>,
    pub sui_client: Arc<SuiClient>,
}
