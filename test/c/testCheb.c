/*
 * testCheb.c
 * ----------
 * Standalone suite for mex/rsCheb.c, built and run by runStandaloneTests.sh.
 *
 * The arithmetic is validated here, in C, before any MATLAB exists. That is
 * the session S3 pattern: every failure this file catches is a failure the
 * MATLAB layer never has to diagnose through a MEX boundary.
 *
 * Three kinds of check, in the section D.1 sense:
 *   reference  - the fit reproduces analytic functions whose exact value and
 *                exact derivative are known independently of this toolbox.
 *   precision  - the fit reproduces SOFA iauXys06a and the IERS sub-daily
 *                models to the accuracy decision D82 claims for degree 20.
 *   contract   - degree, span and panel bounds are refused, and a refused call
 *                leaves its output untouched.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-27 09:40 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "rsCheb.h"
#include "iers/iersModels.h"
#include "sofa/sofa.h"
#include "rsCore.h"
#include <math.h>
#include <stdio.h>

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

static void checkBelow(double actual, double limit, const char *name)
{
    testCount++;
    if (!(actual <= limit)) {
        failCount++;
        printf("  FAIL  %s: %.6g exceeds %.6g\n", name, actual, limit);
    }
}

/* Radians to microarcseconds. */
static const double RS_RAD_TO_UAS = 1.0 / (4.8481368110953599e-6 * 1e-6);

/* ------------------------------------------------------------------ */
/* reference: analytic functions with known derivatives               */
/* ------------------------------------------------------------------ */
static void testAnalytic(void)
{
    const int degree = 20;
    const double t0 = 100.0, span = 2.0;
    double node[RS_CHEB_MAX_DEGREE + 1];
    double value[RS_CHEB_MAX_DEGREE + 1];
    double coefficient[RS_CHEB_MAX_DEGREE + 1];
    double worstValue = 0.0, worstSlope = 0.0, residual;
    int allInside = 1;
    int j, i, status;

    /* A cubic is in the space exactly, so both the fit and its derivative
     * must be exact to roundoff. If the derivative recurrence carried a wrong
     * factor this is where it shows, with nothing else to blame. */
    status = rsChebNodes(t0, span, degree, node);
    check(status == RS_CHEB_OK, "rsChebNodes accepts a valid panel");
    for (j = 0; j <= degree; j++) {
        double x = node[j] - t0;
        value[j] = 2.0 + 3.0 * x - 1.5 * x * x + 0.25 * x * x * x;
    }
    check(rsChebFit(value, degree, coefficient) == RS_CHEB_OK,
          "rsChebFit accepts a valid degree");
    check(rsChebNodeResidual(coefficient, value, degree, &residual) == RS_CHEB_OK
          && residual < 1e-12, "node residual of an exact cubic is roundoff");

    for (i = 0; i <= 400; i++) {
        double t = t0 + span * (double)i / 400.0;
        double x = t - t0;
        double exactValue = 2.0 + 3.0 * x - 1.5 * x * x + 0.25 * x * x * x;
        double exactSlope = 3.0 - 3.0 * x + 0.75 * x * x;
        double got, slope, difference;

        if (rsChebEval(coefficient, degree, t0, span, t, &got) != RS_CHEB_OK) {
            allInside = 0;
        }
        difference = fabs(got - exactValue);
        if (difference > worstValue) worstValue = difference;

        if (rsChebEvalDerivative(coefficient, degree, t0, span, t, &slope)
                != RS_CHEB_OK) {
            allInside = 0;
        }
        difference = fabs(slope - exactSlope);
        if (difference > worstSlope) worstSlope = difference;
    }
    check(allInside, "every point of the closed panel evaluates");
    checkBelow(worstValue, 1e-11, "cubic is reproduced exactly");
    checkBelow(worstSlope, 1e-10, "ANALYTIC DERIVATIVE of a cubic is exact");

    /* A sinusoid the space does not contain: the derivative must still agree
     * with a central difference OF THE FIT, which tests the recurrence rather
     * than the fit's accuracy. */
    for (j = 0; j <= degree; j++) {
        value[j] = sin(3.0 * (node[j] - t0)) + 0.5 * cos(7.0 * (node[j] - t0));
    }
    rsChebFit(value, degree, coefficient);
    worstSlope = 0.0;
    for (i = 1; i < 400; i++) {
        double t = t0 + span * (double)i / 400.0;
        double h = 1e-5, ahead, behind, slope, difference;
        rsChebEval(coefficient, degree, t0, span, t + h, &ahead);
        rsChebEval(coefficient, degree, t0, span, t - h, &behind);
        rsChebEvalDerivative(coefficient, degree, t0, span, t, &slope);
        difference = fabs(slope - (ahead - behind) / (2.0 * h));
        if (difference > worstSlope) worstSlope = difference;
    }
    checkBelow(worstSlope, 1e-6,
               "derivative recurrence agrees with a difference of the fit");
}

