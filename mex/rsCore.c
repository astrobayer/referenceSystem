/*
 * rsCore.c
 * --------
 * See rsCore.h for the API, the conventions and the thread-safety contract.
 *
 * This file has no MATLAB dependency and is compiled and tested standalone by
 * test/c/testRsCore.c under plain gcc (handover section C.4).
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:10 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "rsCore.h"
#include "sofa/sofa.h"
#include "iers/iersModels.h"
#include <math.h>
#include <stddef.h>

#ifdef _OPENMP
#include <omp.h>
#endif

#ifndef RS_SOFA_RELEASE
#define RS_SOFA_RELEASE "20231011"
#endif

/* Epoch count below which every loop stays serial. Below roughly this size a
 * parallel region costs more than the arithmetic it distributes. */
#define RS_PARALLEL_THRESHOLD 64

/* pi. sofam.h is a SOFA-internal header and is deliberately not included
 * here, so the one constant this file needs is stated locally. */
static const double rsPi = 3.14159265358979323846264338328;

/* Set once per process by the gateway, before any compute call. */
static int rsMaxThreads = 0;

/* ---------------------------------------------------------------------- */
/* Build and configuration                                                 */
/* ---------------------------------------------------------------------- */

const char *rsSofaRelease(void)
{
    return RS_SOFA_RELEASE;
}

int rsOpenMpEnabled(void)
{
#ifdef _OPENMP
    return 1;
#else
    return 0;
#endif
}

void rsSetMaxThreads(int maxThreads)
{
    rsMaxThreads = (maxThreads > 0) ? maxThreads : 0;
}

int rsGetMaxThreads(void)
{
#ifdef _OPENMP
    return (rsMaxThreads > 0) ? rsMaxThreads : omp_get_max_threads();
#else
    (void)rsMaxThreads;
    return 1;
#endif
}

int rsParallelThreshold(void)
{
    return RS_PARALLEL_THRESHOLD;
}

/* ---------------------------------------------------------------------- */
/* Local helpers                                                           */
/* ---------------------------------------------------------------------- */

/* Two-part Julian date from a split epoch: part 1 carries the whole day, part
 * 2 the fraction, which is the split SOFA documents as the most accurate. */
static void rsSplitJulianDate(double day, double secOfDay, double *jd1, double *jd2)
{
    *jd1 = RS_JULIAN_DATE_OFFSET + day;
    *jd2 = secOfDay / RS_SECONDS_PER_DAY;
}

/* Julian centuries of TT since J2000.0, from a split TT epoch. The subtraction
 * is done on the day number, which is exact, before the fraction is added. */
static double rsJulianCenturies(double day, double secOfDay)
{
    return ((day - 51544.0) + (secOfDay / RS_SECONDS_PER_DAY - 0.5)) / 36525.0;
}

/* Write a row-major SOFA 3x3 matrix as a column-major page. */
static void rsStorePage(const double m[3][3], double *page)
{
    int row;
    int col;
    for (col = 0; col < 3; col++) {
        for (row = 0; row < 3; row++) {
            page[3 * col + row] = m[row][col];
        }
    }
}

/* ---------------------------------------------------------------------- */
/* Time scales                                                             */
/* ---------------------------------------------------------------------- */

int rsDeltaAt(int n, const double *day, const double *secOfDay,
              double *deltaAt, int *status)
{
    int worstNegative = 0;
    int worstPositive = 0;
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        reduction(min:worstNegative) reduction(max:worstPositive) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        int year = 0;
        int month = 0;
        int dayOfMonth = 0;
        double unusedFraction = 0.0;
        double fractionOfDay;
        double value = 0.0;
        int code;

        code = iauJd2cal(RS_JULIAN_DATE_OFFSET + day[k], 0.0,
                         &year, &month, &dayOfMonth, &unusedFraction);
        if (code != 0) {
            status[k] = -6;
        } else {
            /* A positive leap second puts secOfDay in [86400, 86401). dAT is
             * constant across a UTC day in the integer-second era, so clamping
             * the fraction to just under one day is exact there; before 1972
             * the fraction is always < 1 anyway and is passed through. */
            fractionOfDay = secOfDay[k] / RS_SECONDS_PER_DAY;
            if (fractionOfDay >= 1.0) {
                fractionOfDay = nextafter(1.0, 0.0);
            }
            if (fractionOfDay < 0.0) {
                fractionOfDay = 0.0;
            }
            status[k] = iauDat(year, month, dayOfMonth, fractionOfDay, &value);
            if (status[k] >= 0) {
                deltaAt[k] = value;
            }
        }
        if (status[k] < worstNegative) {
            worstNegative = status[k];
        }
        if (status[k] > worstPositive) {
            worstPositive = status[k];
        }
    }

    return (worstNegative < 0) ? worstNegative : worstPositive;
}

