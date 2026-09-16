/*
 * rsCore.h
 * --------
 * Numerical core of the referenceSystem toolbox: a thin, MATLAB-free layer
 * over the IAU SOFA C library (release 20231011, unmodified, in mex/sofa/).
 *
 * Design rules this file obeys (handover sections B.1 rule 4, C.4, C.6):
 *
 *   - No mex.h anywhere in rsCore.c or rsCore.h. The file compiles and its
 *     tests run under plain gcc, which is how test/c/testRsCore.c is built.
 *   - Arithmetic only. No policy. SOFA return codes are passed up unchanged;
 *     this library never warns, never prints and never throws. The MATLAB
 *     layer turns a code into a warning or an error (decision D3, section C.6).
 *   - No NaN is written in place of a status. An epoch whose time conversion
 *     failed leaves its outputs untouched and reports its code; the caller
 *     decides. This is section C.6 rule 5 pushed down into C, and it is the
 *     one behavioural difference from the v1 core, which filled the matrix
 *     with NaN and returned.
 *   - Epochs cross the boundary as a split (day, secOfDay) pair, never as a
 *     decimal MJD, so that sub-microsecond resolution survives (section B.3).
 *   - Rotation matrices cross the boundary as 3x3xN pages, column-major and
 *     contiguous: element (row, col) of page k is at [9*k + 3*col + row].
 *
 * Thread safety (section C.9):
 *   - SOFA is re-entrant; its tables are read-only after initialisation. No
 *     locking is needed around any function here, and adding a defensive
 *     mutex would serialise the OpenMP loop for nothing.
 *   - Every rs* compute function below is re-entrant.
 *   - rsSetMaxThreads is NOT re-entrant. Call it once, before any compute
 *     call, from a single thread. The MEX gateway does exactly that, once
 *     per MATLAB process.
 *   - The per-epoch loops carry no reduction and no cross-epoch state, so
 *     results are bit-identical at any thread count (decision D31). Any
 *     future change that introduces a shared accumulator breaks that
 *     guarantee and must be rejected.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:10 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#ifndef RS_CORE_H
#define RS_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/* JD - MJD. Kept here so that no rs* file repeats the literal. */
#define RS_JULIAN_DATE_OFFSET 2400000.5

/* Seconds in a day of TAI, TT or SI. */
#define RS_SECONDS_PER_DAY 86400.0

/*
 * Column order of the block written by rsFundamentalArguments. The block is
 * n x RS_FA_COLUMNS in column-major order, so argument j of epoch k is at
 * fa[j*n + k]. The MATLAB wrapper names the columns from this same order and
 * a contract test asserts the two agree, so this enum is the single authority
 * for the layout (handover principle 2).
 */
enum {
    RS_FA_L = 0,      /* Delaunay: mean anomaly of the Moon                  */
    RS_FA_LPRIME,     /* Delaunay: mean anomaly of the Sun                   */
    RS_FA_F,          /* Delaunay: L - Omega                                 */
    RS_FA_D,          /* Delaunay: mean elongation of the Moon from the Sun  */
    RS_FA_OMEGA,      /* Delaunay: mean longitude of the ascending node      */
    RS_FA_LME,        /* Planetary: mean longitude of Mercury                */
    RS_FA_LVE,        /* Planetary: mean longitude of Venus                  */
    RS_FA_LE,         /* Planetary: mean longitude of Earth                  */
    RS_FA_LMA,        /* Planetary: mean longitude of Mars                   */
    RS_FA_LJ,         /* Planetary: mean longitude of Jupiter                */
    RS_FA_LSA,        /* Planetary: mean longitude of Saturn                 */
    RS_FA_LU,         /* Planetary: mean longitude of Uranus                 */
    RS_FA_LNE,        /* Planetary: mean longitude of Neptune                */
    RS_FA_PA,         /* Planetary: general accumulated precession, NOT wrapped */
    RS_FA_TAU,        /* Doodson: tau = theta + pi - s, needs UT1            */
    RS_FA_S,          /* Doodson: mean longitude of the Moon                 */
    RS_FA_H,          /* Doodson: mean longitude of the Sun                  */
    RS_FA_P,          /* Doodson: longitude of lunar perigee                 */
    RS_FA_NPRIME,     /* Doodson: negative longitude of the lunar node       */
    RS_FA_PSTAR,      /* Doodson: longitude of solar perigee                 */
    RS_FA_COLUMNS
};

