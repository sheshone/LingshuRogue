# 数据结构

静态模板保存在 JSON，当前 HP、已掌握能力、背包和材料等变化保存在 `RunState`。

# Unit

玩家与敌人均由 `UnitFactory` 创建：

```json
{
  "unit_id": "bandit",
  "template_id": "bandit",
  "unit_type": "cultivator",
  "faction": "enemy",
  "name": "强盗",
  "hp": {"current": 52, "max": 52},
  "shield": 0,
  "attributes": {"tendencies": {}},
  "skills": {
    "spell_ids": [],
    "ability_ids": ["bandit_slash", "bandit_guard"]
  },
  "spiritual_sense": {
    "base_capacity": 3,
    "capacity_modifiers": {}
  },
  "inventory": {"water_talisman": 1},
  "resources": {},
  "statuses": {},
  "selected_action": {}
}
```

# Action 来源

## 神通

文件：`data/spells.json`。神通永久掌握，并消耗玩家丹田灵气。

```json
{
  "id": "qi_strike",
  "name": "灵气冲击",
  "sense_cost": 1,
  "cost": {"all_sea_qi": true, "minimum": 1},
  "effects": [
    {
      "type": "damage",
      "value": 4,
      "target": "opponent",
      "scaling": {"source": "spent_qi_total", "per_point": 1}
    }
  ]
}
```

`all_sea_qi` 是通用消耗模式；施法结果会把本次实际消耗量写入 `spent_qi_total`，效果可以通过 `scaling` 读取。`scaling.source` 也支持 `status`，通过 `status`、`target` 和 `per_point` 按状态层数提高效果。该接口不依赖具体神通 ID。

`sense_cost` 是神通占用的神识容量。玩家模板通过 `spiritual_sense.base_capacity` 提供初始容量，运行时加成保存在 `capacity_modifiers`。神通奖励超过容量时不会直接写入技能列表，而是进入替换流程；替换成功后同时遗忘旧神通并学习新神通。

## 单位能力

文件：`data/abilities.json`。构装体、修士敌人和妖兽引用这里的能力。

## 消耗品

文件：`data/items.json`。

```json
{
  "id": "water_talisman",
  "type": "consumable",
  "name": "水波符",
  "combat_use": {
    "effects": [
      {"type": "damage", "attribute": "water", "value": 12, "target": "opponent"}
    ]
  }
}
```

`use_item` 成功后从执行者 Unit 的 `inventory` 扣除一件。符箓不会加入神通列表。

# Effect

通用 `CombatEffectExecutor` 根据 `effects` 执行伤害、护盾、状态或丹田资源效果。`self` 指行动者，`opponent` 指当前目标。

治疗：

```json
{"type": "heal", "value": 8, "target": "self"}
```

`target` 支持 `self`、`opponent`、`all_opponents` 和 `ally`。`ally` 默认选择同阵营生命比例最低的存活友军，也可以通过 `target_id` 指定已存在的 Unit。

`add_status` 与 `consume_status` 使用通用状态 ID。`consume_status` 设置 `"all": true` 时消耗指定目标的全部对应状态。

攻防强化：

```json
{
  "type": "buff",
  "status": "attack_up",
  "value": 30,
  "duration": 1,
  "target": "ally"
}
```

Demo 只支持 `attack_up` 与 `defense_up`。`value` 是百分比，`duration` 是对应伤害触发次数：攻击提升在造成伤害时消耗，防御提升在受到伤害时消耗。状态统一保存在 Unit 的 `statuses`。

敌人意图直接显示 ability 或 item 的 `name` 和 `description`，UI 不根据 effect 类型拼装意图文字。

# 奖励

文件：`data/reward_tables.json`。每张奖励表可以同时定义 `fixed_rewards` 和 `choice_groups`。

```json
{
  "id": "training_puppet_rewards",
  "fixed_rewards": [],
  "choice_groups": [
    {
      "id": "intro_method_choice",
      "choose": 1,
      "options": [
        {"type": "learn_method", "method_id": "flame_method", "set_active": true},
        {"type": "learn_method", "method_id": "earth_method", "set_active": true},
        {"type": "learn_method", "method_id": "water_method", "set_active": true}
      ]
    }
  ]
}
```

神通奖励：

```json
{"type": "learn_spell", "spell_id": "fireball"}
```

消耗品奖励接口：

```json
{"type": "consumable", "item_id": "water_talisman", "quantity": 1}
```

材料奖励：

