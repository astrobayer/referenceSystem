# Coding Guide — rules that survive the person who wrote them

*HOW-TO only. The binding rules for **this** toolbox are handover sections C.1
through C.11; where this file and the handover disagree, the handover is right
and this file is stale (O36). What is written here is the reasoning, in a form
another project can adopt.*

**Companion documents, and this file does not repeat them.**
`VALIDATION_GUIDE.md` owns tests, tolerances-as-findings, fault injection,
prediction and tiers. `DOCUMENTATION_GUIDE.md` owns help text, generated
artefacts and the single-point-of-truth rule. `WORKFLOW_GUIDE.md` owns the CI
and review loop.

*Generalised from `BEST_PRACTICE.md` Part 2 (R1–R6), handover Part C, `geoMap
v2` §2.7, the MathWorks **MATLAB Coding Guidelines** v1.0, and — for the native
layer — MISRA C, CERT C and the NASA/JPL Power of Ten.*

---

## The six rules

Everything else is instantiation.

### R1. One authority per fact

A value with two definitions has no definition. Where a fact is stated twice,
delete the copy — and where a copy is genuinely unavoidable, something
mechanical must compare the two.

The version string lives in one function; every other file carries its *value*
and the audit checks them. A folder location lives in one accessor; the
downloaders ask it rather than composing it. A layer map lives in one contents
listing; the layering check parses that one.

**Consumers read fields; nothing recovers a fact by parsing a composed value.**
Taking a substring of a version to recover its patch component cost one project
an entire test report. Expose the components separately *and* composed, so no
caller ever has to split. **Cache keys are structs, not concatenated strings
parsed back apart.**

### R2. Metadata travels with the data

A grid carries its source and units. A reader returns provenance —
`verified | unverified` — not just values. A coordinate object carries the model
it assumes.

The test to apply: **if two objects from different sources were combined by
mistake, would anything notice?** If the answer is no, the metadata is missing.

### R3. Measured, never declared

A property is read from the data, never inferred from a name, a filename or a
convention. "Is this longitude vector global?" is measured from the vector.

**A diagnostic message is a claim about the world too.** Derive skip text,
warning text and report lines from what the run actually holds. A message that
names the wrong place costs more than no message.

### R4. Refuse, report, or proceed — never degrade silently

Three outcomes and no fourth. Either the input is rejected with a documented
error, or the work proceeds with a warning naming what was assumed, or it
proceeds silently because nothing was assumed.

**No function returns a numeric status, flag or return code.** A returned status
is useful only if the caller checks it, and in practice nobody does. Where a
vendored library reports through an integer, translate at the boundary: `0` →
silent, "dubious but computed" → warning with the result, "unacceptable" → error
with nothing returned. There is then exactly one representation of "something is
wrong" and no ambiguity about whether a result is usable. This is MISRA C
directive **D.4.7** — *if a function returns error information, that information
shall be tested* — discharged once, at the boundary, instead of at every call.

**A `NaN`-filled result where an error belonged is the worst outcome
available**, because it propagates into whatever the caller does next.

### R5. Do not overrule the user; make it impossible to act unknowingly

The failure this prevents is a silent default that changes the answer. One
function here took a missing Earth-rotation offset as zero: up to 0.9 s, fifteen
arcseconds of rotation, hundreds of metres at the surface, invisible in the
result.

The idiom that fixes it: **make an omission distinguishable from a choice.**
Default the option to an empty value rather than to the value you would have
assumed, so the function can tell "the caller said nothing" from "the caller
named the default", and warn only on the first. An explicit zero is silent; an
absent argument warns once.

**A validated default changes only the allowed way**: measured, then decided,
then frozen — with the old behaviour left reachable and every acceptance
criterion rebaselined in the same change.

### R6. A tolerance is a claim about which error dominates

Every tolerance carries a comment saying where it came from and which physical
term it bounds. A tolerance with no derivation is a number chosen to make
today's run pass.

**A tolerance justified by the magnitude of an input is usually circular.**
Bounding a rotation residual by "the size of the Earth-orientation correction"
proves only that the correction was applied at all.

For what to do when a tolerance fails, see `VALIDATION_GUIDE.md` Part 9.

---

## Part 1 — Adopting the MathWorks MATLAB Coding Guidelines

<https://github.com/mathworks/MATLAB-Coding-Guidelines> (v1.0, for R2025a and
later). Adopt it as the base layer; this guide is the project-specific overlay.

**The structure is worth understanding before the content.** The document
separates **Rules** — which must be followed and which the MATLAB Code Analyzer
detects — from **Best Practices**, which are recommendations, some of them
optionally detectable by enabling a check.