/* ---------------------------------------------------------------------- */
/* Build and configuration                                                 */
/* ---------------------------------------------------------------------- */

/* SOFA release this core was compiled against, e.g. "20231011". */
const char *rsSofaRelease(void);

/* 1 if compiled with OpenMP, 0 otherwise. */
int rsOpenMpEnabled(void);

/* Upper bound on OpenMP threads used by the per-epoch loops. A value <= 0
 * restores the OpenMP default. Not re-entrant; see the header comment. */
void rsSetMaxThreads(int maxThreads);

/* Current upper bound; 1 when OpenMP is absent. */
int rsGetMaxThreads(void);

/* Number of epochs below which the loops stay serial regardless of the
 * thread count, so that short calls do not pay for a parallel region. */
int rsParallelThreshold(void);

/* ---------------------------------------------------------------------- */
/* Time scales                                                             */
/* ---------------------------------------------------------------------- */

/*
 * TAI - UTC in seconds, from SOFA iauDat.
 *
 *   n         number of epochs
 *   day       [n] integer MJD (UTC day number at 0h)
 *   secOfDay  [n] seconds since 0h UTC; values >= 86400 occur on a positive
 *                 leap-second day and are clamped to just under one day for
 *                 the lookup, which is exact from 1972 onward because dAT is
 *                 constant across a UTC day in the integer-second era
 *   deltaAt   [n] output, TAI - UTC in seconds; untouched where status != 0
 *   status    [n] output, SOFA iauDat code, plus one code of our own:
 *                  0  ok
 *                 +1  dubious year, value returned
 *                 -1..-5  SOFA iauDat errors (bad year, month, day, fraction,
 *                     internal)
 *                 -6  the day number is not representable as a calendar date,
 *                     detected here rather than by SOFA
 *
 * Returns the most severe status: the minimum over all epochs if any is
 * negative, otherwise the maximum.
 *
 * TRAP, measured against SOFA 20231011 and documented because it is not
 * obvious from the SOFA header: a date before 1960 returns +1, NOT a negative
 * code, and leaves dAT at zero. A caller that treats +1 as a mere warning
 * therefore silently obtains dAT = 0 for a pre-UTC epoch. The MATLAB layer
 * range-checks against 1972-01-01 for this reason and never relies on the
 * status alone.
 */
int rsDeltaAt(int n, const double *day, const double *secOfDay,
              double *deltaAt, int *status);

/*
 * TDB - TT in seconds at the geocentre, from SOFA iauDtdb with the observer
 * terms set to zero. Purely periodic, bounded by about 1.7 ms.
 *
 *   day, secOfDay   [n] TT epoch, split form
 *   tdbMinusTt      [n] output, seconds
 *
 * Never fails; iauDtdb has no failure mode.
 */
void rsTdbMinusTt(int n, const double *day, const double *secOfDay,
                  double *tdbMinusTt);

/*
 * The same quantity for an observer who is NOT at the geocentre (prompt P21).
 *
 *   day, secOfDay      [n] TT epoch, split form
 *   ut1Fraction        [n] UT1 as a fraction of one day, or NULL
 *   eastLongitude      [n] observer east longitude, RADIANS, or NULL
 *   axisDistance       [n] distance from the Earth spin axis, METRES, or NULL
 *   equatorDistance    [n] distance north of the equatorial plane, METRES,
 *                          signed, or NULL
 *   tdbMinusTt         [n] output, seconds
 *
 * SI ENTERS HERE AND SOFA's OWN UNITS DO NOT LEAVE. iauDtdb takes u and v in
 * kilometres; the division by 1000 happens in this function, so that no other
 * file in the toolbox carries that factor and no caller can forget it. This is
 * the same rule rsSubdailyEopCorrection follows for microarcseconds.
 *
 * A NULL array is read as zero for every epoch. With axisDistance and
 * equatorDistance both zero the topocentric contribution of iauDtdb vanishes
 * identically, so rsTdbMinusTt is this function with four NULLs and there is
 * exactly one implementation of the series (the rsRotationItrsToGcrs /
 * rsRotationItrsToGcrsFromCip arrangement, applied again).
 *
 * Never fails; iauDtdb has no failure mode.
 */
