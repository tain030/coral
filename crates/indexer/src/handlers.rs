// 외부 라이브러리
use anyhow::Result;
use sui_indexer_alt_framework::{
    pipeline::{Processor, sequential::Handler},
    postgres::{Connection, Db},
    types::full_checkpoint_content::CheckpointData,
};
use diesel_async::RunQueryDsl;
// 표준 라이브러리
use crate::models::StoredTransactionDigest;
use crate::schema::transaction_digests::dsl::*;
use std::sync::Arc;

pub struct TransactionDigestHandler;

impl Processor for TransactionDigestHandler {
    const NAME: &'static str = "transaction_digest_handler";
    type VALUE = StoredTransactionDigest;

    fn process(&self, checkpoint: &Arc<CheckpointData>) -> Result<Vec<Self::VALUE>> {
        let checkpoint_seq = checkpoint.checkpoint_summary.sequence_number as i64;

        let digests = checkpoint
            .transactions
            .iter()
            .map(|tx| StoredTransactionDigest {
                tx_digest: tx.transaction.digest().to_string(),
                checkpoint_sequence_number: checkpoint_seq,
            })
            .collect();

        Ok(digests)
    }
}

#[async_trait::async_trait]
impl Handler for TransactionDigestHandler {
    type Store = Db;
    type Batch = Vec<Self::VALUE>;

    fn batch(batch: &mut Self::Batch, values: Vec<Self::VALUE>) {
        batch.extend(values);
    }

    async fn commit<'a>(
        batch: &Self::Batch,
        conn: &mut Connection<'a>,
    ) -> Result<usize> {
        let inserted = diesel::insert_into(transaction_digests)
            .values(batch)
            .on_conflict(tx_digest)
            .do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}
