# Documentation Guide — one authority per fact, and instruments that watch it

*HOW-TO only. The binding rules for **this** toolbox are handover sections C.3,
C.7, C.11 and Part E; where this file and the handover disagree, the handover is
right and this file is stale (O36). What is written here is the reasoning, plus
the templates, in a form another project can adopt.*

**This file OWNS: the help-text template, generated artefacts, the sync gate,
the records template and the single-point-of-truth rule.**
`CODING_GUIDE.md` owns the code rules, `VALIDATION_GUIDE.md` tests and fault
injection, `WORKFLOW_GUIDE.md` the loop.

*Generalised from `referenceSystem` (§C.3, Part E), `geoMap v2` (§2.8) and
`BEST_PRACTICE.md` Part 2, and from the documentation defects found between
revs. 1.174 and 1.207 — which were all the same defect.*

---

## The one idea

**A fact stated in two places is a fact that will disagree.** Every rule below is
a corollary. Where a second statement is unavoidable — a generated page, a
mirrored constant, a symbol named in both a test and a catalogue — something
mechanical must compare the two, because the copy nobody reads is the one that
rots, and a rotted copy is indistinguishable from a fresh one until someone
checks.

This is not a style preference. It produced, in these projects: a shipped
function reference missing twenty functions; a manual stamped three revisions
behind its sources; a help block claiming two sibling functions used the same
step size when they used different ones; a docstring quoting a version literal
from twenty-one revisions earlier; a header naming two closed items as open for
three revisions running; and a data model that parsed argument descriptions for
years while the renderer never read the field — every audit green, because there
was no text to disagree with.

**Documentation is a deliverable and is verified like one. Write it in the same
prompt as the code.**

---

## Part 1 — The help-text template

The help block is the primary document. Not the README, not the website, not the
PDF. It is what a developer reads at the moment of use, so it is the copy that
must be right, and every other document should be **derived from it** rather than
written beside it.

**Make the template rigid enough to parse.** A mandatory verbatim structure is
not bureaucracy — it is what lets a generator consume the help text and emit the
reference page, which is what makes that page derivable rather than maintained.

```matlab
function [out1, out2] = name(in1, in2, options)
%NAME  One-sentence purpose line, ending in a period.
%
%   SYNTAX
%     OUT1 = NAME(IN1, IN2)
%     [OUT1, OUT2] = NAME(..., Name, Value)
%
%   DESCRIPTION
%     Motivated: why this exists and why it works this way, with the
%     measured numbers backing any claim it makes. NOT a restatement of
%     the syntax.
%
%   INPUTS
%     in1   (1,:) double   Units. Description.
%     in2   (1,1) struct   Description (see NAME2).
%
%   OUTPUTS
%     out1  (M,N) double   Units. Description.
%     out2  (1,1) struct   Fields: Alpha (1,1) double, ...; every field
%                          named, typed, dimensioned, described.
%
%   OPTIONS
%     Option1   (1,1) double   [default]   Description.
%
%   ACCURACY
%     What this function's numerical claim is, what it was measured
%     against, and the tolerance achieved. Name the oracle by its
%     register id. Where a measurement could only be taken in the target
%     language, say so and give the procedure for re-deriving it.
%
%   ERRORS
%     Grouped by CAUSE, not listed flat:
%     Input geometry:
%       name:SizeMismatch      - when ...
%       name:NonMonotonic      - when ...
%     Domain:
%       name:OutOfDomain       - when ...
%
%   EXAMPLE
%     ...runnable lines, which the doc build extracts and lints...
%
%   LIMITATIONS
%     Model assumptions, known quirks, what this function cannot do.
%
%   See also NAME2, NAME3.
%
%   ---------------------------------------------------------------------
%   <toolbox> v<major.minor> | <dd-Mmm-yyyy HH:MM local> | <model name>
%   Reviewed by a human before release. Updates append below this line.
```

**`ACCURACY` is not optional, and "not applicable" is a real answer.** A function
that computes nothing numerical says so and why. What is forbidden is silence,
because silence is indistinguishable from an approximation nobody measured.

**Group error identifiers by cause.** A flat list is a lookup table; a grouped one
tells the reader which of their assumptions is wrong.

**The `ERRORS` block is a contract, enforced statically.** The documented
identifier must equal the raised one, checked by the audit and not only by tests.
Identifiers are names: no identifier may have a deprecated twin.

