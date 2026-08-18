/*
 * testIersModels.c
 * ----------------
 * Standalone test suite for the ported IERS Conventions (2010) routines in
 * mex/iers/, built and run with plain gcc by test/c/runStandaloneTests.sh.
 *
 * Every expected value below is a published literal taken from the header of
 * the original Fortran routine in mex/iers/iers_src/, never a number produced
 * by this toolbox (handover section D.1, category reference). That is the
 * whole point of keeping these ports byte-intact under decision D27: the
 * published test case is the only external validation the tidal chain has, so
 * it is re-measured here rather than inherited from v1.
 *
 * The suite also discharges obligation O3 of handover section G.2b. It sweeps
 * the ported FUNDARG over 1960 to 2100 and writes test/fixtures/fundargIers.csv,
 * which is what lets the filtered MATLAB test
 * TestTime/fundamentalArguments_reference_agreesWithPortedFundarg run against
 * SOFA's iauFa*03. The comparison belongs in C because both implementations
 * live here; no gateway command exposes FUNDARG and none should.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-25 10:05 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "iers/iersModels.h"
#include "sofa/sofa.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

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

/* ---------------------------------------------------------------------- */

static void testFundarg(void)
{
    /* FUNDARG.F published test case, T = 0.07995893223819302 centuries, that
     * is MJD 54465.
     *
     * THE SUPPLIED FUNDARG.F DOES NOT REPRODUCE THE TEST CASE PRINTED IN ITS
     * OWN HEADER, for L' and D. This was found in S2 by compiling the file
     * with gfortran and comparing, and it is a property of the file, not of
     * the port: the C port reproduces the Fortran bit-for-bit at all five
     * arguments over 2001 epochs.
     *
     * Cause, isolated: the DATA statements carry
     *     LP constant 1287104.79305     D constant 1072260.70369
     * where the constants that DO reproduce the header values, and which SOFA
     * uses in iauFalp03 and iauFad03, are
     *     LP constant 1287104.793048    D constant 1072260.703692
     * Two truncated digits, 2e-6 arcsec each, which is 9.7e-12 rad. Every
     * other argument agrees with the published value to 1e-13.
     *
     * So the assertion is split. L, F and OM are checked against the published
     * literal. L' and D are checked against the value the supplied file
     * actually produces -- an independent literal, since it comes from
     * gfortran compiling the IERS Fortran, not from this toolbox -- and the
     * offset from the published value is then pinned explicitly, so that the
     * anomaly is a tested fact rather than a comment somebody deletes.
     *
     * Consequence for the toolbox: none that is measurable. 2 uas of lunisolar
     * argument propagates to below 1e-9 uas of polar motion through PMSDNUT2
     * and to 1e-14 s through RG_ZONT2. It is recorded because an unexplained
     * 1e-11 is how a real defect hides. */
    const double publishedLp = 6.212931111003726414;
    const double publishedD = 4.554139562402433228;
    double l;
    double lp;
    double f;
    double d;
    double om;

    iersFundarg(0.07995893223819302, &l, &lp, &f, &d, &om);

    checkClose(l, 2.291187512612069099, 1e-12, "iersFundarg L vs published");
    checkClose(f, 3.658025792050572989, 1e-12, "iersFundarg F vs published");
    checkClose(om, -0.5167379217231804489, 1e-12, "iersFundarg OM vs published");

    /* gfortran 13.3.0 on the supplied FUNDARG.F, printed to 18 digits. */
    checkClose(lp, 6.21293111101342621, 1e-14, "iersFundarg LP vs the file");
    checkClose(d, 4.55413956239284179, 1e-14, "iersFundarg D vs the file");

    checkClose(fabs(lp - publishedLp), 9.700e-12, 1e-14,
               "iersFundarg LP file-minus-published offset pinned");
    checkClose(fabs(d - publishedD), 9.591e-12, 1e-14,
               "iersFundarg D file-minus-published offset pinned");
}

static void testCnmtx(void)
{
    /* CNMTX.F published test case, dmjd = 54964.0. */
    static const double expected[12] = {
        15.35873641938967360, 9.784941251812741214, -5.520740128266865554,
        3.575314211234633888, -13.93717453496387648, -9.167400321705855504,
        5.532815475865292321, 9.558741883500834646, -10.22541212627272600,
        0.8367570529461261231, 1.946355176475630611, -13.55702062247304696
    };
    double h[12];
    char name[64];
    int k;

    iersCnmtx(54964.0, h);
    for (k = 0; k < 12; k++) {
        sprintf(name, "iersCnmtx h(%d)", k + 1);
        checkClose(h[k], expected[k], 1e-11, name);
    }
}

