#!/bin/bash
set -e

echo -e "\n=== OpenClaw 全自动部署脚本 ===\n"

read -p "请输入飞书 App ID (例 cli_xxx): " FEISHU_APP_ID
read -p "请输入飞书 App Secret: " FEISHU_APP_SECRET
read -p "请输入 Gemini API Key (例 AIza...): " GEMINI_API_KEY

echo -e "\n⏳ 信息收集完毕，开始自动配置...\n"

echo ">>> [1/7] 更新系统并安装基础依赖..."
sudo apt-get update
sudo apt-get install -y git curl wget build-essential make python3 python3-pip

echo ">>> [2/7] 升级 CMake..."
sudo apt-get remove -y cmake || true
sudo pip3 install cmake
hash -r

echo ">>> [3/7] 升级 Node.js 至 22.x..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm cache clean --force

echo ">>> [4/7] 正在全局安装 OpenClaw (包含源码编译)..."
sudo npm install -g openclaw@latest

echo ">>> [5/7] 局部修复飞书插件依赖..."
sudo npm uninstall -g @openclaw/feishu || true
sudo rm -rf /usr/lib/node_modules/openclaw/extensions/feishu || true

mkdir -p ~/.openclaw/extensions
cd ~/.openclaw/extensions
npm install @openclaw/feishu @sinclair/typebox @larksuiteoapi/node-sdk
cd ~

echo ">>> [6/7] 正在写入核心配置..."
openclaw config set channels.feishu.enabled true --json
openclaw config set channels.feishu.appId "$FEISHU_APP_ID"
openclaw config set channels.feishu.appSecret "$FEISHU_APP_SECRET"
openclaw config set channels.feishu.dmPolicy "open"
openclaw config set channels.feishu.allowFrom '["*"]' --json
openclaw config set providers.google.apiKey "$GEMINI_API_KEY"

node -e "
const fs = require('fs');
const file = require('os').homedir() + '/.openclaw/openclaw.json';
if (fs.existsSync(file)) {
    let cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
    cfg.model = 'google/gemini-3-flash-preview';
    fs.writeFileSync(file, JSON.stringify(cfg, null, 2));
}
"

echo ">>> [7/7] 注册 Systemd 后台服务..."
mkdir -p ~/.config/systemd/user
cat << 'SERVICE' > ~/.config/systemd/user/openclaw-gateway.service
[Unit]
Description=OpenClaw Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5
Environment=OPENCLAW_GATEWAY_PORT=18789

[Install]
WantedBy=default.target
SERVICE

systemctl --user daemon-reload
systemctl --user enable --now openclaw-gateway.service
sudo loginctl enable-linger $USER

echo -e "\n🎉 部署彻底完成！服务已在后台静默运行。"
