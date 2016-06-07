#! /bin/bash -f

:<<block
declare -r THIS_SCRIPT_PATH=$(dirname $(readlink -f $0))
declare -r THIS_SCRIPT=$(basename $(readlink -f $0))
if [ ! -f $THIS_SCRIPT_PATH/bash_helper.sh ]; then
		echo "$THIS_SCRIPT_PATH/bash_helper.sh not exists."
		exit 1
fi
. ${THIS_SCRIPT_PATH}/bash_helper.sh
echo ${THIS_SCRIPT_PATH}
echo ${THIS_SCRIPT}
block
echo -e "Hello Shell!\a\n
I will ues 'touch' command to create 3 files."
read -p "Please input your filename:" fileuser

filename=${fileuser:-"filename"}

date1=$(date --date="2 days ago" +%Y%m%d)
date2=$(date --date="1 days ago" +%Y%m%d)
date3=$(date +%Y%m%d)
file1=${filename}${date1}
file2=${filename}${date2}
file3=${filename}${date3}

touch "$file1"
touch "$file2"
touch "$file3"



