/// Mediator module — initialises the TDK, ATM, and profiles for Alice & Bob.
///
/// Reads configuration from `environments.json` (produced by `setup_environment`)
/// and sets up both identities with ACLs so they can exchange messages.
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::{error, info};

use affinidi_messaging_sdk::{
    ATM,
    profiles::ATMProfile,
    protocols::mediator::acls::{AccessListModeType, MediatorACLSet},
};
use affinidi_tdk::{TDK, common::config::TDKConfig};

use crate::identity::IdentityInfo;
use crate::packet_logger::PacketEvent;

/// Shared application state passed into every Axum handler.
pub struct AppState {
    pub atm: Arc<ATM>,
    pub tdk: Arc<TDK>,

    // Activated ATM profiles (thread-safe handles)
    pub alice_profile: Arc<ATMProfile>,
    pub bob_profile: Arc<ATMProfile>,

    // Public identity metadata for the frontend
    pub alice_info: IdentityInfo,
    pub bob_info: IdentityInfo,

    // Bob's mediator DID (needed for forwarding)
    pub alice_mediator_did: String,
    pub bob_mediator_did: String,

    // Packet event broadcast channel
    pub packet_tx: broadcast::Sender<PacketEvent>,
}

/// Bootstrap everything: TDK → ATM → profiles → ACLs.
///
/// `environment_name` corresponds to the key inside `environments.json`.
pub async fn initialise(
    environment_name: &str,
    packet_tx: broadcast::Sender<PacketEvent>,
) -> Result<Arc<AppState>, Box<dyn std::error::Error + Send + Sync>> {
    info!("Initialising TDK with environment '{environment_name}'");

    // ── 1. Instantiate TDK ──────────────────────────────────────────────
    let tdk = TDK::new(
        TDKConfig::builder()
            .with_environment_name(environment_name.to_string())
            .build()?,
        None,
    )
    .await?;

    let environment = &tdk.get_shared_state().environment;
    let atm = tdk.atm.clone().unwrap();

    // ── 2. Activate Alice profile ───────────────────────────────────────
    let tdk_alice = environment
        .profiles
        .get("Alice")
        .ok_or_else(|| {
            format!("Alice not found in environment '{environment_name}'")
        })?;
    tdk.add_profile(tdk_alice).await;

    let atm_alice = atm
        .profile_add(&ATMProfile::from_tdk_profile(&atm, tdk_alice).await?, true)
        .await?;

    let alice_account = atm
        .mediator()
        .account_get(&atm_alice, None)
        .await?
        .ok_or("Alice account not found on mediator")?;
    info!("Alice profile active — DID hash: {}", alice_account.did_hash);

    let alice_acl_mode = MediatorACLSet::from_u64(alice_account.acls)
        .get_access_list_mode()
        .0;

    // ── 3. Activate Bob profile ─────────────────────────────────────────
    let tdk_bob = environment
        .profiles
        .get("Bob")
        .ok_or_else(|| {
            format!("Bob not found in environment '{environment_name}'")
        })?;
    tdk.add_profile(tdk_bob).await;

    let atm_bob = atm
        .profile_add(&ATMProfile::from_tdk_profile(&atm, tdk_bob).await?, true)
        .await?;

    let bob_account = atm
        .mediator()
        .account_get(&atm_bob, None)
        .await?
        .ok_or("Bob account not found on mediator")?;
    info!("Bob profile active — DID hash: {}", bob_account.did_hash);

    let bob_acl_mode = MediatorACLSet::from_u64(bob_account.acls)
        .get_access_list_mode()
        .0;

    // ── 4. Set up ACLs ──────────────────────────────────────────────────
    if let AccessListModeType::ExplicitAllow = alice_acl_mode {
        atm.mediator()
            .access_list_add(&atm_alice, None, &[&bob_account.did_hash])
            .await?;
        info!("Added Bob to Alice's allow list");
    }

    if let AccessListModeType::ExplicitAllow = bob_acl_mode {
        atm.mediator()
            .access_list_add(&atm_bob, None, &[&alice_account.did_hash])
            .await?;
        info!("Added Alice to Bob's allow list");
    }

    // ── 5. Enable WebSocket streams for live pickup ─────────────────────
    if let Err(e) = atm.profile_enable_websocket(&atm_alice).await {
        error!("Failed to enable WS for Alice: {e}");
    } else {
        info!("WebSocket enabled for Alice");
    }

    if let Err(e) = atm.profile_enable_websocket(&atm_bob).await {
        error!("Failed to enable WS for Bob: {e}");
    } else {
        info!("WebSocket enabled for Bob");
    }

    // ── 6. Build identity metadata ──────────────────────────────────────
    let alice_mediator_did = tdk_alice.mediator.clone().unwrap_or_default();
    let bob_mediator_did = tdk_bob.mediator.clone().unwrap_or_default();

    let alice_identity = IdentityInfo::from_profile(
        "Alice",
        &atm_alice.inner.did,
        Some(&alice_mediator_did),
    );
    let bob_identity = IdentityInfo::from_profile(
        "Bob",
        &atm_bob.inner.did,
        Some(&bob_mediator_did),
    );

    info!("Alice DID: {}", alice_identity.did);
    info!("Bob   DID: {}", bob_identity.did);

    Ok(Arc::new(AppState {
        atm: Arc::new(atm),
        tdk: Arc::new(tdk),
        alice_profile: atm_alice,
        bob_profile: atm_bob,
        alice_info: alice_identity,
        bob_info: bob_identity,
        alice_mediator_did,
        bob_mediator_did,
        packet_tx,
    }))
}
