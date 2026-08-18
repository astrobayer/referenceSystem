# Best practice — lessons from `referenceSystem`

**What this is.** `referenceSystem` was built over roughly 180 recorded revisions of a
handover document, by a domain expert working with a language model. This file extracts
what that cost taught, so the next project can buy the lessons instead of the defects.

**How to read it.** Every rule below is followed by the defect that produced it. The
defects are the point. A rule without its evidence becomes a style preference and gets
argued with; a rule with a number attached to it does not.

**Scope.** Written for numerical and scientific software where correctness is not
self-evident from the output — geodesy, orbit determination, anything where a wrong
answer is smooth, plausible and the right shape.

---

## Part 1 — The five failure modes that produced almost everything

Of the defects found in this project, nearly all fall into five classes. They recur
because each one is invisible to the check that would normally catch it.

### F1. The plausible wrong answer

A wrong Euler sense still produces an orthogonal, unit-determinant matrix that
round-trips through its own inverse. Pole offsets referred to the wrong
precession-nutation model produce a rotation that is smooth, continuous and wrong by
4.2 mm. A column-major flatten of a character matrix produces 43 077 "lines" that are
each one character long, and every downstream regex simply fails to match.

> **No self-consistency check can catch a consistently wrong program.** Validate against
> something that was not built here: a published worked example, a second toolkit, real
> instrument data, a physical invariant the code does not use.

*Evidence:* the v1 CIP model defect (4.2 mm, invisible); `readEphemeris`'s D15 pairing
check, inert from the day it was written until four runs later.

### F2. The claim recalled instead of read

Seven of ten consecutive failures at one point in this project were a name or a value
recalled rather than read from source: a gateway signature that took fourteen arguments
and not three; a function that did not exist; a `downloadEop` series name that was not
one of the four accepted; an IERS chapter number that contains no spatial transformation
at all; a kernel filename in the wrong directory.

> **Anything not exercised by a currently-green test is a guess until the source is
> open.** This includes the standard library. It includes your own API from three
> revisions ago. It includes documents you are certain of.

The refined form, which is the operational one:

> **An `arguments` block without a `mustBeMember` does not define the accepted values.
> Read the body.**

*Evidence:* two of three invented gateway signatures were wrong; the third was right,
"which is worse than useless as evidence — guessing correctly twice is what makes the
third guess feel safe."

### F3. The instrument that lies

Three separate ad-hoc scripts, each written in the same session as the change it was
checking, produced confidently wrong answers: a block-depth checker missing its
increment, a slice that swallowed a whole method, a tag regex that omitted one category.
In every case the fault-injection-tested auditor disagreed and was right.

> **No count, structure or coverage claim from an instrument written in the same session
> as the change it checks.** Either use one that has been shown to fail on a known
> defect, or mark the claim provisional in writing.

*Corollary, learned late:* an "independent" check that was copied from the code under
test is not independent. The comment-area reader in the test was copied out of the
library **including its defect**, so the two agreed perfectly about nothing, and the
assertion passed while the number beside it was absurd.

### F4. The preserving mechanism that destroys

Three times, a mechanism whose purpose was to preserve information destroyed it:

| Where | What was lost |
|---|---|
| A downloader that raised after fetching | The manifest describing four files already on disk |
| `fprintf` refusing a `<missing>` array element | An entire report of 577 test results |
| An exception anywhere before the report was written | Three revisions of runs, silently |

Each was repaired **at the site where it was noticed**, and the same shape was left
standing one level up.

> **When a mechanism that preserves is found destroying, immediately ask where else the
> same producer/artefact relationship exists.** Fixing the instance is not fixing the
> class.

### F5. The layered defect

Open item B4 — validating one code path against an external authority — was declared
closed three times and was not. The fixture was assumed to lack a body it had always
contained; then a name map had no entry, so the path would have stayed dead even with
the data present; then the helper opened one hard-coded filename, so a file the user had
already downloaded was invisible; then a safety refusal excluded it from the set.

**Each cause was visible only after the previous one was removed.**

> **Do not write "closed" until the path has run end to end and produced a number.** A
> repair that removes one of several blockers looks exactly like a repair that removes
> the last one.

---

## Part 2 — Rules for the code

### R1. One authority per fact

