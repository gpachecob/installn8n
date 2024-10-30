#!/bin/bash
# Instalador do N8N em fila no Docker Swarm
# Autor: Maicon Ramos - Automação sem Limites
# Versao: 0.1

SSL_EMAIL=$1
DOMINIO_N8N=$2
DOMINIO_PORTAINER=$3
WEBHOOK_N8N=$4

echo "Iniciando instalação.."

N8N_KEY=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -base64 12)

echo "SSL_EMAIL=$SSL_EMAIL" > .env
echo "DOMINIO_N8N=$DOMINIO_N8N" >> .env
echo "WEBHOOK_N8N=$WEBHOOK_N8N" >> .env
echo "DOMINIO_PORTAINER=$DOMINIO_PORTAINER" >> .env
echo "N8N_KEY=$N8N_KEY" >> .env
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env

#evitar interação
export DEBIAN_FRONTEND=noninteractive

#ajustar fuso horário
sudo timedatectl set-timezone America/Sao_Paulo

echo "Instalando vários pacotes necessários, dependendo do servidor pode demorar um pouco"
{
    DEBIAN_FRONTEND=noninteractive apt update -y &&
    DEBIAN_FRONTEND=noninteractive apt upgrade -y &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils &&
    DEBIAN_FRONTEND=noninteractive sudo apt install -y curl &&
    DEBIAN_FRONTEND=noninteractive sudo apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2
} >> instalacao_n8n.log 2>&1 &
wait

echo "Lista de Pacotes atualizados"
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    sleep 10
done

echo "Alocando um arquivo de swap "
# Aloca um arquivo de swap
sudo fallocate -l 4G /swapfile >> instalacao_n8n.log 2>&1
sudo chmod 600 /swapfile >> instalacao_n8n.log 2>&1
sudo mkswap /swapfile >> instalacao_n8n.log 2>&1
sudo swapon /swapfile >> instalacao_n8n.log 2>&1
sudo cp /etc/fstab /etc/fstab.bak >> instalacao_n8n.log 2>&1
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >> instalacao_n8n.log 2>&1
echo "Swap alocado!"

echo "Atualizando nome do Servidor"

# Novo hostname que será configurado
novo_hostname="manager1"
# Alterar o arquivo /etc/hosts para atualizar o hostname
sudo sed -i "s/127.0.0.1.*/127.0.0.1 $novo_hostname/" /etc/hosts
# Atualizar o hostname da máquina
sudo hostnamectl set-hostname $novo_hostname

while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    sleep 10
done
echo "Instalando o Docker..."
# Instalar o Docker
curl -fsSL https://get.docker.com | bash >> instalacao_n8n.log 2>&1 && echo "Docker instalado com sucesso!"

while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    sleep 10
done
sudo usermod -aG docker $USER

echo "Configurando o Docker Swarm"

# Identificar a interface de rede principal
interface=$(ip -o -4 route show to default | awk '{print $5}')
endereco_ip=$(ip -o -4 addr show "$interface" | awk '{split($4, a, "/"); print a[1]}' | head -n 1)

# Verificar se o endereço IP foi obtido corretamente
if [[ -z $endereco_ip ]]; then
    echo "Não foi possível obter o endereço IP da interface $interface."
    exit 1
fi

# Iniciar o Swarm usando o endereço IP obtido
docker swarm init --advertise-addr $endereco_ip >> instalacao_n8n.log 2>&1 && echo "Docker Swarm iniciado"
# Configurar a rede do Docker Swarm
docker network create --driver=overlay network_public >> instalacao_n8n.log 2>&1 && echo "Rede Swarm Criada com sucesso!"

# Stack do Traefik
echo "Configurando o Traefik com o e-mail $SSL_EMAIL"
curl -sSL "https://instalador.automacaosemlimites.com.br/arquivos/instalador/stack/traefik.yaml" -o "traefik.yaml"
env SSL_EMAIL="$SSL_EMAIL" docker stack deploy --prune --resolve-image always -c traefik.yaml traefik >> instalacao_n8n.log 2>&1 && echo "Traefik instalado com sucesso!"

# Stack do Portainer
echo "Configurando o Portainer com o domínio $DOMINIO_PORTAINER"
curl -sSL "https://instalador.automacaosemlimites.com.br/arquivos/instalador/stack/portainer.yaml" -o "portainer.yaml"
env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy --prune --resolve-image always -c portainer.yaml portainer >> instalacao_n8n.log 2>&1 && echo "Portainer instalado com sucesso!"

# Stack do Postgres
echo "Configurando o Banco de Dados Postgres"
curl -sSL "https://instalador.automacaosemlimites.com.br/arquivos/instalador/stack/postgres.yaml" -o "postgres.yaml"
env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy --prune --resolve-image always -c postgres.yaml postgres >> instalacao_n8n.log 2>&1 && echo "Postgres instalado com sucesso!"

# Stack do Redis
echo "Configurando o Redis"
curl -sSL "https://instalador.automacaosemlimites.com.br/arquivos/instalador/stack/redis.yaml" -o "redis.yaml"
docker stack deploy --prune --resolve-image always -c redis.yaml redis >> instalacao_n8n.log 2>&1 && echo "Redis instalado com sucesso!"

# Stack do n8n
echo "Criando o Banco de Dados do n8n"
sleep 40
postgres_container_name=$(docker ps --filter "name=postgres_postgres" --format "{{.Names}}")
docker exec $postgres_container_name psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null >> instalacao_n8n.log 2>&1 && echo "Banco n8n criado com sucesso!"
echo "Configurando o o n8n com domínio $DOMINIO_N8N e webhook $WEBHOOK_N8N"
curl -sSL "https://instalador.automacaosemlimites.com.br/arquivos/instalador/stack/n8n.yaml" -o "n8n.yaml"
env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy --prune --resolve-image always -c n8n.yaml n8n >> instalacao_n8n.log 2>&1 && echo "n8n instalado com sucesso!"

echo "Instalação concluída"
echo "Feche essa janela do terminal e acesse o endereço do portainer e depois do n8n"
