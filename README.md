# referenceSystem v2.1

Time systems, Earth orientation and coordinate transformations for satellite
geodesy, in MATLAB with a C/MEX floor. Built on the **IERS Conventions (2010)**
and the unmodified **IAU SOFA** library.

It consolidates three earlier toolboxes — `ecef2eci`, `geodesyToolbox` and
`convertTimeSystem` — into one package with a single set of conventions, one
epoch type, one leap-second authority and one set of frame names.

## Install

Distribution is by **zip archive** or **git repository**. There is no packaged
installer and no `.mltbx`.

```matlab
>> cd <wherever you unpacked or cloned it>/referenceSystem
>> setupReferenceSystem
```

That is the whole procedure. `setupReferenceSystem` is the installer: it sets
**and saves** the path, compiles the MEX gateway, builds the function reference
and the help search database, downloads the Earth orientation series and the
SPICE kernels, and prints a summary — **each step only when it is out of date or
absent**. A fresh copy takes a few minutes and about 700 MB, of which 650 MB is
the small-body kernel; afterwards it costs milliseconds, so it is safe in
`startup.m`.

```matlab
>> setupReferenceSystem(Fetch="none")      % offline: download nothing
>> setupReferenceSystem(KernelSet="minimal")  % de440s.bsp alone, ~31 MB
>> setupReferenceSystem(Save=false)        % this session only
>> setupReferenceSystem(Verbose=false)     % no summary
>> setupReferenceSystem(Build="always")    % rebuild everything
>> setupReferenceSystem(Build="never")     % report only, build nothing
>> referenceSystem.runTestSuite            % writes referenceSystem_testReport.txt
```

The defaults install rather than inspect, because the call with no arguments is
what somebody makes once on a fresh clone and what they want out of it is a
toolbox that still works in the next session. A failed download never stops
setup; it is recorded in `status.fetch.failures` and reported.

**Add the parent folder to the path, never `+referenceSystem` itself.** A folder
whose name begins with `+` is a namespace folder and is never on the path — that
is what makes it a namespace. `setupReferenceSystem` removes it if it finds it
there.

A build failure never stops setup: the path is the one thing it must get right,
and a toolbox on the path with no gateway still gives a working namespace,
readable help and an error that names the missing piece. The three build steps
are also callable directly — `referenceSystem.buildMex`,
`referenceSystem.buildDocumentation`, `referenceSystem.runTestSuite`.

One further instrument ships beside the suite and is **not** part of the toolbox
API: `test/profileRotationCall.m`. It profiles a single-epoch
`rotationItrsToGcrs` call, times the time-scale chain against a set of untouched
control functions, and writes a report that it can later read back as its own
baseline. Run it from a folder you can write to, with the `test` folder on the
path:

```matlab
>> before = profileRotationCall('Output', "profileBefore.txt");
>> after  = profileRotationCall('Output', "profileAfter.txt", 'Baseline', before);
```

Absolute times are meaningful only against a baseline recorded on the same host
and MATLAB release; the report records both and marks the comparison unsafe if
either moved. Call counts per rotation are exact and host-independent.

### Working from git

The repository holds **sources only**; every artefact is built locally and is
listed in `.gitignore`. The MEX binary in particular is never committed: it is
platform-specific, so a committed one is wrong for most people who clone, and
wrong *silently* on the platform it was built for once the C sources move on.
Setup compares the newest C source against the binary and rebuilds when the
sources are newer — which works only because the binary is local.

The generated function reference **is** committed, deliberately, so that it can
be read from a web view of the repository without a MATLAB session. Setup
regenerates it when a help block is newer, and a test asserts it has a section
for every function in the package.

For a release archive, `git archive` gives the right contents for free:

```bash
$ git archive --format=zip --prefix=referenceSystem/ -o referenceSystem_v2.1.zip HEAD
```

See `doc/referenceSystem_installation.html` for requirements, the Help browser
files, and removal.

## Quick start

```matlab
eop  = referenceSystem.readEop("eopc04_20.1962-now.txt");
utc  = referenceSystem.daySecondToEpoch([day, secondOfDay], "UTC");
[R, Rdot] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop);
[rGcrs, vGcrs] = referenceSystem.applyRotation(R, Rdot, rItrs, vItrs);
```

`R` is `3x3xN` pages. The inverse is the transpose: use `invertRotation`, or
`applyRotation(..., 'Inverse', true)`. There is no direction option anywhere.

## Layers

| Layer | What it owns | Examples |
|---|---|---|
| **L0** | time scales, epochs, constants | `convertTimeScale`, `mjdToEpoch`, `epochTo`, `leapSecondTable`, `fundamentalArguments` |
| **L1** | Earth orientation data | `readEop`, `interpolateEop`, `subdailyEopCorrection`, `zonalTideEopCorrection` |
| **L2** | ITRS ↔ GCRS | `cipCoordinates`, `earthRotationAngle`, `rotationItrsToGcrs`, `applyRotation` |
| **L3** | terrestrial realizations | `itrfParameters`, `convertItrf`, `applyHelmert7`, `applyMolodensky` |
| **L4** | coordinate representations | `cartesianToGeodetic`, `cartesianToEnu`, `geodeticToUtm`, `geoidUndulation` |
| **L4b** | rotation algebra | `rotationX/Y/Z`, `rotationFromQuaternion`, `eulerSequenceFromRotation` |
| **L5** | orbit, attitude, navigation | `rotationGcrsToRsw`, `interpolateQuaternions`, `integrateAttitude` |
| **L6** | dispatch and infrastructure | `convertCoordinates`, `buildMex`, `buildDocumentation`, `runTestSuite` |

`help referenceSystem` lists every function grouped this way; `lookfor` works
because every help block carries a `KEYWORDS` line.