void rsTdbMinusTtAtObserver(int n, const double *day, const double *secOfDay,
                            const double *ut1Fraction,
                            const double *eastLongitude,
                            const double *axisDistance,
                            const double *equatorDistance,
                            double *tdbMinusTt);

/* ---------------------------------------------------------------------- */
/* Solar-system body states (prompt P22, SOFA provider)                    */
/* ---------------------------------------------------------------------- */

/*
 * Bodies rsBodyState can supply. These values are indices into this enum and
 * mean nothing outside it. The NAIF identifier a kernel uses for the same body
 * is NOT here: it lives in referenceSystem.ephemerisBodies, which is the single
 * authority for the mapping from a body NAME to a kernel identifier, because
 * the identifier is a property of the ephemeris and not of this arithmetic.
 */
enum {
    RS_BODY_SUN = 0,
    RS_BODY_MERCURY,
    RS_BODY_VENUS,
    RS_BODY_EARTH,
    RS_BODY_MOON,
    RS_BODY_MARS,
    RS_BODY_JUPITER,
    RS_BODY_SATURN,
    RS_BODY_URANUS,
    RS_BODY_NEPTUNE,
    RS_BODY_EARTH_MOON_BARYCENTRE,
    RS_BODY_COUNT
};

/* Origin of the returned state. */
enum {
    RS_ORIGIN_BARYCENTRE = 0,   /* solar-system barycentre, BCRS oriented */
    RS_ORIGIN_GEOCENTRE = 1     /* Earth centre, by BCRS coordinate difference */
};

/* The astronomical unit in metres, exposed so that a test may compare it
 * against SOFA's own DAU rather than assume the two literals agree. */
double rsAstronomicalUnit(void);

/*
 * Position and velocity of a solar-system body from the bundled SOFA models.
 *
 *   day, secOfDay   [n] TDB epoch, split form. TT may be substituted; the two
 *                       differ by at most 1.7 ms, which is 51 m of Earth
 *                       motion and three orders below the model error
 *   body            one of the RS_BODY_* values
 *   origin          RS_ORIGIN_BARYCENTRE or RS_ORIGIN_GEOCENTRE
 *   state           [6n] output, 6-by-n COLUMN-MAJOR: element i of epoch k is
 *                        at state[6*k + i], rows 0..2 position in METRES and
 *                        rows 3..5 velocity in METRES PER SECOND. This is the
 *                        layout MATLAB reads back as a 6-by-N array with one
 *                        column per epoch, so nothing is transposed
 *   status          [n] output, per-epoch code, see below
 *
 * Returns the most severe status over all epochs: the minimum if any is
 * negative, otherwise the maximum.
 *
 *    0  ok
 *   +1  the epoch lies outside the interval over which the model's stated
 *       accuracy holds (iauEpv00 outside 1900-2100, iauPlan94 outside 1000-3000)
 *   +2  the planetary series failed to converge (iauPlan94 status +2)
 *   -1  unknown body
 *   -2  unknown origin
 *
 * HOW EACH BODY IS BUILT, BECAUSE SOFA SUPPLIES ONLY THREE THINGS AND THE REST
 * IS COMPOSITION:
 *
 *   Earth       iauEpv00 pvb, the only barycentric vector SOFA produces
 *   Sun         pvb - pvh: the Sun is exactly where the Earth's barycentric
 *               and heliocentric vectors differ, so no separate solar theory
 *               is involved and the two errors partly cancel
 *   Moon        pvb + iauMoon98
 *   planets     (pvb - pvh) + iauPlan94, which is heliocentric
 *
 * iauEpv00 is therefore evaluated ONCE per epoch and reused, which is also why
 * the geocentric origin costs nothing: it subtracts the pvb already in hand.
 *
 * FRAME. iauEpv00 and iauMoon98 are BCRS/GCRS oriented. iauPlan94 is referred
 * to the mean equator and equinox of J2000.0, which differs from the ICRS by
 * the frame bias, about 23 mas. NO BIAS ROTATION IS APPLIED. At Mercury that
 * is 6.7 km against a model error of 334 km, and at Neptune 500 km against
 * 158000 km, so applying it would imply a precision the model does not have
 * while adding a rotation whose sign cannot be checked against anything. The
 * MATLAB layer reports this as meta.frameBiasApplied = false rather than
 * leaving it to be discovered.
 */
