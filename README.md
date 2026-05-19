# 团本划水检测 Raid Water Check

魔兽世界团本表现复盘插件。插件默认只记录 Boss 战，在战斗结束后生成团队表现摘要，帮助团长快速查看死亡、无动作、打断、驱散、承伤、可规避伤害和关键技能使用情况。

## 功能

- Boss 战后自动生成表现报告
- 可选记录小怪/非 Boss 战
- 统计伤害、有效治疗、承伤、死亡、打断、驱散、施法次数
- 统计长时间无动作
- 支持自定义可规避伤害技能
- 支持自定义关键技能检查
- 点击玩家查看个人详情
- 支持右上角插件集合入口和小地图备用按钮
- 支持手动通报异常玩家到团队/队伍频道
- 可视化设置面板，包含基础设置、高级设置和权重设置
- 可选 NAXX/WCL 冲分参考提示，标记可能不计入 WCL 排名的目标伤害或特殊 Buff

## 安装

下载 Release 中的 `RaidWaterCheck-0.1.0.zip`，解压后放入：

```text
World of Warcraft/_retail_/Interface/AddOns/RaidWaterCheck
```

怀旧服请放入对应版本的 `Interface/AddOns` 目录。如果插件列表提示过期，可先勾选“加载过期插件”，或按客户端版本修改 `RaidWaterCheck.toc` 里的 `Interface` 数字。

## 命令

```text
/rwc
/huashui
/rwc menu
/rwc show
/rwc options
/rwc announce
/rwc demo
/rwc trash
/rwc rules
/rwc avoid add 技能ID 技能名
/rwc avoid del 技能ID
/rwc track add 技能ID 技能名 [职业英文] [最低次数]
/rwc track del 技能ID
/rwc minimap
```

## 说明

插件定位是“复盘辅助”，不是自动定罪工具。DPS 低可能来自机制分工、转火、跑位、死亡、装等、职业环境或团队策略，需要结合实际战斗判断。

调试界面时可以输入 `/rwc demo` 生成一份虚拟副本记录，用于查看单场报告、副本总结、Boss 展开和个人详情的排版。

右上角插件集合入口和小地图按钮左键会打开操作面板，里面可以直接点单场报告、副本总结、设置、演示数据和清除记录；命令仍然保留。

NAXX/WCL 参考模式只做游戏内提示，不等同于 Warcraft Logs 官方结算。WCL 最终仍以上传后的日志和官方规则为准。

## 合规

- 不自动操作角色
- 不自动施法
- 不修改游戏客户端文件
- 不联网，不上传战斗数据
- 只读取游戏插件 API 提供的战斗日志事件
- 团队通报必须由玩家手动点击按钮或输入命令触发
