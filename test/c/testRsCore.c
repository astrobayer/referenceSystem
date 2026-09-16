/*
 * testRsCore.c
 * ------------
 * Standalone test suite for mex/rsCore.c. It is built and run with plain gcc
 * by test/c/runStandaloneTests.sh and never links against mex.h, which is the
 * property handover section C.4 requires of the core: the arithmetic can be
 * validated without MATLAB in the loop.
 *
 * Every expected value below is an independently published literal, never a
 * number produced by this toolbox (handover section D.1, category reference):
 *
 *   - IAU SOFA release 20231011 validation program t_sofa_c.c, for iauDat,
 *     iauEra00, iauSp00, iauPom00, iauXys06a, iauXys00a, iauDtdb and the
 *     fourteen iauFa*03 arguments;
 *   - IERS Conventions (2010) software FUNDARG.F, published test case at
 *     T = 0.07995893223819302 centuries (MJD 54465), for the Delaunay set;
 *   - the Astronomical Almanac three-term approximation of TDB - TT, as the
 *     independent cross-check that catches the v1 defect C-1.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:25 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "rsCore.h"
#include "sofa/sofam.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* M_PI is not in strict C99, so the one constant these tests need is
 * stated locally rather than depending on a compiler extension. */
static const double testPi = 3.14159265358979323846264338328;

static int testCount = 0;
static int failCount = 0;

static void checkClose(double actual, double expected, double tolerance,
                       const char *name)
{
    double difference = fabs(actual - expected);
    testCount++;
    if (!(difference <= tolerance)) {
        failCount++;
        printf("  FAIL  %-46s got %.17g want %.17g (|d| = %.3e > %.3e)\n",
               name, actual, expected, difference, tolerance);
    } else {
        printf("  PASS  %-46s |d| = %.3e\n", name, difference);
    }
}

static void checkInt(int actual, int expected, const char *name)
{
    testCount++;
    if (actual != expected) {
        failCount++;
        printf("  FAIL  %-46s got %d want %d\n", name, actual, expected);
    } else {
        printf("  PASS  %-46s = %d\n", name, actual);
    }
}

static void checkTrue(int condition, const char *name)
{
    testCount++;
    if (!condition) {
        failCount++;
        printf("  FAIL  %-46s condition false\n", name);
    } else {
        printf("  PASS  %-46s\n", name);
    }
}

/* ---------------------------------------------------------------------- */

static void testDeltaAt(void)
{
    /* SOFA t_sofa_c.c, t_dat: 2003-06-01 -> 32 s, 2008-01-17 -> 33 s,
     * 2017-09-01 -> 37 s. The MJDs of those calendar dates are 52791,
     * 54482 and 57997. */
    double day[3] = {52791.0, 54482.0, 57997.0};
    double secOfDay[3] = {0.0, 0.0, 0.0};
    double deltaAt[3] = {0.0, 0.0, 0.0};
    int status[3] = {0, 0, 0};
    int worst;

    puts("rsDeltaAt");
    worst = rsDeltaAt(3, day, secOfDay, deltaAt, status);
    checkInt(worst, 0, "rsDeltaAt worst status");
    checkClose(deltaAt[0], 32.0, 0.0, "dAT 2003-06-01");
    checkClose(deltaAt[1], 33.0, 0.0, "dAT 2008-01-17");
    checkClose(deltaAt[2], 37.0, 0.0, "dAT 2017-09-01");

    /* A positive leap-second instant: UTC 2016-12-31 23:59:60.5 is day 57753
     * with secOfDay 86400.5. dAT must still be the pre-step value, 36 s. */
    {
        double leapDay = 57753.0;
        double leapSec = 86400.5;
        double leapValue = 0.0;
        int leapStatus = 0;
        rsDeltaAt(1, &leapDay, &leapSec, &leapValue, &leapStatus);
        checkInt(leapStatus, 0, "leap-second instant status");
        checkClose(leapValue, 36.0, 0.0, "dAT during the 2016 leap second");
    }

    /* The documented trap: a pre-1960 epoch returns +1, not a negative code,
     * and leaves dAT at zero. This test pins the behaviour so that a future
     * SOFA release which changed it would be caught here rather than by a
     * user obtaining a silent zero. */
    {
        double earlyDay = 30000.0;   /* 1941-01-06 */
        double earlySec = 0.0;
        double earlyValue = -999.0;
        int earlyStatus = 0;
        int code = rsDeltaAt(1, &earlyDay, &earlySec, &earlyValue, &earlyStatus);
        checkInt(code, 1, "pre-1960 epoch reports the dubious-year code");
        checkClose(earlyValue, 0.0, 0.0, "pre-1960 dAT is zero, not a value");
    }

    /* A day number that is not a representable calendar date is rejected here
     * rather than by SOFA, with our own code -6, and leaves the output alone
     * rather than filling it with NaN (section C.6 rule 5, pushed into C). */
    {
        double badDay = -3.0e6;
        double badSec = 0.0;
        double badValue = -999.0;
        int badStatus = 0;
        int code = rsDeltaAt(1, &badDay, &badSec, &badValue, &badStatus);
        checkInt(code, -6, "unrepresentable day reports -6");
        checkClose(badValue, -999.0, 0.0, "output untouched on failure");
    }
}

