# Gravix

一个面向 Windows 远程桌面的原生 macOS RDP 客户端。界面使用 SwiftUI，桌面视图使用 AppKit，连接引擎为 FreeRDP 3.32.1。

## 直接使用

打开 `build/Gravix.app`，点击“新建会话”，填写 Windows 主机地址、用户名及账户密码。默认端口为 3389。Windows 需要开启远程桌面；首次连接须核对证书。

应用已打包运行库，不需要用户安装 Homebrew、FreeRDP 或 FFmpeg。当前产物是 Apple silicon / macOS 14+ 的本地开发版，使用 ad-hoc 签名，并为本地动态库设置 library-validation entitlement；正式分发时应以同一 Developer ID 签署应用和所有运行库，再移除此开发例外；尚未经过真实 Windows 主机的端到端验证，也未做 Developer ID 公证。

## 已实现

- 原生连接管理、收藏、搜索、多个独立会话窗口、全屏、连接取消。
- 紧凑会话工作台：顶部新建/连接工具栏、侧边栏保存列表、收藏和历史搜索，已有会话窗口可快速唤回。
- 设置页（侧边栏或 ⌘,）：默认 Liquid Glass，可切换简洁风格、跟随系统/浅色/深色以及四种强调色；自动保存并应用到会话窗口。macOS 26+ 使用原生玻璃材质，macOS 14/15 回退磨砂材质，开启“减少透明度”时使用实色面板。
- FreeRDP TLS/NLA 连接；首次和变更证书使用原生确认弹窗，由 FreeRDP 保存已信任证书。
- H.264 AVC420 + FFmpeg VideoToolbox 硬件解码；可关闭。实际编码由服务端协商。
- macOS Keychain 保存密码；JSON 配置和进程参数不含密码。
- 文字剪贴板双向同步，⌘C / ⌘V 等映射到 Windows Ctrl 快捷键。
- Mac → Windows：Finder 复制文件、应用“发送文件”或拖入文件，然后在 Windows 文件夹内粘贴。
- Windows → Mac：在 Windows 复制文件，点击“接收文件”或 ⌘⇧V，选择保存位置。接收完成后文件也放到 Mac 剪贴板，可到 Finder 粘贴。
- 剪贴板文件的分块传输、中文文件名、进度、取消、失败清理，以及路径穿越与请求边界校验。
- 显式选择文件夹后，通过 RDPDR 双向共享到 `\\tsclient\Gravix`。
- Display Control 分辨率调整与可选 Retina 分辨率；不支持时本地按比例显示。
- 最近 200 次连接的时间、结果和时长；历史不会保存密码。

## 开发

已安装本项目运行库时，双击 `Gravix.xcodeproj`，选择 Gravix scheme，点击 Run。

完整重新构建：

```sh
./Scripts/build-dependencies.sh  # 首次构建；所有依赖在项目内部，无 sudo
./Scripts/build.sh              # 构建 Release app，产物在 build/Gravix.app
./Scripts/test.sh               # 安全、存储、钥匙串、文件通道、连接失败及硬件解码测试
./Scripts/check-bundle.sh       # 签名、运行库闭包和打包后的 Windows 加密依赖测试
```

`Scripts/generate-project.py` 可重建 Xcode 工程。`Scripts/make-icon.swift` 生成应用图标源，`Scripts/bundle-libraries.py` 收集 dylib 依赖并移除开发机绝对路径。OpenSSL legacy provider 也随应用打包，用于 Windows NTLM 所需的密码派生算法。

依赖版本与来源：

| 组件 | 版本 | 用途 |
| --- | --- | --- |
| FreeRDP / WinPR | 3.32.1 | RDP、NLA、GFX、CLIPRDR、DISP、RDPDR |
| FFmpeg | 8.1.3 | H.264 / VideoToolbox、图像格式转换；LGPL 共享库构建 |
| OpenSSL | 3.5.9 | TLS、NTLM 所需加密操作 |
| CMake | 3.31.10 | 仅构建工具 |
| pkg-config | 0.29.2 | 仅构建工具 |

源码地址和构建选项都在 `Scripts/build-dependencies.sh`；开源许可位于 `Resources/THIRD_PARTY_NOTICES.txt`。FFmpeg 以共享库链接，未启用 GPL 或 nonfree 组件，允许按 LGPL 要求替换/重链接。

## 结构

- `Sources/Gravix`：界面、连接资料、钥匙串、会话/窗口生命周期。
- `Sources/RDPBridge/GravixRDP.mm`：协议事件循环、图像更新、输入、证书确认、原生剪贴板和文件传输。
- `Sources/RDPBridge/TransferSafety.hpp`：文件路径和块边界验证。
- `Tests`：真实库调用与受控输入的回归测试，不使用用户的远程主机或密码。

## 验证范围

本机通过 Release 编译、签名和依赖闭包检查；钥匙串读写、删除以及密码不写入 JSON；文件描述符、中文路径、分块文件读写、恶意路径拒绝和取消清理；回环地址连接失败处理；VideoToolbox 实际 H.264 硬件帧解码，以及 FreeRDP AVC420 到 BGRA 的输出验证。

0.2 界面在本机实际验证了侧边栏图标与留白点击、⌘, 打开设置、Liquid Glass/简洁风格切换、深浅色与强调色切换、重启后保留设置，以及新建会话表单。旧系统材质回退和“减少透明度”分支尚未做实机检查。

未验证：真实 Windows 认证、完整桌面交互、服务器策略下的剪贴板/驱动器重定向、自适应分辨率，以及不同 Windows 版本兼容性。

当前不包含 RD Gateway、Entra ID 交互登录、RemoteApp、音视频设备重定向、图片剪贴板和自动重连。Windows 到 Mac 的文件接收由应用按钮/快捷键触发，未提供直接在 Finder 粘贴远程文件的延迟下载机制。剪贴板文件传输不接受符号链接，最多 10,000 项，名称限 Windows FILEDESCRIPTORW 长度；大量文件可使用共享目录。传输过程中改变 Windows 剪贴板会取消当前接收。

## 数据位置

连接与历史：`~/Library/Application Support/Gravix/connections.json`，目录权限 0700，文件权限 0600。密码：钥匙串中的 `com.gravix.desktop.rdp` 服务，每个连接一个条目。删除连接会删除其密码。应用不提供云同步，不上传这些资料。