**The reason to adopt it is `codeAnalyzerConfiguration.json`.** The guidelines
ship a configuration file that turns the Rules into Code Analyzer checks, which
means the base layer is **machine-enforced rather than remembered**. That is
this project's own "prefer a mechanism to a reminder" applied to style, and it
subsumes several hand-written checks in `auditPackage.py`. Put it in the
repository root, and run the Code Analyzer in CI:

```matlab
issues = codeIssues(projectRoot);          % honours codeAnalyzerConfiguration.json
assert(isempty(issues.Issues), "Code Analyzer reported %d issue(s).", ...
    height(issues.Issues));
```

There is also a rule file for AI coding assistants at
<https://github.com/matlab/rules/blob/main/matlab-coding-standards.md>, derived
from the same document — worth pointing a session at, so generated code starts
compliant rather than being corrected.

### Where this project deviates, and why

A deviation is a decision, recorded with its reason, not a silent local habit.

| Guideline | Their rule | Here | Why |
|---|---|---|---|
| Line length | ≤ 120 characters | **≤ 100** | The narrower limit is what makes the two-line provenance footer necessary rather than optional, and it keeps side-by-side diffs readable on a laptop. Tighter than the base layer is always allowed. |
| Persistent variables | Best Practice: *minimise* | **Used, five times, each justified in the file** | Every use caches a compile-time constant or a table that cannot change during a session. The guideline's concern is program logic that becomes hard to follow; a memoised constant is not that. Each site says in a comment why the value cannot change mid-run. |
| Abbreviations | Best Practice: avoid; whole words | **Closed list, written down** | Agreed in spirit. The list makes it enforceable: anything not on it is spelled out. |
| Argument validation | Best Practice, for user-facing interfaces | **Rule, for every public function** | Promoted from Best Practice to Rule here, because `contract` tests assert the documented identifier and there must be one to assert. |

Everything else — 4-space indent, no tabs, lowerCamelCase functions, `end` on
every function, no `eval`/`assignin`/`evalin`, no growing arrays in loops,
string arrays rather than cell arrays of char, spacing rules — is adopted as
written and needs no local restatement.

---

## Part 2 — Interfaces

**One `arguments` block per public function.** No parser objects, no `nargin`
chains, no positional-or-name ambiguity.

**Name/value options resolve case-insensitively with partial matching OFF.**
Partial matching turns a typo into a different option.

**Validation runs before the body**, which is why a contract test is cheap: a
rejected call is refutable in microseconds however expensive a successful one
is.

**Know what the block costs.** Measured here: argument validation is the
dominant per-call overhead on both platforms — roughly 75 bare calls' worth per
validated call, ~58 validated calls per composite operation. That is not an
argument against validation; it is an argument for knowing where the hot path is
before optimising, and for **not evaluating an expensive default expression on
every call** — a default that calls another function is paid on every
invocation, whether or not the argument was supplied.

**Error identifiers are `<toolbox>:<functionName>:<reason>`**, camelCase reason,
no spaces. **The documented identifier must equal the raised one, enforced
statically** — not only by tests.

**Identifiers are names, and names have no deprecated twins.** A renamed
function has one name; the old one is deleted and the rename declared breaking.

---

## Part 3 — Structure

**Layers, and calls go downward only.** Declare the layer of every public
function in one place and check the rule mechanically. A layering rule nothing
checks is a diagram.

**Local functions at the bottom.** No nested functions unless a shared workspace
is genuinely required — a nested function that needs two variables should have
taken two arguments.

**No function over ~400 lines without a written justification in the record.**

**Qualify sibling calls inside a namespace.** An unqualified name resolves
against the path, not the package, so an unqualified sibling call is a latent
collision with whatever a user has installed.

**Compiled artefacts are package-private**, re-exported by a public wrapper
where callers legitimately need them.

---

## Part 4 — Numerical work

**Vectorise, then assert that the vectorised path equals the loop** — bitwise,
unless you can say why not. **State whether an equality is bitwise or eps-level,
and why.**

**Bit-identical across thread counts is a requirement, not an aspiration.** A
reduction whose order depends on worker count is a defect that appears only
under load.

**A finite difference needs a convergence test, not a comparison to another
finite difference.**

**Porting from another language ports the literal types too.** Two of five
inherited Fortran ports here carried double-precision C literals where the
Fortran `DATA` had no exponent suffix and therefore stored single precision — a
2e-8 relative error that passed review twice. This is MISRA C directive **D.4.6**
in spirit: use types that state size and signedness rather than trusting the
default. **Difference the port against the compiled original**, not against its
own header example.

**A data-derived constant is written with the span of the data it came from**,
and re-derived when the span grows.

---

## Part 5 — The native layer (C and MEX)

### Which standard, and how much of it

There is no MathWorks C equivalent of the MATLAB guidelines. Three authorities
are worth drawing on, and adopting any of them wholesale is disproportionate for
a scientific core:

