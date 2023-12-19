#! /bin/bash
#############################################################################################
# 名称：实现回收站功能
# 作者：chenxiangshu@outlook.com
# 日期：2023年12月11日
# ------------- 修改 -------------
# 1.0   2023年12月12日  创建
# 2.0   2023年12月19日  使用sqlite3作为数据管理工具
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
is_del_dir=false #是否删除文件夹
is_Print=true    # 显示

declare -A Pars # <k> "v1 \n v2 \n .."

_LOG_COLORS=('' '\033[33m' '\033[31m')
_LOG_NC='\033[0m'

[[ "$RM_LOG" != "ON" ]] && RECYCLE_LOG="/dev/null"

# 日志输出
function _log_out() {
    local level=$1
    local str=$2
    local line=${BASH_LINENO[1]}
    $is_Print && echo -e ${_LOG_COLORS[$level]}"[$line]"$str$_LOG_NC
    echo "[$line]"$str >>$RECYCLE_LOG
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

_LOCK_SQL=200  # 索引保护
_LOCK_VIEW=201 # 视图

_lockfiles=("/dev/shm/.recycle.data.lock" "/dev/shm/.recycle.view.lock")
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
            printf " [%d]rm 其它程序正在使用 PID: %s %-50.50s \r" $t $pid "$str"
        fi
    done
    # 获得锁
    echo $$ >$lockfile
    [[ $t -gt 0 ]] && $is_Print && printf "                                                                 \r"
    return
}

# 解锁
function UnLock() {
    local sn=$1
    # 释放锁
    flock -u $sn
    return
}

# --------------------------------------------------------------------------------
#                              | 数据库操作 |
# --------------------------------------------------------------------------------

function SQL_Exec() {
    Lock $_LOCK_SQL
    sqlite3 ${RECYCLE_DIR}/infos.db "$1"
    UnLock $_LOCK_SQL
    return $?
}

# 创建数据库
function SQL_CreateDB() {
    local cmd="CREATE TABLE IF NOT EXISTS info (
            [id] INTEGER PRIMARY KEY AUTOINCREMENT,
            [uuid] CHAR(32) NOT NULL,
            [time] INTEGER,
            [name] TEXT NOT NULL
        );"
    SQL_Exec "$cmd"
    return $?
}

# 添加数据点 【uuid】【时间戳】【文件名称】
function SQL_AddNode() {
    local uuid=$1
    local ts=$2
    local name=$3
    SQL_Exec "INSERT INTO info (uuid, time, name) VALUES ( \"$uuid\",$ts,\"$name\" );"
    return $?
}

