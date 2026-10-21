#!/usr/bin/env python3
"""Summarise native measurements; exit 1 when the original release quality gate fails."""
import argparse
import json
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument("reports",nargs="+",type=Path)
parser.add_argument("--output",type=Path)
args=parser.parse_args()
results=[]
for path in args.reports:
    rows=json.loads(path.read_text());groups={}
    for sport in ["baseball_pitch","baseball_swing"]:
        group=[r for r in rows if r["sport"]==sport]
        keys=["visible","detected","correct","wristVisible","wristDetected","wristCorrect","elbowVisible","elbowDetected","elbowCorrect","leftRightSuspicions","highConfidenceErrors"]
        sums={k:sum(r[k] for r in group) for k in keys}
        groups[sport]={"frames":len(group),"clips":sorted(set(r["clip"] for r in group)),**sums,
            "coverage":sums["detected"]/max(1,sums["visible"]),
            "PCK005AllVisible":sums["correct"]/max(1,sums["visible"]),
            "PCK005DetectedOnly":sums["correct"]/max(1,sums["detected"]),
            "ambiguousFrames":sum(bool(r["ambiguous"]) for r in group)}
    passed=all(g["frames"]>=30 and g["PCK005AllVisible"]>=0.9 for g in groups.values())
    result={"report":path.name,"gatePassed":passed,"groups":groups};results.append(result)
    print(path.name, "PASS" if passed else "FAIL: pose quality release gate")
    for name,g in groups.items():
        print(f'  {name}: PCK@0.05 {g["PCK005AllVisible"]:.1%}; detected-only {g["PCK005DetectedOnly"]:.1%}; coverage {g["coverage"]:.1%}')
if args.output:
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({"threshold":0.9,"normalisation":"human-labelled per-frame body box height","results":results},indent=2)+"\n")
raise SystemExit(0 if all(r["gatePassed"] for r in results) else 1)
