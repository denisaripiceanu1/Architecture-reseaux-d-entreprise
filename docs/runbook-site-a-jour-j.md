# Runbook Jour J — Site A

Responsable : toto.

Ce PC heberge les services internes et la voix :

```text
SERVICES : 192.168.3.0/24
VOICE    : 192.168.30.0/24
```

## 1. Branchement

```text
Interface SERVICES -> pfSense Site A SERVICES
Interface VOICE    -> pfSense Site A VOICE
```

Configuration reseau attendue :

```text
Interface SERVICES : 192.168.3.250/24, gateway 192.168.3.254
Interface VOICE    : 192.168.30.250/24, pas de gateway par defaut
```

Ne pas configurer plusieurs gateways par defaut sur le meme PC. Garder la
gateway par defaut cote SERVICES.

## 2. Recuperer le projet

Git est deja installe sur les machines de lab.

```bash
git clone URL_DU_REPO RzoEntreprise
cd RzoEntreprise
ip -br link
ip -br addr
```

Remplacer `URL_DU_REPO` par l'URL Git du projet.

## 3. Configurer les variables

```bash
cp env/site-a.env.example env/site-a.env
nano env/site-a.env
```

Adapter :

```text
SERVICES_IFACE=nom_interface_services
VOICE_IFACE=nom_interface_voice
OPENVPN_HOSTNAME=vpn.lafassonnade.lan
```

## 4. Premier lancement

Cette commande installe/reinstalle Docker, prepare les dossiers runtime,
construit les images puis lance la stack Site A :

```bash
./scripts/start-site-a.sh --install-deps
```

Le script initialise automatiquement l'arborescence LDAP de base.

## 5. Relances utiles

Relance normale :

```bash
./scripts/start-site-a.sh
```

Relance propre :

```bash
./scripts/start-site-a.sh --down-first
```

Relancer uniquement l'amorcage LDAP :

```bash
./scripts/bootstrap-openldap-tree.sh
```

Demarrer sans toucher a LDAP :

```bash
./scripts/start-site-a.sh --skip-ldap-bootstrap
```

## 6. Services attendus

```text
DNS        192.168.3.1
DHCP       192.168.3.2
LDAP       192.168.3.5
phpLDAP    192.168.3.6
OpenVPN    192.168.3.10
Vault      192.168.3.15
Portainer  192.168.3.20
Asterisk   192.168.30.3
```

Comptes LDAP de test crees :

```text
alice / alice123
bob / bob123
admin-tp / admin123
```

## 7. Verifications cote Site A

```bash
docker compose --env-file env/site-a.env -f docker-compose.site-a.macvlan.yml ps
docker exec dns_e3 named-checkconf /etc/bind/named.conf
docker exec openldap ldapsearch -x -H ldap://127.0.0.1 -b "dc=lafassonnade,dc=lan" "(uid=alice)"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show endpoints"
docker exec openvpn_gateway sh -lc 'sacli ConfigQuery | grep -E "host.name|ovpndco"'
```

Attendu pour OpenVPN :

```text
host.name = vpn.lafassonnade.lan
vpn.server.daemon.ovpndco = false
```

Portainer doit etre initialise rapidement par le poste admin :

```text
https://192.168.3.20:9443
```

## 8. En cas de reset Vault en lab

```bash
docker compose --env-file env/site-a.env -f docker-compose.site-a.macvlan.yml down
sudo rm -rf data/vault
rm -rf vault-credentials
mkdir -p data/vault
sudo chown -R 100:1000 data/vault
sudo chmod 700 data/vault
./scripts/start-site-a.sh
```

## 9. Erreur overlay/whiteout Docker

Si Docker affiche une erreur du type :

```text
failed to convert whiteout file: operation not supported
failed to mount source overlay
```

le filesystem du lab ne supporte probablement pas correctement `overlay2`.
Relancer l'installation propre : le script configure Docker en `vfs` par defaut
et supprime l'ancien stockage Docker.

```bash
./scripts/start-site-a.sh --install-deps
docker info | grep -i "Storage Driver"
```

Attendu :

```text
Storage Driver: vfs
```
