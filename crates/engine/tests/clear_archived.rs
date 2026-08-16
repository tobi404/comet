//! Settings → Archived "Clear archived": the `clearArchivedChats` mutate op
//! tombstones every archived chat row in one doc transaction, and purges each
//! removed chat's session doc. Unarchived chats are untouched.

use std::sync::Arc;
use std::time::Duration;

use zeron_doc::SessionCommandPayload;
use zeron_engine::{EngineCore, HarnessRegistry};
use zeron_proto::HarnessId;

async fn wait_for<F>(mut predicate: F, what: &str)
where
    F: FnMut() -> bool,
{
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !predicate() {
        assert!(
            tokio::time::Instant::now() < deadline,
            "timed out waiting for {what}"
        );
        tokio::time::sleep(Duration::from_millis(15)).await;
    }
}

fn command_count(core: &EngineCore, chat_id: &str) -> usize {
    core.doc_host
        .open(chat_id)
        .ok()
        .and_then(|h| h.doc().read_commands().ok())
        .map(|c| c.len())
        .unwrap_or_default()
}

fn chat_ids(core: &EngineCore) -> Vec<String> {
    let mut ids: Vec<String> = core
        .workspace
        .read_chats()
        .expect("read chat rows")
        .into_iter()
        .map(|c| c.id)
        .collect();
    ids.sort();
    ids
}

#[tokio::test(flavor = "multi_thread")]
async fn clear_archived_removes_archived_rows_and_purges_their_docs() {
    let tmp = tempfile::tempdir().unwrap();
    let core = EngineCore::assemble(
        &tmp.path().join("data"),
        Arc::new(HarnessRegistry::new()),
        HarnessId::Mock,
        None,
    )
    .expect("engine core assembles");

    let client = zeron_rpc::memory_client(core.rpc_service());
    for chat in ["chat-a", "chat-b", "chat-c"] {
        client
            .call(
                zeron_rpc::methods::MUTATE,
                serde_json::json!({
                    "op": "createChat",
                    "chatId": chat,
                    "deviceId": core.device_id,
                }),
            )
            .await
            .expect("createChat");
        // Give each session doc a ledger entry, so the purge is observable.
        // An interrupt is not a message — it leaves the archive state alone.
        core.doc_host
            .queue_command(chat, SessionCommandPayload::Interrupt {})
            .expect("queue interrupt");
        assert_eq!(command_count(&core, chat), 1, "{chat} doc has an entry");
    }

    core.workspace
        .set_chat_archived("chat-a", true)
        .expect("archive chat-a");
    core.workspace
        .set_chat_archived("chat-c", true)
        .expect("archive chat-c");

    client
        .call(
            zeron_rpc::methods::MUTATE,
            serde_json::json!({ "op": "clearArchivedChats" }),
        )
        .await
        .expect("clearArchivedChats");

    assert_eq!(chat_ids(&core), ["chat-b"], "only the live chat remains");
    wait_for(
        || command_count(&core, "chat-a") == 0 && command_count(&core, "chat-c") == 0,
        "archived session docs to be purged",
    )
    .await;
    assert_eq!(
        command_count(&core, "chat-b"),
        1,
        "the live chat's doc survives"
    );

    core.shutdown().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn clear_archived_is_a_no_op_when_nothing_is_archived() {
    let tmp = tempfile::tempdir().unwrap();
    let core = EngineCore::assemble(
        &tmp.path().join("data"),
        Arc::new(HarnessRegistry::new()),
        HarnessId::Mock,
        None,
    )
    .expect("engine core assembles");

    let client = zeron_rpc::memory_client(core.rpc_service());
    client
        .call(
            zeron_rpc::methods::MUTATE,
            serde_json::json!({
                "op": "createChat",
                "chatId": "chat-a",
                "deviceId": core.device_id,
            }),
        )
        .await
        .expect("createChat");

    client
        .call(
            zeron_rpc::methods::MUTATE,
            serde_json::json!({ "op": "clearArchivedChats" }),
        )
        .await
        .expect("clearArchivedChats");

    assert_eq!(chat_ids(&core), ["chat-a"]);

    core.shutdown().await;
}
