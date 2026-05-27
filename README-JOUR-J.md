# RzoEntreprise — fichiers utiles Jour J

Le repo est maintenant orienté vers le montage avec deux pfSense et Docker en
macvlan.

## À utiliser demain

Sur chaque PC serveur :

```bash
sudo apt update
sudo apt install -y git
git clone URL_DU_REPO RzoEntreprise
cd RzoEntreprise
```

Remplacer `URL_DU_REPO` par l'URL Git du projet.

PC Site A, services + voix :

```bash
cp .env.site-a.example .env.site-a
nano .env.site-a
./start-site-a.sh --install-deps
```

PC Site B, DMZ :

```bash
cp .env.site-b.example .env.site-b
nano .env.site-b
./start-site-b.sh --install-deps
```

Relances normales :

```bash
./start-site-a.sh
./start-site-b.sh
```

## Fichiers principaux

```text
docker-compose.site-a.macvlan.yml
docker-compose.site-b.macvlan.yml
start-site-a.sh
start-site-b.sh
.env.site-a.example
.env.site-b.example
install-deps-linux-v2.sh
```

Configs utilisées par les compose Jour J :

```text
config/dns/
config/dhcp/
config/asterisk-pjsip/
config/openldap/
config/nginx/
config/vault/
```

Docs :

```text
docs/runbook-jour-j-pfsense-macvlan.md
docs/runbook-poste-admin-jour-j.md
docs/pfsense-regles-segmentation.md
docs/admin-acces-configuration-outils.md
```

## Important OpenVPN

Le profil client doit contenir :

```text
remote vpn.lafassonnade.lan 1194 udp
```

Il ne doit pas contenir :

```text
remote 192.168.3.10 1194 udp
```

Le nom `vpn.lafassonnade.lan` doit résoudre avant la connexion VPN vers
l'entrée pfSense Site A.