int rsBodyState(int n, const double *day, const double *secOfDay,
                int body, int origin, double *state, int *status);

/* ---------------------------------------------------------------------- */
/* Earth orientation primitives                                            */
/* ---------------------------------------------------------------------- */

/*
 * CIP X, Y and the CIO locator s, radians, from a TT epoch.
 *   model 2006 -> SOFA iauXys06a (IAU 2006/2000A)
 *   model 2000 -> SOFA iauXys00a (IAU 2000A)
 * x, y, s are [n] outputs. Returns 0; the SOFA routines cannot fail.
 */
int rsCipXys(int n, const double *day, const double *secOfDay, int model,
             double *x, double *y, double *s);

/* Earth rotation angle, radians in [0, 2pi), from a UT1 epoch (iauEra00). */
void rsEarthRotationAngle(int n, const double *day, const double *secOfDay,
                          double *era);

/* Rate of the Earth rotation angle, rad/s, DERIVED from iauEra00 (decision
 * D63): rsEarthRotationAngle at MJD 51544 + 1000 s minus at MJD 51544 + 0 s,
 * over 1000. That is the arithmetic referenceSystem.earthRotationAngleRate
 * performs through the gateway, so the C API and MATLAB take the same value
 * from the same authority. It is NOT iersConstants.earthRotationRate
 * (7.292115e-5, a nominal mean), which differs by 1.47e-12 rad/s. */
double rsEarthRotationAngleRate(void);

/* TIO locator s', radians, from a TT epoch (iauSp00). */
void rsTioLocator(int n, const double *day, const double *secOfDay, double *sp);

/*
 * Polar-motion matrix TIRS -> ITRS (iauPom00), 3x3xN pages, column-major.
 * xp, yp, sp are [n] arrays in radians.
 */
void rsPolarMotionMatrix(int n, const double *xp, const double *yp,
                         const double *sp, double *matrices);

/* ---------------------------------------------------------------------- */
/* Fundamental arguments                                                   */
/* ---------------------------------------------------------------------- */

/*
 * The Delaunay, planetary and Doodson fundamental arguments, radians.
 *
 *   ttDay, ttSec    [n] TT epoch, split form
 *   ut1Day, ut1Sec  [n] UT1 epoch, split form; read only if hasUt1 != 0
 *   hasUt1          0 -> the tau column is filled with NaN, which is the
 *                        documented undefined-but-valid value: tau is a
 *                        function of GMST and therefore of UT1, and cannot
 *                        be formed from TT alone
 *   fa              [n * RS_FA_COLUMNS] output, column-major, see the enum
 *
 * All columns except RS_FA_PA are wrapped to [0, 2pi). RS_FA_PA is the
 * accumulated general precession, a secular quantity rather than a cyclic
 * angle, and is deliberately left unwrapped (decision D52).
 */
void rsFundamentalArguments(int n, const double *ttDay, const double *ttSec,
                            const double *ut1Day, const double *ut1Sec,
                            int hasUt1, double *fa);

/* ---------------------------------------------------------------------- */
/* Tidal variations in the Earth orientation parameters                    */
/* ---------------------------------------------------------------------- */

