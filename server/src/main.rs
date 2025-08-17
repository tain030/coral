use nostr_sdk::prelude::*;
use sui_sdk::SuiClientBuilder;

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let sui_testnet = SuiClientBuilder::default().build_testnet().await?;

    Ok(())
}