void rsTdbMinusTtAtObserver(int n, const double *day, const double *secOfDay,
                            const double *ut1Fraction,
                            const double *eastLongitude,
                            const double *axisDistance,
                            const double *equatorDistance,
                            double *tdbMinusTt)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double jd1;
        double jd2;
        double ut = (ut1Fraction == NULL) ? 0.0 : ut1Fraction[k];
        double elong = (eastLongitude == NULL) ? 0.0 : eastLongitude[k];
        /* iauDtdb wants kilometres. The division lives here so that the SI
         * boundary of this library holds and no caller repeats the factor. */
        double u = (axisDistance == NULL) ? 0.0 : axisDistance[k] / 1000.0;
        double v = (equatorDistance == NULL) ? 0.0 : equatorDistance[k] / 1000.0;

        rsSplitJulianDate(day[k], secOfDay[k], &jd1, &jd2);
        tdbMinusTt[k] = iauDtdb(jd1, jd2, ut, elong, u, v);
    }
}

void rsTdbMinusTt(int n, const double *day, const double *secOfDay,
                  double *tdbMinusTt)
{
    /* Observer terms zero: the geocentre. With u = v = 0 the topocentric
     * contribution of iauDtdb vanishes identically, so this is the exact
     * geocentric value and not an approximation of one, and it is the same
     * series evaluation the observer form runs rather than a second copy. */
    rsTdbMinusTtAtObserver(n, day, secOfDay, NULL, NULL, NULL, NULL,
                           tdbMinusTt);
}

/* ---------------------------------------------------------------------- */
/* Solar-system body states (prompt P22, SOFA provider)                    */
/* ---------------------------------------------------------------------- */

/*
 * The astronomical unit in metres. IAU 2012 Resolution B2 makes this a
 * defining constant, so it is exact and carries no uncertainty. sofam.h is a
 * SOFA-internal header this file deliberately does not include, so the value
 * is stated here and rsAstronomicalUnit exposes it; testRsCore.c MAY include
 * sofam.h and asserts the two literals are bit-identical, which turns "they
 * agree" from an assumption into a measurement.
 */
static const double rsAu = 1.49597870700e11;

double rsAstronomicalUnit(void)
{
    return rsAu;
}

/* The more severe of two status codes: negative wins, otherwise the larger. */
static int rsWorseStatus(int first, int second)
{
    if (first < 0 || second < 0) {
        return (first < second) ? first : second;
    }
    return (first > second) ? first : second;
}

/*
 * Barycentric state of one body in au and au/day, given the Earth's
 * heliocentric and barycentric vectors already evaluated for this epoch.
 * Returns the iauPlan94 status, or -1 for an unknown body.
 */
static int rsBarycentricStateAu(double jd1, double jd2, int body,
                                const double pvh[2][3],
                                const double pvb[2][3],
                                double pv[2][3])
{
    double pvBody[2][3];
    int planet = 0;
    int status;
    int row;
    int col;

    switch (body) {
    case RS_BODY_EARTH:
        for (row = 0; row < 2; row++) {
            for (col = 0; col < 3; col++) {
                pv[row][col] = pvb[row][col];
            }
        }
        return 0;

    case RS_BODY_MOON:
        iauMoon98(jd1, jd2, pvBody);
        for (row = 0; row < 2; row++) {
            for (col = 0; col < 3; col++) {
                pv[row][col] = pvb[row][col] + pvBody[row][col];
            }
        }
        return 0;

    case RS_BODY_SUN:
        for (row = 0; row < 2; row++) {
            for (col = 0; col < 3; col++) {
                pv[row][col] = pvb[row][col] - pvh[row][col];
            }
        }
        return 0;

    case RS_BODY_MERCURY:               planet = 1; break;
    case RS_BODY_VENUS:                 planet = 2; break;
    case RS_BODY_EARTH_MOON_BARYCENTRE: planet = 3; break;
    case RS_BODY_MARS:                  planet = 4; break;
    case RS_BODY_JUPITER:               planet = 5; break;
    case RS_BODY_SATURN:                planet = 6; break;
    case RS_BODY_URANUS:                planet = 7; break;
    case RS_BODY_NEPTUNE:               planet = 8; break;
    default:
        return -1;
    }

    status = iauPlan94(jd1, jd2, planet, pvBody);
    if (status < 0) {
        /* Unreachable: planet is 1..8 by construction. Kept so that a future
         * body added to the enum without an arm here fails loudly. */
        return -1;
    }
    for (row = 0; row < 2; row++) {
        for (col = 0; col < 3; col++) {
            pv[row][col] = (pvb[row][col] - pvh[row][col]) + pvBody[row][col];
        }
    }
    return status;
}

