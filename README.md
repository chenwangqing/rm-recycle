# Linux 回收站实现

用于避免误删除导致数据丢失

## 准备

安装 sqlite3

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
实现回收站功能 2.0
替代命令              : ln -s rm-recycle.sh /usr/local/bin/rm
回收站路径            : /root/.recycle
移动文件夹到回收站    :
  rm xxx xxxx
  rm -rf xxx/* xxx/*
  rm -rf ../xxx ../xxx
公共参数              :
  只显示文件夹 -od
  只显示大小   -os
  起始时间     -st=2019-1-1  -st=18:00:00 -st=2019-1-1T18:00:00
  结束时间     -st=2019-1-1  -st=18:00:00 -st=2019-1-1T18:00:00
  uuid列表     -uuid=xxx,xxx,...,xxx (权限最高)
  输出数据数量 -n=3
  过滤器       -F=过滤表达式1;过滤表达式2;...;
  反向过滤     -RF=过滤表达式1;过滤表达式2;...;
                 %            代替一个或多个字符
                 _            仅代替一个字符
                 [char list]  字符列中任何一个字符
                 [^char list] 不在字符列中的任何一个字符
查看回收站文件        : rm -list 文件/夹 [-st] [-et] [-n] [-od] [-os] [-F] [-RF]
查看文件历史          : rm -hist 文件/夹 [-st] [-et] [-n] [-os]
更新回收站视图        : rm -show [文件/夹[%]] [-uuid] [-st] [-et] [-n]
还原文件              : rm -reset [文件/夹] [-uuid] [-st] [-et]
清理回收站            : rm -clean [文件/夹] [-uuid] [-st] [-et] [-F] [-RF]
直接删除              : rm -del [文件(夹)]
添加忽略              : rm -ig-add '过滤表达式1' '过滤表达式2'
删除忽略              : rm -ig-del '过滤表达式1' '过滤表达式2'
查看忽略              : rm -ig-list
回收站已用大小        : 1.8G [2023-12-21T15:45:17 - 2023-12-21T16:14:29 10969]

```

### 2.回收站结构

```
ignore  : 忽略文件，不会移动到回收站
storage : 回收站数据存储
infos.db: 回收站信息存储
view    : 回收站视图
```

### 3.回收站视图

为了更方便查看回收站内容可以通过一下目录生成回收站视图

```sh
rm -show
```

然后在/root/.recycle/view可以看到回收站内容

### 4.还原某个时间段删除的文件

```sh
rm -reset /xxx -st=2023-1-1T12:00:00 -et=2023-1-1T13:00:00
```

### 5.清理回收站的一些临时文件

```sh
rm -clean /xxx -F="%.o;%.i;%.tmp;%.a;%.s"
```
