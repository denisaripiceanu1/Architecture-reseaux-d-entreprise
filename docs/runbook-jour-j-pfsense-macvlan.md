# Runbook Jour J — index

Ce fichier sert uniquement d'index. Chaque personne suit son document.

| Personne | Responsabilite | Document |
|---|---|---|
| toto | PC Site A, services + voix | `docs/runbook-site-a-jour-j.md` |
| tata | PC Site B, DMZ web | `docs/runbook-site-b-jour-j.md` |
| titi | Poste admin physique | `docs/runbook-poste-admin-jour-j.md` |
| equipe pfSense | pfSense Site A/Site B | `docs/runbook-pfsense-jour-j.md` |
| test client | Client VPN externe | `docs/runbook-client-vpn-jour-j.md` |

Docs de reference :

```text
docs/admin-acces-configuration-outils.md
docs/pfsense-regles-segmentation.md
```

## Topologie rapide

| Élément | Rôle | Réseaux |
|---|---|---|
| PC Site A | Services internes + voix | `192.168.3.0/24`, `192.168.30.0/24` |
| PC Site B | DMZ web | `192.168.40.0/24` |
| pfSense Site A | Routage/firewall SERVICES/VOICE + entree OpenVPN | `192.168.3.254`, `192.168.30.254` |
| pfSense Site B | Routage/firewall DMZ | `192.168.40.254` |
| Poste admin physique | Administration | `192.168.3.241/24` |
| Client VPN | Client externe | hors reseaux internes avant VPN |

## Rappel macvlan

Avec macvlan, les conteneurs apparaissent directement sur les reseaux pfSense
avec leurs IP finales. Le PC Docker ne peut souvent pas joindre ses propres
conteneurs par IP : c'est normal.

Tester depuis :

```text
poste admin physique
pfSense
client VPN
autre machine du reseau
interieur d'un conteneur
```