static void testOrthoEop(void)
{
    /* ORTHO_EOP.F published test case, MJD = 47100.0. */
    double eop[3];

    iersOrthoEop(47100.0, eop);
    checkClose(eop[0], -162.8386373279636530, 1e-11, "iersOrthoEop dx [uas]");
    checkClose(eop[1], 117.7907525842668974, 1e-11, "iersOrthoEop dy [uas]");
    checkClose(eop[2], -23.39092370609808214, 1e-11, "iersOrthoEop dUT1 [us]");
}

static void testPmsdnut2(void)
{
    /* PMSDNUT2.F published test case, rmjd = 54335.0 (2007-08-23). */
    double pm[2];

    iersPmsdnut2(54335.0, pm);
    checkClose(pm[0], 24.83144238273364834, 1e-11, "iersPmsdnut2 dx [uas]");
    checkClose(pm[1], -14.09240692041837661, 1e-11, "iersPmsdnut2 dy [uas]");
}

static void testUtlibr(void)
{
    /* UTLIBR.F published test cases, both of them. */
    double dut1;
    double dlod;

    iersUtlibr(44239.1, &dut1, &dlod);
    checkClose(dut1, 2.441143834386761746, 1e-11, "iersUtlibr dUT1 a [us]");
    checkClose(dlod, -14.78971247349449492, 1e-11, "iersUtlibr dLOD a [us/day]");

    iersUtlibr(55227.4, &dut1, &dlod);
    checkClose(dut1, -2.655705844335680244, 1e-11, "iersUtlibr dUT1 b [us]");
    checkClose(dlod, 27.39445826599846967, 1e-11, "iersUtlibr dLOD b [us/day]");
}

static void testRgZont2(void)
{
    /* RG_ZONT2.F published test case, T = 0.07995893223819302 centuries of TT
     * since J2000.0, that is MJD 54465. This is the new capability of P7 and
     * the only one of the six ports with no v1 predecessor, so it is the one
     * whose table transcription is genuinely unproven until this passes. */
    double dut;
    double dlod;
    double domega;

    iersRgZont2(0.07995893223819302, &dut, &dlod, &domega);
    checkClose(dut, 7.983287678576557467e-2, 1e-15, "iersRgZont2 dUT1 [s]");
    checkClose(dlod, 5.035331113978199288e-5, 1e-18, "iersRgZont2 dLOD [s/day]");
    checkClose(domega, -4.249711616463017e-14, 1e-27, "iersRgZont2 dOmega [rad/s]");
}

static void testRgZont2Amplitude(void)
{
    /* How big is this correction? Decision D30 exists because applying it in
     * the wrong sense is invisible, so the size of the mistake has to be a
     * measured number in the ACCURACY blocks rather than a remembered one.
     * Handover approximation #6 quotes "up to about 30 us in UT1", which is
     * the SHORT-PERIOD part only. The full 62-term model is dominated by the
     * 18.6-year nodal term, whose UT1 amplitude is 1617.2681e-4 s = 162 ms,
     * four orders of magnitude larger.
     *
     * MEASURED IN S2, and both figures are far larger than the handover's:
     *   - full 62-term model, peak over one nodal period: 168 ms of UT1,
     *     which is 78 m of surface displacement at the equator;
     *   - short-period part alone (35-day high-pass), which is what
     *     separates UT1R from UT1: 2.1 ms, which is 0.96 m.
     * Handover approximation #6 quotes 30 us and 14 mm. Both are wrong by
     * three to four orders of magnitude, and wrong in the safe direction for
     * the argument being made: D30 is far more necessary than the handover
     * claimed, not less. The correction is recorded in rev. 1.40.
     *
     * The split is by term period, computed from the mean rates of the five
     * lunisolar arguments; 35 days is the conventional UT1R boundary. */
    double dut;
    double dlod;
    double domega;
    double maxAbsDut = 0.0;
    double maxAbsDlod = 0.0;
    double maxAbsDomega = 0.0;
    double mjd;


    for (mjd = 51544.5; mjd <= 51544.5 + 6798.0; mjd += 1.0) {
        iersRgZont2((mjd - 51544.5) / 36525.0, &dut, &dlod, &domega);
        if (fabs(dut) > maxAbsDut) {
            maxAbsDut = fabs(dut);
        }
        if (fabs(dlod) > maxAbsDlod) {
            maxAbsDlod = fabs(dlod);
        }
        if (fabs(domega) > maxAbsDomega) {
            maxAbsDomega = fabs(domega);
        }
    }
    printf("  INFO  peak |dUT1|   over one nodal period    = %.3f ms\n",
           maxAbsDut * 1e3);
    printf("  INFO  peak |dLOD|   over one nodal period    = %.4f ms/day\n",
           maxAbsDlod * 1e3);
    printf("  INFO  peak |dOmega| over one nodal period    = %.4e rad/s\n",
           maxAbsDomega);

    /* Band, not a literal: the peak depends on where the terms happen to
     * beat, so an equality would be brittle. One order of magnitude either
     * side of the dominant term catches a lost rescale (1e-4), a dropped
     * table block or a sign collapse, which are the failures that matter. */
    checkClose((maxAbsDut > 0.05 && maxAbsDut < 0.5) ? 1.0 : 0.0, 1.0, 0.0,
               "iersRgZont2 peak dUT1 in band 50..500 ms");
    checkClose((maxAbsDlod > 1.0e-4 && maxAbsDlod < 1.0e-2) ? 1.0 : 0.0, 1.0,
               0.0, "iersRgZont2 peak dLOD in band 0.1..10 ms/day");
}

