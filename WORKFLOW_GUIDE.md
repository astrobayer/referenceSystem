# Workflow Guide — phone-and-CI development with a MATLAB postflight

*HOW-TO only. Every design decision, obligation and status statement lives in
`HANDOVER_referenceSystem.md`, which is the single point of truth (O36). This
file may POINT at the handover and must never RESTATE it: where the two
disagree, the handover is right and this file is stale.*

*Part 7 transfers the pattern to any other project. The shape is not specific
to MATLAB, to this toolbox, or to geodesy.*

---

## The picture (read once)

    DECIDE      Write the decision into the handover FIRST, as a statement of
                what will be true. Matthias approves or redirects. The code is
                then answerable to a standard rather than described by one.
    DEVELOP     Claude's container clones the repo, opens a branch, implements.
                Numerical claims get a Python mirror, committed - not left in a
                container that resets.
    PRE-CHECK   Audit and any licence-free suites run in the container. Free,
                no push, catches most of what CI would.
    PREDICT     State the expected test count BEFORE running anything.
    OPEN        Push the branch and open a DRAFT pull request at once. The
                draft is not the submission - it is what BUYS THE CI VERDICT.
                With `on: pull_request`, a branch without a PR gets no runs
                at all, however many times it is pushed.
    VERIFY      Two tiers, both recorded:
                  CI       - hosted runners, on every push once the PR exists
                  MCP      - the local machine, through the MATLAB MCP bridge
    PR          Green in both → mark the draft READY, citing both verdicts.
                Red → fix, push again, back to PRE-CHECK.
    MERGE       Matthias alone. `main` is protected; the checks must pass.
    RECORD      The same PR carries the handover's revision entry.

**Five actors.** GitHub (code, history, CI, PRs — public). Claude's container
(the developer). CI (the judge; MATLAB is free here *because* the repo is
public). The MATLAB MCP bridge (the second platform: the real machine, the
real toolchain, the toolkits CI cannot have). Matthias (the only one who
merges).

**Why two verifying tiers and not one.** They cover different ground and
neither is sufficient. CI is Linux, `gcc`, no MICE, a clean machine every time.
The local machine is Windows, `mex -setup C`, MICE present — and it is the only
place where the kernel-backed tests execute at all. A CI-green / MCP-red result
is the *expected* failure mode, not the exotic one.

---

## Part 1 — What has to exist on the local machine

1. **Git** — https://git-scm.com/download/win, defaults are fine. Verify in a
   *new* terminal: `git --version`.
2. **MATLAB on the system PATH** — add `C:\Program Files\MATLAB\R2026a\bin` to
   the system `Path`. Verify in a new terminal:
   `matlab -batch "disp(version)"`.
3. **Claude Desktop** — signed in.
4. **The MATLAB MCP bridge** — download `matlab-mcp-server.mcpb` from the
   latest release of https://github.com/matlab/matlab-mcp-server (MathWorks,
   free), double-click, *Install*, then fully restart Claude Desktop. The tools
   list should show MATLAB entries.
5. **Filesystem extension** (optional) — grant it the repository folder if
   Claude should read local files directly.

> **Checkpoint:** in a chat with the bridge active, "run `disp(2+2)` in MATLAB"
> succeeds.

---

## Part 2 — The repository

The repository is **public**, and that is a deliberate trade: the free MATLAB
on GitHub's runners exists only for public repositories. Consequences, all
non-negotiable:

- No measurement data, no credentials, no personal information. Ever. When in
  doubt it stays out.
- A `LICENSE` is chosen consciously. Until one exists, "public, all rights
  reserved" applies — people may look, not reuse.
- `.gitignore` keeps build products out: compiled MEX, platform binaries, help
  search databases, test reports. A committed binary is wrong for most people
  who clone it and *silently* wrong for the machine that built it once the
  sources move on.

Branch protection on `main`: require the status checks before merging, and
require branches to be up to date. Without it the CI is a reporting system, not
a gate — anyone, including a future Claude session, can merge red.

---

## Part 3 — The GitHub token

Claude's container has no GitHub identity, so it needs a token.