/*
 * Sub-daily ocean-tide and libration variation in polar motion and UT1, from
 * the ported IERS Conventions routines in mex/iers/. This is the sum of three
 * models, which is why it is one function and not three: they are always
 * applied together and separating them at this boundary would invite a caller
 * to apply two of the three.
 *
 *   ORTHO_EOP   diurnal and semidiurnal ocean tides, in xp, yp and UT1
 *   PMSDNUT2    diurnal lunisolar libration, in xp and yp
 *   UTLIBR      subdiurnal libration, in UT1
 *
 *   day, secOfDay   [n] UTC epoch, split form (decision D57; the routines'
 *                       own headers do not pin the scale down to better than
 *                       a minute and the difference is below 0.1 uas)
 *   dxp, dyp        [n] output, RADIANS
 *   dut1            [n] output, SECONDS
 *
 * SI conversion happens here rather than in mex/iers/, so that the ported
 * files stay a transcription of the Fortran and nothing else. The originals
 * return microarcseconds and microseconds.
 *
 * Never fails; the models are unconditional polynomials and trigonometric
 * sums with no failure mode and no valid-range test of their own.
 */
void rsSubdailyEopCorrection(int n, const double *day, const double *secOfDay,
                             double *dxp, double *dyp, double *dut1);

/*
 * Long-period zonal tide effect on the rotation of the Earth, from the ported
 * RG_ZONT2. These are the quantities that regularise UT1, NOT a missing signal
 * to be added to an observed series (decision D30).
 *
 *   day, secOfDay   [n] TT epoch, split form. TT, not UTC: RG_ZONT2's own
 *                       header states the argument is TT (strictly TDB, which
 *                       it says makes no significant difference)
 *   dut1            [n] output, SECONDS
 *   dlod            [n] output, SECONDS PER DAY
 *   domega          [n] output, RADIANS PER SECOND
 *
 * Units are already SI in the original, so nothing is rescaled here.
 * Never fails.
 */
void rsZonalTideEopCorrection(int n, const double *day, const double *secOfDay,
                              double *dut1, double *dlod, double *domega);


/* ---------------------------------------------------------------------- */
/* Earth rotation, ITRS to GCRS (prompt P9)                                */
/* ---------------------------------------------------------------------- */

/*
 * CIP X, Y and the CIO locator s INCLUDING the observed celestial pole
 * offsets, with the model-reference handling that finding C-2 exists for.
 *
 *   day, secOfDay [n] TT epoch, split form
 *   cipModel      2006 -> dX, dY are referred to IAU 2006/2000A; they are
 *                         added to iauXys06a directly and iauXys00a is never
 *                         called
 *                 2000 -> dX, dY are referred to IAU 2000A; the model bias
 *                         (X00 - X06) is added as well, which costs a second
 *                         full nutation series and is the only case in which
 *                         paying for it is correct
 *   dX, dY        [n] observed offsets in radians, or NULL for none
 *   x, y, s       [n] outputs, radians
 *
 * Returns 0, or -1 if cipModel is neither 2006 nor 2000.
 *
 * This is the ONLY place in the toolbox that decides what dX and dY are
 * referred to. cipCoordinates and rsRotationItrsToGcrs both come here, so the
 * C-2 fix has one implementation and cannot drift between the two callers
 * (handover principle 2, decision D61).
 */
int rsCipCoordinates(int n, const double *day, const double *secOfDay,
                     int cipModel, const double *dX, const double *dY,
                     double *x, double *y, double *s);

/*
 * Celestial-to-intermediate matrix GCRS -> CIRS from X, Y and s (iauC2ixys),
 * 3x3xN pages, column-major. x, y, s are [n] arrays in radians.
 */
void rsCelestialToIntermediateMatrix(int n, const double *x, const double *y,
                                     const double *s, double *matrices);

/*
 * Greenwich sidereal time, radians in [0, 2pi).
 *
 *   ut1Day, ut1Sec  [n] UT1 epoch, split form
 *   ttDay, ttSec    [n] TT epoch, split form, at the same instants
 *   apparent        0 -> mean, iauGmst06;  1 -> apparent, iauGst06a
 *   gst             [n] output
 *
 * Both quantities need both scales: UT1 carries the rotation and TT carries
 * the precession-nutation, and supplying one scale twice is a silent error of
 * up to 0.9 s of Earth rotation.
 */
void rsGreenwichSiderealTime(int n, const double *ut1Day, const double *ut1Sec,
                             const double *ttDay, const double *ttSec,
                             int apparent, double *gst);

