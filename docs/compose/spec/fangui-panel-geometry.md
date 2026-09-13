---
feature: fangui-panel-geometry
status: in-progress
updated: 2026-09-13
branch: main
commits: 18b698a..HEAD
---

# FangUI 悬浮面板几何与方向修正

## Report

## [S1] Problem

iPad 横屏上，开启菜单后的悬浮面板有可见缺陷（录屏 `a03c7bc8…mp4` / `7aada180…mp4`）：

1. 面板内容整体旋转 90°。
2. 旋转角度进一步变成 180°，字样看起来是镜像。
3. 卡片位置错乱：跑到屏幕左上、部分出屏。
4. 屏幕同时出现**多份面板**：一份正的、一份转过的、左上角还有残片。

S1.4 的根因在复核与实机录屏对照后确认：`hide()` 把窗口置 nil，
而窗口的 SpringBoard 托管上下文不会随之注销；下一次 `show()` 又新建窗口，
多个 contextID 同时被托管 → 叠加显示。**已在 T5 修复**（窗口单例 + 注册幂等）。

### 实机诊断（`bdd992f`，用户截图）

诊断行读到：`#w1 sbsY tf:auto(-90°) · sp 1194×834 · sc 1194×834 · win 781×528`

据此排除与确认：

- `#w1` → **进程内只有 1 个悬浮窗口**，T5 的窗口单例成立，重影不是「多窗口」造成的。
- `sp/sc 1194×834`、`win 781×528` → 布局空间是横屏、窗口是横版，几何正常。
- 截图主面板 `BUTTONS / Primary / Ghost / Exit` **方向正确** → 方向补偿生效。
- 残留：**左上角一份更小、转过的副本**。

结合 `sbsY`（托管已注册）与「本进程只有 1 个窗口」，剩余重影最可能来自
**SpringBoard 托管层与 App 自身场景各渲染一份**：我们给窗口施加的补偿让
**本地那份**变正，而托管那份由 SpringBoard 以自己的坐标空间再合成一次，于是转掉。
该判断**尚未证实**，需要一次对照实验（见下）。

### 待做的判定实验（阻断 T4）

面板上**双指长按** → 徽章变 `sbs off·重启` → **重启 App** → 观察左上角副本是否消失。

- 消失 ⇒ 确认是托管层重复渲染。此时要在「跨 App 可见」与「单份正确」之间定方案：
  (a) 关托管：单份正确，但只在 App 前台可见；
  (b) 留托管、抑制本地渲染：需查清 SpringBoard 对托管层的方向/位置约定；
  (c) 换一种跨 App 呈现方式。
- 不消失 ⇒ 另有来源，需要新的判据（例如逐帧对比两次渲染的尺寸差）。

## [S2] Design

- **窗口单例**：窗口只在首次 `show()` 创建，`hide()` 只摘面板并
  `isHidden = true`，**不销毁**；contextID 全程唯一，SpringBoard 只托管一层。
- **注册幂等**：`registerWithSpringBoard` 用已注册窗口做保护，
  不再在每个心跳 / 生命周期回调里重复注册。
- **坐标空间**：`UIWindowScene.coordinateSpace` 与 `UIScreen.main.bounds`
  谁跟旋转走在文档与实测上不一致，因此不赌：取一个来源的尺寸后，
  用界面方向把长边摆到宽上（`layoutSpace()`），横屏恒有 width > height。
- **位置夹取**：窗口绕自身中心旋转，因此夹取用 **旋转后的包围盒** 半宽半高。
- **方向修正**：`PanelOrientation` 覆盖 9 档（auto + 4 旋转 + 4 反射），
  长按品牌区循环切换，选择持久化到 `UserDefaults`。
- **方向来源**：实时 `scene.interfaceOrientation` **优先于**桥内缓存，
  避免兜底探测写入的缓存把方向冻住；兜底通知路径同样刷新缓存，
  块式观察者用 token 注销。
- **拖动**：存 **中心点**（窗口带变换时 `frame` 是包围盒，会漂）。
- **诊断**：诊断行显示 `sp / screen / win / 当前档位`，用于实机定位。

- **逻辑开关**：窗口长期存在后，必须另设 `isOpen`。生命周期通知/注册重试/心跳
  全部以它为门，否则「已收起」的菜单会被前台事件重新亮出来并抢 key。
- **收起要 flush**：关闭多发生在 App 已退后台时，`isHidden` 后补一次
  `CATransaction.flush()`，确保隐藏状态赶在挂起前进入 CA。
- **面板停表**：`CADisplayLink(target: self)` 会强引用控制器，`deinit` 里的
  `invalidate()` 永远执行不到。改用弱代理，并由宿主在收起时显式 `setActive(false)`。

## [S3] Out of Scope

- 不改 identity（Bundle / entitlements / 图标）。
- 不改 SpringBoard 托管注册方式与窗口层级。
- 不改 FangUI 菜单的视觉设计与分页内容。

## Tasks
- [x] T1: 布局空间按界面方向归一化 + 旋转包围盒夹取 — acceptance: 面板各档位下完整可见、居中略偏上，不再出屏 (covers: S2)
- [x] T2: `PanelOrientation` 9 档 + 长按循环 + 持久化 — acceptance: 长按依次切换，诊断行显示档位，重启保留 (covers: S2)
- [x] T3: 面板视图单实例（`attachPanel` / `hide`） — acceptance: 反复开关后窗口内只有一份面板视图 (covers: S2)
- [x] T5: 窗口单例 + 注册幂等 — acceptance: 反复开关、切前后台后屏幕上只出现一份面板，无重影 (covers: S1.4, S2; depends: T3)
- [x] T6: `isOpen` 门控 + `hide` flush + displayLink 弱代理 — acceptance: 收起后前后台切换不会重新亮出菜单；收起后不再 60fps 空转 (covers: S2; depends: T5)
- [ ] T4: 推 CI 出包并在 iPad 上确认 — acceptance: CI 绿；装包后 4 项现象全部消失 (covers: S1; depends: T1, T2, T3, T5, T6)
