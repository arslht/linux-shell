#! /bin/sh

[ $# -ne 1 ] && exit 0

DIR_PATH=~/                 
OBJ_FILE=.bashrc

#下面改变的是69行的内容，原内容将被参数1代替

echo  "the original content:"
echo " "

sed -n -e "117p" $DIR_PATH/$OBJ_FILE    #显示69行的内容

 

#69 stands for line number; $OBJ_FILE stands for object file
#sed -i "117c$1" $DIR_PATH/$OBJ_FILE          #用$1替换69行的内容
sed -i 's/$1/$2/g' $DIR_PATH/$OBJ_FILE

echo "Now, the  content:"
sed -n -e "117p" $DIR_PATH/$OBJ_FILE        #再次显示69行的内容
echo " "
