#!/usr/bin/env bash
# =============================================================================
# ldap-passwords.sh — Génération des hashs SSHA pour le LDIF bootstrap
#
# Prérequis : avoir ldap-utils installé (apt install ldap-utils)
# OU utiliser le conteneur openldap directement :
#   docker exec openldap slappasswd -s "monmotdepasse"
#
# Usage : ./ldap-passwords.sh
# Les hashs générés sont à coller dans 01-structure.ldif
# =============================================================================

set -euo pipefail

echo "Génération des hashs SSHA pour les utilisateurs LDAP..."
echo "Remplacez les {SSHA}ChangeMe_* dans 01-structure.ldif par ces valeurs"
echo ""

users=("pdg" "tech1" "tech2" "admin1" "particulier" "svc-asterisk" "svc-openvpn")

for user in "${users[@]}"; do
  read -rsp "Mot de passe pour $user : " password
  echo ""
  hash=$(docker exec openldap slappasswd -s "$password")
  echo "  $user → $hash"
  echo ""
done

echo "Terminé. Pensez à redémarrer le conteneur openldap après modification du LDIF :"
echo "  docker compose restart openldap"
