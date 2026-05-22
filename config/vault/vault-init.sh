#!/usr/bin/env bash
# =============================================================================
# vault-init.sh — Initialisation et bootstrap Vault
# À exécuter UNE SEULE FOIS après le premier démarrage du conteneur Vault
#
# Prérequis : wg (wireguard-tools) installé sur la machine hôte
#   apt install wireguard-tools  /  brew install wireguard-tools
#
# Ce script :
#   1. Initialise Vault (génère unseal keys + root token)
#   2. Unseal Vault
#   3. Active le moteur KV v2
#   4. Active AppRole
#   5. Crée les policies par service
#   6. Crée les AppRoles par service
#   7. Génère les clés WireGuard et les pousse dans Vault
#   8. Génère les wg0.conf à partir des clés stockées dans Vault
#   9. Pousse les secrets applicatifs (LDAP, SIP, OpenVPN)
#  10. Sauvegarde les credentials dans ./vault-credentials/ (GARDER SECRET)
# =============================================================================

set -euo pipefail

# Simple logger with timestamps
log() {
  printf "%s %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

# Mask secrets when printing
mask() {
  local v="$1"
  if [ -z "$v" ]; then
    echo "(empty)"
  else
    echo "${v:0:6}...(${#v})"
  fi
}

# On error, print helpful diagnostics
trap 'err=$?; log "ERROR: script failed (exit=$err) at line $LINENO"; log "Vault status:"; VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200} vault status -format=json 2>&1 | sed -n "1,200p" || true' ERR

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
CREDS_DIR="${CREDS_DIR:-./vault-credentials}"
export VAULT_ADDR

# Vérification de wg
if ! command -v wg &> /dev/null; then
  echo "❌ 'wg' n'est pas installé. Installer wireguard-tools d'abord."
  echo "   apt install wireguard-tools  ou  brew install wireguard-tools"
  exit 1
fi

mkdir -p "$CREDS_DIR"
chmod 700 "$CREDS_DIR"

echo ""
echo "============================================================"
echo " VAULT INIT — Entreprise3"
echo "============================================================"

# -------------------------------------------------------------------
# 0. Attente de la disponibilité de Vault (utile en init container)
# -------------------------------------------------------------------
echo ""
echo "[0/9] Attente de Vault sur $VAULT_ADDR ..."
for i in $(seq 1 30); do
  vault status >/dev/null 2>&1 && break
  rc=$?
  [ "$rc" -eq 2 ] && break          # exit 2 = scellé mais joignable → OK
  echo "  ... Vault pas encore prêt (tentative $i/30)"
  sleep 2
done

# -------------------------------------------------------------------
# 1. Initialisation
# -------------------------------------------------------------------
echo ""
echo "[1/9] Initialisation de Vault..."

# Check if Vault is already initialized to avoid failing on re-run
STATUS_JSON=$(vault status -format=json 2>/dev/null || true)
INITIALIZED=$(echo "$STATUS_JSON" | python3 -c 'import sys, json
s=sys.stdin.read()
try:
    obj=json.loads(s) if s else {}
    print(str(obj.get("initialized", False)).lower())
except Exception:
    print("false")')
log "DEBUG: vault status json: ${STATUS_JSON:0:800}"

if [ "$INITIALIZED" = "true" ]; then
  echo "  ✓ Vault already initialized"
  if [ -f "$CREDS_DIR/vault-init.json" ]; then
    INIT_OUTPUT=$(cat "$CREDS_DIR/vault-init.json")
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('root_token',''))")
    UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('unseal_keys_b64',[''])[0])")
    UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('unseal_keys_b64',['',''])[1])")
    UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('unseal_keys_b64',['','',''])[2])")
    echo "  ✓ Loaded saved credentials from $CREDS_DIR/vault-init.json"
    log "Loaded credentials: root=$(mask \"$ROOT_TOKEN\") unseal1=$(mask \"$UNSEAL_KEY_1\") unseal2=$(mask \"$UNSEAL_KEY_2\") unseal3=$(mask \"$UNSEAL_KEY_3\")"
  else
    echo "  ⚠️  Vault is initialized but $CREDS_DIR/vault-init.json not found."
    echo "       If Vault is sealed you must provide unseal keys or set VAULT_TOKEN to perform subsequent steps. Skipping init/unseal."
    SKIP_INIT=true
  fi
