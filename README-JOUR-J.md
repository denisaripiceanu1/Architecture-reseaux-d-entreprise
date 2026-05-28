# RzoEntreprise — fichiers utiles Jour J

Le repo est maintenant orienté vers le montage avec deux pfSense et Docker en
macvlan.

## À utiliser demain

Repartition rapide :

| Personne | Machine | Section principale |
|---|---|---|
| toto | PC Site A | `docs/runbook-site-a-jour-j.md` |
| tata | PC Site B | `docs/runbook-site-b-jour-j.md` |
| titi | Poste admin | `docs/runbook-poste-admin-jour-j.md` |
| equipe pfSense | pfSense | `docs/runbook-pfsense-jour-j.md` |
| test client | Client VPN | `docs/runbook-client-vpn-jour-j.md` |

Sur chaque PC serveur :

```bash
git clone URL_DU_REPO RzoEntreprise
cd RzoEntreprise
```

Git est deja installe sur les machines de lab. Remplacer `URL_DU_REPO` par
l'URL Git du projet.

Le premier lancement avec `--install-deps` installe/reinstalle Docker, prepare
les dossiers runtime, puis lance le Docker Compose du site.

PC Site A, services + voix :

```bash
cp env/site-a.env.example env/site-a.env
nano env/site-a.env
./scripts/start-site-a.sh --install-deps
```

PC Site B, DMZ :

```bash
cp env/site-b.env.example env/site-b.env
nano env/site-b.env
./scripts/start-site-b.sh --install-deps
```

Relances normales :

```bash
./scripts/start-site-a.sh
./scripts/start-site-b.sh
```

## Fichiers principaux

```text
docker-compose.site-a.macvlan.yml
docker-compose.site-b.macvlan.yml
scripts/start-site-a.sh
scripts/start-site-b.sh
scripts/install-deps-linux.sh
scripts/bootstrap-openldap-tree.sh
env/site-a.env.example
env/site-b.env.example
```

Configs utilisées par les compose Jour J :

```text
config/dns/
config/dhcp/
config/ldap/
config/asterisk-pjsip/
config/nginx/
config/vault/
```

Configuration locale a creer sur chaque PC :

```text
env/site-a.env
env/site-b.env
```

Ces fichiers contiennent les noms d'interfaces propres a chaque machine et ne
doivent pas etre versionnes.

Le script d'amorcage LDAP `scripts/bootstrap-openldap-tree.sh` est lance
automatiquement par `./scripts/start-site-a.sh`.

Runtime généré au lancement, à ne pas versionner avec de vrais secrets :

```text
vault-credentials/
vault-credentials/openldap/
vault-credentials/openvpn/
vault-credentials/asterisk/
data/vault/
```

OpenVPN AS stocke sa configuration persistante dans le volume Docker
`openvpn_data`. Les reglages de base automatises passent par `sacli` dans le
`docker-compose.site-a.macvlan.yml`, pas par un dossier `config/openvpn/`.

Docker est configure en `vfs` par defaut par `scripts/install-deps-linux.sh`.
Cela evite les erreurs `overlay` / `whiteout` rencontrees sur certains
filesystems de lab.

Docs :

```text
docs/runbook-site-a-jour-j.md
docs/runbook-site-b-jour-j.md
docs/runbook-jour-j-pfsense-macvlan.md
docs/runbook-poste-admin-jour-j.md
docs/runbook-pfsense-jour-j.md
docs/runbook-client-vpn-jour-j.md
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
