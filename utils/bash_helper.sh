#! /bin/bash

SUDO=''
declare -r BLACK='\E[30m'
declare -r RED='\E[31m'
declare -r GREEN='\E[32m'
declare -r YELLOW='\E[33m'
declare -r BLUE='\E[34m'
declare -r MAGENTA='\E[35m'
declare -r CYAN='\E[36m'
declare -r WHITE='\E[37m'
declare -r RESET_COLOR='\E[00m'

#################
### functions
#################

convert_mem_unit () {
    # input memory in kb
    local mem_in_kb=$1
    local ret=$(echo $mem_in_kb | awk '
    BEGIN{
        gb_factor = 1024*1024
        mb_factor = 1024
    }

    {
        if($1 > gb_factor)
            printf "%.3fGB\n", $1/gb_factor
        else if ($1 > mb_factor)
            printf "%.3fMB\n", $1/mb_factor
        else
            printf "%.3fKB\n", $1
    }')
    echo $ret
}

check_for_root_rights() {
    if [ $USER != "root" ]; then
        #SUDO="sudo -E "
        SUDO="sudo"
        echo "Run as a sudoers" 
        return 1
    else 
        echo  "Run as a root" 
        return 0
    fi
}

bash_exec() {
    local logfile=${2:-/dev/null}
    echo "[$1]" >> $logfile
    local output=$($1 2>&1 | tee -a $logfile)
    local result=$?
    if [ $result -eq 0 ]; then
        echo_success "$1"
    else
        echo_error "$1: $output"
        exit 1
    fi
}

test_install_package() {
    # usage: test_install_package package_name

    if [ $# -eq 1 ]; then
        dpkg -s "$1" > /dev/null 2>&1 && {
            echo_success "$1 is installed."
        } || {
            echo_error "$1 is not installed." 
            echo "Installing ..."
            $SUDO apt-get install -y $@
            echo_success "Done. $1 is installed."
        }
    fi
}

test_is_host_reachable() {
    ping -c 1 $1 > /dev/null || { echo_fatal "$2 host $1 does not respond to ping" >&2 ; }
    echo_success "$2 host $1 is reachable"
}

#################
### echo
#################

cecho() {
    # Color-echo
    # arg1 = message
    # arg2 = color

    local message=$1
    local color=$2
    if [ $# -eq 2 ]; then 
        echo -e -n "$color$message$RESET_COLOR"
        echo
    else 
        echo "$message"
    fi
    return
}

echo_info() {
    local my_string=""
    until [ -z "$1" ]
    do
        my_string="$my_string$1"
        shift
    done
    cecho "$my_string" $YELLOW
}

echo_success() {
    local my_string=""
    until [ -z "$1" ]
    do
        my_string="$my_string$1"
        shift
    done
    cecho "$my_string" $GREEN
}

echo_error() {
    local my_string=""
    until [ -z "$1" ]
    do
        my_string="$my_string$1"
        shift
    done
    cecho "$my_string" $RED
}