The version lives in one file. The layer manifest lives in one file. The leap-second
table lives behind one function. Consumers **read the field they want** — they never
recover a fact by taking a substring of a composed value.

*Evidence:* a report title built as `extractBefore(helpTag, " | ")` worked until the tag
was split into two lines; then it returned `<missing>` and destroyed the whole report.
A consumer that re-splits a composed authority has made itself a second authority, and
the two will agree until the day nobody is looking.

*Mechanical form:* a mirror instrument (a linter in another language, a build script)
must **derive** what the original derives. Never hold a copy. A mirror that does not
mirror is worse than none, because it is cheap and is therefore believed.

### R2. Metadata travels with the data

The model reference, the convention, the ephemeris generation, the units, the source of
the leap-second table — all travel in a `meta` field beside the values. Anything assumed
is eventually assumed wrongly.

*Test for this:* if two objects from different sources were combined by mistake, would
anything notice? If not, the metadata is missing.

### R3. Measured, never declared

Where the program can ask, it asks. Kernel pairing is read from the file's own comment
area, not inferred from the filename. A build reports what the compiler did, not what it
was told to do. A channel count is read from the file's header line, not from its version
number.

*Extended form, learned late:* **a diagnostic message is a claim about the world too.**
A skip reason reading "the kernel is not in the set" went on printing for two revisions
after the kernel appeared. Derive the message from what the run actually holds.

### R4. Refuse, report, or proceed — never degrade silently

Three legitimate responses to an anomaly; "quietly return something plausible" is not
one of them. A guard that cannot positively determine a fault **proceeds** — a false
negative blocks all work, a false positive merely fails to warn.

### R5. Do not overrule the user; make it impossible to act unknowingly

This one was learned by getting it wrong. A refusal to load two ephemeris generations
together was justified as "mixing them is not harmless and nothing downstream would
report it". The second half stopped being true — a metadata field, a warning channel and
a report section had all been added since — and the refusal then merely prevented a
legitimate comparison.

> **A library that will not let you do the thing you came to do is not protecting you.**
> Report the contradiction, record it in the returned metadata, and leave the judgement
> with the caller.

*And the general lesson:* **a decision must be re-read when the conditions it was taken
under change.** Nothing prompts that automatically. Date the reasoning, not just the
decision.

### R6. A tolerance is a claim about which error dominates

When a precision test fails, decompose the residual into its physical contributors
**before** touching the bound. Loosening a tolerance to make a test pass usually destroys
exactly the discrimination the test existed for.

*Corollary:* one bound cannot span two error regimes. A planetary-ephemeris tolerance
inherited by an asteroid reported a working comparison as a failure at 8 km — a figure
that was entirely correct and meant something else.

*Corollary:* a relative tolerance is undefined against an expected zero. Axis-aligned
test vectors introduce them by the pair.

*Corollary:* bit-identity may be asserted only where the arithmetic is elementwise. A
batch and a per-row result that both pass through a matrix product need not agree bit for
bit; BLAS may block them differently.

---

## Part 3 — Rules for the tests

### T1. Four categories, per function, always

`contract` (shapes, argument rejection, error identifiers) · `reference` (against an
outside authority) · `precision` (the numerical claim) · `vectorization` (an arc equals
the same epochs one at a time). Add `speed`, `diagnostics` and `provenance` as
cross-cutting tags.

Count them mechanically. An audit that asked this question for the first time found 46 of
81 functions short of at least one category **after nine green runs**.

### T2. An exemption is a claim that the test is impossible, not inconvenient

Keep the list, require a reason per entry, and have something object when an exemption
becomes false. Then note what that does *not* catch: an exemption that was **wrong when
written**.

*Evidence:* two entries reasoned from an expensive *success* to an impossible test —
"calling it recompiles 255 sources", "every code path reaches the network" — and never
asked what a **rejected** call costs. An `arguments` block runs before the body, so both
were refutable in microseconds.

> Mechanical rule that followed: **`contract` may not be exempted for a function that has
> an `arguments` block.**

### T3. A passing test must leave the number it checked

`verifyLessThan` that passes leaves no trace, so the report is silent about exactly the
measurements that went well. Three separate figures were repaired by hand before a
mechanism was built: a helper that **qualifies the bound and returns the report record**,
so an assertion cannot exist without something to log.

