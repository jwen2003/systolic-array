# Systolic Array MVP: 时钟频率缩放分析

## 1. 实验范围与可追溯环境

[已建立事实] 本实验只使用 $N=2$、$K=2$、`DATA_W=8`、`ACC_W=18`。五个频点均从read_slang frontend开始独立执行mapping、floorplan、placement、CTS、global/detailed routing、RC extraction、final STA、GDS和KLayout DRC，没有复用其他频点的netlist、ODB、SPEF或placement结果。

- ORFS commit：`6101364b2d7909dd797e1e3e7f80695401cfa4e4`；
- 固定镜像：`openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`；
- OpenROAD：`26Q3-1305-gf552262465`；
- 容器Yosys：`0.68+post`；OpenSTA：`3.1.0`；
- 平台与corner：Nangate45 typical；
- `LEC_CHECK=0`。

[工具兼容性限制] `LEC_CHECK=0`只禁用在当前CPU上启动即发生`SIGILL`的Kepler stage LEC；没有禁用CTS、STA、routing、extraction、GDS或DRC。每个频点的baseline RTL到derived frontend equivalence均为843/843个`$equiv` proven。Post-synthesis equivalence仍为`inconclusive_tool_scalability`，post-route equivalence未证明。

[已建立事实] 除clock period外，所有点继续复用Butterfly的400 MHz active-operation评测口径：0.050 ns clock uncertainty、0.050 ns clock/input transition、0.250 ns input/output delay、0.010 output load、50% core utilization、1:1 aspect ratio和0.10 placement density lower-bound addon。`rst_n`是同步低有效复位；STA假设它在operation开始前释放并在运行期间稳定，且不验证外部reset assertion/deassertion接口时序。

## 2. 完成状态与时序

| 配置 | Period | Nominal target | 状态 | Setup WNS / TNS | Hold WNS / TNS |
|---|---:|---:|---|---|---|
| `clk_2500ps` | 2.500 ns | 400.000 MHz | `flow_completed_timing_met` | +0.720010 ns / 0 | +0.065023 ns / 0 |
| `clk_2250ps` | 2.250 ns | 444.444 MHz | `flow_completed_timing_met` | +0.475454 ns / 0 | +0.064492 ns / 0 |
| `clk_2000ps` | 2.000 ns | 500.000 MHz | `flow_completed_timing_met` | +0.219901 ns / 0 | +0.064352 ns / 0 |
| `clk_1750ps` | 1.750 ns | 571.429 MHz | `flow_completed_timing_met` | +0.085547 ns / 0 | +0.064006 ns / 0 |
| `clk_1500ps` | 1.500 ns | 666.667 MHz | `flow_completed_timing_met` | +0.024937 ns / 0 | +0.065251 ns / 0 |

[已建立事实] 五个点均完成到final route、extracted STA、GDS和KLayout DRC，setup与hold均通过，unconstrained endpoint为0。因此本次离散测试范围内没有出现首个timing failure；只能说明最高受测nominal target 666.667 MHz仍收敛，不能确定下一失效点。

[已建立事实] 400 MHz fresh结果精确重现已提交baseline的setup/hold WNS、2068个functional standard cells和3522.64 µm² final functional standard-cell area。工具、ORFS commit、flow参数和约束内容除受控period外一致。

## 3. Mapping、placement与实现成本

| Target | Mapped cells / area | Placement cells / area | Final cells / area | Timing-repair buffers | Final clock buffers |
|---:|---|---|---|---:|---:|
| 400.000 MHz | 1902 / 3442.57 µm² | 2052 / 3502.95 µm² | 2068 / 3522.64 µm² | 152 | 9 |
| 444.444 MHz | 1902 / 3442.57 µm² | 2051 / 3501.09 µm² | 2067 / 3521.84 µm² | 151 | 9 |
| 500.000 MHz | 1902 / 3442.57 µm² | 2052 / 3502.16 µm² | 2068 / 3523.17 µm² | 152 | 9 |
| 571.429 MHz | 1902 / 3442.57 µm² | 2064 / 3512.00 µm² | 2080 / 3529.82 µm² | 164 | 11 |
| 666.667 MHz | 1902 / 3442.57 µm² | 2354 / 3869.50 µm² | 2372 / 3896.63 µm² | 456 | 9 |

[已建立事实] 每点frontend结构均为4个signed multiplier、4个18-bit accumulator adder和110 register bits。Mapped cell count与mapped library area完全不变；频率相关成本出现在physical optimization阶段。Core/die area固定为6711.18/7220.75 µm²。Placement utilization从400 MHz的52.20%提高到666.667 MHz的57.66%。

[结构解释] 400–500 MHz的final cell/area基本稳定；571.429 MHz增加12个timing-repair buffer并出现11个final clock buffer；666.667 MHz的timing-repair buffer增至456，final functional cells比400 MHz多304个，final area增加373.99 µm²。该跃升与更激进的resizing/buffer insertion一致，是工具用面积换取时序的直接结构证据。不能仅凭class count把每个新增cell唯一归因于setup或hold repair；CTS JSON在五点均报告0个专门setup/hold-fix buffer，CTS本身均创建9个clock buffer、110个sink和3层clock tree。

## 4. CTS与routing