## Accuracy in one paragraph

For an absolute Earth-fixed ↔ inertial rotation the error is set by the **EOP,
not by this toolbox**: about 1.5–2 mm at the surface for an IERS C04 series.
Every algorithmic term is at least an order smaller. The rotation reproduces the
SOFA cookbook to 2.6e-15 (5e-4 µas); the equinox and CIO routes agree to
4.4e-16 rad continuously; `geodeticToCartesian` matches PROJ 9.5.1 bit for bit;
UTM closes its round trip to 7.4e-4 m; SLERP tracks real GRACE-FO attitude to
4.4e-6 rad at 2 s gaps. Full budget in `doc/referenceSystem_accuracy.html`.

## Documentation

| File | Contents |
|---|---|
| `doc/referenceSystem_installation.html` | zip and git, build artefacts, requirements, the Help browser |
| `doc/referenceSystem_gettingStarted.html` | the namespace, the two data types, workflows |
| `doc/referenceSystem_functionReference.html` | **generated** from the help blocks by `referenceSystem.buildDocumentation` |
| `doc/referenceSystem_accuracy.html` | every approximation, measured, and when it matters |
| `doc/referenceSystem_migration.html` | v1 → v2 names and the four behaviour changes |
| `doc/examples/` | three runnable scripts |
| `HANDOVER_referenceSystem.md` | **single point of truth** for the design, the workflow and the rules |

Never edit the function reference by hand. Edit the help block and build again
— or just run setup, which notices:

```matlab
>> referenceSystem.buildDocumentation
```

## Things that will surprise a v1 user

1. Every call is now `referenceSystem.`-qualified and camelCase, so **every v1
   call site fails immediately** as an undefined function. Deliberately loud.
2. `R` returns `3x3xN` pages instead of `Nx9`; the `reshape` idiom is gone.
3. `ApplyTidalCorrections` **defaults to `true`**, so results differ from v1 by
   about 15 mm unless explicitly disabled.
4. The `status` output is **gone entirely**. SOFA conditions surface as MATLAB
   warnings and errors. `info` is diagnostics, not a status code.
5. The default ellipsoid is **GRS80**, not WGS84.
6. Every epoch from **2029 onward raises a dubious-year warning** on the bundled
   SOFA leap-second table.

## Scope and limitations

- **In scope:** time scales, EOP, ITRS↔GCRS with derivatives, ITRF realizations,
  coordinate representations, rotation algebra, orbit and attitude kinematics.
- **Not in v2.0:** the interpolated (Chebyshev) CIP mode, EOP partial
  derivatives, barycentric frames, planetary ephemerides, planetary body-fixed
  frames. All are specified in Part H of the handover, deferred rather than
  cancelled.
- **Not ever:** force models, orbit determination filters, navigation filters.
  This toolbox supplies frames and kinematics; the dynamics belong elsewhere.
- **No geoid grid is bundled** (licensing and size). `geoidUndulation` documents
  the expected format and errors outside its grid rather than returning NaN.
- **The leap-second table is frozen at 2017-01-01.** Check IERS Bulletin C and
  supply an override before operational use.
- **One test uses the network and the rest do not**, nor a downloaded
  multi-decade EOP file. The exception is
  `downloadKernels_contract_partialFetchWarnsAndReturnsTheManifest`, which
  provokes a failed transfer with a one-second timeout against the real NAIF
  host. On a machine with no route it fails fast and the test does its job; on
  one that answers inside a second the test is FILTERED rather than passed.
  Making it deterministic needs a catalogue seam and is recorded in the
  handover, §H.11.

## Licence

**MIT** — see `LICENSE`. Copyright (c) 2026 Matthias Weigelt.

The MIT grant covers this project's own code and documentation: the
`+referenceSystem/` package, the C sources at the top of `mex/`, the test
suite, the build and audit scripts, and the written documentation. **It does
not cover the third-party software and data distributed with it** — SOFA, the
IERS Conventions routines and the reference fixtures keep their own terms.
Those are listed with their licences, and with the statements SOFA and the
IERS Conventions licences require of a derived work, in
`THIRD_PARTY_NOTICES.md`.

## Licences and third-party code

| Component | Location | Terms |
|---|---|---|
| **IAU SOFA** | `mex/sofa/` | Unmodified. SOFA Software Licence; see the notice in each source file. Redistribution requires the notices to be retained. |
| **IERS Conventions software** | `mex/iers/` | Ported from the published Fortran, arithmetic byte-intact. The routines carry an `iers` prefix to satisfy clause 3(c) of the IERS Conventions Software Licence, which requires renaming a modified routine. Licence text in `mex/iers/IERS_CONVENTIONS_LICENSE.txt`. |
| **IGN Helmert tables** | `+referenceSystem/itrfParameters.m` | Published transformation parameters, transcribed and verified row by row against the source. |

The SOFA sources are **never modified**. Where a published IERS Fortran routine
had to be transcribed to C, the transcription is validated by differencing
against the compiled original over 2001 epochs spanning 1960–2100, not against
the single test case in its own header.

## Documents

| File | What it holds |
|---|---|
| `HANDOVER_referenceSystem.md` | **The single point of truth** — design, decisions, obligations, revision log, open items |
| `BEST_PRACTICE.md` | The lessons this project paid for, as a template for future work |
| `LICENSE` | MIT, and what it does and does not cover |
| `THIRD_PARTY_NOTICES.md` | Third-party components, their terms, and the notices SOFA and IERS require |
| `doc/referenceSystem_manual.pdf` | Generated reference manual: theory, philosophy, installation, guides, accuracy, API |
| `doc/*.html` | Browsable help, registered with the MATLAB Help browser |

---

*referenceSystem v2.1*
*Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)*
