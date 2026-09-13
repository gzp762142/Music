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

### 实机诊断（`bdd992f` / `285503d`）

诊断行读到：`#w1 sbsY tf:auto(-90°) · sp 1194×834 · sc 1194×834 · win 781×528`

据此排除与确认：

- `#w1` → 进程内只有 1 个悬浮窗口；T5 的窗口单例成立，重影不是「多窗口」。
- `sp/sc 1194×834`、`win 781×528` → 布局空间与窗口尺寸都是横版，几何正常。
- 用户补充的现象是关键判据：**App 内两份，退出 App 后只剩一份**。

### 根因（S1.4 最终结论）

窗口交给 SpringBoard 托管后，**托管层与 App 自身场景会各渲染一份**：

| 那一份 | 来源 | 朝向 |
|---|---|---|
| 竖版、被转 -90°、显得更大 | App 自己的场景 | 错（补偿只对托管那份有效） |
| 横版、正向 | SpringBoard 托管层 | 对 |

退出 App 后 App 场景不参与合成，所以只剩正确的那一份 —— 与观察完全一致。

### 修法（T7）

- **本地窗口层级压到 App 主窗口之下**（`levelLocal = -1`）：本地那份被 App
  不透明底盖住，屏幕上只留 SpringBoard 托管那一份。
- **注册给 SpringBoard 的层级仍是 `statusBar + 2000`**：跨 App 悬浮不变。
- 不再 `makeKeyAndVisible`，避免抢走 App 主窗口的 key。
- 面板默认**正居中**（原先偏上 6%）——用户的明确要求。
- 诊断行增加 `lv` 字段，便于确认本地层级。

这一点也解释了为什么之前「补偿方向怎么调都不对」：
两个渲染目标需要的变换相反，只调一个必然有一份是歪的。

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
- [x] T7: 本地层级压到 App 之下 + 默认居中 — acceptance: App 内与退出后都只有一份、且是正向的那一份；面板正居中 (covers: S1.4, S2; depends: T5)
- [ ] T4: 推 CI 出包并在 iPad 上确认 — acceptance: CI 绿；装包后 4 项现象全部消失 (covers: S1; depends: T1, T2, T3, T5, T6, T7)
