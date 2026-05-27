# pfSense — segmentation services / voix / DMZ

Ce document récapitule la configuration pfSense recommandée pour séparer les
services internes, la VoIP et la DMZ, tout en gardant WireGuard comme VPN
site-à-site entre les routeurs pfSense.

## Plan d'adressage

| Zone | Réseau | Interface pfSense | Rôle |
|---|---:|---:|---|
| SERVICES | `192.168.3.0/24` | `192.168.3.254` | DNS, DHCP, LDAP, Vault, Portainer, OpenVPN |
| VOIX | `192.168.30.0/24` | `192.168.30.254` | Asterisk et téléphones IP |
| DMZ | `192.168.40.0/24` | `192.168.40.254` | Serveur web exposable |
| WireGuard | `10.200.0.0/30` | `10.200.0.1` côté 3a | Tunnel site-à-site |

Dans Docker, la variante segmentée place :

| Service | IP |
|---|---:|
| DNS | `192.168.3.1` |
| DHCP | `192.168.3.2` |
| LDAP | `192.168.3.5` |
| phpLDAPadmin | `192.168.3.6` |
| OpenVPN | `192.168.3.10` |
| Vault | `192.168.3.15` |
| Portainer | `192.168.3.20` |
| Asterisk | `192.168.30.3` |
| Web DMZ | `192.168.40.4` |

Pour le jour J avec les deux pfSense, utiliser les fichiers macvlan :

```text
docker-compose.site-a.macvlan.yml : SERVICES + VOICE
docker-compose.site-b.macvlan.yml : DMZ
```

Dans ce mode, pfSense voit directement les IP des conteneurs. Il ne faut donc
pas utiliser les ports publiés de l'hôte Docker pour tester la segmentation.

## Interfaces pfSense

Créer ou affecter les interfaces suivantes :

| Interface | Adresse | Description |
|---|---:|---|
| `LAN_SERVICES` | `192.168.3.254/24` | Réseau interne services |
| `VOICE` | `192.168.30.254/24` | Réseau voix |
| `DMZ` | `192.168.40.254/24` | Zone démilitarisée |
| `WAN_AS` | IP fournie par le réseau AS | Transit inter-AS |
| `WG_SITE` | `10.200.0.1/30` | WireGuard site-à-site |

Si le lab utilise des VLANs, utiliser par exemple :

| VLAN | Zone |
|---:|---|
| 10 | SERVICES |
| 30 | VOIX |
| 40 | DMZ |

## DHCP

Deux choix possibles.

### Option recommandée pour pfSense

Faire porter le DHCP par pfSense sur chaque interface :

| Interface | Plage DHCP |
|---|---:|
| SERVICES | `192.168.3.100` à `192.168.3.200` |
| VOICE | `192.168.30.100` à `192.168.30.200` |
| DMZ | statique de préférence, sinon `192.168.40.100` à `192.168.40.150` |

DNS distribué : `192.168.3.1`.

### Option avec le conteneur DHCP

Le conteneur DHCP est `192.168.3.2`. Il peut servir VOICE et DMZ seulement si
pfSense relaie les requêtes DHCP.

À activer sur pfSense :

```text
Services > DHCP Relay
Interfaces : VOICE, DMZ
Destination server : 192.168.3.2
```

Ajouter les règles firewall nécessaires pour le relais :

| Interface | Source | Destination | Ports | Action |
|---|---|---|---|---|
| VOICE | `VOICE net` | `192.168.3.2` | UDP `67-68` | Pass |
| DMZ | `DMZ net` | `192.168.3.2` | UDP `67-68` | Pass |

## Alias pfSense

Créer ces alias pour rendre les règles lisibles :

| Alias | Valeur |
|---|---|
| `NET_SERVICES` | `192.168.3.0/24` |
| `NET_VOICE` | `192.168.30.0/24` |
| `NET_DMZ` | `192.168.40.0/24` |
| `NET_OPENVPN` | `10.8.0.0/24` |
| `NET_WG_SITE` | réseau distant du site pair |
| `SRV_DNS` | `192.168.3.1` |
| `SRV_DHCP` | `192.168.3.2` |
| `SRV_LDAP` | `192.168.3.5` |
| `SRV_VAULT` | `192.168.3.15` |
| `SRV_PORTAINER` | `192.168.3.20` |
| `SRV_ASTERISK` | `192.168.30.3` |
| `SRV_WEB_DMZ` | `192.168.40.4` |
| `PORTS_DNS` | TCP/UDP `53` |
| `PORTS_LDAP` | TCP `389`, TCP `636` |
| `PORTS_SIP` | TCP/UDP `5060` |
| `PORTS_RTP` | UDP `10000-10100` |
| `PORTS_WEB` | TCP `80`, TCP `443` |
| `PORTS_ADMIN` | TCP `8200`, TCP `9000`, TCP `9443`, TCP `8080` |

