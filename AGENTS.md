# Repository workflow

- When the user asks to package a build, complete the pull request and code review, fix blocking findings, merge into `main`, then package from the merged `main` checkout. Do not stop after merging into a development branch.
- Keep `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Build.xcconfig`. Use a build number above the highest one the user confirms has been uploaded. Version 1.0.1 build 3 has been uploaded; build 4 is the current packaging target.
- GitHub simulator verification must remain manual (`workflow_dispatch` only). Do not add automatic push or pull request triggers, or launch long performance/soak tests, without an explicit user request. Run focused local checks appropriate to changes.
- Keep signing configuration, private footage, archives and build output out of Git. Package locally; upload/distribute only when explicitly requested.
