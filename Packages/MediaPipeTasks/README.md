# Pinned MediaPipe Tasks native distribution

The checked-in package manifest is Google's [Package.swift](https://github.com/google-ai-edge/mediapipe/blob/0e152b35eeea3cc9e8b55886428982b82de5925b/Package.swift), pinned to the native 1.1.1 release URLs and SHA-256 checksums. Binary archives are fetched by Swift Package Manager; no framework binaries are stored in Git. `Sources/MediaPipeTasksCommon/Exports.swift` is the local shim needed for the Common Swift target. Static calculator registration requires the upstream `-all_load` linker setting and all upstream binary dependencies.

Actual 1.1.1 archives include arm64 iPhone/iPad and arm64 simulator slices. The project therefore excludes x86_64 simulator builds; use an Apple Silicon Mac or the arm64 GitHub Actions runner. The minimum App deployment target remains iOS/iPadOS 17.

The Full v1 model is prepared separately by `scripts/prepare_dependencies.py`, checksum verified and copied into the App at build time. Runtime inference is offline. The optional Heavy comparison model belongs only to the ignored test fixtures and is never an App resource.

Upstream [iOS setup](https://developers.google.com/edge/mediapipe/solutions/setup_ios), [Pose Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker), and Apache 2.0 license: [LICENSE](LICENSE). A copy of the license is displayed in the App.