int rsBodyState(int n, const double *day, const double *secOfDay,
                int body, int origin, double *state, int *status)
{
    int k;
    int worst = 0;

    if (body < 0 || body >= RS_BODY_COUNT) {
        return -1;
    }
    if (origin != RS_ORIGIN_BARYCENTRE && origin != RS_ORIGIN_GEOCENTRE) {
        return -2;
    }

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double jd1;
        double jd2;
        double pvh[2][3];
        double pvb[2][3];
        double pv[2][3];
        int epvStatus;
        int bodyStatus;
        int row;
        int col;

        rsSplitJulianDate(day[k], secOfDay[k], &jd1, &jd2);
        epvStatus = iauEpv00(jd1, jd2, pvh, pvb);
        bodyStatus = rsBarycentricStateAu(jd1, jd2, body, pvh, pvb, pv);

        if (origin == RS_ORIGIN_GEOCENTRE) {
            for (row = 0; row < 2; row++) {
                for (col = 0; col < 3; col++) {
                    pv[row][col] -= pvb[row][col];
                }
            }
        }

        for (col = 0; col < 3; col++) {
            state[6 * k + col] = pv[0][col] * rsAu;
            state[6 * k + 3 + col] = pv[1][col] * rsAu / RS_SECONDS_PER_DAY;
        }
        status[k] = rsWorseStatus(epvStatus, bodyStatus);
    }

    /* Reduced OUTSIDE the parallel region on purpose. An OpenMP reduction over
     * a custom "most severe" operator would be order dependent in principle and
     * decision D31 makes bit-reproducibility across thread counts an asserted
     * property, not a hope. The second pass is n comparisons. */
    for (k = 0; k < n; k++) {
        worst = rsWorseStatus(worst, status[k]);
    }
    return worst;
}

/* ---------------------------------------------------------------------- */
/* Earth orientation primitives                                            */
/* ---------------------------------------------------------------------- */

int rsCipXys(int n, const double *day, const double *secOfDay, int model,
             double *x, double *y, double *s)
{
    int k;

    if (model != 2006 && model != 2000) {
        return -1;
    }

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double jd1;
        double jd2;
        rsSplitJulianDate(day[k], secOfDay[k], &jd1, &jd2);
        if (model == 2006) {
            iauXys06a(jd1, jd2, &x[k], &y[k], &s[k]);
        } else {
            iauXys00a(jd1, jd2, &x[k], &y[k], &s[k]);
        }
    }

    return 0;
}

void rsEarthRotationAngle(int n, const double *day, const double *secOfDay,
                          double *era)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double jd1;
        double jd2;
        rsSplitJulianDate(day[k], secOfDay[k], &jd1, &jd2);
        era[k] = iauEra00(jd1, jd2);
    }
}

double rsEarthRotationAngleRate(void)
{
    /* The same two epochs and the same subtraction as earthRotationAngleRate,
     * so the two values are equal bit for bit rather than to a tolerance. The
     * difference is exact in the expression - ERA is linear in UT1 - and 1000 s
     * keeps it clear of the 2pi wrap at this epoch. */
    const double day[2] = {51544.0, 51544.0};
    const double sec[2] = {0.0, 1000.0};
    double era[2];

    rsEarthRotationAngle(2, day, sec, era);
    return (era[1] - era[0]) / 1000.0;
}

void rsTioLocator(int n, const double *day, const double *secOfDay, double *sp)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double jd1;
        double jd2;
        rsSplitJulianDate(day[k], secOfDay[k], &jd1, &jd2);
        sp[k] = iauSp00(jd1, jd2);
    }
}

