# V2 Burst Top Nangate45 物理实现结果

## 结论

在固定的 Nangate45 typical（1.10 V、25 °C）单 corner、2.500 ns、既定 active-operation 约束和本次检查范围内，`systolic_axi_burst_top` 完成 fresh RTL-to-GDS，并满足 routed setup/hold、电气、拥塞、detailed-route DRC、OpenROAD antenna 与 KLayout DRC 检查。Baseline run 已直接通过，因此没有运行 `CAP_MARGIN=10` 或天线放置 hook。

这不是商业工艺 signoff，不代表 silicon Fmax、multi-corner closure、LVS 或 post-route formal equivalence。ORFS Kepler LEC 仍因既有 CPU SIGILL 兼容性限制通过 `LEC_CHECK=0` 关闭；本轮只证明 source-to-derived equivalence。

## 固定输入与工具

- Git HEAD：`b5077a7537c0929f4b0b97793ff1cfee4671c3cd`；工作树在运行时非 clean，完整状态保存在各 run 的 `manifest.txt`。
- Top/参数：`systolic_axi_burst_top`，`N=2`、`K=17`、`DATA_W=8`、`ACC_W=18`、`PACKED_ENABLE=0`。
- 所有运行时 Burst 长度共享同一硬件；`AxLEN` 未被固化为 elaboration 参数。
- ORFS commit：`6101364b2d7909dd797e1e3e7f80695401cfa4e4`。
- Image：`openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`（amd64）。
- 容器工具：Yosys 0.68+post、OpenROAD `26Q3-1305-gf552262465`、OpenSTA 3.1.0、KLayout 0.30.7。
- read_slang 前端：OSS CAD Suite Yosys 0.68+136；0 error、0 warning。
- Source-to-derived equivalence：Burst 4401/4401 proven；公平对照 Lite 4023/4023 proven。
- 约束：2.500 ns、uncertainty 0.050 ns、I/O max/min delay 0.250/0.000 ns、input transition 0.050 ns、output load 0.010 pF。
- Floorplan：50% target utilization、aspect ratio 1、placement density lower-bound addon 0.10；由各自映射面积推导，不复制固定坐标。
- `rst_n` 是同步低有效 reset；active-operation STA 对其设置 false path，因此 `check_setup` 报告它没有 input delay。这是已声明的 reset 接口验证边界，不是未约束的功能数据路径。
- 输入 SHA-256 见 `input_snapshot_sha256.txt`，完整运行时快照见 build 内 `manifest.txt` 与 `input_sha256.txt`。

## Burst 逐阶段结果

| Stage | Setup WNS/TNS (ns) | Hold WNS/TNS (ns) | Area (µm²) | 结果 |
|---|---:|---:|---:|---|
| Synthesis | unavailable | unavailable | 11,545.730 | 完成 |
| Floorplan | +0.115013 / 0 | -0.0389183 / -0.288240 | 11,546.8 | pre-CTS hold 尚未修复 |
| Global placement | +0.176815 / 0 | -0.0136090 / -0.0228617 | 11,505.0 | 完成 |
| Detailed placement | +0.171497 / 0 | -0.0128871 / -0.0225758 | 11,523.7 | 完成 |
| CTS | +0.172796 / 0 | +0.000711015 / 0 | 12,228.6 | hold 已修复 |
| Global route | +0.125637 / 0 | +0.00110725 / 0 | 12,232.0 | overflow 0；repair 前发现 3 个 max-cap，最终修复 |
| Routed/extracted final | +0.172356 / 0 | +0.0123354 / 0 | 12,232.0 | setup/hold、电气均通过 |

Final ORFS `stdcell` 指标为 6,492 cells / 12,232.0 µm²，其中包含 271 个 tap cells、排除 filler。排除 tap/filler 后，逻辑、时钟和修复标准单元为 6,221 cells / 12,159.914 µm²。Final core/die area 为 22,953.7 / 23,703.7 µm²，utilization 为 53.290%。

Final cell classes：849 sequential、818 timing-repair buffers、195 clock buffers、44 clock inverters、160 ordinary inverters。Global-route estimated routing-tree wirelength 为 129,692 µm，overflow 为 0。Detailed-route actual routing-shape wirelength 为 86,405 µm，via 数为 44,136。两种 wirelength 来自不同阶段和统计定义，不计算改善比例。

Final detailed-route DRC report为空（0 violations）；OpenROAD antenna 为 0 net / 0 pin violations；KLayout XML 中真实 `<item>` 数为 0。GDS、ODB、SPEF、DEF 和 final netlist 均已生成。

## Burst 最差路径

