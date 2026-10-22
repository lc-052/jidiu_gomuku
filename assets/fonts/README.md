# 本地中文字体

JidiuSans-Regular.otf 由 [Noto Sans SC Regular](https://github.com/notofonts/noto-cjk/tree/main/Sans/SubsetOTF/SC) 裁剪并重新命名，遵循同目录 OFL.txt 中的 SIL Open Font License 1.1。原字体内的版权及授权元数据保留。

包含 GB2312 字符集、拉丁字符、标点及项目界面文本使用的字符。Web 主题优先使用该字体，常用中文不需要请求外部字体服务；未收录的生僻字或 emoji 仍可能触发引擎回退字体。

更新步骤：安装 fonttools，下载上游 NotoSansSC-Regular.otf 后运行 `python tools/subset_font.py 字体文件路径`。修改界面文本后可重新生成。
