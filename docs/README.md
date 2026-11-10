# Documentation Index and Reading Order

[English](README.md) | [简体中文](README-zh_CN.md)

Start with the [repository current-status summary](../README.md). For V2 read 11→12→13→14→16→17, then the consolidated measured results in 19 and verification scope in 15. Review Core with 01→02→03; V1 physical evidence with 05→06→07→08→09. Document 10 retains the upstream V1 abstraction, not a claim of all Runtime features.

| Directory | Responsibility |
|---|---|
| core/ | Frozen V1 math/timing/microarchitecture and upstream software abstraction |
| wrapper/ | V2 system, address and bus contracts |
| software/ | Host Runtime/BFM, invocation and reproduction |
| verification/ | Core/Wrapper validation and evidence boundaries |
| performance/ | Hypotheses, models, RTL measurements and co-design |
| implementation/ | Generic synthesis, STA, physical implementation and limits |

Languages remain paired as -EN.md / -zh_CN.md within each topic, not separate language trees. Retain numbers 01–10 and add 11–19.

| Number | Document |
|---|---|
| 01 | [Design intent](core/01_design_intent-EN.md) |
| 02 | [Dataflow](core/02_dataflow-EN.md) |
| 03 | [Microarchitecture](core/03_microarchitecture-EN.md) |
| 04 | [V1 verification](verification/04_verification_plan-EN.md) |
| 05 | [Synthesis/PPA flow](implementation/05_synthesis_and_ppa_plan-EN.md) |
| 06 | [Synthesis scaling](implementation/06_synthesis_scaling_analysis-EN.md) |
| 07 | [Physical implementation](implementation/07_physical_implementation_plan-EN.md) |
| 08 | [Clock sweep](implementation/08_clock_sweep_analysis-EN.md) |
| 09 | [Registered Boundary tradeoff](implementation/09_registered_boundary_ppa_analysis-EN.md) |
| 10 | [V1 software abstraction](core/10_minimal_software_contract-EN.md) |
| 11 | [V2 system architecture](wrapper/11_system_architecture-EN.md) |
| 12 | [Register/error contract](wrapper/12_register_contract-EN.md) |
| 13 | [AXI subset/arbitration](wrapper/13_axi_protocol-EN.md) |
| 14 | [Runtime/BFM](software/14_runtime_bfm-EN.md) |
| 15 | [V2 verification](verification/15_wrapper_verification-EN.md) |
| 16 | [Burst model/measurement](performance/16_burst_analysis-EN.md) |
| 17 | [Packing experiment](performance/17_packed_analysis-EN.md) |
| 18 | [Co-design roadmap](performance/18_codesign_roadmap-EN.md) |
| 19 | [V2 Burst, packed, and physical results](performance/19_v2_axi_burst_packed_results-EN.md) |
