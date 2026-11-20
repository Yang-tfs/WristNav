# 腕上导航（WristNav）

为 **红米 Watch 6 + iPhone（iOS 16.3.1，TrollStore 环境）** 定制的腕上转向提示方案。

## 重要：先读这一节

### 这块手表能做到什么、不能做到什么

红米 Watch 6 运行小米封闭的 HyperOS 3，不支持安装任意第三方 App，也没有离线地图。**因此无法在手表上运行真正的地图导航 App**（这一点与小米 Watch 2 Pro / Apple Watch 不同）。

本方案走的是另一条路：

```
iPhone 上跑导航逻辑 → 生成转向通知 → iOS 通知中心 → ANCS → 手表显示文字 + 震动
```

手表上看到的是**文字转向卡片**（例如「↰ 200米后 右转 · 建国路」）和震动提醒，**不是地图画面**。这是该硬件条件下能实现的最佳形态。

### 第一步：零成本验证（决定是否真的需要这个 App）

这一步不需要安装任何东西，5 分钟完成。它可能直接省掉编译 App 的工作。

1. iPhone → 设置 → 蓝牙 → 忽略此设备（红米 Watch 6），然后用 **Mi Fitness（小米运动健康）** 重新配对
2. Mi Fitness → 设备 → REDMI Watch 6 → **消息通知** → 打开总开关，勾选高德地图、微信、提醒事项
3. iPhone → 设置 → 通知 → 高德地图 → 允许通知，且「锁定屏幕 / 通知中心 / 横幅」三项全开
4. 在 iPhone 的「提醒事项」建一个 1 分钟后的提醒，或让朋友发一条微信
5. **观察手表是否震动并显示通知文字**
6. 打开高德地图开始一段骑行/步行导航，观察手表上出现什么

判定决策树：

| 验证结果 | 结论 | 下一步 |
|---|---|---|
| 普通通知能到手表，且高德导航通知也到了 | **ANCS 通道通畅，直接用高德即可** | 无需编译 App，直接用高德导航，本 App 可作为格式优化备选 |
| 普通通知能到，但高德导航通知不到 | 高德用了实时活动（Live Activity）而非普通通知 | 编译安装本 App，按距离主动发通知，绕开高德的通知形式 |
| 普通通知都到不了 | 配对/权限问题，或该固件通知转发路径不同 | 先重配对、关勿扰、更新 Mi Fitness；仍不行则反馈，我换方案 |

**关键提示**：iOS 上高德导航主要依赖「实时活动 / 灵动岛」，而实时活动不走 ANCS 通知通道。因此第 6 步很可能收不到——这正是本 App 存在的意义：用标准本地通知替代实时活动，确保手表能收到。

## 技术原理

| 环节 | 实现 |
|---|---|
| 路线规划 | Apple MapKit（中国大陆使用高德数据），无需 API Key |
| 定位 | CoreLocation，`requestAlwaysAuthorization` + 后台 location/audio 模式保活 |
| 转向计算 | 沿路线折线投影当前位置，计算到下一 maneuver 的剩余距离 |
| 通知触发 | 500m / 200m / 50m 三档阈值，各自播报一次 |
| 偏航处理 | 距路线 > 80m 触发重新规划（60 秒限频） |
| 投递到手表 | 本地通知写入 iOS 通知中心，红米 Watch 6 通过 BLE **ANCS** 自动接收 |

### 为什么 TrollStore 是关键

iOS 严格限制第三方 App 的后台定位与保活。TrollStore 安装的 App 可以：
- 自由声明 `UIBackgroundModes`（location + audio）
- 用 `ldid` 伪签名绕过 App Store 签名校验
- 长期后台运行而不需要 Apple 开发者账号

## 编译安装

### 构建方式：GitHub Actions（已配置完成）

本机是 Windows，无需 macOS 即可出包。仓库 `Yang-tfs/WristNav` 已配置好 `.github/workflows/build.yml`，使用 `macos-latest` runner 自动安装 Xcode 工具链与 ldid，产出 IPA 并上传为 artifact。

**当前状态**：IPA 已成功构建并下载到本地 `WristNav.ipa`（97 KB，已验证结构与签名配置）。

