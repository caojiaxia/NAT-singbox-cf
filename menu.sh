#!/bin/bash

WORK_DIR="$HOME/nat-proxy"
SB="$WORK_DIR/sing-box"
CF="$WORK_DIR/cloudflared"
CONF="$WORK_DIR/config.json"
LOG_CF="$WORK_DIR/cf.log"
MODE_FILE="$WORK_DIR/mode.txt"

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
plain="\033[0m"

ok(){ echo -e "${green}[✔] $1${plain}"; }
doit(){ echo -e "${yellow}[➜] $1...${plain}"; }
err(){ echo -e "${red}[✘] $1${plain}"; }

# ================= 下载核心（多源防炸） =================
download_sb() {
URLS=(
"https://ghfast.top/https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
"https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
)

for u in "${URLS[@]}"; do
    doit "下载 sing-box"
    curl -L --retry 3 -o sb.zip "$u" && break
done

file sb.zip | grep -q "Zip archive" || return 1
}

install_core() {
mkdir -p $WORK_DIR && cd $WORK_DIR

echo "[➜] 安装 sing-box（多源尝试）..."

URLS=(
"https://ghfast.top/https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
"https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
"https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip"
)

SUCCESS=0

for url in "${URLS[@]}"; do
    echo "尝试: $url"
    curl -L --connect-timeout 10 --max-time 60 -o sb.zip "$url"

    SIZE=$(stat -c%s sb.zip 2>/dev/null || echo 0)

    if [ "$SIZE" -gt 1000000 ]; then
        SUCCESS=1
        break
    else
        echo "下载异常，换源..."
    fi
done

if [ "$SUCCESS" -ne 1 ]; then
    echo "[✘] sing-box 下载失败（网络完全不通）"
    return 1
fi

unzip -o sb.zip >/dev/null 2>&1 || {
    echo "[✘] 解压失败"
    return 1
}

mv sing-box*/sing-box $SB 2>/dev/null
chmod +x $SB
rm -rf sb.zip sing-box*

echo "[✔] sing-box 安装完成"

echo "[➜] 安装 cloudflared..."

CF_URLS=(
"https://ghfast.top/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
"https://ghproxy.com/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
"https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
)

for url in "${CF_URLS[@]}"; do
    echo "尝试: $url"
    curl -L --connect-timeout 10 --max-time 60 -o $CF "$url"

    SIZE=$(stat -c%s $CF 2>/dev/null || echo 0)

    if [ "$SIZE" -gt 5000000 ]; then
        break
    else
        echo "下载异常，换源..."
    fi
done

chmod +x $CF
echo "[✔] cloudflared 安装完成"
}

# ================= 配置 =================
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
ok "配置生成完成"
}

# ================= 守护 =================
create_keep() {
cat > $WORK_DIR/keep.sh <<'EOF'
#!/bin/bash
DIR="$HOME/nat-proxy"
MODE=$(cat $DIR/mode.txt 2>/dev/null)
TOKEN=$(cat $DIR/token.txt 2>/dev/null)

while true; do
 pgrep sing-box >/dev/null || nohup $DIR/sing-box run -c $DIR/config.json > $DIR/sb.log 2>&1 &

 if [ "$MODE" = "temp" ]; then
   pgrep -f "cloudflared tunnel --url" >/dev/null || nohup $DIR/cloudflared tunnel --url http://localhost:10000 > $DIR/cf.log 2>&1 &
 else
   pgrep -f "cloudflared tunnel run" >/dev/null || nohup $DIR/cloudflared tunnel run --token $TOKEN > $DIR/cf.log 2>&1 &
 fi

 sleep 10
done
EOF

chmod +x $WORK_DIR/keep.sh
}

# ================= 启动 =================
start_temp() {
echo "temp" > $MODE_FILE

pkill -f sing-box
pkill -f cloudflared

doit "启动临时隧道"
nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
sleep 2
nohup $CF tunnel --url http://localhost:10000 > $LOG_CF 2>&1 &

nohup bash $WORK_DIR/keep.sh >/dev/null 2>&1 &

sleep 3
ok "启动完成"
show_node
}

start_token() {
read -p "输入 CF Token: " TOKEN
echo $TOKEN > $WORK_DIR/token.txt
echo "token" > $MODE_FILE

pkill -f sing-box
pkill -f cloudflared

doit "启动 Token 隧道"
nohup $SB run -c $CONF > $WORK_DIR/sb.log 2>&1 &
sleep 2
nohup $CF tunnel run --token $TOKEN > $LOG_CF 2>&1 &

nohup bash $WORK_DIR/keep.sh >/dev/null 2>&1 &

ok "启动完成（固定域名模式）"
}

# ================= 节点 =================
parse_domain() {
for i in {1..15}; do
 DOMAIN=$(grep -o 'https://.*trycloudflare.com' $LOG_CF | tail -1)
 [ -n "$DOMAIN" ] && break
 sleep 1
done
}

show_node() {
MODE=$(cat $MODE_FILE 2>/dev/null)
UUID=$(cat $WORK_DIR/uuid.txt 2>/dev/null)

if [ "$MODE" = "temp" ]; then
 parse_domain

 echo
 echo "====== 临时节点 ======"
 echo "地址: $DOMAIN"
 echo "UUID: $UUID"
 echo

 echo "vless://$UUID@${DOMAIN#https://}:443?encryption=none&security=tls&type=ws&host=${DOMAIN#https://}&path=%2Fws#NAT"
 echo "======================"
else
 echo "当前为 Token 模式（使用你自己的域名）"
fi
}

# ================= 其他 =================
diagnose() {
pgrep -af sing-box || echo "sing-box 未运行"
pgrep -af cloudflared || echo "cloudflared 未运行"
tail -n 20 $LOG_CF
}

uninstall_all() {
pkill -f sing-box
pkill -f cloudflared
rm -rf $WORK_DIR
ok "已卸载"
}

# ================= 菜单 =================
menu(){
clear
echo -e "${green}
====== NAT 专用 CF + sing-box 面板 ======
1. 临时隧道
2. Token固定隧道
3. 查看节点信息
4. 诊断
5. 卸载
6. 退出
==============================
${plain}"

read -p "选择: " n
case $n in
1) install_core && gen_config && create_keep && start_temp ;;
2) install_core && gen_config && create_keep && start_token ;;
3) show_node ;;
4) diagnose ;;
5) uninstall_all ;;
6) exit ;;
*) echo "输入错误" ;;
esac

read -p "回车继续"
menu
}

menu
