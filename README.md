# Music

iOS 壳子（加载 → 卡密 → 控制台），身份皮对齐 Apple Music。

- Bundle: `com.apple.Music`
- 最低系统: iOS 13.0
- 图标: 脱壳 `Apple Music_3.4_decrypted.ipa` 内 `AppIcon*.png`（CgBI 已转标准 PNG）
- 产物: GitHub Actions 编出 unsigned `Music.tipa`

## FangUI 接入（对齐 TrollEngine）

- `FangUISystemWindow`（ObjC）：`_isSystemWindow` / `_isWindowServerHostingManaged=NO` / `_isSecure` / `_shouldCreateContextAsSecure`
- `windowLevel = statusBar + 2000`（SHMainWnd 同款）
- `FangUISBSHosting`：`objc_getClass("SBSAccessibilityWindowHostingController")` + `registerWindowWithContextID:atLevel:`（`_contextId`）
- 进后台不释放，心跳 reassert + **重新 register**
- **形态＝悬浮卡片**：窗口只覆盖卡片本身（四周各留 14pt 阴影边距），卡片不透明、圆角 22、带阴影，卡片之外透出桌面或下层 app
- **尺寸与位置**：面板宽 `min(max(屏宽 × 0.42, 360), 560)`、高 `min(max(屏高 × 0.62, 320), 470)`，默认居中偏上，始终夹在屏幕内；顶栏左侧是拖拽把手，拖完的位置写回 `FangUIBridge.setPanelFrame`，心跳重设几何时沿用
- **方向纠偏**：面板视图直接挂在窗口上（宿主 VC 退化为只管窗口状态的空壳），窗口 / 宿主视图 / 面板视图的 `transform` 在每轮布局里强制归位，压掉 UIKit 按界面方向施加的 90° 旋转
- 卡片内＝顶栏 / 滚动内容 / 底栏三段；页面宽度由约束链锁定（页面 → 内容容器 → 滚动视口 → 卡片 → 窗口），高度由内容撑开，`UIStackView` 既不会被摊开、也不会被压成 1 字符宽
- 顶栏与行标题一律单行截断，宽度异常时不会退化成逐字竖排
- 顶栏品牌行显示 `UI THEME KIT · v5`，底栏上方一行诊断信息显示 `win / card / tf` —— 用来确认实际运行的是哪一版、几何与旋转是否正常
- 顶栏：品牌 → 标题 + 副标题 →（窄卡片折两行）主题开关 · Ready 徽章 · `✕`；底栏：图标 + 文字药丸
- entitlements 不改（已有 accessibility-window-hosting）

## 本地生成工程

```bash
brew install xcodegen
xcodegen generate
open Music.xcodeproj
```

## CI

push / 手动触发 `Build tipa`，Actions → Artifacts 下载 `Music-tipa`。  
打 tag（如 `v1.02`）会把 tipa 附到 Release。