void rsPolarMotionMatrix(int n, const double *xp, const double *yp,
                         const double *sp, double *matrices)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double rpom[3][3];
        iauPom00(xp[k], yp[k], sp[k], rpom);
        rsStorePage(rpom, &matrices[9 * (size_t)k]);
    }
}

/* ---------------------------------------------------------------------- */
/* Fundamental arguments                                                   */
/* ---------------------------------------------------------------------- */

void rsFundamentalArguments(int n, const double *ttDay, const double *ttSec,
                            const double *ut1Day, const double *ut1Sec,
                            int hasUt1, double *fa)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double t = rsJulianCenturies(ttDay[k], ttSec[k]);
        double l = iauFal03(t);
        double lPrime = iauFalp03(t);
        double f = iauFaf03(t);
        double d = iauFad03(t);
        double omega = iauFaom03(t);

        /* Doodson set, derived exactly as IERS Conventions (2010) Ch. 6
         * defines it. The derivations are done before wrapping, so that a
         * difference of two wrapped angles never produces a value outside
         * [-2pi, 2pi) that the final wrap could not repair. */
        double doodsonS = f + omega;
        double doodsonH = doodsonS - d;
        double doodsonP = doodsonS - l;
        double doodsonNPrime = -omega;
        double doodsonPStar = doodsonS - d - lPrime;
        double doodsonTau;

        if (hasUt1) {
            double ttJd1;
            double ttJd2;
            double ut1Jd1;
            double ut1Jd2;
            double gmst;
            rsSplitJulianDate(ttDay[k], ttSec[k], &ttJd1, &ttJd2);
            rsSplitJulianDate(ut1Day[k], ut1Sec[k], &ut1Jd1, &ut1Jd2);
            gmst = iauGmst06(ut1Jd1, ut1Jd2, ttJd1, ttJd2);
            doodsonTau = gmst + rsPi - doodsonS;
        } else {
            doodsonTau = NAN;
        }

        fa[(size_t)RS_FA_L * n + k] = iauAnp(l);
        fa[(size_t)RS_FA_LPRIME * n + k] = iauAnp(lPrime);
        fa[(size_t)RS_FA_F * n + k] = iauAnp(f);
        fa[(size_t)RS_FA_D * n + k] = iauAnp(d);
        fa[(size_t)RS_FA_OMEGA * n + k] = iauAnp(omega);

        fa[(size_t)RS_FA_LME * n + k] = iauAnp(iauFame03(t));
        fa[(size_t)RS_FA_LVE * n + k] = iauAnp(iauFave03(t));
        fa[(size_t)RS_FA_LE * n + k] = iauAnp(iauFae03(t));
        fa[(size_t)RS_FA_LMA * n + k] = iauAnp(iauFama03(t));
        fa[(size_t)RS_FA_LJ * n + k] = iauAnp(iauFaju03(t));
        fa[(size_t)RS_FA_LSA * n + k] = iauAnp(iauFasa03(t));
        fa[(size_t)RS_FA_LU * n + k] = iauAnp(iauFaur03(t));
        fa[(size_t)RS_FA_LNE * n + k] = iauAnp(iauFane03(t));
        /* Not wrapped: see rsCore.h and decision D52. */
        fa[(size_t)RS_FA_PA * n + k] = iauFapa03(t);

        fa[(size_t)RS_FA_TAU * n + k] = hasUt1 ? iauAnp(doodsonTau) : doodsonTau;
        fa[(size_t)RS_FA_S * n + k] = iauAnp(doodsonS);
        fa[(size_t)RS_FA_H * n + k] = iauAnp(doodsonH);
        fa[(size_t)RS_FA_P * n + k] = iauAnp(doodsonP);
        fa[(size_t)RS_FA_NPRIME * n + k] = iauAnp(doodsonNPrime);
        fa[(size_t)RS_FA_PSTAR * n + k] = iauAnp(doodsonPStar);
    }
}

/* ---------------------------------------------------------------------- */
/* Tidal variations in the Earth orientation parameters                    */
/* ---------------------------------------------------------------------- */

/* Microarcseconds to radians, and microseconds to seconds. The ported IERS
 * routines return the units their originals return; the conversion to SI
 * belongs on this side of the boundary so mex/iers/ stays a transcription. */
