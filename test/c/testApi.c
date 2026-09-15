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
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define DEGREE 20
#define PANELS 3
#define STRIDE (DEGREE + 1)

/* D28's velocity budget, as referenceSystem.rotationItrsToGcrs's help states it,
 * over the orbit radius the handover evaluates it at: a rotation-rate error e
 * moves a velocity by about e*r, so every Rdot check here is held to
 * 1 nm/s / 7000 km = 1.43e-16 1/s (rev. 1.223, H.11 item 5). The same two
 * numbers are TestRotation.VelocityBudget and TestRotation.OrbitRadius; the
 * languages cannot share one definition, so each file carries its own. */
#define RATE_BUDGET (1.0e-9 / 7.0e6)

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

/* THE FORMAT-2 FIXTURE, THE FORMAT MATLAB HAS WRITTEN SINCE P19c. Until rev.
 * 1.221 the suite read only arc.eopi, which is format 1, and the reader refused
 * every format-2 file without anything here noticing. Written by
 * earthOrientationInterpolant from eop20c04.txt with the defaults, then
 * writeInterpolant; the panels it shares with arc.eopi (MJD 57754-57757) agree
 * with its coefficients to 2.2e-17. SINCE REV. 1.226 IT STARTS AT MJD 57752 AND
 * SO CROSSES THE 2017-01-01 LEAP SECOND, which a builder that took each panel's
 * last node after the jump could not fit; its four later panels are bit for bit
 * the rev. 1.221 file's. The second argument, for the same reason as the first. */
static const char *fixturePath2 = "test/fixtures/arcFormat2.eopi";

/* MATLAB'S RATE ON THAT FILE, THE ONLY TRUTH HERE THAT DOES NOT SHARE rsApi's
 * OMEGA (rev. 1.222). Every other rate check in this file compares rsApi with
 * rsRotationItrsToGcrs handed the same omega, so a wrong omega passes them all -
 * which is how a nominal constant and a missing length of day stood for forty
 * revisions at 5.8e-13 1/s from MATLAB's default. The file holds
 * rotationItrsToGcrs(..., 'Interpolant', ...) at its defaults, and
 * TestRotation/rotationItrsToGcrs_contract_cApiRateFixtureIsCurrent holds MATLAB
 * to it, so a change on either side fails a test on that side. */
static const char *rateFixturePath = "test/fixtures/arcFormat2Rate.csv";

/* MATLAB'S ROTATION AND RATE ON THE SAME FILE AT A DAY AND A SECOND (rev.
 * 1.236), the truth for rsApiRotationRateDaySecond.
 * TestRotation/rotationItrsToGcrs_contract_cApiDaySecondFixtureIsCurrent holds
 * MATLAB to it. */
static const char *daySecondFixturePath = "test/fixtures/arcFormat2DaySecond.csv";

