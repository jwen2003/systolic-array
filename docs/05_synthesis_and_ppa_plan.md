# Systolic Array MVP: 综合与PPA计划

## 1. 文档状态

- 状态：第二版，`read_slang` generic synthesis flow 已建立并通过三种配置
- baseline：`rtl/` 下五个 RTL 文件保持冻结，未因综合工具兼容性而修改
- 当前证据：`N/K=1/1`、`2/2`、`4/4` 均完成 generic synthesis、结构检查、网表与统计输出
- 当前边界：没有 Liberty、SDC 或物理实现，因此所有数字仅是 generic 结构统计或逻辑规模代理

本文档记录可重复 generic synthesis flow 的工具前提、配置矩阵、结构检查和 PPA 边界。generic Yosys 统计只能作为结构统计或逻辑规模代理，不能解释为真实 ASIC 面积、频率、功耗或物理关键路径。

## 2. 已建立的环境事实

### 2.1 工具版本与前端探测

系统 Yosys 0.52 的探测和失败复现保留如下，作为选择独立前端的原因。工作目录为仓库根目录。2026-08-30 在 WSL 中执行：

```text
yosys -V
```

结果：

```text
Yosys 0.52 (git sha1 fee39a3284c90249e1d9684cf6944ffbbcbb8f90)
```

执行：

```text
yosys -p "help read_slang"
```

结果为 `No such command or cell type: read_slang`。

执行：

```text
yosys -m slang -p "help read_slang"
```

结果为：

```text
ERROR: Can't load module `./slang': /usr/lib/yosys/plugins/slang.so:
cannot open shared object file: No such file or directory
```

执行：

```text
command -v sv2v
```

无输出，说明当前 PATH 中没有 `sv2v`。

### 2.2 内置前端失败复现

准确复现命令为：

```text
yosys -p "read_verilog -sv rtl/systolic_pe.sv rtl/systolic_array.sv rtl/input_feeder.sv rtl/systolic_controller.sv rtl/systolic_array_top.sv; hierarchy -top systolic_array_top"
```

`systolic_pe.sv` 读取成功，随后停止于：

```text
rtl/systolic_array.sv:12: ERROR: syntax error, unexpected '[', expecting ',' or '=' or ')'
```

第 12 行是 unpacked-array 端口 `a_left [N-1:0]`。这是当前 Yosys 内置 `read_verilog -sv` 的前端能力限制，不是修改 baseline 接口或手工扁平化 baseline 的理由。

## 3. 已采用的前端与安装方式

既定选择顺序为：

1. `read_slang`；
2. `sv2v` 生成到 `build/sv2v/`；
3. 两者均不可用时停止。

初次探测符合第 3 种情况。获得安装授权后，下载官方 `2026-08-30` Linux x64 OSS CAD Suite，下载文件为：

```text
oss-cad-suite-linux-x64-20260830.tgz
SHA-256: 54ffdd32d9126ee0473a204a6b4ab98d9938c9f47013a42fe73d0822eae21dc7
```

安装到独立的 local user installation，由环境变量记录其根目录：

```text
$OSS_CAD_SUITE_ROOT
```

实际使用的可执行文件和版本为：

```text
$OSS_CAD_SUITE_ROOT/bin/yosys
Yosys 0.68+136 (git sha1 c30457480-dirty, Release, Clang /usr/bin/clang++ 21.1.8)
```

未替换 `/usr/bin/yosys`，未使用 `sudo`，未修改 `.bashrc`。`scripts/oss_cad_suite_env.sh` 只对 source 它的当前 shell 设置 `PATH`，综合入口自身仍使用显式 Yosys 路径。

该 Yosys 的 `help read_slang` 正常。五个原始 RTL 文件由以下前端形式读取：

```text
read_slang --top systolic_array_top \
  -G N=<N> -G K=<K> -G DATA_W=8 -G ACC_W=18 \
  rtl/systolic_pe.sv rtl/systolic_array.sv rtl/input_feeder.sv \
  rtl/systolic_controller.sv rtl/systolic_array_top.sv
