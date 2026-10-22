# 使用 1Panel 部署寄丢棋室

本次目标：`101.37.85.166`，公网游戏端口 `3000/TCP`。
App 默认连接 `http://101.37.85.166:3000`，也可在联机大厅修改。
网页版已在该服务器部署并完成双浏览器五子棋联机验证。网页与服务端一体部署见 [网页版部署说明](DEPLOY_WEB_1PANEL.md)。

压缩包的快速用法：在面板文件管理中新建 `/opt/jidiu-gomuku`，把部署包上传到这里并解压，
确认出现 `/opt/jidiu-gomuku/server/Dockerfile` 后，按下文创建编排。

## 准备文件

在 1Panel 的文件管理中新建专用目录 `/opt/jidiu-gomuku/server`，上传：

- index.js
- game_rules.js
- package.json
- package-lock.json
- Dockerfile
- .dockerignore

不需要上传 node_modules。这个目录应专用于本项目，避免覆盖其他服务文件。

## 创建编排

在「容器 → 编排 → 创建编排」选择「编辑」，名称填写 `jidiu-gomuku`，
粘贴 compose.1panel.yaml 的内容。首次启动需要联网拉取 Node 镜像、安装依赖及构建。
如果使用其他上传目录，请同时修改 build.context。

编排运行后查看容器日志，应出现服务器启动成功的提示。
本服务的启动日志为 `READY 3000`。
在面板终端执行 `curl http://127.0.0.1:3000/health`，应得到 status 为 ok 的 JSON。

## 让手机能连接

无域名时，放行服务器防火墙和云安全组的 TCP 3000 端口，App 中填写 `公网IP:3000`。
不要关闭整个防火墙。若端口已占用，可将编排 ports 改为 `"3001:3000"`，App 对应填写 3001。

有域名时，可在 1Panel 网站中创建反向代理、配置 HTTPS，并启用 WebSocket 转发。
代理必须将 /socket.io/ 请求传递给本服务，同时转发 Upgrade 与 Connection 请求头。
如果 OpenResty 运行在另一个容器中，它的 127.0.0.1 并非宿主机，不能直接以
127.0.0.1:3000 作为代理目标；应使用面板可达的宿主机地址，或将双方接入同一个 Docker 网络，
通过服务名 jidiu-gomuku:3000 代理。网络名称以该服务器的实际配置为准。
App 中填写完整地址，例如 `https://game.example.com`。

## 验收

1. 外网访问 /health 成功。
2. 两台设备连接同一地址，一台创建房间，另一台使用房间码加入。
3. 双方准备、交替落子，并测试聊天、悔棋、认输及再来一局。

支持五子棋与围棋（9 / 13 / 19 路）。房间保存在内存中，重启服务会结束当前房间；掉线后重新进房开局。
无需数据库。服务端协议版本为 2，需要与本次新版 App 配套。

官方编排文档：https://docs.fit2cloud.com/1panel/user_manual/containers/compose/