static void testTdbMinusTt(void)
{
    /* The Astronomical Almanac three-term approximation, an independent
     * published formula. Agreement at the ten-microsecond level is what
     * distinguishes a correct series from the corrupted v1 table, which is
     * in error by up to 1.7e-4 s over 2020-2024 (handover finding C-1). */
    const double mjd[4] = {51544.5, 55197.0, 58849.0, 60310.0};
    double day[4];
    double secOfDay[4];
    double value[4];
    int k;

    puts("rsTdbMinusTt");
    for (k = 0; k < 4; k++) {
        day[k] = floor(mjd[k]);
        secOfDay[k] = (mjd[k] - day[k]) * 86400.0;
    }
    rsTdbMinusTt(4, day, secOfDay, value);

    for (k = 0; k < 4; k++) {
        double daysFromJ2000 = mjd[k] - 51544.5;
        double g = (357.53 + 0.9856003 * daysFromJ2000) * (testPi / 180.0);
        double l = (246.11 + 0.90251792 * daysFromJ2000) * (testPi / 180.0);
        double almanac = 0.001657 * sin(g) + 0.000022 * sin(l);
        char name[80];
        snprintf(name, sizeof(name), "TDB-TT vs almanac at MJD %.1f", mjd[k]);
        checkClose(value[k], almanac, 3.0e-5, name);
        snprintf(name, sizeof(name), "TDB-TT bounded at MJD %.1f", mjd[k]);
        checkTrue(fabs(value[k]) < 2.0e-3, name);
    }
}

static void testEarthOrientationPrimitives(void)
{
    double day;
    double secOfDay = 0.0;
    double x;
    double y;
    double s;
    double era;
    double sp;

    puts("rsCipXys / rsEarthRotationAngle / rsTioLocator / rsPolarMotionMatrix");

    /* SOFA t_xys06a and t_xys00a at TT MJD 53736. */
    day = 53736.0;
    rsCipXys(1, &day, &secOfDay, 2006, &x, &y, &s);
    checkClose(x, 0.5791308482835292617e-3, 1e-14, "iauXys06a X");
    checkClose(y, 0.4020580099454020310e-4, 1e-15, "iauXys06a Y");
    checkClose(s, -0.1220032294164579896e-7, 1e-18, "iauXys06a s");

    rsCipXys(1, &day, &secOfDay, 2000, &x, &y, &s);
    checkClose(x, 0.5791308472168152904e-3, 1e-14, "iauXys00a X");
    checkClose(y, 0.4020595661591500259e-4, 1e-15, "iauXys00a Y");
    checkClose(s, -0.1220040848471549623e-7, 1e-18, "iauXys00a s");

    checkInt(rsCipXys(1, &day, &secOfDay, 1980, &x, &y, &s), -1,
             "unknown CIP model rejected");

    /* SOFA t_era00 at UT1 MJD 54388. */
    day = 54388.0;
    rsEarthRotationAngle(1, &day, &secOfDay, &era);
    checkClose(era, 0.4022837240028158102, 1e-12, "iauEra00");

    /* SOFA t_sp00 at TT MJD 52541. */
    day = 52541.0;
    rsTioLocator(1, &day, &secOfDay, &sp);
    checkClose(sp, -0.6216698469981019309e-11, 1e-12, "iauSp00");

    /* SOFA t_pom00. The page is column-major, so element (row, col) is at
     * 3*col + row; the published values are quoted row by row. */
    {
        double xp = 2.55060238e-7;
        double yp = 1.860359247e-6;
        double spValue = -0.1367174580728891460e-10;
        double page[9];
        rsPolarMotionMatrix(1, &xp, &yp, &spValue, page);
        checkClose(page[0 + 3 * 0], 0.9999999999999674721, 1e-12, "pom00 (1,1)");
        checkClose(page[0 + 3 * 1], -0.1367174580728846989e-10, 1e-16, "pom00 (1,2)");
        checkClose(page[0 + 3 * 2], 0.2550602379999972345e-6, 1e-16, "pom00 (1,3)");
        checkClose(page[1 + 3 * 0], 0.1414624947957029801e-10, 1e-16, "pom00 (2,1)");
        checkClose(page[1 + 3 * 1], 0.9999999999982695317, 1e-12, "pom00 (2,2)");
        checkClose(page[1 + 3 * 2], -0.1860359246998866389e-5, 1e-16, "pom00 (2,3)");
        checkClose(page[2 + 3 * 0], -0.2550602379741215021e-6, 1e-16, "pom00 (3,1)");
        checkClose(page[2 + 3 * 1], 0.1860359247002414021e-5, 1e-16, "pom00 (3,2)");
        checkClose(page[2 + 3 * 2], 0.9999999999982370039, 1e-12, "pom00 (3,3)");
    }
}