## Politique firewall générale

Principe : bloquer par défaut entre zones, puis ouvrir seulement le nécessaire.

Ordre conseillé sur chaque interface :

1. Autorisations techniques nécessaires.
2. Autorisations applicatives précises.
3. Blocage explicite vers les autres réseaux internes.
4. Autorisation Internet si nécessaire.

## Règles interface SERVICES

| Source | Destination | Ports | Action | Commentaire |
|---|---|---:|---|---|
| `NET_SERVICES` | `SRV_DNS` | TCP/UDP `53` | Pass | Résolution DNS interne |
| `NET_SERVICES` | `SRV_LDAP` | TCP `389,636` | Pass | Annuaire |
| postes admin | `SRV_VAULT` | TCP `8200` | Pass | UI/API Vault admin uniquement |
| postes admin | `SRV_PORTAINER` | TCP `9443,9000` | Pass | Portainer admin uniquement |
| `NET_SERVICES` | `NET_DMZ` | TCP `80,443` | Pass | Accès au web DMZ depuis le LAN |
| `NET_SERVICES` | `NET_VOICE` | any | Block | Éviter les accès latéraux non prévus |

Si certains services internes doivent administrer Asterisk, remplacer la règle
de blocage par une règle ciblée depuis les IP admin vers `SRV_ASTERISK`.

## Règles interface VOICE

| Source | Destination | Ports | Action | Commentaire |
|---|---|---:|---|---|
| `NET_VOICE` | `SRV_DNS` | TCP/UDP `53` | Pass | DNS pour téléphones et Asterisk |
| `NET_VOICE` | `SRV_ASTERISK` | TCP/UDP `5060` | Pass | Signalisation SIP |
| `NET_VOICE` | `SRV_ASTERISK` | UDP `10000-10100` | Pass | Flux RTP voix |
| `SRV_ASTERISK` | `SRV_LDAP` | TCP `389` | Pass | Seulement si Asterisk interroge LDAP |
| `NET_VOICE` | `NET_SERVICES` | any | Block | Sauf exceptions ci-dessus |
| `NET_VOICE` | `NET_DMZ` | any | Block | Pas d'accès voix vers DMZ |

Si les téléphones et Asterisk sont dans le même VLAN, les flux téléphone vers
Asterisk ne passent pas forcément par pfSense. Les règles restent utiles pour
les clients VPN, les sites distants ou les architectures routées.

## Règles interface DMZ

| Source | Destination | Ports | Action | Commentaire |
|---|---|---:|---|---|
| `NET_DMZ` | `SRV_DNS` | TCP/UDP `53` | Pass | DNS si le serveur web en a besoin |
| `NET_DMZ` | Internet | TCP `80,443` | Pass | Mises à jour système/applicatives |
| `NET_DMZ` | `NET_SERVICES` | any | Block | La DMZ ne doit pas initier vers le LAN |
| `NET_DMZ` | `NET_VOICE` | any | Block | Aucun accès DMZ vers voix |

Pour de l'administration DMZ, préférer une règle depuis un poste admin du LAN
vers `SRV_WEB_DMZ`, jamais une règle large depuis la DMZ vers le LAN.

## NAT WAN vers DMZ

Pour exposer le serveur web :

```text
Firewall > NAT > Port Forward
Interface : WAN_AS
Protocol  : TCP
Destination port : 80
Redirect target IP : 192.168.40.4
Redirect target port : 80
```

Si HTTPS est configuré :

```text
Destination port : 443
Redirect target IP : 192.168.40.4
Redirect target port : 443
```

pfSense peut créer automatiquement les règles WAN associées. Sinon ajouter :

| Interface | Source | Destination | Ports | Action |
|---|---|---|---:|---|
| WAN_AS | any | `WAN address` | TCP `80,443` | Pass |

## NAT sortant

Conserver le NAT uniquement vers le WAN :

```text
Firewall > NAT > Outbound
Mode : Hybrid ou Manual
```

Règles NAT vers WAN :

| Source | Destination | Traduction |
|---|---|---|
| `NET_SERVICES` | Internet | WAN address |
| `NET_VOICE` | Internet | WAN address |
| `NET_DMZ` | Internet | WAN address |

Ne pas faire de NAT entre SERVICES, VOICE, DMZ et WireGuard. Le trafic interne
doit rester routé et filtré, pas masqué.

## WireGuard site-à-site

WireGuard doit être configuré sur les pfSense, pas dans Docker.

Côté site A :

