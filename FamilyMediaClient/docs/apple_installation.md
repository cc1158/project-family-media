# 家映 iPhone 与 Apple TV 长期安装指南

这份指南用于把家映覆盖安装到家里的 iPhone 和 Apple TV，并在后续升级时保留 NAS 地址、播放设置和 Jellyfin 会话。

## 1. 先选择签名方式

- 免费 Apple ID 的 Personal Team 可以用于短期真机调试，但配置文件有效期很短，不适合无人维护的长期安装。
- 如果希望长时间使用，建议使用付费 Apple Developer Program 团队签名。签名和设备授权仍有有效期，到期前需要覆盖安装新包。
- TestFlight 适合测试分发，不是永久安装方式；测试包到期后需要更新。

无论使用哪种方式，后续升级都必须保持下列标识不变：

```text
iPhone:   com.senhu.familymedia.ios
Apple TV: com.senhu.familymedia.tv
Team:     由本机 LocalSigning.xcconfig 提供同一个 Apple Developer Team
```

如果 Bundle ID 或签名团队被更换，系统可能将它视为另一个 App，而不是原 App 的升级。

## 2. 每次安装前准备

1. 在 Mac 上安装完整 Xcode 和 XcodeGen。
2. 使用将要签名的 Apple ID 登录 Xcode。
3. 首次在这台 Mac 上开发时，查询 Apple Developer Team ID，然后生成只保存在本机的签名配置：

```bash
cd FamilyMediaClient
python3 scripts/configure_local_signing.py YOUR_TEAM_ID
```

Team ID 可在 Xcode 的 Settings > Accounts 中选择 Apple ID 和对应 Team 后查看。

`LocalSigning.xcconfig` 已被 Git 忽略，只保存 Team ID，不会上传到公开仓库。更换开发团队时重新执行该命令即可。

4. 在 `project.yml` 中同时更新 iOS 和 tvOS 的版本号与构建号。
5. 执行：

```bash
cd FamilyMediaClient
python3 scripts/validate_release_configuration.py
xcodegen generate
swift test
open FamilyMediaClient.xcodeproj
```

6. 确认 Signing & Capabilities 没有红色签名错误。两个 App 和测试 Target 会从 `LocalSigning.xcconfig` 继承同一个 Team；以后重新运行 XcodeGen 不需要再次手工选择。

GitHub CI 不使用本机文件，而是通过 `CODE_SIGNING_ALLOWED=NO` 验证代码和通用构建。CI 产物不能直接安装到真机，真机安装仍需要本机证书、设备授权和有效的 Provisioning Profile。

## 3. 安装到真实 iPhone

1. 用数据线连接 iPhone 与 Mac，并在两端完成“信任此电脑”。
2. 在 Xcode 的 Window > Devices and Simulators 确认 iPhone 可见。
3. 选择 `FamilyMediaiOS` Scheme，运行目标选择该 iPhone。
4. 点击 Run，等待编译、签名和安装完成。
5. 首次开发调试时，iPhone 可能要求开启“开发者模式”并重启。
6. 首次访问 NAS 时允许家映使用“本地网络”。

## 4. 安装到真实 Apple TV

1. 让 Mac 和 Apple TV 连接同一个家庭网络。
2. Apple TV 进入“设置 > 遥控器与设备 > 遥控器 App 与设备”，保持在配对页。
3. Mac 上打开 Xcode 的 Window > Devices and Simulators，选择 Apple TV 并输入电视显示的配对码。
4. 选择 `FamilyMediaTV` Scheme，运行目标选择该 Apple TV。
5. 点击 Run，安装完成后从 Apple TV 主屏幕打开家映。
6. 保存 Xcode 中的配对关系；下次在同一网络通常可以直接覆盖安装。

## 5. 安全升级，不丢配置

1. 不要先删除设备上的家映。
2. 保持 Bundle ID 和 Team 不变，只递增版本号和构建号。
3. 用 Xcode Run 或正式分发包直接覆盖安装。
4. 升级后先检查设置页显示的版本和构建号。
5. 确认家庭媒体地址、Jellyfin 地址、播放数量和照片停留时间仍在。
6. 确认 Jellyfin 仍为已登录，并播放一个 Direct Play 和一个转码视频。

覆盖安装会保留 UserDefaults 中的地址与播放选项，也会保留 Keychain 中的 Jellyfin 会话。如果手动删除 App，应当按新安装处理，不要依赖系统恢复旧配置。
新版启动时会检查已保留的播放数量和照片停留时间；如果旧版留下的值超出当前范围或存储格式已损坏，会自动修复为安全值，不影响服务地址和 Jellyfin 登录。

## 6. 安装后的最小验收

- 两个来源可以同时打开，切换来源不会退出另一个。
- 重启 App 后 Jellyfin 仍保持登录。
- iPhone 横竖屏可用，Apple TV 遥控器焦点可正常移动。
- H.264 MP4 使用 Direct Play，AVI/XVID 等使用 Jellyfin HLS 转码。
- 暂停、切换媒体和退出播放器后，Jellyfin 不留下无人使用的转码任务。
- 更完整的验收项见 [release_checklist.md](release_checklist.md)。

## 7. 常见问题

### 提示“不受信任的开发者”

先确认 Xcode 已用当前 Apple ID 签名。如果系统仍要求信任，到设备的 VPN 与设备管理页查找对应开发者。新版系统也可能先要求开启开发者模式。

### 连接不上 NAS

确认设备与 NAS 在同一家庭网络，然后检查家映的“本地网络”权限、NAS IP、端口、Docker/Jellyfin 状态。服务地址不能使用 `localhost`。

iPhone 上可从家映的“设置 > 帮助与诊断”直接打开系统设置，然后确认“本地网络”已允许。

### 覆盖安装后出现了两个家映

这通常表示 Bundle ID 或签名团队发生了变化。不要继续分别使用两个 App；先回到 `project.yml` 修复稳定标识，再确认哪一个包保留了正确配置。