static void testFundamentalArguments(void)
{
    /* SOFA t_fa*03 at T = 0.80 centuries, i.e. TT MJD 51544.5 + 29220 =
     * 80764.5, which is day 80764 and 43200 s exactly. */
    double day = 80764.0;
    double secOfDay = 43200.0;
    double fa[RS_FA_COLUMNS];

    puts("rsFundamentalArguments");
    rsFundamentalArguments(1, &day, &secOfDay, NULL, NULL, 0, fa);

    checkClose(fa[RS_FA_L], 5.132369751108684150, 1e-12, "iauFal03 at T=0.80");
    checkClose(fa[RS_FA_LPRIME], 6.226797973505507345, 1e-12, "iauFalp03 at T=0.80");
    checkClose(fa[RS_FA_F], 0.2597711366745499518, 1e-12, "iauFaf03 at T=0.80");
    checkClose(fa[RS_FA_D], 1.946709205396925672, 1e-12, "iauFad03 at T=0.80");
    /* iauFaom03 returns -5.973618440951302183; wrapped to [0, 2pi). */
    checkClose(fa[RS_FA_OMEGA], -5.973618440951302183 + 2.0 * testPi, 1e-12,
               "iauFaom03 at T=0.80, wrapped");
    checkClose(fa[RS_FA_LME], 5.417338184297289661, 1e-12, "iauFame03 at T=0.80");
    checkClose(fa[RS_FA_LVE], 3.424900460533758000, 1e-12, "iauFave03 at T=0.80");
    checkClose(fa[RS_FA_LE], 1.744713738913081846, 1e-12, "iauFae03 at T=0.80");
    checkClose(fa[RS_FA_LMA], 3.275506840277781492, 1e-12, "iauFama03 at T=0.80");
    checkClose(fa[RS_FA_LJ], 5.275711665202481138, 1e-12, "iauFaju03 at T=0.80");
    checkClose(fa[RS_FA_LSA], 5.371574539440827046, 1e-12, "iauFasa03 at T=0.80");
    checkClose(fa[RS_FA_LU], 5.180636450180413523, 1e-12, "iauFaur03 at T=0.80");
    checkClose(fa[RS_FA_LNE], 2.079343830860413523, 1e-12, "iauFane03 at T=0.80");
    checkClose(fa[RS_FA_PA], 0.1950884762240000000e-1, 1e-12, "iauFapa03 at T=0.80");
    checkTrue(isnan(fa[RS_FA_TAU]), "tau is NaN without UT1");

    /* IERS Conventions (2010) FUNDARG.F published test case, MJD 54465 TT.
     * This is the decision D27 agreement measurement: the toolbox uses SOFA
     * publicly, the ported IERS routines keep their own FUNDARG internally,
     * and the two are required to agree. */
    {
        double faDay = 54465.0;
        double faSec = 0.0;
        double published[5] = {2.291187512612069099, 6.212931111003726414,
                               3.658025792050572989, 4.554139562402433228,
                               -0.5167379217231804489 + 2.0 * testPi};
        double actual[RS_FA_COLUMNS];
        rsFundamentalArguments(1, &faDay, &faSec, NULL, NULL, 0, actual);
        checkClose(actual[RS_FA_L], published[0], 1e-12, "FUNDARG L");
        checkClose(actual[RS_FA_LPRIME], published[1], 1e-12, "FUNDARG LP");
        checkClose(actual[RS_FA_F], published[2], 1e-12, "FUNDARG F");
        checkClose(actual[RS_FA_D], published[3], 1e-12, "FUNDARG D");
        checkClose(actual[RS_FA_OMEGA], published[4], 1e-12, "FUNDARG OM");
    }

    /* Doodson derivations, recomputed here from the wrapped Delaunay
     * arguments by the IERS Conventions Ch. 6 definitions. */
    {
        double doodsonDay = 54465.0;
        double doodsonSec = 43200.0;
        double ut1Day = 54465.0;
        double ut1Sec = 43200.0 - 65.0;
        double value[RS_FA_COLUMNS];
        double twoPi = 2.0 * testPi;
        double expectedS;
        rsFundamentalArguments(1, &doodsonDay, &doodsonSec, &ut1Day, &ut1Sec, 1, value);
        expectedS = fmod(value[RS_FA_F] + value[RS_FA_OMEGA], twoPi);
        if (expectedS < 0.0) {
            expectedS += twoPi;
        }
        checkClose(value[RS_FA_S], expectedS, 1e-12, "Doodson s = F + Omega");
        checkTrue(!isnan(value[RS_FA_TAU]), "tau is finite with UT1");
        checkTrue(value[RS_FA_TAU] >= 0.0 && value[RS_FA_TAU] < twoPi,
                  "tau wrapped to [0, 2pi)");
        checkTrue(value[RS_FA_NPRIME] >= 0.0 && value[RS_FA_NPRIME] < twoPi,
                  "nPrime wrapped to [0, 2pi)");
    }
}

