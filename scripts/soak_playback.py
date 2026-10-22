#!/usr/bin/env python3
"""Four 10-minute editor resource scenarios per simulator. Latency uses measure_playback.py separately."""
from pathlib import Path
import subprocess,json,datetime,argparse
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument("--build-only",action="store_true");p.add_argument("--seconds",type=int,default=600);a=p.parse_args()
assert 1<=a.seconds<=600
def run(*args,**kw):return subprocess.run(args,cwd=ROOT,text=True,check=True,**kw)
run('python3','scripts/generate_project.py')
devices=json.loads(run('xcrun','simctl','list','devices','available','--json',capture_output=True).stdout)
targets=[(kind,next(d for g in devices['devices'].values() for d in g if d['name']==f'CoachInsights 1.0 {title} QA')) for kind,title in [('iphone','iPhone'),('ipad','iPad')]]
excluded=[f.name for f in (ROOT/'CoachInsightsTests').rglob('*.swift') if f.name not in ['PlaybackSoakTests.swift','BenchmarkFixture.swift']]
out=ROOT/'artifacts/v1.0.1'/('soak' if a.seconds==600 else f'soak-smoke-{a.seconds}');out.mkdir(parents=True,exist_ok=True)
base=['xcodebuild','-project','CoachInsights.xcodeproj','-scheme','CoachInsights','-configuration','Release','-derivedDataPath','build/PlaybackSoak','-parallel-testing-enabled','NO','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','3600','-maximum-test-execution-time-allowance','3600','CODE_SIGNING_ALLOWED=NO','ENABLE_TESTABILITY=YES','EXCLUDED_SOURCE_FILE_NAMES='+' '.join(excluded),'-only-testing:CoachInsightsTests/PlaybackSoakTests']
with (out/'build.log').open('w') as log:run(*base,'-destination',f'platform=iOS Simulator,id={targets[0][1]["udid"]}','build-for-testing',stdout=log,stderr=subprocess.STDOUT)
if a.build_only:print("Release soak host built",flush=True);raise SystemExit(0)
jobs=[]
stamp=datetime.datetime.now().strftime('%H%M%S')
for kind,d in targets:
 container=Path(run('xcrun','simctl','get_app_container',d['udid'],'com.coachinsights.CoachInsights','data',capture_output=True).stdout.strip())
 (container/'Documents/v101-soak-settings.json').write_text(json.dumps({'secondsPerScenario':a.seconds}))
 folder=out/kind;folder.mkdir(exist_ok=True)
 log=(folder/'test.log').open('w')
 cmd=base+['-destination',f'platform=iOS Simulator,id={d["udid"]}','-resultBundlePath',str(folder/f'Soak-{stamp}.xcresult'),'test-without-building']
 jobs.append((kind,d,subprocess.Popen(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT),log))
 print(f'{kind}: started four {a.seconds}s scenarios',flush=True)
failed=False
for kind,d,job,log in jobs:
 code=job.wait();log.close()
 if code:failed=True;print(f'{kind}: FAIL {code}',flush=True);continue
 container=Path(run('xcrun','simctl','get_app_container',d['udid'],'com.coachinsights.CoachInsights','data',capture_output=True).stdout.strip())
 report=json.loads((container/'Documents/playback-soak.json').read_text());(out/kind/'metrics.json').write_text(json.dumps(report,indent=2)+'\n')
 print(f'{kind}: PASS',flush=True)
raise SystemExit(1 if failed else 0)
