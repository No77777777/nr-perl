---
name: nr5g-throughput-log-analysis
description: 分析 NR5G QXDM/QCAT 过滤日志中的上下行速率问题（速率低、波动、调度不足、BLER 高等），输入为过滤后的解码文本。
---

# NR5G 上下行速率日志分析

## 触发条件
用户报告下行或上行速率不达标、速率波动大、RB 资源未占满、BLER 高，且提供了经过 Perl 工具过滤的速率日志文本。

## 输入格式说明
- 每条消息前有块头 `=== 八位序号 0x类型 ===`，序号用于证据引用。
- 块头下一行是设备时间戳（注意用户会声明时区，通常为 UTC）。
- 文件末尾附事件摘要和按消息类型的统计。

## 分析流程
1. 确定测试窗口与业务方向切换点：下行 TB 字节大幅下降、上行 TB 字节大幅上升的时段即切换点；先下后上与同传要分开统计。
2. 计算速率：下行用 0xB888 CRC Pass TB Bytes 累计值差分，或用 0xB887 每条 PDSCH 的 TB Size 求和；上行用 0xB883 中 PUSCH 记录的 TB Size 求和。
3. 检查调度是否喂饱：RB 占用率、MCS、层数、调制方式、DCI 次数。
4. 检查链路质量：BLER、HARQ ACK/NACK、CQI/RI、SNR、发射功率。
5. 分层归因：区分应用层/PDCP 层与物理层差异、区分首传与重传口径。

## 关键消息与字段速查
- 0xB885 MAC DCI Info：上下行授权次数、MCS（注意动态表头）。
- 0xB887 MAC PDSCH Status：TB Size、MCS、Rbs、RV、HARQ Id、K1、Layers、CRC State、Mod Type。
- 0xB883 MAC UL Physical Channel Schedule Report：PUSCH 的 RB Start/Num RBs、MCS、TB Size、TX Mode、TX Type（NEW_TX/RETX）。
- 0xB888 MAC PDSCH Stats：Num CRC Pass/Fail TB、Num ReTx、CRC Pass TB Bytes（累计值）。
- 0xB89B MAC UCI Information：HARQ ACK/NACK 反馈。
- 0xB8A7 MAC CSF Report：CQI、RI、PMI。
- 0xB8D8 LL1 SERVING SNR：各 RX 天线 SNR。
- 0xB8B5 MAC Tx Pwr Dist Stats：上行发射功率分档。

## 判定规则
- BLER 持续高于 10%：链路质量差，优先查 SNR/RSRP，再看 MCS 被压低。
- RB 占用率长期低于 60% 且缓冲有数据：调度受限或配置限制。
- MCS 高但速率低：检查层数、调制与 TB Size，是否被误用单层。
- 上行重传率（TX Type=RETX 占比）高：上行链路受限或功率受限。

## 输出要求
- 按秒或按相给出速率、RB、MCS、BLER、CQI/RI、SNR 的汇总表。
- 时间线描述业务方向切换与异常时段。
- 每个结论附日志块号（=== 序号 0x类型 ===）作为证据。

## 注意事项
- 物理层速率含重传与协议开销，会高于应用层测速软件结果。
- 累计计数器必须用前后两次的差值，不能用单条数值。