static void testThreadReproducibility(void)
{
    /* Decision D31: the per-epoch loops carry no reduction, so results must be
     * bit-identical at any thread count. Compared with memcmp, not with a
     * tolerance, because a tolerance would hide exactly the reduction-order
     * drift this test exists to catch. */
    enum { N = 4096 };
    static double day[N];
    static double secOfDay[N];
    static double serial[N];
    static double parallel[N];
    int k;

    puts("thread reproducibility (D31)");
    for (k = 0; k < N; k++) {
        day[k] = 55000.0 + k;
        secOfDay[k] = 43200.0 + 0.001 * k;
    }

    rsSetMaxThreads(1);
    rsTdbMinusTt(N, day, secOfDay, serial);
    rsSetMaxThreads(0);
    rsTdbMinusTt(N, day, secOfDay, parallel);
    checkTrue(memcmp(serial, parallel, sizeof(serial)) == 0,
              "rsTdbMinusTt bit-identical, 1 vs N threads");

    rsSetMaxThreads(1);
    rsEarthRotationAngle(N, day, secOfDay, serial);
    rsSetMaxThreads(0);
    rsEarthRotationAngle(N, day, secOfDay, parallel);
    checkTrue(memcmp(serial, parallel, sizeof(serial)) == 0,
              "rsEarthRotationAngle bit-identical, 1 vs N threads");

    rsSetMaxThreads(0);
}

/* ---------------------------------------------------------------------- */
/* Earth rotation, ITRS to GCRS (prompt P9)                                */
/* ---------------------------------------------------------------------- */

/*
 * All literals below come from the SOFA cookbook "SOFA Tools for Earth
 * Attitude" (sofa_pn_c.pdf, release 20231011), worked example of
 * 2007-04-05 12:00:00 UTC. The two CIP branches are checked against DIFFERENT
 * sections of that document -- section 5.3 for the IAU 2000A-referred offsets
 * and section 5.5 for the IAU 2006/2000A-referred ones -- because the point of
 * finding C-2 is that the same observed pole is reached from either, and a
 * test that used one literal for both could not show it.
 */
#define RS_TEST_AS2R 4.848136811095359935899141e-6

static void testCipCoordinates(void)
{
    double day = 54195.0;
    double sec = 43265.184;          /* 12:00:00 UTC + 32.184 s + 33 s dAT */
    double x;
    double y;
    double s;
    double dx06 =  0.1750e-3 * RS_TEST_AS2R;
    double dy06 = -0.2259e-3 * RS_TEST_AS2R;
    double dx00 =  0.1725e-3 * RS_TEST_AS2R;
    double dy00 = -0.2650e-3 * RS_TEST_AS2R;
    double x2;
    double y2;
    double s2;

    puts("\nCIP coordinates with the observed pole offsets (finding C-2)");

    rsCipCoordinates(1, &day, &sec, 2006, &dx06, &dy06, &x, &y, &s);
    checkClose(x, 0.000712264729599, 5e-15, "cookbook 5.5 X");
    checkClose(y, 0.000044385250426, 5e-15, "cookbook 5.5 Y");
    checkClose(s / RS_TEST_AS2R, -0.002200475, 5e-9, "cookbook 5.5 s");

    rsCipCoordinates(1, &day, &sec, 2000, &dx00, &dy00, &x2, &y2, &s2);
    checkClose(x2, 0.000712264729708, 5e-15, "cookbook 5.3 X, bias applied");
    checkClose(y2, 0.000044385250265, 5e-15, "cookbook 5.3 Y, bias applied");

    /* The C-2 statement itself: one pole, two parameterisations, one answer.
     * The 1.1e-13 rad residual is the cookbook's own difference between its
     * sections 5.3 and 5.5, which is the rounding of the published offsets to
     * four decimal places of a milliarcsecond, not an error in this code. */
    checkTrue(fabs(x - x2) < 3e-13, "both CIP models reach the same X");
    checkTrue(fabs(y - y2) < 3e-13, "both CIP models reach the same Y");

    checkInt(rsCipCoordinates(1, &day, &sec, 1999, NULL, NULL, &x, &y, &s), -1,
             "unknown CIP model refused");

    /* Passing NULL offsets must mean zero offsets and not undefined behaviour. */
    rsCipCoordinates(1, &day, &sec, 2006, NULL, NULL, &x, &y, &s);
    checkClose(x, 0.000712264729599 - dx06, 5e-15, "NULL offsets mean zero");
}

