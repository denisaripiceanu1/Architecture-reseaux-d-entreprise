# =============================================================================
# policy-openvpn.hcl — Politique Vault pour le service OpenVPN
# =============================================================================

path "secret/data/entreprise3/openvpn/*" {
  capabilities = ["read"]
}
