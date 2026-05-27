# Runbook Jour J — pfSense + macvlan

Ce runbook est la version à utiliser quand les deux pfSense sont en place.
Les conteneurs n'utilisent plus le bridge Docker : ils apparaissent directement
sur les réseaux pfSense avec leurs IP finales.

## 1. Topologie

| Élément | Rôle | Réseaux |
|---|---|---|
| PC Site A | Services internes + voix | `192.168.3.0/24`, `192.168.30.0/24` |
| PC Site B | DMZ web | `192.168.40.0/24` |
| pfSense Site A | Routage/firewall SERVICES/VOICE + entrée OpenVPN | `192.168.3.254`, `192.168.30.254` |
| pfSense Site B | Routage/firewall DMZ | `192.168.40.254` |
| Poste admin physique | Administration | `192.168.3.241/24` |
| Client VPN | Client externe | hors des réseaux internes avant VPN |

## 2. Branchement physique

Sans VLAN, il faut une interface physique par réseau hébergé.

PC Site A :

```text
Interface SERVICES -> pfSense Site A SERVICES
Interface VOICE    -> pfSense Site A VOICE
```

PC Site B :

```text
Interface DMZ -> pfSense Site B DMZ
```

Poste admin :

```text
Interface admin -> réseau SERVICES
IP              -> 192.168.3.241/24
Gateway         -> 192.168.3.254
DNS             -> 192.168.3.1
```

Client VPN :

```text
Branché hors SERVICES/VOICE/DMZ.
Il doit seulement pouvoir joindre l'entrée VPN pfSense.
```

## 3. Configuration Ubuntu des PCs serveurs

Sur chaque PC serveur, installer Git puis récupérer le projet :

```bash
sudo apt update
sudo apt install -y git
git clone URL_DU_REPO RzoEntreprise
cd RzoEntreprise
```

Remplacer `URL_DU_REPO` par l'URL Git du projet.

Identifier les interfaces :

```bash
ip -br link
ip -br addr
```

PC Site A :

```text
Interface SERVICES : 192.168.3.250/24, gateway 192.168.3.254
Interface VOICE    : 192.168.30.250/24, pas de gateway par défaut
```

PC Site B :

```text
Interface DMZ : 192.168.40.250/24, gateway 192.168.40.254
```

Ne pas configurer plusieurs gateways par défaut sur le même PC. Si le PC Site A
a deux cartes, garder la gateway par défaut côté SERVICES.

## 4. Lancement PC Site A

Sur le PC Site A, après le `git clone` :

```bash
cd RzoEntreprise
```

Préparer le fichier d'environnement :

```bash
cp .env.site-a.example .env.site-a
nano .env.site-a
```

Adapter :

```text
SERVICES_IFACE=nom_interface_services
VOICE_IFACE=nom_interface_voice
OPENVPN_HOSTNAME=vpn.lafassonnade.lan
```

Premier lancement avec installation/réinstallation Docker :

```bash
./start-site-a.sh --install-deps
```

Lancement normal si Docker est déjà installé :

```bash
./start-site-a.sh
```

Relance propre de la stack Site A :

```bash
./start-site-a.sh --down-first
```

Commandes équivalentes sans script :

```bash
set -a
. ./.env.site-a
set +a
docker compose -f docker-compose.site-a.macvlan.yml up -d --build --remove-orphans
```

Services attendus :

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

## 5. Lancement PC Site B

Sur le PC Site B, après le `git clone` :

```bash
cd RzoEntreprise
```

Préparer le fichier d'environnement :

```bash
cp .env.site-b.example .env.site-b
nano .env.site-b
```

Adapter :

```text
DMZ_IFACE=nom_interface_dmz
```

Premier lancement avec installation/réinstallation Docker :

```bash
./start-site-b.sh --install-deps
```

Lancement normal si Docker est déjà installé :

```bash
./start-site-b.sh
```

Relance propre de la stack Site B :

```bash
./start-site-b.sh --down-first
```

Commandes équivalentes sans script :

```bash
set -a
. ./.env.site-b
set +a
docker compose -f docker-compose.site-b.macvlan.yml up -d --build --remove-orphans
```

Service attendu :

```text
Web DMZ 192.168.40.4
```

## 6. Point important macvlan

Avec macvlan, le PC Docker ne peut souvent pas joindre ses propres conteneurs
par IP. C'est normal.

Tester depuis :

```text
poste admin physique
pfSense
client VPN
autre machine du réseau
```

