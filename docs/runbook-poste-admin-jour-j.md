# Runbook Jour J — Poste admin physique

Ce document décrit uniquement les étapes à faire depuis la machine admin
physique. Il complète :

```text
docs/runbook-site-a-jour-j.md
docs/runbook-site-b-jour-j.md
docs/runbook-pfsense-jour-j.md
docs/pfsense-regles-segmentation.md
```

## 1. Configurer le poste admin

Brancher le poste admin sur le réseau SERVICES.

Configuration réseau :

```text
IP      : 192.168.3.241/24
Gateway : 192.168.3.254
DNS     : 192.168.3.1
```

Installer les outils :

```bash
sudo apt update
sudo apt install -y curl dnsutils ldap-utils jq netcat-openbsd nmap openvpn
```

Vérifier la connectivité :

```bash
ping 192.168.3.254
ping 192.168.3.1
```

## 2. Vérifier DNS

```bash
dig @192.168.3.1 dns.lafassonnade.lan
dig @192.168.3.1 ldap.lafassonnade.lan
dig @192.168.3.1 ldapadmin.lafassonnade.lan
dig @192.168.3.1 vault.lafassonnade.lan
dig @192.168.3.1 portainer.lafassonnade.lan
dig @192.168.3.1 voip.lafassonnade.lan
dig @192.168.3.1 web.lafassonnade.lan
```

Résultats attendus :

```text
dns        -> 192.168.3.1
ldap       -> 192.168.3.5
ldapadmin  -> 192.168.3.6
vault      -> 192.168.3.15
portainer  -> 192.168.3.20
voip       -> 192.168.30.3
web        -> 192.168.40.4
```

## 3. Initialiser Portainer immédiatement

À faire dès que le PC Site A est démarré.

Ouvrir :

```text
https://192.168.3.20:9443
```

Actions :

```text
Créer le compte admin
Choisir l'environnement local Docker
Vérifier les conteneurs du Site A
```

Test CLI :

```bash
curl -k -I https://192.168.3.20:9443
```

## 4. Vérifier Vault

Ouvrir :

```text
http://192.168.3.15:8200/ui
```

Health check :

```bash
curl -s http://192.168.3.15:8200/v1/sys/health | jq
```

Sur le PC Site A, récupérer le root token si nécessaire :

```bash
jq -r .root_token vault-credentials/vault-init.json
```

## 5. Vérifier LDAP

Sur le PC Site A, `./scripts/start-site-a.sh` initialise automatiquement
l'arborescence LDAP de base. Si besoin, relancer l'amorcage :

```bash
./scripts/bootstrap-openldap-tree.sh
```

Tester l'annuaire :

```bash
ldapsearch -x -H ldap://192.168.3.5 -b "" -s base namingContexts
ldapsearch -x -H ldap://192.168.3.5 -b "dc=lafassonnade,dc=lan" "(uid=alice)"
ldapwhoami -x -H ldap://192.168.3.5 \
  -D "uid=alice,ou=users,dc=lafassonnade,dc=lan" \
  -w "alice123"
```

Ouvrir phpLDAPadmin :

```text
http://192.168.3.6
```

Identifiant :

```text
cn=admin,dc=lafassonnade,dc=lan
```

Sur le PC Site A, récupérer le mot de passe :

```bash
docker exec openldap sh -c 'cat /run/secrets/ldap-admin-password'
```

À vérifier :

```text
Base DN dc=lafassonnade,dc=lan visible
OU users, groups et services visibles
Utilisateurs alice, bob et admin-tp visibles
Groupes admins, vpn-users et voip-users visibles
Bind utilisateur possible
```

## 6. Vérifier le web DMZ

Depuis le poste admin :

```bash
curl http://192.168.40.4/health
curl -I http://192.168.40.4
```

Si ça échoue, vérifier les règles pfSense entre SERVICES et DMZ, puis vérifier
sur le PC Site B :

```bash
docker compose --env-file env/site-b.env -f docker-compose.site-b.macvlan.yml ps
docker logs web_entreprise3b --tail 80
```

## 7. Vérifier Asterisk

Depuis le poste admin :

```bash
nc -vz 192.168.30.3 5060
```

Depuis le PC Site A :

```bash
docker exec asterisk_voip_e3 asterisk -rx "core show uptime"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show endpoints"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show contacts"
docker exec asterisk_voip_e3 asterisk -rx "dialplan show internal"
```

Comptes softphone :

```text
Extension 100 : utilisateur 100 / mot de passe 100100
Extension 200 : utilisateur 200 / mot de passe 200200
Extension 600 : test echo
```

## 8. Vérifier OpenVPN AS

Le nom utilisé par les clients doit résoudre vers l'entrée pfSense Site A :

```bash
getent hosts vpn.lafassonnade.lan
```

Si le DNS externe/lab n'est pas prêt, ajouter temporairement sur le client :

```text
IP_ENTREE_PFSENSE_SITE_A vpn.lafassonnade.lan
```

dans `/etc/hosts`.

Ouvrir l'admin :

```text
https://vpn.lafassonnade.lan:943/admin
```

Compte :

```text
openvpn
```

Sur le PC Site A, récupérer le mot de passe :

```bash
docker logs openvpn_gateway | grep -i "pass"
```

Vérifier la configuration :

```bash
docker exec openvpn_gateway sh -lc 'sacli ConfigQuery | grep -E "host.name|ovpndco"'
```

Attendu :

```text
host.name = vpn.lafassonnade.lan
vpn.server.daemon.ovpndco = false
```

Dans l'UI OpenVPN :

```text
Créer client1
Définir son mot de passe
Pousser les routes 192.168.3.0/24 et 192.168.40.0/24 si besoin
Définir DNS VPN = 192.168.3.1
Définir domaine = lafassonnade.lan
Sauvegarder et appliquer
```

## 9. Tester le client VPN

Depuis la machine cliente, hors réseaux internes :

```bash
ping vpn.lafassonnade.lan
```

Télécharger le profil depuis :

```text
https://vpn.lafassonnade.lan:943/
```

Vérifier que le profil ne contient pas :

```text
remote 192.168.3.10 1194 udp
```

Puis lancer :

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

## 10. Checklist finale admin

```text
[ ] DNS répond depuis le poste admin
[ ] Portainer initialisé
[ ] Vault accessible et unsealed
[ ] LDAP répond
[ ] phpLDAPadmin accessible
[ ] Web DMZ accessible selon règles pfSense
[ ] Asterisk PJSIP voit les endpoints 100/200
[ ] OpenVPN AS accessible via vpn.lafassonnade.lan
[ ] Profil client OpenVPN pointe vers vpn.lafassonnade.lan
[ ] Client VPN reçoit une IP 10.8.0.x
[ ] Client VPN atteint DNS et Web DMZ selon règles
```