static void testRotationAssembly(void)
{
    double ttDay = 54195.0;
    double ttSec = 43265.184;
    double ut1Day = 54195.0;
    double ut1Sec = 43199.927926315;   /* 12:00:00 UTC - 0.072073685 s */
    double xp[3];
    double yp[3];
    double dX[3];
    double dY[3];
    /* UT1 - TAI held constant: the rate is the ERA slope itself. */
    double ut1MinusTai[3] = {-33.072073685, -33.072073685, -33.072073685};
    double r[9];
    double rdot[9];
    double rddot[9];
    /* Cookbook section 5.5, celestial to terrestrial matrix including polar
     * motion. The toolbox returns its transpose. */
    static const double want[3][3] = {
        { 0.973104317697535,  0.230363826239128, -0.000703163482198},
        {-0.230363800456037,  0.973104570632801,  0.000118545366625},
        { 0.000711560162668,  0.000046626403995,  0.999999745754024}};
    double worst = 0.0;
    double orthogonality = 0.0;
    double symmetry = 0.0;
    int row;
    int col;
    int m;
    double poleRate = 1.229 * RS_TEST_AS2R / (365.25 * 86400.0);

    puts("\nITRS to GCRS assembly and its derivatives");

    for (m = 0; m < 3; m++) {
        double dt = (m - 1) * 200.0;
        xp[m] = 0.0349282 * RS_TEST_AS2R + poleRate * dt;
        yp[m] = 0.4833163 * RS_TEST_AS2R - poleRate * dt;
        dX[m] =  0.1750e-3 * RS_TEST_AS2R;
        dY[m] = -0.2259e-3 * RS_TEST_AS2R;
    }

    checkInt(rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
             dX, dY, ut1MinusTai, 2006, 2, 200.0, r, rdot, rddot), 0,
             "assembly returns success");

    for (row = 0; row < 3; row++) {
        for (col = 0; col < 3; col++) {
            /* r holds ITRS -> GCRS column-major, so element (row, col) of the
             * GCRS -> ITRS matrix is r[3*row + col]. */
            double d = fabs(r[3 * row + col] - want[row][col]);
            if (d > worst) {
                worst = d;
            }
        }
    }
    checkTrue(worst < 5e-15, "cookbook 5.5 rotation matrix reproduced");

    for (row = 0; row < 3; row++) {
        for (col = 0; col < 3; col++) {
            double sum = 0.0;
            double rate = 0.0;
            for (m = 0; m < 3; m++) {
                sum += r[3 * m + row] * r[3 * m + col];
                rate += rdot[3 * m + row] * r[3 * m + col]
                      + r[3 * m + row] * rdot[3 * m + col];
            }
            sum -= (row == col) ? 1.0 : 0.0;
            if (fabs(sum) > orthogonality) {
                orthogonality = fabs(sum);
            }
            if (fabs(rate) > symmetry) {
                symmetry = fabs(rate);
            }
        }
    }
    checkTrue(orthogonality < 1e-15, "R'R - I below 1e-15");
    /* d(R'R)/dt = 0 catches a sign or transposition error in Rdot that no
     * magnitude comparison would, and it holds whatever step was used. */
    checkTrue(symmetry < 1e-17, "Rdot' R + R' Rdot vanishes");

    /* nargout gating: with derivativeOrder 0 the derivative buffers must not
     * be touched, so a NULL pointer must be safe. */
    checkInt(rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
             dX, dY, ut1MinusTai, 2006, 0, 0.0, r, NULL, NULL), 0,
             "order 0 accepts NULL derivative buffers and a zero step");

    checkInt(rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
             dX, dY, ut1MinusTai, 2006, 1, 0.0, r, rdot, NULL), -3,
             "a non-positive step with derivatives is refused");
    checkInt(rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
             dX, dY, ut1MinusTai, 1999, 1, 200.0, r, rdot, NULL), -1,
             "assembly refuses an unknown CIP model");
    checkInt(rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
             dX, dY, ut1MinusTai, 2006, 3, 200.0, r, rdot, rddot), -2,
             "assembly refuses a derivative order above 2");
}

/*
 * D128: Rdot AND Rddot ARE THE TIME DERIVATIVES OF R. The oracle is R itself,
 * evaluated at t - d, t and t + d with UT1 - TAI following the same quadratic
 * the three samples describe, and differenced. The rate and its change are
 * exaggerated - 1e-6 s/s and 1e-9 s/s^2, against about 2.5e-8 and 5e-13 in
 * the Earth - so that each term is far above the difference's own error, and
 * the check fails if either is dropped: without the rate term Rdot misses by
 * omega * 1e-6 = 7.3e-11 1/s, without omegadot Rddot misses by 7.3e-14 1/s^2.
 *
 * Tolerances: Rdot 1e-12 1/s bounds the d = 0.5 s difference's truncation,
 * omega^3 d^2 / 6 = 1.6e-14, and the core's 200 s CIP difference; Rddot
 * 5e-15 1/s^2 bounds the d = 10 s second difference's truncation,
 * omega^4 d^2 / 12 = 2.4e-16, and its roundoff, 4 eps / d^2 = 8.9e-18.
 */
static void rsRotationAt(double shift, double rate, double acceleration,
                         double step, int order, double *r, double *rdot,
                         double *rddot)
{
    double ttDay = 54195.0;
    double ttSec = 43265.184 + shift;
    double ut1Day = 54195.0;
    double base = -33.072073685;
    double ut1Sec = ttSec - 32.184 + base + rate * shift
        + 0.5 * acceleration * shift * shift;
    double poleRate = 1.229 * RS_TEST_AS2R / (365.25 * 86400.0);
    double xp[3], yp[3], dX[3], dY[3], ut1MinusTai[3];
    int m;

    for (m = 0; m < 3; m++) {
        double dt = shift + (m - 1) * step;
        xp[m] = 0.0349282 * RS_TEST_AS2R + poleRate * dt;
        yp[m] = 0.4833163 * RS_TEST_AS2R - poleRate * dt;
        dX[m] = 0.1750e-3 * RS_TEST_AS2R;
        dY[m] = -0.2259e-3 * RS_TEST_AS2R;
        ut1MinusTai[m] = base + rate * dt + 0.5 * acceleration * dt * dt;
    }
    (void)rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
                               dX, dY, ut1MinusTai, 2006, order, step,
                               r, rdot, rddot);
}

