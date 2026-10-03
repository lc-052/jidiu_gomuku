# 寄丢五子棋 (Gomoku)

一个支持多色主题、单机双人对战和在线联机的 Flutter 五子棋游戏。

## ✨ 功能特性

- 🎮 **本地双人** — 同一设备两人轮流下棋，支持悔棋、投降
- 🤖 **人机对战** — AI 三种难度（简单/中等/困难），会主动封堵活三冲四
- 🌐 **在线联机** — 自建 Socket.IO 服务器，**6 位数字房间码**即可和好友对战；一局结束**原地再来一局**，无需重新建房
- 💬 **局内聊天** — 新消息以浮动气泡即时提示，不用点开面板也不会漏看
- ✋ **联机悔棋** — 走错棋可请求悔棋，**需对方同意**才生效（自动撤回应子）
- 🔍 **终局复盘** — 结算弹窗可"查看棋盘"，输赢之后还能回看最终盘面
- 🎨 **6 种主题** — 经典黑白、星空蓝红、翡翠金翠、霓虹紫青、落日橙粉、水墨丹青
- ⚙️ **完整设置** — 音效、震动、默认执色等

---

## 📱 运行客户端

```bash
cd jidiu_gomuku
flutter pub get
flutter run              # Android 真机
# 或 flutter build apk --release   # 打 release 包发给朋友安装
```

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

### 🔧 常用管理命令

```bash
# 查看所有进程
pm2 list

# 查看日志
pm2 logs gomuku-server --lines 100

# 重启服务
pm2 restart gomuku-server

# 停止服务
pm2 stop gomuku-server

# 删除进程
pm2 delete gomuku-server

# 实时监控资源占用
pm2 monit
```

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

---

### ⚡ 性能参考

| 指标 | 数值 |
|------|------|
| CPU | 2 核 |
| 内存 | 2 GB |
| 最大并发 | ~200 个同时在线玩家 |
| 平均延迟 | < 50ms（国内） |

2H2G 的配置对于五子棋在线对战绰绰有余。Socket.IO 本身非常轻量，每个连接约消耗 2-3MB 内存。

---

## ❓ 联机常见问题

| 现象 | 原因 / 解决 |
|------|------------|
| 加入时提示"房间不存在" | 房间码输错；好友还没建好房；或服务器刚重启过（房间存内存，重启即清空） |
| 双方都显示"你执黑"、开不了局 | 两人都点了"创建房间"，各开了各的房——正确流程是一人创建、另一人用 6 位房间码加入 |
| 进了房间但一直"等待开局" | 需要**双方各自**点页面右上角"未准备"按钮变"已准备"才会开局 |
| 聊天收不到（单侧或双侧，房主最常见） | 旧版客户端会按默认昵称"玩家"互滤对方的消息：请**双方手机都装最新 APK**，并把服务器 `index.js` 更新到最新后 `pm2 restart gomuku-server`（新版服务器自动给默认昵称加后缀、消息只发给对方不回显；新版客户端还会缓存"刚进房间瞬间"收到的消息，不漏气泡提示） |
| 改了端口后 App 连不上 | 服务器需 `PORT=3001 pm2 start ...` 重启 + 安全组/ufw 放行；App 服务器地址填 `IP:3001` |
| 换了服务器文件但不生效 | `pm2 list` 确认进程名，再 `pm2 restart <名字>`；改环境变量（如 PORT）需 `pm2 delete` 后重新 start |

---

