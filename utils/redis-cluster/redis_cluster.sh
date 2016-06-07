#! /bin/bash -f

THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
REDIS_SCRIPT_NAME='redis.sh'
REDIS_CONFIG_NAME='redis.conf'
REDIS_CONFIG_PATH="$THIS_SCRIPT_PATH/template/$REDIS_CONFIG_NAME"
REDIS_SCRIPT_PATH="$THIS_SCRIPT_PATH/template/$REDIS_SCRIPT_NAME"
TEMPLATE='TEMPLATE'
SUDO='sudo'
REDIS_CLI='/usr/local/bin/redis-cli'
REDIS_TRIB="$THIS_SCRIPT_PATH/redis-trib.rb"
LOCALHOST=$(ifconfig | grep -A2 'eth[0-9]' | awk '/inet addr:/{print substr($2,6)}')
REDIS_SLOT_MAX=16384
REDIS_TYPE='master'

################
### function
################

generate_redis_config () {
    local input=$1

    # check template file
    if [ ! -f $REDIS_CONFIG_PATH ] || [ ! -x $REDIS_SCRIPT_PATH ]; then
        echo "$REDIS_CONFIG_PATH or $REDIS_SCRIPT_PATH not exist."
        return 1
    fi

    # read parameters from $REDIS_CONFIG_PATH file
    local redisport=$(awk '/^port/ {print $2}' $REDIS_CONFIG_PATH)
    local pid_file=$(awk '/^pidfile/ {print $2}' $REDIS_CONFIG_PATH)
    local data_dir=$(awk '/^dir/ {print $2}' $REDIS_CONFIG_PATH)

    # check parameters: $redisport, $pid_file, $data_dir
    if  [ "${redisport#*$TEMPLATE}" == $redisport ] ||
        [ "${pid_file#*$TEMPLATE}" == $pid_file ] ||
        [ "${data_dir#*$TEMPLATE}" == $data_dir ];
    then
        echo "TEMPALTE config file $REDIS_CONFIG_PATH format error."
        return 1
    fi

    # check input whether is a valid port
    echo $input | grep -aE '^[0-9]{4,5}$' > /dev/null &&
    {
        local target_path="$THIS_SCRIPT_PATH/$input"
        if [ ! -d $target_path ]; then
            mkdir $target_path
            sed "s/$TEMPLATE/$input/g" $REDIS_CONFIG_PATH > "$target_path/$REDIS_CONFIG_NAME"
            cp $REDIS_SCRIPT_PATH $target_path
            echo "generate redis node in $target_path."
        else
            echo "$target_path exists."
            echo "stop generating redis node."
            return 1
        fi

        local data_dir=$(awk '/^dir/ {print $2}' "$target_path/$REDIS_CONFIG_NAME")
        if [ ! -d $data_dir ]; then
            echo "$data_dir not exists, mkdir $data_dir"
            $SUDO mkdir -p $data_dir
        else
            echo "$data_dir already exists."
        fi

        echo "Done."
        return 0
    } ||
    {
        echo "$input invalid port number."
        return 1
    }
}

remove_redis_config () {
    local target_port=$1
    local target_path="$THIS_SCRIPT_PATH/$target_port"

    if [ ! -f "$target_path/$REDIS_CONFIG_NAME" ]; then
        echo "$target_path/$REDIS_CONFIG_NAME does not exist."
        return 1
    fi

    local pid_file=$(awk '/^pidfile/ {print $2}' "$target_path/$REDIS_CONFIG_NAME")
    local data_dir=$(awk '/^dir/ {print $2}' "$target_path/$REDIS_CONFIG_NAME")

    if [ -f $pid_file ]; then
        echo "$pid_file exists, process is already running or crashed"
        echo "stop."
        return 1
    fi

    # check & remove redis config path
    if [ ! -d $target_path ]; then
        echo "$target_path not exist."
        echo "stop."
        return 1
    fi
    echo "removing $target_path"
    rm -rI $target_path
    [ ! -d $target_path ] && echo "Done." || {
        echo "Fail."
        return 1
    }

    # check & remove redis data path
    if [ ! -d $data_dir ]; then
        echo "$data_dir not exist."
        echo "stop."
        return 1
    fi
    echo "removing $data_dir"
    $SUDO rm -rI $data_dir
    [ ! -d $data_dir ] && echo "Done." || {
        echo "Fail."
        return 1
    }

    return 0
}

