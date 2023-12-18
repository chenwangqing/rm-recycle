#! /bin/bash
#############################################################################################
# 名称：实现回收站功能
# 作者：chenxiangshu@outlook.com
# 日期：2023年12月11日
# ------------- 修改 -------------
# 1.0   2023年12月12日  创建
#############################################################################################

## ---------------------------------- 参数配置 ---------------------------------- ##
RECYCLE_DIR=~/.recycle              # 回收站路径
RECYCLE_LOG=/dev/shm/rm-recycle.log # 日志
DEL_EXEC=/usr/bin/rm                # 实际删除程序
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

set -f # 关闭通配符
idx_max=0
idx_min=0
_flag=' ' # 功能标志
_RECYCLE_DIR=$(realpath $RECYCLE_DIR)
Pars_Start_idx=
Pars_End_idx=
Pars_Start_Time=
Pars_End_Time=
is_del_dir=false #是否删除文件夹
is_Print=true    # 显示

_LOG_COLORS=('' '\033[33m' '\033[31m')
_LOG_NC='\033[0m'

[[ "$RM_LOG" != "ON" ]] && RECYCLE_LOG="/dev/null"

# 日志输出
function _log_out() {
    local level=$1
    local str=$2
    $is_Print && echo -e ${_LOG_COLORS[$level]}$str$_LOG_NC
    echo $str >>$RECYCLE_LOG
    return 0
}

# 日志输出
function LOG_PRINTF() {
    _log_out 0 "$@"
    return $?
}

function LOG_WARN() {
    _log_out 1 "$@"
    return $?
}

function LOG_ERROR() {
    _log_out 2 "$@"
    return $?
}

