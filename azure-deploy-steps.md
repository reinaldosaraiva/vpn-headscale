# Headscale VPN Deployment Guide para VM Azure

Este guia fornece instruções para implantar o Headscale na VM Azure como uma solução simplificada para gerenciar VPN, permitindo acesso à rede interna 10.0.0.0/24 da Sysprime.

## Pré-requisitos

Certifique-se que sua VM Azure atende aos seguintes requisitos:

1. **Docker e Docker Compose**: Necessários para containerização
2. **Portas**: As seguintes portas precisam estar abertas:
   - 27896/TCP - API/serviço Headscale
   - 3000/TCP - Interface web Headplane
   - 41641/UDP - Tráfego WireGuard/Tailscale VPN

3. **Recursos do Sistema**:
   - Mínimo 2 núcleos de CPU
   - 4GB RAM
   - 20GB armazenamento

## 1. Preparação da VM

Conecte-se à sua VM Azure:

```bash
ssh -p 50822 azureuser@172.203.160.243
```

Atualize o sistema e instale o Docker:

```bash
# Atualize os pacotes do sistema
sudo apt update && sudo apt upgrade -y

# Instale os pacotes necessários
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Adicione a chave GPG oficial do Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# Adicione o repositório Docker
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Instale o Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Instale o Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Adicione seu usuário ao grupo docker para executar docker sem sudo
sudo usermod -aG docker $USER

# Aplique as alterações (pode ser necessário sair e entrar novamente)
newgrp docker
```

## 2. Estrutura de Diretórios

Crie a estrutura de diretórios necessária:

```bash
# Crie o diretório principal do projeto
mkdir -p ~/docker/headscale/{config,data}
```

## 3. Configuração do Headscale

Crie o arquivo de configuração do Headscale:

```bash
# Navegue até o diretório de configuração
cd ~/docker/headscale/config

# Crie o arquivo config.yaml
cat > config.yaml << 'EOF'
server_url: http://172.203.160.243:27896
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
    ipv4: 172.203.160.243
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
```

## 4. Configuração do Headplane

Crie o arquivo de configuração do Headplane:

```bash
# Crie headplane-config.yaml no diretório de configuração
cat > ~/docker/headscale/config/headplane-config.yaml << 'EOF'
headscale:
  url: "http://172.203.160.243:27896"
  config_strict: false
server:
  host: "0.0.0.0"
  port: 3000
  cookie_secret: "240f451d933dd370c5d7e311cd3d298b"
  cookie_secure: false
EOF
```

## 5. Configuração do Docker Compose

Crie o arquivo Docker Compose para o Headscale e Headplane:

```bash
# Crie o arquivo docker-compose.yml
cat > ~/docker/headscale/docker-compose.yml << 'EOF'
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
      COOKIE_SECRET: "240f451d933dd370c5d7e311cd3d298b"
      HEADSCALE_URL: "http://172.203.160.243:27896"
      CONFIG_FILE: "/etc/headscale/config.yaml"
      HEADSCALE_INTEGRATION: "docker"
      HEADSCALE_CONTAINER: "headscale"
      DISABLE_API_KEY_LOGIN: "true"
      HOST: "0.0.0.0"
      PORT: "3000"
      TZ: "America/Sao_Paulo"
      # ROOT_API_KEY será definido após gerarmos
EOF
```

## 6. Iniciar os Serviços

Inicie o Headscale primeiro para gerar a API key:

```bash
# Inicie o Headscale
cd ~/docker/headscale
docker compose up -d headscale

# Aguarde o Headscale inicializar
sleep 10

# Gere a API Key
API_KEY=$(docker exec -it headscale headscale apikeys create | grep -oP '(?<=key: ).+')
echo "Sua API Key é: $API_KEY"

# Atualize o docker-compose.yml com a API key
sed -i "s/# ROOT_API_KEY será definido após gerarmos/ROOT_API_KEY: \"$API_KEY\"/g" docker-compose.yml

# Inicie o Headplane
docker compose up -d headplane
```

## 7. Configuração Inicial do Headscale

Crie o namespace para acessar a rede Sysprime:

```bash
# Crie o namespace para a Sysprime
docker exec -it headscale headscale namespaces create sysprime

# Gere a chave de pré-autenticação para o namespace
docker exec -it headscale headscale preauthkeys create -e 720h sysprime
```

## 8. Configuração do Cliente Tailscale

Para cada cliente que precisa acessar a rede interna da Sysprime:

```bash
# Instale o cliente Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Conecte-se ao seu servidor Headscale 
sudo tailscale up --login-server http://172.203.160.243:27896 --authkey=SEU_AUTH_KEY
```

Para o gateway que dará acesso à rede interna 10.0.0.0/24:

```bash
# Instale o cliente Tailscale no servidor interno
curl -fsSL https://tailscale.com/install.sh | sh

# Conecte-se e anuncie a rede interna
sudo tailscale up --login-server http://172.203.160.243:27896 --authkey=SEU_AUTH_KEY --advertise-routes=10.0.0.0/24
```

## 9. Aprovação de Rotas

Após o gateway anunciar a rota 10.0.0.0/24, aprove-a no Headscale:

```bash
# Liste os nós para identificar o gateway
docker exec -it headscale headscale nodes list

# Aprove a rota anunciada (substitua MACHINE_ID pelo ID correto)
docker exec -it headscale headscale routes enable --route 10.0.0.0/24 MACHINE_ID 
```

## 10. Gerenciamento e Monitoramento

1. Acesse o Headplane em http://172.203.160.243:3000
2. A API key é configurada automaticamente
3. Use o Headplane para:
   - Gerenciar clientes
   - Aprovar anúncios de rotas
   - Configurar políticas de ACL
   - Monitorar conexões

## Solução de Problemas

- Verifique os logs do Headscale: `docker logs headscale`
- Verifique os logs do Headplane: `docker logs headplane`
- Verifique o status do serviço: `docker ps`
- Teste a conectividade: `tailscale ping <nome-da-máquina>`
- Verifique as rotas no cliente: `tailscale status`

## Considerações de Backup

Para fazer backup da sua implantação do Headscale:

```bash
# Backup de todo o diretório
tar -czvf headscale-backup.tar.gz ~/docker/headscale

# Ou apenas backup dos dados críticos
tar -czvf headscale-data-backup.tar.gz ~/docker/headscale/data
```

---
## Notas de Segurança Importantes

1. Atualize o cookie secret e gere uma API key forte
2. Considere implementar backups regulares
3. Mantenha as imagens Docker atualizadas regularmente
4. Se possível, restrinja o acesso à interface do Headplane a apenas IPs confiáveis

Este guia configura uma VPN centralizada que permite acesso à rede interna 10.0.0.0/24 da Sysprime através do Headscale como servidor de coordenação e clientes Tailscale em cada ponto de acesso.