static void testRotationRateFollowsUt1(void)
{
    const double rate = 1e-6;
    const double acceleration = 1e-9;
    const double step = 200.0;
    double r[9], rdot[9], rddot[9];
    double before[9], after[9], unused[9];
    double worstRate = 0.0;
    double worstAcceleration = 0.0;
    int k;

    puts("\nRdot and Rddot against differences of R (decision D128)");

    rsRotationAt(0.0, rate, acceleration, step, 2, r, rdot, rddot);

    rsRotationAt(-0.5, rate, acceleration, step, 0, before, unused, unused);
    rsRotationAt(0.5, rate, acceleration, step, 0, after, unused, unused);
    for (k = 0; k < 9; k++) {
        double d = fabs(rdot[k] - (after[k] - before[k]) / 1.0);
        if (d > worstRate) {
            worstRate = d;
        }
    }
    printf("  Rdot against a 0.5 s difference of R: %.3g 1/s\n", worstRate);
    checkTrue(worstRate < 1e-12, "Rdot is the derivative of R, UT1 rate included");

    rsRotationAt(-10.0, rate, acceleration, step, 0, before, unused, unused);
    rsRotationAt(10.0, rate, acceleration, step, 0, after, unused, unused);
    for (k = 0; k < 9; k++) {
        double d = fabs(rddot[k] - (after[k] - 2.0 * r[k] + before[k]) / 100.0);
        if (d > worstAcceleration) {
            worstAcceleration = d;
        }
    }
    printf("  Rddot against a 10 s second difference of R: %.3g 1/s^2\n",
           worstAcceleration);
    checkTrue(worstAcceleration < 5e-15,
              "Rddot is the second derivative of R, omegadot included");
}

static void testEquinoxCrossCheck(void)
{
    /* Risk R13b. The equinox route and the CIO route describe the same
     * rotation and must agree; the toolbox transforms through the CIO and
     * keeps the classical route as a validation asset only.
     *
     * Rz(-(ERA - GAST)) * NPB must equal the CIO based GCRS -> CIRS matrix. */
    int k;
    double worst = 0.0;

    puts("\nEquinox versus CIO cross-check (risk R13b)");

    for (k = 0; k < 12; k++) {
        double day = 47892.0 + k * 1826.0;
        double sec = 43200.0;
        double x;
        double y;
        double s;
        double q[9];
        double npb[9];
        double era;
        double gast;
        double angle;
        double c;
        double sn;
        int row;

        rsCipCoordinates(1, &day, &sec, 2006, NULL, NULL, &x, &y, &s);
        rsCelestialToIntermediateMatrix(1, &x, &y, &s, q);
        rsEquinoxNutationMatrix(1, &day, &sec, npb);
        rsEarthRotationAngle(1, &day, &sec, &era);
        rsGreenwichSiderealTime(1, &day, &sec, &day, &sec, 1, &gast);

        angle = -(era - gast);
        c = cos(angle);
        sn = sin(angle);
        for (row = 0; row < 3; row++) {
            /* Rz(angle) * npb, one column at a time; column-major page. */
            double a = c * npb[3 * row + 0] + sn * npb[3 * row + 1];
            double b = -sn * npb[3 * row + 0] + c * npb[3 * row + 1];
            double da = fabs(a - q[3 * row + 0]);
            double db = fabs(b - q[3 * row + 1]);
            double dc = fabs(npb[3 * row + 2] - q[3 * row + 2]);
            if (da > worst) worst = da;
            if (db > worst) worst = db;
            if (dc > worst) worst = dc;
        }
    }
    printf("    equinox versus CIO worst element %.3e rad = %.4f uas\n",
           worst, worst / RS_TEST_AS2R * 1e6);
    checkTrue(worst < 1e-14, "equinox and CIO routes agree below 1e-14");
}


/* ---------------------------------------------------------------------- */
/* Body states and the observer form of TDB - TT (prompt P22, P21)         */
/* ---------------------------------------------------------------------- */

/*
 * THE ENUM IS VALIDATED BY PHYSICS, NOT BY A SECOND LIST. ephemerisBodies.m
 * mirrors RS_BODY_* and nothing on either side of the MEX boundary can see the
 * other, so the only check with any power is one a permutation cannot pass:
 * every body is required to sit in the heliocentric distance band it alone
 * occupies. The bands are perihelion and aphelion from published elements,
 * widened a few per cent, and no two overlap except the three Earth-system
 * entries, which the lunar distance test separates instead.
 */