```json
{"type": "material", "item_id": "red_flame_core", "quantity": 1}
```

长期灵枢灵气奖励：

```json
{"type": "add_core_qi", "qi": "fire", "value": 5}
```

该奖励调用长期 `add_core_qi`，不修改当前丹田。

功法奖励：

```json
{"type": "learn_method", "method_id": "flame_method", "set_active": true}
```

神通写入 `player.skills.spell_ids`；功法写入 `RunState.learned_method_ids`；消耗品进入 `player.inventory`；材料进入 `RunState.materials`；法宝进入 `RunState.relics`。不同资源域互不混用。

奖励表可以通过 `include_table_ids` 组合共享奖励层。同一场战斗引用多个敌人奖励表时，共享表只展开一次，避免多敌人战重复生成成长选择。

选择组支持：

- `candidate_count`：从合法候选中显示的数量。
- `randomize`：是否在截取候选前随机排序。
- `skippable`：是否允许不领取该层奖励并继续结算。
- `requirements.not_learned` 与 `requirements.not_owned`：排除已学神通和已有法宝。

固定奖励在胜利时自动应用，无需点击领取。当前普通战依次生成神通三选一和五行灵气三选一，两层均可跳过；精英战在此之后追加法宝三选一。

法宝奖励：

```json
{"type": "relic", "relic_id": "scarlet_flame_pearl"}
```

# 功法

文件：`data/cultivation_methods.json`。

```json
{
  "id": "flame_method",
  "name": "赤炎诀",
  "description": "以火行灵气为根基的基础功法。",
  "element_affinity": {"fire": 1.2},
  "initial_spell_id": "fireball",
  "replaces_spell_ids": ["qi_strike"],
  "effects": [
    {"type": "modifier", "target": "spell_tag:fire", "effect": "damage_up", "value": 10}
  ]
}
```

`CultivationMethodManager` 支持学习、选择当前功法、读取五行倾向和执行通用 modifier。首次选择入门功法时，管理器学习 `initial_spell_id`，并从玩家已掌握列表移除 `replaces_spell_ids`。`spell_tag:*` 可以强化匹配标签的伤害，`effect:shield` 可以强化护盾，`battle_rule:sea_retention` 可以改变丹田保留比例；均不依赖功法 ID。

# 法宝

文件：`data/relics.json`。法宝是保存在 `RunState.relics` 的单局规则修改器，不进入神通或物品列表。

```json
{
  "id": "mystic_water_bottle",
  "name": "玄水瓶",
  "effects": [
    {"type": "modifier", "target": "battle_rule:sea_retention", "effect": "retention_up", "value": 25}
  ]
}
```

当前通用接口支持 `battle_start` 的 `trigger_effect`，以及丹田、护盾保留规则的 `modifier`。新增法宝通过这些通用触发器和规则目标表达，不在 BattleManager 中判断法宝 ID。

# 战斗配置

文件：`data/battle_setups.json`。每关定义 `enemy_ids`、是否启用属性倍率以及下一关 ID。第三关通过两个 `enemy_ids` 生成双狼。

# 敌人池

文件：`data/encounter_pools.json`。

```json
{
  "id": "qi_refining_normal",
  "type": "normal",
  "enemy_count": 1,
  "enemy_ids": ["rock_shell_tortoise", "withered_vine_spirit"]
}
```

战斗配置没有显式 `enemy_ids` 时，可以使用：

```json
{
  "encounter_pool_id": "qi_refining_normal",
  "enemy_count": 1
}
```

BattleManager 会随机选取池内不重复的敌人。该接口不依赖地图系统。

# 地图节点

文件：`data/map_nodes.json`。地图保存固定节点及其有向连接；当前节点只允许选择 `next_node_ids` 中列出的节点。

```json
{
  "id": "qr_event",
  "name": "溪边遗刻",
  "type": "event",
  "layer": 1,
  "content_id": "event_stream_inscription",
  "description": "溪水冲刷出一块刻有行气图的青石。",
  "next_node_ids": ["qr_cultivation"]
}
```

当前支持 `battle`、`elite`、`event`、`cultivation`、`rest`、`breakthrough`。战斗类节点通过 `battle_setup_id` 进入通用战斗场景；其他节点通过 `content_id` 进入通用节点场景。

文件：`data/map_node_contents.json`。事件、修炼、休息和突破检查均使用通用内容数据。

