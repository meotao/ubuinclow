#!/bin/bash
set -e

# ==============================================================================
# OpenClaw + 飞书 全自动部署脚本 (多系统适配版)
# ==============================================================================

# 【终极防坑】强制接管标准输入，解决 curl | bash 模式下无法读取键盘交互的问题
exec < /dev/tty

echo -e "\n🦞 欢迎使用 OpenClaw 全自动部署脚本 🦞\n"

# ---------------------------------------------------------
# 1. 检测系统版本与发行版
# ---------------------------------------------------------
echo ">>> [1/8] 正在检测系统环境..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "当前系统: $NAME $VERSION"
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        echo "⚠️ 警告: 此脚本主要基于 Ubuntu/Debian 编写。您当前的系统 ($ID) 可能会在包管理 (apt) 阶段报错。"
        read -p "是否继续尝试执行？(y/n): " CONTINUE_FLAG
        if [[ "$CONTINUE_FLAG" != "y" ]]; then
            echo "已取消安装。"
            exit 1
        fi
    fi
else
    echo "⚠️ 警告: 无法检测具体的 Linux 发行版，将强行继续尝试执行..."
fi

# 获取基础配置信息
read -p "👉 请输入飞书的 App ID (例 cli_xxx): " FEISHU_APP_ID
read -p "👉 请输入飞书的 App Secret: " FEISHU_APP_SECRET
export FEISHU_APP_ID
export FEISHU_APP_SECRET

echo -e "\n⏳ 信息收集完毕，开始自动化流水线...\n"

# ---------------------------------------------------------
# 2. 安装底层依赖与 Node.js 22.x 环境
# ---------------------------------------------------------
echo ">>> [2/8] 正在更新系统并安装编译依赖..."
sudo apt-get update
sudo apt-get install -y git curl wget build-essential make python3 python3-pip

echo ">>> 正在升级 CMake (适配底层 C++ 引擎编译)..."
sudo apt-get remove -y cmake || true
sudo pip3 install cmake --break-system-packages || sudo pip3 install cmake
hash -r

echo ">>> 正在升级 Node.js 至 22.x..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm cache clean --force

# ---------------------------------------------------------
# 3. 安装 OpenClaw 核心
# ---------------------------------------------------------
echo ">>> [3/8] 正在全局安装 OpenClaw (涉及源码编译，请耐心等待)..."
sudo npm install -g @qingchencloud/openclaw-zh@latest

# ---------------------------------------------------------
# 4. 局部安装并修复飞书插件
# ---------------------------------------------------------
echo ">>> [4/8] 正在局部修复飞书插件依赖与文件结构..."
sudo npm uninstall -g @openclaw/feishu || true
sudo rm -rf /usr/lib/node_modules/openclaw/extensions/feishu || true
sudo rm -rf ~/.openclaw/extensions/feishu || true

mkdir -p ~/.openclaw/extensions
cd ~/.openclaw/extensions
npm install @openclaw/feishu @sinclair/typebox @larksuiteoapi/node-sdk

# 弃用软链接，直接使用真实文件夹，彻底粉碎 CLI 的 plugin not found 报错
cp -r node_modules/@openclaw/feishu ./feishu
cd ~

# ---------------------------------------------------------
# 5. 安全注入核心配置 (仅飞书部分，避开模型层级校验坑)
# ---------------------------------------------------------
echo ">>> [5/8] 正在注入飞书私聊直通配置..."
node -e "
const fs = require('fs');
const path = require('path');
const file = path.join(require('os').homedir(), '.openclaw', 'openclaw.json');

fs.mkdirSync(path.dirname(file), { recursive: true });
let cfg = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};

// 容错初始化
cfg.channels = cfg.channels || {};
cfg.channels.feishu = cfg.channels.feishu || {};
cfg.plugins = cfg.plugins || {};
cfg.plugins.allow = cfg.plugins.allow || [];

// 精准注入
cfg.channels.feishu.enabled = true;
cfg.channels.feishu.appId = process.env.FEISHU_APP_ID;
cfg.channels.feishu.appSecret = process.env.FEISHU_APP_SECRET;
cfg.channels.feishu.dmPolicy = 'open';
cfg.channels.feishu.allowFrom = ['*'];

// 加入信任白名单
if (!cfg.plugins.allow.includes('feishu')) {
    cfg.plugins.allow.push('feishu');
}

fs.writeFileSync(file, JSON.stringify(cfg, null, 2));
"

# ---------------------------------------------------------
# 6. 注册 Systemd 守护进程
# ---------------------------------------------------------
echo ">>> [6/8] 正在注册并启动后台守护服务..."
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

# ---------------------------------------------------------
# 7. 手动配置 AI 模型大脑
# ---------------------------------------------------------
echo -e "\n🎉 基础框架搭建完毕！"
echo ">>> [7/8] 请在接下来的向导中，为您的机器人选择 AI 大脑："
echo "操作提示：选择【Model】 -> 选择提供商 (如 Google/Z.AI) -> 输入 API Key -> 勾选模型并保存。"
echo "（正在唤醒配置向导...）"
sleep 2

# 调用官方交互界面，供用户安全地选择并注入模型
openclaw configure

# 重启服务使模型生效
systemctl --user restart openclaw-gateway.service

# ---------------------------------------------------------
# 8. 实时运行日志测试
# ---------------------------------------------------------
echo -e "\n>>> [8/8] 所有配置均已生效！"
echo -e "正在为您拉取实时运行日志..."
echo -e "💡 【测试方法】：请现在打开飞书客户端，给机器人发送一句消息。"
echo -e "如果您在下方日志中看到 \033[32m'dispatch complete'\033[0m，则代表彻底通关！\n"
echo -e "（退出日志查看请按 \033[33mCtrl + C\033[0m）\n"
echo -e "============================================================"

# 直接挂起并监听日志，给予用户最直观的成功反馈
openclaw logs --follow
