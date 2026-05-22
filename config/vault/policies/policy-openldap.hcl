# =============================================================================
# policy-openldap.hcl — Politique Vault pour OpenLDAP
# Accès en lecture seule sur les mots de passe admin/config/readonly
# =============================================================================

path "secret/data/entreprise3/openldap/*" {
  capabilities = ["read"]
}
