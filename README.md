# 灵枢 Roguelike Demo

Godot 4 回合制修仙 Roguelike Demo。当前目标是在炼气地图中积累灵枢、形成构筑并检查筑基条件。

当前展示版默认以 1280×720 全屏启动，`F11` 可切换窗口模式。正式原型资源位于 `assets/art`、`assets/ui/generated` 与 `assets/audio`；音频可由 `scripts/tools/generate_audio.ps1` 重新生成。

## 当前流程

1. 完成试炼木傀教学，选择一门入门功法并获得绑定神通。
2. 进入滚动生成的山野路线，在战斗、机缘、修炼、休息、商店、宝箱、精英与Boss节点间选择。
3. 通过奖励和节点结果积累长期灵枢，在休息处选择闭关并检查筑基条件。

战斗资源只存在于当前丹田。长期灵枢、已学功法、神通、法宝、物品、灵石和地图进度保存在单局运行状态中。当前不实现筑基后的新境界或转生；炼气商店与宝箱已经可以实际使用。
## 炼气期 Vertical Slice

当前版本已经形成“教学战 → 五行功法选择 → 持续路线探索 → 战斗/事件/修炼/休息/宝箱/商店/精英/Boss → 闭关检查筑基”的完整循环。地图滚动生成，不会因固定节点耗尽而停止。

核心规模：五门入门功法、27门炼气神通（含教学用灵气冲击）、12件法宝、6种随机池普通敌人、3种精英和1名阶段Boss。神通永久掌握并受10点基础神识限制；丹田灵气按灵枢比例随机凝聚并在回合末散逸。

验证命令：

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path F:\rogue res://tests/DemoFlowTest.tscn
Godot_v4.7-stable_win64_console.exe --headless --path F:\rogue res://tests/VerticalSlicePlaytest.tscn
```