```

最小前端验证结果为 0 error、0 warning，`hierarchy -check` 与 `check` 为 0 problems。没有使用 `sv2v`，也没有回退到内置 `read_verilog -sv`。

## 4. Generic synthesis 配置与结果

当前覆盖：

| 配置 | `N` | `K` | `DATA_W` | `ACC_W` | 推导 `CYCLE_W` |
|---|---:|---:|---:|---:|---:|
| unit | 1 | 1 | 8 | 18 | 1 |
| base | 2 | 2 | 8 | 18 | 2 |
| scale | 4 | 4 | 8 | 18 | 4 |

每种配置已执行的固定流程为：

```text
frontend read/elaboration
hierarchy -check
proc
opt
check
memory
opt
techmap
opt
stat
```

每种配置均在 `build/synth/<config>/` 保存完整日志、独立 `stat` 报告、`post_proc.v`、generic Verilog netlist、pre-tech 与 final JSON、参数清单和工具版本。`post_proc.v` 明确表示其生成点位于 `proc` 和第一次 `opt` 之后，不将其误称为纯 elaborated netlist。`build/` 已由 `.gitignore` 排除。

### 4.1 可追溯与 fresh-build 机制

每次运行都先在 `build/synth/.run.XXXXXX/` 临时目录中完成三种配置和结构检查。只有全部成功后，才用同一文件系统内的目录移动替换正式的 `n1_k1`、`n2_k2`、`n4_k4`。旧正式目录在发布期间先移动到临时目录作为回滚备份；综合、检查或发布失败均返回非零，失败临时结果不会被标记成正式成功结果。

脚本将 build root解析并核对为仓库内明确的 `build/synth`，只允许三个固定配置名。递归清理只针对经过前缀验证的本次 `.run.XXXXXX` 临时目录，不会作用于源码、Git文件或 `build/synth` 以外路径。

每个正式配置的 `config.txt` 记录：

- UTC运行时间；
- Git commit hash及完整 `git status --porcelain`；
- Yosys绝对路径、版本与 OSS CAD Suite根目录；
- `N`、`K`、`DATA_W`、`ACC_W`；
- 实际综合 Tcl脚本绝对路径及正式输出目录。

工作树不干净不会阻止综合，但状态会原样保存在产物中。

### 4.2 Pre-tech word-level 结构统计

| 配置 | PE result marker | signed multiplier | accumulator adder | controller/index adder | register cell | register bit | cell 总数 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `n1_k1` | 1 | 1 | 1 | 1 | 4 | 21 | 30 |
| `n2_k2` | 4 | 4 | 4 | 1 | 13 | 110 | 75 |
| `n4_k4` | 16 | 16 | 16 | 1 | 55 | 498 | 231 |

PE result marker是 pre-tech JSON中保留的层次化 `u_pe.psum_out` netname数量，不是 flatten 后的独立 PE module cell数量。该标记数量不能单独证明完整 PE instance仍存在；本流程将其与 $N^2$ 个 multiplier、$N^2$ 个 accumulator adder以及 pre-tech/final cell set非空共同作为 PE结构没有消失的证据。

Accumulator adder通过连接关系可靠分类：其 A端必须精确连接对应 `u_pe.psum_out` 的 `ACC_W` 位向量，且 A/B/Y宽度均为 `ACC_W`。三种配置均精确得到 $N^2$ 个 accumulator adder。其余 `$add` 单独记录为 controller/index adder。

当前固定 OSS CAD Suite/Yosys版本下，total `$add` 恰好为 $N^2+1$，脚本将其保留为严格结构回归基线；额外 controller/index adder可能随工具优化策略变化，因此该总数不是跨工具版本的架构不变量。

Slang 将两个原始 `DATA_W=8` signed operand在 `$mul` 输入处显式符号扩展为 `2*DATA_W=16` bit，输出保持完整16 bit。检查器从每项配置读取 `DATA_W` 和 `ACC_W`，使用 product width $2\times DATA\_W$ 和 sign index $DATA\_W-1$ 验证 A/B/Y宽度、signed参数及全部扩展高位，不硬编码乘法器宽度关系。

寄存器统计是优化后的 observable generic 结构。最右侧 A 和最下侧 B 的 terminal forwarding 输出未暴露到 top，可能被 `opt` 删除，因此不能用寄存器 bit 数直接反推未优化 PE 状态总和。

### 4.3 Techmap 后 generic primitive 统计

| 配置 | AND | MUX | NOT | OR | SDFFE | SDFF | XOR | cell 总数 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `n1_k1` | 342 | 88 | 2 | 116 | 19 | 2 | 264 | 833 |
| `n2_k2` | 1373 | 310 | 12 | 474 | 74 | 36 | 1058 | 3337 |
| `n4_k4` | 5485 | 1162 | 36 | 1887 | 292 | 206 | 4234 | 13302 |

这些数量由 `generic_netlist.json` 的 cell type自动统计，写入每个配置的 `structure_summary.json`，并汇总到 `build/synth/structure_summary.json`；表中数字没有硬编码。它们重现了加固前的统计结果。Primitive数量是 Yosys generic `techmap` 的逻辑规模代理，不是标准单元数量或面积。

## 5. 结构合理性检查结果

已完成的结构检查：

- Slang展平后，PE result marker为1、4、16；该 netname计数不单独称为 PE instance证明；
- multiplier和按连接分类的 accumulator adder均精确为 $N^2$，并与 marker和non-empty检查交叉验证；
- register结构随 $N^2$ 扩展，`K` 只影响 feeder选择逻辑与 controller周期范围，不应改变 PE marker数量；
- controller counter 位宽分别为 1、2、4 bit；
- 四个阶段的 `check` 对每种配置均报告 0 problems，没有 latch、undriven、multiple driver 或 combinational loop 报告；
- top 端口和内部逻辑没有被错误优化为空设计；
- 每个 PE 保留 8×8 signed multiplication，并以完整 16-bit product 符号扩展到 18-bit accumulator；
- `N=1` 保留一个 PE、一个 accumulator，A/B pipe netname 宽度分别为 16 data bit与 2 valid bit，对应输入/输出两个边界位置；不可观察的 terminal forwarding register允许被优化。

Slang 三种配置均报告 0 error、0 warning。完整日志没有 Yosys warning/error diagnostic；`PROC_DLATCH` 只是 pass 名称，没有生成 latch。

严格失败语义由 `set -euo pipefail`、Yosys退出码、Python checker退出码和 pipefail下的 `tee`共同保证。检查器还要求四次 `check` 全部为0 problems、Slang为0 error/0 warning、日志无 warning/error diagnostic，并要求 pre-tech和techmap cell set均非空。

## 6. 前端转换后的验证要求

综合流程完成后仍需并已执行：

- 确认 `git diff -- rtl` 为空；
- 运行 `git diff --check`；
- 重新运行现有统一回归入口，确保五组定向 TB 和六种参数配置全部通过；
- 本流程未采用 `sv2v`，`read_slang` 直接读取原始 baseline；现有回归仍是主要动态功能证据，Yosys 成功退出本身不代替验证。

## 7. 尚未建立的 PPA 事实

当前没有目标工艺 Liberty、SDC、OpenROAD 或其他物理设计流程，因此尚未建立：

- 工艺映射后的标准单元面积；
- 可实现的 Fmax 或 setup/hold 裕量；
- 动态功耗、漏电功耗或功耗密度；
- wire delay、buffering、fanout 修复及布线后关键路径；
- floorplan、拥塞、时钟树或寄生参数影响。

即使后续得到 generic `stat`，也只能称为结构统计或逻辑规模代理。

## 8. 下一阶段所需输入

进入可信 PPA 分析前至少需要：

- 明确的目标工艺与 PVT corner；
- 对应 Liberty 文件及允许使用的标准单元集合；
- 时钟周期、uncertainty、input/output delay 等 SDC 约束；
- wire/load 模型，或明确的 floorplan、placement、CTS、routing 流程；
- 面积、频率、功耗的优化目标和比较配置；
- 若做功耗估计，需有代表性 activity 数据或明确的静态假设。
