#!/bin/sh
# control redis server
# put this script and redis config file in the same path
# run this script with root permission

THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
EXEC=/usr/local/bin/redis-server
CLIEXEC=/usr/local/bin/redis-cli
REDIS_CONFIG_NAME="redis.conf"
REDIS_CONFIG_PATH="$THIS_SCRIPT_PATH/$REDIS_CONFIG_NAME"

if [ $(id -u) -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

if [ ! -f $REDIS_CONFIG_PATH ]; then
    echo "$REDIS_CONFIG_PATH not exist."
    exit 1
fi

REDISPORT=$(awk '/^port/ {print $2}' $REDIS_CONFIG_PATH)
PIDFILE=$(awk '/^pidfile/ {print $2}' $REDIS_CONFIG_PATH)
DATA_DIR=$(awk '/^dir/ {print $2}' $REDIS_CONFIG_PATH)

if [ ! -d $DATA_DIR ]; then
    echo "$DATA_DIR does not exist."
    exit 1
fi

###############
# SysV Init Information
# chkconfig: - 58 74
# description: redis.sh is the redis daemon.
### BEGIN INIT INFO
# Provides: redis.sh
# Required-Start: $network $local_fs $remote_fs
# Required-Stop: $network $local_fs $remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Should-Start: $syslog $named
# Should-Stop: $syslog $named
# Short-Description: start and stop redis.sh
# Description: Redis daemon
### END INIT INFO


case "$1" in
    start)
        if [ -f $PIDFILE ]
        then
            echo "$PIDFILE exists, process is already running or crashed"
        else
            echo "Starting Redis server..."
            $EXEC $REDIS_CONFIG_PATH
        fi
        ;;
    stop)
        if [ ! -f $PIDFILE ]
        then
            echo "$PIDFILE does not exist, process is not running"
        else
            PID=$(cat $PIDFILE)
            echo "Stopping ..."
            $CLIEXEC -p $REDISPORT shutdown
            while [ -x /proc/${PID} ]
            do
                echo "Waiting for Redis to shutdown ..."
                sleep 1
            done
            echo "Redis stopped"
        fi
        ;;
    status)
        PID=$(cat $PIDFILE)
        if [ ! -x /proc/${PID} ]
        then
            echo 'Redis is not running'
        else
            echo "Redis is running ($PID)"
        fi
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Please use start, stop, restart or status as first argument"
        ;;
esac