| Target | CTS cells / area | Setup / hold skew | Placement estimated WL | Global-route WL / overflow | Detailed-route WL / vias | DRC |
|---:|---|---|---:|---|---|---|
| 400.000 MHz | 2068 / 3522.64 µm² | 0.053577 / 0.055555 ns | 17466.6 µm | 31367 µm / 0 | 18551 µm / 13035 | 0 / 0 |
| 444.444 MHz | 2067 / 3521.84 µm² | 0.054091 / 0.054445 ns | 17503.7 µm | 31441 µm / 0 | 18592 µm / 13052 | 0 / 0 |
| 500.000 MHz | 2068 / 3523.17 µm² | 0.051908 / 0.054703 ns | 17450.0 µm | 31230 µm / 0 | 18691 µm / 13134 | 0 / 0 |
| 571.429 MHz | 2080 / 3529.82 µm² | 0.053622 / 0.055000 ns | 17377.8 µm | 30802 µm / 0 | 18440 µm / 13031 | 0 / 0 |
| 666.667 MHz | 2370 / 3891.31 µm² | 0.055670 / 0.055941 ns | 17928.9 µm | 31136 µm / 0 | 18383 µm / 13861 | 0 / 0 |

[已建立事实] 表中DRC为“detailed-route DRC / KLayout DRC”，所有点均为0；antenna violating net/pin也均为0，GDS均已生成。666.667 MHz的via count和placement estimated wirelength高于其余点，与显著增加的physical optimization cells一致。

[不能得出的结论] Global-route wirelength来自routing tree估计，detailed-route wirelength来自最终routing shapes；二者统计阶段和定义不同，不直接相减或计算改善比例。跨频点可分别观察同一类指标，但小幅非单调变化也不能单独解释为物理质量改善。

## 5. Critical path迁移

| Target | Startpoint → endpoint | Data delay | Cell / net占比 |
|---:|---|---:|---|
| 400.000 MHz | `cycle_idx[0]/Q` → boundary PE(1,0) `psum_out[17]/D` | 1.69648 ns | 99.635% / 0.365% |
| 444.444 MHz | `cycle_idx[0]/Q` → boundary PE(1,0) `psum_out[17]/D` | 1.69160 ns | 99.622% / 0.378% |
| 500.000 MHz | `cycle_idx[0]/Q` → boundary PE(1,0) `psum_out[17]/D` | 1.69741 ns | 99.806% / 0.194% |
| 571.429 MHz | `cycle_idx[0]/Q` → boundary PE(1,0) `psum_out[17]/D` | 1.58314 ns | 99.526% / 0.474% |
| 666.667 MHz | `b_matrix[11]` → boundary PE(0,1) `psum_out[17]/D` | 1.23900 ns，arrival 1.48900 ns | 99.911% / 0.089% |

[已建立事实] 400–571.429 MHz的关键路径保持为`cycle_idx → Feeder/control → boundary PE accumulator`。666.667 MHz时最差路径迁移为`matrix B input → Feeder/control → boundary PE accumulator`；其arrival包含0.250 ns input delay，表中1.23900 ns data delay从primary-input arrival基准之后计算。

[结构解释] 所有点的路径都由cell delay主导。571.429 MHz仍保持原路径但delay下降；到666.667 MHz，工具显著增加timing-repair cells并把原控制路径压到不再最差，最差路径转移到受固定input delay约束的matrix input组合路径。这表明继续提高目标频率时，瓶颈已经从controller-driven feeder selection迁移到输入到PE的组合算术路径。

## 6. Warning与检查器审计

[已建立事实] 五个点均没有tool error或未分类warning。已分类warning包括：floorplan snap与早期wire-load estimate、无macro设计的空macro PDN grid、已审计的one-pin未用输出、无antenna diode、extractor弃用参数以及headless GUI环境提示。666.667 MHz额外出现`RSZ-0062`，表示早期repair阶段未能修复全部setup violation；后续placement/CTS/route继续优化后final setup WNS为+0.024937 ns，因此它被保留为收敛过程证据，而非静默忽略。

## 7. 结论边界

[已建立事实] 在固定RTL、固定Nangate45 typical平台、固定物理参数和固定active-operation约束下，五个受测点均完成物理实现并通过final setup、hold和DRC。实现成本在571.429 MHz开始小幅增长，在666.667 MHz出现明显cell/area跃升和关键路径迁移。

[不能得出的结论]

- 666.667 MHz只是最高已测试且通过的nominal target，不能称为硅上Fmax；
- 因为没有测试更短period，本实验没有确定首个失败点，也不能把下一失败频点称为设计物理极限；
- Nangate45是开源参考平台，结果不是商业工艺signoff；
- 没有activity-based power、multi-corner、OCV/AOCV/POCV或silicon correlation，不能得出可信功耗或完整PPA结论；
- Post-synthesis和post-route equivalence缺口仍然存在；
- 结果只适用于N2/K2 baseline，不能外推到其他N/K或registered Feeder变体。

机器可读结果位于被Git忽略的`build/openroad/clock_sweep/clock_sweep_summary.json`与`clock_sweep_summary.tsv`；每个配置目录还保存独立manifest、constraint hash、完整日志、stage JSON、final audit和单配置`clock_sweep_result.json`。

Registered Boundary 变体的独立结构、500/667 MHz物理结果与架构裁决见 [09_registered_boundary_ppa_analysis-zh_CN.md](09_registered_boundary_ppa_analysis-zh_CN.md)。
