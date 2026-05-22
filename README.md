# Infrastructure Réseau Entreprise 3a / 3b — Docker Compose

## Architecture

```
         AS3 (120.0.48.1)
               |
               | 120.0.48.0/30
               |
pfSense/R_ent3a (.2 WAN / .254 LAN) <─── VPN WireGuard ───> pfSense/R_ent3b
               |                                             |
               | 192.168.3.0/24                    192.168.3.0/24
               |                                             |
   ┌───────────────────────────┐                     [web .4 / nginx]
   │     Site Entreprise 3a    │
   ├───────────────────────────┤
  │ DNS          192.168.3.1  │  Bind9 — autoritaire lafassonnade.lan
   │ DHCP         192.168.3.2  │  ISC dhcpd — plage .100–.200
   │ VoIP         192.168.3.3  │  Asterisk — SIP + extensions
  │ OpenLDAP     192.168.3.5  │  Annuaire LDAP — dc=lafassonnade,dc=lan
   │ phpLDAPadmin 192.168.3.6  │  Interface web LDAP (port 8080)
   │ OpenVPN AS   192.168.3.10 │  Acces particulier distant (UI web)
   │ Vault        192.168.3.15 │  Gestion des secrets (AppRole + KV v2)
   │ Portainer    192.168.3.20 │  Interface web Docker (port 9443)
   │ R_ent3a      192.168.3.254│  Gateway LAN sur pfSense
   └───────────────────────────┘
               ↑
        Particulier (client OpenVPN)
```

> WireGuard n'est plus lancé par Docker. Le tunnel site-à-site doit être
> configuré sur les VM pfSense/routeurs de bord afin de traverser les AS.

## Services

| Conteneur | Image | IP | Port(s) | Rôle |
|---|---|---|---|---|
| `dns_entreprise3` | internetsystemsconsortium/bind9:9.18 | 192.168.3.1 | 53/udp+tcp | DNS autoritaire |
| `dhcp_entreprise3` | networkboot/dhcpd | 192.168.3.2 | — | DHCP LAN |
| `asterisk_voip` | andrius/asterisk:22-cert | 192.168.3.3 | 5060, 10000-10100/udp | VoIP SIP |
| `openldap` | osixia/openldap:1.5.0 | 192.168.3.5 | 389, 636 | Annuaire LDAP |
| `phpldapadmin` | osixia/phpldapadmin | 192.168.3.6 | 8080 | UI LDAP |
| `openvpn_gateway` | openvpn/openvpn-as | 192.168.3.10 | 943, 443, 1194/udp | VPN particulier (UI web) |
| `vault` | hashicorp/vault | 192.168.3.15 | 8200 | Gestion secrets |
| `portainer` | portainer/portainer-ce | 192.168.3.20 | 9443, 9000 | UI Docker |
| `web_entreprise3b` | nginx:alpine | 192.168.3.4 | 80 | Serveur web (site 3b) |
| `as3_router` | frrouting/frr | 120.0.48.1 | — | Simulation AS3 |

> Les anciens conteneurs `wireguard_rent3a` et `wireguard_rent3b` sont
> volontairement commentés dans `docker-compose.yml`. WireGuard appartient aux
> pfSense, pas au LAN applicatif Docker.

## Gestion des secrets

Tous les secrets sont centralisés dans **HashiCorp Vault** (`192.168.3.15`) :

| Chemin Vault | Contenu |
|---|---|
| `secret/entreprise3/wireguard/rent3a` | Clé privée + clé publique R_ent3a |
| `secret/entreprise3/wireguard/rent3b` | Clé privée + clé publique R_ent3b |
| `secret/entreprise3/wireguard/psk` | Clé pré-partagée (PSK) inter-sites |
| `secret/entreprise3/openldap/passwords` | Mots de passe admin/config/readonly LDAP |
| `secret/entreprise3/asterisk/sip-passwords` | Mots de passe SIP (postes 100→900) |
| `secret/entreprise3/openvpn/config` | Passphrase PKI OpenVPN |

Les secrets WireGuard peuvent encore être générés par `vault-init.sh` si vous
voulez vous en servir comme aide pour configurer pfSense, mais ils ne sont plus
consommés par des conteneurs Docker.

## Structure des fichiers