static void testBodyState(void)
{
    static const struct {
        int body;
        const char *name;
        double lowAu;
        double highAu;
    } band[] = {
        {RS_BODY_SUN,                 "sun",      0.000,  0.020},
        {RS_BODY_MERCURY,             "mercury",  0.290,  0.480},
        {RS_BODY_VENUS,               "venus",    0.700,  0.740},
        {RS_BODY_EARTH,               "earth",    0.975,  1.025},
        {RS_BODY_MOON,                "moon",     0.972,  1.028},
        {RS_BODY_MARS,                "mars",     1.370,  1.680},
        {RS_BODY_JUPITER,             "jupiter",  4.930,  5.470},
        {RS_BODY_SATURN,              "saturn",   8.980, 10.150},
        {RS_BODY_URANUS,              "uranus",  18.230, 20.150},
        {RS_BODY_NEPTUNE,             "neptune", 29.750, 30.400},
        {RS_BODY_EARTH_MOON_BARYCENTRE, "emb",    0.975,  1.025}
    };
    const int bandCount = (int)(sizeof(band) / sizeof(band[0]));
    double day = 60000.0;
    double sec = 43200.0;
    double sun[6];
    double state[6];
    double earth[6];
    int status[1];
    int result;
    int k;
    int j;
    char name[80];

    puts("rsBodyState");

    checkInt(RS_BODY_COUNT, bandCount, "every enum member has a band");

    result = rsBodyState(1, &day, &sec, RS_BODY_SUN, RS_ORIGIN_BARYCENTRE,
                         sun, status);
    checkInt(result, 0, "sun barycentric status");

    for (k = 0; k < bandCount; k++) {
        double squared = 0.0;
        double distance;
        rsBodyState(1, &day, &sec, band[k].body, RS_ORIGIN_BARYCENTRE,
                    state, status);
        for (j = 0; j < 3; j++) {
            double component = (band[k].body == RS_BODY_SUN)
                ? state[j] : state[j] - sun[j];
            squared += component * component;
        }
        distance = sqrt(squared) / rsAstronomicalUnit();
        snprintf(name, sizeof(name), "%s heliocentric distance in band",
                 band[k].name);
        checkTrue(distance >= band[k].lowAu && distance <= band[k].highAu, name);
    }

    /* The geocentric origin must be exactly the barycentric difference, or the
     * two origins are computing different things and only one of them is the
     * one that was checked. The bound is the roundoff of a subtraction at the
     * 1e11 m scale, not a tolerance chosen to pass. */
    rsBodyState(1, &day, &sec, RS_BODY_EARTH, RS_ORIGIN_BARYCENTRE, earth,
                status);
    rsBodyState(1, &day, &sec, RS_BODY_MARS, RS_ORIGIN_BARYCENTRE, state,
                status);
    {
        double geocentric[6];
        rsBodyState(1, &day, &sec, RS_BODY_MARS, RS_ORIGIN_GEOCENTRE,
                    geocentric, status);
        for (j = 0; j < 3; j++) {
            snprintf(name, sizeof(name), "mars geocentric = bary difference [%d]",
                     j);
            checkClose(geocentric[j], state[j] - earth[j], 1.0e-4, name);
        }
        for (j = 3; j < 6; j++) {
            snprintf(name, sizeof(name), "mars geocentric velocity [%d]", j - 3);
            checkClose(geocentric[j], state[j] - earth[j], 1.0e-9, name);
        }
    }

    /* Lunar distance separates the Moon from the Earth and from the EMB, which
     * the heliocentric bands cannot. */
    {
        double moon[6];
        double distance = 0.0;
        rsBodyState(1, &day, &sec, RS_BODY_MOON, RS_ORIGIN_GEOCENTRE, moon,
                    status);
        for (j = 0; j < 3; j++) {
            distance += moon[j] * moon[j];
        }
        distance = sqrt(distance) / 1000.0;
        checkTrue(distance > 356000.0 && distance < 407000.0,
                  "lunar geocentric distance between perigee and apogee");
    }

    /* The Earth's barycentric speed, which is the only check that would notice
     * a lost factor of 86400 in the au/day conversion while every position
     * stayed correct. */
    {
        double speed = sqrt(earth[3] * earth[3] + earth[4] * earth[4] +
                            earth[5] * earth[5]) / 1000.0;
        checkTrue(speed > 29.0 && speed < 30.6,
                  "earth barycentric speed near 30 km/s");
    }

    /* Refusals leave the caller's array alone and report rather than guess. */
    {
        double untouched[6];
        for (j = 0; j < 6; j++) {
            untouched[j] = -12345.0;
        }
        checkInt(rsBodyState(1, &day, &sec, RS_BODY_COUNT,
                             RS_ORIGIN_BARYCENTRE, untouched, status),
                 -1, "unknown body refused");
        checkInt(rsBodyState(1, &day, &sec, RS_BODY_EARTH, 7, untouched,
                             status), -2, "unknown origin refused");
        checkClose(untouched[0], -12345.0, 0.0,
                   "a refused call writes nothing");
    }

    /* Outside 1900-2100 iauEpv00 reports +1 and the state is still returned;
     * the MATLAB layer turns that into one warning per call (section C.6). */
    {
        double oldDay = -58000.0;
        checkInt(rsBodyState(1, &oldDay, &sec, RS_BODY_EARTH,
                             RS_ORIGIN_BARYCENTRE, state, status),
                 1, "epoch outside the model interval reports +1");
    }
}

/*
 * The observer form of TDB - TT. The geocentric call must be reproduced BIT FOR
 * BIT by a zero observer, because with the distance from the axis and from the
 * equator both zero the topocentric contribution vanishes identically and any
 * difference at all would mean a second series is being evaluated.
 */
