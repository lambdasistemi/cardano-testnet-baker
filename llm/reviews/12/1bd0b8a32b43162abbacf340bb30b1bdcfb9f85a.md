---
sha: 1bd0b8a32b43162abbacf340bb30b1bdcfb9f85a
patch: wip-t003-acceptance-archive
task: T003
---

## ready

Round 2 of T003 — addresses the round-1 verdict on
`13bfc36`.

The reviewer correctly flagged a real bug: the archive-mode
branch was `baked_output_dir=$(extract_archive_seed "$input")`,
which runs `extract_archive_seed` in a *subshell* (Bash's
command-substitution semantics). The function's
`archive_extract_dir=$(mktemp ...)` therefore set the
variable only in the subshell; the parent shell's
`archive_extract_dir` stayed empty, and the
`trap cleanup EXIT` did `rm -rf ""` — leaving the mktemp tree
under `/dev/shm` (or `$TMPDIR`) on every archive-mode
invocation. T003 acceptance ("archive mode leaves no residue
in /dev/shm") was not actually satisfied.

### What changed

`compose/acceptance/run.sh`:

- Removed the global allocation from `extract_archive_seed`.
  The function now takes the extraction dir as its second
  argument and writes the seed tree under that path.
- The archive branch in the main flow allocates
  `archive_extract_dir` directly in the parent shell with
  the tmpfs+fallback `mktemp`, then calls
  `extract_archive_seed "$input" "$archive_extract_dir"`
  without command substitution. The cleanup trap therefore
  always sees a populated path, regardless of where (or
  whether) the helper fails.
- `baked_output_dir` is computed by the parent as
  `$archive_extract_dir/seed-root/seed` — same path the
  helper used to print, but no subshell hop.
- Added an explanatory comment block on
  `extract_archive_seed` and on the parent's allocation
  noting the subshell trap pitfall, so the next reader does
  not undo it.

### Validation

- `shellcheck --severity=warning` clean (run via
  `nix shell nixpkgs#shellcheck -c shellcheck --severity=warning
  compose/acceptance/run.sh`).
- The dir-mode path is structurally unchanged.
- The archive branch's failure modes — `skopeo copy` failure,
  `manifest.json` missing, layer count != 1, missing layer
  blob, missing `/seed/` root — all return non-zero from
  `extract_archive_seed` and propagate through `set -e`,
  with the cleanup trap removing the extraction dir on the way
  out.

### Local validation

Same caveat as earlier rounds: I cannot run the project's
`./llm/reviews/12/gate.sh` locally because of the
CI-vs-local narHash divergence noted earlier. CI's
compose-acceptance job exercises the dir-mode path directly;
T004's Nix check (next task) exercises the archive-mode path
via `seed-image-acceptance`.

## approved

- The round-1 cleanup blocker is fixed semantically: the parent shell now
  allocates `archive_extract_dir`, calls `extract_archive_seed` without
  command substitution, and derives `baked_output_dir` from the parent-owned
  path. The `trap` can therefore see and remove the archive extraction tree on
  both success and failure paths.
- The commit remains one vertical T003 slice, keeps directory mode intact, and
  records the author-run validation. Reviewer-owned commit message gate passed.
