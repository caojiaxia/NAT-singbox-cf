#!/bin/bash

WORK_DIR="$HOME/nat-proxy"
SB="$WORK_DIR/sing-box"
CF="$WORK_DIR/cloudflared"
CONF="$WORK_DIR/config.json"
LOG_CF="$WORK_DIR/cf.log"

mkdir -p $WORK_DIR

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
plain="\033[0m"

install_core() {
    cd $WORK_DIR

    echo -e "${yellow}安装 sing-box...${plain}"
    wget -q -O sb.zip https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip
    unzip -o sb.zip >/dev/null
    mv sing-box*/sing-box $SB
    chmod +x $SB
    rm -rf sb.zip sing-box*

    echo -e "${yellow}安装 cloudflared...${plain}"
    wget -q -O $CF https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x $CF
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
}

start_services_temp() {
    pkill -f sing-box
    pkill -f cloudflared

    nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
    sleep 2
    nohup $CF tunnel --url http://localhost:10000 > $LOG_CF 2>&1 &

    nohup bash $WORK_DIR/keep.sh > /dev/null 2>&1 &
}

start_services_token() {
    read -p "输入 CF Token: " TOKEN

    pkill -f sing-box
    pkill -f cloudflared

    nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
    sleep 2
    nohup $CF tunnel run --token $TOKEN > $LOG_CF 2>&1 &

    nohup bash $WORK_DIR/keep.sh $TOKEN > /dev/null 2>&1 &
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

show_info() {
    if [ ! -f "$WORK_DIR/uuid.txt" ]; then
        echo -e "${red}未安装${plain}"
        return
    fi

    UUID=$(cat $WORK_DIR/uuid.txt)
    DOMAIN=$(grep -o 'https://.*trycloudflare.com' $LOG_CF | tail -1)

    echo -e "${green}节点信息:${plain}"
    echo "地址: $DOMAIN"
    echo "端口: 443"
    echo "UUID: $UUID"
    echo "WS路径: /ws"
    echo "TLS: 开"
}

diagnose() {
    echo "=== sing-box ==="
    pgrep -af sing-box || echo "未运行"

    echo "=== cloudflared ==="
    pgrep -af cloudflared || echo "未运行"

    echo "=== 日志 ==="
    tail -n 20 $LOG_CF
}

uninstall_all() {
    pkill -f sing-box
    pkill -f cloudflared
    rm -rf $WORK_DIR
    echo -e "${green}已彻底卸载${plain}"
}

menu() {
clear
echo -e "${green}
================================
 NAT 专用 CF + sing-box 面板
================================
1. 部署 Token 模式 (自有域名/永久)
2. 部署 临时隧道模式 (无需域名)
3. 查看当前节点信息
4. 链路诊断
5. 彻底卸载
6. 退出
================================
${plain}"
read -p "请选择: " num

case "$num" in
1)
install_core
gen_config
create_keep
start_services_token
;;
2)
install_core
gen_config
create_keep
start_services_temp
;;
3) show_info ;;
4) diagnose ;;
5) uninstall_all ;;
6) exit ;;
*) echo "无效输入" ;;
esac

read -p "按回车返回菜单"
menu
}

menu