| Standard | What it is | How much to take |
|---|---|---|
| **MISRA C:2012 / :2023** | The authoritative C subset for critical systems: 143 rules, 16 directives | Take the **directives**, which are about process and typing, not the full rule set. Full compliance is an audited process for safety-critical work and is not what a numerical library needs. |
| **CERT C** (SEI) | Security-oriented rules, freely readable, mapped to MISRA by Addendum 3 | Take the memory and integer rules. Free, and the rationale is written out. |
| **NASA/JPL Power of Ten** | Holzmann's ten rules for safety-critical code — one page | **The best fit for a small numerical core.** Bounded loops, no dynamic allocation after initialisation, functions on one page, check every return value, minimal scope. |

**The proportionate subset**, and the reason for each:

- **Fixed-width types with stated signedness** (`int32_t`, `size_t`) rather than
  bare `int`/`long` at any interface. MISRA D.4.6. This is the rule that would
  have caught the Fortran literal defect one layer earlier.
- **Every allocation freed on every path, including error paths.** Prefer a
  single allocation at entry and a single free at exit over allocation inside
  branches.
- **Check every return value** that carries error information — MISRA D.4.7 —
  and translate it at the MATLAB boundary per R4.
- **No implicit conversions that lose precision or signedness.** Compile with
  `-Wall -Wextra -Wconversion` and treat the output as findings.
- **Bounded loops.** A loop whose bound is not statically apparent gets a
  comment saying what bounds it.
- **One function, one page**, or a comment explaining why not.

### MEX-specific rules

- **One gateway function**, dispatching on a command string. Validate argument
  counts per command and type-check every numeric input (`mxIsDouble &&
  !mxIsComplex`) rather than trusting the caller.
- **No `printf`.** Errors through `mexErrMsgIdAndTxt` with the project's
  identifier scheme, so a MEX error is indistinguishable from a MATLAB one to
  the caller.
- **Never make memory persistent.** `mexMakeMemoryPersistent` moves ownership to
  a lifetime nothing in the project models.
- **The numerical core must build and its tests run with a plain compiler, with
  no host headers in the picture.** This is the single most valuable structural
  rule in a licensed-toolchain project: it makes the arithmetic verifiable at
  zero licence cost, on every push, and it is the only check of the core that
  does not depend on the host being installed. Keep it true by running it in CI,
  or it stops being true within a few revisions.
- **Test the gateway's dispatch logic separately from the host.** A stub
  `mex.h` lets the command parsing, argument counting and error paths be tested
  under plain `gcc` — the part most likely to be wrong and the part hardest to
  reach from MATLAB.

### Vendored sources

**Vendored third-party sources stay unmodified**, in their own directory, with
their own licence file. If a change is unavoidable it is a documented patch
applied on top, not an edit in place — otherwise the next upstream release
cannot be taken.

**A vendored table is an authority, and the build reports its coverage** as a
return value, not a print.

---

## Part 6 — Licence scoping

A project licence with vendored sources under different terms is not a
formality, and the failure mode is the familiar one: a `LICENSE` file that
states a term the tree does not satisfy is a second authority disagreeing with
the first.

**Four things must be written, not assumed:**

1. **The project's own licence**, chosen consciously. Until one exists, "public,
   all rights reserved" applies — people may look, not reuse.
2. **An explicit carve-out** naming each vendored directory and the terms it is
   under. "Except as noted below" with nothing below is worse than silence.
3. **A derived-work statement** where the upstream licence demands one. Some
   scientific libraries require derived works to be renamed, to state that they
   are derived, and to not imply endorsement — three separate obligations, each
   needing its own sentence.
4. **A third-party notices file** listing every vendored component, its version,
   its origin and its terms.

**Make it mechanical.** The audit here checks that the licence exists, that its
holder is derived from the same authority as the code's authorship, that the
scope carve-outs are stated, and that every vendored directory is named in the
notices file. Those checks cost nothing and they are the only thing standing
between a correct licence and a correct-looking one.

---

## Part 7 — Diagnostics and state

**No printing from library code.** Every diagnostic goes through one logging
function with one verbosity control. Exactly one function in the project is
permitted to print, and it is the installer's summary.

**A warning fires once per call, not once per element.** Assert that with a
counter over a large N.

**Persistent and cached state is stored last.** A failure part way through a
build then leaves nothing cached, rather than serving a half-built value on
every later call.

**Cache a fact that cannot change during a run; do not cache one that can** —
and say which it is in the comment, because the next reader cannot tell from the
code.

**Reset global state on error.** A function that changes warning state, the
path, or the working directory restores it through a cleanup object, on every
exit path.

**A guard is not a fix.** Where a defect can be removed, remove it. A guard that
hides it is worse than the failure it replaces, because it looks like progress.

---

## Part 8 — Naming

Two tiers, governed differently.

