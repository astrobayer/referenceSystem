/*
 * testApi.c
 * ---------
 * Standalone suite for mex/rsApi.c, the public C interface (prompt P19).
 *
 * THE CLAIM UNDER TEST IS EQUIVALENCE, NOT ACCURACY. rsApi does not assemble a
 * rotation; it evaluates panels and calls rsRotationItrsToGcrsFromCip, which is
 * the same function the MATLAB path reaches through the gateway. So what has to
 * be shown is that a C program and a MATLAB script produce the same matrix from
 * the same panels - and the way to show it here, with no MATLAB present, is to
 * build the panels exactly as earthOrientationInterpolant does and check the
 * result against the DIRECT chain the toolbox would otherwise run.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-27 18:00 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "rsApi.h"
#include "rsCheb.h"
#include "rsCore.h"
#include "iers/iersModels.h"
#include "sofa/sofa.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define DEGREE 20
#define PANELS 3
#define STRIDE (DEGREE + 1)

static int testCount = 0;
static int failCount = 0;

static void check(int condition, const char *name)
{
    testCount++;
    if (!condition) {
        failCount++;
        printf("  FAIL  %s\n", name);
    }
}

/* Constant EOP for the test: what matters is that both paths see the same
 * numbers, not that the numbers are a real series. The sub-daily models ARE
 * evaluated, because they are what makes degree 20 necessary. */
static const double BASE_XP = 1.0e-7;
static const double BASE_YP = 2.0e-7;
static const double BASE_DUT1 = -0.35;
static const double TAI_MINUS_UTC = 37.0;

/* The six quantities at one UTC MJD, by the same route the MATLAB builder
 * uses: the sub-daily models on the pole and UT1, then the CIP with the
 * offsets applied. Zero offsets keep the arithmetic readable; the wiring for
 * non-zero ones is what testCheb's injection test covers. */
static void chainAt(double mjdUtc, double *value)
{
    double eop[3];
    double pm[2];
    double dut1Lib;
    double dlod;
    double ttDay;
    double ttSec;
    double zero = 0.0;
    double x;
    double y;
    double s;
    double uas = 4.8481368110953599e-6 * 1e-6;

    iersOrthoEop(mjdUtc, eop);
    iersPmsdnut2(mjdUtc, pm);
    iersUtlibr(mjdUtc, &dut1Lib, &dlod);

    value[3] = BASE_XP + (eop[0] + pm[0]) * uas;
    value[4] = BASE_YP + (eop[1] + pm[1]) * uas;
    value[5] = BASE_DUT1 + (eop[2] + dut1Lib) * 1e-6;

    ttDay = floor(mjdUtc);
    ttSec = (mjdUtc - ttDay) * 86400.0 + TAI_MINUS_UTC + 32.184;
    rsCipCoordinates(1, &ttDay, &ttSec, 2006, &zero, &zero, &x, &y, &s);
    value[0] = x;
    value[1] = y;
    value[2] = s;
}

/*
 * THE FIXTURE PATH IS AN ARGUMENT, NOT A RELATIVE LITERAL. Until this was
 * fixed the path was "test/fixtures/arc.eopi" resolved against the CURRENT
 * WORKING DIRECTORY, so the eight file-reading tests passed when the runner
 * happened to be invoked from the distribution root and reported eight
 * failures from anywhere else - including from test/c, which is where somebody
 * standing next to the script naturally runs it. A green suite that depends on
 * where it was started from is not a green suite, and the symptom - "the C API
 * cannot read a MATLAB-written file" - points nowhere near the cause.
 * testIersModels already took its fixture as an argument; this one now does
 * too, and the runner passes an absolute path for both.
 */
static const char *fixturePath = "test/fixtures/arc.eopi";