```json
{
  "id": "event_stream_inscription",
  "type": "event",
  "title": "溪边遗刻",
  "choices": [
    {
      "id": "absorb_water",
      "name": "顺水参悟",
      "description": "水灵气增加10。",
      "effects": [
        {"type": "add_core_qi", "qi": "water", "value": 10}
      ]
    }
  ]
}
```

当前节点效果支持 `add_core_qi`、`add_item`、`heal_player_full` 和 `convert_core_qi`。炼气容量固定，现有炼气节点不调用 `add_core_capacity`。

突破条件来自 `data/breakthrough_rules.json`，当前支持灵枢总量、主功法对应属性数量与比例、当前功法和精英完成次数；不检查灵枢容量，检查通过也不会进入筑基境界。

地图运行态保存在 `RunState`：`current_realm_id`、`current_map_id`、`current_map_node_id`、`visited_map_node_ids`、`completed_map_node_ids` 和 `chapter_progress`。这些字段不写回玩家模板。

# 地图生成规则

文件：`data/map_generation.json`。`map_nodes.json` 只保存固定拓扑和随机槽；首次进入境界地图时，生成器按规则填充随机槽，并把完整结果保存到 `RunState.generated_map_definition`。

```json
{
  "id": "qi_refining_generation",
  "map_id": "qi_refining_region",
  "random_node_ids": ["qr_l1_a", "qr_l1_b", "qr_l2_a", "qr_l2_b", "qr_l3_a", "qr_l4_a"],
  "type_weights": {
    "battle": 50,
    "event": 25,
    "cultivation": 25
  },
  "minimum_type_counts": {
    "battle": 3,
    "event": 1,
    "cultivation": 1
  },
  "maximum_elite_count": 1,
  "battle_pool": [
    {
      "battle_setup_id": "map_qi_normal",
      "encounter_pool_id": "qi_refining_normal",
      "enemy_count": 1
    }
  ],
  "event_pool": [
    {"content_id": "event_stream_inscription"}
  ],
  "cultivation_pool": [
    {"content_id": "cultivation_stone_platform"}
  ]
}
```

随机战斗节点通过 `encounter_pool_id` 交给 BattleManager，从对应敌人池抽取敌人。事件和修炼节点分别从内容池抽取 `content_id`。返回同一地图时读取已生成定义；只有重新开始该境界地图才清空并重新生成。

炼气图的精英、休息、商棚/宝匣占位和突破节点不属于随机槽。主路线经过4层随机节点后进入整备分支，再汇入唯一精英节点和突破节点。突破节点使用 `always_visible` 与 `early_access` 声明独立入口；检查失败时通过 `previous_map_node_id` 回到尝试前位置继续探索。

MapUI 同时渲染当前节点的直接后继和这些后继的下一层连接。直接后继是可点击卡片，再下一层只作为禁用预览卡片显示连接来源。

战斗神通区以可重叠卡牌横排渲染，不使用滚动技能列表。每张卡片显示名称、专属插画、图片化灵气图标、消耗和核心效果；完整描述与神识占用放入 Tooltip。五行、通用灵气、法宝与地图节点统一使用图集素材，不依赖系统 Emoji 字体。

# 预留敌人字段

敌人模板可以包含 `phases` 和 `stances`。当前只保存这些字段，不执行阶段切换、姿态切换、属性免伤或 Boss 特殊规则。

# 五行倍率

文件：`data/attribute_rules.json`。当前只使用相克关系：金克木、木克土、土克水、水克火、火克金，倍率为 `1.5`，其他情况为 `1.0`。只有第三关启用。

# 灵枢与丹田

灵枢长期保存五行实际储量。每回合基础凝聚量等于玩家神识总容量，并按灵枢组成比例生成；存在当前主功法时，至少凝聚1点对应属性。神通的 `add_sea_qi` 不得修改长期灵枢。

丹田散逸规则来自灵枢 `battle_projection.retention`：

```json
{
  "base_rate": 0.5,
  "maximum_rate": 0.9,
  "maximum_total": 3
}
```

回合结束时丹田基础保留率为0，未消耗灵气全部散逸。功法与法宝可以通过通用规则增加保留率；保留量向下取整，并受 `maximum_rate` 与 `maximum_total` 双重限制。

未来法宝增加神识容量时使用：

```json
{"type": "modifier", "target": "player_rule:spiritual_sense_capacity", "effect": "capacity_up", "value": 1}
```

该 modifier 由通用法宝管理器写入 `spiritual_sense.capacity_modifiers`，不判断法宝 ID。