static void testTdbMinusTtAtObserver(void)
{
    double day = 60000.0;
    double sec = 43200.0;
    double geocentric;
    double value;
    double zero = 0.0;
    double ut;
    double eastLongitude = 0.0;
    double equatorialRadius = 6378137.0;
    double polarRadius = 6356752.3;
    double lowest = 1.0e30;
    double highest = -1.0e30;
    double polarLowest = 1.0e30;
    double polarHighest = -1.0e30;
    int k;

    puts("rsTdbMinusTtAtObserver");

    rsTdbMinusTt(1, &day, &sec, &geocentric);
    rsTdbMinusTtAtObserver(1, &day, &sec, &zero, &zero, &zero, &zero, &value);
    checkClose(value, geocentric, 0.0, "zero observer is the geocentre exactly");

    rsTdbMinusTtAtObserver(1, &day, &sec, NULL, NULL, NULL, NULL, &value);
    checkClose(value, geocentric, 0.0, "NULL observer is the geocentre exactly");

    /* Swept over one day, an equatorial station traces the diurnal Lorentz
     * term (v_E . r)/c2. Its amplitude is about 2 us - three orders above the
     * series' own accuracy, so it is not an optional refinement. */
    for (k = 0; k < 240; k++) {
        double difference;
        double stationSecond;
        ut = (double)k / 240.0;
        stationSecond = ut * 86400.0;
        rsTdbMinusTt(1, &day, &stationSecond, &geocentric);
        rsTdbMinusTtAtObserver(1, &day, &stationSecond, &ut, &eastLongitude,
                               &equatorialRadius, &zero, &value);
        difference = value - geocentric;
        if (difference < lowest) {
            lowest = difference;
        }
        if (difference > highest) {
            highest = difference;
        }

        rsTdbMinusTtAtObserver(1, &day, &stationSecond, &ut, &eastLongitude,
                               &zero, &polarRadius, &value);
        difference = value - geocentric;
        if (difference < polarLowest) {
            polarLowest = difference;
        }
        if (difference > polarHighest) {
            polarHighest = difference;
        }
    }

    checkTrue((highest - lowest) / 2.0 > 1.5e-6 &&
              (highest - lowest) / 2.0 < 2.5e-6,
              "equatorial diurnal amplitude near 2 us");

    /* On the spin axis the diurnal term must collapse while the term in the
     * distance north of the equator survives. A transposed pair of observer
     * arguments passes the equatorial check and fails this one. */
    checkTrue(polarHighest - polarLowest < 5.0e-8,
              "diurnal term vanishes on the spin axis");
    checkTrue(fabs(polarLowest) > 1.0e-7,
              "the equator-distance term survives at the pole");

    /* SI IN, KILOMETRES NOWHERE. rsCore divides by 1000 before calling iauDtdb,
     * so a station given in metres must NOT behave like one given in km. If the
     * conversion were dropped the term would be a thousand times larger. */
    {
        double kilometres = 6378.137;
        double asMetres;
        double asKilometres;
        ut = 0.25;
        sec = 21600.0;
        rsTdbMinusTt(1, &day, &sec, &geocentric);
        rsTdbMinusTtAtObserver(1, &day, &sec, &ut, &eastLongitude,
                               &equatorialRadius, &zero, &asMetres);
        rsTdbMinusTtAtObserver(1, &day, &sec, &ut, &eastLongitude,
                               &kilometres, &zero, &asKilometres);
        checkTrue(fabs(asMetres - geocentric) >
                  500.0 * fabs(asKilometres - geocentric),
                  "the observer distance is read as metres, not kilometres");
    }
}

/*
 * The astronomical unit is stated in rsCore.c because sofam.h is a
 * SOFA-internal header that file deliberately does not include. This test MAY
 * include it, so the agreement between the two literals is measured here rather
 * than assumed - the same treatment every other duplicated constant in this
 * project has had to earn.
 */
static void testAstronomicalUnit(void)
{
    puts("rsAstronomicalUnit");
    checkClose(rsAstronomicalUnit(), DAU, 0.0,
               "rsCore au is bit-identical to SOFA DAU");
    checkClose(rsAstronomicalUnit(), 1.49597870700e11, 0.0,
               "and to the IAU 2012 defining value");
}

int main(void)
{
    printf("referenceSystem rsCore standalone tests\n");
    printf("SOFA release %s, OpenMP %s, max threads %d, parallel threshold %d\n\n",
           rsSofaRelease(), rsOpenMpEnabled() ? "yes" : "no",
           rsGetMaxThreads(), rsParallelThreshold());

    testDeltaAt();
    testTdbMinusTt();
    testEarthOrientationPrimitives();
    testFundamentalArguments();
    testThreadReproducibility();
    testCipCoordinates();
    testRotationAssembly();
    testRotationRateFollowsUt1();
    testEquinoxCrossCheck();
    testAstronomicalUnit();
    testBodyState();
    testTdbMinusTtAtObserver();

    printf("\n%d tests, %d failures\n", testCount, failCount);
    return (failCount == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
