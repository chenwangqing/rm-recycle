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
DEL_EXEC=/usr/bin/rm   # 实际删除程序
ProtectionList=( # 保护文件夹列表
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
    /mnt/c
    /mnt/d
    /mnt/e
    /mnt/f
    /mnt/wsl
    /mnt/wslg
    # 自定义...
)
## ----------------------------------   END   ---------------------------------- ##

idx=1
_flag=' ' # 功能标志
_RECYCLE_DIR=$(realpath $RECYCLE_DIR)

# 检查
function CheckFile() {
    local file=$1
    local ret=$(echo "$file" | awk -F '/' '{printf NF-1}') # 检查是否为根目录
    [[ "$ret" = "1" ]] && echo "Fail" && return
    for p in ${ProtectionList[@]}; do
        [[ "$file" = "$p" ]] && echo "Fail" && return
    done
    # 自身保护/防止自身本删除
    # local base_dir=$(dirname $(realpath $0))
    # local dir=$(dirname $file)
    # [[ $base_dir =~ ^$dir.* ]] && echo "Fail" && return
    echo "Ok"
}

# 删除文件
function DeleteFile() {
    local dir_last=$1
    local dir_new=$2
    local file=$3
    # 检查文件是否保护
    local ret=$(CheckFile $file)
    [[ "$ret" != "Ok" ]] && echo "$file: 文件保护" && return
    local f_dir=$(dirname $file)
    if [[ "$f_dir" =~ ^$_RECYCLE_DIR.* ]]; then
        $DEL_EXEC -rf $file # 删除回收站文件
    else
        # 检查上一个存储点是否有空的位置
        if [[ "$dir_last" != "" ]] && [ ! -e "${dir_last}${file}" ]; then
            if [ ! -d "${dir_last}${f_dir}" ]; then
                # 创建文件夹
                mkdir -p "${dir_last}${f_dir}" 2>/dev/null
                [[ "$?" != "0" ]] && echo "文件夹创建失败: ${dir_last}${f_dir}" && return
            fi
            #echo mv -f "$file" "${dir_last}${f_dir}/"
            mv -f "$file" "${dir_last}${f_dir}/"
        else
            # 使用新的存储点
            if [ ! -d "${dir_new}${f_dir}" ]; then
                # 创建文件夹
                mkdir -p "${dir_new}${f_dir}" 2>/dev/null
                [[ "$?" != "0" ]] && echo "文件夹创建失败: ${dir_new}${f_dir}" && return
            fi
            #echo mv -f "$file" "${dir_new}${f_dir}/"
            mv -f "$file" "${dir_new}${f_dir}/"
            dir_last="" # 一旦使用新的存储就不能使用之前的
        fi
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
    local dir=""
    [[ "$start" = "" ]] && start=0
    [[ "$end" = "" ]] && end=$idx || end=$(expr $end + 1)
    start=$((10#$start))
    end=$((10#$end))

    if [[ "$start" = "" ]]; then
        ${DEL_EXEC} -rf ${RECYCLE_DIR}/*
    else
        while true; do
            # 遍历结束 start < end
            [[ $start -ge $end ]] && break
            # 检查文件夹是否存在
            dir=${RECYCLE_DIR}/snapshoot/$(printf "%010d" $start)
            [ -d $dir ] && ${DEL_EXEC} -rf $dir
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
    local isOk='N'
    local pro=2
    local pro_str=""
    local sum=$idx

    [[ "$file" = "" ]] && echo "参数错误" && return
    [[ "$start" = "" ]] && start=0
    [[ "$end" = "" ]] && end=$idx || end=$(expr $end + 1)
    [ ${file:0:1} = "/" ] || file=$(realpath $file)
    if [ -e "$file" ] && [ ! -d "$file" ]; then
        echo "文件已存在，无法还原：$file"
    fi
    start=$((10#$start))
    end=$((10#$end))
    sum=$(expr $end - $start)

    echo -n "开始还原文件（$file [$start-$end]）?[Y/N]"
    read isOk
    [[ "$isOk" = "y" ]] && isOk='Y'
    [[ "$isOk" != "Y" ]] && echo "取消还原操作" && return

    local OLDIFS="$IFS" #备份旧的IFS变量
    IFS=$'\n'           #修改分隔符为换行符
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 显示进度条
        v=$(expr $(expr $sum - $end + $start) \* 100 / $sum)
        while [[ $v -ge $pro ]]; do
            pro=$(expr $pro + 2)
            pro_str+="="
        done
        printf "[%-50s]%3d%%\r" $pro_str $v
        # 遍历结束 start < end
        [[ $start -gt $idx ]] && break
        idx=$(printf "%010d" ${idx})
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
        # 检查文件
        [ ! -e ${RECYCLE_DIR}/snapshoot/${idx}${file} ] && continue
        # 还原文件
        cd ${RECYCLE_DIR}/snapshoot/$idx
        if [ ! -d .${file} ]; then
            p=$file
            # 检查文件是否已存在
            [ -e "${p}" ] && break
            echo "还原 $idx: ${p}"
            local t_dir=$(dirname $p)
            if [ ! -d "$t_dir" ]; then
                # 文件夹不存在，创建文件夹
                mkdir -p "${t_dir}" 2>/dev/null
                [[ "$?" != "0" ]] && echo "文件夹创建失败: ${t_dir}" && exit 1
            fi
            # 移动文件
            mv -n ".${p}" "${p}"
            break
        else
            # 遍历文件夹
            for p in $(find .${file}); do
                # 跳过文件夹
                [ -d $p ] && continue
                p=${p:1}
                # 检查文件是否已存在
                [ -e "${p}" ] && continue
                echo "还原 $idx: ${p}"
                local t_dir=$(dirname $p)
                if [ ! -d "$t_dir" ]; then
                    # 文件夹不存在，创建文件夹
                    mkdir -p "${t_dir}" 2>/dev/null
                    [[ "$?" != "0" ]] && echo "文件夹创建失败: ${t_dir}" && continue
                fi
                # 移动文件
                mv -n ".${p}" "${p}"
                [[ "$?" != "0" ]] && echo "文件移动失败: ${p}" && continue
            done
        fi
    done
    # 删除所有空的目录
    find ${RECYCLE_DIR}/snapshoot -type d -empty -delete
    IFS="$OLDIFS" #还原IFS变量
    echo ""
    return 0
}

# 列出回收站文件
function ListRecycle() {
    local file=$1
    local start=$2
    local end=$3
    local depth=$4

    [[ "$file" = "" ]] && echo "参数错误" && return
    [[ "$start" = "" ]] && start=0
    [[ "$end" = "" ]] && end=$idx || end=$(expr $end + 1)
    [[ ${file:0:1} = "/" ]] || file=$(realpath $file)
    [[ "$depth" = "" ]] && depth=32767
    local OLDIFS="$IFS" #备份旧的IFS变量
    IFS=$'\n'           #修改分隔符为换行符
    start=$((10#$start))
    end=$((10#$end))
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束 start < end
        [[ $start -gt $idx ]] && break
        idx=$(printf "%010d" ${idx})
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
        # 检查文件
        [ ! -e ${RECYCLE_DIR}/snapshoot/${idx}${file} ] && continue
        # 还原文件
        cd ${RECYCLE_DIR}/snapshoot/$idx
        if [ ! -d .${file} ]; then
            echo "[$idx]: ${file}"
            break
        else
            for p in $(find .${file} -maxdepth ${depth}); do
                p=${p:1}
                echo "[$idx]: ${p}"
            done
        fi
    done
    IFS="$OLDIFS" #还原IFS变量
}

# 更新视图
function ShowView() {
    local file=$1
    local start=$2
    local end=$3
    local OLDIFS="$IFS" #备份旧的IFS变量
    local dir_view=${RECYCLE_DIR}/view
    local pro=2
    local pro_str=""
    local sum=$idx
    IFS=$'\n' #修改分隔符为换行符
    [[ "$start" = "" ]] && start=0
    [[ "$end" = "" ]] && end=$idx
    start=$((10#$start))
    end=$((10#$end))
    [[ $end > $sum ]] && end=$sum
    [[ "$file" = "" ]] && file="/"
    [[ ${file:0:1} = "/" ]] || file=$(realpath $file)
    [ -e "$dir_view/$file" ] && $DEL_EXEC -rf "$dir_view/$file"
    sum=$(expr $end - $start)
    echo "正在生成视图：$start - $end $file"
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 显示进度条
        v=$(expr $(expr $sum - $end + $start) \* 100 / $sum)
        while [[ $v -ge $pro ]]; do
            pro=$(expr $pro + 2)
            pro_str+="="
        done
        printf "[%-50s]%3d%%\r" $pro_str $v
        # 遍历结束 start < end
        [[ $start -gt $idx ]] && break
        idx=$(printf "%010d" ${idx})
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
        # 检查文件
        [[ "$file" != "/" ]] && [ ! -e ${RECYCLE_DIR}/snapshoot/${idx}${file} ] && continue
        # 遍历文件
        cd ${RECYCLE_DIR}/snapshoot/$idx
        if [ ! -d .${file} ]; then
            p=${file}
            if [ ! -e "${dir_view}${p}" ]; then
                dir=$(dirname $p)
                if [ ! -d "${dir_view}${dir}" ]; then
                    # 文件夹不存在 创建文件夹
                    mkdir -p "${dir_view}${dir}" 2>/dev/null
                    [[ "$?" != "0" ]] && echo "文件夹创建失败: ${dir_view}${dir}" && break
                fi
                ln ".$p" "${dir_view}${p}"
            fi
            break
        else
            for p in $(find .${file}); do
                # 跳过文件夹
                [ -d $p ] && continue
                p=${p:1}
                if [ ! -e "${dir_view}${p}" ]; then
                    dir=$(dirname $p)
                    if [ ! -d "${dir_view}${dir}" ]; then
                        # 文件夹不存在 创建文件夹
                        mkdir -p "${dir_view}${dir}" 2>/dev/null
                        [[ "$?" != "0" ]] && echo "文件夹创建失败: ${dir_view}${dir}" && continue
                    fi
                    ln ".$p" "${dir_view}${p}"
                fi
            done
        fi
    done
    IFS="$OLDIFS" #还原IFS变量
    echo ""
    return
}

# 查找快照
function FindSnapshoot() {
    local st=$1
    local se=$2
    local start=0
    local end=$idx
    local pro=2
    local pro_str=""
    local sum=$idx
    local snapshoot_start="-1"
    local snapshoot_end="-1"

    [[ "$st" = "" ]] && st="1970-1-1"
    [[ "$se" = "" ]] && se=$(date "+%Y-%m-%d" -d '+1 day')

    echo "开始查找：$st - $se ..."
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 显示进度条
        v=$(expr $(expr $sum - $end) \* 100 / $sum)
        while [[ $v -ge $pro ]]; do
            pro=$(expr $pro + 2)
            pro_str+="="
        done
        printf "[%-50s]%3d%%\r" $pro_str $v
        # 遍历结束 start < end
        [[ $start -gt $idx ]] && break
        idx=$(printf "%010d" ${idx})
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
        # 遍历文件
        cd ${RECYCLE_DIR}/snapshoot/$idx
        ret=$(find ./ -type f -newermt "$st" ! -newermt "$se" -print -quit)
        if [[ "$ret" = "" ]]; then
            [[ "$snapshoot_end" != "-1" ]] && break
            continue
        fi
        [[ "$snapshoot_end" = "-1" ]] && snapshoot_end=$idx
        snapshoot_start=$idx
    done
    echo ""
    echo "存储点: $snapshoot_start - $snapshoot_end"
    return
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
        echo "回收站已用大小        : $(du -sh ${RECYCLE_DIR} | awk '{print $1}')"
        echo "最大存储点            : $idx"
        echo "移动文件夹到回收站    :"
        echo "	rm xxx xxxx"
        echo "	rm -rf xxx/* xxx/*"
        echo "	rm -rf ../xxx ../xxx"
        echo "清空回收站            : rm -clean [起始存储点] [结束存储点]"
        echo "还原文件              : rm -reset 文件(夹) [起始存储点] [结束存储点]"
        echo "查看回收站文件        : rm -list 文件(夹) [起始存储点] [结束存储点] [深度]"
        echo "更新回收站视图        : rm -show [文件(夹)] [起始存储点] [结束存储点]"
        echo "删除回收站视图        : rm -delshow"
        echo "根据时间查找存储点    : rm -time [起始时间 2019-1-1T00:00:00] [结束时间 2019-1-2T23:59:59]"
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
    "-show")
        ShowView $2 $3 $4
        _flag="end"
        ;;
    "-delshow")
        [ -e "${RECYCLE_DIR}/view/$file" ] && $DEL_EXEC -rf "${RECYCLE_DIR}/view/$file"
        _flag="end"
        ;;
    "-time")
        FindSnapshoot $2 $3
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
    [[ "$?" != "0" ]] && exit $?
fi

# 获取索引
[ ! -f ${RECYCLE_DIR}/snapshoot.idx ] && echo 1 >${RECYCLE_DIR}/snapshoot.idx
idx=$(cat ${RECYCLE_DIR}/snapshoot.idx)
DIR_LAST=''
DIR_NEW=''
if [[ "$idx" = "" ]]; then
    DIR_NEW=$(printf "%010d" 0)
    DIR_LAST=$DIR_NEW
else
    idx=$((10#$idx)) # 去除前面的0
    dir=$(printf "%010d" ${idx})
    ret=""
    if [ -d ${RECYCLE_DIR}/snapshoot/$dir ]; then
        # 文件夹已存在,检查文件是否为空
        ret=$(ls -A ${RECYCLE_DIR}/snapshoot/$dir)
    fi
    if [[ "$ret" = "" ]]; then
        DIR_NEW=$(printf "%010d" $idx)
        idx=$(expr $idx - 1)
        DIR_LAST=$(printf "%010d" ${idx})
    else
        DIR_LAST=$(printf "%010d" ${idx})
        idx=$(expr $idx + 1)
        DIR_NEW=$(printf "%010d" $idx)
        echo $idx >${RECYCLE_DIR}/snapshoot.idx
    fi
fi
DIR_LAST=${RECYCLE_DIR}/snapshoot/$DIR_LAST
DIR_NEW=${RECYCLE_DIR}/snapshoot/$DIR_NEW

# 执行
for arg in "$@"; do
    if [[ ${arg:0:1} = "-" ]]; then
        _flag=$arg
        CheckFun $arg $2 $3 $4 $5
        [[ "$_flag" = "end" ]] && break
    else
        # 获取绝对路径
        file=$(realpath $arg)
        [ ! -e "$file" ] && continue
        DeleteFile $DIR_LAST $DIR_NEW $file
    fi
done
exit 0
# ------------------------------------------ END ------------------------------------------
