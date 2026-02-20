/// Identity management for Alice and Bob using TDK profiles.
///
/// Wraps the Affinidi TDK profile system — identities are loaded from
/// the `environments.json` file produced by `setup_environment`.
use serde::Serialize;

/// Public identity information exposed to the frontend.
#[derive(Debug, Clone, Serialize)]
pub struct IdentityInfo {
    pub alias: String,
    pub did: String,
    pub mediator_did: Option<String>,
    pub key_types: Vec<String>,
}

impl IdentityInfo {
    /// Build an `IdentityInfo` from a TDK profile reference and the resolved ATM profile.
    pub fn from_profile(
        alias: &str,
        did: &str,
        mediator_did: Option<&str>,
    ) -> Self {
        Self {
            alias: alias.to_string(),
            did: did.to_string(),
            mediator_did: mediator_did.map(|s| s.to_string()),
            // Key types are inferred from the did:peer method — each profile
            // typically carries P256 + Ed25519 (verification) and X25519 + Secp256k1 (encryption)
            key_types: vec![
                "P-256".into(),
                "Ed25519".into(),
                "X25519".into(),
                "secp256k1".into(),
            ],
        }
    }
}
