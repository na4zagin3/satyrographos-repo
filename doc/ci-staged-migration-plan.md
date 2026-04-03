# Staged CI Migration Plan (Keep Old SATySFi Working)

## Goal
Modernize CI/tooling while preserving support for old SATySFi snapshots.

Non-goal: dropping `snapshot-stable-0-0-*` support.

## Constraints we should respect
- Old SATySFi snapshots must remain installable and testable.
- CI should stay deterministic over time.
- Local developer setup should not depend on global OPAM plugin hooks.

## Strategy summary
Run CI in two lanes:

1. Legacy lane (required)
- Source of truth for compatibility with old SATySFi snapshots.
- Uses a pinned opam-repository commit (`LEGACY_OPAM_REPO`), not floating `master`.
- Keeps current snapshot matrix (`stable-0-0-4` ... `stable-0-0-11` + `develop` if needed).

2. Modern lane (non-blocking at first)
- Tracks current opam-repository tip.
- Targets fewer snapshots first (`develop`, latest stable snapshot).
- Used to incrementally raise toolchain health and detect future breakage early.

## Rollout phases

### Phase 0: Stabilize and capture baseline
- Keep existing CI as-is until legacy lane passes with a pinned opam-repository commit.
- Add this repository variable/secret:
  - `LEGACY_OPAM_REPO`: `https://github.com/ocaml/opam-repository.git#<commit>`
- Pick `<commit>` where historical toolchain resolves for old snapshots.

Exit criteria:
- Legacy lane green on PRs for old snapshots.

### Phase 1: Split CI lanes
- Introduce matrix dimension `lane: [legacy, modern]`.
- Use lane-specific repository selection:
  - `legacy`: pinned commit in `LEGACY_OPAM_REPO`
  - `modern`: `https://github.com/ocaml/opam-repository.git`
- Keep legacy checks required in branch protection.
- Mark modern as informational (continue-on-error or separate non-required check).

Exit criteria:
- Legacy required checks stable for at least 2 weeks.
- Modern lane runs reliably and produces actionable failures.

### Phase 2: Expand modern lane safely
- Add more snapshots to modern lane gradually.
- Tighten modern lane from informational to required only per snapshot after repeated green runs.

Exit criteria:
- Selected modern checks can be required without harming old SATySFi support.

## Proposed CI matrix split

Legacy lane matrix:
- `ocaml-version: 4.12.0`
- `snapshot: stable-0-0-11, stable-0-0-10, stable-0-0-8, stable-0-0-7, stable-0-0-6--1, stable-0-0-6, stable-0-0-5`
- extra include: `ocaml-version: 4.07.1`, `snapshot: stable-0-0-4`

Modern lane matrix (initial):
- `ocaml-version: 4.14.2` (or best currently green)
- `snapshot: develop, stable-0-0-11`

## Minimal workflow changes (implementation sketch)

Add to `strategy.matrix`:

```yaml
lane:
  - legacy
  - modern
```

Select OPAM repo per lane:

```yaml
- name: Determine default OPAM repo
  id: determine-default-opam-repo
  run: |
    if [ "${{ matrix.lane }}" = "legacy" ] ; then
      DEFAULT_OPAM_REPO="${{ vars.LEGACY_OPAM_REPO }}"
    else
      DEFAULT_OPAM_REPO="https://github.com/ocaml/opam-repository.git"
    fi
    echo "opam-repo-default=$DEFAULT_OPAM_REPO" >> "$GITHUB_OUTPUT"
```

Lane-specific selection (avoid combinatorial explosion):

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-11
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-10
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-8
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-7
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-6--1
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-6
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.12.0
        snapshot: stable-0-0-5
      - lane: legacy
        os: ubuntu-latest
        ocaml-version: 4.07.1
        snapshot: stable-0-0-4
      - lane: modern
        os: ubuntu-latest
        ocaml-version: 4.14.2
        snapshot: stable-0-0-11
      - lane: modern
        os: ubuntu-latest
        ocaml-version: 4.14.2
        snapshot: develop
```

Optional modern-lane non-blocking guard:

```yaml
continue-on-error: ${{ matrix.lane == 'modern' }}
```

## Safety checks to keep
- `opam lint --strict *.opam`
- Snapshot consistency check (`comm` required-by vs recursive-required-by)
- File collision detection (`satyrographos install test-satysfi-root`)
- `ci.sh` oldest-deps and revdeps checks

## Local developer recommendations
- Use a fresh local switch when reproducing CI.
- Avoid global OPAM plugin build hooks for this repo.
- If old snapshots fail to resolve on floating default repo, test with the same pinned `LEGACY_OPAM_REPO` as CI.

## Suggested branch protection policy
Required checks:
- `CI / legacy-*` (all legacy matrix entries)

Informational checks (initially):
- `CI / modern-*`

## Immediate next actions
1. Choose and set `LEGACY_OPAM_REPO` commit.
2. Update `.github/workflows/ci.yaml` with matrix `include` split by `lane`.
3. Open a PR with lane split and branch protection update.
4. Observe for 1-2 weeks, then decide which modern entries become required.