*And:* a new record type is not a diagnostic until the report has a **section** for it.
Two records were logged into a section that did not exist, in revisions that cited the
"diagnostics must reach the report" rule as their justification.

### T4. One measurement at one setting is not a measurement

A single disagreement of 1.66e-7 was recorded as "55× above the floor" and treated as a
probable defect. Sweeping the perturbation over four decades settled it in one run: the
error falls as 1/δ, dropping 306-fold by the largest step, so it is the *oracle's* own
roundoff floor and the analytic derivative is sound. The original floor estimate was also
wrong, by sevenfold, in the other direction.

> **A floor moves with the step; a model error does not.** When a number looks wrong,
> sweep the thing it should depend on before diagnosing it.

*Related:* a one-way comparison at one offset cannot measure a truncation, because it
cannot see a term that does not vary with the swept quantity. A UTM error was recorded as
0.06 mm; the dominant term was 0.7 mm and independent of the offset being swept.

### T5. Assert the claim, not a proxy

If the prompt says "the marginal cost is small", assert a **ratio against the thing it is
marginal to**, timed back to back on the same machine. An absolute figure with no
baseline cannot detect the change it was written for — a benchmark added for a speed
change measured only the state *after* the change and shipped a 1.30× regression.

*And:* an absolute sub-millisecond timing measures the host, not the code. One such row
swung 6.8× across three runs on a function nobody had touched.

### T6. Write tests that can fail informatively

The single most useful test in this project was one whose assertion was a **hypothesis**:
it stated both possible outcomes in its diagnostic and failed loudly. That failure is what
got a console log pasted, which is what found an unrelated defect that had gone unnoticed
for three revisions.

*And its opposite:* a test that only asserts a refusal passes on a function that refuses
everything. Always pair it with the case that must succeed.

### T7. Test the default path of every optional argument

A format-guard test passed cleanly while nine other tests failed on that very format,
because it always supplied all the arguments and the defect lived only on the
default path.

---

## Part 4 — Rules for the process

### P1. A session is not complete until its report has been read

Code that has not been executed is a draft, however carefully reviewed. This project's
foundation session was reviewed through nine revisions and still contained four wrong
statements about the language itself, one test that had never checked what it claimed, and
one false positive — none reachable by reading, all reachable by one run.

Mark such a session ◐ on the status board, never ☑.

### P2. Predict the test count before every run

Then reconcile it afterwards, three ways: tag sums, per-class sums, and pass-plus-skip.
A prediction that misses is the cheapest available signal that the change was not the
change you thought you made. One miss in this project was caused by counting three added
*assertions* as three added *methods* — a distinction that matters and is invisible in a
green run.

### P3. Freeze the scope before implementing

Design grows indefinitely under review. Fix the prompt list, deliver against it, and put
everything new in a backlog with explicit re-entry criteria.

### P4. Record decisions with their reasoning and their date

A numbered decision log — what was chosen, what was rejected, and the number that decided
it. This is what makes a decision re-readable when conditions change (R5), and what
prevents the same question being re-litigated every session.

Do the same for **obligations**: standing rules with an owner and a closing condition,
kept in one place a later reader will actually find.

### P5. Prefer a mechanism to a reminder

Every rule in this document that survived was turned into something that fires: a test,
an audit check, a formatter that cannot be used without producing a record. Every rule
that stayed a note in a document was broken again — usually by the person who wrote it,
usually within three revisions.

### P6. Do not mix a substantial change with unrelated repairs

A stretch of this project's history reads: real work, fix what the real work broke, fix
the fix, fix the instrument added to check the fix. The loop converges, but it converges
on tooling rather than on the subject. Give a substantial change its own session.

### P7. Version the artefact against the document

The patch component of the semantic version **is** the revision number of the handover
document, and the two are written in the same edit. Any copy of the sources then names the
log entry that explains it — which dates cannot do, since two revisions on one day are
ordinary.

---

## Part 5 — A template for prompting

What follows is the shape of instruction that worked. It is written as an example, not as
a form to fill in.

### 5.1 The standing instruction (set once, applies to every session)