/*
 * Equinox-based nutation-precession-bias matrix (iauPnm06a), 3x3xN pages.
 * A validation asset only (risk R13b): the toolbox transforms through the
 * CIO, and this exists so that a test can build the same rotation by the
 * classical route and difference the two.
 */
void rsEquinoxNutationMatrix(int n, const double *ttDay, const double *ttSec,
                             double *matrices);

/*
 * The ITRS -> GCRS rotation and, on request, its first two time derivatives.
 *
 *   ttDay, ttSec    [n] TT epoch of each output, split form
 *   ut1Day, ut1Sec  [n] UT1 epoch of the same instants, split form
 *   xp, yp          [3n] polar motion in radians, sampled at t-step, t and
 *                        t+step; sample j of epoch k is at [j*n + k], so
 *                        MATLAB passes an n-by-3 array and nothing is
 *                        transposed here. Samples 0 and 2 are read only when
 *                        derivativeOrder > 0
 *   dX, dY          [3n] observed CIP offsets, radians, same blocking
 *   ut1MinusTai     [3n] UT1 - TAI in seconds, same blocking. The Earth
 *                        rotation rate is the ERA slope times
 *                        1 + d(UT1 - TAI)/dt and its change the slope times
 *                        d2(UT1 - TAI)/dt2, both from the central differences
 *                        of these samples, so Rdot and Rddot are the time
 *                        derivatives of the UT1 the caller interpolated.
 *                        Read only when derivativeOrder > 0
 *   cipModel        as rsCipCoordinates
 *   derivativeOrder 0, 1 or 2; 0 evaluates the CIP once instead of three
 *                   times, which is the whole of the nargout gating
 *   step            central-difference step in seconds; must be > 0 when
 *                   derivativeOrder > 0
 *   r, rdot, rddot  3x3xN pages; rdot and rddot may be NULL when not wanted
 *
 * Returns 0, -1 for an unknown cipModel, -2 for a derivativeOrder outside
 * 0..2, -3 for a non-positive step with derivatives requested.
 *
 * The product formed internally is the GCRS -> ITRS matrix W*R3(theta)*Q,
 * which is the order SOFA documents; what is stored is its transpose, because
 * the toolbox returns ITRS -> GCRS and the inverse of an orthogonal rotation
 * is its transpose (decision D23). Transposing at the store costs nothing.
 */
int rsRotationItrsToGcrs(int n,
                         const double *ttDay, const double *ttSec,
                         const double *ut1Day, const double *ut1Sec,
                         const double *xp, const double *yp,
                         const double *dX, const double *dY,
                         const double *ut1MinusTai,
                         int cipModel, int derivativeOrder, double step,
                         double *r, double *rdot, double *rddot);

/*
 * The same rotation from a PRECOMPUTED CIP (prompt P19b).
 *
 * rsRotationItrsToGcrs evaluates iauXys06a itself, so there is no argument
 * through which an interpolated CIP can reach it. This entry point adds three,
 * and both entry points share one assembly - rsRotationItrsToGcrs is a call to
 * this one with NULL panels.
 *
 *   cipX, cipY, cipS  [3n] X, Y and the CIO locator in radians, blocked
 *                     exactly as xp and dX are: sample j of epoch k at
 *                     [j*n + k], samples 0 and 2 read only when
 *                     derivativeOrder > 0. THE OBSERVED POLE OFFSETS MUST
 *                     ALREADY BE IN THEM; dX and dY are then unread, and so is
 *                     cipModel, though both are still validated. Pass all
 *                     three or none.
 *
 * Returns as rsRotationItrsToGcrs, and additionally -4 if one or two of the
 * three CIP arrays are supplied.
 */
int rsRotationItrsToGcrsFromCip(int n,
                         const double *ttDay, const double *ttSec,
                         const double *ut1Day, const double *ut1Sec,
                         const double *xp, const double *yp,
                         const double *dX, const double *dY,
                         const double *ut1MinusTai,
                         const double *cipX, const double *cipY,
                         const double *cipS,
                         int cipModel, int derivativeOrder, double step,
                         double *r, double *rdot, double *rddot);

#ifdef __cplusplus
}
#endif

#endif /* RS_CORE_H */