else
  # Initialize Vault (first run)
  INIT_OUTPUT=$(vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json) || {
    echo "Error: vault operator init failed" >&2
    exit 1
  }

  echo "$INIT_OUTPUT" > "$CREDS_DIR/vault-init.json"
  chmod 600 "$CREDS_DIR/vault-init.json"

  # show masked init output for debugging
  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('root_token',''))")
  log "Init output saved — root=$(mask \"$ROOT_TOKEN\")"

  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['root_token'])")
  UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][0])")
  UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][1])")
  UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][2])")

  echo "  ✓ Vault initialisé — credentials sauvegardés dans $CREDS_DIR/vault-init.json"
  echo "  ⚠️  Sauvegardez ces clés dans un endroit SÉCURISÉ (gestionnaire de mots de passe)"
fi

# -------------------------------------------------------------------
# 2. Unseal (3 clés sur 5 requises)
# -------------------------------------------------------------------
echo ""
echo "[2/9] Unseal Vault..."
if [ "${SKIP_INIT:-false}" = "true" ]; then
  echo "[2/9] Skipping unseal (no local credentials available)"
else
  # Check if Vault is sealed before attempting to unseal
  STATUS_JSON2=$(vault status -format=json 2>/dev/null || true)
  SEALED=$(echo "$STATUS_JSON2" | python3 -c 'import sys,json; s=sys.stdin.read(); print(str(json.loads(s).get("sealed", True)).lower() if s else "true")')

  if [ "$SEALED" = "true" ]; then
    log "Attempting unseal with keys: $(mask "$UNSEAL_KEY_1"), $(mask "$UNSEAL_KEY_2"), $(mask "$UNSEAL_KEY_3")"
    vault operator unseal "$UNSEAL_KEY_1" || log "unseal step 1 returned $?"
    vault operator unseal "$UNSEAL_KEY_2" || log "unseal step 2 returned $?"
    vault operator unseal "$UNSEAL_KEY_3" || log "unseal step 3 returned $?"
    log "Unseal commands sent. Checking status..."
    VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200} vault status -format=json 2>/dev/null | sed -n '1,120p' | sed 's/\"unseal_keys_b64\": \[[^\]]*\]/"unseal_keys_b64": [REDACTED]/' | sed -n '1,200p'
    echo "  ✓ Vault unsealed"
  else
    echo "  ✓ Vault already unsealed"
  fi
fi

export VAULT_TOKEN="$ROOT_TOKEN"

# -------------------------------------------------------------------
# 3. Activation KV v2
# -------------------------------------------------------------------
echo ""
echo "[3/9] Activation du moteur KV v2..."
# Idempotent enable: check if path 'secret/' is already enabled
if VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200} vault secrets list -format=json 2>/dev/null | python3 -c 'import sys,json
s=sys.stdin.read()
try:
    d=json.loads(s) if s else {}
    print("secret/" in d.keys())
except Exception:
    print(False)
' | grep -q True; then
  echo "  ✓ KV v2 already enabled on /secret"
else
  vault secrets enable -path=secret kv-v2
  echo "  ✓ KV v2 activé sur /secret"
fi

# -------------------------------------------------------------------
# 4. Activation AppRole
# -------------------------------------------------------------------
echo ""
echo "[4/9] Activation AppRole..."
# Idempotent enable for auth method 'approle/'
if VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200} vault auth list -format=json 2>/dev/null | python3 -c 'import sys,json
s=sys.stdin.read()
try:
    d=json.loads(s) if s else {}
    print("approle/" in d.keys())
except Exception:
    print(False)
' | grep -q True; then
  echo "  ✓ AppRole already enabled"
else
  vault auth enable approle
  echo "  ✓ AppRole activé"
fi

# -------------------------------------------------------------------
# 5. Création des policies
# -------------------------------------------------------------------
echo ""
echo "[5/9] Création des policies..."
vault policy write openldap-policy   config/vault/policies/policy-openldap.hcl
vault policy write asterisk-policy   config/vault/policies/policy-asterisk.hcl
vault policy write openvpn-policy    config/vault/policies/policy-openvpn.hcl
vault policy write wireguard-policy  config/vault/policies/policy-wireguard.hcl
echo "  ✓ Policies créées : openldap, asterisk, openvpn, wireguard"

# -------------------------------------------------------------------
# 6. Création des AppRoles par service
# -------------------------------------------------------------------
echo ""
echo "[6/9] Création des AppRoles..."

