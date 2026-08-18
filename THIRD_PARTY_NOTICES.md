# Third-party notices

`referenceSystem` is distributed under the MIT licence in `LICENSE`. **That
licence covers this project's own code only.** The components below are
third-party and carry their own terms; where those terms differ from the MIT
licence, the third-party terms govern that component. Nothing in `LICENSE`
grants any right in them.

| Component | Location | Terms | Modified? |
|---|---|---|---|
| IAU SOFA, release 2023-10-11 | `mex/sofa/` | SOFA Software Licence, reproduced in full in every source file | **No** — intact, unchanged copies |
| IERS Conventions (2010) software | `mex/iers/` | IERS Conventions Software Licence, `mex/iers/IERS_CONVENTIONS_LICENSE.txt` | **Yes** — transcribed from the published Fortran to C, renamed with an `iers` prefix as clause 3(c) requires |
| IGN Helmert transformation parameters | `+referenceSystem/itrfParameters.m` | Published parameter tables, transcribed and verified row by row | Transcribed values only |
| IERS EOP series (C04, `finals2000A`) | `test/fixtures/*.txt` | IERS data products, Paris Observatory / IERS Earth Orientation Centre | Truncated to a test-sized span |
| JPL HORIZONS state vectors | `test/fixtures/horizonsVectors.txt` | JPL Solar System Dynamics, generated output retained as a reference fixture | Reformatted for the test harness |
| GRACE-FO IMU1B excerpt | `test/fixtures/imu1bGraceC.txt` | NASA/JPL GRACE Follow-On Science Data System, distributed via PO.DAAC | Excerpt only |

JPL planetary ephemeris kernels (DE440/DE441, `sb441-n16`) and the NAIF
SPICE/MICE toolkit are **not** distributed with this toolbox. They are fetched
by the user and remain subject to their own terms.

---

## Statement required by the SOFA Software Licence

The SOFA Software Licence, clause 3, requires that any part of a distribution
which is not an intact, unchanged copy of SOFA source be marked as a derived
work and described. The following statement is made in satisfaction of clauses
3(a) and 3(b); clause 3(e) requires it to be reproduced in any onward source
distribution.

**(a)** This work uses routines and computations derived by the author from
software provided by SOFA under licence, and **it does not itself constitute
software provided by and/or endorsed by SOFA**. The IAU SOFA Board has neither
reviewed nor endorsed this toolbox.

**(b)** How this work is based upon, contains, and differs from the original
SOFA software:

- **Contains.** `mex/sofa/` holds 247 SOFA C source files and 2 headers as distributed in
  release 2023-10-11, byte-for-byte unchanged, each retaining its own copyright
  notice and the full licence text. They are compiled into this toolbox's MEX
  gateway and are not edited, patched, or wrapped in place.
- **Is based upon.** The toolbox's own C layer (`mex/rsCore.c`) calls SOFA
  routines for the parts of the transformation chain SOFA defines — the CIP
  coordinates and CIO locator (`iauXys06a`, `iauXys00a`), the
  celestial-to-intermediate matrix (`iauC2ixys`), polar motion (`iauPom00`,
  `iauSp00`), the Earth rotation angle (`iauEra00`), sidereal time
  (`iauGmst06`, `iauGst06a`), the leap-second table (`iauDat`), the TDB
  periodic terms (`iauDtdb`), the fundamental arguments (`iauFa*03`) and the
  bundled low-precision ephemerides (`iauEpv00`, `iauPlan94`, `iauMoon98`). The rotation chain
  this toolbox assembles from them is SOFA's, and the accuracy of that chain is
  SOFA's.
- **Differs.** Everything around those calls is this project's own and is not
  SOFA's responsibility: the epoch representation and its leap-aware carry, the
  Chebyshev interpolant for the Earth-orientation chain, the finite-difference
  rate and acceleration of the rotation matrix, the analytic EOP partial
  derivatives, the sub-daily and zonal-tide EOP corrections (taken from the
  IERS Conventions software, not from SOFA), the vectorisation and OpenMP
  scheduling, the C API, the MATLAB interface, and every option, default and
  refusal in it. No SOFA source file is modified; no routine defined by this
  toolbox carries an `iau` or `sofa` prefix, as clause 3(c) requires.

The SOFA sources may be replaced with a different official release by the user;
`referenceSystem.mexSourceDigest` reports a content digest of every C source the
gateway was built from, so which SOFA release is in a given build is a
measurable fact rather than a claim.

---

## Statement required by the IERS Conventions Software Licence

The routines `ORTHO_EOP`, `UTLIBR`, `PMSDNUT2`, `FUNDARG`, `CNMTX` and
`RG_ZONT2` from the IERS Conventions (2010) software collection were
transcribed from the published Fortran into C. They are therefore **modified**
software under that licence and are renamed with an `iers` prefix, as its
clause 3(c) requires; the licence text is reproduced in
`mex/iers/IERS_CONVENTIONS_LICENSE.txt`. Each transcription is validated by
differencing against the compiled original over 2001 epochs spanning 1960–2100,
and the residuals are recorded in `HANDOVER_referenceSystem.md`. The IERS
Conventions Center has neither reviewed nor endorsed this toolbox.
