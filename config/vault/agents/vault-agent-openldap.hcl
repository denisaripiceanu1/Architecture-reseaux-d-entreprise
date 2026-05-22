# =============================================================================
# vault-agent-openldap.hcl — Vault Agent (sidecar) pour OpenLDAP
# Récupère les mots de passe admin/config/readonly et les injecte dans
# /run/secrets/ldap-*-password (volume partagé avec le conteneur openldap).
# =============================================================================

vault {
  address = "http://192.168.3.15:8200"
}

# Authentification via AppRole (role-id / secret-id fournis par vault-init.sh)
auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/agent/role-id"
      secret_id_file_path = "/vault/agent/secret-id"
    }
  }

  sink "file" {
    config = {
      path = "/vault/agent/token"          # Token renouvelé automatiquement
    }
  }
}

# --- Mot de passe administrateur (cn=admin) ---
template {
  source      = "/vault/agent/templates/ldap-admin-password.tmpl"
  destination = "/run/secrets/ldap-admin-password"
  perms       = "0400"
}

# --- Mot de passe de configuration (cn=admin,cn=config) ---
template {
  source      = "/vault/agent/templates/ldap-config-password.tmpl"
  destination = "/run/secrets/ldap-config-password"
  perms       = "0400"
}

# --- Mot de passe du compte readonly ---
template {
  source      = "/vault/agent/templates/ldap-readonly-password.tmpl"
  destination = "/run/secrets/ldap-readonly-password"
  perms       = "0400"
}

# Recharge automatique si les secrets changent (rotation)
template_config {
  static_secret_render_interval = "5m"
  exit_on_retry_failure         = false   # Attend que Vault soit descellé/prêt
}
