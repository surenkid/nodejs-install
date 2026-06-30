#!/bin/bash
# Author: Jrohy
# Github: https://github.com/Jrohy/nodejs-install

# cancel centos alias
[[ -f /etc/redhat-release ]] && unalias -a

latest=0

force_mode=0

install_version=""

# 镜像源: 国内环境使用腾讯云, 海外使用官方源
NODEJS_OFFICIAL="https://nodejs.org/dist"
NODEJS_MIRROR="https://mirrors.cloud.tencent.com/nodejs-release"

# curl 超时: 连接 10s 内必须握上手, 避免某些网络"探测通但下载卡死"时无限挂起
CURL_CONNECT_TIMEOUT="--connect-timeout 10"
# 小文件 (index.json / SHASUMS) 总时长 30s, tarball 体积大给到 600s
CURL_SMALL_MAXTIME="--max-time 30"
CURL_LARGE_MAXTIME="--max-time 600"

#######color code########
red="31m"
green="32m"
yellow="33m"
blue="36m"
fuchsia="35m"

color_echo(){
    echo -e "\033[$1${@:2}\033[0m"
}

#######get params#########
while [[ $# > 0 ]];do
    case "$1" in
        -v|--version)
        install_version="$2"
        [[ $install_version && ${install_version:0:1} != "v" ]] && install_version="v$install_version"
        echo -e "准备安装$(color_echo ${blue} $install_version)版本nodejs..\n"
        shift
        ;;
        -f)
        force_mode=1
        echo -e "强制更新nodejs..\n"
        ;;
        -l)
        latest=1
        echo -e "准备安装最新当前发布版nodejs..\n"
        ;;
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done
#############################

ip_is_connect(){
    ping -c2 -i0.3 -W1 $1 &>/dev/null
    if [ $? -eq 0 ];then
        return 0
    else
        return 1
    fi
}

# 通过 HTTP 探测判断是否为国内网络环境(很多 CI 容器禁用了 ICMP, ping 不可靠)
# 探测结果缓存, 同一次运行内只探测一次
_is_china=""
is_china_network(){
    [[ -n "$_is_china" ]] && return $_is_china
    # 用国内可达、海外通常不可达的域名做 HTTP 探测, 超时 3s
    if curl -s -o /dev/null --max-time 3 https://mirrors.cloud.tencent.com/; then
        _is_china=0
    else
        _is_china=1
    fi
    return $_is_china
}

check_sys() {
    #检查是否为Root
    [ $(id -u) != "0" ] && { color_echo ${red} "Error: You must be root to run this script"; exit 1; }
    # 缺失/usr/local/bin路径时自动添加
    [[ -z `echo $PATH|grep /usr/local/bin` ]] && { echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile; source /etc/profile; }
}

# 根据网络环境选择 node 二进制下载源
dist_base_url(){
    if is_china_network; then
        echo "$NODEJS_MIRROR"
    else
        echo "$NODEJS_OFFICIAL"
    fi
}

setup_proxy(){
    # 注意: 不要用 `npm config list`, npm 启动开销大, 实测单次约 20s, 会让用户以为卡死。
    # 改用 `npm config get registry` 只取 registry 值, 实测约 0.1s, 快约 200 倍。
    if is_china_network && [[ -z "$(npm config get registry 2>/dev/null | grep -E 'mirrors.cloud.tencent')" ]]; then
        npm config set registry https://mirrors.cloud.tencent.com/npm/
        color_echo $green "当前网络环境为国内环境, 成功设置腾讯云npm源!"
    fi
}

sys_arch(){
    arch=$(uname -m)
    if [[ "$arch" == "i686" ]] || [[ "$arch" == "i386" ]]; then
        vdis="linux-386"
    elif [[ "$arch" == *"armv7"* ]] || [[ "$arch" == "armv6l" ]]; then
        vdis="linux-armv7l"
    elif [[ "$arch" == *"armv8"* ]] || [[ "$arch" == "aarch64" ]]; then
        vdis="linux-arm64"
    elif [[ "$arch" == *"s390x"* ]]; then
        vdis="linux-s390x"
    elif [[ "$arch" == "ppc64le" ]]; then
        vdis="linux-ppc64le"
    elif [[ "$arch" == *"darwin"* ]]; then
        vdis="darwin-x64"
    elif [[ "$arch" == "x86_64" ]]; then
        vdis="linux-x64"
    fi
}

# 校验下载文件的 SHA256, 失败返回非 0
# macOS 自带 shasum, Linux 通常有 sha256sum
verify_sha256(){
    local version=$1
    local file_name=$2
    local shasum_file="SHASUMS256.txt"
    if ! curl -s -L $CURL_CONNECT_TIMEOUT $CURL_SMALL_MAXTIME -o "$shasum_file" "$(dist_base_url)/$version/$shasum_file"; then
        color_echo $yellow "警告: 无法下载校验文件 $shasum_file, 跳过完整性校验"
        return 1
    fi
    local expected
    if command -v sha256sum &>/dev/null; then
        expected=$(grep "  $file_name$" "$shasum_file" | awk '{print $1}')
        [[ -z "$expected" ]] && { color_echo $yellow "警告: 校验文件中未找到 $file_name, 跳过完整性校验"; return 1; }
        echo "$expected  $file_name" | sha256sum -c - &>/dev/null
    elif command -v shasum &>/dev/null; then
        expected=$(grep "  $file_name$" "$shasum_file" | awk '{print $1}')
        [[ -z "$expected" ]] && { color_echo $yellow "警告: 校验文件中未找到 $file_name, 跳过完整性校验"; return 1; }
        echo "$expected  $file_name" | shasum -a 256 -c - &>/dev/null
    else
        color_echo $yellow "警告: 未找到 sha256sum/shasum, 跳过完整性校验"
        return 1
    fi
}

