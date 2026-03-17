#!/bin/bash

WORK_DIR="$HOME/nat-proxy"
SB="$WORK_DIR/sing-box"
CF="$WORK_DIR/cloudflared"
CONF="$WORK_DIR/config.json"
LOG_CF="$WORK_DIR/cf.log"

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
plain="\033[0m"

print_ok(){ echo -e "${green}[✔] $1${plain}"; }
print_do(){ echo -e "${yellow}[➜] $1...${plain}"; }
print_err(){ echo -e "${red}[✘] $1${plain}"; }

# ✅ 多源下载 + 重试
download_file() {
    URLS=(
        "https://ghfast.top/https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
        "https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
    )

    for url in "${URLS[@]}"; do
        print_do "尝试下载: $url"
        curl -L --retry 3 --connect-timeout 10 -o sb.zip "$url" && break
    done

    file sb.zip | grep -q "Zip archive" || return 1
}

install_core() {
    mkdir -p $WORK_DIR && cd $WORK_DIR

    print_do "安装 sing-box"
    if ! download_file; then
        print_err "sing-box 下载失败（网络问题）"
        return 1
    fi

    unzip -o sb.zip >/dev/null
    mv sing-box*/sing-box $SB
    chmod +x $SB
    rm -rf sb.zip sing-box*
    print_ok "sing-box OK"

    print_do "安装 cloudflared"
    curl -L --retry 3 -o $CF https://ghfast.top/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x $CF
    print_ok "cloudflared OK"
}

gen_config() {
    UUID=$(cat /proc/sys/kernel/random/uuid)

    cat > $CONF <<EOF
{
 "inbounds":[
  {
   "type":"vless",
   "listen":"0.0.0.0",
   "listen_port":10000,
   "users":[{"uuid":"$UUID"}],
   "transport":{"type":"ws","path":"/ws"}
  }
 ],
 "outbounds":[{"type":"direct"}]
}
EOF

    echo $UUID > $WORK_DIR/uuid.txt
    print_ok "配置生成完成"
}

create_keep() {
cat > $WORK_DIR/keep.sh <<'EOF'
#!/bin/bash
DIR="$HOME/nat-proxy"
while true; do
 pgrep sing-box >/dev/null || nohup $DIR/sing-box run -c $DIR/config.json > $DIR/sb.log 2>&1 &
 pgrep cloudflared >/dev/null || nohup $DIR/cloudflared tunnel --url http://localhost:10000 > $DIR/cf.log 2>&1 &
 sleep 10
done
EOF
chmod +x $WORK_DIR/keep.sh
}

parse_domain() {
    for i in {1..15}; do
        DOMAIN=$(grep -o 'https://.*trycloudflare.com' $LOG_CF | tail -1)
        [ -n "$DOMAIN" ] && break
        sleep 1
    done
}

show_node() {
    UUID=$(cat $WORK_DIR/uuid.txt 2>/dev/null)
    parse_domain

    echo
    echo -e "${green}========= 节点 =========${plain}"
    echo "地址: $DOMAIN"
    echo "UUID: $UUID"
    echo

    LINK="vless://$UUID@${DOMAIN#https://}:443?encryption=none&security=tls&type=ws&host=${DOMAIN#https://}&path=%2Fws#NAT"
    echo "$LINK"
    echo -e "${green}========================${plain}"
}

start_temp() {
    pkill -f sing-box
    pkill -f cloudflared

    print_do "启动服务"
    nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
    sleep 2
    nohup $CF tunnel --url http://localhost:10000 > $LOG_CF 2>&1 &

    nohup bash $WORK_DIR/keep.sh >/dev/null 2>&1 &

    sleep 3
    print_ok "启动完成"
    show_node
}

diagnose() {
    echo "=== 状态 ==="
    pgrep -af sing-box || echo "sing-box 未运行"
    pgrep -af cloudflared || echo "cloudflared 未运行"
    echo
    tail -n 20 $LOG_CF
}

uninstall_all() {
    pkill -f sing-box
    pkill -f cloudflared
    rm -rf $WORK_DIR
    print_ok "已卸载"
}

menu(){
clear
echo -e "${green}
====== NAT 专用 CF + sing-box 面板 ======
1. 一键部署（临时隧道）
2. 查看节点
3. 诊断
4. 卸载
5. 退出
============================
${plain}"

read -p "选择: " n
case $n in
1) install_core && gen_config && create_keep && start_temp ;;
2) show_node ;;
3) diagnose ;;
4) uninstall_all ;;
5) exit ;;
*) echo "错误输入" ;;
esac

read -p "回车继续"
menu
}

menu