create_approle() {
  local SERVICE=$1
  local POLICY=$2

  vault write auth/approle/role/${SERVICE} \
    token_policies="${POLICY}" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0

  # Réutiliser les credentials existants pour ne PAS régénérer un secret-id à chaque boot
  if [ -s "$CREDS_DIR/${SERVICE}/role-id" ] && [ -s "$CREDS_DIR/${SERVICE}/secret-id" ]; then
    echo "  ✓ AppRole '${SERVICE}' — credentials déjà présents, réutilisés"
    return
  fi

  ROLE_ID=$(vault read -field=role_id auth/approle/role/${SERVICE}/role-id)
  SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/${SERVICE}/secret-id)

  mkdir -p "$CREDS_DIR/${SERVICE}"
  echo "$ROLE_ID"   > "$CREDS_DIR/${SERVICE}/role-id"
  echo "$SECRET_ID" > "$CREDS_DIR/${SERVICE}/secret-id"
  chmod 600 "$CREDS_DIR/${SERVICE}/role-id" "$CREDS_DIR/${SERVICE}/secret-id"

  echo "  ✓ AppRole '${SERVICE}' — credentials dans $CREDS_DIR/${SERVICE}/"
}

create_approle "openldap"   "openldap-policy"
create_approle "asterisk"   "asterisk-policy"
create_approle "openvpn"    "openvpn-policy"
create_approle "wireguard"  "wireguard-policy"

# -------------------------------------------------------------------
# 7. Génération des clés WireGuard + stockage dans Vault
# -------------------------------------------------------------------
echo ""
echo "[7/9] Génération / récupération des clés WireGuard..."

if vault kv get secret/entreprise3/wireguard/rent3a >/dev/null 2>&1; then
  # Déjà présentes : on les relit depuis Vault (clés stables d'un boot à l'autre)
  PRIV_3A=$(vault kv get -field=private_key secret/entreprise3/wireguard/rent3a)
  PUB_3A=$(vault kv get -field=public_key  secret/entreprise3/wireguard/rent3a)
  PRIV_3B=$(vault kv get -field=private_key secret/entreprise3/wireguard/rent3b)
  PUB_3B=$(vault kv get -field=public_key  secret/entreprise3/wireguard/rent3b)
  PSK=$(vault kv get -field=preshared_key  secret/entreprise3/wireguard/psk)
  echo "  ✓ Clés WireGuard déjà dans Vault — réutilisées"
else
  # Première fois : génération puis stockage dans Vault
  PRIV_3A=$(wg genkey); PUB_3A=$(echo "$PRIV_3A" | wg pubkey)
  PRIV_3B=$(wg genkey); PUB_3B=$(echo "$PRIV_3B" | wg pubkey)
  PSK=$(wg genpsk)

  vault kv put secret/entreprise3/wireguard/rent3a \
    private_key="$PRIV_3A" \
    public_key="$PUB_3A"
  vault kv put secret/entreprise3/wireguard/rent3b \
    private_key="$PRIV_3B" \
    public_key="$PUB_3B"
  vault kv put secret/entreprise3/wireguard/psk \
    preshared_key="$PSK"
  echo "  ✓ Clés WireGuard générées et stockées dans Vault"
fi

echo "  ✓ R_ent3a (pub: ${PUB_3A:0:20}...)"
echo "  ✓ R_ent3b (pub: ${PUB_3B:0:20}...)"

# -------------------------------------------------------------------
# 8. Génération des wg0.conf à partir des clés
# -------------------------------------------------------------------
echo ""
echo "[8/9] Génération des fichiers wg0.conf..."

mkdir -p config/wireguard/3a config/wireguard/3b

cat > config/wireguard/3a/wg0.conf << WG3A
# Généré automatiquement par vault-init.sh — NE PAS ÉDITER MANUELLEMENT
# WireGuard — R_ent3a (serveur) | WAN: 120.0.48.2 | LAN: 192.168.3.254

[Interface]
Address    = 10.200.0.1/30
PrivateKey = ${PRIV_3A}
ListenPort = 51820

PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s 192.168.3.0/24 -o eth1 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s 192.168.3.0/24 -o eth1 -j MASQUERADE

[Peer]
# R_ent3b — Site Entreprise 3b
PublicKey    = ${PUB_3B}
PresharedKey = ${PSK}
AllowedIPs   = 10.200.0.2/32, 192.168.3.4/32
Endpoint     = 120.0.48.1:51821
PersistentKeepalive = 25
WG3A

cat > config/wireguard/3b/wg0.conf << WG3B
# Généré automatiquement par vault-init.sh — NE PAS ÉDITER MANUELLEMENT
# WireGuard — R_ent3b (client) | LAN: 192.168.3.253

