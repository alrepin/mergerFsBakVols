#!/bin/bash
configFile="$(dirname "$0")/$(basename "$0" .sh).conf"
version=0.0.1
declare -A params_key_value

function interact() {
    echo "$(basename "$0") ($version) - "
    about
    usage
    checkReturn=$(checkPossibilities)
    targetLetter=$(echo "${checkReturn}" | cut -f 1 -d ":")
    srcDevice=$(echo "${checkReturn}" | cut -f 2 -d ":")
    srcPath=$(echo "${checkReturn}" | cut -f 3 -d ":")
    targetDevice=$(echo "${checkReturn}" | cut -f 4 -d ":")
    targetPath=$(echo "${checkReturn}" | cut -f 5 -d ":")
    echo Mergerfs volume "${targetLetter}" will be backuped from block device "${srcDevice}": "${srcPath}" to "${targetDevice}": "${targetPath}"
    confirm_func yes
    rsyncItWithSourceAndDestinationPaths "${srcPath}" "${targetPath}"
}

function about() {
    cat <<EOF
script looking for a list of devices by s/n 
in eponymous config file and suggest to 
do syncronize mergerfs volumes (folders A,B,C...)
mirrowing with rsync to tethered block devices
EOF
}

function usage() {
    cat <<EOF
-v, --version
        Show current script version
-a, --about
        Show extended script description

EOF
}

function main() {
    # If no arguments are provided
    [ $# -eq 0 ] && interact && exit

    while [ "$1" ]; do
        case "$1" in
        --about | -a) about && exit ;;
        --version | -v) echo "$version" && exit ;;
        *[0-9]*)
            # If the user provides number as an argument,
            exit
            ;;
        -*) die "option '$1' does not exist" ;;
        esac
        shift
    done
    exit 0
}

die() {
    # Print error message and exit
    #
    # The first argument provided to this function will be the error message.
    # Script will exit after printing the error message.
    printf "%b\n" "Error: $1" >&2
    exit 1
}

#shellcheck disable=SC2120
function checkPossibilities() {
    readConf
    srcDevice=$(getMountedSourceDev)
    targetParams=$(getMountedTargetParams)
    if ! [[ ${srcDevice} ]]; then
        echo err: nothing to bak
        exit 1
    fi
    if ! [[ ${targetParams} ]]; then
        echo err: there is nowhere to bak
        exit 1
    fi
    #shellcheck disable=SC2034
    srcPath="${params_key_value[SRC]}"
    targetLetter=$(echo "${targetParams}" | cut -f 1 -d "=")
    targetDevice=$(echo "${targetParams}" | cut -f 2 -d "=")
    #shellcheck disable=SC2034
    targetPath=$(lsblk -o NAME,SERIAL,MOUNTPOINT | grep -v loop | grep "${targetDevice}" -A1 | grep crypto | sed 's/\ \{1,\}/:/g' | cut -f 1,2 -d ":" | grep "$1:" | cut -f 2 -d ":")
    echo "${targetLetter}:${srcDevice}:${srcPath}${targetLetter}/:${targetDevice}:${targetPath}/${targetLetter}/"
    exit 0
}

function rsyncItWithSourceAndDestinationPaths() {
    rsync -axvv --no-whole-file --progress --force --delete --delete-before --delete-excluded --exclude="/.Trash*" --exclude="/lost+found" --exclude="/System Volume Information" "${1}" "${2}"
}

function devNameBySn() {
    result=$(lsblk -o NAME,SERIAL,MOUNTPOINT | grep -v loop | grep "${1}" | cut -f 1 -d " ")
    if [[ $result ]]; then
        echo "${result}"
    else
        exit 1
    fi
}

function dstPathByDevName() {
    result=$(lsblk -o NAME,SERIAL,MOUNTPOINT | grep -v loop | grep "${1}" | cut -f 1 -d " ")
    if [[ $result ]]; then
        echo "${result}"
    else
        exit 1
    fi
}

function devSnByName() {
    result=$(lsblk -o NAME,SERIAL,MOUNTPOINT | grep -v loop | sed 's/\ \{1,\}/:/g' | cut -f 1,2 -d ":" | grep "$1:" | cut -f 2 -d ":")
    #| grep "$1 " | awk '{ print $2 }')
    if [[ $result ]]; then
        echo "${result}"
    else
        exit 1
    fi
}

function readConf() {
    shopt -s extglob
    while IFS='= ' read -r lhs rhs; do
        if [[ $lhs != '*( )#*' ]]; then
            params_key_value[$lhs]=$rhs
        fi
    done <"$configFile"
}

function getMountedSourceDev() {
    for keySn in "${!params_key_value[@]}"; do
        #look at what should be the source serial number
        if [ "${params_key_value[${keySn}]}" == ROOT ]; then
            #does it our sn plugged in system
            blockDeviceName=$(devNameBySn "${keySn}")
            if [[ $blockDeviceName ]]; then
                #return blockname
                echo "${blockDeviceName}"
            else
                #or not plugged
                exit 1
            fi
        fi
    done
}

function getMountedTargetParams() {
    #will returning which DIR available on which DEVICE
    for keySn in "${!params_key_value[@]}"; do
        blockDeviceName=$(devNameBySn "${keySn}")
        if [[ $blockDeviceName ]]; then
            if [ "${params_key_value[${keySn}]}" != ROOT ]; then
                echo "${params_key_value[${keySn}]}"="${blockDeviceName}"
            fi
        fi
    done
}

function confirm_func() {
    if [[ "$1" == "yes" ]]; then
        echo -ne "Are you sure that want to continue? (\033[32my\033[0m/\033[31mn\033[0m)[y]: "
    else
        echo -ne "Are you sure that want to continue? (\033[32my\033[0m/\033[31mn\033[0m)[n]: "
    fi

    read -r item
    case "$item" in
    y | Y) #echo  do it
        ;;
    n | N) #echo "input «n»..."
        exit 0
        ;;
    *) #echo "nothing..."

        if [[ "$1" != "yes" ]]; then
            exit 0
        fi
        ;;
    esac
}

main "$@"
exit 0
