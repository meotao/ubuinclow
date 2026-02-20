#!/bin/bash
set -e

echo -e "\n=== OpenClaw 全自动部署脚本 ===\n"

# 强制从当前终端读取，完美兼容 curl | bash 的执行方式
read -p "请输入飞书 App ID (例 cli_xxx): " FEISHU_APP_ID < /dev/tty
read -p "请输入飞书 App Secret: " FEISHU_APP_SECRET < /dev/tty
read -p "请输入 Gemini API Key (例 AIza...): " GEMINI_API_KEY < /dev/tty

# 导出环境变量，供后续 Node.js 脚本安全读取
export FEISHU_APP_ID
export FEISHU_APP_SECRET
export GEMINI_API_KEY

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
# 创建软链接，确保 OpenClaw 引擎能精准识别到插件入口
ln -sfn node_modules/@openclaw/feishu feishu || true
cd ~

echo ">>> [6/7] 正在写入核心配置 (绕过 CLI 强行注入)..."
# 使用 Node.js 脚本精准修改 JSON，彻底避开 CLI 的 schema 校验报错
node -e "
const fs = require('fs');
const path = require('path');
const file = path.join(require('os').homedir(), '.openclaw', 'openclaw.json');

// 确保配置目录存在
fs.mkdirSync(path.dirname(file), { recursive: true });

let cfg = {};
if (fs.existsSync(file)) {
    cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
}

// 初始化各个层级的节点，防止 undefined 报错
cfg.channels = cfg.channels || {};
cfg.channels.feishu = cfg.channels.feishu || {};
cfg.providers = cfg.providers || {};
cfg.providers.google = cfg.providers.google || {};
cfg.plugins = cfg.plugins || {};
cfg.plugins.allow = cfg.plugins.allow || [];

// 暴力注入飞书和模型配置
cfg.channels.feishu.enabled = true;
cfg.channels.feishu.appId = process.env.FEISHU_APP_ID;
cfg.channels.feishu.appSecret = process.env.FEISHU_APP_SECRET;
cfg.channels.feishu.dmPolicy = 'open';
cfg.channels.feishu.allowFrom = ['*'];

cfg.providers.google.apiKey = process.env.GEMINI_API_KEY;
cfg.model = 'google/gemini-3-flash-preview';

// 强制信任飞书插件
if (!cfg.plugins.allow.includes('feishu')) {
    cfg.plugins.allow.push('feishu');
}

fs.writeFileSync(file, JSON.stringify(cfg, null, 2));
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
