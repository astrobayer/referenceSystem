# Validation Guide — what a green suite is allowed to mean

*HOW-TO only. The binding rules for **this** toolbox are handover Part D and
sections C.4 and C.9; where this file and the handover disagree, the handover is
right and this file is stale (O36). What is written here is the reasoning, in a
form another project can adopt.*

**This file OWNS: the categories, oracles, tolerances-as-findings, filters,
prediction, fault injection, the green gate and the verification tiers. Other
guides point here rather than repeating them.** `CODING_GUIDE.md` owns the code
rules, `DOCUMENTATION_GUIDE.md` the templates and artefacts, `WORKFLOW_GUIDE.md`
the loop.

*Generalised from three projects: `referenceSystem` (handover Part D,
`BEST_PRACTICE.md` Part 3), `lsqvce`, and `geoMap v2`, whose seven-category
scheme and ratio-based speed doctrine supersede the narrower ones the other two
started with. Every number quoted below was measured somewhere, not estimated.*

---

## The one idea

**A test that cannot fail informatively is not evidence.** Green is a claim
about coverage as much as about correctness, and most of the work below is about
making that claim honest: which tests ran, which did not, why, and on what
machine.

Two measurements justify the whole document:

- Run 1 of one session found **seven** defects — two in library code — after a
  clean static audit *and* a cross-language mirror that had already caught five.
  Reviewing does not substitute for running.
- An audit that asked "which categories does each function actually ship?" for
  the first time found **46 of 81 functions short of at least one category,
  after nine green runs.** Counting categories is not bookkeeping.

---

## Part 1 — The seven categories

Three tiers (`contract` / `numeric` / `speed`) is what most projects reach for,
and it is too coarse: it collapses four distinct questions into `numeric` and has
no category at all for vectorisation or metamorphic properties — the two cheapest
reference tests in an array language, and the two most often assumed.

| Tag | Asserts | Typical form |
|---|---|---|
| `contract` | The promises in the help text: output shapes and types, argument rejection with the **documented** identifier and only that one, determinism where promised, error messages naming the offending field | Every documented identifier fires; NaN-as-gap propagates; orientation preserved |
| `reference` | Agreement with an outside authority — see Part 2 | A second toolkit, a published worked example, a real third-party file |
| `precision` | The numerical claim, with an explicit tolerance **and a comment saying where the tolerance came from** | Round-trip identity; direct and composed paths agreeing; closure at the measured floor |
| `speed` | A **relative** budget against a recorded baseline on the same machine — see Part 4 | `cost(dispatcher)/cost(kernel)`, both timed on the same arrays |
| `robustness` | Behaviour at and beyond the edge of validity: degeneracy **constructed from the algebra**, conditioning, boundary and empty inputs, non-finite propagation, reproducibility under worker count | The exactly-degenerate parameter; the antipode; the single-row grid; the all-NaN source |
| `vectorisation` | A batched call equals the same inputs one at a time | 1000-element array equals 1000 scalar calls, **bitwise** |
| `metamorphic` | Invariance and equivariance **through the public API**, each stating whether the expectation is bitwise or eps-level and why | Shift equivariance; split/merge; permutation invariance; mirror symmetry; idempotence |

Add cross-cutting **tags**, which are not categories and do not count as
coverage:

- `diagnostics` — does every measured number reach the report? Does the
  documented warning fire exactly once, whatever N?
- `provenance` — does every result carry the metadata saying where it came from,
  and every source file its authorship and version?
- `layering` — a static check that no layer calls upward.
- `concurrency` — identical results at 1, 2 and N threads, **bit-identical**, not
  to a tolerance. Cheap, and the only guard against a future optimisation
  introducing a thread-order-dependent reduction.
- `convergence` — refine the step and assert the expected order and the location
  of the roundoff–truncation plateau. This replaces the circular check of a
  finite difference against a finite difference, which passes for any step,
  including a badly chosen one.

**`reference` is the hard one and the one that matters.** A round trip proves
self-consistency; it cannot detect a sign convention wrong in both directions.
Only an external authority can.

**`metamorphic` is the cheap one nobody writes.** It needs no oracle at all, only
a property the API must satisfy, and it catches the class of defect where every
individual value looks plausible.