#define RS_MICROARCSEC_TO_RAD (4.848136811095359935899141e-6 * 1e-6)
#define RS_MICROSEC_TO_SEC 1e-6

void rsSubdailyEopCorrection(int n, const double *day, const double *secOfDay,
                             double *dxp, double *dyp, double *dut1)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double mjd = day[k] + secOfDay[k] / RS_SECONDS_PER_DAY;
        double ocean[3];
        double libration[2];
        double librationUt1;
        double librationLod;

        iersOrthoEop(mjd, ocean);
        iersPmsdnut2(mjd, libration);
        iersUtlibr(mjd, &librationUt1, &librationLod);

        /* librationLod is computed by UTLIBR and deliberately discarded. It is
         * the libration part of the sub-daily LOD signal only; ORTHO_EOP
         * publishes no matching ocean-tide LOD term, so returning it would
         * hand the caller a quantity that looks like "the sub-daily LOD
         * correction" and is in fact a fraction of it. Decision D55. */
        (void)librationLod;

        dxp[k] = (ocean[0] + libration[0]) * RS_MICROARCSEC_TO_RAD;
        dyp[k] = (ocean[1] + libration[1]) * RS_MICROARCSEC_TO_RAD;
        dut1[k] = (ocean[2] + librationUt1) * RS_MICROSEC_TO_SEC;
    }
}

void rsZonalTideEopCorrection(int n, const double *day, const double *secOfDay,
                              double *dut1, double *dlod, double *domega)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        iersRgZont2(rsJulianCenturies(day[k], secOfDay[k]),
                    &dut1[k], &dlod[k], &domega[k]);
    }
}

/* ---------------------------------------------------------------------- */
/* Earth rotation, ITRS to GCRS (prompt P9)                                */
/* ---------------------------------------------------------------------- */

/*
 * R3(theta) and its first two derivatives with respect to theta, in the SOFA
 * iauRz sense: the matrix that premultiplies a column vector to rotate the
 * FRAME about +z by theta. Written out rather than obtained by calling iauRz
 * on an identity, because the derivative matrices are not rotations and iauRz
 * cannot produce them.
 */
static void rsRotationZ(double theta, double m[3][3])
{
    double c = cos(theta);
    double s = sin(theta);
    m[0][0] =  c;  m[0][1] =  s;  m[0][2] = 0.0;
    m[1][0] = -s;  m[1][1] =  c;  m[1][2] = 0.0;
    m[2][0] = 0.0; m[2][1] = 0.0; m[2][2] = 1.0;
}

static void rsRotationZFirstDerivative(double theta, double m[3][3])
{
    double c = cos(theta);
    double s = sin(theta);
    m[0][0] = -s;  m[0][1] =  c;  m[0][2] = 0.0;
    m[1][0] = -c;  m[1][1] = -s;  m[1][2] = 0.0;
    m[2][0] = 0.0; m[2][1] = 0.0; m[2][2] = 0.0;
}

static void rsRotationZSecondDerivative(double theta, double m[3][3])
{
    double c = cos(theta);
    double s = sin(theta);
    m[0][0] = -c;  m[0][1] = -s;  m[0][2] = 0.0;
    m[1][0] =  s;  m[1][1] = -c;  m[1][2] = 0.0;
    m[2][0] = 0.0; m[2][1] = 0.0; m[2][2] = 0.0;
}

/* c = a * b, all 3x3, no aliasing. */
static void rsMultiply(const double a[3][3], const double b[3][3],
                       double c[3][3])
{
    int i;
    int j;
    for (i = 0; i < 3; i++) {
        for (j = 0; j < 3; j++) {
            c[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j];
        }
    }
}

/* c = a + scale * b. */
static void rsAccumulate(double c[3][3], const double b[3][3], double scale)
{
    int i;
    int j;
    for (i = 0; i < 3; i++) {
        for (j = 0; j < 3; j++) {
            c[i][j] += scale * b[i][j];
        }
    }
}

static void rsZero(double c[3][3])
{
    int i;
    int j;
    for (i = 0; i < 3; i++) {
        for (j = 0; j < 3; j++) {
            c[i][j] = 0.0;
        }
    }
}

/*
 * Store the TRANSPOSE of m as one column-major page. The assembly below forms
 * the GCRS -> ITRS product because that is the order SOFA documents and the
 * order the cookbook prints; the toolbox returns ITRS -> GCRS, which is its
 * transpose (decision D23: an orthogonal rotation has one function and the
 * inverse is the transpose). Transposing at the store costs nothing.
 */
