#!/usr/bin/env python3
"""Check maintained documentation links, bilingual pairs and evidence consistency."""
from pathlib import Path
import argparse
import csv
import re
from urllib.parse import unquote


def without_fences(text):
    return re.sub(r'^\s*(```|~~~).*?^\s*\1\s*$', '', text, flags=re.M|re.S)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[1])
    args=ap.parse_args(); root=args.repo.resolve(); errors=[]; checked=0
    docs=sorted((root/'docs').rglob('*.md'))
    files=docs+[root/'README.md',root/'README-zh_CN.md']
    files += [root/p for p in ['models/wrapper/README.md','sim/burst/README.md','sim/packed/README.md']]
    for path in files:
        if not path.is_file(): errors.append(f'missing document: {path}');continue
        text=path.read_text();body=without_fences(text)
        for target in re.findall(r'\]\(([^)]+)\)',body):
            target=target.strip().split(' "',1)[0]
            if re.match(r'[a-zA-Z][\w+.-]*:',target): continue
            name,_,anchor=target.partition('#')
            dst=(path.parent/unquote(name)).resolve() if name else path
            checked+=1
            if not dst.exists(): errors.append(f'{path.relative_to(root)} -> missing {target}');continue
            if anchor and dst.is_file() and dst.suffix=='.md':
                headings=[];seen={}
                for heading in re.findall(r'^#{1,6}\s+(.+)$',without_fences(dst.read_text()),re.M):
                    slug=re.sub(r'[^\w\-\s]','',heading.lower()).replace(' ','-')
                    count=seen.get(slug,0);seen[slug]=count+1
                    headings.append(slug+(f'-{count}' if count else ''))
                if unquote(anchor) not in headings:errors.append(f'{path.relative_to(root)} -> missing anchor {target}')
        if path.name.endswith('-EN.md'):
            peer=path.with_name(path.name[:-6]+'-zh_CN.md')
            if not peer.exists():errors.append(f'unpaired English doc: {path}')
        if path.name.endswith('-zh_CN.md') and path.name!='README-zh_CN.md':
            peer=path.with_name(path.name[:-9]+'-EN.md')
            if not peer.exists():errors.append(f'unpaired Chinese doc: {path}')
    # Validate retained measurements without depending on one-time migration snapshots.
    try:
        with (root/'reports/wrapper/burst_comparison.csv').open(newline='') as f:old=list(csv.DictReader(f))
        continuous=[r for r in old if r['path']=='BURST' and r['length']=='16' and r['master_gap']=='0']
        if not continuous or any((r['measured_load'],r['measured_total'])!=('82','120') for r in continuous):
            errors.append('old N2/K17 L16 evidence differs from documented 82/120')
        rows=[]
        for p in sorted((root/'reports/wrapper/packed').glob('*_packed_comparison.csv')):
            with p.open(newline='') as f: rows+=list(csv.DictReader(f))
        if len(rows)!=24:errors.append(f'expected 24 retained packed rows, got {len(rows)}')
        selected=[r for r in rows if (r['n'],r['k'],r['length'])==('2','17','16')]
        if len(selected)!=2 or any(tuple(r[k] for k in ['beats','bursts','last_commit_cycles','write_complete_cycles','confirmed_load_cycles','total_cycles'])!=('18','2','21','22','24','62') for r in selected):
            errors.append('packed N2/K17 L16 evidence differs from documented boundaries')
        for lang in ['EN','zh_CN']:
            contract=(root/f'docs/wrapper/12_register_contract-{lang}.md').read_text()
            if not all(s in contract for s in ['0x0008','0x000C','0x0010','0x4000','0x5000','ACK','W1C','PACKED_ENABLE']):
                errors.append(f'incomplete contract markers: {lang}')
    except (OSError,KeyError,ValueError) as exc:errors.append(f'evidence validation: {exc}')
    if errors:
        print('\n'.join('FAIL '+e for e in errors));return 1
    print(f'PASS: {len(files)} Markdown files, {checked} relative links, bilingual pairs and retained measurement boundaries')
    return 0


if __name__=='__main__':raise SystemExit(main())
