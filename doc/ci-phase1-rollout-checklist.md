# CI Phase 1 Rollout Checklist

## 1) Configure repository variable
Set repository variable:
- Name: `LEGACY_OPAM_REPO`
- Value: `https://github.com/ocaml/opam-repository.git#<pinned-commit>`

Notes:
- Use a commit known to resolve old snapshots (`stable-0-0-*`).
- Keep this pinned; do not use floating branches for legacy lane.

## 2) Run first CI on a PR branch
Expected jobs:
- Legacy lane jobs (`snapshot-stable-0-0-*`, `develop`) on OCaml 4.12.0 and 4.07.1 for `stable-0-0-4`
- Modern lane jobs (`develop`, `stable-0-0-11`) on OCaml 4.14.2

Expected policy:
- Legacy lane should be required for merge.
- Modern lane is non-blocking (`continue-on-error`).

## 3) Verify debug output (temporary)
In each job, check step `Debug lane/repo selection`:
- `lane=legacy` jobs should print `opam-repo=<LEGACY_OPAM_REPO>`
- `lane=modern` jobs should print `opam-repo=https://github.com/ocaml/opam-repository.git`

If `LEGACY_OPAM_REPO` is missing, CI prints a warning and falls back to upstream default.

## 4) Branch protection settings
Require only legacy job checks initially.
Do not require modern lane checks yet.

## 5) Stabilization window
Observe results for 1-2 weeks:
- Track repeated failures by lane.
- Fix legacy regressions first.
- Keep modern failures informational unless they indicate upcoming breakage risk.

## 6) Remove temporary debug step
After the first successful confirmation run:
- Remove step `Debug lane/repo selection` from `.github/workflows/ci.yaml`.

## 7) Promote modern checks gradually
When a modern job is green consistently, consider making it required one-by-one.
Do not change legacy required checks while old SATySFi support is still a project requirement.
