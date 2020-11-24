#! /bin/bash

function install_xfsprogs(){
        echo "-->Instalando el paquete xfsprogs desde pacman..."
        pacman -Sy xfsprogs
        echo "-->Configurando el disco o particion ingresada..."
        mkfs.xfs -f -i size=2048 $1
        echo "-->Ingresando la particion en fstab.."
        echo '$1 /mnt/osd xfs rw,noatime,inode64 0 0' >> /etc/fstab
        echo "-->Creando carpetas en /mnt ..."
        existe_directorio "/mnt/osd"
        mkdir -p /mnt/osd && mount /mnt/osd
}

function existe_directorio(){
        if [ -d $1 ]; then
                echo "-->Error el directorio ya existe: $1";
        fi
}

function existe_archivo(){
        if [ -f $1 ]; then
                echo "-->El $1 existe";
        else
                echo "-->ERROR no esta el archivo...";
                exit 1;
        fi
}

function obtener_llaves_ceph(){
        echo "-->Obteniendo llaves ceph..."
        docker run -d --rm --net=host \
                --name ceph_mon \
                -v `pwd`/etc:/etc/ceph \
                -v `pwd`/var:/var/lib/ceph \
                -e NETWORK_AUTO_DETECT=4 \
                -e DEBUG=verbose \
                ceph/daemon:master-13b097c-mimic-centos-7-x86_64 mon

        docker exec -it ceph_mon ceph mon getmap -o /etc/ceph/ceph.monmap
        existe_archivo "var/bootstrap-osd/ceph.keyring"
        echo "-->Deteniendo la imagen de ceph"
        docker stop ceph_mon
}

function generando_llaves_swarm(){
        echo "-->Generando configuraciones swarm"
        docker config create ceph.conf etc/ceph.conf
        docker secret create ceph.monmap etc/ceph.monmap
        docker secret create ceph.client.admin.keyring etc/ceph.client.admin.keyring
        docker secret create ceph.mon.keyring etc/ceph.mon.keyring
        docker secret create ceph.bootstrap-osd.keyring var/bootstrap-osd/ceph.keyring
        echo "-->Mostrando configuraciones de swarm"
        docker config ls
        echo "-->Mostrando llaves de swarm"
        docker secret ls
        sleep 5
}

function desplegando_ceph_swarm(){
        docker stack deploy -c docker-compose.yml ceph
}

function comprobar_salud_ceph(){
        HEALTH='NULL'
        while [ $HEALTH != 'HEALTH_OK' ]; do
                HEALTH=$(docker exec -i `docker ps -qf name=ceph_mon` ceph -s | grep "health" | awk -F: '{print $2}')
                echo "-->En espera..."
                sleep 15
        done
        echo "-->Ceph marca ok"
}

function comprobar_osd(){
        OSD='NULL'
        while [ $OSD != '3' ]; do
                OSD=$(docker exec -i `docker ps -qf name=ceph_mon` ceph -s | grep "osd:" | cut -d: -f 2 | cut -c 2)
                echo "-->En espera de los OSD"
                sleep 25
        done
        echo "-->OSD listos"
}

function configuracion_ceph(){
        echo "-->Configurando contenedor ceph..."
        docker exec -i `docker ps -qf name=ceph_mon` ceph osd pool create cephfs_data 64
        docker exec -i `docker ps -qf name=ceph_mon` ceph osd pool create cephfs_metadata 64
        docker exec -i `docker ps -qf name=ceph_mon` ceph fs new cephfs cephfs_metadata cephfs_data
        docker exec -i `docker ps -qf name=ceph_mon` ceph fs authorize cephfs client.swarm / rw | grep "key" | cut -d= -f2 > /root/.llave_ceph
        sleep 10
        sed 's/ //' /root/.llave_ceph > /root/.ceph; rm /root/.llave_ceph
        docker exec -i `docker ps -qf name=ceph_mon` ceph osd pool set cephfs_data nodeep-scrub 1
}

function instalando_ceph(){
        pacman -S ceph
        echo '$1:/ /mnt/ceph ceph _netdev,name=swarm,secretfile=/root/.ceph 0 0' >> /etc/fstab
}

function crear_carpeta_ceph(){
        existe_directorio "/mnt/ceph"
        mkdir /mnt/ceph && mount /mnt/ceph
}


install_xfsprogs $2
obtener_llaves_ceph
echo "-->Es correcto el contenido de este archivo?"
sleep 5
nano etc/ceph.conf
generando_llaves_swarm
echo "-->limpiando..."
rm -r ./var ./etc
sleep 2
desplegando_ceph_swarm
sleep 30
echo "-->Comprobando salud de ceph"
comprobar_salud_ceph
comprobar_osd
configuracion_ceph
instalando_ceph $1
crear_carpeta_ceph
echo "-->listo"
