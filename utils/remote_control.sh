#! /bin/bash -f

declare -r THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
declare -r THIS_SCRIPT=$(basename $(readlink -f $0))
if [ ! -f $THIS_SCRIPT_PATH/bash_helper.sh ]; then
    echo "$THIS_SCRIPT_PATH/bash_helper.sh not exists."
    exit 1
fi
. ${THIS_SCRIPT_PATH}/bash_helper.sh

USER_SERVER_LIST=(
    "cloud@10.3.242.231"
    "cloud@10.3.242.232"
    "cloud@10.3.242.233"
    "cloud@10.3.242.234"
    "cloud@10.3.242.235"
    "cloud@10.3.242.236"
)

usage() {
    echo -e "Usage: ./$THIS_SCRIPT [options] \"remote command\""
    echo -e " [-l] show list"
    echo -e " [-h] help"
    echo -e " [-a \"user1@server1;user2@server2;...\"] append list"
    echo -e " [-s \"user1@server1;user2@server2;...\"] set list"
}

until [ -z "$1" ]
do
    case "$1" in
        -a | --append )
            shift;
            USER_SERVER_LIST=(${USER_SERVER_LIST[@]} $(echo $1 | sed 's/[;:,]/ /g'))
            echo "user@server list: ${USER_SERVER_LIST[@]}"
            shift;
            ;;
        -s | --set )
            shift;
            USER_SERVER_LIST=($(echo $1 | sed 's/[;:,]/ /g'))
            echo "user@server list: ${USER_SERVER_LIST[@]}"
            shift;
            ;;
        -h | --help )
            usage
            exit 0
            ;;
        -l | --list )
            echo ${USER_SERVER_LIST[@]}
            exit 0
            ;;
        * )
            CMD=(${CMD[@]} $1)
            shift;
            ;;
    esac
done

CMD=${CMD:-'echo $HOME'}

for (( i=0; i<${#USER_SERVER_LIST[@]}; i++))
do
    if [[ ${CMD[0]} == 'vim' ]]; then
        echo ${CMD[0]} scp://${USER_SERVER_LIST[i]}//home/${USER_SERVER_LIST[i]%%@*}/$(echo ${CMD[@]} | sed "s/${CMD[0]} //g")
        ${CMD[0]} scp://${USER_SERVER_LIST[i]}//home/${USER_SERVER_LIST[i]%%@*}/$(echo ${CMD[@]} | sed "s/${CMD[0]} //g")
        continue
    fi

    echo -e "${YELLOW}${USER_SERVER_LIST[i]}\$ ${CMD[@]}${RESET_COLOR}"
    ssh ${USER_SERVER_LIST[i]} ${CMD[@]}
done