**Where `precision` ends and `metamorphic` begins**, because a round trip looks
like both: **if the assertion needs ONE call and a known answer, it is
`precision`; if it needs TWO related calls compared to each other, it is
`metamorphic`.** A round trip is therefore `precision` — one composite call
against the identity. Shift equivariance is `metamorphic` — two calls with
different arguments that must agree. When a test could be written either way,
prefer `metamorphic`, because it needs no tolerance source.

### Counting and exemptions

**Count mechanically, per unit.** The audit reports, for every public function,
which categories its suite ships. Anything missing and not exempted is a gap.

**An exemption is a claim that the test is impossible, not that it is
inconvenient.** One row per function per category, each with a reason a sceptic
could argue with. Two mechanical rules keep the list honest:

1. **`contract` may never be exempted for a function that validates its
   arguments.** Validation runs before the body, so a rejected call is refutable
   in microseconds however expensive a successful one is.
2. **Something must refuse an entry whose category has since become covered**,
   or the list rots into a dumping ground that licenses gaps permanently.

Usually legitimate: graphics elements have no batched form, so no
`vectorisation`; a function whose observable is a hit or a miss has no
invariance, so no `metamorphic`; a function reporting the state of *this machine*
has no external authority, so no `reference`; a path is not a quantity whose
precision can be round-tripped, so no `precision`.

Both directions of the exemption trap have been walked here. The staleness
companion once refused an exemption written the same hour: routing test helpers
through a new function gave it `reference` coverage through the calls, and the
impossibility claim became false within the hour. The correction then over-shot —
the diagnostic named **one** category, the whole entry was removed, and the next
run failed on the other. **Read the scope of a diagnostic, not only its verdict.**

---

## Part 2 — The oracle register

> **If you cannot name what this will be checked against that was not built
> here, the prompt is not ready.**

Keep a table of oracles, and let gaps show as **empty rows rather than as an
absence nobody notices**. A work package may not begin with an unfilled oracle
row in its scope.

| Column | Why |
|---|---|
| id | So a test cites `O4` rather than restating the authority |
| Oracle | The thing itself, **with version** — `pyproj 3.7.2 / PROJ 9.5.1`, not "PROJ" |
| Type | Worked example / second toolkit / real data file / analytic invariant / prior implementation |
| Certifies | Exactly what it is evidence for, and nothing wider |
| Consumed by | Which stage, which category |
| Status | Confirmed with a date and the agreement achieved, or open |

**Types, in descending strength.** A *second independent toolkit* is strongest
and most work. A *published worked example* is cheap and narrow. An *analytic
invariant* costs nothing and is often the best available — an equal-area
projection's area integral is 4π, a conformal one has zero angular distortion,
and no external file is needed for either. A *real third-party data file* is the
only thing that certifies a reader. A *prior implementation* is an oracle only
for the defects it is known to have: it is the thing being replaced, not an
authority on correctness.

**Configure the oracle deliberately and record how.** One comparison here needed
a same-sphere geographic source rather than the obvious EPSG code, which would
have inserted a datum shift into every residual. That note belongs beside the
result, or the next person re-derives the trap.

**Record what the oracle refuted, not only what it confirmed.** One register row
reads: two values confirmed exactly, two refuted — and the refutations were the
round's real output.

**A data-derived number is written with the span of the data it came from**, and
re-derived when the span grows.

### Oracles for a geodetic or astrodynamic toolbox

The examples above are cartographic because that is where the register was first
written. The equivalents in this domain, with the same discipline:

| Type | Oracle | Certifies |
|---|---|---|
| Worked example | IAU SOFA cookbooks and the test values in the vendored sources | Frame chains end to end, at published intermediate values |
| Normative text | IERS Conventions (2010), TN36 | Model definitions, the constants, the correction terms |
| Second toolkit | JPL MICE / CSPICE | Ephemeris state vectors, body-fixed rotations, quaternion algebra |
| Real data | JPL HORIZONS vector fixtures | End-to-end body states, against a service this project did not write |
| Published paper | The ephemeris release paper for the kernels in use | Which kernels form a coherent set, and the bound on mixing generations |
| Analytic invariant | Orthonormality of a rotation matrix; the rate matrix being skew-symmetric in the body frame; round-trip through a time-scale chain | Costs nothing, needs no file, and catches sign and transpose errors |
| Prior implementation | The toolbox being replaced | **Only** its known defects. Not an authority on correctness. |