**Create it:** GitHub → *Settings* → *Developer settings* → *Fine-grained
tokens* → *Generate new token*.

- **Repository access:** *Only select repositories* — name the one repository.
  A token that can reach every repository turns one leaked file into six
  compromised projects.
- **Permissions:** `Contents: Read and write`, `Pull requests: Read and write`,
  `Actions: Read and write`. Actions matters: it is what lets a session cancel
  and re-run a wedged CI job, and a missing scope is discovered mid-incident,
  which is too late.
- **`Administration: Read and write`** only if Claude should set branch
  protection itself. Without it, that endpoint returns 403 and protection is a
  manual step in the web UI — which is the safer default.
- **Expiry:** short enough that forgetting it is survivable.

**Store it** as a file in the Claude Project, e.g. `github_token.txt`. Sessions
read it at call time.

**Handling rules — these are absolute:**

- Never committed to the repository, under any name.
- Never echoed into command output. Read it into a shell variable and pipe
  every command that carries it through `sed "s/$TOKEN/***/g"`.
- Never baked into a remote URL that a later `git remote -v` could print. If a
  clone uses `https://x-access-token:$TOKEN@…`, reset the remote to the plain
  URL immediately afterwards.
- Revoked and reissued the moment it appears anywhere it should not.

> **Checkpoint:** one probe call returns the repository's metadata, and the
> token's own expiry is visible in the response headers.

---

## Part 4 — The CI

Three jobs, cheapest first, so a cheap failure never waits on an expensive one:

| Job | Needs a licence? | What it checks |
|---|---|---|
| `audit` | no | The static audit script. Exits non-zero on findings. Seconds. |
| `csuites` | no | The standalone C suites, plain `gcc`, no MATLAB and no `mex.h`. |
| `matlab` | yes (free: public repo) | The full suite behind a single gate entry point. |

Two of the three need no MATLAB at all. That is the part worth copying: the
more a project can verify without its expensive toolchain, the faster the loop
and the less the licence matters.

**The gate entry point.** The CI never calls a bare test runner. A bare runner
reports failures but says nothing about coverage, and a suite that fails to
*load* passes unseen. The gate runs the suite, then judges: any failed test,
any filtered test not on the intended-filter allow-list, any test class on disk
that contributed nothing, or a missing report — and it **errors** on red so
that `matlab -batch` exits non-zero.

**Triggers.** `push` on `main` plus `pull_request`. Not `push` on all branches
*and* `pull_request`, which runs everything twice the moment a PR exists.

**Caches.** Use `cache/restore` and `cache/save` with `if: always()`, never the
combined action: its post step is skipped when the job fails, so every red run
re-downloads everything and leaves nothing behind.

**Artefacts.** Upload the test report with `if: always()`. It is wanted *most*
when the run is red.

---

## Part 5 — The loop in daily use

1. **Decide.** The decision goes into the handover before the code exists.
2. **Develop.** Container clones, branches, implements. Python mirrors for
   numbers, committed under `validation/`.
3. **Pre-check.** Audit and C suites in the container. Free.
4. **Predict.** State the expected count. A missed prediction is a finding even
   when the suite is green — this is what catches version/revision drift.
5. **Push, then open a draft PR immediately.** Two separate facts make this
   one step. Actions needs a ref, so CI cannot run before a push at all. And
   with `on: pull_request` and `push` restricted to `main`, a branch **without
   a pull request gets no runs whatever** — four pushes to a branch can produce
   zero runs, which reads exactly like a queue that has not started. The draft
   PR is what buys the verdict; it is not the submission.
6. **Verify, both tiers.**
   - CI judges each push now that the PR exists.
   - Run the same gate through the MCP bridge on the local machine.
   - Both verdicts are recorded separately. "Green" without saying which tier
     is not a verdict. A CI/MCP disagreement is a finding, not a nuisance —
     the tiers cover different ground on purpose.
7. **Ready.** Both green → mark the draft ready, citing both. Matthias reads
   *Files changed* and the log artefact, comments, merges.
8. **Record.** The PR carries the revision entry. No entry, no merge.