/* ------------------------------------------------------------------ */
/* precision: the D82 accuracy claim, against the real models          */
/* ------------------------------------------------------------------ */
static void testCipPanel(void)
{
    const int degree = 20;
    const double t0 = 57754.0, span = 1.0;
    double node[RS_CHEB_MAX_DEGREE + 1];
    double vx[RS_CHEB_MAX_DEGREE + 1], vy[RS_CHEB_MAX_DEGREE + 1];
    double vs[RS_CHEB_MAX_DEGREE + 1];
    double cx[RS_CHEB_MAX_DEGREE + 1], cy[RS_CHEB_MAX_DEGREE + 1];
    double cs[RS_CHEB_MAX_DEGREE + 1];
    double worst = 0.0;
    int j, i;

    rsChebNodes(t0, span, degree, node);
    for (j = 0; j <= degree; j++) {
        iauXys06a(2400000.5, node[j], &vx[j], &vy[j], &vs[j]);
    }
    rsChebFit(vx, degree, cx);
    rsChebFit(vy, degree, cy);
    rsChebFit(vs, degree, cs);

    for (i = 0; i <= 1000; i++) {
        double t = t0 + span * (double)i / 1000.0;
        double x, y, s, got, difference;
        iauXys06a(2400000.5, t, &x, &y, &s);
        rsChebEval(cx, degree, t0, span, t, &got);
        difference = fabs(got - x) * RS_RAD_TO_UAS;
        if (difference > worst) worst = difference;
        rsChebEval(cy, degree, t0, span, t, &got);
        difference = fabs(got - y) * RS_RAD_TO_UAS;
        if (difference > worst) worst = difference;
        rsChebEval(cs, degree, t0, span, t, &got);
        difference = fabs(got - s) * RS_RAD_TO_UAS;
        if (difference > worst) worst = difference;
    }
    printf("  CIP  X,Y,s  degree 20, 1 d panel : worst %.4g uas\n", worst);
    /* Decision D22 offers 0.01 uas as its tightest tolerance. The measured
     * floor in handover section B.9.2 is four orders below that; the limit
     * asserted here is 0.001 uas, which is loose enough to survive a compiler
     * changing its mind about a cosine and tight enough that a real regression
     * in the fit cannot hide under it. */
    checkBelow(worst, 1.0e-3, "CIP panel meets the D82 accuracy claim");
}