**Two domain-specific traps belong in the register's notes.** A comparison
against an external toolkit must fix the *frame realisation and the time scale
on both sides* or the residual contains a transformation nobody intended — the
same shape as the datum-shift trap in the cartographic case. And a kernel or
data file is an oracle only for the span it covers; state the span beside the
expectation.

---

## Part 3 — The ways a suite lies

### Vacuous passes

- **The unobserved warning.** Provoke a warning, assert the result, never check
  the warning was raised.
- **The premise that failed to build.** A test that constructs a difficult
  situation and then asserts something true regardless. If the construction can
  fail silently, assert that it succeeded first.
- **The circular check.** Finite differences against finite differences.
- **The proxy.** Asserting something implied by the claim rather than the claim.

**A passing test must leave the number it checked.** An assertion that passes
leaves no trace, so the report goes silent about exactly the measurements that
went well. Give the harness a `verifyAndRecord(actual, bound, label, units)` that
qualifies the bound *and* returns a report record, so **an assertion cannot exist
without something to log**. A new record type is not a diagnostic until the
report has a section for it.

### Filters and skips

Three categories, kept distinct in the report, and only three:

1. **Intended, unconditional** — the premise cannot be built on *any* machine.
2. **Intended, conditional** — the premise cannot be built *while a named
   capability is absent*. The condition is a **symbol**, not an adjective, and it
   is the same symbol the test's own guard probes.
3. **Unexpected** — everything else, and it fails the gate.

The conditional category earns its complexity: a skip excused unconditionally is
excused on the one machine where the test *could* have run. Here, eight tests
needing an external toolkit are excused on hosted runners that cannot install it
and reported as findings on the machine that has it — and the first time that
fired it was right, because the data had moved and seven consumers were still
looking in the old place.

**Beware what the capability probe proves.** That a wrapper file resolves is not
that the toolkit works.

### The instrument that lies

The failure mode that produced more red runs than any other: **a cheap
instrument's silence read as evidence about what an expensive one checks.** Twice
in three revisions here, a static audit checked *help sections* while the suite
checked *test categories*; the lists differed; a file satisfying the first failed
the second. The second time, the lesson from the first was already written down
by the same author.

- **No count, structure or coverage claim from an instrument written in the same
  session as the change it checks** — unless the instrument has been shown to
  fail on a known defect. Otherwise mark the claim provisional, in writing.
- **Every check ships a fault-injection self-test in the same round**: it fires
  on a broken tree, silent on a healthy one. A check without a fixture proving it
  fires is not a check.
- **The second gate must read something the first does not.**
- **An "independent" check copied from the code under test is not independent.**
- **Prove a mutator on a scratch copy and read the applied diff** before pointing
  it at the tree. A help-text migration over 94 files produced three defects,
  every one found by reading the diff and none by any check — a lowercase-only
  rename left the old name in every uppercase header.
- **A one-shot mutator is not shipped.**

---

## Part 4 — Speed doctrine

**Absolute budgets are withdrawn.** An absolute figure with no baseline cannot
detect the change it was written for. One project shipped a **1.30× regression**
behind an absolute benchmark, and a sub-millisecond absolute row swung **6.8×
across three runs on untouched code**.

**Every budget is a ratio**, stated with its measurement point `N`, its
`expected` value and its provenance, and a `budget` clear of expected in the
direction failure would hurt. **Concretely: `budget = 3 x expected` where slow is
the risk.** Where the assertion is a *speedup* the direction reverses and the
comparison is `>=`, which must be written out — `cache cold / warm >= 10` against
an expected 50 is a floor, not a ceiling, and a reader who assumes otherwise
inverts the test. Where `expected` comes from a mirror rather than a recorded
baseline, widen to 3x and label the row **PREDICTED**, because a cross-language
ratio transfers only when both sides scale alike.

### The timing helper comes before the first budget

One helper is **the only** timing instrument in the project. Eleven near-copies of
a local median helper in one project meant thirteen places for the next repair to
be applied twelve times. **No budget may be written before its instrument
exists** — which is why the harness is the first work package, not the last.