- Startpoint：`u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_/QN`
- Endpoint：`u_core.u_array.gen_row[0].gen_col[1].u_pe.psum_out[17]$_SDFFE_PN0P_/D`
- Data arrival / required / slack：2.419 / 2.591 / +0.1724 ns（JSON 高精度 slack 为 +0.172356 ns）。
- Launch/capture clock latency：0.1740 / 0.1748 ns；capture-minus-launch skew 约 +0.0008 ns。
- Library setup margin：0.03372 ns；clock uncertainty：0.050 ns。
- Clock-to-Q：0.0876 ns；其后组合 cell arcs：2.1128 ns；估算 extracted net increments：0.0446 ns；合计 data path（launch clock pin 至 endpoint D）2.2450 ns。
- 组合路径含 35 个同实例 input-to-output timing arcs；该数字不是报告行数或引脚数。

因此全局瓶颈仍是 Core 的 `cycle_idx → feeder/PE → accumulator` 路径，不是 Device 矩阵读写。Burst 最差 input-to-register 路径为 `s_burst_awlen[0] → u_burst.burst_error`，slack +0.913314 ns。Lite AXI 写地址寄存器到 Device 矩阵状态的审计路径在 Burst Top 中仍有 +1.528917 ns slack。当前 audit 未单独建立 Burst `current_addr` 到矩阵状态的专用 path group；全局 top-N reg-to-reg 报告仍覆盖这些路径，因此“Device 非全局瓶颈”成立，但不把专用分组缺失描述为形式证明。

## 同口径 Lite/Burst 对照

旧 Lite clean physical baseline 使用了不同的 derived frontend（mapped area 10,928.078 µm²），只作为历史参考。为公平比较，本轮使用统一 frontend、同一 ORFS/image/corner/约束/floorplan原则和完整检查，fresh 重跑 Lite，mapped area 为 10,655.960 µm²。

| Metric | Lite | Burst | Burst 代价 |
|---|---:|---:|---:|
| Mapped cells / area | 5,020 / 10,655.960 µm² | 5,553 / 11,545.730 µm² | +533 / +8.350% area |
| Final functional cells / area（排除 tap/fill） | 5,398 / 11,041.972 µm² | 6,221 / 12,159.914 µm² | +823 / +10.124% area |
| Timing-repair buffers | 485 | 818 | +333（+68.660%） |
| Clock buffers | 186 | 195 | +9 |
| Setup WNS/TNS | +0.161062 / 0 ns | +0.172356 / 0 ns | 两者均通过 |
| Hold WNS/TNS | +0.0128362 / 0 ns | +0.0123354 / 0 ns | 两者均通过 |
| Core / die area | 21,014.3 / 21,899.6 µm² | 22,953.7 / 23,703.7 µm² | +9.229% core / +8.238% die |
| Global overflow | 0 | 0 | 无新增 overflow |
| Detailed-route / OpenROAD antenna / KLayout DRC | 0 / 0 / 0 | 0 / 0 / 0 | 两者 clean |
| Detailed wirelength / vias | 77,806 µm / 38,671 | 86,405 µm / 44,136 | +11.052% / +14.132% |

Burst 支持的主要物理成本来自新增接口状态与控制组合逻辑，以及更显著的 timing-repair buffer 增长；它没有使 Device 读写路径取代 Core 成为最终关键路径。本对照不包含运行时多 beat 的吞吐收益，相关周期结果仍在 `reports/v2_lite_vs_burst/`。

## Warning 与证明边界

- ORFS final metrics：0 errors，2 类 final warnings：`RCX-0514`（旧 extraction option deprecated）和 `GUI-0076`（headless `XDG_RUNTIME_DIR` fallback）。
- 路由日志还有 one-pin net warnings，主要包括未使用的 32-bit slot高位、WSTRB高位、AXI PROT 输入及优化后内部临时 net。它们没有造成 flow error、未约束功能 endpoint、DRC 或 connectivity failure；本轮没有完成逐 net LVS 级分类。
- Nangate45 平台没有被 OpenROAD 识别的 `CORE ANTENNACELL`；本次无需 diode，因为 OpenROAD 与 KLayout antenna/DRC 均为 0。
- 没有 activity-based power 结论；ORFS 报出的默认 power 不作为可信 PPA 结论。
- Source-to-derived formal proven 不等于 mapped、post-route equivalence。Kepler LEC 关闭，post-route equivalence 未证明，LVS 未执行。

## 复现

```bash
cd /path/to/systolic-array
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
export OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830
OPENROAD_THREADS=16 bash scripts/run_v2_burst_physical.sh
OPENROAD_THREADS=16 bash scripts/run_v2_lite_comparable_physical.sh
```

正式 ignored 结果：

- `build/openroad/v2_burst_physical/baseline_2p5ns/`
- `build/openroad/v2_lite_comparable_physical/baseline_2p5ns/`

第一次 Burst 尝试因 Docker daemon 在 KLayout DRC 中断而保留在 `build/openroad/v2_burst_physical/.run.3meMiT/`；它未被用于任何最终数字。
