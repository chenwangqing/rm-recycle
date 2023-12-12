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
实现回收站功能 1.0
替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm
回收站路径            : /root/.recycle
回收站已用大小        : 190M [210]
移动文件夹到回收站    :
        rm xxx xxxx
        rm -rf xxx/* xxx/*
        rm -rf ../xxx ../xxx
清空回收站            : rm -clean [start] [end]
还原文件              : rm -reset 文件(夹) [start] [end]
查看回收站文件        : rm -list 文件(夹) [start] [end] [深度]
```

### 2.回收站结构

```sh
# ls -lh /root/.recycle
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

每进行一次rm操作就会创建一个删除文件的快照