It does all of this, and no test does any of it by hand:

1. One untimed warm-up call per point.
2. **Both points timed inside one repeat** — never A to completion then B. That
   puts them in different windows and everything that drifts lands on the later
   one. Measured: a ratio read **8.298 inside the full runner against 4.81 to
   5.54 for the same binary run alone, five times out of five**, against a budget
   of 8.
3. **Rotation** of which point goes first; a fixed order leaves a small,
   always-identically-signed bias.
4. **15 repeats.** Measured spread over 10 trials: 5 → 31.2%, 9 → 14.0%,
   15 → 10.2%, 21 → 4.4%.
5. The statistic formed **per repeat**, then the **median of those** — never a
   ratio of medians.
6. A failure message quoting the per-repeat `min .. max` band, so the next reader
   can tell a regression from a machine having a bad minute.
7. A returned report record carrying the ratio, the band, both absolutes and the
   machine tag.

### Choosing the pair

The stable shape is **two sides doing the same work on the same arrays** — a
dispatch layer against the kernel it dispatches to. Before any budget is written:

- **Same memory regime.** One budget moved 6.751 → 9.380 between two runs of
  byte-identical code because its points were 3.1 MiB and 12.5 MiB, straddling
  L3. Check the footprint first.
- **Fixed cost must not dominate a growth budget.** Solve `f + v` and `f + 4v`
  from two points; if `f` is larger, the ratio is measuring call overhead. One
  ladder *passed* at 0.95× and 1.08× where linear predicts 2.00×, because 99% of
  the small point was the call.
- **Below ~1 ms you are timing the timer.** Inner batch, not more repeats.
- **Cross-language ratios transfer only when both sides scale alike**, and the
  direction is not predictable. A mirror figure is quoted as prediction, never as
  authority.

**A threshold does not move as part of an instrument repair.** If the honest
instrument reads differently, that is a finding recorded with its measurement,
never absorbed by widening the budget.

**Renderer-dependent budgets are weak evidence**, tagged so, reported separately;
a red one opens an investigation rather than blocking a release.

**Do not compare per-suite seconds across rounds of different colour.** A failing
verification makes the framework build a diagnostic, resolve a stack and format
links, which is not free.

### Repeatability before interpretation

Two consecutive runs of identical code on one machine give the scatter; only then
does a cross-machine ratio mean anything. That exercise once refuted the previous
revision's reading of its own numbers: rows dismissed as "at the timing floor,
not interpretable" reproduced to 1.3–1.7%, while the single-shot row carrying the
argument swung 11.8%.

**At the timing floor you are measuring call overhead, not the function.** Still
useful — but it is not a statement about the thing it names, and the report
should say so rather than refuse the row.

---

## Part 5 — Warnings are a gate

**Exactly one warning identifier may appear in a clean run's inventory: a
deliberate internal test probe.** Any other identifier is new and fails the gate.
This needs no allow-list to maintain, which is the point.

- A test that provokes a documented warning **turns that identifier off for the
  duration with a cleanup-based restore**, so a failing assertion cannot leave
  warning state altered for later suites.
- **Do not silence an identifier where it cannot fire.** An unnecessary
  suppression teaches the next reader that the identifier is unavoidable.
- Reuse a documented identifier rather than coining a test-only one.
- **A warning-free assertion is about all warnings, not the one you mean.**
  Silence the neighbours explicitly, then assert.
- **State-changing REPL experiments carry the same cleanup obligation as tests.**
  A snippet that disables warnings and crashes before its restore leaves the
  interpreter's warning state off globally; six unrelated suites then failed
  their warning assertions at once.

> **A cluster of unrelated failures sharing one symptom is session state, not
> code.** Check the state before reading a single diff.

---

## Part 6 — The green gate

**Green means: zero failures AND every suite loaded AND no new warning identifier
AND no speed budget exceeded AND the manifest verified AND the static audit
exited zero.** Not "the number went up."

**One runner, and its count is authoritative** — never the framework's directory
discovery directly. Its log records: manifest verification; which files loaded;
pass / fail / incomplete per suite; per-suite seconds; the warning inventory by
identifier; every speed record with its ratio and band; the category coverage
table.

**Read the log, not the pass count.**

**One gate entry point** wraps the runner and judges:

- any failed test → red
- any unexpected filter → red
- **any test file on disk that contributed nothing** → red
- **any expected class absent from the results** → red
- no report written → red

and **errors** on red so a batch invocation exits non-zero. Return codes are not
enough: a runner that returns results and raises only on catastrophic failure
lets a red run look like a pass to any caller checking for an exception. **A
suite that fails to load passes unseen**, which is worse than a failure, because
a failure is counted.

**Reconcile the report's own arithmetic** rather than reading its summary line:
per-tag counts summing to the total, passed plus skipped equalling the total,
every class present. A guard that prints nothing when nothing is wrong is
evidence only when an independent count agrees.

---

## Part 7 — Predict before you run

**State the predicted point count before every run**, reconciled three ways: **tag
sums, per-class sums, and pass-plus-skip**. Per suite, **declared vs executed**: a
grep for the test-function pattern minus the entry point must equal the executed
count exactly.

The prediction exists because **a suite that silently fails to load is
indistinguishable from a green run by the pass count alone.**

**A missed prediction is a finding even when the suite is green.** It has caught
here: a version literal moved in one file and not its pair; four methods added
where the arithmetic assumed four and parameterised tests added three more; a
whole class silently excluded.

> **The prediction is a disposable per-round instrument. It is never written into
> the permanent record and no test asserts a hardcoded total.**

The discipline erodes exactly when running becomes cheap. Write the prediction
where it cannot be quietly revised — a commit message, a pull-request body.

---

## Part 8 — Tiers, and what "green" may mean

| Tier | Cost | Covers |
|---|---|---|
| Static audit | seconds, no toolchain | Conventions, provenance, structure, layering |
| Native suites | seconds, compiler only | Numerical core without the expensive toolchain |
| Cross-language mirror | minutes | Numbers derived independently of the implementation |
| CI | minutes | A clean machine, a second platform, every push |
| Local | minutes | The real toolchain, optional dependencies, the user's configuration |

### Two different things are called a tier, and they are orthogonal

**Execution tier** answers *what can this session reach?* **Verification tier**
answers *what judged this change?* A session can be execution-Tier-A and still
have a red CI verdict, so the two are reported separately and never collapsed.

| | Tier A | Tier B |
|---|---|---|
| **Execution tier** | A live interpreter is reachable from the authoring session, **over the very folder the deliverable is built from**. If the run is over a copy, it is Tier B with extra steps. | No interpreter in the sandbox. Development is mirrored, every asserted number pre-validated there, and the human's run is the gate. |

**Declare the execution tier in the first line of every session, never assume
it**, and **state what it does not give**, measured rather than assumed — for
example, that a push can be made but a pull request cannot be opened, so a
human clicks once per round.

The verification tiers are the five rows in the table above. `WORKFLOW_GUIDE.md`
Part 6 owns what happens when one of them is unavailable.

**The mirror survives promotion to Tier A.** It is the pre-validation instrument,
not a fallback; it loses only its role as the last word. Where target and mirror
disagree, the **target is right by definition** — the mirror's job is to find the
disagreement, not to win it.

Mirror rules worth copying wholesale: **one owner per kernel**, and a stage that
needs it **imports** rather than re-derives; arithmetic changes in the target
change the mirror **in the same round**; scratch probes are deleted the day they
are written, while the *procedure* is kept; superseded scripts are **frozen, not
rewritten**, as the record of their own round; and `LIMITS.md` records what the
mirror structurally **cannot** see — dropped trailing singleton dimensions,
graphics, differing extrapolation semantics, speed ratios that transfer only when
both sides scale alike.

**A disagreement between tiers is a finding, not a nuisance.** Here CI and the
local machine differ by exactly eight tests on identical sources, and that number
*is* the argument for running both.

**Never report "green" without naming the tier.** If one could not run, say which
and why, and record the debt with a discharge that **names what it clears** — then
count the debt, so one nobody rereads cannot accumulate silently.

---

## Part 9 — Diagnosis order

When a number is wrong: **configuration, then criterion, then code.** Cheapest
repair first.

1. **Configuration.** Replay the exact frozen script, never a recollection of it.
   A paraphrased mask once halved a validated trend — +0.71 against +1.41 — and
   an hour went into hunting a code regression that did not exist.
