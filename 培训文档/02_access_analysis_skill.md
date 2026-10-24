---
name: nr5g-access-log-analysis
description: 分析 NR5G QXDM/QCAT 过滤日志中的接入问题（搜网慢、无服务、Attach/Registration 拒绝、随机接入失败），输入为过滤后的解码文本。
---

# NR5G 接入问题日志分析

## 触发条件
用户报告搜网慢、无服务、Attach/Registration 被拒绝、注册后不建业务，且提供了经过 Perl 工具过滤的接入日志文本。

## 输入格式说明
- 每条消息前有块头 `=== 八位序号 0x类型 ===`，序号用于证据引用。
- 事件标记 `>>> RACH_TRIGGER`、`>>> RACH_ATTEMPT`、`>>> SERVING_CELL` 已由过滤脚本插入。
- RRC OTA 文本内嵌 NAS 消息，需按 3GPP TS 24.501 解码关键 IE 与 cause。

## 分析流程
1. 定基线：用 0xB823 服务小区消息梳理驻留小区变化时间线。
2. RRC 建链：在 0xB821 中找 RRC Setup / SetupComplete / Reject 及原因。
3. NAS 注册：跟踪 Registration request → accept/reject，记录 5GMM cause；0xB80C 看注册状态变化。
4. 随机接入：0xB889 看触发原因，0xB88A 看 Msg1~Msg4 成功失败点。
5. 搜网评估：0xB970/0xB96F 看空闲态 S 准则与连接态小区评估，0xB98F 看天线分集切换。

## 关键消息与字段速查
- 0xB821 RRC OTA Packet：RRC Setup、RRC Reject、RRCRelease，内嵌 NAS。
- 0xB80C NAS MM5G State：注册状态（DEREGISTERED/REGISTERED）。
- 0xB80D NAS MM5G Service Request：业务请求。
- 0xB823 RRC Serving Cell Info：PCI、DL/UL Frequency、Bandwidth。
- 0xB889 MAC RACH Trigger：Rach Reason（INITIAL_ACCESS/RLF/BEAM_FAILURE 等）。
- 0xB88A MAC RACH Attempt：Msg1~Msg4 位图、RACH Result、RA_RNTI、C_RNTI。
- 0xB970 / 0xB96F：空闲态 S 准则、连接态小区评估。

## 判定规则
- Registration reject 5GMM cause 27（N1 mode not allowed）：N1 被网络禁止，勿按 APN 问题处理。
- Attach reject EMM cause 17（Network failure）且伴随无效 DNN/APN：数据配置问题。
- RACH 多次 FAILURE_MSG4_CT_TIMER_EXPIRED：竞争解决失败，检查上行链路与小区拥塞。
- 连续 RACH 失败且服务小区不变：优先怀疑上行受限，而非小区选择异常。

## 输出要求
- 输出 RRC→NAS→RACH 的接入流程时间线。
- 明确拒绝/失败原因（cause 值与含义），区分 RRC 层与 NAS 层问题。
- 每个结论附日志块号作为证据。

## 注意事项
- 设备日志通常为 UTC，与本地时间存在固定偏差，先对齐再下结论。
- 单次 RACH 失败不代表接入失败，要看是否有后续成功与 NAS 层结果。