```
.
├── docker-compose.yml
├── .gitignore
├── README.md
└── config/
    ├── bind/
    │   ├── named.conf                      # Config Bind9 (forwarder + zones)
    │   └── zones/
    │       ├── db.lafassonnade.lan         # Zone directe
    │       └── db.192.168.3               # Zone inverse (PTR)
    ├── dhcpd/
    │   └── dhcpd.conf                      # ISC dhcpd — plage + options réseau
    ├── asterisk/
    │   ├── asterisk.conf                   # Config principale Asterisk
    │   ├── sip.conf                        # Comptes SIP (100 à 900)
    │   └── extensions.conf                 # Plan de numérotation
    ├── openldap/
    │   ├── bootstrap/ldif/
    │   │   └── 01-structure.ldif           # OUs, groupes, utilisateurs initiaux
    │   └── ldap-passwords.sh               # Génération hashs SSHA
    ├── wireguard/
    │   ├── 3a/wg0.conf                     # Référence pfSense / généré par vault-init.sh
    │   └── 3b/wg0.conf                     # Référence pfSense / généré par vault-init.sh
    ├── vault/
    │   ├── vault.hcl                       # Config Vault (backend fichier)
    │   ├── vault-init.sh                   # Script bootstrap (1 seule fois)
    │   ├── policies/
    │   │   ├── policy-wireguard.hcl        # Accès clés WireGuard
    │   │   ├── policy-openldap.hcl         # Accès secrets LDAP
    │   │   ├── policy-asterisk.hcl         # Accès secrets SIP
    │   │   └── policy-openvpn.hcl          # Accès secrets VPN
    │   └── agents/
    │       ├── vault-agent-samba.hcl       # Vault Agent (OpenLDAP)
    │       └── templates/
    │           ├── samba-env.tmpl          # Template injection mdp LDAP
    │           └── asterisk-sip-secrets.tmpl # Template injection mdp SIP
    ├── nginx/
    │   ├── nginx.conf                      # Config Nginx (site 3b)
    │   └── html/
    │       ├── index.html                  # Page d'accueil site 3b
    │       └── 404.html                    # Page d'erreur
    └── frr/
        ├── daemons                         # Activation démons FRR
        └── frr.conf                        # Config BGP/routage AS3
```

## Déploiement

### Prérequis

```bash
# wireguard-tools requis seulement si vault-init.sh génère les clés WireGuard
apt install wireguard-tools     # Debian/Ubuntu
brew install wireguard-tools    # macOS
```

### Dépannage Ubuntu 22 (erreurs whiteout/overlay)

Si `docker compose build` échoue avec une erreur du type `failed to convert whiteout file ... operation not supported`, le problème vient généralement du backend de stockage Docker (`overlay2`) sur l'hôte Ubuntu, pas des Dockerfile.

Procédure recommandée pour le projet :

```bash
# Le script applique vfs par défaut (plus lent, mais robuste)
./install-deps-linux.sh

# Vérifier le driver actif
docker info | grep -E "Storage Driver|Docker Root Dir"

# Nettoyer le cache build et relancer un build propre
docker builder prune -af
DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0 docker compose build --no-cache
```

Pour revenir au mode standard ensuite :

```bash
DOCKER_STORAGE_DRIVER=overlay2 ./install-deps-linux.sh
```

### Étape 1 — Démarrer Vault et bootstrapper tous les secrets

> Modifier les mots de passe par défaut dans `vault-init.sh` avant de l'exécuter.

```bash
# Démarrer uniquement Vault en premier
docker compose up -d vault

# Attendre ~10s qu'il soit healthy, puis lancer le bootstrap
chmod +x config/vault/vault-init.sh
./config/vault/vault-init.sh
```

Le script réalise automatiquement les opérations suivantes :
- Initialise Vault (5 unseal keys, seuil à 3) et l'unseal
- Active KV v2 et AppRole
- Crée les 4 policies et AppRoles (openldap, asterisk, openvpn, wireguard)
- Peut générer les clés WireGuard (`wg genkey`/`wg pubkey`/`wg genpsk`) et les stocker dans Vault pour aider la configuration pfSense
- Peut générer les fichiers `wg0.conf` comme référence, sans lancement Docker associé
- Pousse les secrets applicatifs (LDAP, SIP, OpenVPN)
- Sauvegarde les credentials AppRole dans `vault-credentials/`

Copier ensuite les credentials AppRole dans les conteneurs :

```bash
docker cp vault-credentials/openldap/role-id   openldap:/vault/agent/role-id
docker cp vault-credentials/openldap/secret-id openldap:/vault/agent/secret-id
docker cp vault-credentials/asterisk/role-id   asterisk_voip:/vault/agent/role-id
docker cp vault-credentials/asterisk/secret-id asterisk_voip:/vault/agent/secret-id
docker cp vault-credentials/openvpn/role-id    openvpn_gateway:/vault/agent/role-id
docker cp vault-credentials/openvpn/secret-id  openvpn_gateway:/vault/agent/secret-id
```

