#!/usr/bin/env python3
"""Pinned BZJA highlight GPU selector; retain the One UI 9 native/JNI cohort."""
import argparse,hashlib,json,pathlib
C=json.loads(pathlib.Path(__file__).with_name('contract.json').read_text())
def sha(b): return hashlib.sha256(b).hexdigest()
def check_models(root):
    for name,record in C['models'].items():
        p=root/name
        if p.is_file(): data=p.read_bytes()
        else:
            parts=sorted(root.glob(name+'.*'))
            if [p.suffix for p in parts]!=['.00','.01']: raise SystemExit('Incomplete MCA split model: '+name)
            data=b''.join(p.read_bytes() for p in parts)
        if sha(data)!=record['sha256'] or data[4:8]!=b'TFL3': raise SystemExit('Unreviewed MCA model: '+name)
def check_aliases(root):
    expected={'Detection.tfl':'human-pet-det_SR-V131.tflite','Pose.tfl':'human-pet-pose_SR-V200.tflite','Keyword.tfl':'keyword-classification_SR-V031.tflite'}
    for name,target in expected.items():
        p=root/name
        if p.exists() or p.is_symlink():
            if not p.is_symlink() or p.readlink()!=pathlib.Path(target):
                raise SystemExit('Unreviewed existing MCA alias: '+str(p))
def patch(path,apply,target):
    if target not in C['target_snap_sha256']: raise SystemExit('Unreviewed MCA target')
    snap=path.with_name('libsnap_aidl.snap.samsung.so')
    if not snap.is_file() or sha(snap.read_bytes())!=C['target_snap_sha256'][target]:
        raise SystemExit('Unreviewed target SNAP provider: '+target)
    for name,expected in C['retained_libraries'].items():
        retained=path.with_name(name)
        if not retained.is_file() or sha(retained.read_bytes())!=expected:
            raise SystemExit('Unreviewed retained One UI 9 MCA provider: '+name)
    data=path.read_bytes();h=sha(data)
    for guard in C['unchanged_guards']:
        expected=bytes.fromhex(guard['bytes']);start=guard['offset']
        if data[start:start+len(expected)]!=expected: raise SystemExit('MCA execution contract mismatch: '+guard['purpose'])
    if h==C['patched_sha256']:
        for x in C['instructions']:
            if data[x['offset']:x['offset']+4]!=bytes.fromhex(x['after']): raise SystemExit('MCA postcondition failed')
        return
    if h!=C['source_sha256']: raise SystemExit('Unreviewed One UI 9 MCA library: '+h)
    out=bytearray(data)
    for x in C['instructions']:
        pos=x['offset']
        if data[pos:pos+4]!=bytes.fromhex(x['before']): raise SystemExit('MCA instruction mismatch')
        out[pos:pos+4]=bytes.fromhex(x['after'])
    if sha(out)!=C['patched_sha256']: raise SystemExit('MCA output contract mismatch')
    if apply:
        # In-place preserves filesystem mode, ownership and SELinux metadata.
        with path.open('r+b') as f:
            if sha(f.read())!=h: raise SystemExit('MCA library changed concurrently')
            f.seek(0);f.write(out)
        patch(path,False,target)
a=argparse.ArgumentParser();a.add_argument('--target');a.add_argument('--models',type=pathlib.Path);a.add_argument('--aliases',type=pathlib.Path);a.add_argument('--library',type=pathlib.Path);a.add_argument('--apply',action='store_true');n=a.parse_args()
if n.aliases: check_aliases(n.aliases)
if n.models: check_models(n.models)
if n.library: patch(n.library,n.apply,n.target)
