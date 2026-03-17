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

print_step() {
    echo -e "${green}[✔] $1${plain}"
}

print_doing() {
    echo -e "${yellow}[➜] $1...${plain}"
}

install_core() {
    mkdir -p $WORK_DIR
    cd $WORK_DIR

    print_doing "下载 sing-box"
    wget -q --show-progress -O sb.zip https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip
    unzip -o sb.zip >/dev/null
    mv sing-box*/sing-box $SB
    chmod +x $SB
    rm -rf sb.zip sing-box*
    print_step "sing-box 安装完成"

    print_doing "下载 cloudflared"
    wget -q --show-progress -O $CF https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x $CF
    print_step "cloudflared 安装完成"
}

gen_config() {
    print_doing "生成配置"

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
    print_step "配置生成完成"
}

create_keep() {
cat > $WORK_DIR/keep.sh <<'EOF'
#!/bin/bash
DIR="$HOME/nat-proxy"
SB="$DIR/sing-box"
CF="$DIR/cloudflared"
CONF="$DIR/config.json"

TOKEN=$1

while true; do
    pgrep -f "sing-box" >/dev/null || nohup $SB run -c $CONF > $DIR/sb.log 2>&1 &
    
    if [ -z "$TOKEN" ]; then
        pgrep -f "cloudflared tunnel --url" >/dev/null || nohup $CF tunnel --url http://localhost:10000 > $DIR/cf.log 2>&1 &
    else
        pgrep -f "cloudflared tunnel run" >/dev/null || nohup $CF tunnel run --token $TOKEN > $DIR/cf.log 2>&1 &
    fi

    sleep 10
done
EOF

chmod +x $WORK_DIR/keep.sh
}

parse_domain() {
    for i in {1..10}; do
        DOMAIN=$(grep -o 'https://.*trycloudflare.com' $LOG_CF | tail -1)
        [ -n "$DOMAIN" ] && break
        sleep 1
    done
}

output_node() {
    UUID=$(cat $WORK_DIR/uuid.txt)
    parse_domain

    echo
    echo -e "${green}========= 节点信息 =========${plain}"
    echo "地址: $DOMAIN"
    echo "端口: 443"
    echo "UUID: $UUID"
    echo "传输: WS"
    echo "路径: /ws"
    echo "TLS: 开"
    echo

    echo "👉 v2rayN / v2rayNG 手动填入即可"
    echo "👉 或复制下面链接导入："
    echo
    echo "vless://$UUID@${DOMAIN#https://}:443?encryption=none&security=tls&type=ws&host=${DOMAIN#https://}&path=%2Fws#NAT-CF"
    echo -e "${green}============================${plain}"
}

start_temp() {
    print_doing "启动服务（临时隧道）"

    pkill -f sing-box
    pkill -f cloudflared

    nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
    sleep 2
    nohup $CF tunnel --url http://localhost:10000 > $LOG_CF 2>&1 &

    nohup bash $WORK_DIR/keep.sh > /dev/null 2>&1 &

    sleep 3
    print_step "启动完成"
    output_node
}

start_token() {
    read -p "输入 CF Token: " TOKEN

    print_doing "启动服务（Token 模式）"

    pkill -f sing-box
    pkill -f cloudflared

    nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
    sleep 2
    nohup $CF tunnel run --token $TOKEN > $LOG_CF 2>&1 &

    nohup bash $WORK_DIR/keep.sh $TOKEN > /dev/null 2>&1 &

    print_step "启动完成"
    echo "👉 使用你自己的域名访问"
}

show_info() {
    output_node
}

diagnose() {
    echo "=== 运行状态 ==="
    pgrep -af sing-box || echo "sing-box 未运行"
    pgrep -af cloudflared || echo "cloudflared 未运行"

    echo
    echo "=== 最新日志 ==="
    tail -n 20 $LOG_CF
}

uninstall_all() {
    pkill -f sing-box
    pkill -f cloudflared
    rm -rf $WORK_DIR
    print_step "已彻底卸载"
}

menu() {
clear
echo -e "${green}
================================
 NAT 专用 CF + sing-box 面板
================================
1. 部署 Token 模式（稳定）
2. 部署 临时隧道（推荐 NAT）
3. 查看节点信息
4. 链路诊断
5. 卸载
6. 退出
================================
${plain}"
read -p "请选择: " num

case "$num" in
1)
install_core
gen_config
create_keep
start_token
;;
2)
install_core
gen_config
create_keep
start_temp
;;
3) show_info ;;
4) diagnose ;;
5) uninstall_all ;;
6) exit ;;
*) echo "无效输入" ;;
esac

read -p "回车继续"
menu
}

menu