int main(int argc, char *argv[])
{
    if (argc > 1) {
        fixturePath = argv[1];
    }
    if (argc > 2) {
        fixturePath2 = argv[2];
    }
    if (argc > 3) {
        rateFixturePath = argv[3];
    }
    if (argc > 4) {
        daySecondFixturePath = argv[4];
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
            /* The omega rsApi takes for a six-channel interpolant (rev. 1.222):
             * the ERA slope, with no length of day to apply. */
            omega[0] = rsEarthRotationAngleRate();
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
     * Rdot: D28's budget, RATE_BUDGET = 1.43e-16 1/s, SINCE REV. 1.223 (H.11
     * item 5). From rev. 1.218 to 1.222 it was 5e-12/step, D123's statement of
     * the R claim in rate units, which at step 60 s is 8.3e-14 - 580 times the
     * budget, and a bound that moved with the step. Both paths difference
     * samples at t-step and t+step, so a sample error e reaches the rate as
     * e/step: measured 9.28e-19 1/s, against 1.16e-16/60 = 1.9e-18, and 154
     * times below the budget. No LOD term can hide here - the interpolant built
     * above has six channels, so rsApi has no lod to apply, and both paths are
     * handed the same ERA slope (the nominal omega until rev. 1.222) - so what
     * this bound sees is a rate the two paths construct differently, which R
     * cannot see at all. Because both paths share that omega, this block cannot
     * tell a wrong omega from a right one; the MATLAB rate fixture below can.
     * Fault-injected: rsApi's omega set 1.5 ms of excess LOD off gives
     * Rdot 1.27e-12 with R unchanged at 1.16e-16; it passed 5e-12 and failed
     * 5e-12/step 15 times over. */
    check(worst < 5.0e-12, "R matches the direct chain across panel boundaries");
    check(worstRate < RATE_BUDGET, "Rdot matches the direct chain");

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

    /* ---- reading the format MATLAB writes today (rev. 1.221) ------------ */
    {
        /* A FORMAT-2 FILE MUST READ, CARRY SEVEN CHANNELS, AND GIVE THE SAME
         * ROTATION AS THE FORMAT-1 FILE OF THE SAME PANELS. The last check is
         * what makes the striding visible: a reader that took seven channels
         * as six would read panel 1 out of panel 0's lod column and rotate
         * wrongly by far more than the bound. The bound is P19c's 5e-12 on a
         * direction cosine (1.03 uas); the two files' first six channels agree
         * to 2.2e-17 in their coefficients, so what is left is roundoff. */
        rsApiInterpolant one;
        rsApiInterpolant two;
        static double coefficientOne[64 * RS_API_MAX_QUANTITIES * 64];
        static double coefficientTwo[64 * RS_API_MAX_QUANTITIES * 64];
        double taiOne[64];
        double taiTwo[64];
        double rOne[9];
        double rTwo[9];
        double worstFormat = 0.0;
        int statusOne;
        int statusTwo;

        statusTwo = rsApiReadInterpolant(fixturePath2, &two, NULL, 0, NULL, 0);
        check(statusTwo == RS_API_OK, "the header of a format-2 file parses");
        /* Conditional on the status, because the parser counts the quantity
         * line before its final check: under the rev. 1.220 defect the count
         * read 7 on a file that was then refused. */
        check(statusTwo == RS_API_OK && two.quantityCount == RS_API_MAX_QUANTITIES,
              "a format-2 file is read with its seven channels");
        statusTwo = rsApiReadInterpolant(fixturePath2, &two, coefficientTwo,
            (int)(sizeof coefficientTwo / sizeof *coefficientTwo), taiTwo, 64);
        check(statusTwo == RS_API_OK, "the body of a format-2 file parses");
        statusOne = rsApiReadInterpolant(fixturePath, &one, coefficientOne,
            (int)(sizeof coefficientOne / sizeof *coefficientOne), taiOne, 64);

        if (statusOne == RS_API_OK && statusTwo == RS_API_OK) {
            for (i = 0; i < 6; i++) {
                double mjd = firstPanel + 0.13579 + 0.61803 * (double)i;
                check(rsApiRotation(&one, mjd, rOne) == RS_API_OK &&
                      rsApiRotation(&two, mjd, rTwo) == RS_API_OK,
                      "both formats rotate across the panels");
                for (j = 0; j < 9; j++) {
                    double d = fabs(rOne[j] - rTwo[j]);
                    if (d > worstFormat) worstFormat = d;
                }
            }
            printf("  format 2 vs format 1 : R %.3g\n", worstFormat);
            check(worstFormat < 5.0e-12,
                  "a format-2 file gives the rotation its format-1 twin gives");
        }

        /* ---- and it must give MATLAB's RATE (rev. 1.222) ---------------- */
        if (statusTwo == RS_API_OK) {
            /* Bounds as everywhere else in this file: 5e-12 on R, P19c's
             * requirement, and RATE_BUDGET on Rdot (rev. 1.223), with the step
             * read from the fixture rather than written here a second time
             * (O33). Measured when the fixture was written, MinGW gcc against
             * the MATLAB MEX on one host, and again by gcc on ubuntu-24.04 in
             * CI #52: 0 and 0, bit for bit. Before rev. 1.222 the rate missed
             * by 5.8e-13, 4000 times the budget: 1.467e-12 from the nominal
             * omega and up to 1.25e-12 from the unread length of day, partly
             * cancelling. */
            FILE *rates = fopen(rateFixturePath, "r");
            char line[1024];
            double rateStep = 0.0;
            double worstMatlabR = 0.0;
            double worstMatlabRdot = 0.0;
            int rows = 0;
            int dataLines = 0;
            int rowsOk = 1;

            check(rates != NULL, "the MATLAB rate fixture opens");
            while (rates != NULL && fgets(line, (int)sizeof line, rates) != NULL) {
                double field[19];
                double rApi[9];
                double rdotApi[9];
                char *cursor = line;
                char *end;
                int n = 0;

                if (line[0] == '#') continue;
                if (sscanf(line, "step %lf", &rateStep) == 1) continue;
                dataLines++;
                while (n < 19) {
                    field[n] = strtod(cursor, &end);
                    if (end == cursor) break;
                    n++;
                    cursor = (*end == ',') ? end + 1 : end;
                }
                if (n != 19 || !(rateStep > 0.0)) {
                    rowsOk = 0;
                    continue;
                }
                if (rsApiRotationRate(&two, field[0], rateStep, rApi, rdotApi)
                    != RS_API_OK) {
                    rowsOk = 0;
                    continue;
                }
                for (j = 0; j < 9; j++) {
                    double d = fabs(rApi[j] - field[1 + j]);
                    if (d > worstMatlabR) worstMatlabR = d;
                    d = fabs(rdotApi[j] - field[10 + j]);
                    if (d > worstMatlabRdot) worstMatlabRdot = d;
                }
                rows++;
            }
            if (rates != NULL) {
                fclose(rates);
            }
            printf("  rsApi vs MATLAB's rate : R %.3g, Rdot %.3g over %d epochs, step %g\n",
                   worstMatlabR, worstMatlabRdot, rows, rateStep);
            check(rowsOk && rows > 0 && rows == dataLines,
                  "every row of the MATLAB rate fixture is evaluated");
            check(rows > 0 && worstMatlabR < 5.0e-12, "R matches MATLAB's interpolated R");
            check(rows > 0 && worstMatlabRdot < RATE_BUDGET,
                  "Rdot matches MATLAB's default interpolated Rdot");

            /* A SHOULDER INSIDE THE LEAP SECOND HAS NO LABEL AND IS REFUSED
             * (rev. 1.226), and the refusal leaves the caller's arrays alone.
             * 57753 + 86200.5 s puts the +200 s shoulder at 23:59:60.5; 57754 +
             * 199.5 s puts the -200 s shoulder there. The fixture's rows 86.4 s
             * either side of the leap second are the ones that straddle it and
             * are NOT refused - a shoulder beyond a change in TAI-UTC is taken
             * at its own label, and until rev. 1.226 it was taken one second
             * off, missing MATLAB's rate by 1.1e-14 1/s there. */
            {
                double sentinelR[9];
                double sentinelRdot[9];
                for (j = 0; j < 9; j++) {
                    sentinelR[j] = -1.0;
                    sentinelRdot[j] = -1.0;
                }
                check(rsApiRotationRate(&two, 57753.0 + 86200.5 / 86400.0, 200.0,
                                        sentinelR, sentinelRdot) == RS_API_OUT_OF_RANGE,
                      "a +step shoulder inside the leap second is refused");
                check(rsApiRotationRate(&two, 57754.0 + 199.5 / 86400.0, 200.0,
                                        sentinelR, sentinelRdot) == RS_API_OUT_OF_RANGE,
                      "a -step shoulder inside the leap second is refused");
                check(sentinelR[0] == -1.0 && sentinelRdot[0] == -1.0,
                      "a refused shoulder leaves the outputs untouched");
                check(rsApiRotationRate(&two, 57753.0 + 86199.5 / 86400.0, 200.0,
                                        sentinelR, sentinelRdot) == RS_API_OK,
                      "one second earlier the shoulder is clear of it and is taken");
            }

            /* ---- the day-and-second form, against MATLAB (rev. 1.236) -- */
            /* THE SAME TRUTH, AT SECONDS AN MJD DOUBLE CANNOT NAME. Bounds as
             * above, 5e-12 on R and RATE_BUDGET on Rdot, step from the file.
             * Measured when the fixture was written, MinGW gcc against the
             * MATLAB MEX: 0 and 0, bit for bit. The same rows are put through
             * the MJD form as well, and it must MISS them. It missed by
             * 2.15e-11 on R and 1.57e-15 1/s on Rdot at the arc rows, and by
             * 7.17e-5 rad 0.2 us before 23:59:60, where the nearest MJD double
             * is the next day's 0h, a second later. A fixture both forms
             * passed could not show what this form is for. */
            {
                FILE *fixture = fopen(daySecondFixturePath, "r");
                char line[1024];
                double fixtureStep = 0.0;
                double worstDayR = 0.0;
                double worstDayRdot = 0.0;
                double worstMjdR = 0.0;
                double worstMjdRdot = 0.0;
                double worstArcR = 0.0;       /* the MJD form, rows 7-21 only */
                double worstArcRdot = 0.0;
                int rows = 0;
                int dataLines = 0;
                int rowsOk = 1;

                check(fixture != NULL, "the day-and-second fixture opens");
                while (fixture != NULL && fgets(line, (int)sizeof line, fixture) != NULL) {
                    double field[20];
                    double rApi[9];
                    double rdotApi[9];
                    char *cursor = line;
                    char *end;
                    int n = 0;

                    if (line[0] == '#') continue;
                    if (sscanf(line, "step %lf", &fixtureStep) == 1) continue;
                    dataLines++;
                    while (n < 20) {
                        field[n] = strtod(cursor, &end);
                        if (end == cursor) break;
                        n++;
                        cursor = (*end == ',') ? end + 1 : end;
                    }
                    if (n != 20 || !(fixtureStep > 0.0)) {
                        rowsOk = 0;
                        continue;
                    }
                    if (rsApiRotationRateDaySecond(&two, field[0], field[1],
                            fixtureStep, rApi, rdotApi) != RS_API_OK) {
                        rowsOk = 0;
                        continue;
                    }
                    for (j = 0; j < 9; j++) {
                        double d = fabs(rApi[j] - field[2 + j]);
                        if (d > worstDayR) worstDayR = d;
                        d = fabs(rdotApi[j] - field[11 + j]);
                        if (d > worstDayRdot) worstDayRdot = d;
                    }
                    if (rsApiRotationRate(&two, field[0] + field[1] / 86400.0,
                            fixtureStep, rApi, rdotApi) == RS_API_OK) {
                        for (j = 0; j < 9; j++) {
                            double d = fabs(rApi[j] - field[2 + j]);
                            if (d > worstMjdR) worstMjdR = d;
                            if (rows >= 6 && d > worstArcR) worstArcR = d;
                            d = fabs(rdotApi[j] - field[11 + j]);
                            if (d > worstMjdRdot) worstMjdRdot = d;
                            if (rows >= 6 && d > worstArcRdot) worstArcRdot = d;
                        }
                    }
                    rows++;
                }
                if (fixture != NULL) {
                    fclose(fixture);
                }
                printf("  day-second form vs MATLAB : R %.3g, Rdot %.3g over %d epochs, step %g\n",
                       worstDayR, worstDayRdot, rows, fixtureStep);
                printf("  MJD form on the same rows : R %.3g, Rdot %.3g; arc rows R %.3g, Rdot %.3g\n",
                       worstMjdR, worstMjdRdot, worstArcR, worstArcRdot);
                check(rowsOk && rows > 0 && rows == dataLines,
                      "every row of the day-and-second fixture is evaluated");
                check(rows > 0 && worstDayR < 5.0e-12,
                      "the day-and-second form gives MATLAB's R");
                check(rows > 0 && worstDayRdot < RATE_BUDGET,
                      "the day-and-second form gives MATLAB's Rdot");
                /* The arc rows on their own, so that the second lost before
                 * 23:59:60 cannot pass this check by itself. */
                check(worstArcR > 5.0e-12 && worstArcRdot > RATE_BUDGET,
                      "the MJD form misses the arc rows, so the fixture tells the forms apart");
                check(worstMjdR > 1.0e-6,
                      "the MJD form loses a whole second of rotation just before a leap second");
            }

            /* ---- what the day-and-second form refuses and carries -------- */
            {
                double sentinel[9];
                double sentinelDot[9];
                double carried[9];
                double named[9];
                int same = 1;
                for (j = 0; j < 9; j++) {
                    sentinel[j] = -1.0;
                    sentinelDot[j] = -1.0;
                }
                check(rsApiRotationDaySecond(&two, 57753.0, 86400.5, sentinel)
                      == RS_API_OUT_OF_RANGE,
                      "23:59:60.5 is refused: the panels cannot represent it");
                check(rsApiRotationDaySecond(&two, 57754.0, -0.5, sentinel)
                      == RS_API_OUT_OF_RANGE,
                      "a negative second carried back into the leap second is refused");
                check(rsApiRotationRateDaySecond(&two, 57753.0, 86200.5, 200.0,
                          sentinel, sentinelDot) == RS_API_OUT_OF_RANGE,
                      "a shoulder carried into the leap second is refused");
                check(rsApiRotationDaySecond(&two, 57752.0, -1.0, sentinel)
                      == RS_API_OUT_OF_RANGE,
                      "a second carried before the first panel is out of range");
                check(rsApiRotationDaySecond(&two, 57753.5, 0.0, sentinel)
                      == RS_API_BAD_EPOCH,
                      "a day that is not a whole number is a bad epoch");
                check(rsApiRotationDaySecond(&two, 57753.0, NAN, sentinel)
                      == RS_API_BAD_EPOCH
                      && rsApiRotationDaySecond(&two, HUGE_VAL, 0.0, sentinel)
                      == RS_API_BAD_EPOCH,
                      "a day or second that is not finite is a bad epoch");
                check(sentinel[0] == -1.0 && sentinelDot[0] == -1.0,
                      "a refused day and second leave the outputs untouched");
                check(rsApiRotationDaySecond(NULL, 57753.0, 0.0, sentinel)
                      == RS_API_NULL_ARGUMENT,
                      "the day-and-second form checks its interpolant first");
                /* 86400.5 s into an ordinary day is 0.5 s into the next. */
                if (rsApiRotationDaySecond(&two, 57755.0, 86400.5, carried) == RS_API_OK
                    && rsApiRotationDaySecond(&two, 57756.0, 0.5, named) == RS_API_OK) {
                    for (j = 0; j < 9; j++) {
                        if (carried[j] != named[j]) same = 0;
                    }
                } else {
                    same = 0;
                }
                check(same, "a second past an ordinary day is carried into the next, bit for bit");
                /* ACROSS THE LEAP SECOND THE CARRY IS WHAT KEEPS UT1 RIGHT.
                 * Uncarried, -1.5 s on 57754 reads the right panel but forms
                 * UT1 from the wrong day's label, a second off; the ordinary day
                 * above cannot see that, and a fault that skipped the carry
                 * passed it. 86401.5 s on 57753 is 0.5 s into 57754. */
                same = 1;
                if (rsApiRotationDaySecond(&two, 57754.0, -1.5, carried) == RS_API_OK
                    && rsApiRotationDaySecond(&two, 57753.0, 86399.5, named) == RS_API_OK) {
                    for (j = 0; j < 9; j++) {
                        if (carried[j] != named[j]) same = 0;
                    }
                } else {
                    same = 0;
                }
                if (rsApiRotationDaySecond(&two, 57753.0, 86401.5, carried) == RS_API_OK
                    && rsApiRotationDaySecond(&two, 57754.0, 0.5, named) == RS_API_OK) {
                    for (j = 0; j < 9; j++) {
                        if (carried[j] != named[j]) same = 0;
                    }
                } else {
                    same = 0;
                }
                check(same, "a second carried across the leap second lands on its own side, bit for bit");
            }
        }
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
