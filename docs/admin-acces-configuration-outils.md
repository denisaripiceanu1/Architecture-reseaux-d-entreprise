# Guide admin — Accès aux outils Jour J

Ce guide correspond au montage pfSense + macvlan. Il n'y a plus de conteneur
admin : l'administration se fait depuis la machine physique admin.

Poste admin recommandé :

```text
IP      : 192.168.3.241/24
Gateway : 192.168.3.254
DNS     : 192.168.3.1
```

## Commandes Docker

Sur le PC Site A :

```bash
./start-site-a.sh
docker compose -f docker-compose.site-a.macvlan.yml ps
docker compose -f docker-compose.site-a.macvlan.yml logs -f
```

Sur le PC Site B :

```bash
./start-site-b.sh
docker compose -f docker-compose.site-b.macvlan.yml ps
docker compose -f docker-compose.site-b.macvlan.yml logs -f
```

## DNS

Service :

```text
dns.lafassonnade.lan = 192.168.3.1
```

Tester depuis le poste admin :

```bash
dig @192.168.3.1 dns.lafassonnade.lan
dig @192.168.3.1 voip.lafassonnade.lan
dig @192.168.3.1 web.lafassonnade.lan
```

Valider côté Site A :

```bash
docker exec dns_e3 named-checkconf /etc/bind/named.conf
docker exec dns_e3 named-checkzone lafassonnade.lan /etc/bind/zones/db.lafassonnade.lan
docker compose -f docker-compose.site-a.macvlan.yml restart dns
```

## LDAP et phpLDAPadmin

Services :

```text
ldap.lafassonnade.lan      = 192.168.3.5
ldapadmin.lafassonnade.lan = 192.168.3.6
```

Interface :

```text
http://192.168.3.6
```

Identifiant :

```text
cn=admin,dc=lafassonnade,dc=lan
```

Récupérer le mot de passe :

```bash
docker exec openldap sh -c 'cat /run/secrets/ldap-admin-password'
```

Tester :

```bash
ldapsearch -x -H ldap://192.168.3.5 -b "" -s base namingContexts
```

## Vault

Service :

```text
vault.lafassonnade.lan = 192.168.3.15
```

Interface :

```text
http://192.168.3.15:8200/ui
```

Root token côté Site A :

```bash
jq -r .root_token vault-credentials/vault-init.json
```

Health :

```bash
curl -s http://192.168.3.15:8200/v1/sys/health | jq
```

Si Vault Agent indique `invalid role or secret ID`, faire un reset cohérent en
lab :

```bash
docker compose -f docker-compose.site-a.macvlan.yml down
sudo rm -rf data/vault
rm -rf vault-credentials
mkdir -p data/vault
sudo chown -R 100:1000 data/vault
sudo chmod 700 data/vault
./start-site-a.sh
```

## Portainer

Service :

```text
portainer.lafassonnade.lan = 192.168.3.20
```

Interface :

```text
https://192.168.3.20:9443
```

Créer le compte admin immédiatement après le premier démarrage.

## Asterisk

Service :

```text
voip.lafassonnade.lan = 192.168.30.3
```

Commandes côté Site A :

```bash
docker exec asterisk_voip_e3 asterisk -rx "core show uptime"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show endpoints"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show contacts"
docker exec asterisk_voip_e3 asterisk -rx "dialplan show internal"
```

Comptes de test :

```text
Extension 100 : utilisateur 100 / mot de passe 100100
Extension 200 : utilisateur 200 / mot de passe 200200
Extension 600 : test echo
```

Ports à autoriser/prioriser :

```text
SIP : TCP/UDP 5060
RTP : UDP 10000-10100
```

## Web DMZ

Service :

```text
web.lafassonnade.lan = 192.168.40.4
```

Tester depuis le poste admin si les règles pfSense l'autorisent :

```bash
curl http://192.168.40.4/health
```

Redémarrer côté Site B :

```bash
docker compose -f docker-compose.site-b.macvlan.yml restart web_3b
```

## OpenVPN Access Server

Service interne :

```text
OpenVPN AS = 192.168.3.10
```

Le profil client doit pointer vers l'entrée pfSense, pas vers `192.168.3.10` :

```text
remote vpn.lafassonnade.lan 1194 udp
```

Vérifier côté Site A :

```bash
docker exec openvpn_gateway sh -lc 'sacli ConfigQuery | grep -E "host.name|ovpndco"'
```

Résultat attendu :

```text
host.name = vpn.lafassonnade.lan
vpn.server.daemon.ovpndco = false
```

Interface admin :

```text
https://vpn.lafassonnade.lan:943/admin
```

Compte admin :

```text
openvpn
```

Récupérer le mot de passe :

```bash
docker logs openvpn_gateway | grep -i "pass"
```

À configurer dans l'UI :

```text
Utilisateur client1
Routes privées : 192.168.3.0/24 et 192.168.40.0/24 si besoin
DNS VPN : 192.168.3.1
Domaine : lafassonnade.lan
```

## DHCP

Recommandation demain : faire porter le DHCP par pfSense, ou utiliser le DHCP
Relay pfSense vers `192.168.3.2`.

Vérifier le conteneur DHCP si utilisé :

```bash
docker logs dhcp_e3 --tail 80
docker exec dhcp_e3 cat /data/dhcpd.leases
```
