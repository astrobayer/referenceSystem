/*
 * iersModels.h -- C ports of the IERS Conventions (2010) software collection.
 *
 * DERIVED WORK NOTICE (IERS Conventions Software License, clause 3).
 * ------------------------------------------------------------------
 * The routines declared here are a derived work based on the IERS Conventions
 * software.  They are NOT IERS Conventions software, they were neither
 * distributed nor endorsed by the IERS Conventions Center, and the original
 * Fortran is reproduced unmodified in mex/iers/iers_src/ so that any reader
 * can see exactly what was derived from what.  How the derived work differs
 * from the original, in full:
 *
 *   1. Language.  Each routine is transcribed line-for-line from Fortran 77
 *      to C99.  No expression was re-ordered, re-associated or simplified,
 *      because the published test cases are quoted to the last digit and
 *      re-association would move that digit.
 *   2. Names.  Clause 3(c) of the licence requires the name of every modified
 *      routine to be changed, so ORTHO_EOP becomes iersOrthoEop, FUNDARG
 *      becomes iersFundarg, and so on.  The prefix is also what handover
 *      section C.4 asks of C code, which has no namespaces.
 *   3. Fortran-only mechanics.  DATA statements filling a two-dimensional
 *      array in column-major order are unrolled into explicit C tables; this
 *      is a transcription of storage order, not of arithmetic, and it is the
 *      one place a silent error could hide, which is why every table is
 *      exercised by its routine's own published test case in
 *      test/c/testIersModels.c.
 *   4. iersCnmtx drops the redundant N dimension of NJ/MJ, since every one of
 *      the 71 tabulated lines has N = 2 and the original loops N = 2..2.
 *   5. iersPmsdnut2 keeps the original's hard-coded IBAND = 1 behaviour: the
 *      ten quasi-diurnal terms only, as IERS Conventions (2010) section
 *      5.5.1.1 recommends and as the original routine implements.
 *
 * Nothing else was changed.  In particular iersFundarg is NOT replaced by
 * SOFA's iauFa*03 (decision D27): the published validation of the four
 * routines that call it was obtained with this FUNDARG, and substituting a
 * different implementation inside a validated unit would invalidate the only
 * external check the tidal chain has.  The agreement between the two is
 * measured instead -- see test/c/testIersModels.c, which sweeps 1960 to 2100
 * and writes test/fixtures/fundargIers.csv for the MATLAB-side cross-check.
 *
 * Units, exactly as in the originals.  Nothing here converts to SI; that
 * happens one layer up in rsCore.c, so that this file stays a transcription.
 *
 *   iersFundarg    radians
 *   iersCnmtx      dimensionless orthotide partials (feeds iersOrthoEop only)
 *   iersOrthoEop   dx, dy in microarcseconds; dUT1 in microseconds
 *   iersPmsdnut2   dx, dy in microarcseconds
 *   iersUtlibr     dUT1 in microseconds; dLOD in microseconds per day
 *   iersRgZont2    dUT1 in seconds; dLOD in seconds per day;
 *                  dOmega in radians per second
 *
 * Time argument.  iersOrthoEop, iersPmsdnut2 and iersUtlibr take a Modified
 * Julian Date whose scale the original headers do not pin down to better than
 * a minute; this toolbox feeds them UTC (decision D57, and see the ACCURACY
 * block of referenceSystem.subdailyEopCorrection for the measured cost).
 * iersRgZont2 takes Julian centuries of TT since J2000.0, which its own header
 * does state.
 *
 * Thread safety: every routine here is a pure function of its arguments with
 * no static mutable state, so all of them are re-entrant and safe to call from
 * an OpenMP loop without locking (handover section C.9 rule 3).
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-25 09:40 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#ifndef IERS_MODELS_H
#define IERS_MODELS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Lunisolar fundamental arguments from Julian centuries of TT since J2000.0.
 * Derived from FUNDARG.F. */
void iersFundarg(double t, double *l, double *lp, double *f, double *d,
                 double *om);

/* Orthotide partials of the diurnal and semidiurnal ocean tides; h has
 * length 12.  Derived from CNMTX.F. */
void iersCnmtx(double dmjd, double h[12]);

/* Diurnal and semidiurnal ocean-tide variation in polar motion and UT1.
 * eop[0] = dx (uas), eop[1] = dy (uas), eop[2] = dUT1 (us).
 * Derived from ORTHO_EOP.F. */
void iersOrthoEop(double timeMjd, double eop[3]);

/* Diurnal lunisolar libration in polar motion; pm[0] = dx, pm[1] = dy, both
 * in microarcseconds.  Derived from PMSDNUT2.F. */
void iersPmsdnut2(double rmjd, double pm[2]);

/* Subdiurnal libration in UT1 and LOD, in microseconds and microseconds per
 * day.  Derived from UTLIBR.F. */
void iersUtlibr(double rmjd, double *dut1, double *dlod);

/* Long-period zonal Earth tide effect on the rotation of the Earth, from
 * Julian centuries of TT since J2000.0.  dut is in seconds, dlod in seconds
 * per day, domega in radians per second.  Derived from RG_ZONT2.F.
 *
 * These are the quantities that turn observed UT1 into regularised UT1R:
 * UT1R = UT1 - dut.  They are NOT a missing signal to be added to a C04
 * series, which already contains them as observed (handover decision D30).
 */
void iersRgZont2(double t, double *dut, double *dlod, double *domega);

#ifdef __cplusplus
}
#endif

#endif /* IERS_MODELS_H */
