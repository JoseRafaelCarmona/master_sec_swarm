#! /bin/bash

function modoUso(){
    echo 'Para ejecutar el script: manager.sh IP-MANAGER PUNTO-MONTAJE INTERFACE-KEEPALIVED IP-FUTURO-NODO'
    echo 'Ejemplo: ./manager.sh /dev/sda1 ensp03'
}

function validarParams(){
    [[ ! $# -eq 2 ]] && { echo -e "\e[31mTu número de parámetros no es el correcto\e[0m"; modoUso; exit 1; }
    validar_punto_montaje $1
    validar_interface $2
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
        echo -e "\e[32m       OK\e[0m";
    else
        echo -e "\e[31mDebes ser el usuario root para realizar esto\e[0m";
        exit 1;
    fi
}

function validacion(){
    if [ $1 != "0" ]; then
        echo -e "\e[31m       Mal\e[0m";
        exit 1;
    fi
    echo -e "\e[32m       OK\e[0m";
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

function iniciar_redsuperpuesta(){
  echo "--> Creado red"
  docker network create --driver=overlay --attachable --subnet=172.16.200.0/24 traefik_public
  echo -e "\e[37m       Listo\e[0m";
}

function install_keepalived(){
         docker run -d --name keepalived --restart=always \
              --cap-add=NET_ADMIN --cap-add=NET_BROADCAST --cap-add=NET_RAW --net=host \
              -e KEEPALIVED_INTERFACE=$4 \
              -e KEEPALIVED_UNICAST_PEERS="#PYTHON2BASH:[$1,$2]" \
              -e KEEPALIVED_VIRTUAL_IPS=$3 \
              -e KEEPALIVED_PRIORITY=200 \
              osixia/keepalived
}

function keepalived(){
        echo '--> Ingresa la direccion virtual:'
        read IP_VIRTUAL
        echo $IP_VIRTUAL > /root/.ip_virtual
        echo $2 > /root/.ip_nodo
        install_keepalived $1 $2 $IP_VIRTUAL $3
}

function comprobaciones(){
        validarParams "$@"
        echo '-->Comprobando si eres usuario root:'
        usuario_root
        echo '-->Comprobando sistema operativo'
        validar_os
        echo '-->Acceso a internet'
        acceso_internet
        echo '-->Comprobando docker'
        validar_docker
}

function instalacion_ceph(){
        echo 'Iniciando la instalacion de ceph..'
        chmod +x ceph/install_ceph.sh
        chmod -R +x ceph/
        cd ceph/ && bash ./install_ceph.sh "$1" "$2"
}

function instalacion_traefik(){
        echo  '---> Creando red superpuesta';
        iniciar_redsuperpuesta;
        echo '--> Creando traefik';
        chmod +x ../traefik/install_traefik.sh;
        cd ../traefik/ && ./install_traefik.sh;
}

function ips_keepalived(){
        echo '->¿Que IP quiere que sea el respaldo del contenedor de keepalived?';
        echo '->el respaldo funciona si el nodo que tiene el contenedor cae, este nodo';
        echo '->obtiene la dirección IP virtual';
        echo '1.-$2 o 2.-$3';
        read $respuesta;
        if [[ $respuesta > 0 ]] && [[ $respuesta < 3 ]]; then
            if [[ $respuesta == 1 ]]; then
                keepalived "$1" "$2" "$4";
                echo "$2" > /root/.configsCluster/nodo_backup_keepalived
            else
                if [[ $respuesta == 2 ]]; then
                    keepalived "$1" "$3" "$4";
                    echo "$3" > /root/.configsCluster/nodo_backup_keepalived
                else
                    ips_keepalived $1 $2 $3 $4;
                fi
            fi
        fi
}

function main(){
        comprobaciones $1 $2;
        punto_montaje=$1
        interface=$2

        #aqui falta para validar las direcciones IP
        echo 'Ingrese las 3 IPS que estaran en el cluster';
        echo '###########################################';
        echo '->IP nodo master:';
        read ip_master;
        echo '->IP nodo 1';
        read ip_nodo1;
        echo '->IP nodo 2';
        read ip_nodo2;
        #--------------------------------
        mkdir /root/.configsCluster
        echo "$ip_master" > /root/.configsCluster/ips_cluster
        echo "$ip_nodo1" >> /root/.configsCluster/ips_cluster
        echo "$ip_nodo3" >> /root/.configsCluster/ips_cluster

        echo '-->Permitir login ssh root';
        permitir_root_login;
        echo '-->Obteniendo llave swarm';
        iniciar_swarm "$ip_master";
        echo -e "\e[93m INFO: ya puedes unir los nodos a este swarm\e[0m";
        instalacion_ceph $ip_master $punto_montaje;
        instalacion_traefik;
        echo '---> Creando el contenedor de keepalived';
        ips_keepalived $ip_master $ip_nodo1 $ip_nodo2 $interface
        docker service update --replicas-max-per-node=1 ceph_mds
}

main $1 $2






