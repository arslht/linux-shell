#! /bin/bash -f

BACKUPHOST='houlu@10.110.136.188'
REL_BACKUPDIR='backup'
DATADIR='/var/lib/redis'
FLAG_REMOTE=1

THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
SUDO='sudo'
LOCALHOST=$(ifconfig | grep -A2 'eth[0-9]' | awk '/inet addr:/{print substr($2,6)}')
TIMENOW=$(date "+%Y-%m-%d_%H-%M-%S")

################
### main
################
echo -e "#############################################"
echo -e "# backup host:\t\t$BACKUPHOST"
echo -e "# backup dir:\t\t<\$HOME>/$REL_BACKUPDIR"
echo -e "# redis datadir:\t$DATADIR"
echo -e "# remote backup:\t$FLAG_REMOTE"
echo -e "#############################################"

# check $DATADIR
if [ ! -d $DATADIR ]; then
    echo "redis data directory $DATADIR does not exist"
    exit 1
fi

# local backup
if [ $FLAG_REMOTE -eq 0 ]; then
    backupdir="$HOME/$REL_BACKUPDIR"
    # check $backupdir
    if [ ! -d $backupdir ]; then
        echo "backup directory does not exist"
        exit 1
    fi

    # get local redis datadir list
    port_list=($(ls $DATADIR))
    for port in ${port_list[@]}
    do
        # check redis data directories format. should be port number
        echo $port | grep -aE "^[0-9]{4,5}$" > /dev/null || {
            echo "$DATADIR/$port is invalid"
            echo "stop"
            exit 1
        }

        # check backup directory
        target_backupdir="$backupdir/$LOCALHOST/$port/$TIMENOW"
        if [ ! -d "$target_backupdir" ]; then
            mkdir -p $target_backupdir
        fi

        # compress redis data. backup both dump.rdb & appendonly.aof
        echo "compressing redis data ($DATADIR/$port), this may cost some time..."
        tar -czvf "$target_backupdir/${TIMENOW}.tar.gz" -C "$DATADIR/$port" . > /dev/null
        if [ $? -eq 0 ]; then
            echo "$DATADIR/$port compress success"
        else
            echo "$DATADIR/$port compress fail"
            echo "stop"
            exit 1
        fi
    done

# remote backup
elif [ $FLAG_REMOTE -eq 1 ]; then
    # check $BACKUPHOST
    if [ -z $BACKUPHOST ]; then
        echo "backup host is not given"
        exit 1
    fi

    # test network
    echo "testing network, ping ${BACKUPHOST##*@}..."
    ping -c 1 ${BACKUPHOST##*@} > /dev/null && {
        echo "network ok"
    }|| {
        echo "cannot connect to ${BACKUPHOST##*@}"
        exit 1
    }

    # check ssh key
    ssh -o BatchMode=yes $BACKUPHOST true > /dev/null 2>&1 
    if [ $? -ne 0 ]; then
        echo "Please copy ssh-key to $BACKUPHOST by ssh-copy-id"
        exit 1
    fi

    # get remote host $HOME
    backupdir="$(ssh $BACKUPHOST pwd)/$REL_BACKUPDIR"

    # get local redis datadir list
    port_list=($(ls $DATADIR))
    for port in ${port_list[@]}
    do
        # check redis data directories format. should be port number
        echo $port | grep -aE "^[0-9]{4,5}$" > /dev/null || {
            echo "$DATADIR/$port is invalid"
            echo "stop"
            exit 1
        }

        # check backup directory
        target_backupdir="$backupdir/$LOCALHOST/$port/$TIMENOW"
        if [ ! -d "$target_backupdir" ]; then
            ssh $BACKUPHOST "mkdir -p $target_backupdir"
        fi

        # compress redis data. backup both dump.rdb & appendonly.aof
        echo "compressing redis data ($DATADIR/$port), this may cost some time..."
        tmp_file="/tmp/${TIMENOW}.tar.gz"
        tar -zpcvf $tmp_file -C "$DATADIR/$port" . > /dev/null
        if [ $? -eq 0 ]; then
            echo "$DATADIR/$port compress success"
        else
            echo "$DATADIR/$port compress fail"
            echo "stop"
            exit 1
        fi

        # copy compressed data to remote host
        echo "copying data to $BACKUPHOST:$target_backupdir, this may cost some time..."
        scp $tmp_file $BACKUPHOST:$target_backupdir > /dev/null
        echo "done."

        # clean local tmp file
        rm $tmp_file
    done
fi

exit 0
