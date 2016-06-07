#! /bin/bash
# This script is used to install Node.js & Redis automatically

THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
if [ ! -f $THIS_SCRIPT_PATH/bash_helper.sh ]; then
    echo "$THIS_SCRIPT_PATH/bash_helper.sh not exists."
    exit 1
fi
. $THIS_SCRIPT_PATH/bash_helper.sh

CLOUD_PATH="$THIS_SCRIPT_PATH/cloud"
NODEJS_PATH="$HOME/ProgramFiles/Node.js"
REDIS_PATH="$HOME/ProgramFiles/Redis/redis-3.0.4"

CHECK_INSTALLED_SOFTWARE=1
NODEJS_VERSION="4.1.2"
REDIS_VERSION="3.0.4"
INSTALL_LOG="/tmp/install_log.txt"

echo -e "Node.js path:\t\t$NODEJS_PATH"
echo -e "Redis path:\t\t$REDIS_PATH"
echo -e "Node.js version:\t$NODEJS_VERSION"
echo -e "Redis versiong:\t\t$REDIS_VERSION"
echo -e "check dependence:\t$CHECK_INSTALLED_SOFTWARE"
echo -e "log path:\t\t$INSTALL_LOG"

#################
### main
#################

if [ -f $INSTALL_LOG ]; then
    read -p "log file [$INSTALL_LOG] exists. overwrite? [yes|no]:" user_input
    if [[ $user_input != 'yes' ]]; then
        echo_error "Install abort."
        exit 1
    fi
fi

exit 0

echo "$0 $@" > $INSTALL_LOG
check_for_root_rights

# check the dependence software & cloud code
echo_info "1. Checking the Node.js & Redis source code ..."
if [ ! -d "$NODEJS_PATH" ]; then
    echo_error "Can't find Node.js source code in $NODEJS_PATH path." 
    exit 1
else
    echo_success "Node.js source code exists in $NODEJS_PATH."
fi

if [ ! -d "$REDIS_PATH" ]; then
    echo_error "Can't find Redis source code in $REDIS_PATH path." 
    exit 1
else
    echo_success "Redis source code exists in $REDIS_PATH."
fi

# TODO
# 1. if source code does not exist, download...
# 2. setting system config, e.g, /etc/sysctl.conf, /etc/redis/6379.conf, /etc/security/limit.d/...

# install depandences
if [ $CHECK_INSTALLED_SOFTWARE -eq 1 ]; then 
    echo_info "2. Checking the required softwares/packages ..."

    echo "apt-get updating ..."
    bash_exec "$SUDO apt-get update" $INSTALL_LOG
    echo "apt-get update done."
    test_install_package make
    test_install_package gcc
    test_install_package g++
    test_install_package tcl8.6
    test_install_package ruby
    $SUDO gem install redis

else
    echo_info "2. Not checking the required softwares/packages ..."
fi

# install Node.js
echo_info "3. Checking Node.js ..."
RES=$(which node)
if [ $? -ne 0 ]; then
    echo_error "Node.js is not installed."
    echo "Installing Node.js version ${NODEJS_VERSION} ..."

    # install n
    cd "$NODEJS_PATH/n"
    bash_exec "$SUDO make install" $INSTALL_LOG
    bash_exec "$SUDO n $NODEJS_VERSION" $INSTALL_LOG

    # install npm
    cd $NODEJS_PATH
    bash_exec "$SUDO /bin/bash install.sh" $INSTALL_LOG

    # install forever
    bash_exec "$SUDO npm install -g forever" $INSTALL_LOG

    echo_success "Done. Node.js version ${NODEJS_VERSION} is installed."
else
    echo_success "Node.js is installded in $RES."
fi

# install Redis
echo_info "4. Checking Redis ..."
RES=$(which redis-server)
if [ $? -ne 0 ]; then
    echo_error "Redis is not installed."
    echo "Installing Redis version ${REDIS_VERSION} ..."

    cd $REDIS_PATH
    bash_exec "make" $INSTALL_LOG

    echo "make testing ..."
    make test >> $INSTALL_LOG 2>&1
    if [ $? -ne 0 ]; then
        echo_error "make test error. Skipping it."
    fi

    bash_exec "$SUDO make install" $INSTALL_LOG

    cd "$REDIS_PATH/utils"
    $SUDO /bin/bash install_server.sh

    echo_success "Done. Redis version ${REDIS_VERSION} is installed."
else
    echo_success "Redis is installded in $RES."
fi

# done
echo_info "Install done \\o/."

exit 0
