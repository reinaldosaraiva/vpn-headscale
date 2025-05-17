#!/bin/bash

# Script de configuração para clientes Tailscale
# Conecta à rede VPN Headscale para acesso à rede Sysprime

set -e

# Cores para saídas
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Sem cor

# Função para exibir mensagens
log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
  echo -e "${RED}[ERRO]${NC} $1"
  exit 1
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
  error "Este script precisa ser executado como root (use sudo)"
fi

# Solicitar informações necessárias
read -p "Digite o IP do servidor Headscale: " SERVER_IP
read -p "Digite a chave de autenticação (auth key): " AUTH_KEY
read -p "Este cliente irá anunciar rotas para a rede 10.0.0.0/24? (s/n): " ANNOUNCE_ROUTES

# Instalar Tailscale
log "Instalando Tailscale..."
if ! command -v tailscale &> /dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  log "Tailscale já está instalado."
fi

# Conectar ao Headscale
log "Conectando ao servidor Headscale..."
if [[ $ANNOUNCE_ROUTES == "s" || $ANNOUNCE_ROUTES == "S" ]]; then
  log "Configurando como gateway para rede 10.0.0.0/24..."
  tailscale up --login-server http://${SERVER_IP}:27896 --authkey=${AUTH_KEY} --advertise-routes=10.0.0.0/24
  
  # Habilitar IP forwarding
  log "Habilitando IP forwarding..."
  echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-tailscale.conf
  sysctl -p /etc/sysctl.d/99-tailscale.conf
  
  log "IMPORTANTE: Lembre-se de aprovar a rota no painel Headplane ou com o comando:"
  log "docker exec -it headscale headscale routes list"
  log "docker exec -it headscale headscale routes enable --route 10.0.0.0/24 MACHINE_ID"
else
  log "Configurando como cliente normal..."
  tailscale up --login-server http://${SERVER_IP}:27896 --authkey=${AUTH_KEY}
fi

# Verificar status da conexão
log "Verificando status da conexão..."
tailscale status

# Exibir informações adicionais
log "==================================================================="
log "Cliente Tailscale configurado com sucesso!"
log ""
log "Para verificar o status a qualquer momento, execute:"
log "tailscale status"
log ""
log "Para desconectar da VPN:"
log "tailscale down"
log ""
log "Para reconectar à VPN:"
log "tailscale up"
log "==================================================================="