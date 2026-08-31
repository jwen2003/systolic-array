# Systolic Array MVP: 物理实现与PPA分析

## 1. 范围与正式基线

[已建立事实] 本轮仅实现 $N=2$、$K=2$、`DATA_W=8`、`ACC_W=18`。正式物理基线固定为：

- ORFS commit：`6101364b2d7909dd797e1e3e7f80695401cfa4e4`；
- ORFS描述：`26Q3-345-g6101364b2`；
- 官方镜像tag：`26Q3-345-g6101364b2`；
- immutable image：`openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`；
- OpenROAD：`26Q3-1305-gf552262465`；
- 容器Yosys：`0.68+post`；OpenSTA：`3.1.0`；
- read_slang与独立formal使用的Yosys：`0.68+136`。

[已建立事实] 所有正式PPA数字来自上述固定镜像的一次完整fresh flow，没有复用或拼接旧镜像的netlist、ODB、placement、CTS、route或timing结果。

## 2. Kepler Formal兼容性与`LEC_CHECK`

[工具兼容性限制] 原问题不是OpenROAD CTS算法失败。Clock-tree construction、CTS后detailed placement和`repair_timing`均完成，随后ORFS执行`kepler-formal --config 4_rsz_lec_test.yml`时收到`SIGILL`。`kepler-formal --help`也以132退出。

[已建立事实] 官方Nangate45/GCD、16线程Systolic和单线程Systolic均复现。以下三枚固定官方镜像均复现Kepler启动SIGILL：

- `sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380`；
- `sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`；
- `sha256:2e22028b36fd7a1cc6952f0f864527b88e42577acb1068fa0e34d373e61dec47`。

[已建立事实] `LEC_CHECK`是ORFS `variables.yaml`中正式定义、仅属于CTS阶段的配置变量。`LEC_CHECK=0`只令`lec_check_enabled`不写出Kepler比较用netlist、不调用`run_lec_test`；它不改变或跳过`clock_tree_synthesis`、detailed placement、`repair_timing`、global/detailed routing、RC extraction、STA、GDS或DRC，也不改变SDC、综合目标或Nangate45平台。

[已建立事实] 项目design config显式设置`export LEC_CHECK = 0`。正式flow日志不存在Kepler调用，物理阶段全部执行。原失败证据、官方GCD复现、单线程复现与`compatibility_summary.json`均保留并标记为Kepler Formal CPU compatibility diagnosis。

## 3. 等价性证据分层

- [已建立事实] baseline RTL到read_slang derived frontend Verilog：`equiv_simple`加10步`equiv_induct`证明通过，共843个`$equiv` cell全部proven。
- [验证缺口] derived frontend到1902-cell mapped netlist：使用官方Nangate45 functional cell models展开后尝试Yosys sequential equivalence。求解在`equiv_simple -seq 10`长时间无进展，未发现反例但人工受控终止，状态为`inconclusive_tool_scalability`，不得称为通过或失败。
- [工具兼容性限制] Kepler阶段性LEC：`disabled_due_to_cpu_sigill`。
- [验证缺口] post-route netlist没有独立formal证明。Clock buffer、physical-only filler/tap/decap和物理网表模型使本轮没有建立可靠post-route formal setup。

[已建立事实] RTL Verilator regression不能替代mapped或post-route equivalence，只证明原始baseline及其冻结验证语义。

## 4. 约束口径

[已建立事实] 本项目复用Butterfly的400 MHz评测口径，不称为Butterfly默认配置：

- clock period：2.500 ns；
- clock uncertainty：0.050 ns；
- clock transition：0.050 ns；
- input/output delay：0.250 ns；
- input transition：0.050 ns；
- output load：0.010；
- core utilization：50%；
- core aspect ratio：1；
- placement density lower-bound addon：0.10。

[已建立事实] Matrix输入、`cycle_idx → feeder → boundary PE`及psum读取路径没有false path或multicycle path。唯一false path仍是同步低有效复位`rst_n`。最终`check_setup`报告0个unconstrained endpoints；唯一缺input delay的端口是被明确false-path处理的`rst_n`。

## 5. Mapping与面积

| 指标 | 结果 |
|---|---:|
| Mapped standard cells | 1902 |
| Mapped cell area | 3442.572 µm² |
| Sequential cells | 110 |
| Sequential area | 497.420 µm² |
| Mapped combinational area | 2945.152 µm² |
| FA_X1 / HA_X1 | 228 / 182 |
| BUF_X1 / BUF_X2 / CLKBUF_X1 | 111 / 1 / 6 |
| INV_X1 | 102 |
| Final functional/physical standard cells | 2068 |
| Final standard-cell area | 3522.64 µm² |
| All final instances including fill/tap | 4406 |

[基于结果的解释] 四个PE的乘法和累加器被映射为FA、HA及布尔单元，没有专用multiplier macro。最终分类包括152个timing-repair buffer、9个clock buffer、7个clock inverter、102个普通inverter、116个tap cell和2338个fill cell。

## 6. Floorplan与placement

| 指标 | 结果 |
|---|---:|
| Die area | 7220.75 µm² |
| Core area | 6711.18 µm² |
| Floorplan utilization | 51.30% |
| Detailed-placement utilization | 52.20% |
| Detailed-placement instances | 2052 |
| Detailed-placement design area | 3502.95 µm² |
| Estimated wirelength | 17466.6 µm |
| Placement violations | 0 |

