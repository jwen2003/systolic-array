# V2 Lite-only Physical Adjustment Log

## Baseline observation

- The fresh 2.500 ns run completed through GDS generation and physical checks.
- Routed setup and hold timing met the target.
- Detailed routing converged to zero DRC violations.
- Final electrical checks reported two max-capacitance violations while max-slew and max-fanout checks passed.

## Evidence-based adjustment hypothesis

The remaining violations are small load-capacitance overruns on two routed nets. A modest capacitance repair margin should make `repair_design` select or insert enough drive strength before routing to absorb parasitic estimation error without changing RTL, timing exceptions, clock period, floorplan, or functional latency.

## Planned change

Set the ORFS `CAP_MARGIN` variable to 10 for one independent fresh run. The baseline run remains immutable. The adjusted run will start again from frontend normalization and synthesis and will be compared against the baseline for timing, area, repair buffers, electrical violations, congestion, and DRC.

## Outcome

The adjusted run cleared the two max-capacitance violations and retained positive setup and hold slack. It added 18 functional cells and 31.9 µm² relative to the physical baseline. Both detailed-route runs reached zero routing DRC.

The subsequent KLayout deck found two `METAL6_ANTENNA` items in both runs. OpenROAD's antenna checker found zero and the Nangate45 library exposes no antenna-diode cell. Because increasing antenna-repair iterations would not trigger when OpenROAD sees no violation, no additional speculative backend run was started.
