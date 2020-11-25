#! /bin/bash
function validarParams(){
    [[ ! $# -eq 2 ]] && { echo "Tu número de parámetros no es el correcto"; modoUso; exit 1; }
    comprobar_ping $1
    validar_punto_montaje $2
}

function comprobar_ping(){
    echo '-->Comprobando conectividad'
    ping -c 1 $1 > /dev/null
    validacion $(echo $?)
}

function modoUso(){
    echo 'Para ejecutar el script: manager.sh IP-MANAGER PUNTO-MONTAJE'
    echo 'Ejemplo: ./manager.sh 192.168.1.1 /dev/sda1'
}

function validar_punto_montaje(){
    echo '-->Comprobando punto de montaje'
    fdisk -l | grep -w $1
    validacion $(echo $?)
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
    validacion $(echo $?)
}

function validar_docker(){
    docker --version > /dev/null
    validacion $(echo $?)
}

function validar_os(){
    hostnamectl | grep -w Arch
    validacion $(echo $?)
}

function permitir_root_login(){
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
}

function iniciar_swarm(){
    docker swarm init --advertise-addr $1 | grep "docker swarm join --token" | sed "s/    //" > /root/.key_swarm
}

# shellcheck disable=SC2068
validarParams $@
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
iniciar_swarm $1
echo 'INFO: ya puedes unir los nodos a este swarm'
