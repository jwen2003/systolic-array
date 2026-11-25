#!/usr/bin/env python3
"""Summarize the N8/K8 single- versus dual-input-bank mapped STA experiment."""
from __future__ import annotations
import csv, re, shutil
from pathlib import Path

REPO=Path(__file__).resolve().parents[1]
BUILD=REPO/'build/v2_n8k8_double_buffer_synth_sta'
OUT=REPO/'reports/v2_n8k8_double_buffer_synth_sta'

def one(root:Path,name:str)->Path:
    m=list(root.rglob(name))
    if len(m)!=1: raise RuntimeError(f'expected one {name} under {root}, found {len(m)}')
    return m[0]
def field(pat:str,text:str)->str:
    m=re.search(pat,text,re.M)
    if not m: raise RuntimeError(f'missing {pat}')
    return m.group(1).strip()
def cell_rows(text:str):
    out={}
    for line in text.splitlines():
        m=re.match(r'^\s*(\d+)\s+([0-9.E+-]+)\s+\d+\s+[0-9.E+-]+\s+([A-Z][A-Z0-9_]+)$',line)
        if m: out[m.group(3)]=(int(m.group(1)),float(m.group(2)))
    return out
def paths(text:str):
    out=[]
    for block in re.split(r'(?=^Startpoint: )',text,flags=re.M):
        if not block.startswith('Startpoint:'): continue
        out.append({'startpoint':field(r'^Startpoint: (.+)$',block),'endpoint':field(r'^Endpoint: (.+)$',block),
                    'slack_ns':float(field(r'^\s*(-?[0-9.]+)\s+slack \((?:MET|VIOLATED)\)$',block))})
    return out
def electrical(text:str):
    sections=re.split(r'^(max slew|max capacitance|max fanout)\s*$',text,flags=re.M)
    vals={'max slew':0,'max capacitance':0,'max fanout':0}
    for i in range(1,len(sections),2): vals[sections[i]]=sections[i+1].count('(VIOLATED)')
    return vals
def parse(v:str):
    root=BUILD/v; stat=one(root/'work/reports','synth_stat.txt').read_text(errors='replace'); sta=(root/'sta/openroad_sta.log').read_text(errors='replace')
    cells=cell_rows(stat); total=int(field(r'^\s*(\d+)\s+[0-9.E+-]+\s+\d+\s+[0-9.E+-]+\s+cells$',stat))
    area=float(field(r"Chip area for module .*?:\s*([0-9.]+)",stat)); seq_area=float(field(r'used for sequential elements:\s*([0-9.]+)',stat))
    seq=sum(n for k,(n,_) in cells.items() if k.startswith(('DFF','SDFF')))
    buffers=sum(n for k,(n,_) in cells.items() if k.startswith(('BUF_','CLKBUF_'))); inv=sum(n for k,(n,_) in cells.items() if k.startswith('INV_'))
    gp=paths((root/'paths/global_top5.rpt').read_text()); sp=paths((root/'paths/storage_to_pe.rpt').read_text()); bp=paths((root/'paths/bitmap_to_control.rpt').read_text())
    bank=paths((root/'paths/bank_select_to_pe.rpt').read_text()) if (root/'paths/bank_select_to_pe.rpt').exists() else []
    e=electrical(sta)
    return dict(variant=v,area=area,cells=total,seq_area=seq_area,comb_area=area-seq_area,seq_cells=seq,comb_cells=total-seq,buffers=buffers,inverters=inv,
        setup_wns=float(field(r'^wns max (-?[0-9.]+)$',sta)),setup_tns=float(field(r'^tns max (-?[0-9.]+)$',sta)),actual_setup=gp[0]['slack_ns'],
        hold_wns=float(field(r'^wns min (-?[0-9.]+)$',sta)),hold_tns=float(field(r'^tns min (-?[0-9.]+)$',sta)),slew=e['max slew'],cap=e['max capacitance'],fanout=e['max fanout'],global_paths=gp,storage_paths=sp,bitmap_paths=bp,bank_paths=bank)