Steps 1–6a work from a phone. The MCP tier waits for the machine.

---

## Part 6 — When the MCP is unavailable (O2 and O37)

**O2** says a session whose report has not been read is not complete, whatever
the code looks like: record it as ◐, never ☑.

**O37 amends that** for one case. Development runs from a phone against CI for
days at a time, when the MATLAB MCP is by definition unavailable. A CI-green
change may then merge, and the unrun MATLAB tier becomes a **recorded debt**
rather than a blocker. Three conditions, and the exception fails without all
three:

1. **The revision row states the debt and its reason** — which bridge, and why
   it was down. "Unavailable" and "inconvenient" are indistinguishable a month
   later unless the reason is written, and only the reason stops the first
   quietly becoming the second.
2. **The board carries ◐, never ☑.**
3. **Discharge names what it clears** — *"run N discharges O2 for revs. 1.a
   through 1.b"*. The audit guards a closed item called open; nothing guards
   the reverse, which is the direction this rule creates.

A CI-only verdict is reported as **"green on CI, O2 open"**, in those words,
never as "green".

**The ceiling is 15 consecutive unrun revisions, and it WARNS.** It is not a
tolerance for sloppiness; it is the length of an ordinary phone-and-CI stretch.
A ceiling that blocked would stop the normal way of working in order to police
the exceptional one. `auditPackage.py` counts from the top of the revision log,
stops at the first row that recorded a run, and reports past the ceiling on a
channel that does not touch the exit code — so the exit code still means
exactly one thing: something is **wrong**, not something is **owed**.

---

## Part 7 — Transferring the pattern

Four files and two settings, independent of MATLAB:

1. **A single gate entry point** the CI calls — one command, green or fail,
   which checks its own coverage rather than only its assertions.
2. **`.github/workflows/ci.yml`** — copy it; swap the toolchain setup step and
   the gate command. Keep the cheap-jobs-first ordering, and **copy the
   draft-PR practice along with the trigger block**: `on: pull_request` alone
   is a silent no-op on a branch nobody has opened a PR for, and the two only
   make sense together.
3. **A pointer file** (`CLAUDE.md` or equivalent) naming that project's single
   source of truth, its commands and its hard rules.
4. **`.gitignore`** that keeps data and build products out.

Then: a scoped token as a Claude Project file, and branch protection on `main`.
Any local toolchain plugs into the postflight the same way MATLAB does, through
an MCP server if one exists for it. Where none exists, Part 6 is the whole
answer: CI is the verdict and the debt is recorded.

---

## If something goes wrong

- **The `matlab` job fails immediately with a licensing message** — is the
  repository still public? The free MATLAB exists only for public repositories.
- **A push produces no CI run** — is there a pull request for that branch? With
  `on: pull_request`, a branch without one gets no runs however often it is
  pushed, and the Actions tab simply stays empty rather than saying so. Open a
  draft PR. (Also check the workflow file is on that branch.)
- **The bridge does nothing** — Desktop app fully restarted after installing
  the `.mcpb`? MATLAB on the system `PATH`?
- **`git` or `matlab` "is not recognized"** — old terminal. Open a new one.
- **A branch protection API call returns 403** — the token lacks
  `Administration`. That is the safe default; set protection in the web UI.
- **Generated documentation looks stale after a version bump** — bump the
  version literals *first*, then regenerate. The generator reads the version at
  build time, so building before the bump stamps the old one and building after
  a bump that has already been recorded leaves the record ahead of the artefact.

---

## The rules that keep this safe

1. **Public means public.** No data, no credentials, no personal information.
2. **The handover is where the record opens** (O36). A PR body, a commit
   message, a code comment or this file may point at it; none may restate it.
3. **Any change under `.github/workflows/` is read before it is merged.**
4. **Merging is Matthias's alone.**
5. **A new check is fault-injected before it is trusted** (O29). A check that
   has only ever passed is not known to work.

---

*Created 2026-08-21 (CEST, UTC+02:00). Developed by Matthias Weigelt with the
assistance of Claude Opus 5 (Anthropic).*
