#! /bin/bash
#############################################################################################
# 名称：实现回收站功能
# 作者：chenxiangshu@outlook.com
# 日期：2023年12月11日
# ------------- 修改 -------------
# 1.0   2023年12月12日  创建
#############################################################################################

# 防止脚本同时运行
LOCKFILE="/var/lock/$(basename $0).lock"
exec 7<>$LOCKFILE
flock 7

## ---------------------------------- 参数配置 ---------------------------------- ##
RECYCLE_DIR=~/.recycle # 回收站路径
DEL_EXEC=/usr/bin/rm       # 实际删除程序
ProtectionList=(       # 保护文件夹列表
    /usr/bin
    /usr/lib
    /usr/lib32
    /usr/lib64
    /usr/libx32
    /usr/sbin
    /usr/include
    /usr/share
    /usr/local
    /usr/local/bin
    /usr/local/include
    /usr/local/sbin
    /usr/local/share
    # 自定义...
)
## ----------------------------------   END   ---------------------------------- ##

DIR=$RECYCLE_DIR  
_flag=' '        # 功能标志
idx=0
_RECYCLE_DIR=`realpath $RECYCLE_DIR`

# 检查
function CheckFile() {
    local file=$1
    local ret=$(echo "$file" | awk -F '/' '{printf NF-1}') # 检查是否为根目录
    [[ "$ret" = "1" ]] && echo "Fail" && return
    for p in ${ProtectionList[@]}; do
        [[ "$file" = "$p" ]] && echo "Fail" && return
    done
    echo "Ok"
}

# 删除文件
function DeleteFile() {
    local dir=$1
    local file=$2
    # 检查文件是否保护
    local ret=$(CheckFile $file)
    [[ "$ret" != "Ok" ]] && echo "$file: 文件保护" && return
    local f_dir=$(dirname $file)
    if [[ "$f_dir" =~ ^$_RECYCLE_DIR.* ]];then
        $DEL_EXEC -rf $file # 删除回收站文件
    else
        [ ! -d "${dir}${f_dir}" ] && mkdir -p "${dir}${f_dir}"
        mv -f "$file" "${dir}${f_dir}/"
    fi
    return
}

# 删除空文件夹
function DeleteEmpty() {
    local dir=$1
    [ ! -d $dir ] && return 0
    [ "$(ls -A $dir)" = "" ] && ${DEL_EXEC} -rf "$dir"
    return 0
}

