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
- **面板不透明**：`UIWindow` / 宿主 VC / `RootViewController` 三层同一个底色，整块画面只有 FangUI，不透出桌面或下层 app
- **几何以场景坐标空间为准**：`windowScene.coordinateSpace.bounds` 直接给 window frame；不再按 `interfaceOrientation` 手工拼长宽（旧逻辑会让 iPad 横屏内容转 90°、整块错位并露出桌面）
- 根控制器＝**铺满窗口 + 顶栏 / 滚动内容 / 底栏**三段；页面高度按内容计算，`UIStackView` 不再被容器摊开成巨大间距
- 顶栏：品牌 → 标题 + 副标题 →（窄屏折两行）主题开关 · Ready 徽章 · `✕`；底栏：图标 + 文字药丸
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