install_nodejs(){
    if [[ -z $install_version ]];then
        [[ $latest == 0 ]] && echo "正在获取最新长期支持版nodejs..." || echo "正在获取最新当前发布版nodejs..."
        # 通过官方版本索引 dist/index.json 获取, 数组按版本号倒序排列
        # lts 字段为代号字符串(如 Krypton)的是 LTS 版, 为 false 的是 Current 版
        all_version=`curl -s $CURL_CONNECT_TIMEOUT $CURL_SMALL_MAXTIME -H 'Cache-Control: no-cache' $(dist_base_url)/index.json`
        if [[ -z "$all_version" ]]; then
            color_echo $red "下载版本索引失败, 请检查网络连接 (超时或被墙)!"
            exit 1
        fi
        # 注意: 末尾的 grep -o 'v[0-9.]*' 会因 [0-9.]* 允许 0 次匹配而误取到 "version":" 后那个孤立的 v,
        # 导致 install_version 带换行、URL 拼接出错。这里要求 v 后至少 1 位数字 (v[0-9][0-9.]*)
        if [[ $latest == 0 ]]; then
            install_version=`echo "$all_version"|grep -v '"lts":false'|grep -o '"version":"v[0-9][0-9.]*"'|head -n 1|grep -o 'v[0-9][0-9.]*'`
        else
            install_version=`echo "$all_version"|grep '"lts":false'|grep -o '"version":"v[0-9][0-9.]*"'|head -n 1|grep -o 'v[0-9][0-9.]*'`
        fi
        if [[ -z $install_version ]];then
            color_echo $red "获取最新版nodejs失败, 请检查网络连接!"
            exit 1
        fi
        echo "最新版nodejs: `color_echo $blue $install_version`"
    fi
    if [[ $force_mode == 0 && `command -v node` ]];then
        # 用 timeout 包住 node -v: 上次安装被 Ctrl+C 打断可能残留损坏的半成品二进制,
        # 直接执行 node -v 可能 hang 住(依赖缺失/二进制截断), 无超时会无限卡死
        if [[ `timeout 10 node -v 2>/dev/null` == $install_version ]];then
            return
        fi
    fi
    base_name="node-$install_version-$vdis"
    file_name=`[[ "$arch" == *"darwin"* ]] && echo "$base_name.tar.gz" || echo "$base_name.tar.xz"`
    # 下载二进制包: 加连接/总超时, 避免"探测通但 CDN 下载卡死"时无限挂起;
    # -# 显示进度条, 让用户看到实时下载而非死等
    echo "正在下载 $file_name ..."
    if ! curl -L -# $CURL_CONNECT_TIMEOUT $CURL_LARGE_MAXTIME "$(dist_base_url)/$install_version/$file_name" -o "$file_name"; then
        color_echo $red "下载 $file_name 失败! (连接超时/被墙或镜像源不可达)"
        color_echo $yellow "可尝试: 1) 重新运行; 2) 检查网络/代理; 3) 指定其它源"
        rm -rf "$file_name"
        exit 1
    fi
    # 下载后做 SHA256 完整性校验, 避免损坏的二进制被安装
    if verify_sha256 "$install_version" "$file_name"; then
        color_echo $green "完整性校验通过"
    else
        # verify_sha256 内部已对"无校验工具/无校验文件"给出黄色警告, 这里只处理真正的校验不匹配
        if [[ -f "$file_name" && `command -v sha256sum` || `command -v shasum` ]]; then
            color_echo $red "下载文件完整性校验失败!"
            rm -rf $base_name* $file_name SHASUMS256.txt
            exit 1
        fi
    fi
    # 直接解压安装到 /usr/local (--strip-components=1 去掉包内顶层 node-xxx/ 目录)
    # 不再用 "先解压到当前目录再 cp -rf": cp 会把 5000+ 文件再读+写一遍,
    # 在慢盘/网络文件系统(如某些 VPS 的 /usr/local)上会逐文件卡住, 用户表现为
    # 卡在 cp 这一步。tar -C 直装只做一次磁盘写, I/O 减半, 且无需后续 rm 解压目录。
    echo "正在解压安装到 /usr/local/ (慢机器上 xz 解压约需数十秒, 出现点号说明在进行中)..."
    local tar_flag="xJf"
    [[ "$arch" == *"darwin"* ]] && tar_flag="xzf"
    # --checkpoint + dot: 解压时持续打点号, 让用户看到进展而非死等屏幕
    if ! tar $tar_flag "$file_name" -C /usr/local --strip-components=1 --checkpoint=200 --checkpoint-action=dot 2>/dev/null; then
        echo
        color_echo $red "解压安装失败!"
        rm -rf "$file_name" SHASUMS256.txt
        exit 1
    fi
    echo " 完成"
    rm -rf "$file_name" SHASUMS256.txt
}

main(){
    check_sys
    sys_arch
    install_nodejs
    # 安装后验证 node 可用, 避免 cp 成功但二进制损坏的极端情况
    # 同样用 timeout 包住, 防止损坏二进制 hang 住整个脚本
    if ! `command -v node` >/dev/null 2>&1 || ! timeout 10 node -v >/dev/null 2>&1; then
        color_echo $red "nodejs 安装完成但无法运行, 请检查系统架构或依赖!"
        exit 1
    fi
    setup_proxy
    echo -e "nodejs `color_echo $blue $install_version` 安装成功!"
}

main
