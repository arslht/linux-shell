#!/bin/bash

echo -e "Please input a filename,I will check the filename's type and\
permission.\n"
read -p "Input a filename :" filename
test -z $filename && echo "You MUST input a ilename." && exit 0

test ! -e $filename && echo "The filename $filename DO BOT exist" && exit 0
test -f $filename && filetype="regulare file"
test -d $filename && filetype="directory"
test -r $filename &&		 perm="readable"
test -w $filename &&		 perm="$perm writable"
test -x $filename &&		 perm="$perm executable"

echo "The filename: $filename is a $filetype"
echo "And the permissions are : $perm"