**The `EXAMPLE` is code, not illustration.** Extract and lint it at build time. An
example that stops running should fail the build, not the reader.

**Units belong in the tables, always.** A size and a type without units is a
column that looks complete and is not.

**The provenance footer is derived, never retyped.** One function owns the version
and authorship strings; every file carries their *values*; a test asserts the
presence of both; and the static audit derives the same two strings from the same
authority rather than holding its own copy. When the audit held a copy, a version
bump made the two instruments disagree — the cheap one reporting 82 failures
while the expensive one passed.

**The audit reads the whole block, not the first line.** Two gates in one project
shared a blind spot for different reasons: one because its pattern disallowed a
dot, one because it read only the first line.

---

## Part 2 — The documentation sync gate

**Every change ships its documentation in the same change — all surfaces, every
time.** The audit cross-reads the help text, the generated HTML, the guide, the
README, the changelog and the contents listing, and fails on any disagreement.

**It runs on a fresh build, never before one.** A gate that reads yesterday's
build approves yesterday's docs.

**Count completeness in the built artefact, not in the pipeline that feeds it.**
One project parsed input descriptions into its data model for years while the
renderer never read the field, and every audit stayed green because there was no
text to disagree with. Report *arguments documented / arguments rendered*,
counted in the emitted output.

**A generated manual is verified by rasterising it and looking**, never by the
absence of an exception.

---

## Part 3 — Generated artefacts

**Generate anything that restates the help blocks.** A reference page written by
hand beside ~100 help blocks saying the same thing is the two-sources-of-truth
pattern, and it is the copy that rots first, because it is not what developers
read.

**One generator is the authority, and a careful transcription does not replace
it.** During one review a page was rebuilt by a one-off script in another
language, verified line by line — and then **discarded**, precisely so the real
generator remained the only thing that writes that file. A transcription that
survives becomes a second generator with no tests. **A one-shot mutator is not
shipped.**

### The trap that cost the most: a stamp is not the content

Staleness gates almost always compare a **version stamp**. That is cheap and
catches the common case. It does not catch the important one.

At rev. 1.207 the shipped reference page carried a correct footer stamp and help
text from twenty-one revisions earlier. The stamp gate passed on every run. The
staleness was found only because the generator was run for an unrelated reason
and produced a seven-line diff.

1. **Decide staleness by CONTENT first and by the clock second.** A timestamp
   comparison is defeated by an archive, a checkout or a copy: a zip stores naive
   local time, and a fresh checkout gives every file the same mtime.
2. **A stamp gate must not be mistaken for a content gate.** If you have one, say
   in its own message what it does *not* check.
3. **Watch the bodies, not only the index.** Index-level checks — every function
   appears, no ghost entries — catch additions and removals and are blind to a
   help block whose *text* changed.
4. **Bump the version FIRST, then generate.** The generator reads the version at
   build time. Generate before the bump and the artefact carries the old stamp;
   record the bump before generating and the record is ahead of the artefact.
   This ordering is discovered twice by everyone and written down by almost
   nobody. Put it in a script.

### If the generator needs a toolchain you cannot always reach

The generated file is committed by whoever can run it, and everything else waits.
Correcting a stamp by hand is defensible exactly once, under a stated precedent,
and only when nothing but the stamp can have changed — and the next run of the
real generator must overwrite it. Twice in a row means the discipline has become
a habit, and the habit is the defect.

---

## Part 4 — The single point of truth

**One document holds design, decisions, obligations and status.** Everything else
— a README, a guide like this one, a commit message, a pull-request body, a code
comment — may **point** at it and must never **restate** it.

This is easy to violate for good reasons. Here the reasoning for a decision was
once written into a pull-request description and a scratch file, on the argument
that a tidy repository was worth more than a tidy record. That created, in one
act, exactly the second authority every instrument exists to prevent. The
tidiness argument is always available and is never sufficient.

**One authority per fact, and the rest are checked against it.** The version
string lives in one file; the README, the project file, the changelog, the landing
page and the registration XML are **checked against it**, never independently
maintained. Likewise for domains, colour tables, layer stacks, tolerances.

**Consumers read fields; nothing recovers a fact by parsing a composed value.**
Taking a substring of a version to recover its patch cost one project an entire
test report.

**Metadata travels with the data.** The test to apply: *if two objects from
different sources were combined by mistake, would anything notice?*