# 获取参数
function GetPars() {
    local s1=$1
    local s2=$2
    if [[ "$s1" = "" ]] || [[ "$s1" = "-" ]]; then
        Pars_Start_idx=$idx_min
    elif [[ "$s1" =~ [:|-] ]]; then
        Pars_Start_Time=$s1
    else
        Pars_Start_idx=$((10#$s1))
        [[ $Pars_Start_idx < $idx_min ]] && Pars_Start_idx=$idx_min
    fi
    if [[ "$s2" = "" ]] || [[ "$s2" = "-" ]]; then
        Pars_End_idx=$idx_max
    elif [[ "$s2" =~ [:|-] ]]; then
        Pars_End_Time=$s2
    else
        Pars_End_idx=$((10#$s2))
        [[ $Pars_End_idx -gt $idx_max ]] && Pars_End_idx=$idx_max
    fi
    if [[ "$Pars_Start_Time" != "" ]]; then
        [[ "$s2" != "" ]] && [[ ! "$Pars_End_Time" =~ [:|-] ]] && LOG_ERROR "时间格式错误: $s2" && exit 1
        [[ "$Pars_End_Time" = "" ]] && Pars_End_Time=$(date "+%Y-%m-%d" -d '+1 day')
    fi
    [[ "$Pars_Start_idx" != "" ]] && [[ "$Pars_End_idx" = "" ]] && Pars_End_idx=$idx_max
    [[ "$Pars_Start_idx" = "" ]] && Pars_Start_idx=$idx_min
    [[ "$Pars_End_idx" = "" ]] && Pars_End_idx=$idx_max
    # 时间格式
    [[ "$Pars_Start_Time" != "" ]] && Pars_Start_Time=$(date -d "$Pars_Start_Time" +'%Y-%m-%dT%H:%M:%S')
    [[ "$Pars_End_Time" != "" ]] && Pars_End_Time=$(date -d "$Pars_End_Time" +'%Y-%m-%dT%H:%M:%S')
    LOG_PRINTF " - RANG: [$Pars_Start_idx - $Pars_End_idx] [$Pars_Start_Time - $Pars_End_Time]"
    return
}

_LOCK_IDX=200  # 索引保护
_LOCK_VIEW=201 # 视图

_lockfiles=("/dev/shm/.recycle.idx.lock" "/dev/shm/.recycle.view.lock")
exec 200<>${_lockfiles[0]}
exec 201<>${_lockfiles[1]}

# 加锁 type number
function Lock() {
    local sn=$1
    local fd=$sn
    sn=$((sn - 200))
    # 获取锁文件
    local lockfile=${_lockfiles[$sn]}
    local t=0
    while true; do
        flock -w 1 $fd
        [[ "$?" = "0" ]] && break
        if $is_Print; then
            t=$(expr $t + 1)
            pid=$(cat $lockfile)
            str=$(tr -d '\0' </proc/$pid/cmdline 2>/dev/null)
            printf " [%d]rm 其它程序正在使用 PID: %s %s \r" $t $pid "$str"
        fi
    done
    # 获得锁
    echo $$ >$lockfile
    [[ $t -gt 0 ]] && $is_Print && printf "%50s\r" ""
    return
}

# 解锁
function UnLock() {
    local sn=$1
    # 释放锁
    flock -u $sn
    return
}

# 检查
function CheckFile() {
    local file=$1
    local ret=$(echo "$file" | awk -F '/' '{printf NF-1}') # 检查是否为根目录
    [[ "$ret" = "1" ]] && echo "Fail" && return
    for p in ${ProtectionList[@]}; do
        [[ "$file" = "$p" ]] && echo "Fail" && return
    done
    # 不回收临时文件
    [[ $file =~ ^/tmp/ ]] && echo "Fail" && return
    # 自身保护/防止自身本删除
    # local base_dir=$(dirname $(realpath $0))
    # local dir=$(dirname $file)
    # [[ $base_dir =~ ^$dir.* ]] && echo "Fail" && return
    echo "Ok"
}

# 删除文件
function DeleteFile() {
    local file=$1
    [ -d $file ] && ! $is_del_dir && LOG_WARN "文件夹无法删除: $file" && return
    # 检查文件是否保护
    local ret=$(CheckFile $file)
    [[ "$ret" != "Ok" ]] && LOG_ERROR "$file: 文件保护" && return
    local f_dir=$(dirname $file)
    if [[ "$f_dir" =~ ^$_RECYCLE_DIR.* ]]; then
        $DEL_EXEC -rf $file # 删除回收站文件
    else
        local isRun=true
        while $isRun; do
            local dir=${RECYCLE_DIR}/snapshoot/$(printf "%010d" ${idx_max})
            # 检查 存储点是否有空的位置
            if [ ! -e "${dir}${file}" ]; then
                # 可以存储
                if [ ! -d "${dir}${f_dir}" ]; then
                    # 检查max编号
                    Lock $_LOCK_IDX
                    if [[ $idx_max -gt $(cat ${RECYCLE_DIR}/snapshoot.max) ]]; then
                        # 写入索引
                        echo $idx_max >${RECYCLE_DIR}/snapshoot.max && sync -f ${RECYCLE_DIR}/snapshoot.max
                    fi
                    UnLock $_LOCK_IDX
                    # 创建文件夹
                    mkdir -p "${dir}${f_dir}" 2>/dev/null
                    [[ "$?" != "0" ]] && LOG_ERROR "文件夹创建失败: ${dir}${f_dir}" && exit 1
                fi
                echo "MOVE $file -> $dir_new" >>$RECYCLE_LOG
                mv -f "$file" "${dir}${f_dir}/"
                isRun=false
            else
                # 生成新一个编号
                idx_max=$((idx_max + 1))
            fi
        done
    fi
    return
}

# 修正信息
function FixInfo() {
    # 删除所有空的目录
    Lock $_LOCK_IDX
    find ${RECYCLE_DIR}/snapshoot -type d -empty -delete
    local start=$idx_min
    local end=$idx_max
    while [[ $start -lt $end ]]; do
        # 检查文件夹是否存在
        dir=${RECYCLE_DIR}/snapshoot/$(printf "%010d" $start)
        [ -d $dir ] && break
        start=$(expr $start + 1)
    done
    [[ $start -gt $end ]] && start=$end
    echo $start >${RECYCLE_DIR}/snapshoot.min && sync -f ${RECYCLE_DIR}/snapshoot.min
    UnLock $_LOCK_IDX
    return
}

# 清空文件夹
function CleanRecycle() {
    local dir=""
    local file=$1
    local isOk=
    GetPars $2 $3

    echo -n "清理回收站($file)[Y/N]:"
    read isOk
    [[ "$isOk" != "y" ]] && [[ "$isOk" != "Y" ]] && echo "取消操作" && exit 0

    local pro=2
    local pro_str=""
    local start=$idx_min
    local end=$idx_max
    local sum=$(expr $end - $start)
    local OLDIFS="$IFS" #备份旧的IFS变量
    IFS=$'\n'           #修改分隔符

    if [[ "$file" = "" ]]; then
        set +f
        ${DEL_EXEC} -rf ${RECYCLE_DIR}/*
    elif [[ "$Pars_Start_Time" != "" ]]; then
        while true; do
            # 计数器
            local idx=$end
            end=$(expr $end - 1)
            # 遍历结束
            [[ $start -gt $idx ]] && break
            # 显示进度条
            v=$(expr $(expr $sum - $idx + $start) \* 100 / $sum)
            idx=$(printf "%010d" ${idx})
            # 检查文件夹是否存在
            [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
            # 检查文件
            [ ! -e ${RECYCLE_DIR}/snapshoot/${idx}${dir} ] && continue
            cd ${RECYCLE_DIR}/snapshoot/$idx
            for p in $(find .${file} -newermt "$Pars_Start_Time" ! -newermt "$Pars_End_Time"); do
                [ -d $p ] && continue
                n=${#p} && [[ $n -gt 50 ]] && n=50
                printf "删除文件: %s %3d%% %-50.50s\r" $idx $v ${p:0-$n:$n}
                $DEL_EXEC -rf "$p"
            done
        done
        FixInfo
    elif [[ "$Pars_Start_idx" != "" ]]; then
        sum=$(expr $Pars_End_idx - $Pars_Start_idx)
        while true; do
            # 遍历结束
            [[ $Pars_Start_idx -gt $Pars_End_idx ]] && break
            v=$(expr $(expr $sum - $Pars_End_idx + $Pars_Start_idx) \* 100 / $sum)
            while [[ $v -ge $pro ]]; do
                pro=$(expr $pro + 2)
                pro_str+="="
            done
            idx=$(printf "%010d" ${Pars_Start_idx})
            printf " 正在清理: %s [%-50s] %3d%%\r" $idx $pro_str $v
            # 检查文件夹是否存在
            dir=${RECYCLE_DIR}/snapshoot/$idx/$file
            [ -e "$dir" ] && $DEL_EXEC -rf "$dir"
            # 计数器增加
            Pars_Start_idx=$(expr $Pars_Start_idx + 1)
        done
        FixInfo
    fi
    echo ""
    echo "回收站清理完成！"
    exit 0
}

# 清理回收站
function ClearRecycle() {
    local dir=$1
    local suffix=$2
    if [[ "$dir" = "" ]] || [[ "$suffix" = "" ]]; then
        echo "参数错误" >&2
        exit 1
    fi
    local pro=2
    local pro_str=""
    local start=$idx_min
    local end=$idx_max
    local sum=$(expr $end - $start)
    local str=""
    local OLDIFS="$IFS" #备份旧的IFS变量
    IFS=$';'            #修改分隔符
    for p in $suffix; do
        [[ "$str" != "" ]] && str+=" -o"
        str+=" -name \"${p/<>/*}\""
    done
    IFS=$OLDIFS
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束
        [[ $start -gt $idx ]] && break
        # 显示进度条
        v=$(expr $(expr $sum - $idx + $start) \* 100 / $sum)
        while [[ $v -ge $pro ]]; do
            pro=$(expr $pro + 2)
            pro_str+="="
        done
        idx=$(printf "%010d" ${idx})
        printf " 正在清理: %s [%-50s] %3d%%\r" $idx $pro_str $v
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
        # 检查文件
        [ ! -e ${RECYCLE_DIR}/snapshoot/${idx}${dir} ] && continue
        cd ${RECYCLE_DIR}/snapshoot/$idx
        # 删除后缀
        sh -c "find \".${dir}\" $str | xargs $DEL_EXEC -rf"
    done
    echo ""
    FixInfo
    exit 0
}

# 还原回收站
function ResetRecycle() {
    local file=$1
    local isOk='N'
    local pro=2
    local pro_str=""

    GetPars $2 $3

    [[ "$file" = "" ]] && echo "参数错误" && exit 1
    [ ${file:0:1} = "/" ] || file=$(realpath "$file")
    if [ -e "$file" ] && [ ! -d "$file" ]; then
        echo "文件已存在，无法还原：$file" >&2
        exit 1
    fi

    local start=$Pars_Start_idx
    local end=$Pars_End_idx
    local sum=$(expr $Pars_End_idx - $Pars_Start_idx)

    echo -n "开始还原文件（$file）?[Y/N]"
    read isOk
    [[ "$isOk" != "Y" ]] && [[ "$isOk" != "y" ]] && echo "取消还原操作" && exit 1

    local st=$(date +%s)
    local count=0
    local OLDIFS="$IFS" #备份旧的IFS变量
    IFS=$'\n'           #修改分隔符为换行符
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束
        [[ $start -gt $idx ]] && break
        # 显示进度条
        v=$(expr $(expr $sum - $idx + $start) \* 100 / $sum)
        while [[ $v -ge $pro ]]; do
            pro=$(expr $pro + 2)
            pro_str+="="
        done
        idx=$(printf "%010d" ${idx})
        printf " 正在还原: %s [%-50s] %3d%%\r" $idx $pro_str $v
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
            echo " 还原 $idx: ${p}"
            local t_dir=$(dirname $p)
            if [ ! -d "$t_dir" ]; then
                # 文件夹不存在，创建文件夹
                mkdir -p "${t_dir}" 2>/dev/null
                [[ "$?" != "0" ]] && LOG_ERROR "文件夹创建失败: ${t_dir}" && exit 1
            fi
            # 移动文件
            mv -n ".${p}" "${p}"
            count=$((count + 1))
            break
        else
            # 遍历文件夹
            if [[ "$Pars_Start_Time" != "" ]]; then
                files=$(find .${file} -newermt "$Pars_Start_Time" ! -newermt "$Pars_End_Time")
            else
                files=$(find .${file})
            fi
            for p in $files; do
                # 跳过文件夹
                [ -d $p ] && continue
                p=${p:1}
                # 检查文件是否已存在
                [ -e "${p}" ] && continue
                echo " 还原 $idx: ${p}"
                local t_dir=$(dirname $p)
                if [ ! -d "$t_dir" ]; then
                    # 文件夹不存在，创建文件夹
                    mkdir -p "${t_dir}" 2>/dev/null
                    [[ "$?" != "0" ]] && LOG_ERROR " [$idx]文件夹创建失败: ${t_dir}" && continue
                fi
                # 移动文件
                mv -n ".${p}" "${p}"
                [[ "$?" != "0" ]] && LOG_ERROR " [$idx]文件移动失败: ${p}" && continue
                count=$((count + 1))
            done
        fi
    done
    # 删除所有空的目录
    FixInfo
    IFS="$OLDIFS" #还原IFS变量
    echo ""
    echo "还原完成: $count 个文件用时 $(expr $(date +%s) - $st)s"
    exit 0
}

# 列出回收站文件
function ListRecycle_Print() {
    local p=$1
    local _OLDIFS="$IFS"
    IFS=" "
    str=$(ls -lh --time-style '+%Y-%m-%dT%H:%M:%S' "$p" | awk '{print $5,$6}')
    strs=($str)
    IFS=$_OLDIFS
    p=${p:1}
    printf "[%s]: %-6s %s %s\n" $idx ${strs[0]} ${strs[1]} "$p"
    return
}

function ListRecycle() {
    local file=$1
    local depth=$4

    GetPars $2 $3

    [[ "$file" = "" ]] && echo "参数错误" && exit 1
    [[ ${file:0:1} = "/" ]] || file=$(realpath "$file")
    [[ "$depth" = "" ]] && depth=32767

    local start=$Pars_Start_idx
    local end=$Pars_End_idx
    local OLDIFS="$IFS" #备份旧的IFS变量
    IFS=$'\n'           #修改分隔符为换行符
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束
        [[ $start -gt $idx ]] && break
        idx=$(printf "%010d" ${idx})
        # 检查文件夹是否存在
        [ ! -d ${RECYCLE_DIR}/snapshoot/$idx ] && continue
        # 检查文件
        [ ! -e ${RECYCLE_DIR}/snapshoot/${idx}${file} ] && continue
        # 还原文件
        cd ${RECYCLE_DIR}/snapshoot/$idx
        if [ ! -d .${file} ]; then
            ListRecycle_Print ".${file}"
        else
            if [[ "$Pars_Start_Time" != "" ]]; then
                files=$(find .${file} -maxdepth ${depth} -newermt "$Pars_Start_Time" ! -newermt "$Pars_End_Time")
            else
                files=$(find .${file} -maxdepth ${depth})
            fi
            for p in $files; do
                [ -d $p ] && continue
                ListRecycle_Print "$p"
            done
        fi
    done
    IFS="$OLDIFS" #还原IFS变量
    exit 0
}

# 更新视图
function ShowView() {
    local file=$1
    local OLDIFS="$IFS" #备份旧的IFS变量
    local dir_view=${RECYCLE_DIR}/view
    local st=$(date +%s)
    local count=0

    GetPars $2 $3
    Lock $_LOCK_VIEW

    [[ "$file" = "" ]] && file="/"
    [[ ${file:0:1} = "/" ]] || file=$(realpath "$file")
    [ -e "$dir_view/$file" ] && $DEL_EXEC -rf "$dir_view/$file"

    local start=$Pars_Start_idx
    local end=$Pars_End_idx
    local sum=$(expr $end - $start)
    IFS=$'\n' #修改分隔符为换行符
    while true; do
        # 计数器
        local idx=$end
        end=$(expr $end - 1)
        # 遍历结束
        [[ $start -gt $idx ]] && break
        # 计算进度
        v=$(expr $(expr $sum - $idx + $start) \* 100 / $sum)
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
                    [[ "$?" != "0" ]] && LOG_ERROR " [$idx]文件夹创建失败: ${dir_view}${dir}" && break
                fi
                n=${#p} && [[ $n -gt 50 ]] && n=50
                printf " 正在生成视图: %s %3d%% %-50.50s \r" $idx $v ${p:0-$n:$n}
                ln ".$p" "${dir_view}${p}"
                count=$((count + 1))
            fi
            break
        else
            if [[ "$Pars_Start_Time" != "" ]]; then
                files=$(find .${file} -newermt "$Pars_Start_Time" ! -newermt "$Pars_End_Time")
            else
                files=$(find .${file})
            fi
            for p in $files; do
                # 跳过文件夹
                [ -d $p ] && continue
                p=${p:1}
                if [ ! -e "${dir_view}${p}" ]; then
                    dir=$(dirname $p)
                    if [ ! -d "${dir_view}${dir}" ]; then
                        # 文件夹不存在 创建文件夹
                        mkdir -p "${dir_view}${dir}" 2>/dev/null
                        [[ "$?" != "0" ]] && LOG_ERROR " [$idx]文件夹创建失败: ${dir_view}${dir}" && continue
                    fi
                    n=${#p} && [[ $n -gt 50 ]] && n=50
                    printf " 正在生成视图: %s %3d%% %-50.50s \r" $idx $v ${p:0-$n:$n}
                    ln ".$p" "${dir_view}${p}"
                    count=$((count + 1))
                fi
            done
        fi
    done
    UnLock $_LOCK_VIEW
    IFS="$OLDIFS" #还原IFS变量
    echo ""
    echo " 生成视图结束: $count 个文件用时 $(expr $(date +%s) - $st)s"
    exit 0
}

# 检查功能
function CheckFun() {
    local fun=$1
    case "$fun" in
    "-clean")
        CleanRecycle $2 $3 $4
        _flag="end"
        ;;
    "-help" | "--help")
        echo "实现回收站功能 1.0"
        echo "替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm"
        echo "回收站路径            : ${RECYCLE_DIR}"
        printf " 正在获取回收站大小...\r"
        echo "回收站已用大小        : $(du -sh ${RECYCLE_DIR} | awk '{print $1}')"
        echo "存储点                : $idx_min - $idx_max"
        echo "移动文件夹到回收站    :"
        echo "	rm xxx xxxx"
        echo "	rm -rf xxx/* xxx/*"
        echo "	rm -rf ../xxx ../xxx"
        echo "清空回收站            : rm -clean [文件(夹)] [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]"
        echo "清理回收站            : rm -clear 文件(夹) 文件表达式1;文件表达式2.. (<> 表示通配符)"
        echo "  清理 后缀 .tmp 文件 rm -clear / \"<>.tmp\""
        echo "  清理 1.txt 文件     rm -clear / \"1.txt\""
        echo "  多个清理项目        rm -clear / \"<>.tmp;1.txt;2.txt\""
        echo "还原文件              : rm -reset 文件(夹) [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]"
        echo "查看回收站文件        : rm -list 文件(夹) [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59] [深度]"
        echo "更新回收站视图        : rm -show [文件(夹)] [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]"
        echo "删除回收站视图        : rm -delshow"
        echo "直接删除              : rm -del [文件(夹)]"
        echo ""
        echo "查看回收站大于10MB文件 : find ${RECYCLE_DIR}/snapshoot -type f -size +10M -exec du -h {} \;"
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
        Lock $_LOCK_VIEW
        [ -e "${RECYCLE_DIR}/view/$file" ] && $DEL_EXEC -rf "${RECYCLE_DIR}/view/$file"
        UnLock $_LOCK_VIEW
        _flag="end"
        ;;
    "-del")
        is_del_dir=true
        _flag="del"
        ;;
    "-clear")
        ClearRecycle $2 $3
        _flag="end"
        ;;
    *)
        return 0
        ;;
    esac
}

if [ ! -x $DEL_EXEC ]; then
    LOG_ERROR "找不到删除程序: $DEL_EXEC"
    exit 1
fi

echo "-------------------------------- $(date) --------------------------------" >>$RECYCLE_LOG
echo "dir: $(pwd)" >>$RECYCLE_LOG
for arg in "$@"; do
    echo -n "$arg " >>$RECYCLE_LOG
    [[ $arg = "-f" ]] && is_Print=false
    [[ $arg = "-r" ]] && is_del_dir=true
    [[ $arg = "-rf" ]] || [[ $arg = "-fr" ]] && is_Print=false && is_del_dir=true
done
echo "" >>$RECYCLE_LOG

# 检查回收站路径
[ "${RECYCLE_DIR}" = "" ] && echo "回收站路径不能为空" >&2 && exit 1

# 检查回收站是否存在
if [ ! -d ${RECYCLE_DIR} ]; then
    mkdir -p ${RECYCLE_DIR}
    [[ "$?" != "0" ]] && exit $?
fi

Lock $_LOCK_IDX # 保护索引
# 没有快照就清空回收站
[ ! -d ${RECYCLE_DIR}/snapshoot ] && $DEL_EXEC -rf ${RECYCLE_DIR}/*

# 获取索引
[ ! -f ${RECYCLE_DIR}/snapshoot.max ] && echo 0 >${RECYCLE_DIR}/snapshoot.max && sync -f ${RECYCLE_DIR}/snapshoot.max
[ ! -f ${RECYCLE_DIR}/snapshoot.min ] && echo 0 >${RECYCLE_DIR}/snapshoot.min && sync -f ${RECYCLE_DIR}/snapshoot.min
idx_max=$(cat ${RECYCLE_DIR}/snapshoot.max)
idx_min=$(cat ${RECYCLE_DIR}/snapshoot.min)

if [[ "$idx_max" = "" ]]; then
    idx_max=0
else
    idx=$((10#$idx_max)) # 去除前面的0
    dir=$(printf "%010d" ${idx})
    ret=""
    if [ -d ${RECYCLE_DIR}/snapshoot/$dir ]; then
        # 文件夹已存在,检查文件是否为空
        ret=$(ls -A ${RECYCLE_DIR}/snapshoot/$dir)
    fi
    if [[ "$ret" = "" ]]; then
        idx=$(expr $idx - 1)
    else
        idx_max=$(expr $idx + 1)
    fi
fi
UnLock $_LOCK_IDX

# 预处理参数
for arg in "$@"; do
    [[ ${arg:0:1} != "-" ]] && continue
    _flag=$arg
    CheckFun $arg $2 $3 $4 $5
    [[ "$_flag" = "end" ]] && exit 0
done

# 执行
for arg in "$@"; do
    if [[ ${arg:0:1} = "-" ]]; then
        continue
    elif [[ "$_flag" = "del" ]]; then
        $DEL_EXEC -rf "$arg" # 直接删除
    else
        # 获取绝对路径
        file=$(realpath "$arg" 2>>$RECYCLE_LOG)
        echo "$arg => ${file}" >>$RECYCLE_LOG
        [ ! -e "$file" ] && LOG_WARN "文件不存在: $file" && continue
        DeleteFile $file
    fi
done
exit 0
# ------------------------------------------ END ------------------------------------------
