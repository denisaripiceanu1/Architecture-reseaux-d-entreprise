# Runbook Jour J — Client VPN

Responsable : personne qui teste le client externe.

Le client doit etre hors des reseaux internes avant connexion VPN. Il doit
seulement pouvoir joindre l'entree OpenVPN exposee par pfSense.

## 1. Resolution du nom VPN

Le profil `.ovpn` doit contenir :

```text
remote vpn.lafassonnade.lan 1194 udp
```

Il ne doit jamais contenir :

```text
remote 192.168.3.10 1194 udp
```

`192.168.3.10` est l'IP interne du conteneur OpenVPN AS. Le client ne peut pas
la joindre avant d'etre connecte.

Si le DNS externe/lab n'est pas pret, ajouter temporairement dans `/etc/hosts` :

```text
IP_ENTREE_PFSENSE_SITE_A vpn.lafassonnade.lan
```

## 2. Tests avant connexion

```bash
getent hosts vpn.lafassonnade.lan
ping vpn.lafassonnade.lan
nc -vu vpn.lafassonnade.lan 1194
```

## 3. Recuperer le profil

Ouvrir :

```text
https://vpn.lafassonnade.lan:943/
```

Telecharger le profil client genere par OpenVPN AS.

## 4. Connexion

```bash
sudo openvpn --config client1.ovpn
```

## 5. Tests apres connexion

```bash
ip addr | grep tun
ip route | grep 192.168
dig @192.168.3.1 web.lafassonnade.lan
curl http://192.168.40.4/health
```

Tests supplementaires :

```bash
ping 192.168.3.1
ping 192.168.40.4
curl -k -I https://192.168.3.20:9443
```
