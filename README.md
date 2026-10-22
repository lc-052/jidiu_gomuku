# 寄丢棋室 | jidiu_gomuku

基于 Flutter / Dart 的五子棋与围棋应用，支持 Android 和 Web，采用 Material Design 3 响应式卡片界面。

[在线体验](http://101.37.85.166:3000/) · [源码](https://github.com/lc-052/jidiu_gomuku) · [更新记录](CHANGELOG.md) · [网页版部署](server/DEPLOY_WEB_1PANEL.md)

## 功能

- 五子棋与围棋均支持本地双人、人机和在线联机；围棋提供 9 / 13 / 19 路棋盘。
- 三档离线 AI 与执子偏好；围棋 AI 评估提子、救棋、气及连接，困难档检查战术应手。
- 联机支持六位房间码、双方准备、落子同步、聊天、协商悔棋、认输和原房间再来一局。
- 服务端统一校验规则并广播棋局快照，客户端不提前提交本地落子结果。
- 围棋支持提子、禁自杀、全局同形限制、双停、共同标记死子及双方确认计分。
- 五套主题：奶油米白、雾松绿、雨空蓝、浅藤紫、陶土粉，每套均支持浅色、深色及跟随系统，自动保存偏好。
- 棋盘、玩家、操作、记录、计分和设置拆分为独立卡片，适配手机及宽屏布局。

## 技术与结构

Flutter、Dart、Provider / ChangeNotifier、GoRouter、SharedPreferences、Node.js、Express、Socket.IO、Docker。

```text
lib/
  models/       # 本地对局生命周期、联机快照、主题状态
  services/     # 五子棋与围棋规则、AI、网络与存储
  screens/      # 首页、对局、大厅和设置
  widgets/      # 棋盘与响应式卡片组件
server/         # 权威规则服务、测试和 1Panel 部署配置
test/           # 规则、状态、组件及双客户端联机测试
tools/          # 图标生成与部署打包
```

## 开发与验证

```bash
flutter pub get
flutter run
flutter analyze
flutter test
cd server
npm ci
npm test
```

联机集成测试会启动本地 Node.js 服务，因此执行完整 Flutter 测试前需要安装 Node.js 并在 server 中安装依赖。

## Android Release

当前版本：**1.1.0+2**。

```bash
flutter build apk --release --dart-define=GAME_SERVER_URL=http://101.37.85.166:3000
```

安装包位于 `build/app/outputs/flutter-apk/app-release.apk`。默认连接演示服务器，也可以在联机大厅修改地址；支持完整 HTTP / HTTPS 地址。

当前工程的 Release 构建沿用开发签名，适合下载安装和项目演示。商店发布前应配置自己的发布证书，并妥善保存；证书和密码不提交仓库。Release 表示优化构建模式，不代表已完成商店签名或上架。

## Web 与服务器部署

```bash
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
python tools/package_server.py --web
```

生成 `build/deploy/jidiu-qishi-web-1panel.zip`，包含网页、联机服务和 Docker 配置。只需这一个包即可部署网页；服务器无需安装 Flutter。部署后网页默认使用当前网站地址连接 Socket.IO。

- [网页与服务端一体部署 / 权限及端口排错](server/DEPLOY_WEB_1PANEL.md)
- [仅部署联机服务](server/DEPLOY_1PANEL.md)：运行 `python tools/package_server.py`，生成 `build/deploy/jidiu-gomuku-1panel.zip`。
- 当前演示地址：<http://101.37.85.166:3000/>；健康检查：`/health`。
- 有域名后可使用 HTTPS 反向代理，需要转发 WebSocket；客户端支持 HTTPS，无需修改网络代码。

## 对战流程

双方选择相同棋种、连接同一服务器 → 一方建房并分享房间码 → 另一方加入 → 双方准备 → 开始对局。围棋双停后共同核对死子，双方确认当前计分结果后结算；也可恢复下棋处理争议。

## 规则与当前限制

- 围棋采用面积计分，白贴 7.5 目；禁止自杀和重复历史棋盘局面，停着不受同形限制。死活由玩家核对，不自动判定。规则参考：[英国围棋协会规则对照](https://www.britgo.org/rules/compare.html)。
- 围棋 AI 为启发式练习对手，不使用神经网络模型。原生端通过 compute 调度计算，Web 端受浏览器执行环境限制，复杂局面可能短暂停顿。
- 房间保存在服务端内存中，重启服务会丢失房间；断线结束当前对局，暂不支持断线续局、账号和历史棋谱保存。
- Web 发布使用 JavaScript 与本地 CanvasKit，当前未提供 WebAssembly 应用构建。
- 当前交付目标为 Android 和 Web；仓库保留其他平台工程，不代表已完成对应平台发行验证。

## 图标

图标源文件：`assets/icon/app_icon.png`。安装 Pillow 后运行 `python tools/generate_icons.py` 可重新生成各平台图标尺寸。
