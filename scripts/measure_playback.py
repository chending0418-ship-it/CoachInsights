#!/usr/bin/env python3
"""Compare optimized production playback on the same isolated QA simulators."""
from pathlib import Path
import subprocess, json, argparse, datetime
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('--device',choices=['both','iphone','ipad'],default='both');a=p.parse_args()
assert a.label.replace('-','').isalnum()
def run(*args,**kw):return subprocess.run(args,cwd=ROOT,text=True,check=True,**kw)
run('python3','scripts/generate_project.py')
excluded=[f.name for f in (ROOT/'CoachInsightsTests').rglob('*.swift') if f.name not in ['PlaybackPerformanceTests.swift','BenchmarkFixture.swift']]
devices=json.loads(run('xcrun','simctl','list','devices','available','--json',capture_output=True).stdout)
for kind,title in [('iphone','iPhone'),('ipad','iPad')]:
 if a.device not in ['both',kind]:continue
 d=next(d for g in devices['devices'].values() for d in g if d['name']==f'CoachInsights 1.0 {title} QA')
 out=ROOT/'artifacts'/'v1.0.1'/a.label/kind;out.mkdir(parents=True,exist_ok=True)
 print(f'{a.label}: {kind}; {out}',flush=True)
 with (out/'benchmark.log').open('w') as log:
  run('xcodebuild','-project','CoachInsights.xcodeproj','-scheme','CoachInsights','-configuration','Release','-destination',f'platform=iOS Simulator,id={d["udid"]}',
      '-derivedDataPath','build/PlaybackBenchmark','-resultBundlePath',str(out/('Performance-'+datetime.datetime.now().strftime('%H%M%S')+'.xcresult')),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','ENABLE_TESTABILITY=YES',
      'EXCLUDED_SOURCE_FILE_NAMES='+' '.join(excluded),'-only-testing:CoachInsightsTests/PlaybackPerformanceTests','test',stdout=log,stderr=subprocess.STDOUT)
 container=Path(run('xcrun','simctl','get_app_container',d['udid'],'com.coachinsights.CoachInsights','data',capture_output=True).stdout.strip())
 report=json.loads((container/'Documents/playback-performance.json').read_text());(out/'metrics.json').write_text(json.dumps(report,indent=2)+'\n')
 print(f'{kind}: PASS',flush=True)
