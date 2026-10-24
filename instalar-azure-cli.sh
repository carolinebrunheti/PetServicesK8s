#!/usr/bin/env bash
# Instala a Azure CLI no Linux Mint 21.x (base Ubuntu 22.04 "jammy"),
# pelo metodo manual da documentacao da Microsoft.
set -euo pipefail

FINGERPRINT_ESPERADO="BC528686B50D79E339D3721CEB3E94ADBE1229CF"
CHAVE=/etc/apt/keyrings/microsoft.gpg

echo "1/5 baixando a chave publica da Microsoft..."
sudo mkdir -p /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee "$CHAVE" > /dev/null
sudo chmod go+r "$CHAVE"

echo "2/5 conferindo a chave..."
FINGERPRINT=$(gpg --show-keys --with-colons "$CHAVE" | awk -F: '/^fpr/ {print $10; exit}')
if [ "$FINGERPRINT" != "$FINGERPRINT_ESPERADO" ]; then
    echo "ERRO: a chave baixada nao e a esperada ($FINGERPRINT). Nada foi instalado."
    sudo rm -f "$CHAVE"
    exit 1
fi
echo "    chave confere: $FINGERPRINT"

echo "3/5 cadastrando o repositorio da Azure CLI..."
printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: jammy\nComponents: main\nArchitectures: amd64\nSigned-by: %s\n' "$CHAVE" \
    | sudo tee /etc/apt/sources.list.d/azure-cli.sources > /dev/null

echo "4/5 atualizando a lista de pacotes (erros do QGIS/Spotify podem ser ignorados)..."
sudo apt-get update || true

echo "5/5 instalando a Azure CLI..."
sudo apt-get install -y azure-cli

echo
az version
echo
echo "Pronto! Agora rode: az login"