| Paramètre | Valeur |
|---|---|
| Interface WG | `10.200.0.1/30` |
| Peer distant | IP WAN/AS pfSense site B |
| Allowed IPs | `192.168.40.0/24` |

Côté site B :

| Paramètre | Valeur |
|---|---|
| Interface WG | `10.200.0.2/30` |
| Peer distant | IP WAN/AS pfSense site A |
| Allowed IPs | `192.168.3.0/24`, `192.168.30.0/24`, `10.8.0.0/24` |

Sur WAN, autoriser le port WireGuard :

| Interface | Source | Destination | Port | Action |
|---|---|---|---:|---|
| WAN_AS | IP WAN peer | WAN address | UDP `51820` | Pass |

Sur l'interface WireGuard, autoriser seulement les flux inter-sites voulus,
par exemple :

| Source | Destination | Ports | Action |
|---|---|---:|---|
| réseau site distant | `SRV_WEB_DMZ` | TCP `80,443` | Pass |
| réseau site distant | `SRV_DNS` | TCP/UDP `53` | Pass |
| réseau site distant | `SRV_ASTERISK` | TCP/UDP `5060`, UDP `10000-10100` | Pass si VoIP inter-site |

## OpenVPN accès distant

OpenVPN ne dépend pas de WireGuard. Il sert aux utilisateurs distants.

Recommandation pour le TP : exposer OpenVPN sur pfSense Site A uniquement.

```text
Client -> vpn.lafassonnade.lan -> pfSense Site A -> 192.168.3.10
```

NAT sur pfSense Site A :

| Interface | Source | Destination | Port | Redirection |
|---|---|---|---:|---|
| WAN_AS | clients VPN | WAN address | UDP `1194` | `192.168.3.10:1194` |
| WAN_AS | postes admin autorisés | WAN address | TCP `943` | `192.168.3.10:943` |

Le nom `vpn.lafassonnade.lan` utilisé dans les profils `.ovpn` doit résoudre
avant connexion VPN vers l'entrée pfSense, pas vers `192.168.3.10`. En lab,
utiliser `/etc/hosts` sur le client ou un DNS externe/lab.

Règles recommandées pour les clients OpenVPN (`10.8.0.0/24`) :

| Source | Destination | Ports | Action |
|---|---|---:|---|
| `NET_OPENVPN` | `SRV_DNS` | TCP/UDP `53` | Pass |
| `NET_OPENVPN` | `SRV_LDAP` | TCP `389` | Pass si nécessaire |
| `NET_OPENVPN` | `SRV_WEB_DMZ` | TCP `80,443` | Pass si besoin |
| `NET_OPENVPN` | `SRV_VAULT`, `SRV_PORTAINER` | any | Block sauf admins |
| `NET_OPENVPN` | `NET_VOICE` | any | Block par défaut |

## QoS VoIP

Prioriser la voix sur pfSense, idéalement avec Traffic Shaper ou Limiters.

Flux prioritaires :

| Flux | Ports |
|---|---:|
| SIP | TCP/UDP `5060` |
| RTP | UDP `10000-10100` |

Priorité :

1. RTP UDP `10000-10100` : priorité haute.
2. SIP `5060` : priorité haute ou moyenne-haute.
3. DNS : priorité normale.
4. Web/admin/Vault/Portainer : priorité basse ou normale.

Créer des règles flottantes si besoin :

```text
Firewall > Rules > Floating
Quick : yes
Interface : WAN_AS, VOICE, WG_SITE
Protocol : UDP
Source/Destination : SRV_ASTERISK ou NET_VOICE
Ports : 10000-10100
Queue : high priority / voice
```

## Tests de validation

Depuis SERVICES :

```bash
dig @192.168.3.1 web.lafassonnade.lan
dig @192.168.3.1 voip.lafassonnade.lan
curl http://192.168.40.4/health
```

Depuis VOICE :

```bash
ping 192.168.30.3
dig @192.168.3.1 ldap.lafassonnade.lan
```

Depuis DMZ :

```bash
dig @192.168.3.1 dns.lafassonnade.lan
curl http://example.com
```

Depuis pfSense :

```text
Diagnostics > Ping
Source address : interface testée
Destination : IP du service
```

## Points d'attention

- Les règles pfSense sont évaluées de haut en bas sur l'interface d'entrée.
- La passerelle des clients est toujours l'IP pfSense de leur réseau, jamais
  l'IP WireGuard.
- Éviter le même subnet des deux côtés du VPN site-à-site.
- Ne pas NATer les flux entre VLANs internes ni à travers WireGuard.
- Garder Vault et Portainer accessibles uniquement depuis des postes admin.
- Les serveurs en DMZ doivent initier le moins de connexions possible vers le
  réseau SERVICES.