static void testRgZont2ShortPeriodPart(void)
{
    /* The short-period part, isolated by high-pass filtering the daily series
     * with a 35-day centred moving average. This is the quantity handover
     * approximation #6 quotes and the one whose misuse D30 guards, so it is
     * measured rather than asserted from memory. */
    const int days = 6798;
    const int window = 35;
    double *series = (double *)malloc(sizeof(double) * (size_t)(days + 1));
    double maxAbsShort = 0.0;
    int k;

    if (series == NULL) {
        printf("  FAIL  %-46s out of memory\n", "iersRgZont2 short-period part");
        testCount++;
        failCount++;
        return;
    }
    for (k = 0; k <= days; k++) {
        double dut;
        double dlod;
        double domega;
        iersRgZont2((double)k / 36525.0, &dut, &dlod, &domega);
        series[k] = dut;
    }
    for (k = window; k <= days - window; k++) {
        double mean = 0.0;
        double residual;
        int m;
        for (m = k - window / 2; m <= k + window / 2; m++) {
            mean += series[m];
        }
        mean /= (double)(2 * (window / 2) + 1);
        residual = fabs(series[k] - mean);
        if (residual > maxAbsShort) {
            maxAbsShort = residual;
        }
    }
    free(series);

    printf("  INFO  peak short-period |dUT1| (35 d high-pass) = %.2f us\n",
           maxAbsShort * 1e6);
    /* At the equator 1 us of UT1 is 0.465 mm of surface displacement. */
    printf("  INFO  equivalent surface displacement at equator = %.2f mm\n",
           maxAbsShort * 1e6 * 0.465);

    checkClose((maxAbsShort > 5.0e-4 && maxAbsShort < 1.0e-2) ? 1.0 : 0.0, 1.0,
               0.0, "iersRgZont2 short-period dUT1 in band 0.5..10 ms");
}

/* ---------------------------------------------------------------------- */

static double wrapToTwoPi(double angle)
{
    double wrapped = fmod(angle, 6.283185307179586476925287);
    if (wrapped < 0.0) {
        wrapped += 6.283185307179586476925287;
    }
    return wrapped;
}