> Follow the handover document exactly: naming conventions, `arguments` blocks (never
> `inputParser`), error identifiers `<package>:<function>:<reason>`, the mandatory help
> template including the ACCURACY block, the language's coding standard, no printing from
> library code, full vectorisation, no aliases. Deliver the function file(s), the
> corresponding test methods, and a short wrap-up of what changed. **State any assumption
> you had to make.** Work through the numbered prompts in the order given, and satisfy the
> seam contract at the end of the session block before declaring it complete.

Why each clause earns its place:

- **"the handover document exactly"** — one authority, so a rule is never restated in a
  prompt where it can drift.
- **"and the corresponding test methods"** — otherwise tests arrive a session late and
  the code is never exercised.
- **"state any assumption"** — the single highest-yield clause. It converts silent
  guesses into visible ones.
- **"satisfy the seam contract"** — a written definition of done, per session, decided
  before the work rather than after it.

### 5.2 The per-session prompt

State, in this order:

1. **What is being built**, in one sentence.
2. **What it depends on** — which earlier prompts must be green first.
3. **The deliverables**, numbered, each one testable.
4. **The accuracy requirement**, as a number, with the reason that number and not another.
5. **The oracle** — what will this be checked against that was not built here?
6. **Re-entry criteria** if it is deferred.

If item 5 cannot be answered, the prompt is not ready. That question caught more design
problems in this project than any other.

### 5.3 What to ask for in the wrap-up

- What changed, and what it was measured against
- **The predicted test count**
- Any assumption made
- Anything that was *not* done, and why

### 5.4 Anti-patterns in prompting

| Anti-pattern | What happens |
|---|---|
| "Make it robust" | Unfalsifiable. Ask for a named failure mode and the behaviour under it. |
| "Fix the failing test" | Invites the tolerance to be loosened. Ask what the residual is made of. |
| "It should be about X" | A number that is *about* right is asserted, then inherited for fifty revisions. Ask for measured or explicitly predicted. |
| Several unrelated items in one prompt | Produces the repair loop in P6. |
| "Also update the docs" as an afterthought | Documentation written after the fact describes what was intended. Ask for it in the same prompt as the code. |

### 5.5 What the human contributed that mattered most

Recorded because it is not obvious, and because it is the part no amount of care on the
model's side replaces:

- **Running the code.** Every session that was not executed contained defects that no
  review found.
- **Reading the report rather than the summary.** The stale-report defect, the
  unreadable-file defect and the wrong kernel-set message were all found by a human
  reading output and saying "that does not match what I see".
- **Supplying primary sources.** A release paper turned a plausible claim into a
  quantified one — and showed that the *reason* given for the claim had been wrong even
  though the claim was right.
- **Rejecting a design.** The decision to warn rather than refuse on mixed ephemeris
  generations came from the user, against a rule the model had been defending for
  eighty revisions.
- **Noticing repetition.** "I feel we are going in circles" was correct, and produced a
  measurement showing that roughly a third of recent revisions were findings and the rest
  were repairs to instruments added the revision before.

---

## Part 6 — The one-page checklist

**Before writing code**

- [ ] Is there an oracle outside this project? If not, stop and find one.
- [ ] Is the scope frozen and written down?
- [ ] Which existing decision does this change? Is its reasoning still true?

**While writing**

- [ ] One authority per fact; consumers read fields, never parse composites.
- [ ] Metadata travels with the values.
- [ ] Every approximation named and quantified where it is made.
- [ ] Nothing degrades silently; nothing is refused that the caller may legitimately want.

**Before claiming it works**

- [ ] Four test categories present, counted mechanically.
- [ ] Every measured number appears in the report, pass or fail.
- [ ] Every claim of the form "X is small" asserted as a ratio.
- [ ] Predicted test count stated.
- [ ] Any instrument written this session distrusted, or fault-injected.

**After the run**

- [ ] Report read in full, not just the summary line.
- [ ] Count reconciled three ways.
- [ ] Each failure diagnosed before any bound is touched.
- [ ] Anything closed has produced a number, end to end.

---

*Extracted from `HANDOVER_referenceSystem.md`, revisions 1.0–1.180. The handover remains
the single point of truth; this file is a distillation and carries no authority the
handover does not.*

---
*referenceSystem v2.1*
*Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)*
