# Music

iOS 壳子（加载 → 卡密 → 控制台），身份皮对齐 Apple Music。

- Bundle: `com.apple.Music`
- 最低系统: iOS 13.0
- 图标: 脱壳 `Apple Music_3.4_decrypted.ipa` 内 `AppIcon*.png`（CgBI 已转标准 PNG）
- 产物: GitHub Actions 编出 unsigned `Music.tipa`

## FangUI 接入

- 源码：`Aether/FangUI/`（UIKit 菜单 + Metal 特效）
- **独立 `UIWindow`**，`windowLevel = statusBar + 1`，不是 keyWindow 上的 subview
- 依赖 Music 身份证（platform / no-sandbox / springboard window-hosting）尽量悬浮在其他 App 之上
- **卡密通过后默认关闭**
- **开启** 电源 → 创建并显示悬浮窗；**关闭** → hidden 并释放
- **音量+** → 显示；**音量-** → 隐藏（电源状态可不变）
- 右上角「关闭」= 关电源并收起

## 本地生成工程

```bash
brew install xcodegen
xcodegen generate
open Music.xcodeproj
```

## CI

push / 手动触发 `Build tipa`，Actions → Artifacts 下载 `Music-tipa`。  
打 tag（如 `v1.02`）会把 tipa 附到 Release。