static void rsStoreTransposedPage(const double m[3][3], double *page)
{
    int row;
    int col;
    for (col = 0; col < 3; col++) {
        for (row = 0; row < 3; row++) {
            page[3 * col + row] = m[col][row];
        }
    }
}

/*
 * CIP X, Y and the CIO locator s including the observed celestial pole
 * offsets, with the model-reference handling that finding C-2 exists for.
 * This is the ONLY place in the toolbox that decides what dX and dY are
 * referred to; cipCoordinates and rsRotationItrsToGcrs both come here, so the
 * fix has one implementation and not two (handover principle 2).
 */
static int rsCipAt(double day, double secOfDay, int cipModel,
                   double dX, double dY, double *x, double *y, double *s)
{
    double jd1;
    double jd2;
    double x06;
    double y06;
    double s06;

    rsSplitJulianDate(day, secOfDay, &jd1, &jd2);
    iauXys06a(jd1, jd2, &x06, &y06, &s06);

    if (cipModel == 2006) {
        /* The offsets are referred to IAU 2006/2000A, which is the model just
         * evaluated, so they add directly. iauXys00a is NOT called: computing
         * it here would cost a second full nutation series for nothing, which
         * is the other half of finding C-2. */
        *x = x06 + dX;
        *y = y06 + dY;
        *s = s06;
        return 0;
    }
    if (cipModel == 2000) {
        /* The offsets are referred to IAU 2000A. The observed pole is
         * X00 + dX, and the same pole expressed against the model actually
         * being used is X06 + (X00 - X06) + dX. */
        double x00;
        double y00;
        double s00;
        iauXys00a(jd1, jd2, &x00, &y00, &s00);
        *x = x06 + (x00 - x06) + dX;
        *y = y06 + (y00 - y06) + dY;
        *s = s06;
        return 0;
    }
    return -1;
}

/*
 * One CIP sample, from the model or from a precomputed panel (prompt P19b).
 *
 * The alternative was a second copy of rsRotationItrsToGcrs taking X, Y and s.
 * That would have put two implementations of the CIO-based transformation in
 * one file, differing only in three lines, and the toolbox has recorded three
 * separate occasions on which two implementations of the same thing drifted
 * apart. The rotation is assembled ONCE below; only the source of the CIP
 * changes, and it changes here.
 *
 * cipX, cipY, cipS  NULL to evaluate the model, or [3n] arrays blocked exactly
 *                   as xp and dX are - sample j of epoch k at [j*n + k].
 */
static int rsCipSample(const double *cipX, const double *cipY, const double *cipS,
                       int n, int k, int sample,
                       double day, double secOfDay, int cipModel,
                       double dXv, double dYv,
                       double *x, double *y, double *s)
{
    if (cipX != NULL) {
        size_t index = (size_t)sample * (size_t)n + (size_t)k;
        *x = cipX[index];
        *y = cipY[index];
        *s = cipS[index];
        return 0;
    }
    return rsCipAt(day, secOfDay, cipModel, dXv, dYv, x, y, s);
}

int rsCipCoordinates(int n, const double *day, const double *secOfDay,
                     int cipModel, const double *dX, const double *dY,
                     double *x, double *y, double *s)
{
    int k;

    if (cipModel != 2006 && cipModel != 2000) {
        return -1;
    }

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double ox = (dX != NULL) ? dX[k] : 0.0;
        double oy = (dY != NULL) ? dY[k] : 0.0;
        (void) rsCipAt(day[k], secOfDay[k], cipModel, ox, oy,
                       &x[k], &y[k], &s[k]);
    }

    return 0;
}

void rsCelestialToIntermediateMatrix(int n, const double *x, const double *y,
                                     const double *s, double *matrices)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double rc2i[3][3];
        iauC2ixys(x[k], y[k], s[k], rc2i);
        rsStorePage(rc2i, &matrices[9 * (size_t)k]);
    }
}

void rsGreenwichSiderealTime(int n, const double *ut1Day, const double *ut1Sec,
                             const double *ttDay, const double *ttSec,
                             int apparent, double *gst)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double u1;
        double u2;
        double t1;
        double t2;
        rsSplitJulianDate(ut1Day[k], ut1Sec[k], &u1, &u2);
        rsSplitJulianDate(ttDay[k], ttSec[k], &t1, &t2);
        gst[k] = apparent ? iauGst06a(u1, u2, t1, t2)
                          : iauGmst06(u1, u2, t1, t2);
    }
}

