# Music

iOS 壳子（加载 → 卡密 → 控制台），身份皮对齐 Apple Music。

- Bundle: `com.apple.Music`
- 最低系统: iOS 13.0
- 图标: 脱壳 `Apple Music_3.4_decrypted.ipa` 内 `AppIcon*.png`（CgBI 已转标准 PNG）
- 产物: GitHub Actions 编出 unsigned `Music.tipa`

## 本地生成工程

```bash
brew install xcodegen
xcodegen generate
open Music.xcodeproj
```

## CI

push / 手动触发 `Build tipa`，Actions → Artifacts 下载 `Music-tipa`。  
打 tag（如 `v1.02`）会把 tipa 附到 Release。
