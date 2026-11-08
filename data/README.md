# `data/` — the committed tables only; downloads go to the data pool

**Nothing is downloaded into this folder.** Every file the toolbox fetches goes
to the shared data pool, by product: SPICE kernels to `<pool>/SPICE`, Earth
orientation series to `<pool>/EOP` (decision D133, after the organisation's
`DATA_POOL.md`: *all data go always to the data pool; only model code or
libraries go to the toolbox*). `referenceSystem.dataFolder` resolves the pool
root - an explicit argument, the stored preference, `DATAPOOL`, then
`READING_DATA_POOL` - and refuses when none is set; it never falls back to here.

**What this folder holds is committed and stays:** `eopc04_20.1962-now` and
`finals2000A.all`, pinned copies tracked by git so that the CI gate needs to
fetch only the kernels. They are not downloads, nothing writes them, and setup
lists them as `committed` beside the pool's series.

**Kernels stay out of git, wherever they are.** `.gitignore` still refuses
kernel extensions here as a guard: the files are third-party data that are not
ours to redistribute, they are reissued by their publishers so a committed copy
goes stale silently, and they are large enough to make a hand-over archive
unusable. `sb441-n16.bsp` alone is about 650 MB against a toolbox of roughly two.

**Record the filename and a digest in the result, never the file.** That is the
same rule D15 applies to kernel pairing and the one `mexSourceDigest` applies to
the C sources: identity travels, bulk does not.

## Where the files come from

**`referenceSystem.downloadKernels` is the single authority for the kernel URLs
and `referenceSystem.downloadEop` for the Earth orientation series.** This file
deliberately no longer repeats them. A prose table that no code reads is how
handover section H.7.1 came to carry a wrong host for `sb441-n16.bsp` across four
sessions (obligation O26); the catalogue in `downloadKernels.m` is executable, so
it is checkable.

```matlab
referenceSystem.downloadKernels()                    % what it would fetch
referenceSystem.downloadKernels(Mode = "verify")     % do the URLs resolve?
referenceSystem.downloadKernels(Set = "minimal", Mode = "download")

setupReferenceSystem(Fetch = "all", KernelSet = "orientation", Verbose = true)
```

Nothing is fetched by default, by any of these — `Mode` defaults to `"list"`.

There are **two axes**, because there are two independent questions.

| `Set` — how much content, **accumulating** | |
|---|---|
| `minimal` | the planetary ephemeris alone (~31 MB) |
| `orientation` | adds the PCK, the lunar orientation and the lunar frame kernel |
| `all` | adds `sb441-n16.bsp` (~650 MB). It means all. |

| `Span` — which issue of the ephemeris, **exclusive** | |
|---|---|
| `short` | `de440s.bsp`, 1849–2150, ~31 MB. Ample for anything GRACE-era. |
| `full` | `de440.bsp`, 1550–2650, ~2.6 GB |

`de440s.bsp` and `de440.bsp` are the **same integration** over different
intervals, so no selection returns both: holding two issues of one ephemeris
gains nothing and leaves it ambiguous which segment answers a query. That is why
the span is a separate option and not another step in the set.

Handover section H.7.1 keeps the narrative — the toolkit-version trap in
`pck00011.tpc`, and why `codes_300ast_20100725.bsp` is the wrong file even though
it is the one NAIF's asteroid directory contains — and `downloadKernels` carries
both as `Note` rows so they travel with the download rather than beside it.

## What to hand over instead of a kernel

A kernel cannot be uploaded to a review session and does not need to be. What
carries the information is small and textual:

- `cspice_dafec` on the kernel's comment area — it names the planetary
  ephemeris the file expects, which is D15's pairing check;
- `cspice_spkobj` — the body identifiers and their coverage intervals;
- the HORIZONS fixture written by `test/fetchHorizonsVectors.m`;
- the measured DE440−DE441 residual required by §H.7.5.
