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

# --------------------------------------------------------------------------------
#                               | 日志操作 |
# --------------------------------------------------------------------------------

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

# --------------------------------------------------------------------------------
#                                   | 锁 |
# --------------------------------------------------------------------------------

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
    local str=$1
    local sql_file=/dev/shm/.recycle.$$.sql
    [[ $str == "" ]] && return 1
    # echo "[SQL] $str" >>$RECYCLE_LOG
    # 参数太多就只能写到文件在执行
    [[ ${#str} -gt 65536 ]] && echo "$str" >$sql_file && str=""
    Lock $_LOCK_SQL
    if [[ "$str" != "" ]]; then
        sqlite3 ${RECYCLE_DIR}/infos.db "$str"
    else
        sqlite3 ${RECYCLE_DIR}/infos.db <$sql_file
        $DEL_EXEC -rf $sql_file
    fi
    local ret=$?
    UnLock $_LOCK_SQL
    return $ret
}

# 创建数据库
function SQL_CreateDB() {
    local cmd="CREATE TABLE IF NOT EXISTS info (
            [id] INTEGER PRIMARY KEY AUTOINCREMENT,
            [uuid] CHAR(32) NOT NULL,
            [type] CHAR(1)  NOT NULL,
            [time] INTEGER,
            [name] TEXT NOT NULL
        );"
    SQL_Exec "$cmd"
    return $?
}

# 搜索文件  /xx/xx/
function SQL_Search_time_files() {
    local ts=$1
    local te=$2
    local name=$3
    local isAbroad=$4 # 广泛
    local limit=$((10#${Pars["n"]}))
    IFS=$';' #修改分隔符
    local filter=(${Pars["filter"]})
    local nfilter=(${Pars["!filter"]})
    [[ $limit -ne 0 ]] && limit="LIMIT $limit" || limit=""
    local file=$name
    if [[ "${name:0-1:1}" = "/" ]]; then
        local n=${#name}
        n=$((n - 1))
        file=${name:0:$n}
    fi
    local str=""
    if [[ ${#filter[@]} -ne 0 ]]; then
        for p in ${filter[@]}; do
            [[ $str != "" ]] && str+=" or "
            str+="name like '$p'"
        done
        str="and ($str) "
    fi
    if [[ ${#nfilter[@]} -ne 0 ]]; then
        local s=""
        for p in ${nfilter[@]}; do
            [[ $s != "" ]] && s+=" or "
            s+="name like '$p'"
        done
        str+="and not ($s) "
    fi
    [ -v Pars['od'] ] && str+="and type='d' " # 只显示文件夹
    if [[ "$isAbroad" = "" ]]; then
        local cmd="SELECT uuid,time,name FROM info WHERE id in (SELECT max(id) as id FROM info WHERE 
            (name like \"$name%\" or name = \"$file\")
            and time >= $ts 
            and time <= $te 
            $str
            GROUP BY name) ORDER BY id DESC $limit;"
        SQL_Exec "$cmd"
    else
        # 广泛
        local cmd="SELECT uuid,time,name FROM info WHERE 
            (name like \"$name%\" or name = \"$file\")
            and time >= $ts 
            and time <= $te 
            $str;"
        SQL_Exec "$cmd"
    fi
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

# 删除uuid
function SQL_DeleteToUuids() {
    local uuids=$1
    SQL_Exec "DELETE FROM info WHERE uuid in ($uuids);"
    return $?
}

# 获取记录数量
function SQL_GetCount() {
    SQL_Exec "SELECT count(*) FROM info;"
    return $?
}

# 检查uuid
function CheckUuid() {
    local uuid=$1
    [ ! -e "$DIR_STORAGE/$uuid" ] && SQL_DeleteToUuid $uuid
    return 0
}

# --------------------------------------------------------------------------------
#                                | 文件操作 |
# --------------------------------------------------------------------------------

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
function DeleteFiles() {
    IFS=$'\n' #修改分隔符为换行符
    strs=(${Pars["-"]})
    local uuids=()
    local files=()
    local cmd=""
    # 获取当前时间戳
    local time=$(date +%s)
    Pars["-"]=""
    [[ "$time" = "" ]] && echo "获取时间失败: $file" && return 1
    # 生成列表
    for p in ${strs[@]}; do
        # 获取绝对路径
        file=$(realpath "$p" 2>>$RECYCLE_LOG)
        echo "$p => ${file}" >>$RECYCLE_LOG
        [ ! -e "$file" ] && LOG_WARN "文件不存在: $file" && continue
        # 检查文件夹是否可以删除
        local type='f'
        [ -d $file ] && type='d' && ! $is_del_dir && LOG_WARN "文件夹无法删除: $file" && continue
        # 检查文件是否保护
        local ret=$(CheckFile $file)
        [[ "$ret" != "Ok" ]] && LOG_ERROR "$file: 文件保护" && continue
        local f_dir=$(dirname $file)
        if [[ "$f_dir" =~ ^$_RECYCLE_DIR.* ]]; then
            $DEL_EXEC -rf $file # 删除回收站文件
        else
            # 可以删除
            # 获取uuid
            local uuid=$(cat /proc/sys/kernel/random/uuid)
            uuid=${uuid//-/}
            uuids+=("$uuid")
            files+=("$file")
            # 生成插入命令
            [[ $cmd != "" ]] && cmd+=","
            cmd+="('$uuid','$type',$time,'$file')"
        fi
    done
    [[ $cmd = "" ]] && exit 0
    cmd="INSERT INTO info (uuid, type, time, name) VALUES $cmd;"
    # 批量插入
    ! SQL_Exec "$cmd" && LOG_ERROR "sqlite3 执行失败！" && exit 1
    cmd=""
    # 执行删除
    local count=${#uuids[@]}
    local i=0
    local del_uuids=""
    while [[ $i -lt $count ]]; do
        local uuid=${uuids[$i]}
        local file=${files[$i]}
        i=$((i + 1))
        if [ ! -e "$file" ]; then
            # 记录需要删除的uuid
            [[ "$del_uuids" != "" ]] && del_uuids+=","
            del_uuids+="'$uuid'"
            LOG_WARN "文件不存在: $file"
            continue
        fi
        # 移动到存储区
        echo "mv $file -> $DIR_STORAGE/$uuid" >>$RECYCLE_LOG
        mv -f "$file" "$DIR_STORAGE/$uuid"
        [[ $? -ne 0 ]] && echo "移动文件失败: $file" && exit 1
    done
    [[ "$del_uuids" != "" ]] && SQL_DeleteToUuids "$del_uuids"
    exit 0
}

# 清空文件夹
function CleanRecycle() {
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))
    local uuids=${Pars["uuid"]}
    local isOk=false
    local files=""
    local idx=0

    if [[ "$uuids" = "" ]]; then
        if [[ $st -ge 0 ]] && [[ $et -ge $(date +%s) ]] && [[ "$file" = "" ]]; then
            echo -n "将清空整个回收站[Y/N]:"
            read isOk
            [[ "$isOk" != "y" ]] && [[ "$isOk" != "Y" ]] && echo "取消操作" && exit 0
            # 删除所有
            $DEL_EXEC -rf "${RECYCLE_DIR}/storage" "${RECYCLE_DIR}/view" "${RECYCLE_DIR}/infos.db"
            exit 0
        fi
        [[ "$file" = "" ]] && file="/"
        [ ${file:0:1} = "/" ] || file=$(realpath "$file")
        echo "[$st - $et] $file:"
        printf "正在搜索文件 ... \r"
        files=$(SQL_Search_time_files $st $et "$file" 1)
    else
        printf -e "正在搜索文件 ... \r"
        files=$(SQL_Search_uuids "$uuids")
    fi

    idx=0
    IFS=$'\n' #修改分隔符为换行符
    for p in $files; do
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        local ret=$(du -sh "$DIR_STORAGE/$uuid" 2>/dev/null | awk '{print $1}')
        [[ "$ret" = "" ]] && continue
        printf "%-8s %s %s %s\n" "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') $uuid "$file"
        idx=$((idx + 1))
        [[ $idx -gt 10 ]] && echo "..." && break
    done

    local count=$(echo $files | grep -v "^$" | wc -l)
    [[ $count -eq 0 ]] && echo "没有找到文件" && exit 0

    echo -n "清理回收站[Y/N]:"
    read isOk
    [[ "$isOk" != "y" ]] && [[ "$isOk" != "Y" ]] && echo "取消操作" && exit 0

    idx=0
    local uuids=""
    IFS=$'\n' #修改分隔符为换行符
    for p in $files; do
        idx=$((idx + 1))
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        local n=${#file}
        [[ $n -gt 80 ]] && n=80
        printf " [$idx/$count]正在删除: ${file:0-$n:$n}\r"
        [ -e "$DIR_STORAGE/$uuid" ] && $DEL_EXEC -rf "$DIR_STORAGE/$uuid"
        [[ $uuids != "" ]] && uuids+=","
        uuids+="'$uuid'"
        if [[ ${#uuids} -gt 1024 ]]; then
            SQL_DeleteToUuids "$uuids"
            uuids=""
        fi
    done
    [[ "$uuids" != "" ]] && SQL_DeleteToUuids "$uuids"
    echo ""
    echo "回收站清理完成！"
    exit 0
}

# 还原回收站
function ResetRecycle() {
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))
    local uuids=${Pars["uuid"]}
    local isOk=false
    local files=

    if [[ "$uuids" = "" ]]; then
        [[ "$file" = "" ]] && echo "参数错误" && exit 1
        [ ${file:0:1} = "/" ] || file=$(realpath "$file")
        if [ -e "$file" ] && [ ! -d "$file" ]; then
            echo "文件已存在，无法还原：$file" >&2
            exit 1
        fi
        echo "[$st - $et] $file:"
        echo -e "正在搜索文件 ... \r"
        files=$(SQL_Search_time_files $st $et "$file")
    else
        echo -e "正在搜索文件 ... \r"
        files=$(SQL_Search_uuids "$uuids")
    fi

    local list=()
    local uuids=()
    IFS=$'\n' #修改分隔符为换行符
    for p in $files; do
        IFS=$'|'
        local strs=($p)
        [[ ${#strs[@]} -ne 3 ]] && continue
        local uuid=${strs[0]}
        local time=${strs[1]}
        local file=${strs[2]}
        local ret=$(du -sh "$DIR_STORAGE/$uuid" 2>/dev/null | awk '{print $1}')
        [[ "$ret" = "" ]] && CheckUuid $uuid && continue
        printf "%-8s %s %s %s\n" "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') $uuid "$file"
        list+=("$file")
        uuids+=("$uuid")
    done

    local count=${#list[@]}

    # 执行还原
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
                [ -e "$dst" ] && LOG_WARN " [$i/$count]文件存在: $dst" && continue # 文件已存在
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
            [ -e "$p" ] && LOG_WARN " [$i/$count]文件存在: $p" && continue # 文件已存在
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

# 4 => 4K 1024 => 1M
function NumberToStr() {
    local size=$1 # KB
    local zs=$size
    local xs=0
    local flag="K"
    if [[ $size -gt 1048576 ]]; then # GB
        zs=$((size / 1048576))
        xs=$(((size % 1048576) * 1000 / 1048576))
        flag="G"
    elif [[ $size -gt 1024 ]]; then # MB
        zs=$((size / 1024))
        xs=$(((size % 1024) * 1000 / 1024))
        flag="M"
    fi
    echo $zs.$xs$flag
    return 0
}

# 4.0K => 4 1M => 1024
function StrToNumber() {
    local str=$1
    local str_len=${#str}
    str_len=$((str_len - 1))
    [[ $str_len -le 0 ]] && echo $str && return 0
    local flag=${ret:0-1:1}
    str=${ret:0:$str_len}
    local zs=$str
    local xs=0
    if [[ $str =~ \. ]]; then
        zs=${str%.*}
        xs=${str#*.}
    fi
    local sz=1
    local _sz=1
    if [[ "$flag" = "G" ]]; then
        sz=1048576
        _sz=1024
    elif [[ "$flag" = "M" ]]; then
        sz=1024
        _sz=1
    fi
    echo $((zs * sz + xs * _sz))
    return 0
}

function ListRecycle() {
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))
    local size=0

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
        local ret=$(du -sh "$DIR_STORAGE/$uuid" 2>/dev/null | awk '{print $1}')
        [[ "$ret" = "" ]] && CheckUuid $uuid && continue
        printf "%-8s %s %s %s\n" "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') "$uuid" "$file"
        size=$(expr $(StrToNumber $ret) + $size)
    done
    echo "总大小：$(NumberToStr $size)"
    exit 0
}

# 回收站历史
function HistoryRecycle() {
    IFS=$'\n'
    local file=${Pars["-"]}
    local st=$((10#${Pars["st"]}))
    local et=$((10#${Pars["et"]}))
    local idx=0
    local size=0

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
        local ret=$(du -sh "$DIR_STORAGE/$uuid" 2>/dev/null | awk '{print $1}')
        [[ "$ret" = "" ]] && CheckUuid $uuid && continue
        printf "%-4d %-8s %s  %s\n" $idx "$ret" $(date -d @$time '+%Y-%m-%d %H:%M:%S') $uuid
        size=$(expr $(StrToNumber $ret) + $size)
        idx=$((idx + 1))
    done
    echo "总大小：$(NumberToStr $size)"
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
    local idx=0
    local _t=$(date +%s)
    local _count=0

    local list=
    if [[ "$uuids" = "" ]]; then
        [[ "$file" = "" ]] && file="/"
        [[ ${file:0:1} = "/" ]] || file=$(realpath "$file")
        echo "[$st - $et] $file:"
        list=$(SQL_Search_time_files $st $et "$file")
    else
        list=$(SQL_Search_uuids $uuids)
        file="/"
    fi

    Lock $_LOCK_VIEW
    [ -e "$dir_view/$file" ] && $DEL_EXEC -rf "$dir_view/$file"
    count=$(echo $list | grep -v "^$" | wc -l)
    idx=0
    IFS=$'\n' #修改分隔符为换行符
    for p in $list; do
        IFS=$'|'
        local strs=($p)
        idx=$((idx + 1))
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
                    printf " [%d/%d]正在生成视图: %-80.80s\r" $idx $count ${dst:0-$n:$n}
                else
                    echo "$uuid -> $file$fs"
                fi
                ln "$DIR_STORAGE/$uuid$fs" "$dst"
                [[ $? -ne 0 ]] && LOG_ERROR " 移动文件失败: $dst" && continue
                _count=$((_count + 1))
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
                printf " [%d/%d]正在生成视图: %-80.80s\r" $idx $count ${dst:0-$n:$n}
            else
                echo "$uuid -> $file"
            fi
            ln "$DIR_STORAGE/$uuid" "$dst"
            [[ $? -ne 0 ]] && LOG_ERROR " 移动文件失败: $dst" && continue
            _count=$((_count + 1))
        fi
    done
    UnLock $_LOCK_VIEW
    echo ""
    echo "生成视图完成：用时 $(expr $(date +%s) - $_t) s 生成 $_count 个文件 $dir_view"
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
        echo "实现回收站功能 2.0"
        echo "替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm"
        echo "回收站路径            : ${RECYCLE_DIR}"
        echo "移动文件夹到回收站    :"
        echo "	rm xxx xxxx"
        echo "	rm -rf xxx/* xxx/*"
        echo "  rm -rf ../xxx ../xxx"
        echo "公共参数              :"
        echo "  只显示文件夹 -od"
        echo "  起始时间     -st=2019-1-1  -st=18:00:00 -st=2019-1-1T18:00:00"
        echo "  结束时间     -st=2019-1-1  -st=18:00:00 -st=2019-1-1T18:00:00"
        echo "  uuid列表     -uuid=xxx,xxx,...,xxx (权限最高)"
        echo "  输出数据数量 -n=3"
        echo "  过滤器       -filter=过滤表达式1;过滤表达式2;...;"
        echo "  反向过滤     -!filter=过滤表达式1;过滤表达式2;...;"
        echo "                 %            代替一个或多个字符"
        echo "                 _            仅代替一个字符"
        echo "                 [char list]  字符列中任何一个字符"
        echo "                 [^char list] 不在字符列中的任何一个字符"
        echo "查看回收站文件        : rm -list 文件/夹 [-st] [-et] [-n] [-od]"
        echo "查看文件历史          : rm -hist 文件/夹 [-st] [-et] [-n]"
        echo "更新回收站视图        : rm -show [文件/夹] [-uuid] [-st] [-et] [-n]"
        echo "还原文件              : rm -reset [文件/夹] [-uuid] [-st] [-et]"
        echo "清理回收站            : rm -clean [文件/夹] [-uuid] [-st] [-et] [-filter]"
        echo "直接删除              : rm -del [文件(夹)]"
        printf " 正在获取回收站大小...\r"
        echo "回收站已用大小        : $(du -sh ${RECYCLE_DIR} | awk '{print $1}') [$(SQL_GetCount)]"
    elif [ -v Pars["list"] ]; then
        ListRecycle
    elif [ -v Pars["hist"] ]; then
        HistoryRecycle
    elif [ -v Pars["show"] ]; then
        ShowView
    elif [ -v Pars["reset"] ]; then
        ResetRecycle
    elif [ -v Pars["clean"] ]; then
        CleanRecycle
    elif [ -v Pars["del"] ]; then
        # 删除文件
        IFS=$'\n' #修改分隔符为换行符
        strs=(${Pars["-"]})
        for p in ${strs[@]}; do
            # 获取绝对路径
            file=$(realpath "$p" 2>>$RECYCLE_LOG)
            echo "$p => ${file}" >>$RECYCLE_LOG
            [ ! -e "$file" ] && LOG_WARN "文件不存在: $file" && continue
            $DEL_EXEC -rf "$file"
        done
    else
        # 删除文件
        DeleteFiles
    fi
    exit 0
}

if [ ! -x $DEL_EXEC ]; then
    LOG_ERROR "找不到删除程序: $DEL_EXEC"
    exit 1
fi

[[ "$(type sqlite3)" = "" ]] && echo "请安装sqlite3" >&2 && exit 1

echo "-------------------------------- $(date) --------------------------------" >>$RECYCLE_LOG
echo "dir: $(pwd)" >>$RECYCLE_LOG
for arg in "$@"; do
    echo -n "$arg " >>$RECYCLE_LOG
    [[ $arg = "-f" ]] && is_Print=false
    [[ $arg = "-r" ]] && is_del_dir=true
    [[ $arg = "-rf" ]] || [[ $arg = "-fr" ]] && is_Print=false && is_del_dir=true
done
echo "" >>$RECYCLE_LOG

# 创建数据库
SQL_CreateDB

# 检查回收站路径
[ "${RECYCLE_DIR}" = "" ] && echo "回收站路径不能为空" >&2 && exit 1

# 检查存储路径
[ ! -d "$DIR_STORAGE" ] && mkdir -p "$DIR_STORAGE"

# 检查回收站是否存在
if [ ! -d ${RECYCLE_DIR} ]; then
    mkdir -p ${RECYCLE_DIR}
    [[ $? -ne 0 ]] && exit $?
fi

CheckFun "$@"
exit 0
# ------------------------------------------ END ------------------------------------------