show_redis_config () {
    local file=${1:-$REDIS_CONFIG_PATH}
    sed -n '/^[^#]/p' $file
    return 0
}

redis_cluster_add_node () {

    local target_node=$1
    local cluster_list=($2)

    # check whether input is valid
    echo $target_node | grep -aE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{4,5}$' > /dev/null
    if [ $? -ne 0 ]; then
        echo $target_node | grep -aE '^[0-9]{4,5}$' > /dev/null &&
        {
            target_node="$LOCALHOST:$target_node"
        } || {
            echo "Please input <ip>:<port> or <port>"
            return 1
        }
    fi

    # check whether target_node is in redis cluster
    echo ${cluster_list[@]} | grep -o $target_node &&
    {
        echo "$target_node is already in redis cluster ${cluster_list[@]}"
        return 1
    }

    # check whether config file exist
    local target_node_config_dir="$THIS_SCRIPT_PATH/${target_node##*:}"
    if [ ! -d $target_node_config_dir ] || [ ! -f "$target_node_config_dir/$REDIS_CONFIG_NAME" ]; then
        echo "Please create $target_node config file first."
        return 1
    fi

    # check whether target_node is running
    local pid_file=$(awk '/^pidfile/ {print $2}' "$THIS_SCRIPT_PATH/${target_node##*:}/$REDIS_CONFIG_NAME")
    if [ ! -f $pid_file ]; then
        echo "$pid_file not exists, process is not running"
        echo "stop."
        return 1
    fi

    # use redis-trib.rb add target_node to cluster_list
    $REDIS_TRIB add-node $target_node $cluster_list > /dev/null ||
    {
        echo "add-node fail."
        echo "Please clean node.conf file first."
        return 1
    }
    echo "add-node success"
    echo "reshard slot, this may cost some time..."
    sleep 1

    # generate reshard parameters, averaging slot
    local target_node_id=$($REDIS_CLI -c -h ${cluster_list%%:*} -p ${cluster_list##*:} cluster nodes | grep $target_node | awk '/master/ {print $1}')
    local tmp_file=$(mktemp)
    echo $(( $REDIS_SLOT_MAX/(${#cluster_list[@]} + 1) )) > $tmp_file
    echo $target_node_id >> $tmp_file
    echo 'all' >> $tmp_file
    echo 'yes' >> $tmp_file
    sleep 1

    # reshard slot
    $REDIS_TRIB reshard $target_node > /dev/null < $tmp_file ||
    {
        echo "reshard fail"
        rm $tmp_file
        return 1
    }
    echo "$target_node reshard success."

    rm $tmp_file
    return 0
}

redis_cluster_del_node () {

    local target_node=$1
    local cluster_list=($2)

    # check whether input is valid
    echo $target_node | grep -aE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{4,5}$' > /dev/null
    if [ $? -ne 0 ]; then
        echo $target_node | grep -aE '^[0-9]{4,5}$' > /dev/null &&
        {
            target_node="$LOCALHOST:$target_node"
        } || {
            echo "Please input <ip>:<port> or <port>"
            return 1
        }
    fi

    # check whether config file exist
    local target_node_config_dir="$THIS_SCRIPT_PATH/${target_node##*:}"
    if [ ! -d $target_node_config_dir ] || [ ! -f "$target_node_config_dir/$REDIS_CONFIG_NAME" ]; then
        echo "Please create $target_node config file first."
        return 1
    fi

    # check whether target_node is running
    local pid_file=$(awk '/^pidfile/ {print $2}' "$THIS_SCRIPT_PATH/${target_node##*:}/$REDIS_CONFIG_NAME")
    if [ ! -f $pid_file ]; then
        echo "$pid_file not exists, process is not running"
        echo "stop."
        return 1
    fi

    local target_node_slot=$($REDIS_TRIB check $target_node | grep -aEA2 "^M.*$target_node" | grep -aEo "\([0-9]+ slots\)" | grep -o "[0-9]*")
    local target_node_id=$($REDIS_CLI -c -h ${cluster_list%%:*} -p ${cluster_list##*:} cluster nodes | grep $target_node | awk '{print $1}')

    # check whether target_node is in redis cluster (master or slave)
    if [ -z $target_node_id ]; then
        echo "$target_node is not in redis cluster ${cluster_list[@]}"
        return 1
    fi

    # if master
    if [ $(( $target_node_slot )) -ne 0 ]; then
        # use redis-trib.rb reshard the slots of target_node to other redis nodes in cluster
        local redis_id_list=($($REDIS_CLI -c -h ${cluster_list%%:*} -p ${cluster_list##*:} cluster nodes | grep -v $target_node | awk '/master/ {print $1}'))
        local send_slot=$(( $target_node_slot/${#redis_id_list[@]} ))
        local tmp_file=$(mktemp)

        for (( i=1; i<${#redis_id_list[@]}; i++ ))
        do
            echo $send_slot > $tmp_file
            echo ${redis_id_list[$i]} >> $tmp_file
            echo $target_node_id >> $tmp_file
            echo 'done' >> $tmp_file
            echo 'yes' >> $tmp_file
            sleep 1

            # reshard slot
            $REDIS_TRIB reshard $target_node > /dev/null < $tmp_file ||
            {
                echo "reshard fail"
                rm $tmp_file
                return 1
            }
            echo "${redis_id_list[$i]} reshard success. receive $send_slot"
        done

        # the last redis node in cluster receive the reset slots
        echo $(( $target_node_slot - (${#redis_id_list[@]} - 1) * $send_slot )) > $tmp_file
        echo ${redis_id_list[0]} >> $tmp_file
        echo $target_node_id >> $tmp_file
        echo 'done' >> $tmp_file
        echo 'yes' >> $tmp_file
        sleep 1

        $REDIS_TRIB reshard $target_node > /dev/null < $tmp_file ||
        {
            echo "reshard file"
            rm $tmp_file
            return 1
        }
        echo "${redis_id_list[0]} reshard success. receive $(( $target_node_slot - (${#redis_id_list[@]} - 1) * $send_slot ))"

        rm $tmp_file
    fi

    # remove target_node from the cluster by redis-trib.rb
    $REDIS_TRIB del-node $cluster_list $target_node_id > /dev/null ||
    {
        echo "del-node fail"
        return 1
    }
    echo "del-node success"

    return 0
}

redis_cluster_list () {
    local cluster_list=($1)
    local tmp_file1=$(mktemp)
    local tmp_file2=$(mktemp)

    # get master info
    $REDIS_TRIB check $REDIS_LIST > $tmp_file1
    cat $tmp_file1 | grep -aEA2 "^M:" | awk '
    BEGIN{
        i = 1;
    }
    /^M:/{
        id = $2;
        ip = $3;
    }
    /slots:.*master$/{
        master = $NF;
        slot = $(NF-2)"-"$(NF-1);
    }
    /replica\(s\)$/{
        slave = $1;
        printf "%s %s %s %s(%s-replica)\n", id, ip, slot, master, slave;
    }
    ' | sort -k 1 > $tmp_file2

    # get slave info
    # FIXME when a master has two slaves, there may be an error.
    cat $tmp_file1 | grep -aEA2 "^S:" | awk '
    /^S:/{
        ip = $3;
    }
    /replicates/{
        master_id = $2;
        printf "%s %s\n", master_id, ip;
    }
    ' | sort -k 1 | join -a 1 -1 1 -2 1 $tmp_file2 - |
    awk '{print $2" "$3" " $4" "$1" "$5}' |
    sort -k 1

    # clean tmp files
    rm $tmp_file1
    rm $tmp_file2

    return 0
}

redis_cluster_clients_number () {
    local redis_list=($1)
    local total=0

    for node in ${redis_list[@]}
    do
        local redis_host=${node%%:*}
        local redis_port=${node##*:}
        local tmp=$($REDIS_CLI -c -h $redis_host -p $redis_port info clients | awk -F ':' '/connected_clients/ {print $2}' | grep -o '[0-9]*')
        total=$(( $total + $tmp ))
    done
    echo $total

    return 0
}

usage() {
    echo "Usage: ./redis_cluster.sh [options] command"
    echo "[-h ] show this help info"
    echo "[-d port] delete config & data file"
    echo "[-p port] create config & data file"
    echo "[-s file] show <file> parameters"
    echo "[-l list] show redis list. if use '-c' option, it will show cluster list"
    echo "[-c <ip>:<port>] cluster mode. use startup node(<ip>:<port>) get cluster nodes list"
    echo "[-n number] redis cluster(master) connected_clients"
    echo "[add_node <local ip>:<port>] add redis node to redis cluster with average slots allocation. use with '-c'"
    echo "[del_node <local ip>:<port>] remove redis node from redis cluster and give the sameslots to other node. use with '-c'"
    echo "command: [start] [status] [stop] [restart] or other [redis command]"
    return 0
}

################
### main
################

# get local redis list
REDIS_LIST=($(ls $THIS_SCRIPT_PATH | awk -v localhost=$LOCALHOST '/^[0-9]{4,5}$/ {printf "%s:%d\n", localhost, $0}'))
FLAG_REDIS_CLUSTER=0

until [ -z "$1" ]
do
    case "$1" in
        -d | --delete )
            remove_redis_config $2 && exit 0 || exit 1
            ;;
        -p | --port )
            generate_redis_config $2 && exit 0 || exit 1
            ;;
        -s | --show )
            show_redis_config ${2:-$REDIS_CONFIG_PATH} && exit 0 || exit 1
            ;;
        -l | --list )
            if [ $FLAG_REDIS_CLUSTER -eq 1 ]; then
                redis_cluster_list  $REDIS_LIST
            else
                echo ${REDIS_LIST[@]} | sed 's/ /\n/g'
            fi
            exit 0
            ;;
        -n | --number )
            if [ $FLAG_REDIS_CLUSTER -ne 1 ]; then
                echo "Please run with '-c' to specify the target cluster."
                exit 1
            fi

            tmp=${REDIS_LIST[@]}
            redis_cluster_clients_number "$tmp"
            exit 0
            ;;
        -c | --cluster)
            echo $2 | grep -aE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{4,5}$' > /dev/null
            if [ $? -ne 0 ]; then
                usage
                exit 1
            fi
            REDIS_LIST=($($REDIS_CLI -c -h ${2%%:*} -p ${2##*:} cluster nodes | grep $REDIS_TYPE | awk '{print $2}'))
            if [ ${#REDIS_LIST[@]} -eq 0 ]; then
                echo "no redis node found in $2 cluster"
                exit 1
            fi
            FLAG_REDIS_CLUSTER=1

            shift 2
            ;;
        -h | --help )
            usage
            exit 0
            ;;
        add-node )
            if [ $FLAG_REDIS_CLUSTER -ne 1 ]; then
                echo "Please run with '-c' to specify the target cluster."
                exit 1
            fi

            tmp=${REDIS_LIST[@]}
            redis_cluster_add_node $2 "$tmp" && exit 0 || exit 1
            ;;
        del-node )
            if [ $FLAG_REDIS_CLUSTER -ne 1 ]; then
                echo "Please run with '-c' to specify the target cluster."
                exit 1
            fi

            tmp=${REDIS_LIST[@]}
            redis_cluster_del_node $2 "$tmp" && exit 0 || exit 1
            ;;
        * )
            CMD=(${CMD[@]} $1)
            shift
            ;;
    esac
done

if [ ${#REDIS_LIST[@]} -eq 0 ]; then
    echo "no redis node found in $THIS_SCRIPT_PATH"
    exit 1
fi

if [[ ${#CMD[@]} -eq 0 ]]; then
    echo "Please use start, stop, restart, status, or redis command as first argument"
    exit 1
fi

# exec command in every redis node of $REDIS_LIST
for node in ${REDIS_LIST[@]}
do
    redis_host=${node%%:*}
    redis_port=${node##*:}

    case $CMD in
        start | stop | status | restart)
            # local redis server
            redis_script_path="$THIS_SCRIPT_PATH/$redis_port/$REDIS_SCRIPT_NAME"
            redis_config_path="$THIS_SCRIPT_PATH/$redis_port/$REDIS_CONFIG_NAME"

            [ $redis_host = $LOCALHOST ] &&
            [ -f $redis_config_path ] &&
            [ -x $redis_script_path ] &&
            {
                echo -n "$node: "
                $SUDO $redis_script_path $CMD
            }

            ;;
        *)
            # all redis server in the cluster
            echo "$(tput bold)$node$(tput sgr0)"
            $REDIS_CLI -c -h $redis_host -p $redis_port ${CMD[@]}
            ;;
    esac
done

exit 0
