# Linux 回收站实现

用于避免误删除导致数据丢失

## 准备

方法1：在/etc/profile添加

```sh
alias rm="/bin/bash /home/rm-recycle/rm-recycle.sh"
```

方法2： 在/usr/local/bin创建软连接

```sh
ln -sf /home/rm-recycle/rm-recycle.sh /usr/local/bin/rm
```

并在/etc/profile添加环境变量

```sh
PATH=/usr/local/bin:$PATH
```

## 使用

### 1. 查看帮助

```sh
# rm -help
```
```
实现回收站功能 1.0
替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm
回收站路径            : /root/.recycle
回收站已用大小        : 2.1G
存储点                : 11 - 2630
移动文件夹到回收站    :
        rm xxx xxxx
        rm -rf xxx/* xxx/*
        rm -rf ../xxx ../xxx
清空回收站            : rm -clean [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]
清理回收站            : rm -clear 文件夹 文件表达式1;文件表达式2.. (<> 表示通配符)
  清理 后缀 .tmp 文件 rm -clear / "<>.tmp"
  清理 1.txt 文件     rm -clear / "1.txt"
  多个清理项目        rm -clear / "<>.tmp;1.txt;2.txt"
还原文件              : rm -reset 文件(夹) [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]
查看回收站文件        : rm -list 文件(夹) [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59] [深度]
更新回收站视图        : rm -show [文件(夹)] [起始存储点/起始时间 2019-1-1T00:00:00] [结束存储点/结束时间 2019-1-2T23:59:59]
删除回收站视图        : rm -delshow
直接删除              : rm -del [文件(夹)]
```

### 2.回收站结构

```sh
# ls -lh /root/.recycle/snapshoot
total 836K
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000000
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000001
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000002
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000003
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000004
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000005
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000006
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000007
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000008
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000009
drwxr-xr-x 3 root root 4.0K Dec 12 16:56 00000010
```

每进行一次rm操作就可能会创建一个删除文件的快照

### 3.回收站视图

为了更方便查看回收站内容可以通过一下目录生成回收站视图

```sh
rm -show
```

然后在/root/.recycle/view可以看到回收站内容

### 4.还原某个时间段删除的文件

```sh
rm -reset / 2023-1-1T12:00:00 2023-1-1T13:00:00
```

### 5.清理回收站的一些临时文件

```sh
rm -clear / "<>.o;<>.obj;<>.tmp;<>.i;<>.s;<>.tmp"
```
