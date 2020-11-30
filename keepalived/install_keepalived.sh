#!/bin/bash

#Este script recibira la ip virtual, las direcciones ip de los nodos y el nombre de la interfaz
# $1 = direccion IP del manager
# $IP_NODO1 direccion del primer nodo
# $IP_NODO2 = direccion del segundo nodo
# $4 = IP virtual
# $5 = nombre de la interfaz de red

function validar(){
        if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                [[ ${$1[0]} -le 255 && ${$1[1]} -le 255 ${$1[2]} -le 255 && ${$1[3]} -le 255 ]]
                if [ $? != '0' ]; then
                        echo 'mal'
                        exit 1;
                fi
        fi
        echo 'OK'
}

function install_keepalived(){
         docker run -d --name keepalived --restart=always \
              --cap-add=NET_ADMIN --cap-add=NET_BROADCAST --cap-add=NET_RAW --net=host \
              -e KEEPALIVED_INTERFACE=$5 \
              -e KEEPALIVED_UNICAST_PEERS="#PYTHON2BASH:[$1,$2,$3]" \
              -e KEEPALIVED_VIRTUAL_IPS=$4 \
              -e KEEPALIVED_PRIORITY=200 \
              osixia/keepalived
}

echo '--> Ingrese la direccion IP de un nodo'
read IP_NODO1
validar $IP_NODO1
echo '--> Ingrese la direccion IP del segundo nodo'
read IP_NODO2
validar $IP_NODO2