# Migration Asterisk vers PJSIP

Cette configuration remplace l'ancien fichier `sip.conf` utilisé par `chan_sip`.
Asterisk 22 utilise PJSIP par défaut, donc les commandes à utiliser sont :

```bash
docker exec asterisk_voip_e3 asterisk -rx "pjsip show endpoints"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show aors"
docker exec asterisk_voip_e3 asterisk -rx "pjsip show contacts"
docker exec asterisk_voip_e3 asterisk -rx "dialplan show internal"
```

Comptes de test :

| Extension | Utilisateur | Mot de passe |
|---|---|---|
| `100` | `100` | `100100` |
| `200` | `200` | `200200` |

L'extension `600` lance un test d'echo.

Après modification :

```bash
docker compose -f docker-compose.segmented.yml up -d --force-recreate asterisk
```

Si les softphones sont hors du réseau Docker et que l'enregistrement fonctionne
mais pas l'audio RTP, vérifier l'adresse annoncée dans les paquets SDP. Il peut
falloir ajouter `external_media_address`, `external_signaling_address` et
`local_net` dans le transport PJSIP avec l'IP réelle du serveur Docker.
