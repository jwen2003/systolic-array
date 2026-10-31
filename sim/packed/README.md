# Packed Burst experiment

## 当前双语文档 / Maintained bilingual documentation

[中文](../../docs/performance/17_packed_analysis-zh_CN.md) | [English](../../docs/performance/17_packed_analysis-EN.md)

下文保留本目录原始实验说明；当前状态、计时边界与限制以双语报告为准。The notes below retain their original experiment scope; use the report above for current status and boundaries.

See ../../docs/wrapper/packed_experiment.md for the contract, model and measurement
boundaries. Start with `bash scripts/run_packed_comparison.sh` from the repository.
This is an experiment driver using the shared Lite/Burst BFM, not a Linux driver
or an upgrade to the original Matmul Runtime. `PACKED_ENABLE=0` retains legacy
behavior; the new runner elaborates it as 1. Readback uses existing input windows.
