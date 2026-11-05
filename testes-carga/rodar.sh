#!/usr/bin/env bash
# Roda o fluxo.js com o painel web do k6 (graficos ao vivo em http://127.0.0.1:5665)
# e salva um relatorio HTML em relatorios/ para comparar os testes depois.
# O painel roda so na sua maquina: nada e enviado para a Grafana.
#
# Uso: bash rodar.sh <smoke|load|stress|spike|soak> [nome-do-experimento]
#   ex.: bash rodar.sh load 2replicas
set -euo pipefail
cd "$(dirname "$0")"

TIPO="${1:?Uso: bash rodar.sh <smoke|load|stress|spike|soak> [nome-do-experimento]}"
NOME="${2:-}"

# pede o login do admin so se ainda nao estiver definido; a senha nao aparece na tela nem fica no historico
[ -n "${ADMIN_EMAIL:-}" ] || read -rp "E-mail do admin: " ADMIN_EMAIL
[ -n "${ADMIN_SENHA:-}" ] || { read -rsp "Senha do admin: " ADMIN_SENHA; echo; }
export ADMIN_EMAIL ADMIN_SENHA

mkdir -p relatorios
RELATORIO="relatorios/$(date +%Y-%m-%d_%H-%M)_${TIPO}${NOME:+_$NOME}.html"

echo "Painel ao vivo: http://127.0.0.1:5665"
echo "Relatorio ao final: testes-carga/$RELATORIO"
echo

K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_OPEN=true \
K6_WEB_DASHBOARD_EXPORT="$RELATORIO" \
TIPO="$TIPO" k6 run fluxo.js
