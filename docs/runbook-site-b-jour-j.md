# Runbook Jour J — Site B

Responsable : tata.

Ce PC heberge le service web en DMZ :

```text
DMZ : 192.168.40.0/24
```

## 1. Branchement

```text
Interface DMZ -> pfSense Site B DMZ
```

Configuration reseau attendue :

```text
Interface DMZ : 192.168.40.250/24, gateway 192.168.40.254
```

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
cp env/site-b.env.example env/site-b.env
nano env/site-b.env
```

Adapter :

```text
DMZ_IFACE=nom_interface_dmz
```

## 4. Premier lancement

Cette commande installe/reinstalle Docker, prepare les dossiers runtime,
construit les images puis lance la stack Site B :

```bash
./scripts/start-site-b.sh --install-deps
```

## 5. Relances utiles

Relance normale :

```bash
./scripts/start-site-b.sh
```

Relance propre :

```bash
./scripts/start-site-b.sh --down-first
```

## 6. Service attendu

```text
Web DMZ 192.168.40.4
```

## 7. Verifications cote Site B

```bash
docker compose --env-file env/site-b.env -f docker-compose.site-b.macvlan.yml ps
docker logs web_entreprise3b --tail 80
```

Le test HTTP complet se fait depuis le poste admin ou via pfSense :

```bash
curl http://192.168.40.4/health
curl -I http://192.168.40.4
```

## 8. Erreur overlay/whiteout Docker

Si Docker affiche une erreur du type :

```text
failed to convert whiteout file: operation not supported
failed to mount source overlay
```

le filesystem du lab ne supporte probablement pas correctement `overlay2`.
Relancer l'installation propre : le script configure Docker en `vfs` par defaut
et supprime l'ancien stockage Docker.

```bash
./scripts/start-site-b.sh --install-deps
docker info | grep -i "Storage Driver"
```

Attendu :

```text
Storage Driver: vfs
```
