# Music

iOS 壳子（加载 → 卡密 → 控制台），身份皮对齐 Apple Music。

- Bundle: `com.apple.Music`
- 最低系统: iOS 13.0
- 图标: 脱壳 `Apple Music_3.4_decrypted.ipa` 内 `AppIcon*.png`（CgBI 已转标准 PNG）
- 产物: GitHub Actions 编出 unsigned `Music.tipa`

## FangUI 接入

- **独立 `FangUIOverlayWindow`**，`windowLevel`：前台 `statusBar+1`，后台 `alert+1000`
- 进后台 **不释放**，心跳 + 生命周期通知里 `reassert`（配合 platform / no-sandbox / accessibility-window-hosting）
- **半透明可拖小面板**（约 340×520），空白区 `hitTest` 穿透，不全屏挡游戏
- **卡密后默认关**；电源开 / 音量+ 显示；电源关 / 音量- / 面板「关闭」隐藏并释放
- 身份 entitlements 不改

## 本地生成工程

```bash
brew install xcodegen
xcodegen generate
open Music.xcodeproj
```

## CI

push / 手动触发 `Build tipa`，Actions → Artifacts 下载 `Music-tipa`。  
打 tag（如 `v1.02`）会把 tipa 附到 Release。