**Tier 1, normative.** Domain terms with an external standard behind them are
used verbatim, and deviation is an error, not a preference. In a geodetic
toolbox: frame and time-scale names, Earth-orientation quantities, ellipsoid
parameters, coordinate symbols. A reader from the field recognises them without
translation; a reader from outside can look them up.

**Tier 2, the project's own grammar.** Not a standard — a deliberate, written
convention applied without exception:

| Grammar | Job | Shape |
|---|---|---|
| `sourceToTarget` | One fixed, enumerable conversion | `cartesianToGeodetic`, `mjdToEpoch` |
| `verbNoun` | An action on a thing | `applyRotation`, `readEphemeris` |
| `nounQualifier` | A thing, retrieved or described | `iersConstants`, `leapSecondTable` |

**Abbreviations are a closed list.** An abbreviation invented once becomes a
second name for something that already had one.

**A prefix is the standard substitute for a namespace** in languages that lack
one. Say in the record why the native layer's convention differs from the
host's.

---

## Part 9 — A worked example

Not a hypothetical. This is R1 applied to a real defect, in the order the work
actually happened.

**The symptom.** A user set the toolbox's data folder to an external drive, ran
the suite, and seven tests reported as unexpected filters — the kernels were
present, and the tests said they were missing.

**The finding.** The location was defined in two private helpers, one in each
downloader, each composing `<root>/data` from its own file path. Neither could
be moved, and setting one surprised the other.

**The first fix, and why it was incomplete.** A public accessor was written and
both helpers were pointed at it:

```matlab
function cacheDir = localDefaultCache()
%LOCALDEFAULTCACHE The toolbox data folder, from its one authority.
%
%   D119: this function used to compose data/ from its own mfilename, and so
%   did its twin in the sibling downloader. Two definitions of one location
%   cannot be moved together, and a caller who set one was surprised by the
%   other. Both now ask referenceSystem.dataFolder.

    cacheDir = referenceSystem.dataFolder();
end
```

That deleted two copies. **The sweep that found those two was a search for the
literal text**, and the obligation in force says a blast-radius sweep enumerates
call sites **by data flow, not by literal text**. Seven more consumers existed —
six test helpers and, worse, the installer's own default branch, which would
have fetched 700 MB back into the toolbox tree for a user who had just moved
their data.

**Three things this illustrates.**

*Producers and consumers both count.* The sweep looked at the two functions that
*wrote* the location and missed the seven that *read* it.

*The instrument that found it was not a test written for it.* The conditional
skip machinery reported "capability present, premise not built" — which is what
made a data-location defect visible as seven test results rather than as a
support question a year later.

*One copy remains, deliberately, and is recorded as such.* The installer's
no-preference branch still composes the default itself, because it must **warn**
on an absent shipped folder while the accessor **creates** on demand. Two
branches needing different behaviour on absence is a real reason for a second
statement — and the reason is written down, so the next reader does not delete
it and reintroduce the bug.

---

## Part 10 — Things this project learned the hard way

**Path separators are a silent failure mode.** A watch list containing
forward-slash paths matched nothing on Windows, and every affected entry — a MEX
gateway among them — was silently absent from every profile taken there. Build
path-qualified strings programmatically; never write them as literals with a
separator in them.

**A rename pass in one case form is not a rename pass.** A lowercase-only
migration left the old name in every uppercase header and in one camel-case
hook. Prove a mutator on a scratch copy and read the applied diff before
pointing it at the tree. **A one-shot mutator is not shipped.**

**An empty `0x0` is not an empty `0x1`.** A `(:,1)` size constraint rejects the
first. When the default of an option is "nothing", pick the shape the validator
accepts and say why.

**An instrument's silence is evidence only about what it inspects.** The most
expensive lesson in the project. Before concluding a file is compliant, name
which instrument establishes that, and read what it actually looks at. Two
checks with overlapping names checked different lists here, twice, three
revisions apart.

---

## Part 11 — Adopting this elsewhere

1. Take the **MathWorks guidelines** as the base layer and put
   `codeAnalyzerConfiguration.json` in CI. Record every deviation with its
   reason.
2. Write **R1–R6** where they will be read, and make R1 mechanical: one check
   per fact that has more than one home.
3. Fix the **identifier grammar**; check documented-equals-raised statically.
4. Declare **layers**; check the downward rule by parsing.
5. For a native core, take the **Power of Ten** plus MISRA directives **D.4.6**
   and **D.4.7**, and make the core **buildable without the licensed toolchain**.
6. Write the **licence carve-outs and notices**, and check them mechanically.
7. Write the **abbreviation list** and **naming grammar** once, early.
8. Give every tolerance a **derivation comment**.

---

*Created 2026-08-21 (CEST, UTC+02:00). Developed by Matthias Weigelt with the
assistance of Claude Opus 5 (Anthropic).*