### Étape 2 — Générer les mots de passe LDAP

```bash
chmod +x config/openldap/ldap-passwords.sh
./config/openldap/ldap-passwords.sh
```

Remplacer les `{SSHA}ChangeMe_*` dans `config/openldap/bootstrap/ldif/01-structure.ldif`.

### Étape 3 — Configurer OpenVPN Access Server

OpenVPN AS se configure entièrement via son interface web — aucun script `easyrsa` nécessaire.

```bash
# Démarrer le conteneur (s'initialise automatiquement)
docker compose up -d openvpn

# Récupérer le mot de passe admin généré automatiquement
docker logs openvpn_gateway | grep "Auto-generated pass"
```

Accéder à l'UI admin : **https://192.168.3.10:943/admin** (`openvpn` / mot de passe des logs)

Configuration minimale dans l'UI :
1. **Configuration → Network Settings** : définir l'IP `192.168.3.10`
2. **Configuration → VPN Settings** : ajouter la route `192.168.3.0/24`
3. **User Management → User Permissions** : créer l'utilisateur `particulier`

> ℹ️ Sans licence, OpenVPN AS autorise **2 connexions simultanées** gratuitement.

### Étape 4 — Lancer l'infrastructure complète

```bash
docker compose up -d
docker compose ps
docker compose logs -f
```

### Étape 5 — Vérifications

```bash
# DNS — résolution interne
dig @192.168.3.1 ldap.lafassonnade.lan
dig @192.168.3.1 web.lafassonnade.lan
dig @192.168.3.1 vault.lafassonnade.lan

# DNS — résolution externe (forwarder)
dig @192.168.3.1 google.com

# DHCP — baux actifs
docker exec dhcp_e3 cat /data/dhcpd.leases

# LDAP — lister les utilisateurs
ldapsearch -x -H ldap://192.168.3.5 \
  -b "ou=users,dc=lafassonnade,dc=lan" \
  -D "cn=admin,dc=lafassonnade,dc=lan" \
  -W "(objectClass=inetOrgPerson)"

# WireGuard — connectivité inter-sites
# A faire depuis pfSense / une machine du site 3a, pas depuis Docker :
ping 192.168.3.4
curl http://192.168.3.4/health

# Vault — statut
vault status -address=http://192.168.3.15:8200
```

## Interfaces web

| Service | URL | Identifiants |
|---|---|---|
| **Vault UI** | http://192.168.3.15:8200/ui | Root token (généré au init) |
| **OpenVPN AS Admin** | https://192.168.3.10:943/admin | `openvpn` / voir logs au 1er démarrage |
| **OpenVPN AS Client** | https://192.168.3.10:943 | Comptes créés dans l'UI admin |
| **phpLDAPadmin** | http://192.168.3.6:8080 | `cn=admin,dc=lafassonnade,dc=lan` |
| **Portainer** | https://192.168.3.20:9443 | Créer au premier accès (< 5 min) |
| **Site web 3b** | http://192.168.3.4 | — |

## Notes importantes

- **WireGuard** : le VPN site-à-site traverse les AS et doit être porté par pfSense/R_ent3a et pfSense/R_ent3b. Les services Docker WireGuard sont commentés dans `docker-compose.yml`.
- **wg0.conf** : les fichiers générés restent utiles comme référence, mais ils contiennent des clés privées en clair et ne doivent pas être committés.
- **Vault unseal** : à chaque redémarrage du conteneur Vault, il faut le unsealer manuellement avec 3 des 5 clés stockées dans `vault-credentials/vault-init.json`.
- **lan_3b** : Docker ne permet pas deux bridges avec le même subnet (`192.168.3.0/24`). En production, c'est un réseau physiquement distinct derrière pfSense. Pour un VPN routé propre, utiliser idéalement un subnet différent côté 3b (ex: `192.168.4.0/24`).
- **DHCP** : `dhcpd` doit être sur le même segment L2 que les clients. Dans un lab Docker pur, les clients seront les autres conteneurs de `lan_3a`.
- **Portainer** : créer le compte admin dans les **5 minutes** suivant le premier démarrage, sinon l'interface se verrouille.
- **Secrets et git** : `vault-credentials/` et les `wg0.conf` générés sont dans `.gitignore` — ne jamais les committer.
