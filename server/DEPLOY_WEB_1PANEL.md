# 网页版与联机服务一起部署到 1Panel

本压缩包已包含编译好的 Flutter 网页、五子棋和围棋服务端。无需在服务器安装 Flutter。

1. 在 1Panel 文件管理中新建 `/opt/jidiu-gomuku`，将本包上传并解压到当前目录。
2. 确认 `/opt/jidiu-gomuku/server/Dockerfile` 和 `/opt/jidiu-gomuku/server/web/index.html` 存在。
3. 在「容器 → 编排 → 创建编排」选择「编辑」，文件夹填写 `jidiu-qishi`，粘贴 compose.1panel.yaml 的内容并创建。
   如果之前已经部署同名棋室编排，更新该编排并重新构建，不能同时再占用 3000 端口。
4. 在服务器防火墙及云安全组中放行 TCP 3000。
5. 访问 `http://101.37.85.166:3000/` 即可打开棋室；健康检查为同地址的 `/health`。

网页与 Socket.IO 联机服务使用同一地址。首次打开联机大厅会自动填入当前网站地址，
双方访问同一网站、选择相同棋种，建房、分享房间码、准备即可对局。
之前手动保存过服务器地址的浏览器，会保留原设置；必要时在大厅改为当前网站地址。

网页渲染资源已本地打包。房间保存在内存里，重启服务或断线后需要重新进房开局。

有域名后，可以在 1Panel 建立反向代理并配置 HTTPS。需要转发 WebSocket Upgrade，
而且 OpenResty 容器中的 127.0.0.1 不是宿主机地址；代理目标必须在其所在网络可达。
网页会自动使用当前 HTTPS 域名连接联机服务，不需要重新编译。

如果已有棋室服务，更新前先等正在进行的对局结束。请保留已有服务配置和部署文件。

## 更新与常见问题

更新源文件后必须重新构建镜像，单纯重启容器不会更新镜像中的代码和网页。
若编排文件位于以下默认位置，可执行：

```bash
docker compose -f /opt/1panel/docker/compose/jidiu-qishi/docker-compose.yml up -d --build
```

实际文件名和路径以 1Panel 中显示的编排目录为准。

- 端口占用：用 `docker ps --filter publish=3000` 查找旧容器，确认不再使用后停止；也可将映射改成 `3001:3000`，容器内部 PORT 保持 3000。
- 公网无法访问：先检查 `curl http://127.0.0.1:3000/health`，再检查服务器防火墙与云安全组是否放行对应端口。
- 白屏且 CanvasKit 返回 500：查看容器日志。若报 `EACCES`，确认 Dockerfile 在 `COPY web/` 后、`USER node` 前包含 `RUN chmod -R a+rX /app/web`，然后重新构建。新版部署包已经包含该修复。
- 更新后页面仍旧：按 Ctrl + Shift + R 强制刷新。渲染资源使用本地 CanvasKit，无需访问外部渲染资源 CDN。
