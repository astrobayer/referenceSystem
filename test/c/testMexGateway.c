/*
 * testMexGateway.c
 * ----------------
 * Exercises the control flow of mex/mexGateway.c with plain gcc, using the
 * stand-in mex API in mexStub.h. It checks the things that are cheap to get
 * wrong and expensive to diagnose from MATLAB: command dispatch, per-command
 * nrhs and nlhs validation, scalar broadcasting, output shaping, and that the
 * unknown commands are rejected by name.
 *
 * It is not a numerical test; rsCore's numbers are checked by testRsCore.c.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:55 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "mexStub.h"
#include "rsCore.h"
#include <math.h>
#include <string.h>

/* The gateway is compiled into this translation unit so that its static
 * helpers are reachable and no MATLAB entry point is needed. */
#include "mexGateway.c"

static int testCount = 0;
static int failCount = 0;

static void report(int ok, const char *name, const char *detail)
{
    testCount++;
    if (ok) {
        printf("  PASS  %-52s\n", name);
    } else {
        failCount++;
        printf("  FAIL  %-52s %s\n", name, detail);
    }
}

static void expectError(const char *expectedId, const char *name,
                        int nlhs, mxArray *plhs[], int nrhs, mxArray *prhs[])
{
    RS_TRY(mexFunction(nlhs, plhs, nrhs, (const mxArray **)prhs));
    report(strcmp(rsStubErrorId, expectedId) == 0, name,
           rsStubErrorId[0] ? rsStubErrorId : "(no error raised)");
}

static void expectSuccess(const char *name, int nlhs, mxArray *plhs[],
                          int nrhs, mxArray *prhs[])
{
    RS_TRY(mexFunction(nlhs, plhs, nrhs, (const mxArray **)prhs));
    report(rsStubErrorId[0] == '\0', name, rsStubErrorId);
}