# 材料扩展位置

材料可以带 `future_processing` 字段，为未来炼化或其他处理预留引用位置。当前 Demo 不读取或执行该字段。

# 滚动探索与精英保底

`map_generation.json` 使用通用精英遭遇规则：

```json
{
  "elite_encounter": {
    "base_weight": 2,
    "weight_per_node": 4,
    "guaranteed_at": 6,
    "reset_on_victory": true
  }
}
```

`RunState.elite_encounter_counter` 记录连续未完成精英战的普通探索节点数。生成器只读取计数与规则，不判断敌人或地点 ID。精英胜利通过通用节点完成记录将计数归零。

地图池支持 `boss_pool`、`treasure_pool` 和 `shop_pool`。Boss 节点引用 `battle_setup_id` 与 `encounter_pool_id`；宝箱和商店引用通用 `content_id`。

休息选项可声明 `breakthrough_rule_id`。当前突破条件类型为 `core_qi_total`、`method_affinity_qi`、`active_method` 和 `learned_spell_count`，不读取精英完成数。

本局经济保存为 `RunState.spirit_stones`。地图选项通过 `spirit_stone_cost` 声明价格；战斗奖励使用 `{"type":"spirit_stones","value":10}` 增加灵石。灵石不写入玩家模板。

奖励候选允许使用 `weight`。`randomize: true` 时按权重进行不放回抽取，再截取 `candidate_count` 个候选。未填写时权重为1。普通奖励可在同一个选择组中混合 `add_core_qi`、`material`、`consumable` 与 `learn_spell`。

商店沿用地图选项结构：

```json
{
  "spirit_stone_cost": 8,
  "effects": [{"type": "forget_spell", "spell_id": "fireball"}]
}
```

当前商店效果接口包括 `add_item`、`learn_spell`、`add_relic`、`forget_spell` 和 `convert_core_qi`。购买前统一检查灵石、重复持有、神识容量和转换来源，检查失败不扣款。

# Vertical Slice 通用战斗扩展

战斗效果新增：

- `convert_sea_qi`：在当前丹田中转换五行灵气，不影响灵枢。
- `consume_shield`：消耗指定数量或全部护盾。
- `damage/heal/shield.scaling.source = shield/status`：从通用状态或当前护盾读取缩放。
- `condition.hp_ratio_lte`：根据目标生命比例决定效果是否执行，可用于收割与阶段性技能。

敌人行动策略可以包含通用阶段：

```json
{
  "type": "sequence",
  "actions": [],
  "phases": [
    {"hp_ratio_lte": 0.5, "actions": []}
  ]
}
```

战斗管理器按生命比例选取阶段行动列表，不读取敌人 ID。法宝触发器当前支持 `battle_start`、`turn_start` 和 `after_spell`；法宝也可使用 `spell_tag:*` 修改带对应标签的神通。

休息处炼化通过 `data/processing_recipes.json` 配置。`process_recipe` 消耗材料并递归执行通用地图效果，当前用于钢齿妖丹与赤炎妖丹。
# 第二轮纵切新增接口（2026-08）

## 展示资源

界面以 1280×720 为逻辑基准并支持缩放至 960×540。神通卡、按钮、战斗背景与人物/妖兽图集均为项目资源，不保存在数据模板中。音乐按 `map/battle/elite/boss/shop/rest/breakthrough` 场景名读取；音效按 `click/cast/hit/shield/qi/relic/purchase/chest/breakthrough` 事件名读取，缺失资源时才使用程序音备用音色。

## 节点动态货架

`data/node_offer_tables.json` 保存商店与木匣候选池。`offer_count` 控制一次展示数量，`weight` 控制基础权重，`tags` 只提供轻度功法倾向加权，不作流派排他。候选按地图节点实例缓存：重开同一节点不会刷新，下一次遇到新节点会重新生成。商店允许连续购买并主动离开；木匣只能取一件，也可以合匣不取。

## 探索收束

`map_generation.json.boss_encounter` 定义 Boss 最早出现深度、逐层增权和保底深度。`RunState.run_completed` 与 `completion_summary` 只保存本局章节结算；在休息处闭关且满足突破条件后写入，进入炼气篇结算场景。

## 法宝可感知状态

法宝可选字段 `icon` 用于战斗栏标记。触发型法宝按 `relic_id + trigger + effect` 执行，战斗运行态记录本场触发次数；这些次数不写回法宝模板。