void rsEquinoxNutationMatrix(int n, const double *ttDay, const double *ttSec,
                             double *matrices)
{
    int k;

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double t1;
        double t2;
        double rnpb[3][3];
        rsSplitJulianDate(ttDay[k], ttSec[k], &t1, &t2);
        iauPnm06a(t1, t2, rnpb);
        rsStorePage(rnpb, &matrices[9 * (size_t)k]);
    }
}

int rsRotationItrsToGcrs(int n,
                         const double *ttDay, const double *ttSec,
                         const double *ut1Day, const double *ut1Sec,
                         const double *xp, const double *yp,
                         const double *dX, const double *dY,
                         const double *omega,
                         int cipModel, int derivativeOrder, double step,
                         double *r, double *rdot, double *rddot)
{
    /* The model path is the precomputed path with no panel supplied. There is
     * one assembly and one set of tests behind both. */
    return rsRotationItrsToGcrsFromCip(n, ttDay, ttSec, ut1Day, ut1Sec,
        xp, yp, dX, dY, omega, NULL, NULL, NULL,
        cipModel, derivativeOrder, step, r, rdot, rddot);
}

int rsRotationItrsToGcrsFromCip(int n,
                         const double *ttDay, const double *ttSec,
                         const double *ut1Day, const double *ut1Sec,
                         const double *xp, const double *yp,
                         const double *dX, const double *dY,
                         const double *omega,
                         const double *cipX, const double *cipY,
                         const double *cipS,
                         int cipModel, int derivativeOrder, double step,
                         double *r, double *rdot, double *rddot)
{
    int k;

    /* cipModel is unread when a panel is supplied - the offsets are already in
     * it - but it is still VALIDATED, so that a caller cannot pass nonsense on
     * the interpolated path and have it start meaning something the day the
     * panel is left out. */
    if (cipModel != 2006 && cipModel != 2000) {
        return -1;
    }
    if (derivativeOrder < 0 || derivativeOrder > 2) {
        return -2;
    }
    if (derivativeOrder > 0 && !(step > 0.0)) {
        return -3;
    }
    /* All three or none. Two of them is a caller half way through a change,
     * and the failure would be silent: the rotation would take X and Y from
     * the panel and s from the model, which differ by microarcseconds and
     * would look like a tolerance problem rather than a wiring one. */
    {
        int supplied = (cipX != NULL) + (cipY != NULL) + (cipS != NULL);
        if (supplied != 0 && supplied != 3) {
            return -4;
        }
    }

#ifdef _OPENMP
    #pragma omp parallel for schedule(static) num_threads(rsGetMaxThreads()) \
        if (n > RS_PARALLEL_THRESHOLD)
#endif
    for (k = 0; k < n; k++) {
        double q[3][3];
        double w[3][3];
        double z[3][3];
        double t[3][3];
        double tmp[3][3];
        double theta;
        double u1;
        double u2;
        double cx;
        double cy;
        double cs;
        double sp;
        double j1;
        double j2;

        rsSplitJulianDate(ut1Day[k], ut1Sec[k], &u1, &u2);
        theta = iauEra00(u1, u2);
        rsRotationZ(theta, z);

        /* Sample 1 of the three is the epoch itself; with no derivative
         * requested it is the only one evaluated, which is the whole of the
         * nargout gating this function offers. Index j*n + k selects sample j,
         * so MATLAB passes an n-by-3 array and nothing is transposed here. */
        (void) rsCipSample(cipX, cipY, cipS, n, k, 1,
                           ttDay[k], ttSec[k], cipModel,
                           dX[n + k], dY[n + k], &cx, &cy, &cs);
        iauC2ixys(cx, cy, cs, q);

        rsSplitJulianDate(ttDay[k], ttSec[k], &j1, &j2);
        sp = iauSp00(j1, j2);
        iauPom00(xp[n + k], yp[n + k], sp, w);

        rsMultiply(z, q, tmp);
        rsMultiply(w, tmp, t);
        rsStoreTransposedPage(t, &r[9 * (size_t)k]);

        if (derivativeOrder >= 1) {
            double qm[3][3];
            double qp[3][3];
            double wm[3][3];
            double wp[3][3];
            double qdot[3][3];
            double wdot[3][3];
            double zdot[3][3];
            double term[3][3];
            double acc[3][3];
            int i;
            int j;

            rsCipSample(cipX, cipY, cipS, n, k, 0,
                        ttDay[k], ttSec[k] - step, cipModel, dX[k], dY[k],
                        &cx, &cy, &cs);
            iauC2ixys(cx, cy, cs, qm);
            rsCipSample(cipX, cipY, cipS, n, k, 2,
                        ttDay[k], ttSec[k] + step, cipModel,
                        dX[2 * n + k], dY[2 * n + k], &cx, &cy, &cs);
            iauC2ixys(cx, cy, cs, qp);

            rsSplitJulianDate(ttDay[k], ttSec[k] - step, &j1, &j2);
            iauPom00(xp[k], yp[k], iauSp00(j1, j2), wm);
            rsSplitJulianDate(ttDay[k], ttSec[k] + step, &j1, &j2);
            iauPom00(xp[2 * n + k], yp[2 * n + k], iauSp00(j1, j2), wp);

            for (i = 0; i < 3; i++) {
                for (j = 0; j < 3; j++) {
                    qdot[i][j] = (qp[i][j] - qm[i][j]) / (2.0 * step);
                    wdot[i][j] = (wp[i][j] - wm[i][j]) / (2.0 * step);
                }
            }
            rsRotationZFirstDerivative(theta, zdot);
            for (i = 0; i < 3; i++) {
                for (j = 0; j < 3; j++) {
                    zdot[i][j] *= omega[k];
                }
            }

            /* Tdot = Wdot R3 Q + W R3dot Q + W R3 Qdot */
            rsZero(acc);
            rsMultiply(z, q, tmp);
            rsMultiply(wdot, tmp, term);
            rsAccumulate(acc, term, 1.0);
            rsMultiply(zdot, q, tmp);
            rsMultiply(w, tmp, term);
            rsAccumulate(acc, term, 1.0);
            rsMultiply(z, qdot, tmp);
            rsMultiply(w, tmp, term);
            rsAccumulate(acc, term, 1.0);
            rsStoreTransposedPage(acc, &rdot[9 * (size_t)k]);

            if (derivativeOrder >= 2) {
                double qddot[3][3];
                double wddot[3][3];
                double zddot[3][3];

                for (i = 0; i < 3; i++) {
                    for (j = 0; j < 3; j++) {
                        qddot[i][j] = (qp[i][j] - 2.0 * q[i][j] + qm[i][j])
                            / (step * step);
                        wddot[i][j] = (wp[i][j] - 2.0 * w[i][j] + wm[i][j])
                            / (step * step);
                    }
                }
                /* R3ddot = omegadot * dR3/dtheta + omega^2 * d2R3/dtheta2, and
                 * the first term is dropped: omegadot from the observed change
                 * in length of day is of order 1e-17 rad/s^2 against
                 * omega^2 = 5.3e-9, that is 9 orders down. Stated in the help
                 * text of rotationItrsToGcrs rather than left implicit. */
                rsRotationZSecondDerivative(theta, zddot);
                for (i = 0; i < 3; i++) {
                    for (j = 0; j < 3; j++) {
                        zddot[i][j] *= omega[k] * omega[k];
                    }
                }

                rsZero(acc);
                rsMultiply(z, q, tmp);
                rsMultiply(wddot, tmp, term);
                rsAccumulate(acc, term, 1.0);
                rsMultiply(zddot, q, tmp);
                rsMultiply(w, tmp, term);
                rsAccumulate(acc, term, 1.0);
                rsMultiply(z, qddot, tmp);
                rsMultiply(w, tmp, term);
                rsAccumulate(acc, term, 1.0);
                rsMultiply(zdot, q, tmp);
                rsMultiply(wdot, tmp, term);
                rsAccumulate(acc, term, 2.0);
                rsMultiply(z, qdot, tmp);
                rsMultiply(wdot, tmp, term);
                rsAccumulate(acc, term, 2.0);
                rsMultiply(zdot, qdot, tmp);
                rsMultiply(w, tmp, term);
                rsAccumulate(acc, term, 2.0);
                rsStoreTransposedPage(acc, &rddot[9 * (size_t)k]);
            }
        }
    }

    return 0;
}