static void testSubdailyPanel(void)
{
    const int degree = 20;
    const double t0 = 57754.0, span = 1.0;
    double node[RS_CHEB_MAX_DEGREE + 1];
    double value[3][RS_CHEB_MAX_DEGREE + 1];
    double coefficient[3][RS_CHEB_MAX_DEGREE + 1];
    double worst[3] = {0.0, 0.0, 0.0};
    int j, i, comp;

    rsChebNodes(t0, span, degree, node);
    for (j = 0; j <= degree; j++) {
        double eop[3], pm[2], dut1, dlod;
        iersOrthoEop(node[j], eop);
        iersPmsdnut2(node[j], pm);
        iersUtlibr(node[j], &dut1, &dlod);
        value[0][j] = eop[0] + pm[0];
        value[1][j] = eop[1] + pm[1];
        value[2][j] = eop[2] + dut1;
    }
    for (comp = 0; comp < 3; comp++) {
        rsChebFit(value[comp], degree, coefficient[comp]);
    }

    for (i = 0; i <= 2000; i++) {
        double t = t0 + span * (double)i / 2000.0;
        double eop[3], pm[2], dut1, dlod, truth[3], got, difference;
        iersOrthoEop(t, eop);
        iersPmsdnut2(t, pm);
        iersUtlibr(t, &dut1, &dlod);
        truth[0] = eop[0] + pm[0];
        truth[1] = eop[1] + pm[1];
        truth[2] = eop[2] + dut1;
        for (comp = 0; comp < 3; comp++) {
            rsChebEval(coefficient[comp], degree, t0, span, t, &got);
            difference = fabs(got - truth[comp]);
            if (difference > worst[comp]) worst[comp] = difference;
        }
    }
    printf("  SUB-DAILY  degree 20, 1 d panel : xp %.4g uas, yp %.4g uas, "
           "dUT1 %.4g us\n", worst[0], worst[1], worst[2]);
    /* THIS is the binding quantity, not the CIP (section B.9.2). The limit is
     * 1e-4 uas: measured is 2.6e-7, so there are three orders of headroom, and
     * a drop to degree 16 - which measures 3.6e-4 - would fail here. That is
     * deliberate. Degree is the one parameter D82 fixes and the suite should
     * notice if it moves. */
    checkBelow(worst[0], 1.0e-4, "sub-daily xp meets the D82 accuracy claim");
    checkBelow(worst[1], 1.0e-4, "sub-daily yp meets the D82 accuracy claim");
    checkBelow(worst[2], 1.0e-5, "sub-daily dUT1 meets the D82 accuracy claim");
}

/* ------------------------------------------------------------------ */
/* contract                                                            */
/* ------------------------------------------------------------------ */
static void testContract(void)
{
    const int degree = 20;
    const double t0 = 57754.0, span = 1.0;
    double node[RS_CHEB_MAX_DEGREE + 1];
    double value[RS_CHEB_MAX_DEGREE + 1];
    double coefficient[RS_CHEB_MAX_DEGREE + 1];
    double sentinel = -12345.0;
    int j, status;

    rsChebNodes(t0, span, degree, node);
    for (j = 0; j <= degree; j++) {
        value[j] = sin(node[j]);
    }
    rsChebFit(value, degree, coefficient);

    check(rsChebNodes(t0, span, 0, node) == RS_CHEB_BAD_DEGREE,
          "degree 0 is refused");
    check(rsChebNodes(t0, span, RS_CHEB_MAX_DEGREE + 1, node)
          == RS_CHEB_BAD_DEGREE, "degree above the ceiling is refused");
    check(rsChebNodes(t0, 0.0, degree, node) == RS_CHEB_BAD_SPAN,
          "zero span is refused");
    check(rsChebNodes(t0, -1.0, degree, node) == RS_CHEB_BAD_SPAN,
          "negative span is refused");

    /* A NaN span must be refused rather than propagated. The check is written
     * as !(span > 0) precisely so that NaN fails it; written as (span <= 0) it
     * would pass and the panel would evaluate to NaN with a status of OK. */
    check(rsChebNodes(t0, 0.0 / 0.0, degree, node) == RS_CHEB_BAD_SPAN,
          "NaN span is refused");

    /* Section C.6 rule 5: a refused call leaves its output alone. */
    status = rsChebEval(coefficient, degree, t0, span, t0 + 2.0 * span,
                        &sentinel);
    check(status == RS_CHEB_OUT_OF_PANEL, "evaluation past the panel is refused");
    check(sentinel == -12345.0, "a refused evaluation does not touch its output");

    status = rsChebEvalDerivative(coefficient, degree, t0, span, t0 - span,
                                  &sentinel);
    check(status == RS_CHEB_OUT_OF_PANEL, "derivative past the panel is refused");
    check(sentinel == -12345.0, "a refused derivative does not touch its output");

    /* Both panel ends are inside, and the edge slack absorbs a rounded
     * boundary without admitting a usable extrapolation. */
    check(rsChebEval(coefficient, degree, t0, span, t0, &sentinel)
          == RS_CHEB_OK, "the panel start is inside");
    check(rsChebEval(coefficient, degree, t0, span, t0 + span, &sentinel)
          == RS_CHEB_OK, "the panel end is inside");
    check(rsChebEval(coefficient, degree, t0, span,
                     t0 + span * (1.0 + 1e-6), &sentinel)
          == RS_CHEB_OUT_OF_PANEL,
          "a microsecond-scale overshoot is still refused");
}

