# Systolic Array MVP: 综合与 PPA 计划

## 1. 文档状态

- 状态：第一版，generic synthesis 停止在 SystemVerilog 前端环境准备阶段
- baseline：`rtl/` 下五个 RTL 文件保持冻结，未因综合工具兼容性而修改
- 当前边界：尚未产生任何可用于结构统计的 generic netlist 或 `stat` 报告
- 停止原因：当前环境既无可用的 `read_slang`，也无 `sv2v`

本文档记录可重复 generic synthesis flow 的工具前提、配置矩阵、结构检查和 PPA 边界。generic Yosys 统计只能作为结构统计或逻辑规模代理，不能解释为真实 ASIC 面积、频率、功耗或物理关键路径。

## 2. 已建立的环境事实

### 2.1 工具版本与前端探测

工作目录为仓库根目录。2026-08-30 在 WSL 中执行：

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

## 3. 前端选择与当前停止点

既定选择顺序为：

1. `read_slang`；
2. `sv2v` 生成到 `build/sv2v/`；
3. 两者均不可用时停止。

当前环境符合第 3 种情况。因此尚未执行 elaboration、`hierarchy -check`、generic synthesis、结构统计或网表输出，也不得声称三种配置已经综合成功。

最小环境准备方案二选一：

- 推荐：使用包含 Yosys Slang 插件的 OSS CAD Suite，并确认同一套工具中的 `yosys -p "help read_slang"` 成功；使用套件自带的一致版本可避免插件与 Yosys ABI 不匹配。
- 备选：安装 `sv2v` 并确认 `command -v sv2v` 返回可执行路径。转换输出只能写入 `build/sv2v/`，原始 `rtl/` 保持不变。

任何安装或 PATH 修改都需要单独授权。环境就绪后必须重新执行第 2.1 节的探测，再选择唯一前端，不能静默退回内置 `read_verilog -sv`。

## 4. 计划中的 generic synthesis 配置

环境就绪后至少覆盖：

| 配置 | `N` | `K` | `DATA_W` | `ACC_W` | 推导 `CYCLE_W` |
|---|---:|---:|---:|---:|---:|
| unit | 1 | 1 | 8 | 18 | 1 |
| base | 2 | 2 | 8 | 18 | 2 |
| scale | 4 | 4 | 8 | 18 | 4 |

每种配置的固定流程为：

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

每种配置需在 `build/synth/<config>/` 保存完整日志、独立 `stat` 报告、elaborated/generic Verilog netlist、JSON netlist、参数清单和工具版本。`build/` 已由 `.gitignore` 排除。

## 5. 结构合理性检查计划

综合成功后必须检查：

- PE 层次保留时实例数为 $N^2$；若流程展开层次，则用每 PE 状态与运算资源的缩放关系交叉检查；
- signed multiplier、adder 和寄存器结构随 $N^2$ 扩展，`K` 只影响 feeder 选择逻辑与 controller 周期范围，不应改变 PE 数；
- controller counter 位宽分别为 1、2、4 bit；
- `check` 不报告 latch、undriven、multiple driver 或 combinational loop；
- top 端口和内部逻辑没有被错误优化为空设计；
- 每个 PE 保留 8×8 signed multiplication，并以完整 16-bit product 符号扩展到 18-bit accumulator；
- `N=1` 仍保留一个 PE、A/B 输入到寄存输出的完整 pipe 和一个 accumulator。

必须记录所有 warning 并逐项判断，不能仅以 Yosys 退出码代替结构审查。

## 6. 前端转换后的验证要求

综合流程完成后仍需：

- 确认 `git diff -- rtl` 为空；
- 运行 `git diff --check`；
- 重新运行现有统一回归入口，确保五组定向 TB 和六种参数配置全部通过；
- 若采用 `sv2v`，明确现有回归验证的是原始 baseline；还需评估转换前后组合/时序等价检查或转换后网表仿真，不能仅因 Yosys 成功退出便判定转换语义正确。

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

