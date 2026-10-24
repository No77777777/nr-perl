---
name: nr5g-drop-rlf-log-analysis
description: 分析 NR5G QXDM/QCAT 过滤日志中的掉线/无线链路失败问题（RLF、波束失败、上行挂起、RRC 重建），输入为过滤后的解码文本。
---

# NR5G 掉线 / RLF 日志分析

## 触发条件
用户报告通话或数据中断后恢复（出现 RRC 重建），且提供了经过 Perl 工具过滤的掉线日志文本。

## 输入格式说明
- 每条消息前有块头 `=== 八位序号 0x类型 ===`，序号用于证据引用。
- 事件标记 `>>> RACH_TRIGGER`、`>>> RACH_ATTEMPT`、`>>> SERVING_CELL`、`>>> SKIP_UL_TX`、`>>> RLM_STATS`、`>>> UL_BSR` 已由过滤脚本插入。
- 文件末尾附 TX_SUSPEND 次数、DCI 次数、BSR 次数等摘要。

## 分析流程
1. 定位起点：0xB889 的 RACH 触发原因（RLF / BEAM_FAILURE / SR_Failure）与 0xB959 的 Purpose。
2. 重建波束失败过程：0xB959 中 IS/OOS 滤波 BLER 逐帧变化，确认是否达到 beamFailureInstanceMaxCount。
3. 检查上行挂起：0xB8AE 中 Drop Reason=TX_SUSPEND 与 Drop Chan Type（PUCCH/PUSCH），统计挂起起止。
4. 检查调度中断：0xB885 中上下行 DCI 最后一次下发时刻，确认网络侧是否停止调度。
5. 检查缓冲堆积：0xB860 PDCP UL Stats 缓冲字节、0xB868 RLC UL、0xB873 BSR。
6. 确认恢复路径：RACH SUCCESS 或 ABORTED → 服务小区变化 → RRC 重建 → 业务恢复。

## 关键消息与字段速查
- 0xB889 MAC RACH Trigger：Rach Reason。
- 0xB88A MAC RACH Attempt：RACH Result（SUCCESS/ABORTED/FAILURE_MSG4_CT_TIMER_EXPIRED）、Msg1~Msg4。
- 0xB959 ML1 RLM Stats：Purpose（BEAM_FAILURE/RLF）、IS Filt/OOS Filt BLER。
- 0xB8AE MAC Skip UL TX：Drop Reason（TX_SUSPEND/CDRX_INACTIVE/TX_BLANKING）、Drop Chan Type。
- 0xB885 MAC DCI Info：上下行授权是否中断。
- 0xB860 / 0xB868 / 0xB873：PDCP/RLC 缓冲与 BSR 上报。
- 0xB823：服务小区 PCI 变化（切换/重建前后）。

## 判定规则
- SR/BSR 待处理但 PUCCH 被 TX_SUSPEND 丢弃：MAC 层上行挂起，并非 RRC 配置缺失。
- DCI 完全中断且无 RACH 上行授权：网络侧不再调度，UE 无法上报。
- 波束失败恢复 RACH 连续失败或 ABORTED：触发 RLF，进入 RRC 重建。
- PDCP SN 冻结 + 缓冲持续增长：数据停摆，支持上行阻塞结论。

## 输出要求
- 分阶段时间线：正常 → 劣化（波束失败）→ 挂起（无调度）→ 重建恢复。
- 明确每个阶段的关键字段证据与日志块号。
- 给出根因（波束失败/网络侧停止调度/其他）与置信度说明。

## 注意事项
- TX_SUSPEND 抑制实际发送，SR/BSR 的触发逻辑仍可处于 pending，两者不矛盾。
- 区分波束失败恢复成功与最终 RLF：以 RACH 结果与服务小区变化为准。
