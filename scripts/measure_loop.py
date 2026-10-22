#!/usr/bin/env python3
from pathlib import Path
import argparse,subprocess,json,datetime
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,default=ROOT);p.add_argument('--label',required=True);p.add_argument('--build-only',action='store_true');a=p.parse_args()
assert a.label.replace('-','').isalnum()
source=a.source_root.resolve()
def run(*args,**kw):return subprocess.run(args,cwd=source,text=True,check=True,**kw)
run('python3','scripts/generate_project.py')
excluded=[p.name for p in (source/'CoachInsightsTests').rglob('*.swift') if p.name not in ['PlaybackLoopBenchmarkTests.swift','BenchmarkFixture.swift']]
devices=json.loads(run('xcrun','simctl','list','devices','available','--json',capture_output=True).stdout)
for kind,title in [('iphone','iPhone'),('ipad','iPad')]:
 d=next(d for g in devices['devices'].values() for d in g if d['name']==f'CoachInsights 1.0 {title} QA')
 out=ROOT/'artifacts/v1.0.1'/a.label/kind;out.mkdir(parents=True,exist_ok=True)
 with (out/'loop.log').open('w') as log:
  run('xcodebuild','-project','CoachInsights.xcodeproj','-scheme','CoachInsights','-configuration','Release','-destination',f'platform=iOS Simulator,id={d["udid"]}',
      '-derivedDataPath',str(ROOT/'build'/('Loop-'+a.label)),'-resultBundlePath',str(out/('Loop-'+datetime.datetime.now().strftime('%H%M%S')+'.xcresult')),
      '-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','ENABLE_TESTABILITY=YES','EXCLUDED_SOURCE_FILE_NAMES='+' '.join(excluded),'-only-testing:CoachInsightsTests/PlaybackLoopBenchmarkTests','build-for-testing' if a.build_only else 'test',stdout=log,stderr=subprocess.STDOUT)
 if a.build_only:print('Release loop benchmark built',flush=True);break
 container=Path(run('xcrun','simctl','get_app_container',d['udid'],'com.coachinsights.CoachInsights','data',capture_output=True).stdout.strip())
 (out/'loop.json').write_text((container/'Documents/playback-loop.json').read_text());print(kind+': loop PASS',flush=True)
