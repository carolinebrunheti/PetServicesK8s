#!/usr/bin/env bash
# Cria os Secrets do cluster com senhas aleatorias.
# Rode UMA vez por cluster: o Postgres grava as senhas dos usuarios na primeira
# inicializacao, entao gerar senhas novas depois quebraria o login das APIs.
#
# uso: ./criar-secrets.sh email-do-admin
set -euo pipefail

ADMIN_EMAIL="${1:?uso: ./criar-secrets.sh email-do-admin}"
cd "$(dirname "$0")"

kubectl apply -f base/00-namespaces.yaml >/dev/null

if kubectl get secret postgres-credenciais -n infra >/dev/null 2>&1; then
    echo "Os Secrets ja existem neste cluster; nada foi alterado."
    exit 0
fi

gerar() { openssl rand -hex "$1"; }

PG_SUPERUSUARIO=$(gerar 24)
DB_CADASTROS=$(gerar 24)
DB_AGENDAMENTO=$(gerar 24)
DB_HISTORICO=$(gerar 24)
# o mesmo segredo nos 3 servicos: o petServices assina o JWT e os outros validam
JWT_SECRET=$(gerar 32)
ADMIN_SENHA=$(gerar 12)

kubectl create secret generic postgres-credenciais -n infra \
    --from-literal=POSTGRES_PASSWORD="$PG_SUPERUSUARIO" \
    --from-literal=CADASTROS_DB_PASSWORD="$DB_CADASTROS" \
    --from-literal=AGENDAMENTO_DB_PASSWORD="$DB_AGENDAMENTO" \
    --from-literal=HISTORICO_DB_PASSWORD="$DB_HISTORICO"

kubectl create secret generic petservices-secrets -n petservices \
    --from-literal=DB_PASSWORD="$DB_CADASTROS" \
    --from-literal=JWT_SECRET="$JWT_SECRET" \
    --from-literal=ADMIN_EMAIL="$ADMIN_EMAIL" \
    --from-literal=ADMIN_SENHA="$ADMIN_SENHA"

kubectl create secret generic agendamento-secrets -n petservices \
    --from-literal=DB_PASSWORD="$DB_AGENDAMENTO" \
    --from-literal=JWT_SECRET="$JWT_SECRET"

kubectl create secret generic historico-secrets -n petservices \
    --from-literal=DB_PASSWORD="$DB_HISTORICO" \
    --from-literal=JWT_SECRET="$JWT_SECRET"

echo
echo "Admin inicial: $ADMIN_EMAIL"
echo "Senha:         $ADMIN_SENHA"
echo "(para ver de novo: kubectl get secret petservices-secrets -n petservices -o jsonpath='{.data.ADMIN_SENHA}' | base64 -d)"