int main(void)
{
    double day[3] = {57753.0, 57754.0, 58849.0};
    double sec[3] = {0.0, 0.0, 43200.0};
    mxArray *plhs[4];
    mxArray *prhs[16];

    puts("referenceSystem mexGateway logic tests (stubbed mex API)\n");

    /* --- dispatch --------------------------------------------------- */
    prhs[0] = mxCreateString("nosuchcommand");
    expectError("referenceSystem:mex:unknownCommand", "unknown command rejected",
                1, plhs, 1, prhs);

    /* Obligation O4 closed in S3: 'dcm' answers. Until P9 it raised
     * notImplemented, and the test that asserted so is replaced here rather
     * than kept alongside its successor -- two tests asserting one property is
     * the same defect as two sources of truth (handover revision 1.27). The
     * command is exercised for real further down. */
    prhs[0] = mxCreateString("dcm");
    expectError("referenceSystem:mex:inputCount",
                "'dcm' answers and validates its input count", 1, plhs, 1, prhs);

    /* S2 answered these two (obligation O3), so what is asserted now is that
     * they are wired up and validate their arguments like every other command:
     * called with no epoch they must complain about the input count, not about
     * being unimplemented and not about an unknown command. */
    prhs[0] = mxCreateString("subdaily");
    expectError("referenceSystem:mex:inputCount",
                "'subdaily' answers and validates its input count", 1, plhs, 1, prhs);

    prhs[0] = mxCreateString("zonaltide");
    expectError("referenceSystem:mex:inputCount",
                "'zonaltide' answers and validates its input count", 1, plhs, 1, prhs);

    prhs[0] = rsStubScalar(1.0);
    expectError("referenceSystem:mex:commandType",
                "non-char command rejected", 1, plhs, 1, prhs);

    /* --- dat -------------------------------------------------------- */
    prhs[0] = mxCreateString("dat");
    prhs[1] = rsStubVector(day, 3);
    prhs[2] = rsStubVector(sec, 3);
    expectSuccess("dat with three epochs", 2, plhs, 3, prhs);
    report(mxGetNumberOfElements(plhs[0]) == 3, "dat returns one value per epoch", "");
    report(fabs(mxGetPr(plhs[0])[0] - 36.0) < 1e-12 &&
           fabs(mxGetPr(plhs[0])[1] - 37.0) < 1e-12,
           "dat brackets the 2017 leap second", "");
    report(mxGetPr(plhs[1])[0] == 0.0, "dat reports status zero", "");

    expectError("referenceSystem:mex:inputCount", "dat rejects a wrong nrhs",
                1, plhs, 2, prhs);
    expectError("referenceSystem:mex:outputCount", "dat rejects a wrong nlhs",
                3, plhs, 3, prhs);

    /* Scalar broadcasting: one second value for three days. */
    prhs[2] = rsStubScalar(0.0);
    expectSuccess("dat broadcasts a scalar second", 1, plhs, 3, prhs);
    report(mxGetNumberOfElements(plhs[0]) == 3, "broadcast keeps the epoch count", "");

    /* A length that is neither 1 nor N is a size mismatch. */
    prhs[2] = rsStubVector(sec, 2);
    expectError("referenceSystem:mex:sizeMismatch", "dat rejects a bad length",
                1, plhs, 3, prhs);

    /* --- dtdb, era00, sp00 ------------------------------------------ */
    prhs[0] = mxCreateString("dtdb");
    prhs[2] = rsStubVector(sec, 3);
    expectSuccess("dtdb", 1, plhs, 3, prhs);
    report(fabs(mxGetPr(plhs[0])[2]) < 2.0e-3, "dtdb is bounded by 2 ms", "");

    prhs[0] = mxCreateString("era00");
    expectSuccess("era00", 1, plhs, 3, prhs);
    report(mxGetPr(plhs[0])[0] >= 0.0 && mxGetPr(plhs[0])[0] < 6.2832,
           "era00 lies in [0, 2pi)", "");

    prhs[0] = mxCreateString("sp00");
    expectSuccess("sp00", 1, plhs, 3, prhs);

    /* --- xys -------------------------------------------------------- */
    prhs[0] = mxCreateString("xys06a");
    expectSuccess("xys06a with three outputs", 3, plhs, 3, prhs);
    report(mxGetNumberOfElements(plhs[2]) == 3, "xys06a s has one value per epoch", "");

    /* --- pom00 ------------------------------------------------------ */
    {
        double xp[2] = {2.55060238e-7, 2.0e-7};
        double yp[2] = {1.860359247e-6, 1.5e-6};
        prhs[0] = mxCreateString("pom00");
        prhs[1] = rsStubVector(xp, 2);
        prhs[2] = rsStubVector(yp, 2);
        prhs[3] = rsStubScalar(-1.3671745807288915e-11);
        expectSuccess("pom00 with a broadcast s'", 1, plhs, 4, prhs);
        report(mxGetNumberOfElements(plhs[0]) == 18,
               "pom00 returns 3x3xN elements", "");
    }

    /* --- fa --------------------------------------------------------- */
    {
        double ttDay[1] = {54465.0};
        double ttSec[1] = {0.0};
        prhs[0] = mxCreateString("fa");
        prhs[1] = rsStubVector(ttDay, 1);
        prhs[2] = rsStubVector(ttSec, 1);
        prhs[3] = rsStubScalar(0.0);
        prhs[4] = rsStubScalar(0.0);
        prhs[5] = rsStubScalar(0.0);
        expectSuccess("fa without UT1", 1, plhs, 6, prhs);
        report(mxGetNumberOfElements(plhs[0]) == (mwSize)RS_FA_COLUMNS,
               "fa returns one row of RS_FA_COLUMNS", "");
        report(isnan(mxGetPr(plhs[0])[RS_FA_TAU]), "fa leaves tau NaN without UT1", "");

        prhs[3] = rsStubScalar(54465.0);
        prhs[4] = rsStubScalar(-65.0);
        prhs[5] = rsStubScalar(1.0);
        expectSuccess("fa with UT1", 1, plhs, 6, prhs);
        report(!isnan(mxGetPr(plhs[0])[RS_FA_TAU]), "fa fills tau with UT1", "");
    }

    /* --- P9 commands -------------------------------------------------- */
    {
        double ttDay[2] = {54195.0, 54195.0};
        double ttSec[2] = {43265.184, 43265.184};
        double ut1Day[2] = {54195.0, 54195.0};
        double ut1Sec[2] = {43199.927926315, 43199.927926315};
        double zero3[6] = {0, 0, 0, 0, 0, 0};
        double poleX[6], poleY[6];
        double ut1MinusTai[6] = {-33.072073685, -33.072073685, -33.072073685,
                                 -33.072073685, -33.072073685, -33.072073685};
        double xValue[2] = {7.12264729599e-4, 7.12264729599e-4};
        double yValue[2] = {4.4385250426e-5, 4.4385250426e-5};
        double sValue[2] = {-1.0668e-8, -1.0668e-8};
        int i;

        for (i = 0; i < 6; i++) {
            poleX[i] = 0.0349282 * 4.848136811095359935899141e-6;
            poleY[i] = 0.4833163 * 4.848136811095359935899141e-6;
        }

        prhs[0] = mxCreateString("cip");
        prhs[1] = rsStubVector(ttDay, 2);
        prhs[2] = rsStubVector(ttSec, 2);
        prhs[3] = rsStubScalar(2006.0);
        prhs[4] = rsStubScalar(0.1750e-3 * 4.848136811095359935899141e-6);
        prhs[5] = rsStubScalar(-0.2259e-3 * 4.848136811095359935899141e-6);
        expectSuccess("cip with two epochs", 3, plhs, 6, prhs);
        report(mxGetNumberOfElements(plhs[0]) == 2, "cip returns one X per epoch",
               "wrong element count");
        /* SOFA cookbook section 5.5, 2007-04-05 12:00:00 UTC. */
        report(fabs(mxGetPr(plhs[0])[0] - 0.000712264729599) < 5e-15,
               "cip reproduces the cookbook X", "X is wrong");
        report(fabs(mxGetPr(plhs[1])[0] - 0.000044385250426) < 5e-15,
               "cip reproduces the cookbook Y", "Y is wrong");

        prhs[3] = rsStubScalar(1999.0);
        expectError("referenceSystem:mex:unknownCipModel",
                    "cip refuses an unknown CIP model", 3, plhs, 6, prhs);

        prhs[0] = mxCreateString("c2ixys");
        prhs[1] = rsStubVector(xValue, 2);
        prhs[2] = rsStubVector(yValue, 2);
        prhs[3] = rsStubVector(sValue, 2);
        expectSuccess("c2ixys", 1, plhs, 4, prhs);
        report(mxGetNumberOfElements(plhs[0]) == 18,
               "c2ixys returns 3x3xN elements", "wrong element count");

        prhs[0] = mxCreateString("gst");
        prhs[1] = rsStubVector(ut1Day, 2);
        prhs[2] = rsStubVector(ut1Sec, 2);
        prhs[3] = rsStubVector(ttDay, 2);
        prhs[4] = rsStubVector(ttSec, 2);
        prhs[5] = rsStubScalar(0.0);
        expectSuccess("gst mean", 1, plhs, 6, prhs);
        report(mxGetPr(plhs[0])[0] > 0.0 && mxGetPr(plhs[0])[0] < 6.2831854,
               "gst lies in [0, 2pi)", "out of range");
        prhs[5] = rsStubScalar(1.0);
        expectSuccess("gst apparent", 1, plhs, 6, prhs);

        prhs[0] = mxCreateString("pnm06a");
        prhs[1] = rsStubVector(ttDay, 2);
        prhs[2] = rsStubVector(ttSec, 2);
        expectSuccess("pnm06a", 1, plhs, 3, prhs);
        report(mxGetNumberOfElements(plhs[0]) == 18,
               "pnm06a returns 3x3xN elements", "wrong element count");

        prhs[0] = mxCreateString("dcm");
        prhs[1] = rsStubVector(ttDay, 2);
        prhs[2] = rsStubVector(ttSec, 2);
        prhs[3] = rsStubVector(ut1Day, 2);
        prhs[4] = rsStubVector(ut1Sec, 2);
        prhs[5] = rsStubVector(poleX, 6);
        prhs[6] = rsStubVector(poleY, 6);
        prhs[7] = rsStubVector(zero3, 6);
        prhs[8] = rsStubVector(zero3, 6);
        prhs[9] = rsStubVector(ut1MinusTai, 6);
        prhs[10] = rsStubScalar(2006.0);
        prhs[11] = rsStubScalar(200.0);
        expectSuccess("dcm with one output", 1, plhs, 12, prhs);
        report(mxGetNumberOfElements(plhs[0]) == 18,
               "dcm returns 3x3xN elements", "wrong element count");
        {
            const double *r = mxGetPr(plhs[0]);
            double e = 0.0, sum;
            int row, col, m;
            for (row = 0; row < 3; row++) {
                for (col = 0; col < 3; col++) {
                    sum = 0.0;
                    for (m = 0; m < 3; m++) {
                        sum += r[3 * m + row] * r[3 * m + col];
                    }
                    sum -= (row == col) ? 1.0 : 0.0;
                    if (fabs(sum) > e) e = fabs(sum);
                }
            }
            report(e < 1e-15, "dcm output is orthogonal to 1e-15", "not orthogonal");
        }
        expectSuccess("dcm with three outputs", 3, plhs, 12, prhs);
        report(mxGetNumberOfElements(plhs[1]) == 18 &&
               mxGetNumberOfElements(plhs[2]) == 18,
               "dcm derivatives are 3x3xN", "wrong element count");

        prhs[11] = rsStubScalar(-1.0);
        expectError("referenceSystem:mex:badStep",
                    "dcm refuses a non-positive step", 2, plhs, 12, prhs);
        prhs[11] = rsStubScalar(200.0);

        prhs[5] = rsStubVector(poleX, 2);
        expectError("referenceSystem:mex:sizeMismatch",
                    "dcm refuses polar motion that is not n-by-3",
                    1, plhs, 12, prhs);
        prhs[5] = rsStubVector(poleX, 6);

        prhs[9] = rsStubVector(ut1Day, 2);
        expectError("referenceSystem:mex:sizeMismatch",
                    "dcm refuses UT1 - TAI that is not n-by-3",
                    1, plhs, 12, prhs);
    }

    /* --- info ------------------------------------------------------- */
    prhs[0] = mxCreateString("info");
    expectSuccess("info", 1, plhs, 1, prhs);
    report(mxGetField(plhs[0], 0, "sofaRelease") != NULL, "info has sofaRelease", "");
    report(mxGetField(plhs[0], 0, "faColumnCount") != NULL, "info has faColumnCount", "");
    report(mxGetScalar(mxGetField(plhs[0], 0, "faColumnCount")) ==
           (double)RS_FA_COLUMNS, "info faColumnCount matches the enum", "");
    expectError("referenceSystem:mex:inputCount", "info takes no arguments",
                1, plhs, 2, prhs);

    /* ---- Chebyshev panel commands (prompt P19) ---------------------- */
    {
        /* The point of routing the fit through the gateway is that the MATLAB
         * builder and the C API share ONE implementation. This block asserts
         * the MARSHALLING, not the arithmetic - testCheb.c owns that - and in
         * particular that two quantities fitted side by side give the same
         * coefficients as two separate single-column calls. Column bleed is
         * the failure mode a column-major loop invites. */
        mxArray *nodeOut = NULL, *fitOut = NULL, *soloOut = NULL;
        /* Initialised, so that a failing gateway call leaves a NULL this
         * harness can report rather than a wild pointer it crashes on. A test
         * binary that segfaults on the first failure hides every test after
         * it, which is how this block was written the first time. */
        mxArray *evalOut[2] = {NULL, NULL};
        mxArray *arg[5];
        double t0 = 57754.0, span = 1.0;
        double pair[42], single[21], query[3];
        const double *node, *coefficient;
        int j, ok = 1;

        arg[0] = mxCreateString("chebnodes");
        arg[1] = mxCreateDoubleScalar(t0);
        arg[2] = mxCreateDoubleScalar(span);
        arg[3] = mxCreateDoubleScalar(20.0);
        RS_TRY(mexFunction(1, &nodeOut, 4, (const mxArray **)arg));
        report(rsStubErrorId[0] == '\0' && mxGetM(nodeOut) == 21 &&
               mxGetN(nodeOut) == 1, "chebnodes returns degree+1 nodes",
               rsStubErrorId);
        node = mxGetPr(nodeOut);
        report(fabs(node[20] - t0) < 1e-12 &&
               fabs(node[0] - (t0 + span)) < 1e-12,
               "chebnodes spans the panel, last node first", "");

        for (j = 0; j < 21; j++) {
            single[j] = sin(3.0 * (node[j] - t0));
            pair[j] = single[j];
            pair[21 + j] = cos(5.0 * (node[j] - t0));
        }
        arg[0] = mxCreateString("chebfit");
        arg[1] = mxCreateDoubleMatrix(21, 2, mxREAL);
        memcpy(mxGetPr(arg[1]), pair, sizeof pair);
        RS_TRY(mexFunction(1, &fitOut, 2, (const mxArray **)arg));
        report(rsStubErrorId[0] == '\0' && mxGetM(fitOut) == 21 &&
               mxGetN(fitOut) == 2, "chebfit preserves the shape of its input",
               rsStubErrorId);
        coefficient = mxGetPr(fitOut);

        arg[0] = mxCreateString("chebfit");
        arg[1] = mxCreateDoubleMatrix(21, 1, mxREAL);
        memcpy(mxGetPr(arg[1]), single, sizeof single);
        RS_TRY(mexFunction(1, &soloOut, 2, (const mxArray **)arg));
        for (j = 0; j < 21; j++) {
            if (mxGetPr(soloOut)[j] != coefficient[j]) {
                ok = 0;
            }
        }
        report(ok, "chebfit column 1 is bit-identical without the second column",
               "column bleed");

        query[0] = t0;
        query[1] = t0 + 0.5 * span;
        query[2] = t0 + span;
        arg[0] = mxCreateString("chebeval");
        arg[1] = fitOut;
        arg[2] = mxCreateDoubleScalar(t0);
        arg[3] = mxCreateDoubleScalar(span);
        arg[4] = mxCreateDoubleMatrix(3, 1, mxREAL);
        memcpy(mxGetPr(arg[4]), query, sizeof query);
        RS_TRY(mexFunction(2, evalOut, 5, (const mxArray **)arg));
        report(rsStubErrorId[0] == '\0' && mxGetM(evalOut[0]) == 3 &&
               mxGetN(evalOut[0]) == 2,
               "chebeval is one row per epoch, one column per quantity",
               rsStubErrorId);
        report(evalOut[1] != NULL && mxGetM(evalOut[1]) == 3 &&
               mxGetN(evalOut[1]) == 2,
               "chebeval rate has the same shape as the value", "no rate");
        report(evalOut[0] != NULL &&
               fabs(mxGetPr(evalOut[0])[0] - 0.0) < 1e-9 &&
               fabs(mxGetPr(evalOut[0])[3] - 1.0) < 1e-9,
               "chebeval reproduces both quantities at the panel start", "");
        /* d/dt sin(3x) at x = 0 is 3 per day: this is the 2/span chain rule,
         * and it is the factor most easily dropped in the marshalling. */
        report(evalOut[1] != NULL && fabs(mxGetPr(evalOut[1])[0] - 3.0) < 1e-6,
               "chebeval rate carries the 2/span chain rule", "");

        arg[0] = mxCreateString("chebeval");
        arg[1] = fitOut;
        arg[2] = mxCreateDoubleScalar(t0);
        arg[3] = mxCreateDoubleScalar(span);
        arg[4] = mxCreateDoubleScalar(t0 + 2.0 * span);
        expectError("referenceSystem:mex:outOfPanel",
                    "chebeval refuses an epoch outside the panel",
                    1, evalOut, 5, arg);
    }

    /* ---- dcmcip: the rotation from a precomputed CIP (prompt P19b) ---- */
    {
        /* Same equivalence as testCheb's testCipInjection, but through the
         * GATEWAY rather than the core, so that the marshalling of three extra
         * n-by-3 arrays is what is under test. Feeding dcmcip the CIP that dcm
         * would have computed must give bit-identical matrices; anything else
         * is an indexing or blocking error in the argument handling and is
         * invisible to an accuracy test.
         */
        mxArray *dcmOut[3] = {NULL, NULL, NULL};
        mxArray *cipOut[3] = {NULL, NULL, NULL};
        mxArray *cipVals[3] = {NULL, NULL, NULL};
        mxArray *arg[16];
        const int epochCount = 3;
        double worst = 0.0;
        int j, i, ok = 1;

        for (j = 0; j <= 14; j++) {
            arg[j] = NULL;
        }
        arg[0] = mxCreateString("dcm");
        arg[1] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
        arg[2] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
        arg[3] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
        arg[4] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
        for (j = 5; j <= 9; j++) {
            arg[j] = mxCreateDoubleMatrix(epochCount, 3, mxREAL);
        }
        arg[10] = mxCreateDoubleScalar(2006.0);
        arg[11] = mxCreateDoubleScalar(60.0);
        for (i = 0; i < epochCount; i++) {
            mxGetPr(arg[1])[i] = 57754.0 + (double)i;
            mxGetPr(arg[2])[i] = 43200.0 + 137.0 * (double)i;
            mxGetPr(arg[3])[i] = 57754.0 + (double)i;
            mxGetPr(arg[4])[i] = 43200.0 + 137.0 * (double)i - 69.184;
            for (j = 0; j < 3; j++) {
                /* UT1 - TAI changing at 2e-8 s/s, so the rate term is live. */
                mxGetPr(arg[9])[j * epochCount + i] =
                    -37.0 + 2.0e-8 * 60.0 * (double)(j - 1);
                mxGetPr(arg[5])[j * epochCount + i] = 1.0e-7 * (double)(i + 1);
                mxGetPr(arg[6])[j * epochCount + i] = 2.0e-7 * (double)(i + 1);
                mxGetPr(arg[7])[j * epochCount + i] = 1.0e-10;
                mxGetPr(arg[8])[j * epochCount + i] = -2.0e-10;
            }
        }
        RS_TRY(mexFunction(2, dcmOut, 12, (const mxArray **)arg));
        report(rsStubErrorId[0] == '\0' && dcmOut[0] != NULL,
               "dcm still succeeds with the same arguments", rsStubErrorId);

        /* The CIP dcm would have used, obtained from the cip command so that
         * the two are produced by the same code rather than by two copies. */
        {
            mxArray *cipArg[6];
            mxArray *sample[3];
            int s;
            for (s = 0; s < 3; s++) {
                cipVals[s] = mxCreateDoubleMatrix(epochCount, 3, mxREAL);
            }
            for (j = 0; j < 3; j++) {
                double shift = (j == 0) ? -60.0 : ((j == 2) ? 60.0 : 0.0);
                cipArg[0] = mxCreateString("cip");
                cipArg[1] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
                cipArg[2] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
                cipArg[3] = mxCreateDoubleScalar(2006.0);
                cipArg[4] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
                cipArg[5] = mxCreateDoubleMatrix(epochCount, 1, mxREAL);
                for (i = 0; i < epochCount; i++) {
                    mxGetPr(cipArg[1])[i] = mxGetPr(arg[1])[i];
                    mxGetPr(cipArg[2])[i] = mxGetPr(arg[2])[i] + shift;
                    mxGetPr(cipArg[4])[i] = 1.0e-10;
                    mxGetPr(cipArg[5])[i] = -2.0e-10;
                }
                sample[0] = NULL; sample[1] = NULL; sample[2] = NULL;
                RS_TRY(mexFunction(3, sample, 6, (const mxArray **)cipArg));
                if (sample[0] == NULL) {
                    ok = 0;
                    break;
                }
                for (s = 0; s < 3; s++) {
                    for (i = 0; i < epochCount; i++) {
                        mxGetPr(cipVals[s])[j * epochCount + i] =
                            mxGetPr(sample[s])[i];
                    }
                }
            }
            report(ok, "the cip command supplied all three samples", rsStubErrorId);
        }

        arg[0] = mxCreateString("dcmcip");
        arg[12] = cipVals[0];
        arg[13] = cipVals[1];
        arg[14] = cipVals[2];
        RS_TRY(mexFunction(2, cipOut, 15, (const mxArray **)arg));
        report(rsStubErrorId[0] == '\0' && cipOut[0] != NULL,
               "dcmcip succeeds with fifteen arguments", rsStubErrorId);

        if (ok && dcmOut[0] != NULL && cipOut[0] != NULL) {
            for (i = 0; i < 9 * epochCount; i++) {
                double d = fabs(mxGetPr(dcmOut[0])[i] - mxGetPr(cipOut[0])[i]);
                if (d > worst) worst = d;
                d = fabs(mxGetPr(dcmOut[1])[i] - mxGetPr(cipOut[1])[i]);
                if (d > worst) worst = d;
            }
        }
        printf("  dcmcip vs dcm, worst element difference : %.3g\n", worst);
        /* Both calls must have produced matrices, or a pair of failures would
         * leave worst at zero and pass this check vacuously. */
        report(ok && dcmOut[0] != NULL && cipOut[0] != NULL && worst == 0.0,
               "dcmcip with the model's own CIP is BIT-IDENTICAL to dcm", "");

        arg[0] = mxCreateString("dcmcip");
        expectError("referenceSystem:mex:inputCount",
                    "dcmcip refuses the twelve-argument dcm call",
                    2, cipOut, 12, arg);
    }

    printf("\n%d tests, %d failures\n", testCount, failCount);
    return (failCount == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