# 清空文件夹
function CleanRecycle() {
    local start=$1
    local end=$2
    if [[ "$start" = "" ]]; then
        ${DEL_EXEC} -rf ${RECYCLE_DIR}/*
    else
        [[ "$end" = "" ]] && end=$idx || end=$(expr $end + 1)
        while true; do
            # 遍历结束 start < end
            [[ $start -ge $end ]] && break
            # 检查文件夹是否存在
            [ -d ${RECYCLE_DIR}/$start ] && ${DEL_EXEC} -rf ${RECYCLE_DIR}/$start
            # 计数器增加
            start=$(expr $start + 1)
        done
    fi
    return 0
}

# 还原回收站
function ResetRecycle() {
    local file=$1
    local start=$2
    local end=$3
    local isOk='N';

    [[ "$file" = "" ]] && echo "参数错误" && return
    [[ "$start" = "" ]] && start=0
    [[ "$end" = "" ]] && end=$idx || end=$(expr $end + 1)
    [ ${file:0:1} = "/" ] || file=$(realpath $file)
    if [ -e "$file" ]; then
       if [ ! -d "$file" ] || [ "$(ls -A $file)" != "" ];then
            echo "文件已存在，无法还原：$file"
            return
       fi
    fi
    echo -n "开始还原文件（$file [$start-$end]）?[Y/N]"
    read isOk
    [[ "$isOk" = "y" ]] && isOk='Y'
    [[ "$isOk" != "Y" ]] && echo "取消还原操作" && return

    local OLDIFS="$IFS"  #备份旧的IFS变量
    IFS=$'\n'   #修改分隔符为换行符
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束 start < end
        [[ $start -gt $idx ]] && break
        idx=`printf "%08d" ${idx}`
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/$idx ] && continue
        # 检查文件
        [ ! -e ${RECYCLE_DIR}/${idx}${file} ] && continue
        # 还原文件
        cd ${RECYCLE_DIR}/$idx
        for p in $(find .${file}); do
            # 跳过文件夹
            [ -d $p ] && continue
            p=${p:1}
            # 检查文件是否已存在
            [ -e "${p}" ] && continue
            echo "还原 $idx: ${p}"
            local t_dir=$(dirname $p)
            [ ! -d $t_dir ] && mkdir -p "$t_dir"
            # 移动文件
            mv -n ".${p}" "${p}"
        done
        cd ${RECYCLE_DIR}
    done
    # 删除所有空的目录
    find ${RECYCLE_DIR}/ -type d -empty -delete
    IFS="$OLDIFS"  #还原IFS变量
    return 0
}

# 列出回收站文件
function ListRecycle()
{
    local file=$1
    local start=$2
    local end=$3
    local depth=$4
    
    [[ "$file" = "" ]] && echo "参数错误" && return
    [[ "$start" = "" ]] && start=0
    [[ "$end" = "" ]] && end=$idx || end=$(expr $end + 1)
    [[ ${file:0:1} = "/" ]] || file=$(realpath $file)
    [[ "$depth" = "" ]] && depth=32767
    local OLDIFS="$IFS"  #备份旧的IFS变量
    IFS=$'\n'   #修改分隔符为换行符
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束 start < end
        [[ $start -gt $idx ]] && break
        idx=`printf "%08d" ${idx}`
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/$idx ] && continue
        # 检查文件
        [ ! -e ${RECYCLE_DIR}/${idx}${file} ] && continue
        # 还原文件
        cd ${RECYCLE_DIR}/$idx
        for p in $(find .${file} -maxdepth ${depth}); do
            p=${p:1}
            echo "[$idx]: ${p}"
        done
        cd ${RECYCLE_DIR}
    done
    IFS="$OLDIFS"  #还原IFS变量
}

# 检查功能
function CheckFun() {
    local fun=$1
    case "$fun" in
    "-clean")
        echo -n "清空回收站($(du -sh ${RECYCLE_DIR} | awk '{print $1}'))[Y/N]:"
        read fun
        if [[ "$fun" = "y" ]] || [[ "$fun" = "Y" ]]; then
            CleanRecycle $2 $3
            echo "清空回收站完成"
        fi
        _flag="end"
        ;;
    "-help" | "--help")
        echo "实现回收站功能 1.0"
        echo "替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm"
        echo "回收站路径            : ${RECYCLE_DIR}"
        echo "回收站已用大小        : $(du -sh ${RECYCLE_DIR} | awk '{print $1}') [$(ls ${RECYCLE_DIR} | wc -l)]"
        echo "移动文件夹到回收站    :"
        echo "	rm xxx xxxx"
        echo "	rm -rf xxx/* xxx/*"
        echo "	rm -rf ../xxx ../xxx"
        echo "清空回收站            : rm -clean [start] [end]"
        echo "还原文件              : rm -reset 文件(夹) [start] [end]"
        echo "查看回收站文件        : rm -list 文件(夹) [start] [end] [深度]"
        _flag="end"
        ;;
    "-reset")
        ResetRecycle $2 $3 $4
        _flag="end"
        ;;
    "-list")
        ListRecycle $2 $3 $4 $5
        _flag="end"
    ;;
    *)
        return 0
        ;;
    esac
}

if [ ! -x $DEL_EXEC ]; then
    echo "找不到删除程序：rm" >&2
    exit 1
fi

# 检查回收站是否存在
if [ ! -d ${RECYCLE_DIR} ]; then
    mkdir -p ${RECYCLE_DIR}
fi
# 获取索引
idx=$(ls ${RECYCLE_DIR} | sort -r | head -n 1)
if [[ "$idx" = "" ]]; then
    DIR=`printf "%08d" 0`
else
    idx=$(( 10#$idx )) # 去除前面的0
    DIR=`printf "%08d" ${idx}`
    if [ "$(ls -A ${RECYCLE_DIR}/$DIR)" != "" ]; then
        idx=$(expr $idx + 1)
        DIR=`printf "%08d" $idx`
    fi
fi
DIR=${RECYCLE_DIR}/$DIR

# 创建回收站文件夹
mkdir -p $DIR
for arg in "$@"; do
    if [[ ${arg:0:1} = "-" ]];then
        _flag=$arg
        CheckFun $arg $2 $3 $4 $5
        [[ "$_flag" = "end" ]] && break
    else
        # 获取绝对路径
        file=$(realpath $arg)
        [ ! -e "$file" ] && continue
        DeleteFile $DIR $file
    fi
done
# 删除空的文件夹
DeleteEmpty $DIR
exit 0
# ------------------------------------------ END ------------------------------------------
