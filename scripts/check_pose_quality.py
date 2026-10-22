#!/usr/bin/env python3
"""Report pose accuracy for auxiliary estimates; optionally enforce the historical target."""
import argparse
import json
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument("reports",nargs="+",type=Path)
parser.add_argument("--output",type=Path)
parser.add_argument("--strict",action="store_true",help="Require the historical 90%% reference target; not a 1.0 release requirement")
args=parser.parse_args()
results=[]
for path in args.reports:
    rows=json.loads(path.read_text());groups={}
    for sport in ["baseball_pitch","baseball_swing"]:
        group=[r for r in rows if r["sport"]==sport]
        if len(group)<30:
            parser.error(f"{path}: expected at least 30 measured frames for {sport}")
        keys=["visible","detected","correct","wristVisible","wristDetected","wristCorrect","elbowVisible","elbowDetected","elbowCorrect","leftRightSuspicions","highConfidenceErrors"]
        for row in group:
            if any(type(row[k]) is not int or row[k]<0 for k in keys) or not row["correct"]<=row["detected"]<=row["visible"]:
                parser.error(f"{path}: invalid joint counts for {sport}")
        sums={k:sum(r[k] for r in group) for k in keys}
        if sums["visible"]==0:
            parser.error(f"{path}: no visible reference joints for {sport}")
        groups[sport]={"frames":len(group),"clips":sorted(set(r["clip"] for r in group)),**sums,
            "coverage":sums["detected"]/max(1,sums["visible"]),
            "PCK005AllVisible":sums["correct"]/max(1,sums["visible"]),
            "PCK005DetectedOnly":sums["correct"]/max(1,sums["detected"]),
            "ambiguousFrames":sum(bool(r["ambiguous"]) for r in group)}
    passed=all(g["frames"]>=30 and g["PCK005AllVisible"]>=0.9 for g in groups.values())
    result={"report":path.name,"meetsReferenceTarget":passed,"groups":groups};results.append(result)
    print(path.name, "MEETS historical reference" if passed else "BELOW historical reference; auxiliary estimate, manual review required")
    for name,g in groups.items():
        print(f'  {name}: PCK@0.05 {g["PCK005AllVisible"]:.1%}; detected-only {g["PCK005DetectedOnly"]:.1%}; coverage {g["coverage"]:.1%}')
if args.output:
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({"deliveryMode":"auxiliary_estimate","referenceThreshold":0.9,"referenceThresholdBlocksRelease":False,
        "normalisation":"human-labelled per-frame body box height","results":results},indent=2)+"\n")
raise SystemExit(1 if args.strict and not all(r["meetsReferenceTarget"] for r in results) else 0)
