#! /bin/bash

### System configuration ###

THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
DIR=$THIS_SCRIPT_PATH

while [ 1 ];
do
    if [[ $HOME == *"$DIR"* ]]; then
        echo "${COLOR_RED}$DIR no cloud path found.${COLOR_CLEAN}"
        exit 1
    fi
    [ $(basename $DIR) == cloud ] && break
    DIR=$(dirname $(readlink -f $DIR))
done

MQTT_HOST="127.0.0.1"
MQTT_PORT="1883"
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
HTTP_PORT="3000"

# FIXME assume http & mqtt & timing use the same redis host and redis port
NODE_OPT="--max-old-space-size=8192"
MQTT_OPT="$NODE_OPT --rh $REDIS_HOST --rp $REDIS_PORT -l debug"
HTTP_OPT="$NODE_OPT --rh $REDIS_HOST --rp $REDIS_PORT --mh $MQTT_HOST --mp $MQTT_PORT --hp $HTTP_PORT -l debug"
TIMING_OPT="$NODE_OPT --rh $REDIS_HOST --rp $REDIS_PORT"
FOREVER_OPT="--minUptime 10000 --spinSleepTime 1000"

HTTP_SERVER="$DIR/http/http-server.js"
MQTT_SERVER="$DIR/mqtt/mqtt-server.js"
TIMING_SCHED="$DIR/mqtt/time-schedule.js"

HTTP_LOG="/tmp/http.log"
MQTT_LOG="/tmp/mqtt.log"
TIMING_LOG="/tmp/timing.log"

### parameters & functions ###

COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_CLEAN="\033[0m"

Help() {
    local msg="$1"

    [ -n "$msg" ] && echo -e "${COLOR_RED}$msg${COLOR_CLEAN}"
    echo -e "Usage: parameters should be 1 or 2:"
    echo -e "\t\$1 (operate): should be [start], [stop], [restart], [list] or [cleanlog]."
    echo -e "\t\$2 (service): should be [mqtt], [http], or [timing]."
}

ServiceOperate() {
    if [ $# -ne 4 ]; then
        echo "ERROR: $# parameters received in ${FUNCNAME[0]}."
        exit 1;
    fi

    local service="$1"
    local operate="$2"
    local opt="$3"
    local log="$4"

    local res=$(forever list | grep $service)

    case $operate in
        "start" )
            if [ -n "$res" ]; then
                echo -e "${COLOR_RED}$(basename $service) have already started.${COLOR_CLEAN}"
                return
            fi
            forever start $FOREVER_OPT -a -l $log $service $opt
            ;;

        "stop"  )
            if [ -z "$res" ]; then
                echo -e "${COLOR_RED}$(basename $service) have not started.${COLOR_CLEAN}"
                return
            fi
            forever stop $service
            ;;

        "restart"  )
            if [ -z "$res" ]; then
                echo -e "${COLOR_RED}$(basename $service) have not started.${COLOR_CLEAN}"
                return
            fi
            forever stop $service
            forever start $FOREVER_OPT -a -l $log $service $opt
            ;;

        "cleanlog"  )
            if [ -n "$res" ]; then
                echo -e "${COLOR_RED}Cannot clean log. $(basename $service) have already started.${COLOR_CLEAN}"
                return
            fi
            rm -f $log
            echo -e "${COLOR_GREEN}$(basename $log) has been removed.${COLOR_CLEAN}"
            ;;

        *   )
            Help "operate=$operate error."
            ;;
    esac
}

### main ###

FLAG_MQTT=0
FLAG_HTTP=0
FLAG_TIMING=0
OP=''

if [ $# -lt 1 ] || [ $# -gt 2 ]; then # FIXME
    Help "Received $# parameters."
    exit 1
fi

OP=$1

if [ $# -eq 1 ]; then
    FLAG_MQTT=1
    FLAG_HTTP=1
    FLAG_TIMING=1
fi

if [ $# -eq 2 ]; then
    case $2 in
        "mqtt"  )
            FLAG_MQTT=1
            echo "MQTT_OPT: $MQTT_OPT"
            ;;

        "http"  )
            FLAG_HTTP=1
            echo "HTTP_OPT: $HTTP_OPT"
            ;;

        "timing"  )
            FLAG_TIMING=1
            echo "TIMING_OPT: $TIMING_OPT"
            ;;

        *   )
            Help "service=$2 error."
            ;;
    esac
fi

[ $OP = "list" ]        && forever list && exit 0
[ $FLAG_MQTT -eq 1 ]    && ServiceOperate "$MQTT_SERVER"    "$OP" "$MQTT_OPT"   "$MQTT_LOG"
[ $FLAG_HTTP -eq 1 ]    && ServiceOperate "$HTTP_SERVER"    "$OP" "$HTTP_OPT"   "$HTTP_LOG"
[ $FLAG_TIMING -eq 1 ]  && ServiceOperate "$TIMING_SCHED"   "$OP" "$TIMING_OPT" "$TIMING_LOG"

exit 0
