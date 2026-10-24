#!/usr/bin/env bash
# Cria as identidades que o GitHub Actions usa para entrar na Azure SEM senha
# (OIDC): o Entra ID confia nos tokens que o GitHub emite para a branch main
# de cada repositorio listado abaixo, e em mais nenhum.
#
#   github-petservices-build  → so pode enviar imagens para o ACR (AcrPush)
#   github-petservices-deploy → so pode pegar acesso ao cluster AKS
#
# Rode uma vez. No final ele mostra os valores para cadastrar no GitHub.
set -euo pipefail
cd "$(dirname "$0")"
source azure.env

DONO=carolinebrunheti
REPOS_APIS=(PetServices PetAgendamentoApi HistoricoPetApi1)
REPO_K8S=PetServicesK8s

ASSINATURA=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)
ACR_ID=$(az acr show -n "$ACR" --query id -o tsv)
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)

# cria (ou reaproveita) o app registration + service principal e devolve o appId
criar_identidade() {
    local nome=$1 app_id
    app_id=$(az ad app list --display-name "$nome" --query "[0].appId" -o tsv)
    if [ -z "$app_id" ]; then
        app_id=$(az ad app create --display-name "$nome" --query appId -o tsv)
    fi
    az ad sp show --id "$app_id" >/dev/null 2>&1 || az ad sp create --id "$app_id" >/dev/null
    echo "$app_id"
}

# "confie nos tokens do GitHub Actions deste repositorio, branch main"
confiar_no_repo() {
    local app_id=$1 repo=$2
    az ad app federated-credential list --id "$app_id" --query "[].name" -o tsv | grep -qx "$repo-main" && return
    az ad app federated-credential create --id "$app_id" --parameters "{
        \"name\": \"$repo-main\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"repo:$DONO/$repo:ref:refs/heads/main\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
    }" >/dev/null
}

echo "1/2 identidade de build (AcrPush no $ACR)..."
BUILD_ID=$(criar_identidade github-petservices-build)
for repo in "${REPOS_APIS[@]}"; do confiar_no_repo "$BUILD_ID" "$repo"; done
az role assignment create --assignee "$BUILD_ID" --role AcrPush --scope "$ACR_ID" >/dev/null

echo "2/2 identidade de deploy (acesso ao $AKS)..."
DEPLOY_ID=$(criar_identidade github-petservices-deploy)
confiar_no_repo "$DEPLOY_ID" "$REPO_K8S"
az role assignment create --assignee "$DEPLOY_ID" \
    --role "Azure Kubernetes Service Cluster User Role" --scope "$AKS_ID" >/dev/null

cat <<EOF

Pronto! Cadastre no GitHub (Settings → Secrets and variables → Actions → aba Variables):

  Nos repositorios ${REPOS_APIS[*]}:
    AZURE_CLIENT_ID       = $BUILD_ID
    AZURE_TENANT_ID       = $TENANT
    AZURE_SUBSCRIPTION_ID = $ASSINATURA

  No repositorio $REPO_K8S:
    AZURE_CLIENT_ID       = $DEPLOY_ID
    AZURE_TENANT_ID       = $TENANT
    AZURE_SUBSCRIPTION_ID = $ASSINATURA

(sao identificadores, nao senhas: sozinhos nao dao acesso a nada)
EOF