需要重新构建时（改了源码后）：

```bash
# 1. 用 API 推送源码（本机 git 协议不可达，走 Git Data API）
GITHUB_TOKEN=<token> python .workbuddy_api_push.py "提交说明"

# 2. 触发 Actions（dispatch 返回 204 即成功）
#    POST /repos/Yang-tfs/WristNav/actions/workflows/build.yml/dispatches

# 3. 等待构建完成后下载 artifact
#    GET /repos/Yang-tfs/WristNav/actions/artifacts/<id>/zip → 302 到 Azure SAS URL
#    注意：Azure 不接受 gho_ token，需取重定向 Location 后不带 Authorization 下载
```

也可以在浏览器打开 `https://github.com/Yang-tfs/WristNav/actions`，手动点 Run workflow 触发，然后从 Artifacts 下载。

### 本机编译（可选）

若有 macOS + Xcode，直接：

```bash
brew install ldid
chmod +x build.sh && ./build.sh
```

产出 `build/WristNav.ipa`。

### 安装到 iPhone

1. 把 IPA 传到 iPhone（AirDrop 或文件 App）
2. 用 **TrollStore** 打开 IPA → Install
3. 首次启动时按提示开启：
   - 定位服务 → **始终**
   - 通知 → **允许**
   - 后台 App 刷新 → 开启
4. 打开 App，输入目的地，开始导航

### 使用建议
- 手机放在车架 / 臂包上，保持蓝牙连接（手机与手表距离 < 10 米）
- 骑行时把「设置 → 蓝牙 → 红米 Watch 6」的通知权限确认开启
- 导航结束后点「结束导航」，会清除通知中心的导航卡片

## 已知限制

| 限制 | 说明 |
|---|---|
| 无地图画面 | 手表只显示文字 + 震动，无路线图、无箭头动画 |
| 依赖手机 | 手机必须随身且亮屏/后台运行，导航计算在手机端 |
| 通知延迟 | ANCS 通知到手表通常 1-2 秒延迟 |
| 路线数据 | MapKit 在中国大陆覆盖一般，复杂路口/小路可能规划不准 |
| 电量 | 后台持续定位耗电明显，长途骑行建议带充电宝 |
| 驾驶安全 | 不建议驾车时频繁抬腕查看，转向以语音/手机支架为主，手表作为辅助 |

## 可配置项

想调整参数可修改源码后重新编译：

- `NavigationEngine.swift` → `alertDistances`：通知触发距离（默认 500/200/50 米）
- `NavigationEngine.swift` → `offRouteThreshold`：偏航阈值（默认 80 米）
- `RoutePlanner.swift` → `request.transportType`：`.automobile` / `.walking`
- `Models.swift` → `ManeuverKind`：转向类型与箭头映射

## 文件结构

```
WristNav/
├── Sources/
│   ├── WristNavApp.swift        # App 入口 + 静音音频保活
│   ├── ContentView.swift        # SwiftUI 界面
│   ├── NavigationEngine.swift   # 核心导航引擎（定位/推进/偏航）
│   ├── RoutePlanner.swift       # MapKit 路线规划
│   ├── NotificationBridge.swift # 本地通知桥（ANCS 投递）
│   └── Models.swift             # 数据模型
├── .github/workflows/build.yml  # GitHub Actions 云编译配置
├── Info.plist                   # 权限声明
├── entitlements.plist           # TrollStore 伪签名权限
├── build.sh                     # 编译脚本（Actions 与本机共用）
├── .workbuddy_api_push.py       # 绕开 git 协议的 API 推送工具
├── .workbuddy_check_run.py      # 构建状态查询工具
├── WristNav.ipa                 # 已构建的产物（可直接安装）
└── README.md
```

## 仓库与构建记录

- 仓库：https://github.com/Yang-tfs/WristNav （public）
- 最近成功构建：run `44757356383`，artifact id `14640330161`，conclusion `success`
- 已验证：IPA 内含 `Payload/WristNav.app/WristNav`（arm64 可执行文件）+ Info.plist，后台模式 `location`/`audio` 声明正确
