#! /bin/bash

declare -r THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
declare -r THIS_SCRIPT=$(basename $(readlink -f $0))
if [ ! -f $THIS_SCRIPT_PATH/bash_helper.sh ]; then
    echo "$THIS_SCRIPT_PATH/bash_helper.sh not exists."
    exit 1
fi
. ${THIS_SCRIPT_PATH}/bash_helper.sh

declare PNAME="redis-server"
declare TARGET_PID=""
declare HUM_READ=0

### get command line ###
usage() {
    echo_error "Usage: [-p pid] [-h]"
}

while getopts "p:h" args;
do
    case $args in
        p )
            TARGET_PID=$OPTARG
            ;;
        h )
            HUM_READ=1
            ;;
        * )
            usage
            exit 1
            ;;
    esac
done

### get system config ###
declare -r TOTAL_CPU=$(cat /proc/cpuinfo | grep "processor" | wc -l)
declare -r TOTAL_MEM=$(cat /proc/meminfo | awk '/MemTotal/ {print $2}') # in KB
declare PID_LIST=($(pgrep $PNAME))
declare PID_LIST_LENGTH=${#PID_LIST[@]}
declare -A PORT_LIST

# check pid list
if [ $PID_LIST_LENGTH -eq 0 ]; then
    echo_error "no $PNAME runing"
    exit 1
fi

# find pid bind port
for (( i=0; i<$PID_LIST_LENGTH; i++ ))
do
    PORT_LIST[$i]=$(ps -f -p ${PID_LIST[$i]} | awk -v pid="${PID_LIST[$i]}" '$0 ~ pid {print $9}' | awk -F ':' '{printf $2}')
done

# check target pid
if [[ "$TARGET_PID" != "" ]]; then
    for (( i=0; i<=$PID_LIST_LENGTH; i++))
    do
        if [[ "${PID_LIST[$i]}" = "$TARGET_PID" ]]; then
            PID_LIST[0]=${PID_LIST[$i]}
            PORT_LIST[0]=${PORT_LIST[$i]}
            break
        fi
    done

    if [ $i -le $PID_LIST_LENGTH ]; then
        PID_LIST_LENGTH=1
    else
        echo_error "PID is not found."
        exit 1
    fi
fi

### main ###
echo "*** System information ***"
echo "* CPU $TOTAL_CPU"
echo "* total memory $TOTAL_MEM KB"
echo "* program $PNAME"
echo "* pid list ${PID_LIST[@]}"
echo "* port list ${PORT_LIST[@]}"
echo "* target pid $TARGET_PID"
echo "**************************"

declare -r MY_TAB="  "
declare -r FORMAT_FRQ=$(expr 15 / $PID_LIST_LENGTH)
declare FORMAT_COL=""
declare FORMAT_VAL=""
declare time_index=0

get_redis_value () {
    local infotype=$1
    local infostr=$2
    local port=$3
    local ret=$(redis-cli -p $port INFO $infotype | awk -v key="${infostr}" -F ':' '$0 ~ key {print $2}'| tr -d '\015')
    echo $ret
}

# output column list
declare COL_ARRAY=("TIME" "PID/PORT" "VIRT" "RES" "SHR" "%CPU" "%MEM" "clients" "in/out(kbps)" "pubsub" "keys")
declare -A VAL_ARRAY
for (( i=0; i<${#COL_ARRAY[@]}; i++ ))
do
    VAL_ARRAY[${COL_ARRAY[$i]}]=""
done

while sleep 1;
do
    VAL_ARRAY["TIME"]=$(date | awk '{print $4}')

    # traverse PID_LIST & PORT_LIST
    for (( i=0; i<$PID_LIST_LENGTH; i++))
    do
        VAL_ARRAY["PID/PORT"]="${PID_LIST[$i]}/${PORT_LIST[$i]}"
        TOP_RES=$(top -b -n1 -p ${PID_LIST[$i]} | grep ${PID_LIST[$i]})
        VAL_ARRAY["VIRT"]=$(cat /proc/${PID_LIST[$i]}/status | awk '/VmSize/ {print $2}')
        VAL_ARRAY["RES"]=$(cat /proc/${PID_LIST[$i]}/status | awk '/VmRSS/ {print $2}')
        VAL_ARRAY["SHR"]=$(echo $TOP_RES | awk '{print $7}' | grep -aEo "[0-9.]*")
        VAL_ARRAY["%CPU"]=$(echo $TOP_RES | awk '{print $9}')
        VAL_ARRAY["%MEM"]=$(echo $TOP_RES | awk '{print $10}')
        VAL_ARRAY["clients"]=$(get_redis_value 'clients' 'connected_clients:' "${PORT_LIST[$i]}")
        VAL_ARRAY["in/out(kbps)"]=$(get_redis_value 'stats' 'instantaneous_input_kbps:' "${PORT_LIST[$i]}")
        VAL_ARRAY["in/out(kbps)"]="${VAL_ARRAY['in/out(kbps)']}/$(get_redis_value 'stats' 'instantaneous_output_kbps:' "${PORT_LIST[$i]}")"
        VAL_ARRAY["pubsub"]=$(get_redis_value 'stats' 'pubsub_channels' "${PORT_LIST[$i]}")
        VAL_ARRAY["keys"]=$(redis-cli -p "${PORT_LIST[$i]}" INFO Keyspace | grep -aEo "keys=[0-9]*" | awk -F '=' '{print $2}')

        # convert units
        if [ $HUM_READ -eq 1 ]; then
            VAL_ARRAY["VIRT"]=$(convert_mem_unit ${VAL_ARRAY["VIRT"]})
            VAL_ARRAY["RES"]=$(convert_mem_unit ${VAL_ARRAY["RES"]})
            VAL_ARRAY["SHR"]=$(convert_mem_unit ${VAL_ARRAY["SHR"]})
        fi

        # format output
        for (( j=0; j<${#COL_ARRAY[@]}; j++ ))
        do
            LENGTH_DIFF=$(expr ${#COL_ARRAY[$j]} - ${#VAL_ARRAY[${COL_ARRAY[$j]}]} )
            if [ $LENGTH_DIFF -ge 0 ]; then
                FORMAT_COL="${FORMAT_COL}${COL_ARRAY[$j]}${MY_TAB}"
                FORMAT_VAL="${FORMAT_VAL}${VAL_ARRAY[${COL_ARRAY[$j]}]}$(printf '%.0s ' $(seq 1 $LENGTH_DIFF))${MY_TAB}"
            else
                FORMAT_VAL="${FORMAT_VAL}${VAL_ARRAY[${COL_ARRAY[$j]}]}${MY_TAB}"
                FORMAT_COL="${FORMAT_COL}${COL_ARRAY[$j]}$(printf '%.0s ' $(seq 1 ${LENGTH_DIFF/#-/}))${MY_TAB}"
            fi
        done

        # output column list
        if [ $i -eq 0 ] && [ $((time_index % $FORMAT_FRQ)) -eq 0 ]; then
            echo "$FORMAT_COL"
            time_index=0
        fi
        echo "$FORMAT_VAL"

        # clear format buffer
        FORMAT_COL=""
        FORMAT_VAL=""
    done

    let "time_index++"
done
