#!/bin/bash

# Headscale deployment script for Azure VM
# Para rede Sysprime 10.0.0.0/24

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

# Configurações
HEADSCALE_DIR="/root/docker/headscale"
SERVER_IP=$(curl -s https://ipinfo.io/ip)

log "Iniciando instalação do Headscale para gerenciamento de VPN"
log "Usando IP do servidor: $SERVER_IP"

# Atualizar o sistema
log "Atualizando o sistema..."
apt update -qq && apt upgrade -y -qq

# Instalar dependências
log "Instalando dependências..."
apt install -y -qq apt-transport-https ca-certificates curl software-properties-common gnupg2

# Instalar Docker
log "Instalando Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt update -qq
  apt install -y -qq docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
else
  log "Docker já está instalado."
fi

# Instalar Docker Compose
log "Instalando Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
  curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
  log "Docker Compose já está instalado."
fi

# Criar estrutura de diretórios
log "Criando diretórios para Headscale..."
mkdir -p $HEADSCALE_DIR/{config,data}

# Gerar um cookie secret aleatório
COOKIE_SECRET=$(openssl rand -hex 16)
log "Cookie secret gerado: $COOKIE_SECRET"

# Criar arquivo de configuração do Headscale
log "Criando arquivo de configuração do Headscale..."
cat > $HEADSCALE_DIR/config/config.yaml << EOF
server_url: http://${SERVER_IP}:27896
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: false
noise:
  private_key_path: /var/lib/headscale/noise_private.key
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential
derp:
  server:
    enabled: false
    region_id: 999
    region_code: "headscale"
    region_name: "Headscale Embedded DERP"
    stun_listen_addr: "0.0.0.0:3478"
    private_key_path: /var/lib/headscale/derp_server_private.key
    automatically_add_embedded_derp_region: true
    ipv4: ${SERVER_IP}
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  paths: []
  auto_update_enabled: true
  update_frequency: 24h
disable_check_updates: false
ephemeral_node_inactivity_timeout: 30m
database:
  type: sqlite
  debug: false
  gorm:
    prepare_stmt: true
    parameterized_queries: true
    skip_err_record_not_found: true
    slow_threshold: 1000
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true
    wal_autocheckpoint: 1000
log:
  format: text
  level: debug
policy:
  mode: database
dns:
  magic_dns: false
  base_domain: sysprime.local
  nameservers:
    global:
      - 1.1.1.1
      - 1.0.0.1
unix_socket: /var/run/headscale/headscale.sock
unix_socket_permission: "0770"
logtail:
  enabled: false
randomize_client_port: false
EOF

# Criar arquivo de configuração do Headplane
log "Criando arquivo de configuração do Headplane..."
cat > $HEADSCALE_DIR/config/headplane-config.yaml << EOF
headscale:
  url: "http://${SERVER_IP}:27896"
  config_strict: false
server:
  host: "0.0.0.0"
  port: 3000
  cookie_secret: "${COOKIE_SECRET}"
  cookie_secure: false
EOF

# Criar arquivo de política ACL
log "Criando arquivo de política ACL..."
cat > $HEADSCALE_DIR/config/acl.json << EOF
{
  // ACL policy for Headscale - Sysprime Network Access
  // This defines which nodes can communicate with the Sysprime internal network
  "acls": [
    // Allow all users in the sysprime namespace to access internal network
    {
      "action": "accept",
      "src": ["sysprime:*"],
      "dst": ["sysprime:*:*"]
    },
    // Allow access to Sysprime internal resources
    {
      "action": "accept",
      "src": ["sysprime:*"],
      "dst": ["10.0.0.0/24:*"]
    }
  ],
  
  // Auto-approvers for the gateway route
  "autoApprovers": {
    // Automatically approve the 10.0.0.0/24 route from the gateway
    "routes": {
      "sysprime:gateway-sysprime": ["10.0.0.0/24"]
    }
  }
}
EOF

# Criar docker-compose.yml
log "Criando arquivo docker-compose.yml..."
cat > $HEADSCALE_DIR/docker-compose.yml << EOF
services:
  headscale:
    container_name: headscale
    image: headscale/headscale:latest-debug
    volumes:
      - ./config:/etc/headscale/
      - ./data:/var/lib/headscale
    ports:
      - "27896:8080"
    command: "serve"
    restart: unless-stopped
    environment:
      - TZ=America/Sao_Paulo

  headplane:
    container_name: headplane
    image: ghcr.io/tale/headplane:latest
    restart: unless-stopped
    volumes:
      - ./config:/etc/headscale
      - ./data:/var/lib/headscale
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config/headplane-config.yaml:/etc/headplane/config.yaml
    ports:
      - "3000:3000"
    environment:
      COOKIE_SECRET: "${COOKIE_SECRET}"
      HEADSCALE_URL: "http://${SERVER_IP}:27896"
      CONFIG_FILE: "/etc/headscale/config.yaml"
      HEADSCALE_INTEGRATION: "docker"
      HEADSCALE_CONTAINER: "headscale"
      DISABLE_API_KEY_LOGIN: "true"
      HOST: "0.0.0.0"
      PORT: "3000"
      TZ: "America/Sao_Paulo"
      # ROOT_API_KEY será definido após gerarmos
EOF

# Iniciar Headscale
log "Iniciando contêiner do Headscale..."
cd $HEADSCALE_DIR
docker-compose up -d headscale

# Esperar Headscale inicializar
log "Aguardando inicialização do Headscale..."
sleep 10

# Aplicar política ACL
log "Aplicando política de ACL..."
docker exec -it headscale headscale apply-policies --file /etc/headscale/acl.json

# Criar namespace sysprime
log "Criando namespace sysprime..."
docker exec -it headscale headscale namespaces create sysprime

# Gerar API Key
log "Gerando API Key para Headplane..."
API_KEY=$(docker exec -it headscale headscale apikeys create | grep -oP '(?<=key: ).+')
log "API Key gerada: $API_KEY"

# Atualizar docker-compose.yml com a API key
log "Atualizando docker-compose.yml com a API Key..."
sed -i "s/# ROOT_API_KEY será definido após gerarmos/ROOT_API_KEY: \"$API_KEY\"/g" $HEADSCALE_DIR/docker-compose.yml

# Criar chave de pré-autenticação
log "Gerando chave de pré-autenticação para sysprime (válida por 30 dias)..."
PRE_AUTH_KEY=$(docker exec -it headscale headscale preauthkeys create -e 720h sysprime | grep -oP '(?<=key: ).+')
log "Chave de pré-autenticação gerada: $PRE_AUTH_KEY"

# Iniciar Headplane
log "Iniciando contêiner do Headplane..."
docker-compose up -d headplane

# Verificar status dos contêineres
log "Verificando status dos contêineres..."
docker ps

# Exibir informações de acesso
log "==================================================================="
log "Headscale foi instalado com sucesso!"
log "Acesse o Headplane em: http://${SERVER_IP}:3000"
log ""
log "API Key para Headplane: ${API_KEY}"
log ""
log "Utilize a seguinte chave de pré-autenticação para conectar clientes:"
log "Namespace: sysprime"
log "Pre-auth key: ${PRE_AUTH_KEY}"
log ""
log "Para conectar um cliente:"
log "tailscale up --login-server http://${SERVER_IP}:27896 --authkey=${PRE_AUTH_KEY}"
log ""
log "Para anunciar a rede 10.0.0.0/24:"
log "tailscale up --login-server http://${SERVER_IP}:27896 --authkey=${PRE_AUTH_KEY} --advertise-routes=10.0.0.0/24"
log "==================================================================="