[Interface]
Address    = 10.200.0.2/30
PrivateKey = ${PRIV_3B}

PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s 192.168.3.4/32 -o wg0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s 192.168.3.4/32 -o wg0 -j MASQUERADE

[Peer]
# R_ent3a — Site Entreprise 3a
PublicKey    = ${PUB_3A}
PresharedKey = ${PSK}
AllowedIPs   = 10.200.0.1/32, 192.168.3.0/24
Endpoint     = 120.0.48.2:51820
PersistentKeepalive = 25
WG3B

chmod 600 config/wireguard/3a/wg0.conf config/wireguard/3b/wg0.conf
echo "  ✓ config/wireguard/3a/wg0.conf généré"
echo "  ✓ config/wireguard/3b/wg0.conf généré"

# -------------------------------------------------------------------
# 9. Secrets applicatifs (LDAP, SIP, OpenVPN)
# -------------------------------------------------------------------
echo ""
echo "[9/9] Chargement des secrets applicatifs..."

# --- OpenLDAP --- (créés une seule fois ; une rotation manuelle est conservée)
if ! vault kv get secret/entreprise3/openldap/passwords >/dev/null 2>&1; then
  vault kv put secret/entreprise3/openldap/passwords \
    admin_password="ldap_admin_pass" \
    config_password="ldap_config_pass" \
    readonly_password="L23D_&joZ87?"    # ← changer avant exécution
  echo "  ✓ Secrets OpenLDAP créés"
else
  echo "  ✓ Secrets OpenLDAP déjà présents — conservés"
fi

# --- Asterisk SIP ---
if ! vault kv get secret/entreprise3/asterisk/sip-passwords >/dev/null 2>&1; then
  vault kv put secret/entreprise3/asterisk/sip-passwords \
    sip_100="aifUE738§§" \
    sip_200="034kfi++ZV" \
    sip_201="_-jfiehAI33" \
    sip_300="ETH(4888!!" \
    sip_301="nzoJEU928.." \
    sip_400="/.+78hyeopP" \
    sip_500="XAKEeih)!!/" \
    sip_900="12&hidzOKU)-"                  # ← changer avant exécution
  echo "  ✓ Secrets Asterisk créés"
else
  echo "  ✓ Secrets Asterisk déjà présents — conservés"
fi

# --- OpenVPN ---
if ! vault kv get secret/entreprise3/openvpn/config >/dev/null 2>&1; then
  vault kv put secret/entreprise3/openvpn/config \
    pki_passphrase="EOI§Woi!!%"         # ← changer avant exécution
  echo "  ✓ Secrets OpenVPN créés"
else
  echo "  ✓ Secrets OpenVPN déjà présents — conservés"
fi

echo "  ✓ Secrets applicatifs traités"

# -------------------------------------------------------------------
# Résumé
# -------------------------------------------------------------------
echo ""
echo "============================================================"
echo " BOOTSTRAP TERMINÉ"
echo "============================================================"
echo ""
echo " Root token    : $ROOT_TOKEN"
echo " UI Vault      : http://192.168.3.15:8200/ui"
echo " Credentials   : $CREDS_DIR/"
echo ""
echo " Clés WireGuard dans Vault :"
echo "   secret/entreprise3/wireguard/rent3a  (private_key, public_key)"
echo "   secret/entreprise3/wireguard/rent3b  (private_key, public_key)"
echo "   secret/entreprise3/wireguard/psk     (preshared_key)"
echo ""
echo " Fichiers wg0.conf générés et prêts :"
echo "   config/wireguard/3a/wg0.conf"
echo "   config/wireguard/3b/wg0.conf"
echo ""
echo " Prochaine étape : copier les role-id/secret-id dans les conteneurs :"
echo "   docker cp $CREDS_DIR/openldap/role-id   openldap:/vault/agent/role-id"
echo "   docker cp $CREDS_DIR/openldap/secret-id openldap:/vault/agent/secret-id"
echo "   docker cp $CREDS_DIR/asterisk/role-id   asterisk_voip:/vault/agent/role-id"
echo "   docker cp $CREDS_DIR/asterisk/secret-id asterisk_voip:/vault/agent/secret-id"
echo "   docker cp $CREDS_DIR/openvpn/role-id    openvpn_gateway:/vault/agent/role-id"
echo "   docker cp $CREDS_DIR/openvpn/secret-id  openvpn_gateway:/vault/agent/secret-id"
echo ""
echo " ⚠️  Ne committez JAMAIS vault-credentials/ ni les wg0.conf dans git !"
echo "============================================================"
