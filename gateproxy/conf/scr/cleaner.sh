#!/bin/bash
# by maravento.com

# Cleaner

# Contribution:
# http://www.lagg3r.com.ar/buscar-y-eliminar-archivos-por-consola-bash/
# http://geekland.eu

################################################################################
# Nomenclatura:
# Comando find se le indica la ruta de búsqueda
# (.) representa al directorio actual, pero puede ser cualquiera.
# Opcion -type f para buscar archivos
# Opción -name (“”) va el nombre del archivo a buscar. Se admiten expresiones regulares, como (*)
# Opcion -exec rm -f {} \; para eliminar archivos
# Opcion -exec mv -f {} \; para mover archivos
# -----------------------------------------------------------------------------
# Example:
# Buscar y eliminar archivos con el comando find
# find . -type f -name "ARCHIVO-A-BUSCAR"-exec rm -f {} \;
# -----------------------------------------------------------------------------
# Buscar y eliminar archivos y directorios con el comando find
# find . -name "ARCHIVO-A-BUSCAR" -exec rm -rf {} \;
# -----------------------------------------------------------------------------
# Buscar archivos Thumbs.db en el directorio actual (.) y eliminarlos
# find . -type f -name "Thumbs.db" -exec rm -f {} \;
# -----------------------------------------------------------------------------
# Buscar archivos core en el sistema (/) y eliminarlos:
# find / -name core -exec rm -f {} \;
# -----------------------------------------------------------------------------
# Buscar archivos .bak en el directorio actual (.) y eliminarlos solicitando confirmación:
# find . -type f -name "*.bak" -exec rm -i {} \;
# -----------------------------------------------------------------------------
# Eliminar todos los archivos y conservar .mp3:
# find . ! -name "*.mp3" -exec rm -f {} \;
# -----------------------------------------------------------------------------
# Buscar archivos con extensión .xxx y copiarlos a otra carpeta.
# find /home/User/Carpeta/ -regextype posix-egrep -regex '^.*\.(png|jpg)$' -exec cp {} /Destino/ \;
# -----------------------------------------------------------------------------
# Buscar archivos con extensión .xxx y moverlos a otra carpeta.
# find /home/User/Carpeta/ -regextype posix-egrep -regex '^.*\.(png|jpg)$' -exec mv {} /Destino/ \;
# -----------------------------------------------------------------------------
# Mover archivos mp3 y mp4 masivamente de una carpeta a otra.
# find /home/$USER/compartida/ -regextype posix-egrep -regex '^.*\.(mp4|mp3)$' -exec mv {} /home/usuario/musica/ \;
# or
# find ~/compartida -type f ! -name "*.mp3" ! -name "*.aac" ! -name "*.wma" ! -name "*.flac" ! -name "*.wav" ! -name "*.ogg" -exec rm -f {}  \;
# -----------------------------------------------------------------------------
# Mover archivos.ext de un lugar a otro
# find directorio_origen -type f -name *.EXT -exec mv {} ./directorio_destino \;
# -----------------------------------------------------------------------------
# Para mover (o copiar, cambiar mv por cp):
# find /Directorio/ -iname "juno*" | xargs -i mv {}/Dirección donde se quiere mover/
# -----------------------------------------------------------------------------
# Para borrar
# find /Directorio -iname "archivo"-exec rm {} \;
# find / -iname "nombredelarchivo*" | xargs -i mv {} /destino
# find /ruta -iname "*referencia*" -type f -exec mv /destino {} \;
# -----------------------------------------------------------------------------
# Buscar y mover de forma recursiva
# find _origindir_ -type f -name ”_pattern_” -exec mv -v {} _outputdir_ ;
################################################################################

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi
# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

echo "Start Deep Cleaner..."

# Buscar y eliminar archivos ADS (Thumbs.db, Zone.identifier, encryptable, etc)
#find . -type f -name "Nombre_del_Archivo" -exec rm {} \;
find . -type f -regextype posix-egrep -iregex "^.*(:encryptable|Zone\.identifier|.fuse_hidden*|goutputstream*|.spotlight-*|.fseventsd*|.ds_store*|~lock.*|Thumbs\.db|attributes:).*$" -exec rm {} \; &>/dev/null

# Eliminar reportes antiguos de apport
rm -rf /var/crash/*crash &>/dev/null

# eliminar llenado kern/syslog
#cat /dev/null > /var/log/kern.log
#cat /dev/null > /var/log/syslog

# log registry
echo "Cleaner: $(date)" | tee -a /var/log/syslog