**Record decisions with their reasoning and their date.** A decision without its
reasoning is a rule that will be broken by whoever next has the same good idea
that was already rejected. When a decision *is* reversed, say so explicitly,
restate what the original got right, and name what new information changed it.
Two decisions here were revisited that way; both were sound when made, and both
had their scope narrowed rather than their reasoning discarded.

**A status surface carries what is true NOW.** History belongs in the revision
log, which is history by definition. A header that accumulates history stops being
readable and starts being copied forward — which is how three consecutive
revisions came to describe two closed items as open, each copying the previous
header rather than reading anything.

**Evidence and status live in different files.** A records file holds evidence and
**never holds status**; the handover holds status and points at the evidence.

---

## Part 5 — The records template

One entry per stage, written at its green gate.

```markdown
## R-00n — Stage <X>, <date>, tier <A|B>

**Confirming run.** Runner invocation, machine tag, wall time, predicted
vs executed point count reconciled three ways, warning inventory.

**Pre-validation findings.** Each with its measurement, and whether it
changed the specification, the code, or nothing.

**Findings from the run.** Each with the log excerpt that showed it.

**Numbers measured this round.** The table that later stages cite.

**Superseded scripts.** Frozen verbatim, as the record of their own round.

**Binding items a later stage could be wrong for not reading.** Short.
This is the section the next session actually reads.
```

Three things make it work. **Superseded scripts are frozen, not rewritten** — a
rewritten script is no longer the record of the round that produced its numbers.
**Findings carry the log excerpt**, not a paraphrase. And the last section is
deliberately short, because it is the only one anybody reads under time pressure.

---

## Part 6 — What to write in prose, and how

**Write the reasoning, not the mechanism.** The code says what it does. The
comment says why this and not the obvious alternative, what was tried, what the
constraint was. A comment restating the line beneath it is a second copy.

**Name the alternative that was rejected.** "Two parallel arrays and not a map:
three entries do not earn a container." A future reader with the same idea stops
there instead of re-deriving it.

**Quantify.** "Slow" is not a finding; "1.34× on validated calls against 1.00× on
bare dispatch" is. Numbers survive re-reading; adjectives do not.

**Date a measurement, and give it the span of the data behind it.** Measurements
go stale in a way definitions do not.

**Say what an instrument does not cover.** The most expensive documentation
defects in these projects were not wrong statements but *complete-looking* ones —
a check whose silence was read as evidence about something it never inspected.

**No printing from library code.** Diagnostics go through one logging function
with one verbosity control, so a caller can turn them off without editing the
library — and so the report has one place to look.

---

## Part 7 — The checks worth building

Cheapest first. None of these needs the expensive toolchain.

| Check | Catches |
|---|---|
| Every file carries both provenance lines | A file added outside the template |
| Both lines derived from one authority | The audit and the suite disagreeing after a bump |
| Every mandatory help section present | A section quietly dropped |
| Documented error identifier equals the raised one | A rename that missed the help block |
| Header version literals equal the sources | A status surface left behind |
| No date in the future | Clock and log disagreeing |
| No closed item named as open | A header copied forward instead of read |
| Generated page indexes exactly the public names | Additions and removals |
| **Generated page bodies match the help blocks** | **Content rot behind a correct stamp** |
| Arguments documented / arguments **rendered** | A field parsed but never emitted |
| Version literal equals the record's revision number | Artefact and explanation drifting apart |
| Every example runs | An example that stopped being true |

The two emphasised rows are the ones these projects did not have and paid for.

**Fault-inject every check before trusting it** — the rule and its reasoning are
in `VALIDATION_GUIDE.md` Part 3. It applies to documentation checks exactly as
to test assertions, and several here caught live defects on their first run
precisely because someone tried to plant a fake one.

---

## Part 8 — Adopting this elsewhere

1. Choose the **primary document** — for most projects the docstring — and make
   its structure rigid enough to parse. Copy the template in Part 1.
2. **Derive** every restatement of it. Where something cannot be derived, give it
   a check that compares it to the source.
3. Name the **single point of truth** for decisions and status, keep evidence in a
   separate records file, and write the pointing-not-restating rule where people
   will hit it.
4. Add the cheap checks from Part 7 to the licence-free CI job.
5. Put **bump-then-generate** in a script, not in a memory.
6. Make the doc build **extract and lint every example**.

---

*Created 2026-08-21 (CEST, UTC+02:00). Developed by Matthias Weigelt with the
assistance of Claude Opus 5 (Anthropic).*
