Coach Insights: first local engine study, 2026-10-20

Scope from the user
- Version 1.0 supports both iPhone and iPad, with device-local storage and no iCloud sync.
- Bat trajectory and its semi-automatic tracking/correction tools were removed from version 1.0 on 2026-10-20.
- Video tools, drawing annotations, dual-video comparison and human pose analysis remain in scope.
- Current work is engine evaluation; a production iOS app is not implemented by this study.

Archived tracking study
The first study originally evaluated semi-automatic bat tracking. Its code, measurements and
reproduction steps below are retained as historical research. They are not active 1.0 work.
BootsTAPIR and the tracking-specific research dependencies are not application dependencies.
Current product scope is recorded in project_decisions.json; it supersedes the scope text
embedded in the original benchmarks/2026-10-20/summary.json snapshot.

Results
- results/report.html: readable report, with local videos.
- results/pose_comparison.mp4: three pose engines, all 78 input frames, slowed to 8fps.
- results/tracking_comparison.mp4: tracking candidates and corrected BootsTAPIR.
- results/semi_auto_demo.mp4: focused side-by-side correction simulation.
- results/summary.json: measurements, qualifications and approximate checkpoint errors.
- project_decisions.json: retained product scope.

Input video is provided locally by the user and is not included in the repository.
Frames were decoded using AVFoundation; original timestamps are in results/frames.json.
All pose engines receive the same 1280x720 JPEGs.
This is a macOS Apple Silicon feasibility study, not iOS performance or accuracy certification.
Approximate point labels are assistant visual references, not expert ground truth.
The fastest blurred swing frames are not assigned precise reference points.

Reproduction on macOS Apple Silicon (from the project root)
1. Create a Python 3.12 virtual environment and install research/requirements.lock.txt.
   Set the local input path, for example:
   export COACH_INSIGHTS_VIDEO="$HOME/Downloads/IMG_9673.mov"
   .venv/bin/python research/prepare_study.py
2. swiftc -parse-as-library research/inspect_video.swift -o .venv/inspect_video
   .venv/inspect_video "$COACH_INSIGHTS_VIDEO" research/results
3. swiftc -parse-as-library research/extract_frames.swift -o .venv/extract_frames
   .venv/extract_frames "$COACH_INSIGHTS_VIDEO" research/results/frames
4. swiftc -parse-as-library research/vision_benchmark.swift -o .venv/vision_benchmark
   .venv/vision_benchmark research/results
5. swiftc -parse-as-library research/optical_flow.swift -o .venv/optical_flow
   .venv/optical_flow research/results --sanity yes
   .venv/optical_flow research/results
6. .venv/bin/python research/mediapipe_benchmark.py --variant lite
   .venv/bin/python research/mediapipe_benchmark.py --variant full
7. .venv/bin/python research/tracking_baselines.py
8. Place official BootsTAPIR checkpoint at research/models/bootstapir_checkpoint_v2.pt.
   The official URL and local file SHA256 values are in research/provenance.json.
   Vendored source is the official tapnet/torch implementation; its license is retained.
   .venv/bin/python research/sanity_tapir.py
   .venv/bin/python research/bootstapir_benchmark.py --width 256
   .venv/bin/python research/bootstapir_benchmark.py --width 448
9. .venv/bin/python research/build_results.py
   .venv/bin/python research/write_report.py

Native flow revision 1 was explicitly selected after a known-translation coordinate check.
Its synthetic test expected (+10,+5) pixels and measured approximately (+9.98,+4.96).
BootsTAPIR uses the whole video (offline/noncausal) and extra query points for correction simulation.
BootsTAPIR performance excludes checkpoint loading and video decoding.
Input resolution variants are retained separately; 256x256 follows the official demonstration.
Confidence / visibility outputs from different methods are not mutually calibrated.
Rejected outputs remain visible as red crosses in the debug video; they are not valid trajectory results.
Dense flow has no endpoint confidence score. A passing tracking gate does not imply a correct location.

Dependencies and files
- All Python installs are isolated to .venv; the bundled runtime is only used as a base interpreter.
- fetch_wheel.py downloads public wheels through a mirror and verifies them against official PyPI SHA256.
- Downloads, checkpoints, decoded frames and all generated media/report files under results/ are ignored.
- fixtures/img_9673/ contains the versioned numerical initialization and approximate reference points.
- benchmarks/2026-10-20/summary.json preserves the first run's numerical summary without footage or images.
- License: research/vendor/tapnet/LICENSE; official source provenance: research/provenance.json.