# 搜索文件  /xx/xx/
function SQL_Search_time_files() {
    local ts=$1
    local te=$2
    local name=$3
    local limit=$((10#${Pars["n"]}))
    [[ $limit -ne 0 ]] && limit="LIMIT $limit" || limit=""
    local n=${#name}
    n=$((n - 1))
    local file=${name:0:$n}
    local cmd="SELECT uuid,time,name FROM info WHERE id in (SELECT max(id) as id FROM info WHERE 
            (name like \"$name%\" or name = \"$file\")
            and time >= $ts 
            and time <= $te 
            GROUP BY name) ORDER BY id DESC $limit;"
    SQL_Exec "$cmd"
    return $?
}

function SQL_Search_uuids() {
    IFS=$',' #修改分隔符
    local uuids=($1)
    local cmd="SELECT uuid,time,name FROM info WHERE uuid in ("
    for p in ${uuids[@]}; do
        [[ "${cmd:0-1:1}" != "(" ]] && cmd+=","
        cmd+="'$p'"
    done
    cmd+=");"
    SQL_Exec "$cmd"
    return $?
}

# 搜索文件历史
function SQL_Search_time_file_history() {
    local ts=$1
    local te=$2
    local name=$3
    local limit=$((10#${Pars["n"]}))
    [[ $limit -ne 0 ]] && limit="LIMIT $limit" || limit=""
    local cmd="SELECT uuid,time,name FROM info 
            WHERE name = \"$name\" 
            and time >= $ts 
            and time <= $te 
            ORDER BY id DESC $limit;"
    SQL_Exec "$cmd"
    return $?
}

# 删除uuid
function SQL_DeleteToUuid() {
    local uuid=$1
    SQL_Exec "DELETE FROM info WHERE uuid=\"$uuid\";"
    return $?
}

# 检查uuid
function CheckUuid() {
    local uuid=$1
    [ ! -e "$DIR_STORAGE/$uuid" ] && SQL_DeleteToUuid $uuid
    return 0
}

# 检查
function CheckFile() {
    local file=$1
    local ret=$(echo "$file" | awk -F '/' '{printf NF-1}') # 检查是否为根目录
    [[ "$ret" = "1" ]] && echo "Fail" && return
    for p in ${ProtectionList[@]}; do
        [[ "$file" = "$p" ]] && echo "Fail" && return
    done
    # 自身保护/防止自身本删除
    [[ $file =~ ^${RECYCLE_DIR}.* ]] && echo "Fail" && return
    echo "Ok"
}

DIR_STORAGE=${RECYCLE_DIR}/storage

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
        local storage=${RECYCLE_DIR}/storage
        local uuid=$(cat /proc/sys/kernel/random/uuid)
        uuid=${uuid//-/}
        # 获取当前时间戳
        local time=$(date +%s)
        [[ "$time" = "" ]] && echo "获取时间失败: $file" && return 1
        # 写入信息
        SQL_AddNode "$uuid" $time "$file"
        [[ $? -ne 0 ]] && echo "写入信息失败: $file" && return 1
        # 移动到存储区
        mv -f "$file" "$storage/$uuid"
        [[ $? -ne 0 ]] && echo "移动文件失败: $file" && return 1
    fi
    return
}

# 清空文件夹
function CleanRecycle() {
    local dir=""
    local file=$1
    local isOk=
    GetPars ${@:2}

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
        str+=" -name \"${p//<>/*}\""
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

Reset_list=()
Reset_uuids=()

function _ResetRecycle() {
    local list=$Reset_list
    local uuids=$Reset_uuids
    local count=${#list[@]}
    [[ $count -eq 0 ]] && LOG_PRINTF "没有需要还原的文件: $file" && return 0

    echo -n "开始还原?[Y/N]"
    read isOk
    [[ "$isOk" != "Y" ]] && [[ "$isOk" != "y" ]] && echo "取消还原操作" && exit 1

    IFS=$'\n' #修改分隔符为换行符
    local i=0
    while [[ $i -lt $count ]]; do
        local p=${list[$i]}
        local uuid=${uuids[$i]}
        i=$((i + 1))

        [ ! -e "$DIR_STORAGE/$uuid" ] && CheckUuid $uuid && continue

        if [ -d "$DIR_STORAGE/$uuid" ]; then
            cd "$DIR_STORAGE/$uuid"
            IFS=$'\n' #修改分隔符为换行符
            isOk=true
            for fs in $(find ./); do
                [ -d "$fs" ] && continue
                fs=${fs:1}
                local dst=$p$fs
                local dst_dir=$(dirname "$dst")
                [ -e "$dst" ] && continue # 文件已存在
                if [ ! -d "$dst_dir" ]; then
                    mkdir -p "$dst_dir" 2>/dev/null
                    [[ $? -ne 0 ]] && LOG_ERROR " 文件夹冲突: $(dirname $dst_dir)" && isOk=false && continue
                fi
                LOG_PRINTF " [$i/$count]正在还原: $dst"
                mv -f "$DIR_STORAGE/$uuid$fs" "$dst"
                [[ $? -ne 0 ]] && LOG_ERROR " 移动文件失败: $dst" && continue
            done
            ! $isOk && continue
        else
            [ -e "$p" ] && continue # 文件已存在
            LOG_PRINTF " [$i/$count]正在还原: $p"
            local dst_dir=$(dirname "$p")
            if [ ! -d "$dst_dir" ]; then
                mkdir -p "$dst_dir" 2>/dev/null
                [[ $? -ne 0 ]] && LOG_ERROR " 文件夹冲突: $dst_dir" && continue
            fi
            mv -f "$DIR_STORAGE/${uuid}" "$p"
            [[ $? -ne 0 ]] && LOG_ERROR " 移动文件失败: $p" && continue
        fi
        # 文件不存在，进行修正
        SQL_DeleteToUuid $uuid
    done
    exit 0
}

# 还原回收站
function ResetRecycle() {
    local file=$1
    local isOk='N'
    local pro=2
    local pro_str=""
    local OLDIFS="$IFS" #备份旧的IFS变量

    GetPars $2 $3

    [[ "$file" = "" ]] && echo "参数错误" && exit 1
    [ ${file:0:1} = "/" ] || file=$(realpath "$file")
    if [ -e "$file" ] && [ ! -d "$file" ]; then
        echo "文件已存在，无法还原：$file" >&2
        exit 1
    fi

    echo -e "正在搜索文件: $file\r"
    local list=()
    local uuids=()
    IFS=$'\n' #修改分隔符为换行符
    for p in $(SQL_Search_time_files $Pars_Start_Time $Pars_End_Time "$file"); do
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        local ret=$(du -sh "$DIR_STORAGE/$uuid" | awk '{print $1}' 2>/dev/null)
        [[ "$ret" = "" ]] && CheckUuid $uuid && continue
        printf "%-8s %s %s %s\n" "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') $uuid "$file"
        list+=("$file")
        uuids+=("$uuid")
    done

    # 执行还原
    Reset_list=$list
    Reset_uuids=$uuids
    _ResetRecycle
    exit 0
}

# 还原回收站
function ResetUuidRecycle() {
    GetParsUUID $@
    local cmd="SELECT name FROM info WHERE uuid in ("
    for p in ${Pars_UUIDS[@]}; do
        cmd+="\'%p\',"
    done
    cmd+=");"
    echo "$cmd"
    exit 0
    local res=$(SQL_Exec "$cmd")
}

function ListRecycle() {
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))

    [[ "$file" = "" ]] && echo "参数错误" && exit 1
    [[ ${file:0:1} = "/" ]] || file=$(realpath "$file")

    echo "[$st - $et] $file:"
    IFS=$'\n'
    printf "大小         删除时间                    UUID                 文件名称\n"
    for p in $(SQL_Search_time_files $st $et "$file"); do
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        local ret=$(du -sh "$DIR_STORAGE/$uuid" | awk '{print $1}' 2>/dev/null)
        [[ "$ret" = "" ]] && CheckUuid $uuid && continue
        printf "%-8s %s %s %s\n" "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') "$uuid" "$file"
    done
    exit 0
}

# 回收站历史
function HistoryRecycle() {
    IFS=$'\n'
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))
    local idx=0

    [[ "$file" = "" ]] && echo "参数错误" && exit 1
    [[ ${file:0:1} = "/" ]] || file=$(realpath "$file")

    echo "[$st - $et] $file:"
    printf " 序号 大小         删除时间        UUID\n"
    for p in $(SQL_Search_time_file_history $st $et "$file"); do
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        local ret=$(du -sh "$DIR_STORAGE/$uuid" | awk '{print $1}' 2>/dev/null)
        [[ "$ret" = "" ]] && CheckUuid $uuid && continue
        printf "%-4d %-8s %s  %s\n" $idx "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') $uuid
        idx=$((idx + 1))
    done
    exit 0
}

# 更新视图
function ShowView() {
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))
    local uuids=${Pars["uuid"]}
    local dir_view=${RECYCLE_DIR}/view
    local count=0

    local list=
    if [[ "$uuids" = "" ]]; then
        [[ "$file" = "" ]] && file="/"
        [[ ${file:0:1} = "/" ]] || file=$(realpath "$file")
        [ -e "$dir_view/$file" ] && $DEL_EXEC -rf "$dir_view/$file"
        echo "[$st - $et] $file:"
        list=$(SQL_Search_time_files $st $et "$file")
    else
        [ -e "$dir_view" ] && $DEL_EXEC -rf "$dir_view"
        list=$(SQL_Search_uuids $uuids)
    fi

    IFS=$'\n' #修改分隔符为换行符
    for p in $list; do
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        [ ! -e "$DIR_STORAGE/$uuid" ] && CheckUuid $uuid && continue

        if [ -d "$DIR_STORAGE/$uuid" ]; then
            cd "$DIR_STORAGE/$uuid"
            IFS=$'\n' #修改分隔符为换行符
            for fs in $(find ./); do
                [ -d "$fs" ] && continue
                fs=${fs:1}
                local dst=$dir_view$file$fs
                local dst_dir=$(dirname "$dst")
                [ -e "$dst" ] && continue # 文件已存在
                if [ ! -d "$dst_dir" ]; then
                    mkdir -p "$dst_dir" 2>/dev/null
                    [[ $? -ne 0 ]] && LOG_ERROR " 文件夹冲突: $dst_dir" && continue
                fi
                if [[ "$uuids" = "" ]]; then
                    local n=${#dst}
                    [[ $n -gt 80 ]] && n=80
                    printf " 正在生成视图: %-80.80s\r" ${dst:0-$n:$n}
                else
                    echo "$uuid -> $file$fs"
                fi
                ln "$DIR_STORAGE/$uuid$fs" "$dst"
                [[ $? -ne 0 ]] && LOG_ERROR " 移动文件失败: $dst" && continue
            done
        else
            local dst=$dir_view/$file
            local dst_dir=$(dirname "$dst")
            [ -e "$dst" ] && continue # 文件已存在
            if [ ! -d "$dst_dir" ]; then
                mkdir -p "$dst_dir" 2>/dev/null
                [[ $? -ne 0 ]] && LOG_ERROR " 文件夹冲突: $dst_dir" && continue
            fi
            if [[ "$uuids" = "" ]]; then
                local n=${#dst}
                [[ $n -gt 80 ]] && n=80
                printf " 正在生成视图: %-80.80s\r" ${dst:0-$n:$n}
            else
                echo "$uuid -> $file"
            fi
            ln "$DIR_STORAGE/$uuid" "$dst"
            [[ $? -ne 0 ]] && LOG_ERROR " 移动文件失败: $dst" && continue
        fi
    done
    echo ""
    exit 0
}

# 检查功能
function CheckFun() {
    local fun=$1
    # 获取参数
    Pars["-"]=""
    for p in "$@"; do
        if [[ "${p:0:1}" = "-" ]]; then
            p=${p:1}
            if [[ "$p" =~ = ]]; then
                key=${p%=*}
                p=${p##*=}
                echo "key: $key value: $p"
                Pars["$key"]="$p"
            else
                Pars["$p"]=""
            fi
        else
            [[ "${Pars["-"]}" != "" ]] && Pars["-"]+=$'\n'
            Pars["-"]+="$p"
        fi
    done

    # 参数检查
    str=${Pars["st"]} # 起始时间戳
    if [[ "$str" = "" ]]; then
        Pars["st"]="0"
    elif [[ $str =~ [-|:] ]]; then
        Pars["st"]="$(date -d $str +%s)"
    else
        echo "时间格式错误: $str"
        exit 1
    fi
    str=${Pars["et"]} # 结束时间戳
    if [[ "$str" = "" ]]; then
        Pars["et"]="$(date +%s -d '+1 day')"
    elif [[ $str =~ [-|:] ]]; then
        Pars["et"]="$(date -d $str +%s)"
    else
        echo "时间格式错误: $str"
        exit 1
    fi
    IFS=$',' #修改分隔符为换行符
    strs=(${Pars["uuid"]})
    for p in ${strs[@]}; do
        [[ ${#p} -ne 32 ]] && echo "UUID必须是32字节: $p" && exit 1
    done

    [ ! -v Pars["n"] ] && Pars["n"]="0"

    [ -v Pars["r"] ] && is_del_dir=true
    [ -v Pars["f"] ] && is_Print=false
    [ -v Pars["rf"] ] || [ -v Pars["fr"] ] && is_del_dir=true && is_Print=false

    if [ -v Pars["help"] ]; then
        echo "实现回收站功能 1.0"
        echo "替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm"
        echo "回收站路径            : ${RECYCLE_DIR}"
        printf " 正在获取回收站大小...\r"
        echo "回收站已用大小        : $(du -sh ${RECYCLE_DIR} | awk '{print $1}')"
        echo "移动文件夹到回收站    :"
        echo "	rm xxx xxxx"
        echo "	rm -rf xxx/* xxx/*"
        echo "  rm -rf ../xxx ../xxx"
        echo "公共参数              :"
        echo "  起始时间     -st=2019-1-1  -st=18:00:00 -st=2019-1-1T18:00:00"
        echo "  结束时间     -st=2019-1-1  -st=18:00:00 -st=2019-1-1T18:00:00"
        echo "  uuid列表     -uuid=xxx,xxx,...,xxx"
        echo "  输出数据数量 -n=3"
        echo "查看回收站文件        : rm -list 文件/夹 [-st] [-et] [-n]"
        echo "查看文件历史          : rm -hist 文件/夹 [-st] [-et] [-n]"
        echo "更新回收站视图        : rm -show [文件/夹] [-uuid] [-st] [-et] [-n]"
    elif [ -v Pars["list"] ]; then
        ListRecycle
    elif [ -v Pars["hist"] ]; then
        HistoryRecycle
    elif [ -v Pars["show"] ]; then
        ShowView
    else
        # 删除文件
        IFS=$'\n' #修改分隔符为换行符
        strs=(${Pars["-"]})
        for p in ${strs[@]}; do
            # 获取绝对路径
            file=$(realpath "$p" 2>>$RECYCLE_LOG)
            echo "$arg => ${file}" >>$RECYCLE_LOG
            [ ! -e "$file" ] && LOG_WARN "文件不存在: $file" && continue
            DeleteFile $file
        done
    fi
    exit 0

    case "$fun" in
    "-clean")
        CleanRecycle ${@:2}
        _flag="end"
        ;;
    "-help" | "--help")
        echo "实现回收站功能 1.0"
        echo "替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm"
        echo "回收站路径            : ${RECYCLE_DIR}"
        printf " 正在获取回收站大小...\r"
        echo "回收站已用大小        : $(du -sh ${RECYCLE_DIR} | awk '{print $1}')"
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
        echo "还原文件              : rm -reset-uuid [uuid1 ... [uuid..]]"
        echo "查看回收站文件        : rm -list 文件(夹) [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]"
        echo "查看文件历史          : rm -hist 文件(夹) [起始时间 2019-1-1T00:00:00] [结束时间 2019-1-2T23:59:59]"
        echo "更新回收站视图        : rm -show [文件(夹)] [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]"
        echo "删除回收站视图        : rm -delshow"
        echo "直接删除              : rm -del [文件(夹)]"
        _flag="end"
        ;;
    "-reset")
        ResetRecycle ${@:2}
        _flag="end"
        ;;
    "-reset-uuid")
        ResetUuidRecycle ${@:2}
        _flag="end"
        ;;
    "-list")
        ListRecycle ${@:2}
        _flag="end"
        ;;
    "-hist")
        HistoryRecycle ${@:2}
        ;;
    "-show")
        ShowView ${@:2}
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
        ClearRecycle ${@:2}
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

[[ "$(type sqlite3)" = "" ]] && echo "请安装sqlite3" >&2 && exit 1

# 创建数据库
SQL_CreateDB

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

# 检查存储路径
[ ! -d "$DIR_STORAGE" ] && mkdir -p "$DIR_STORAGE"

# 检查回收站是否存在
if [ ! -d ${RECYCLE_DIR} ]; then
    mkdir -p ${RECYCLE_DIR}
    [[ $? -ne 0 ]] && exit $?
fi

[[ "$idx_max" = "" ]] && idx_max=0
[[ "$idx_min" = "" ]] && idx_min=0

CheckFun "$@"

# # 预处理参数
# idx=0
# for arg in "$@"; do
#     idx=$((idx + 1))
#     [[ ${arg:0:1} != "-" ]] && continue
#     _flag=$arg
#     CheckFun ${@:$((idx))}
#     [[ "$_flag" = "end" ]] && exit 0
# done

# exit 0

# # 执行
# for arg in "$@"; do
#     if [[ ${arg:0:1} = "-" ]]; then
#         continue
#     elif [[ "$_flag" = "del" ]]; then
#         $DEL_EXEC -rf "$arg" # 直接删除
#     else
#         # 获取绝对路径
#         file=$(realpath "$arg" 2>>$RECYCLE_LOG)
#         echo "$arg => ${file}" >>$RECYCLE_LOG
#         [ ! -e "$file" ] && LOG_WARN "文件不存在: $file" && continue
#         DeleteFile $file
#     fi
# done
exit 0
# ------------------------------------------ END ------------------------------------------