[基于结果的解释] 设计没有macro，controller、feeder与四个PE的标准单元在同一小型core内混合布局。最终关键路径从controller进入边界PE，说明控制/feeder与PE算术结构在物理上保持直接耦合，而非独立宏块。

## 7. CTS

| 指标 | 结果 |
|---|---:|
| Original sinks | 110 |
| Clock tree levels | 3 |
| Clock buffers | 9个`CLKBUF_X3` |
| Dummy loads | 7 |
| Buffer path depth | 2 |
| Rise network latency | 0.091352–0.095769 ns |
| Fall network latency | 0.093781–0.098114 ns |
| Final setup skew | 0.053165 ns |
| Final hold skew | 0.054306 ns |

[已建立事实] CTS、CTS后placement和timing repair完整执行，均无placement、setup或hold violation。

## 8. STA

| 阶段 | Setup WNS | Setup TNS | Hold WNS | Hold TNS |
|---|---:|---:|---:|---:|
| Post-synthesis独立STA | 未单独建立 | 未单独建立 | 未单独建立 | 未单独建立 |
| Floorplan | 0.859363 ns | 0 | 0.060854 ns | 0 |
| Detailed placement | 0.713213 ns | 0 | 0.063979 ns | 0 |
| Post-CTS | 0.714560 ns | 0 | 0.064591 ns | 0 |
| Post-global-route | 0.675832 ns | 0 | 0.067274 ns | 0 |
| Post-route/extracted final | 0.720010 ns | 0 | 0.065023 ns | 0 |

[验证缺口] ORFS本次没有在未floorplan的`1_synth.odb`上生成独立post-synthesis STA报告，因此不得把floorplan结果重命名为post-synthesis结果。

[已建立事实] Final max transition、capacitance、fanout、setup及hold violation count均为0。

## 9. Post-route关键路径

[已建立事实] 最差setup路径仍为：

```text
u_controller.cycle_idx[0]/Q
→ feeder/control selection
→ boundary PE multiplier/accumulator logic
→ u_array.gen_row[1].gen_col[0].u_pe.psum_out[17]/D
```

- Final data-path delay：1.69648 ns，不含source clock network latency；
- Cell delay：1.69028 ns，占99.63%；
- Extracted net delay：0.00620 ns，占0.37%；
- Final reported slack：0.72001 ns。

[基于结果的解释] 对该很小的Nangate45 core，关键路径仍由组合算术cell delay主导，布线延迟占比较小。路径保持为`cycle_idx → feeder/control → boundary PE accumulator`，没有转变为纯clock或长互连路径。

## 10. Routing、extraction和DRC

| 指标 | 结果 |
|---|---:|
| Global-route wirelength | 31367 µm |
| Global-route total resource usage | 17.91% |
| Maximum reported layer usage | Metal2，49.55% |
| Global-route overflow | 0 |
| Detailed routed wirelength | 18551 µm |
| Detailed-route vias | 13035 |
| Detailed-route DRC errors | 0 |
| Extracted nets / RC segments | 2532 / 6994 |
| KLayout DRC count | 0 |
| Final GDS | 已生成`6_final.gds` |

[已建立事实] Global routing、detailed routing、fill、RC extraction、final STA、GDS merge和KLayout DRC均实际运行。最终SPEF非空，未复用旧run。

## 11. Warning审查

- Floorplan：`IFP-0028`为core坐标snap；`EST-0027`为floorplan阶段尚无寄生参数而使用wire-load model。
- Global route：92个`RSZ-0104`为单pin dangling net提示，主要对应映射cell未使用输出；最终设计非空、STA/DRV/route/DRC均通过。另有`GRT-0246`提示库中没有antenna diode。
- Detailed route：同一`GRT-0246`；最终antenna violating nets/pins均为0。
- Finish：`RCX-0514`为旧extractor参数弃用提示；`GUI-0076`为无`XDG_RUNTIME_DIR`的headless GUI提示。

[已建立事实] 各阶段error count均为0，最终DRC、setup、hold、slew、capacitance和fanout violation均为0。

## 12. `acc_clear`与协议审查

[已建立事实] RTL regression继续检查matrix input稳定、controller/feeder/reset协议、每PE恰好$K$次MAC以及逐拍A/B/k pairing。Physical flow没有增加false path或multicycle path。

[基于结果的解释] Final flow增加了timing-repair buffers，且max fanout violation为0；因此高扇出网络已达到本次library/constraint下的工具检查要求。但mapped netlist已匿名化部分组合net，不能仅凭名称把全部repair buffer归因于`acc_clear`，本轮不宣称其具体buffer树结构已被独立证明。

## 13. 适用边界

[已建立事实] 结果属于Nangate45/FreePDK45教育平台和typical library corner的可重复基准，不是商业工艺signoff。

[验证缺口] 没有多corner/multi-mode分析、foundry-qualified extraction、OCV/AOCV/POCV、真实switching activity或silicon correlation。OpenROAD报告的约0.823 mW是该开源流程假设下的估计值，不应作为可信产品功耗。

[待验证假设] 后续若扩大$N$或$K$，关键路径、拥塞、`acc_clear`扇出和布线延迟占比可能显著变化；在完成受控scaling sweep前不得外推本次N2/K2结果。
