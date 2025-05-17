# Headscale VPN para Acesso à Rede Sysprime

Este repositório contém scripts e instruções para implantar o Headscale como uma solução VPN para gerenciar o acesso à rede interna Sysprime (10.0.0.0/24).

## O que é Headscale?

Headscale é uma implementação open-source e self-hosted do protocolo de coordenação do Tailscale, permitindo criar e gerenciar uma VPN mesh baseada em WireGuard sem depender dos servidores da Tailscale.

## Componentes

- **Headscale**: Servidor de coordenação da VPN
- **Headplane**: Interface web para gerenciar o Headscale
- **Tailscale Client**: Agente que roda nos nós para formar a VPN mesh

## Requisitos

- VM Linux (testado no Ubuntu na Azure)
- Docker e Docker Compose
- Portas abertas:
  - 27896/TCP - API/serviço Headscale 
  - 3000/TCP - Interface web Headplane
  - 41641/UDP - Tráfego WireGuard/Tailscale VPN

## Instalação Rápida

### Método 1: Script Automatizado

Faça o upload do script `install.sh` para a VM e execute:

```bash
# Dê permissão de execução ao script
chmod +x install.sh

# Execute como root
sudo ./install.sh
```

O script irá:
1. Instalar o Docker e o Docker Compose
2. Configurar o Headscale e o Headplane
3. Criar o namespace "sysprime"
4. Gerar uma chave de pré-autenticação
5. Exibir as informações de acesso e configuração

### Método 2: Instalação Manual

Consulte o arquivo `azure-deploy-steps.md` para instruções detalhadas de instalação manual.

## Configuração de Clientes

Use o script `client-setup.sh` para configurar os clientes Tailscale:

```bash
# Dê permissão de execução ao script
chmod +x client-setup.sh

# Execute como root
sudo ./client-setup.sh
```

O script irá solicitar:
- IP do servidor Headscale
- Chave de autenticação
- Se deseja anunciar a rota para a rede 10.0.0.0/24 (para gateway)

## Estrutura de Arquivos

```
.
├── README.md                           # Este arquivo
├── azure-deploy-steps.md               # Guia detalhado de implantação
├── acl-sysprime.json                   # Arquivo de política ACL
├── install.sh                          # Script de instalação automatizada
├── client-setup.sh                     # Script para configuração de clientes
└── config-templates/                   # Templates de arquivos de configuração
    ├── config.yaml.template            # Template de configuração do Headscale
    ├── headplane-config.yaml.template  # Template de configuração do Headplane
    ├── docker-compose.yml.template     # Template do Docker Compose
    └── acl.json.template               # Template do arquivo ACL
```

## Arquitetura

```
                      +----------------+
                      |   Headscale    |
                      | (Servidor VPN) |
                      +-------+--------+
                              |
                              | Gerencia
                              |
                      +-------v--------+
                      |   Headplane    |
                      |  (Interface)   |
                      +----------------+
                              |
                 +------------+-------------+
                 |                          |
        +--------v------+         +---------v-------+
        | Cliente VPN 1 |         | Gateway VPN     |
        |               |         | (anuncia rota)  |
        +---------------+         +---------+-------+
                                            |
                                  +---------v-------+
                                  | Rede Sysprime   |
                                  |  10.0.0.0/24    |
                                  +-----------------+
```

## Gerenciamento

Acesse o painel do Headplane em http://SEU_IP_SERVIDOR:3000 para:

- Visualizar e gerenciar nós conectados
- Aprovar rotas anunciadas
- Gerenciar namespaces e chaves

## Comandos Úteis

### Headscale (dentro do contêiner)

```bash
# Listar todos os nós
docker exec -it headscale headscale nodes list

# Listar rotas anunciadas
docker exec -it headscale headscale routes list

# Aprovar uma rota anunciada
docker exec -it headscale headscale routes enable --route 10.0.0.0/24 MACHINE_ID

# Criar uma nova chave de pré-autenticação (válida por 30 dias)
docker exec -it headscale headscale preauthkeys create -e 720h sysprime
```

### Tailscale (nos clientes)

```bash
# Verificar status da conexão
tailscale status

# Verificar rotas disponíveis
tailscale netcheck

# Desconectar da VPN
tailscale down

# Reconectar à VPN
tailscale up
```

## Backup

Para fazer backup da instalação do Headscale:

```bash
# Backup completo
tar -czvf headscale-backup.tar.gz ~/docker/headscale

# Apenas dados críticos
tar -czvf headscale-data-backup.tar.gz ~/docker/headscale/data
```

## Solução de Problemas

- **Erro de conexão ao servidor**: Verifique se as portas 27896 e 41641 estão abertas no firewall.
- **Nós não se comunicam**: Verifique a política ACL e se as rotas foram aprovadas.
- **Gateway não anuncia rota**: Certifique-se de que o IP forwarding está habilitado.

## Referências

- [Documentação oficial do Headscale](https://github.com/juanfont/headscale)
- [Documentação do Tailscale](https://tailscale.com/kb/)
- [Headplane GitHub](https://github.com/tale/headplane)