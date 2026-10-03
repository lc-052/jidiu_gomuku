# 寄丢五子棋 (jidiu_Gomoku)

一个支持单机双人对战和在线联机的 Flutter 五子棋游戏。

## ✨ 功能特性

- 🎮 **本地双人** — 同一设备两人轮流下棋，支持悔棋、投降
- 🤖 **人机对战** — AI 三种难度（简单/中等/困难），会主动封堵活三冲四
- 🌐 **在线联机** — 自建 Socket.IO 服务器
- 💬 **局内聊天** — 新消息以浮动气泡即时提示，不用点开面板也不会漏看
- ✋ **联机悔棋** — 走错棋可请求悔棋，**需对方同意**才生效（自动撤回应子）
- 🔍 **终局复盘** — 结算弹窗可"查看棋盘"，输赢之后还能回看最终盘面
- 🎨 **6 种主题** — 经典黑白、星空蓝红、翡翠金翠、霓虹紫青、落日橙粉、水墨丹青
- ⚙️ **完整设置** — 音效、震动、默认执色等

---



### 联机对战流程（玩家视角）

1. 双方在大厅填**同一个服务器地址**（`公网IP`，非默认端口时填 `IP:端口`），点"连接"
2. **一人**切到"创建房间"，起个名字点创建 → 等待页会显示 **6 位数字房间码**
3. 把房间码发给另一人，对方在"加入房间"输入房间码加入
4. **双方都点页面右上角的"未准备"按钮**，两人都变"已准备"后自动开局（黑先）
5. 一局结束后可点"查看棋盘"复盘；点"**再来一局**"**原地重开**（房间码不变，双方再各点一次准备即开新局，不用回大厅重新建房）
6. 对局中走错棋可点"悔棋"向对方发请求，**对方同意后**才生效（对方已应子则连同应子一并撤销）

---

## 🖥️ 服务器部署（Ubuntu 2H2G）

### 前置条件

- Ubuntu 18.04+ 服务器
- Node.js >= 18.x
- 开放端口 3000（TCP）
- SSH 访问权限

### 详细步骤

#### 第一步：连接服务器

```bash
ssh user@your-server-ip
```

#### 第二步：安装 Node.js

```bash
# 使用 NodeSource 安装 Node.js 20.x（LTS）
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 验证安装
node -v   # 应显示 v20.x.x
npm -v    # 应显示 10.x.x
```

#### 第三步：安装 PM2（进程守护）

```bash
sudo npm install -g pm2
pm2 --version
```

#### 第四步：上传服务器文件

只需上传三个文件（**不要**上传本地 `node_modules`，依赖到服务器上再装）。
在**本机**项目根目录执行：

```bash
ssh user@your-server-ip "mkdir -p /opt/gomuku/server"
scp server/index.js server/package.json server/package-lock.json user@your-server-ip:/opt/gomuku/server/
```

> 之后每次改了服务器代码，重复这条 scp + `pm2 restart gomuku-server` 即可。

#### 第五步：安装依赖并启动

```bash
cd /opt/gomuku/server

# 安装依赖
npm install

# 用 PM2 启动（后台运行，自动重启）
pm2 start index.js --name gomuku-server
pm2 save
pm2 startup   # 开机自启

# 查看状态
pm2 status
pm2 logs gomuku-server
```

#### 第六步：配置防火墙

```bash
# UFW（Ubuntu 自带防火墙）
sudo ufw allow 3000/tcp
sudo ufw allow 22/tcp
sudo ufw enable   # 如果尚未启用

# 如果使用阿里云/腾讯云安全组
# 需要在云控制台的安全组中添加：
# 入站规则 → TCP → 端口 3000 → 来源 0.0.0.0/0
```

#### 第七步：验证服务

```bash
# 健康检查
curl http://localhost:3000/health

# 预期输出: {"status":"ok","uptime":123}
```

#### 第八步：获取你的服务器 IP

```bash
# 公网 IP
curl ifconfig.me

# 记录这个 IP，后面在 App 中填入
# 例如: 47.100.xx.xx
```

#### 改默认端口（可选：如果服务器上 3000 已被占用）

服务器读取 `PORT` 环境变量，**无需改代码**：

```bash
# 放行新端口（防火墙 + 云安全组都要）
sudo ufw allow 3001/tcp

# 如果之前已经用 pm2 起过，先删掉旧进程记录再带环境变量启动，
# 否则 pm2 restart 不会重新读取环境变量
pm2 delete gomuku-server 2>/dev/null
PORT=3001 pm2 start index.js --name gomuku-server
pm2 save   # 环境变量会随 pm2 save 持久化，重启服务器后仍然生效

# 验证
curl http://localhost:3001/health
```

也可以直接修改 `server/index.js` 最后一行的 `|| 3000` 为所需端口，效果等价。

App 端**不用重新打包**：大厅的"服务器地址"一栏直接填 `公网IP:3001`
（只填 IP 不带端口时默认按 3000 连接）。

---

### 📦 服务端文件结构

```
server/
├── index.js          # Socket.IO 服务器主文件
├── package.json      # Node.js 依赖配置
└── package-lock.json
```

> ⚠️ `server/node_modules/` 不要提交/上传，在服务器上 `npm install` 生成即可（仓库 `.gitignore` 已忽略）。
> 之后更新服务器代码：传新的 `index.js` 覆盖 → `pm2 restart gomuku-server`。

---



### 🛡️ 可选：使用 Nginx 反代 + HTTPS

如果你有域名并想启用 HTTPS：

```bash
# 安装 Nginx
sudo apt install nginx -y

# 申请免费 SSL（Let's Encrypt）
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d your-domain.com

# Nginx 配置示例 (/etc/nginx/sites-available/gomuku)
server {
    listen 80;
    server_name gomuku.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name gomuku.example.com;

    ssl_certificate /etc/letsencrypt/live/gomuku.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gomuku.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }
}

# 加载配置
sudo ln -s /etc/nginx/sites-available/gomuku /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

> 注意：当前 App 固定按 `http://IP:端口` 直连（`lib/services/network_service.dart` 的 `connect()`）。
> 若走 HTTPS 反代，需把该处 URL 改为 `https://` 方案并重新打包 APK。