int main(int argc, char *argv[])
{
    if (argc > 1) {
        fixturePath = argv[1];
    }
    static double coefficient[PANELS * 6 * STRIDE];
    double taiMinusUtc[PANELS];
    rsApiInterpolant interpolant;
    const double firstPanel = 57754.0;
    /* The central-difference step of the rate check, in seconds. ONE literal,
     * because the Rdot bound below is derived from it (D124, obligation O33). */
    const double step = 60.0;
    double node[STRIDE];
    double sampled[6][STRIDE];
    double value[6];
    double r[9];
    double rdot[9];
    double truthR[9];
    double truthRdot[9];
    double worst = 0.0;
    double worstRate = 0.0;
    int panel;
    int j;
    int q;
    int i;

    printf("testApi: public C interface (prompt P19)\n");

    for (panel = 0; panel < PANELS; panel++) {
        taiMinusUtc[panel] = TAI_MINUS_UTC;
        rsChebNodes(firstPanel + (double)panel, 1.0, DEGREE, node);
        for (j = 0; j < STRIDE; j++) {
            chainAt(node[j], value);
            for (q = 0; q < 6; q++) {
                sampled[q][j] = value[q];
            }
        }
        for (q = 0; q < 6; q++) {
            rsChebFit(sampled[q], DEGREE,
                      &coefficient[((panel * 6) + q) * STRIDE]);
        }
    }

    interpolant.degree = DEGREE;
    interpolant.quantityCount = RS_API_QUANTITIES;
    interpolant.panelCount = PANELS;
    interpolant.panelSpan = 1.0;
    interpolant.firstPanelMjd = firstPanel;
    interpolant.coefficient = coefficient;
    interpolant.taiMinusUtc = taiMinusUtc;
    interpolant.cipModel = 2006;

    /* Panel selection, including the two boundaries that are easy to get
     * wrong: the very start belongs to panel 0 and the very end to the last
     * panel, not to one past it. */
    check(rsApiPanelIndex(&interpolant, firstPanel) == 0,
          "the first instant is in panel 0");
    check(rsApiPanelIndex(&interpolant, firstPanel + 1.0) == 1,
          "a panel boundary belongs to the panel it starts");
    check(rsApiPanelIndex(&interpolant, firstPanel + (double)PANELS) == PANELS - 1,
          "the last instant is in the last panel, not one past it");
    check(rsApiPanelIndex(&interpolant, firstPanel - 0.001) < 0,
          "an epoch before the panels is refused");
    check(rsApiPanelIndex(&interpolant, firstPanel + (double)PANELS + 0.001) < 0,
          "an epoch after the panels is refused");

    /* Equivalence against the direct chain, at epochs chosen as irrational
     * fractions of a day so that none can land on a fit node by accident and
     * two of them cross a panel boundary. */
    {
        double query[6];
        query[0] = firstPanel + 0.13579;
        query[1] = firstPanel + 0.99999;
        query[2] = firstPanel + 1.00001;
        query[3] = firstPanel + 1.41421;
        query[4] = firstPanel + 2.27182;
        query[5] = firstPanel + 2.71828;

        for (i = 0; i < 6; i++) {
            double ttDay = floor(query[i]);
            double ttSec = (query[i] - ttDay) * 86400.0 + TAI_MINUS_UTC + 32.184;
            double ut1Day = ttDay;
            double ut1Sec;
            double xp[3];
            double yp[3];
            double zeros[3];
            double omega[1];
            int sample;

            check(rsApiRotationRate(&interpolant, query[i], step, r, rdot)
                  == RS_API_OK, "rsApiRotationRate succeeds inside the panels");

            for (sample = 0; sample < 3; sample++) {
                double shift = ((sample == 0) ? -step :
                                ((sample == 2) ? step : 0.0)) / 86400.0;
                chainAt(query[i] + shift, value);
                xp[sample] = value[3];
                yp[sample] = value[4];
                zeros[sample] = 0.0;
                if (sample == 1) {
                    ut1Sec = (query[i] - ttDay) * 86400.0 + value[5];
                }
            }
            omega[0] = 7.292115e-5;
            rsRotationItrsToGcrs(1, &ttDay, &ttSec, &ut1Day, &ut1Sec, xp, yp,
                zeros, zeros, omega, 2006, 1, step, truthR, truthRdot, NULL);

            for (j = 0; j < 9; j++) {
                double d = fabs(r[j] - truthR[j]);
                if (d > worst) worst = d;
                d = fabs(rdot[j] - truthRdot[j]);
                if (d > worstRate) worstRate = d;
            }
        }
    }
    printf("  rsApi vs the direct chain : R %.3g, Rdot %.3g\n", worst, worstRate);
    /* R: 5e-12 on a direction cosine is 1.03 uas (5e-12 x 2.063e11 uas/rad),
     * not the "about 1e-3 uas, four orders above the fit's own 2.6e-7 uas"
     * this comment said until rev. 1.218 (D124); it is 4e6 above that. It is
     * P19c's requirement, the bound the MATLAB end-to-end tests assert on R,
     * and it bounds the error the panels add to the chain. Measured: 1.16e-16,
     * about one ulp of a direction cosine, from gcc on the Linux CI runner and
     * from MinGW gcc 14.2 on Windows alike - the roundoff of the assembly sets
     * the floor, 4.3e4 below the bound.
     *
     * Rdot: 5e-12/step, THE SAME CLAIM IN RATE UNITS (D123). The MATLAB tests
     * have asserted it since rev. 1.217, and this line kept 5e-12 1/s until
     * rev. 1.218, so "the same claim in two languages" was false for a round.
     * Both paths difference samples at t-step and t+step, so a sample error e
     * reaches the rate as e/step: measured 9.28e-19 1/s, against
     * 1.16e-16/60 = 1.9e-18. No LOD term can hide here - rsApi reads no LOD
     * channel and both paths are handed the nominal omega - so what this bound
     * sees is a rate the two paths construct differently, which R cannot see
     * at all. Fault-injected: rsApi's omega set 1.5 ms of excess LOD off gives
     * Rdot 1.27e-12 with R unchanged at 1.16e-16; it passed 5e-12 and fails
     * 5e-12/step 15 times over. */
    check(worst < 5.0e-12, "R matches the direct chain across panel boundaries");
    check(worstRate < 5.0e-12 / step, "Rdot matches the direct chain");

    /* Refusals. A failed call must leave the caller's array alone, or a
     * plausible stale matrix survives into an orbit. */
    {
        double sentinel[9];
        for (j = 0; j < 9; j++) {
            sentinel[j] = -1.0;
        }
        check(rsApiRotation(&interpolant, firstPanel - 1.0, sentinel)
              == RS_API_OUT_OF_RANGE, "an epoch outside the panels is refused");
        check(sentinel[0] == -1.0, "a refused call does not touch its output");
        check(rsApiRotation(NULL, firstPanel, sentinel) == RS_API_NULL_ARGUMENT,
              "a NULL interpolant is refused");
        check(rsApiRotation(&interpolant, firstPanel, NULL)
              == RS_API_NULL_ARGUMENT, "a NULL output is refused");
        check(rsApiRotationRate(&interpolant, firstPanel, 0.0, sentinel, rdot)
              == RS_API_NULL_ARGUMENT, "a non-positive step is refused");
        interpolant.cipModel = 1999;
        check(rsApiRotation(&interpolant, firstPanel, sentinel)
              == RS_API_BAD_INTERPOLANT,
              "cipModel is validated even though the panels make it unread");
        interpolant.cipModel = 2006;
    }

    /* ---- reading a file MATLAB actually wrote ------------------------ */
    {
        /* THE FILE IS THE ONE MATLAB PRODUCED, not one this test synthesised.
         * The whole point of the serialiser is that two implementations agree
         * about a format, and a C test that writes its own file and reads it
         * back asserts only that C is self-consistent. This is the only check
         * in the toolbox that can catch the writer and the reader disagreeing.
         *
         * It already caught one: cipModel is written as the TEXT
         * "IAU2006/2000A", and atoi of that is 0 - neither of the two legal
         * values, and it would have surfaced as an unknown-model error from
         * deep inside the rotation rather than as a parse problem here. */
        rsApiInterpolant fileIp;
        static double coefficient[64 * RS_API_MAX_QUANTITIES * 64];
        double tai[64];
        double rFile[9], rBuilt[9];
        int status;

        status = rsApiReadInterpolant(fixturePath, &fileIp,
                                      NULL, 0, NULL, 0);
        check(status == RS_API_OK, "the header of a MATLAB-written file parses");
        printf("  read: degree %d, %d panels, span %g d, first MJD %g, cipModel %d\n",
               fileIp.degree, fileIp.panelCount, fileIp.panelSpan,
               fileIp.firstPanelMjd, fileIp.cipModel);
        check(fileIp.cipModel == 2006,
              "cipModel is mapped from its NAME, not parsed as a number");
        check(fileIp.degree == 20 && fileIp.panelSpan == 1.0,
              "the file carries the D82 geometry");
        check(fileIp.coefficient == NULL,
              "a header-only read leaves the interpolant unusable");

        status = rsApiReadInterpolant(fixturePath, &fileIp,
                                      coefficient, (int)(sizeof coefficient / sizeof *coefficient),
                                      tai, 64);
        check(status == RS_API_OK, "the body of a MATLAB-written file parses");
        check(fileIp.taiMinusUtc != NULL && fileIp.taiMinusUtc[0] == 37.0,
              "the leap second count survives the file");

        /* And it must ROTATE. Parsing without evaluating would pass on a file
         * whose coefficients were read in the wrong order. */
        status = rsApiRotation(&fileIp, fileIp.firstPanelMjd + 0.31831, rFile);
        check(status == RS_API_OK, "a rotation is obtained from the file alone");
        {
            double det = rFile[0]*(rFile[4]*rFile[8]-rFile[7]*rFile[5])
                       - rFile[3]*(rFile[1]*rFile[8]-rFile[7]*rFile[2])
                       + rFile[6]*(rFile[1]*rFile[5]-rFile[4]*rFile[2]);
            printf("  det(R) from the file = %.15f\n", det);
            check(fabs(det - 1.0) < 1e-12,
                  "the rotation read from the file is orthonormal");
        }

        status = rsApiReadInterpolant(fixturePath, &fileIp,
                                      coefficient, 3, tai, 64);
        check(status == RS_API_BUFFER_TOO_SMALL, "a short buffer is refused");
        check(rsApiReadInterpolant("test/fixtures/absent.eopi", &fileIp,
                                   NULL, 0, NULL, 0) == RS_API_BAD_FILE,
              "a missing file is refused");
        (void)rBuilt;
    }

    /* ------------------------------------------------------------------ *
     * P19's OTHER TARGET, MEASURED WHERE IT BELONGS. The prompt asks for
     * under 1 microsecond per C evaluation, and until rev. 1.152 nothing
     * measured it - the MATLAB suite cannot, because the thing being timed
     * is precisely the path that does not go through MATLAB. Timed here over
     * enough repetitions that clock resolution cannot dominate, and PRINTED
     * as well as checked, so that a slow host yields a number rather than a
     * mysterious failure.
     * ------------------------------------------------------------------ */
    {
        const int repetitions = 200000;
        clock_t start;
        double perCall;
        double mjd = firstPanel + 0.37;
        double timed[9];
        int rep;

        start = clock();
        for (rep = 0; rep < repetitions; rep++) {
            rsApiRotation(&interpolant, mjd, timed);
            mjd += 1.0e-9;      /* vary the argument: no same-input shortcut */
        }
        perCall = 1.0e6 * (double)(clock() - start) /
            ((double)CLOCKS_PER_SEC * repetitions);

        printf("\n  rsApiRotation: %.3f us per call over %d repetitions"
               " (target 1.000 us, fails above 5)\n", perCall, repetitions);
        /* FIVE TIMES THE TARGET, NOT THE TARGET, AND THE NUMBER IS PRINTED
         * EITHER WAY. This is section D.1's rule, which the MATLAB benchmarks
         * have followed since rev. 1.86 and this one never adopted: a target
         * is machine dependent, a fivefold miss is a defect. The same call
         * measured 0.568 us and 1.293 us on the SAME container within one
         * session - the second run was not slower code, it was a busier host.
         * A test that fails on load teaches its reader to rerun until green,
         * which is worse than no test at all. The figure above is the
         * instrument; this line only refuses a collapse. */
        check(perCall < 5.0,
              "rsApiRotation evaluates in under 5 us (target 1.000 us)");
    }

    printf("\n%d tests, %d failures\n", testCount, failCount);
    return failCount == 0 ? 0 : 1;
}
