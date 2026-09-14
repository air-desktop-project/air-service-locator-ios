#!/usr/bin/env bash
#
# check-version — cette branche change-t-elle la version de l'application ?
#
# # La règle
#
# **Chaque PR change la version semver** (`MARKETING_VERSION` dans
# `project.yml`), dans le commit qui porte le changement. Une version qui ne
# bouge pas entre deux livraisons est une version qui ne dit plus rien : deux
# appareils affichant « 0.2.0 » pourraient faire tourner deux codes
# différents, et l'utilisateur qui rapporte « 0.2.0 » ne dirait rien non plus.
#
# # Ce que le gate vérifie
#
#   VIOLATION  la version de HEAD est celle de la base          → à incrémenter
#   VIOLATION  la version n'est pas un semver `MAJEURE.MINEURE.CORRECTIF`
#   VIOLATION  le numéro de build (`CURRENT_PROJECT_VERSION`) n'a pas augmenté
#
# # Le périmètre
#
# On compare `project.yml` à HEAD et à la base — la branche cible de la PR.
# Sans base (un push sur `main`, un premier commit), il n'y a rien à comparer
# et le gate ne vérifie que la forme.
#
# Usage : scripts/check-version.sh [base]

set -euo pipefail

base="${1:-}"
fichier="project.yml"

lire() {
  # $1 : révision (vide = fichier de travail), $2 : clé
  local contenu
  if [ -n "$1" ]; then contenu=$(git show "$1:$fichier" 2>/dev/null || true); else contenu=$(cat "$fichier"); fi
  printf '%s\n' "$contenu" | sed -n "s/^ *$2: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *$/\1/p" | head -1
}

version=$(lire "" MARKETING_VERSION)
build=$(lire "" CURRENT_PROJECT_VERSION)
violations=0

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "VIOLATION  MARKETING_VERSION « $version » n'est pas un semver MAJEURE.MINEURE.CORRECTIF"
  violations=$((violations + 1))
fi
if ! printf '%s' "$build" | grep -Eq '^[0-9]+$'; then
  echo "VIOLATION  CURRENT_PROJECT_VERSION « $build » n'est pas un entier"
  violations=$((violations + 1))
fi

if [ -n "$base" ] && git rev-parse --verify --quiet "$base" >/dev/null; then
  version_base=$(lire "$base" MARKETING_VERSION)
  build_base=$(lire "$base" CURRENT_PROJECT_VERSION)
  if [ "$version" = "$version_base" ]; then
    echo "VIOLATION  la version est encore « $version », celle de $base : chaque PR la change"
    violations=$((violations + 1))
  else
    echo "version : $version_base → $version"
  fi
  if [ -n "$build_base" ] && [ "$build" -le "$build_base" ] 2>/dev/null; then
    echo "VIOLATION  le numéro de build $build n'a pas augmenté depuis $build_base"
    violations=$((violations + 1))
  fi
else
  echo "version : $version ($build) — pas de base, forme seule vérifiée"
fi

[ "$violations" -eq 0 ] || exit 1
echo "check-version : OK"
