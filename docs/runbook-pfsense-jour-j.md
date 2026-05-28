# Runbook Jour J — pfSense

Responsable : equipe pfSense.

Ce document donne les actions de mise en place. La liste detaillee des regles
est dans :

```text
docs/pfsense-regles-segmentation.md
```

## 1. Interfaces attendues

pfSense Site A :

```text
SERVICES : 192.168.3.254/24
VOICE    : 192.168.30.254/24
```

pfSense Site B :

```text
DMZ : 192.168.40.254/24
```

## 2. WireGuard site-a-site

WireGuard est configure sur les pfSense, pas dans Docker.

Objectif :

```text
Site A SERVICES/VOICE <-> WireGuard <-> Site B DMZ
```

Routes a verifier :

```text
Site A -> 192.168.40.0/24 via tunnel WireGuard
Site B -> 192.168.3.0/24 via tunnel WireGuard
Site B -> 192.168.30.0/24 via tunnel WireGuard si besoin voix/admin
Site B -> 10.8.0.0/24 via tunnel WireGuard si les clients VPN doivent joindre la DMZ
```

## 3. Entree OpenVPN

Recommandation : un seul point d'entree OpenVPN sur pfSense Site A.

Flux attendu :

```text
Client -> vpn.lafassonnade.lan -> pfSense Site A -> OpenVPN AS 192.168.3.10
```

Regles/NAT a prevoir cote entree pfSense :

```text
UDP 1194 -> 192.168.3.10:1194
TCP 943  -> 192.168.3.10:943 si l'UI doit etre accessible depuis l'exterieur/lab
```

Le nom `vpn.lafassonnade.lan` doit resoudre, avant connexion VPN, vers l'entree
pfSense Site A.

## 4. Regles minimales a verifier

SERVICES :

```text
Autoriser le poste admin 192.168.3.241 vers les services internes necessaires
Autoriser DNS vers 192.168.3.1 TCP/UDP 53
Autoriser l'acces a Portainer 192.168.3.20 TCP 9443 depuis admin
Autoriser l'acces a Vault 192.168.3.15 TCP 8200 depuis admin
Autoriser l'acces a phpLDAPadmin 192.168.3.6 TCP 80 depuis admin
```

VOICE :

```text
Autoriser SIP vers Asterisk 192.168.30.3 TCP/UDP 5060
Autoriser RTP vers Asterisk 192.168.30.3 UDP 10000-10100
```

DMZ :

```text
Autoriser HTTP vers 192.168.40.4 TCP 80 selon le scenario de test
Limiter les flux DMZ -> SERVICES au strict necessaire
```

OpenVPN clients :

```text
10.8.0.0/24 -> SERVICES selon besoin
10.8.0.0/24 -> DMZ selon besoin
10.8.0.0/24 -> DNS 192.168.3.1 TCP/UDP 53
```

## 5. Tests rapides

Depuis pfSense ou le poste admin :

```bash
ping 192.168.3.1
ping 192.168.30.3
ping 192.168.40.4
```

Depuis le poste admin :

```bash
dig @192.168.3.1 web.lafassonnade.lan
curl http://192.168.40.4/health
nc -vz 192.168.30.3 5060
```