2. **Criterion.** Re-derive it against an external authority. A criterion is
   *corrected*, never widened until it passes.
3. **Code.** Last.

**Never loosen a tolerance to make a test pass — that is a finding.** Decompose
the residual into its physical contributors first. A criterion loosened until
green is an instrument destroyed in place.

**A guard is not a fix.** Where a defect can be removed, remove it; a guard that
hides it is worse than the failure it replaces, because it looks like progress.

---

## Part 10 — Tests must not change the machine they measure

- **Persistent settings.** A test that stores a user preference and then errors
  leaves the machine reconfigured, and unlike a path change that survives a
  restart. Save and restore through a cleanup handler, in **one** helper so a
  later test cannot forget it.
- **Installer defaults.** When an installer's defaults turn on, every test calling
  it inherits them. Route every call through a single options helper.
- **Network dependence.** A test whose premise needs a *failed* transfer passes
  vacuously wherever the network is fast.
- **Scratch locations.** A temporary directory may sit inside a scanned user
  profile, so a ratio between two scanned locations returns 1 whichever way the
  truth lay — worse than no measurement, because it looks like one.

**If the suite follows a user setting, the report must name the setting.**
Otherwise two runs of identical sources can cover different tests and be
indistinguishable in the record.

---

## Part 11 — A test class skeleton

```matlab
classdef TestB1_projection < ProjectTestCase
    methods (Test, TestTags = {'contract'})
        function returnsNaNOutsideDomain(tc)
            % F3: v1 clamped to +/-85 and drew data at the wrong place.
            [x, y] = geo.project(0, 87, tc.crsMercator);
            tc.verifyTrue(isnan(x) && isnan(y));
        end
    end
    methods (Test, TestTags = {'reference'})
        function agreesWithSecondToolkit(tc)
            % Oracle O4 (pyproj), values from mirror/out/reference_values.json.
            ref = tc.loadMirrorReference("project_mollweide");
            [x, y] = geo.project(ref.lon, ref.lat, tc.crsMollweide);
            tc.verifyEqual([x y], [ref.x ref.y], 'AbsTol', tc.TolRef.O4);
        end
    end
    methods (Test, TestTags = {'metamorphic'})
        function longitudeShiftEquivariance(tc)
            % Bitwise is NOT expected: the two paths wrap at different
            % points, so eps-level it is - and the comment says why.
            a = geo.project(tc.lonS,      tc.latS, geo.crs("robinson"));
            b = geo.project(tc.lonS + 40, tc.latS, ...
                    geo.crs("robinson", CenterLongitude = 40));
            tc.verifyEqual(b, a, 'AbsTol', 1e-12);
        end
    end
    methods (Test, TestTags = {'speed'})
        function mollweideAgainstEquirectangular(tc)
            tc.assumeSpeedTestsEnabled();
            % N = 1e6; expected ~30 (mirror); budget 90. PREDICTED, not baselined.
            tc.assertRatioBudget( ...
                @() geo.project(tc.lonM, tc.latM, tc.crsMollweide), ...
                @() geo.project(tc.lonM, tc.latM, tc.crsEq), ...
                90, 30, "project mollweide / equirectangular, N=1e6");
        end
    end
end
```

Four things to copy: the tag on the `methods` block rather than on each test; the
oracle cited **by register id**; the tolerance expectation stated as
bitwise-or-not **with its reason**; and the speed budget carrying `N`, expected,
provenance and budget.

---

## Part 12 — Adopting this elsewhere

1. Adopt the **seven categories**; make `reference` real by filling an oracle
   register first.
2. Build the **timing helper before the first budget**; every budget a ratio with
   `N`, expected and provenance.
3. Build **one gate entry point** that judges coverage and errors on red.
4. Split filters three ways; make the condition a **symbol**; guard the
   duplication.
5. Add an exemption list **and** its staleness companion in the same commit.
6. Make the warning inventory a gate with exactly one permitted identifier.
7. Predict the count before each run, reconciled three ways, in writing.
8. Fault-inject every new check before trusting it.
9. Never say "green" without naming the tier.

---

*Created 2026-08-21 (CEST, UTC+02:00). Developed by Matthias Weigelt with the
assistance of Claude Opus 5 (Anthropic).*
