# 统一工作区（2026-10-22）

本项目已迁入 BaseballMaster.CC。当前状态以 [docs/CURRENT.md](docs/CURRENT.md) 为入口。公共品牌规范由 [总品牌目录](../../brand/README.md) 管理；开始品牌及宣传工作时显式读取该目录规范。资料位置以 [总导航](../../management/AGENT-GUIDE.md) 为准。总项目规则见 [工作区约定](../../AGENTS.md)。现有工程名、Bundle ID 和版本号保持稳定。历史证据中的旧目录按工作区 management/MIGRATION.md 映射追溯。

# Repository workflow

- When the user asks to package a build, complete the pull request and code review, fix blocking findings, merge into `main`, then package from the merged `main` checkout. Do not stop after merging into a development branch.
- Keep `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Build.xcconfig`. Use a build number above the highest one the user confirms has been uploaded. Version 1.0.1 build 3 has been uploaded; build 4 is the current packaging target.
- GitHub simulator verification must remain manual (`workflow_dispatch` only). Do not add automatic push or pull request triggers, or launch long performance/soak tests, without an explicit user request. Run focused local checks appropriate to changes.
- Keep signing configuration, private footage, archives and build output out of Git. Package locally; upload/distribute only when explicitly requested.
