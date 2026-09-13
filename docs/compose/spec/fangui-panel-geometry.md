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

iPad 横屏上，开启菜单后的悬浮面板有四个可见缺陷（来自用户录屏 `a03c7bc8…mp4`）：

1. 面板内容整体旋转 90°（`Overview` / `BUTTONS` 竖排阅读）。
2. 旋转角度进一步变成 180°，字样看起来是镜像。
3. 卡片位置错乱：跑到屏幕左上、部分出屏，拖动后更明显。
4. 面板疑似多份叠加 / 残留（重影）。

## [S2] Design

- **坐标空间**：几何一律基于当前 `UIWindowScene.coordinateSpace.bounds`，
  不再用 `UIScreen.main.bounds`（横屏时常返回竖屏尺寸，正是卡片被算到屏幕外的原因）。
- **位置夹取**：窗口绕自身中心旋转，因此夹取用 **旋转后的包围盒** 半宽半高，
  保证任何档位下面板都完整留在屏幕内。
- **方向修正**：新增 `PanelOrientation`，把「抵消系统旋转」建模为 8 档
  （auto / 0° / ±90° / 180° / mirror ×3）。`auto` 由界面方向推导；
  其余档位可在设备上 **长按品牌区循环切换**，选择持久化到 `UserDefaults`。
  之所以档位化：系统在 SpringBoard 托管之上叠加的旋转组合无法在 Windows 侧复现，
  用一次装机即可定档，避免反复重编。
- **单实例**：`attachPanel(to:)` 保证窗口内只有一份面板视图；`hide()` 显式
  `removeFromSuperview()` 并清空拖动位置。
- **拖动**：改存 **中心点**（`setPanelCenter`）而非 `frame`；
  窗口带变换时 `frame` 是包围盒，用它做平移会漂。
- **方向来源**：`FBSOrientationObserver`（私有）为主，`scene.interfaceOrientation`
  与 `UIDevice` 兜底；结果缓存，避免每次布局都 new 一个 observer。
- **诊断**：卡片内诊断行显示 `sp / win / 当前档位`，用于确认跑的是哪一版。

## [S3] Out of Scope

- 不改 identity（Bundle / entitlements / 图标）。
- 不改 SpringBoard 托管注册方式与窗口层级。
- 不改 FangUI 菜单的视觉设计与分页内容。

## Tasks
- [ ] T1: 几何改用 scene 空间 + 旋转包围盒夹取 — acceptance: 面板在横屏各档位下都完整可见、居中略偏上，不再出屏 (covers: S2)
- [ ] T2: 新增 `PanelOrientation` 并接长按循环 — acceptance: 长按品牌区可依次切换 8 档，诊断行显示当前档位，选择重启后保留 (covers: S2)
- [ ] T3: `attachPanel` / `hide` 单实例收敛 — acceptance: 反复开关与旋转后，屏幕上只有一份面板 (covers: S2; depends: T1)
- [ ] T4: 推 CI 出包并在 iPad 上确认 — acceptance: CI 绿；装包后 4 项现象全部消失 (covers: S1; depends: T1, T2, T3)
