# =============================================================================
# vault.hcl — Configuration Vault (mode production, backend fichier)
# =============================================================================

ui            = true
disable_mlock = true       # Nécessaire dans Docker (pas de capabilities mlock)

# Listener HTTP — mettre tls_cert_file/tls_key_file pour du vrai TLS en prod
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# Backend de stockage persistant (fichier local dans le volume Docker)
storage "file" {
  path = "/vault/data"
}

api_addr     = "http://192.168.3.15:8200"
cluster_addr = "http://192.168.3.15:8201"
