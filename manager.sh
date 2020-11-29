#! /bin/bash

function modoUso(){
    echo 'Para ejecutar el script: manager.sh IP-MANAGER PUNTO-MONTAJE'
    echo 'Ejemplo: ./manager.sh 192.168.1.1 /dev/sda1'
}

function validarParams(){
    [[ ! $# -eq 4 ]] && { echo "Tu número de parámetros no es el correcto"; modoUso; exit 1; }
    comprobar_ping $1
    validar_punto_montaje $2
    validar_interface $3
}

function comprobar_ping(){
    echo '-->Comprobando conectividad'
    ping -c 1 $1 > /dev/null
    validacion "$(echo $?)"
}

function validar_interface(){
  ip add | grep -wom 1 $1
  validacion "$(echo $?)"
}

function validar_punto_montaje(){
    echo '-->Comprobando punto de montaje'
    fdisk -l | grep -w $1
    validacion "$(echo $?)"
}

function usuario_root(){
    if [ $EUID -eq 0 ]; then
        echo '   OK'
    else
        echo '-->Debes ser el usuario root para realizar esto';
        exit 1;
    fi
}

function validacion(){
    if [ $1 != "0" ]; then
        echo "-->Mal";
        exit 1;
    fi
    echo '   OK'
}

function acceso_internet(){
    curl www.google.com >/dev/null 2>&1
    validacion "$(echo $?)"
}

function validar_docker(){
    docker --version > /dev/null
    validacion "$(echo $?)"
}

function validar_os(){
    hostnamectl | grep -w Arch
    validacion "$(echo $?)"
}

function permitir_root_login(){
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
}

function iniciar_swarm(){
    docker swarm init --advertise-addr $1 | grep "docker swarm join --token" | sed "s/    //" > /root/.key_swarm
}

function iniciar_keepalived(){
    echo "--> Creando contenedor..."
    docker run -d --name keepalived --restart=always \
    --cap-add=NET_ADMIN --cap-add=NET_BROADCAST --cap-add=NET_RAW --net=host \
    -e KEEPALIVED_INTERFACE=$2 \
    -e KEEPALIVED_UNICAST_PEERS="#PYTHON2BASH:[$1, $3]" \
    -e KEEPALIVED_VIRTUAL_IPS=192.168.16.200 \
    -e KEEPALIVED_PRIORITY=200 \
    osixia/keepalived
    echo "--> keepalived listo"
}

function iniciar_redsuperpuesta(){
  echo "--> Creado red"
  docker network create --driver=overlay --attachable --subnet=172.16.200.0/24 traefik_public
  echo "--> listo"
}

validarParams "$@"
ip_master=$1
punto_montaje=$2
interface=$3
ip_future_worker=$4

echo '-->Comprobando si eres usuario root:'
usuario_root
echo '-->Comprobando sistema operativo'
validar_os
echo '-->Acceso a internet'
acceso_internet
echo '-->Comprobando docker'
validar_docker
echo '-->Permitir login ssh root'
permitir_root_login
echo '-->Obteniendo llave swarm'
iniciar_swarm "$ip_master"
echo 'INFO: ya puedes unir los nodos a este swarm'
echo 'Iniciando la instalacion de ceph..'
chmod +x ceph/install_ceph.sh
chmod -R +x ceph/
cd ceph/ && bash ./install_ceph.sh "$ip_master" "$punto_montaje"
echo '---> Creando el contenedor de keepalived'
iniciar_keepalived "$ip_master" "$interface" "$ip_future_worker"
echo  '---> Creando red superpuesta'
iniciar_redsuperpuesta