# Music

iOS 壳子（加载 → 卡密 → 控制台），身份皮对齐 Apple Music。

- Bundle: `com.apple.Music`
- 最低系统: iOS 13.0
- 图标: 脱壳 `Apple Music_3.4_decrypted.ipa` 内 `AppIcon*.png`（CgBI 已转标准 PNG）
- 产物: GitHub Actions 编出 unsigned `Music.tipa`

## FangUI 接入

- 源码：`Aether/FangUI/`（UIKit 菜单 + Metal 特效，来自 `ui_uikit_metal`）
- **开启** 控制台电源 → 全屏弹出 FangUI
- **关闭** 电源 / 右上角「关闭」→ 自动收起
- 重命名 `AppState` → `FangUIState`，避免与壳子状态冲突

## 本地生成工程

```bash
brew install xcodegen
xcodegen generate
open Music.xcodeproj
```

## CI

push / 手动触发 `Build tipa`，Actions → Artifacts 下载 `Music-tipa`。  
打 tag（如 `v1.02`）会把 tipa 附到 Release。
