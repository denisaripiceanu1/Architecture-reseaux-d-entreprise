# =============================================================================
# policy-asterisk.hcl — Politique Vault pour le service Asterisk (VoIP)
# =============================================================================

path "secret/data/entreprise3/asterisk/*" {
  capabilities = ["read"]
}