ou depuis l'intérieur des conteneurs :

```bash
docker exec dns_e3 named-checkconf /etc/bind/named.conf
docker exec asterisk_voip_e3 asterisk -rx "pjsip show endpoints"
```

## 7. Portainer à faire tout de suite

Depuis le poste admin physique :

```text
https://192.168.3.20:9443
```

Créer immédiatement le compte admin. Portainer peut bloquer l'initialisation si
le premier compte n'est pas créé assez vite.

## 8. OpenVPN et nom de domaine

Le profil `.ovpn` ne doit jamais contenir :

```text
remote 192.168.3.10 1194 udp
```

`192.168.3.10` est l'IP interne du conteneur OpenVPN. Le client ne peut pas la
joindre avant d'être connecté.

Le profil doit contenir une adresse joignable avant VPN :

```text
remote vpn.lafassonnade.lan 1194 udp
```

Pour que ça fonctionne, `vpn.lafassonnade.lan` doit résoudre, depuis le client
avant VPN, vers l'entrée OpenVPN exposée par pfSense.

En TP, deux options :

```text
Option simple : ajouter vpn.lafassonnade.lan dans /etc/hosts du client.
Option propre : créer une zone DNS externe/lab qui pointe vers pfSense.
```

Exemple `/etc/hosts` côté client :

```text
IP_ENTREE_PFSENSE_SITE_A vpn.lafassonnade.lan
```

Ensuite, télécharger un nouveau profil `.ovpn` depuis :

```text
https://vpn.lafassonnade.lan:943/
```

## 9. Quel pfSense pour OpenVPN ?

Recommandation pour demain : utiliser **pfSense Site A** comme unique point
d'entrée OpenVPN.

```text
Client -> vpn.lafassonnade.lan -> pfSense Site A -> OpenVPN 192.168.3.10
```

Le client peut être branché derrière n'importe quel routeur seulement si ce
routeur lui permet de joindre le nom `vpn.lafassonnade.lan`. Ce n'est pas le
routeur choisi qui donne accès au VPN : c'est le DNS et le routage vers l'entrée
pfSense qui comptent.

Si vous voulez que pfSense Site B accepte aussi les connexions OpenVPN, il faut
ajouter une redirection Site B vers `192.168.3.10:1194/udp` via WireGuard, ou
installer un deuxième serveur OpenVPN. Pour le TP, garder un seul point d'entrée
est plus simple.

## 10. Tests depuis le poste admin

DNS :

```bash
dig @192.168.3.1 dns.lafassonnade.lan
dig @192.168.3.1 voip.lafassonnade.lan
dig @192.168.3.1 web.lafassonnade.lan
```

LDAP :

```bash
ldapsearch -x -H ldap://192.168.3.5 -b "" -s base namingContexts
```

Portainer :

```bash
curl -k -I https://192.168.3.20:9443
```

Vault :

```bash
curl -s http://192.168.3.15:8200/v1/sys/health | jq
```

Asterisk :

```bash
nc -vz 192.168.30.3 5060
docker exec asterisk_voip_e3 asterisk -rx "pjsip show endpoints"
```

Web DMZ :

```bash
curl http://192.168.40.4/health
```

## 11. Tests OpenVPN client

Depuis le client, avant connexion VPN :

```bash
ping vpn.lafassonnade.lan
nc -vu vpn.lafassonnade.lan 1194
```

Télécharger le profil, puis :

```bash
sudo openvpn --config client1.ovpn
```

Après connexion :

```bash
ip addr | grep tun
ip route | grep 192.168
dig @192.168.3.1 web.lafassonnade.lan
curl http://192.168.40.4/health
```

## 12. Rappel pfSense minimal

pfSense Site A :

```text
SERVICES : 192.168.3.254/24
VOICE    : 192.168.30.254/24
NAT/règle entrée OpenVPN -> 192.168.3.10 UDP 1194
Admin HTTPS OpenVPN      -> 192.168.3.10 TCP 943 si nécessaire
```

pfSense Site B :

```text
DMZ : 192.168.40.254/24
WireGuard site-à-site vers pfSense Site A
```

Routes/règles à vérifier :

```text
SERVICES <-> DMZ via WireGuard selon les règles prévues
OpenVPN clients 10.8.0.0/24 -> SERVICES/DMZ selon besoin
VOICE -> Asterisk 192.168.30.3 TCP/UDP 5060 + UDP 10000-10100
```