static void testCipInjection(void)
{
    /* PROMPT P19b. The claim: feeding rsRotationItrsToGcrsFromCip the SAME CIP
     * the model would have produced must give bit-identical matrices to the
     * model path. If it does not, the injection is reaching the assembly
     * differently - a blocking or an index error - and no accuracy argument
     * about the interpolant could tell that apart from a bad fit.
     *
     * This is deliberately not an interpolation test. It isolates the wiring. */
    const int n = 4;
    double ttDay[4], ttSec[4], ut1Day[4], ut1Sec[4], omega[4];
    double xp[12], yp[12], dX[12], dY[12];
    double cipX[12], cipY[12], cipS[12];
    double rModel[36], rInject[36];
    double rdotModel[36], rdotInject[36];
    double worst = 0.0;
    int k, j, i, status;
    const double step = 60.0;

    for (k = 0; k < n; k++) {
        ttDay[k] = 57754.0 + (double)k;
        ttSec[k] = 43200.0 + 137.0 * (double)k;
        ut1Day[k] = ttDay[k];
        ut1Sec[k] = ttSec[k] - 69.184;
        omega[k] = 7.292115e-5;
        for (j = 0; j < 3; j++) {
            xp[j * n + k] = 1.0e-7 * (double)(k + 1);
            yp[j * n + k] = 2.0e-7 * (double)(k + 1);
            dX[j * n + k] = 1.0e-10;
            dY[j * n + k] = -2.0e-10;
        }
    }

    /* The CIP the model would produce at each of the three samples, offsets
     * included - which is exactly what the interpolant is required to hold. */
    for (k = 0; k < n; k++) {
        double offset[3];
        offset[0] = -step; offset[1] = 0.0; offset[2] = step;
        for (j = 0; j < 3; j++) {
            double one[1], oneY[1], oneS[1];
            double day = ttDay[k], sec = ttSec[k] + offset[j];
            rsCipCoordinates(1, &day, &sec, 2006, &dX[j * n + k], &dY[j * n + k],
                             one, oneY, oneS);
            cipX[j * n + k] = one[0];
            cipY[j * n + k] = oneY[0];
            cipS[j * n + k] = oneS[0];
        }
    }

    status = rsRotationItrsToGcrs(n, ttDay, ttSec, ut1Day, ut1Sec, xp, yp,
        dX, dY, omega, 2006, 1, step, rModel, rdotModel, NULL);
    check(status == 0, "the model path succeeds");
    status = rsRotationItrsToGcrsFromCip(n, ttDay, ttSec, ut1Day, ut1Sec, xp, yp,
        dX, dY, omega, cipX, cipY, cipS, 2006, 1, step, rInject, rdotInject, NULL);
    check(status == 0, "the injected path succeeds");

    for (i = 0; i < 9 * n; i++) {
        double d = fabs(rModel[i] - rInject[i]);
        if (d > worst) worst = d;
        d = fabs(rdotModel[i] - rdotInject[i]);
        if (d > worst) worst = d;
    }
    printf("  CIP injection vs model, worst element difference : %.3g\n", worst);
    check(worst == 0.0,
          "an injected CIP equal to the model gives BIT-IDENTICAL R and Rdot");

    /* All three or none. Two is a half-converted caller and the failure would
     * otherwise be silent: X and Y from the panel, s from the model. */
    check(rsRotationItrsToGcrsFromCip(n, ttDay, ttSec, ut1Day, ut1Sec, xp, yp,
        dX, dY, omega, cipX, cipY, NULL, 2006, 0, step, rInject, NULL, NULL) == -4,
        "two of the three CIP arrays are refused");
    check(rsRotationItrsToGcrsFromCip(n, ttDay, ttSec, ut1Day, ut1Sec, xp, yp,
        dX, dY, omega, cipX, cipY, cipS, 1999, 0, step, rInject, NULL, NULL) == -1,
        "cipModel is validated even when it is unread");
}

int main(void)
{
    printf("testCheb: Chebyshev panel core (prompt P19, decision D82)\n");
    testAnalytic();
    testCipPanel();
    testSubdailyPanel();
    testContract();
    testCipInjection();
    printf("\n%d tests, %d failures\n", testCount, failCount);
    return failCount == 0 ? 0 : 1;
}
