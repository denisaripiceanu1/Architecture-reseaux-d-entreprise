# =============================================================================
# policy-wireguard.hcl — Politique Vault pour WireGuard
# Accès en lecture seule sur les clés des deux peers + PSK
# =============================================================================

path "secret/data/entreprise3/wireguard/*" {
  capabilities = ["read"]
}