## 📐 技术架构

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────┐
│  Player A    │         │                  │         │  Player B    │
│  Flutter App │◄────────►  Socket.IO Server │────────►  Flutter App │
│             │  WebSocket │  Node.js :3000   │  WebSocket│             │
└─────────────┘         └──────────────────┘         └─────────────┘
```

### 通信协议

| 方向 | 事件名 | 数据 |
|------|--------|------|
| 客户端→服务端 | `register` | `{ name }`（留空或默认名"玩家"时，服务器自动加后缀保证双方昵称可区分） |
| 客户端→服务端 | `createRoom` | `{ roomName, playerColor }` |
| 客户端→服务端 | `joinRoom` | `{ roomId }`（6 位数字房间码，也支持房间名称） |
| 客户端→服务端 | `startGame` | — |
| 客户端→服务端 | `makeMove` | `{ row, col }` |
| 客户端→服务端 | `resign` | — |
| 客户端→服务端 | `chat` | `{ message }` |
| 客户端→服务端 | `undoRequest` | —（悔棋请求，服务器校验后转问对方） |
| 客户端→服务端 | `undoReply` | `{ accept }`（被请求方同意/拒绝） |
| 客户端→服务端 | `leaveRoom` | — |
| 服务端→客户端 | `registered` | `{ name, playerId }` |
| 服务端→客户端 | `roomCreated` | `{ roomId, roomName, yourColor }` |
| 服务端→客户端 | `roomJoined` | `{ roomId, yourColor, opponentName }`（发给加入者） |
| 服务端→客户端 | `opponentJoined` | `{ name, color }`（发给房间内既有玩家） |
| 服务端→客户端 | `playerReady` | `{ name, color }`（准备者的对手收到） |
| 服务端→客户端 | `gameStarted` | `{ black, white, yourColor, yourTurn }`（逐人定向发送） |
| 服务端→客户端 | `move` | `{ row, col, playerColor, placedBy, nextPlayer }` |
| 服务端→客户端 | `gameOver` | `{ winner, winnerColor, reason }`（平局时 `winnerColor` 为 `null`；reason: five-in-a-row / draw / resign / left / disconnected） |
| 服务端→客户端 | `chatMessage` | `{ message, sender }`（只发给房间里对方，不回显给发送者） |
| 服务端→客户端 | `undoAsk` | `{ name }`（发给被请求方，弹窗征询） |
| 服务端→客户端 | `undoAnswer` | `{ accept, reason }`（请求方收到；拒绝/过期/对方离开时附原因） |
| 服务端→客户端 | `undone` | `{ removed:[{row,col}], nextPlayer }`（悔棋生效，发给房间双方） |
| 服务端→客户端 | `undoCancelled` | —（请求方离开/掉线，通知被请求方关闭弹窗） |
| 服务端→客户端 | `errorMsg` | `{ message, sender }` |
| 服务端→客户端 | `opponentLeft` / `opponentDisconnected` | `{ name }`（等待阶段对手离开/掉线） |

---

## 📁 项目结构

```
lib/
├── main.dart                  # 应用入口 + GoRouter 路由
├── models/
│   ├── game_state.dart        # 游戏数据模型（枚举、位置、棋盘大小）
│   ├── theme_model.dart       # 6 套主题配色
│   └── game_mode.dart         # 游戏模式枚举
├── services/
│   ├── game_engine.dart       # 核心游戏规则引擎
│   ├── ai_service.dart        # AI 对手（棋型分级 + 堵截梯子 + 前瞻）
│   ├── network_service.dart   # WebSocket 网络对战服务
│   └── storage_service.dart   # 本地设置持久化
├── screens/
│   ├── main_menu_screen.dart  # 主菜单
│   ├── game_screen.dart       # 本地/AI 对战场面
│   ├── online_lobby_screen.dart # 在线大厅（创建/加入房间）
│   ├── online_game_screen.dart  # 在线对战场面
│   └── settings_screen.dart     # 设置页
└── widgets/
    └── board_widget.dart       # 棋盘绘制组件

test/
├── widget_test.dart            # 冒烟测试（主菜单可渲染）
├── game_engine_test.dart       # 规则引擎测试
├── ai_service_test.dart        # AI 封堵/取胜行为测试
└── board_widget_test.dart      # 棋盘渲染/坐标映射测试

assets/icon/                    # 应用图标源图（flutter_launcher_icons 使用）

server/
├── index.js                    # Socket.IO 后端
└── package.json                # Node.js 配置
```

---

## 🎯 AI 算法说明

AI 采用**棋型分级评分 + 堵截梯子 + 一层前瞻**：

1. **候选点生成** — 只评估已有棋子八邻内的空位，大幅缩减搜索量
2. **棋型识别** — 沿横/竖/两条对角共 4 轴，用 9 格窗口字符串识别
   五连、活四、冲四、跳四、活三、眠三、跳三、活二、眠二等棋型，
   分值严格按威胁等级分档（五连 > 双四 > 冲四活三 > 双活三 > 活四 > 冲四 > 活三 > 眠三 > 活二）
3. **堵截梯子** — 先查"自己一手成五→取胜"，再查"对手一手成五→强制封堵"，
   然后按"进攻分 + 防守分×权重"取最大；对手威胁点的防守分即"对手在此落子能成形的分值"，
   保证活三/活四必被拦截
4. **一层前瞻**（困难） — 对头部 8 个候选模拟对手最佳应招，扣减其反手威胁、
   加上己方后续潜力后重评分

难度差异：
- **简单**：防守权重 0.55，且 20% 概率从前六名随机挑（故意留破绽）
- **中等**：攻防全额权衡
- **困难**：全额权衡 + 对手应招一层前瞻

---

## ⭐ 主题列表

| # | 名称 | 黑方 | 白方 |
|---|------|------|------|
| 1 | 经典黑白 | 深灰 | 纯白 |
| 2 | 星空蓝红 | 深蓝 | 绯红 |
| 3 | 翡翠金翠 | 翠绿 | 金色 |
| 4 | 霓虹紫青 | 紫色 | 青色 |
| 5 | 落日橙粉 | 橙色 | 粉色 |
| 6 | 水墨丹青 | 墨黑 | 朱红 |