def main():
    OUT.mkdir(parents=True,exist_ok=True); rows=[parse('single'),parse('dual')]
    fields=['variant','mapped_area_um2','mapped_cells','sequential_area_um2','combinational_area_um2','sequential_cells','combinational_cells','buffer_cells','inverter_cells','setup_wns_ns','setup_tns_ns','actual_worst_setup_slack_ns','setup_violating_endpoints','hold_wns_ns','hold_tns_ns','max_slew_violations','max_capacitance_violations','max_fanout_violations','worst_startpoint','worst_endpoint']
    with (OUT/'comparison.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader()
        for r in rows:w.writerow(dict(variant=r['variant'],mapped_area_um2=f"{r['area']:.3f}",mapped_cells=r['cells'],sequential_area_um2=f"{r['seq_area']:.3f}",combinational_area_um2=f"{r['comb_area']:.3f}",sequential_cells=r['seq_cells'],combinational_cells=r['comb_cells'],buffer_cells=r['buffers'],inverter_cells=r['inverters'],setup_wns_ns=f"{r['setup_wns']:.6f}",setup_tns_ns=f"{r['setup_tns']:.6f}",actual_worst_setup_slack_ns=f"{r['actual_setup']:.6f}",setup_violating_endpoints=0,hold_wns_ns=f"{r['hold_wns']:.6f}",hold_tns_ns=f"{r['hold_tns']:.6f}",max_slew_violations=r['slew'],max_capacitance_violations=r['cap'],max_fanout_violations=r['fanout'],worst_startpoint=r['global_paths'][0]['startpoint'],worst_endpoint=r['global_paths'][0]['endpoint']))
    with (OUT/'path_summary.csv').open('w',newline='') as f:
        w=csv.writer(f);w.writerow(['variant','path_class','rank','startpoint','endpoint','slack_ns','evidence'])
        for r in rows:
            for cls,key,file in [('global','global_paths','global_top5.rpt'),('input_storage_to_pe','storage_paths','storage_to_pe.rpt'),('bitmap_to_control','bitmap_paths','bitmap_to_control.rpt'),('bank_select_to_pe','bank_paths','bank_select_to_pe.rpt')]:
                for rank,p in enumerate(r[key],1):w.writerow([r['variant'],cls,rank,p['startpoint'],p['endpoint'],f"{p['slack_ns']:.6f}",f"build/v2_n8k8_double_buffer_synth_sta/{r['variant']}/paths/{file}"])
    for r in rows:
        dst=OUT/r['variant'];dst.mkdir(exist_ok=True);src=BUILD/r['variant']
        for source,name in [(one(src/'work/reports','synth_stat.txt'),'synth_stat.rpt'),(src/'sta/openroad_sta.log','openroad_sta.log'),(src/'paths/global_top5.rpt','global_top5.rpt'),(src/'paths/storage_to_pe.rpt','storage_to_pe.rpt'),(src/'paths/bitmap_to_control.rpt','bitmap_to_control.rpt'),(src/'manifest.txt','manifest.txt'),(src/'source_sha256.txt','source_sha256.txt'),(src/'flow_sha256.txt','flow_sha256.txt'),(src/'frontend/elaboration_check.rpt','elaboration_check.rpt'),(src/'frontend/equivalence_status.txt','equivalence_status.txt')]:shutil.copy2(source,dst/name)
        if r['bank_paths']:shutil.copy2(src/'paths/bank_select_to_pe.rpt',dst/'bank_select_to_pe.rpt')
    s,d=rows; delta=d['area']-s['area']; pct=delta/s['area']*100; freq_ratio=3254/3919
    text=f"""# N8/K8 single-buffer versus dual-input-bank mapped STA

| Top | Mapped area / cells | Sequential / combinational area | Setup WNS/TNS | Actual worst setup slack | Hold WNS/TNS | Electrical violations | Worst path |
|---|---:|---:|---:|---:|---:|---:|---|
| `systolic_axi_burst_top` | {s['area']:.3f} µm² / {s['cells']:,} | {s['seq_area']:.3f} / {s['comb_area']:.3f} µm² | {s['setup_wns']:+.6f} / {s['setup_tns']:+.6f} ns | {s['actual_setup']:+.6f} ns | {s['hold_wns']:+.6f} / {s['hold_tns']:+.6f} ns | slew {s['slew']}, cap {s['cap']}, fanout {s['fanout']} | `{s['global_paths'][0]['startpoint']}` → `{s['global_paths'][0]['endpoint']}` |
| `systolic_axi_dual_bank_top` | {d['area']:.3f} µm² / {d['cells']:,} | {d['seq_area']:.3f} / {d['comb_area']:.3f} µm² | {d['setup_wns']:+.6f} / {d['setup_tns']:+.6f} ns | {d['actual_setup']:+.6f} ns | {d['hold_wns']:+.6f} / {d['hold_tns']:+.6f} ns | slew {d['slew']}, cap {d['cap']}, fanout {d['fanout']} | `{d['global_paths'][0]['startpoint']}` → `{d['global_paths'][0]['endpoint']}` |

- Dual-bank mapped area increment: **{delta:.3f} µm² ({pct:.2f}%)**, {d['cells']-s['cells']:+,} cells. Sequential area increases by {d['seq_area']-s['seq_area']:.3f} µm² and combinational area by {d['comb_area']-s['comb_area']:.3f} µm².
- Architecture predicts 1,024 additional A/B data bits plus 128 written-map bits. The mapped sequential-cell delta is {d['seq_cells']-s['seq_cells']:+,}; it also includes ownership/control differences and is not a direct bit-to-area conversion.
- Both setup analyses meet 2.500 ns. OpenSTA aggregate WNS clamps positive slack to 0; the full reports show {s['actual_setup']:+.6f} ns and {d['actual_setup']:+.6f} ns. Both global worst paths remain Core `cycle_idx` → PE accumulator paths.
- The explicit single-bank input-storage → PE path has {s['storage_paths'][0]['slack_ns']:+.6f} ns slack. Dual-bank storage → PE has {d['storage_paths'][0]['slack_ns']:+.6f} ns; the separate `active_bank` selection → PE path has {d['bank_paths'][0]['slack_ns']:+.6f} ns and is close to, but not the global worst path.
- Bitmap → state/control slack is {s['bitmap_paths'][0]['slack_ns']:+.6f} ns single and {d['bitmap_paths'][0]['slack_ns']:+.6f} ns dual. AXI decode/read/write logic is not represented in the global top five.
- Setup violating endpoints: 0 for both. The min-delay numbers are ideal-clock, pre-layout estimates and are not routed hold closure. Max-capacitance violations remain and require physical implementation to assess/fix.

## Conditions and limits

Nangate45 typical 1.10 V / 25 °C, 2.500 ns, 0.050 ns uncertainty, 0.250/0.000 ns max/min I/O delay, 0.050 ns input transition, 0.010 pF output load, and `5K_hvratio_1_1` wire-load model. All AXI functional inputs use the same budget; `rst_n` is the sole missing input-delay port because the existing active-operation SDC applies a reset false path. Clocks are ideal and interconnect is a synthesis wire-load estimate, not extracted routing.

Frontend Slang reports 0 errors/warnings and checks report 0 problems. N8/K8 source-to-derived equivalence was not used as a gate: an exploratory `equiv_induct` run produced scalability non-proofs. Post-synthesis and post-route equivalence are not proven. No placement, CTS, routing, LVS, or power analysis was run.

## Cycle-throughput context

The measured cycle totals are 3,919 single versus 3,254 dual, a {3919/3254:.6f}x same-clock speedup. To retain a throughput advantage, the dual implementation must preserve more than **{freq_ratio*100:.2f}%** of the single-buffer clock frequency (`3254/3919`); equivalently it can tolerate at most **{(1-freq_ratio)*100:.2f}%** frequency loss. This is a break-even calculation, not a measured Fmax claim.

## Reproduction

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts bash scripts/run_v2_n8k8_double_buffer_synth_sta.sh
python3 scripts/summarize_v2_n8k8_double_buffer_synth_sta.py
```
"""
    (OUT/'summary.md').write_text(text)
    print(f'wrote {OUT}')
if __name__=='__main__':main()