static void testFundargAgainstSofa(const char *fixturePath)
{
    /* Decision D27 and obligation O3. The toolbox holds two implementations of
     * the lunisolar arguments on purpose: SOFA iauFa*03, which
     * referenceSystem.fundamentalArguments exposes, and this ported FUNDARG,
     * held byte-intact so the published validation above still stands. The
     * duplication is answered by measuring the agreement over the whole span
     * the toolbox claims, not by unifying the code.
     *
     * Both trace to Simon et al. (1994), so agreement is expected; the point
     * is that it is measured and recorded, so that a future SOFA release which
     * changed it would fail loudly instead of silently. */
    const double startMjd = 36934.0;   /* 1960-01-01 */
    const double endMjd = 88069.0;     /* 2100-01-01 */
    const double stepDays = 64.0;      /* 800 samples across the span */
    double worst[5] = {0.0, 0.0, 0.0, 0.0, 0.0};
    const char *label[5] = {"l", "lPrime", "F", "D", "Omega"};
    FILE *fixture;
    double mjd;
    int k;

    fixture = fopen(fixturePath, "w");
    if (fixture == NULL) {
        printf("  FAIL  %-46s cannot open %s\n",
               "fundargIers.csv fixture", fixturePath);
        testCount++;
        failCount++;
        return;
    }
    fprintf(fixture, "day,sec,l,lPrime,F,D,Omega\n");

    for (mjd = startMjd; mjd <= endMjd; mjd += stepDays) {
        double t = (mjd - 51544.5) / 36525.0;
        double ported[5];
        double sofa[5];

        iersFundarg(t, &ported[0], &ported[1], &ported[2], &ported[3],
                    &ported[4]);
        sofa[0] = iauFal03(t);
        sofa[1] = iauFalp03(t);
        sofa[2] = iauFaf03(t);
        sofa[3] = iauFad03(t);
        sofa[4] = iauFaom03(t);

        for (k = 0; k < 5; k++) {
            double difference = fabs(wrapToTwoPi(ported[k]) -
                                     wrapToTwoPi(sofa[k]));
            /* A difference straddling the wrap point is small, not 2pi. */
            if (difference > 3.14159265358979) {
                difference = 6.283185307179586476925287 - difference;
            }
            if (difference > worst[k]) {
                worst[k] = difference;
            }
        }

        fprintf(fixture, "%.1f,%.1f,%.17g,%.17g,%.17g,%.17g,%.17g\n",
                floor(mjd), (mjd - floor(mjd)) * 86400.0,
                ported[0], ported[1], ported[2], ported[3], ported[4]);
    }
    fclose(fixture);

    for (k = 0; k < 5; k++) {
        char name[80];
        sprintf(name, "D27 SOFA vs iersFundarg %s, 1960-2100", label[k]);
        printf("  INFO  worst |SOFA - ported| %-8s = %.3e rad = %.4f uas\n",
               label[k], worst[k], worst[k] / 4.848136811095359935899141e-6 * 1e6);
        /* MEASURED, and not what S1 recorded. S1 checked one epoch and read
         * "better than 1e-13 rad"; swept over 1960 to 2100 the true figure is
         * 9.8e-12 rad, that is 2.0 uas, and it is not noise. It is confined to
         * l' and D and is exactly zero for l, F and Omega, which is the
         * signature of its cause: the supplied FUNDARG.F carries the constants
         * 1287104.79305 and 1072260.70369 where SOFA carries
         * 1287104.793048 and 1072260.703692. The two truncated digits are
         * 2e-6 arcsec each, which is 9.7e-12 rad -- the whole discrepancy.
         *
         * Note which one matches the published test case: SOFA does, to 1e-16.
         * The supplied FUNDARG.F does NOT reproduce the test case printed in
         * its own header. The port is faithful to the file it was ported from;
         * the file is internally inconsistent. Recorded, not repaired, because
         * repairing it would break the byte-intactness the other five routines
         * are validated under (D27) and 2 uas of lunisolar argument is 3e-10
         * uas of polar motion, which is nothing.
         *
         * The tolerance below is therefore set just above the measured value,
         * so that this stays pinned: if a future SOFA release or a corrected
         * FUNDARG.F moves it, the suite says so. */
        checkClose(worst[k], 0.0, 2e-11, name);
        if (k == 0 || k == 2 || k == 4) {
            sprintf(name, "D27 %s agrees exactly (no truncated constant)",
                    label[k]);
            checkClose(worst[k], 0.0, 0.0, name);
        }
    }
}

/* ---------------------------------------------------------------------- */

int main(int argc, char **argv)
{
    const char *fixturePath = "test/fixtures/fundargIers.csv";

    if (argc > 1) {
        fixturePath = argv[1];
    }

    printf("referenceSystem -- ported IERS Conventions (2010) routines\n");
    printf("  every expected value is a published literal from iers_src/\n\n");

    testFundarg();
    testCnmtx();
    testOrthoEop();
    testPmsdnut2();
    testUtlibr();
    testRgZont2();
    testRgZont2Amplitude();
    testRgZont2ShortPeriodPart();
    testFundargAgainstSofa(fixturePath);

    printf("\n  %d test(s), %d failure(s)\n", testCount, failCount);
    return (failCount == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
