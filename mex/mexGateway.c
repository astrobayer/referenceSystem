/*
 * mexGateway.c
 * ------------
 * The single, command-dispatched MEX entry point of the referenceSystem
 * toolbox. It is package-private: the compiled binary is written to
 * +referenceSystem/private/, so nothing outside the package can call it, and
 * the only part of it visible to a user is referenceSystem.mexInfo, which
 * wraps the 'info' command.
 *
 *   varargout = mexGateway(command, varargin)
 *
 * Commands (handover P2):
 *
 *   [deltaAt, status] = mexGateway('dat', day, sec)
 *       TAI - UTC in seconds and the per-epoch SOFA code. day and sec are a
 *       split UTC epoch. The status output is internal and undocumented at
 *       the user-facing level: leapSecondTable consumes it and turns it into a
 *       warning or an error, and never forwards it (decision D3).
 *
 *   tdbMinusTt        = mexGateway('dtdb', day, sec)      split TT epoch
 *   [x, y, s]         = mexGateway('xys06a', day, sec)    split TT epoch
 *   [x, y, s]         = mexGateway('xys00a', day, sec)    split TT epoch
 *   era               = mexGateway('era00', day, sec)     split UT1 epoch
 *   sp                = mexGateway('sp00', day, sec)      split TT epoch
 *   R                 = mexGateway('pom00', xp, yp, sp)   3x3xN pages
 *   fa                = mexGateway('fa', ttDay, ttSec, ut1Day, ut1Sec, hasUt1)
 *                       N x 20, column order fixed by the enum in rsCore.h
 *   [dxp, dyp, dut1]  = mexGateway('subdaily', day, sec)   split UTC epoch
 *                       Sub-daily ocean tide and libration variation in
 *                       polar motion and UT1, radians and seconds.
 *   [dut1, dlod, domega] = mexGateway('zonaltide', day, sec) split TT epoch
 *                       Long-period zonal tide effect on Earth rotation,
 *                       seconds, seconds per day and radians per second.
 *   info              = mexGateway('info')
 *
 *   [R, Rdot, Rddot]  = mexGateway('dcm', ...)     see rsCommandDcm
 *   [R, Rdot, Rddot]  = mexGateway('dcmcip', ...)  see rsCommandDcmCip
 *   [x, y, s]         = mexGateway('cip', ...), q = mexGateway('c2ixys', ...),
 *   gst = mexGateway('gst', ...), npb = mexGateway('pnm06a', ...),
 *   the Chebyshev commands 'chebnodes', 'chebfit', 'chebeval' and
 *   'bodystate': see the comment above each command below.
 *
 * Rules obeyed here (handover section C.4):
 *   - one gateway, command a char row vector;
 *   - every command validates its own nrhs and nlhs;
 *   - mxIsDouble && !mxIsComplex on every numeric input;
 *   - no printf anywhere; errors via mexErrMsgIdAndTxt with
 *     referenceSystem:mex:<reason>;
 *   - every allocation is freed on every path. Validation is complete before
 *     the first allocation, so no error path can leak, and the scratch buffer
 *     used for broadcasting is allocated only when a broadcast is actually
 *     needed (v1 finding m-7 and the v1 defect of allocating eight scratch
 *     buffers unconditionally).
 *
 * Thread clamping (decision D31, section C.9 rule 4): inside a parfor worker
 * OpenMP is clamped to a single thread, so that the correct behaviour is the
 * default and oversubscription requires a deliberate override. The check runs
 * once per MATLAB process, because a MEX file is loaded once per process and
 * a worker is its own process.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:40 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "mex.h"
#include "rsCore.h"
#include "rsCheb.h"
#include <string.h>

#define RS_MAX_COMMAND_LENGTH 32

static int rsClampChecked = 0;
static int rsClampApplied = 0;

/* ---------------------------------------------------------------------- */
/* Argument helpers                                                        */
/* ---------------------------------------------------------------------- */

static void rsRequireNumeric(const mxArray *value, const char *name)
{
    if (!mxIsDouble(value) || mxIsComplex(value)) {
        mexErrMsgIdAndTxt("referenceSystem:mex:inputType",
            "%s must be a real double array.", name);
    }
}

static void rsRequireCounts(int nrhs, int expectedRhs, int nlhs, int maxLhs,
                            const char *command)
{
    if (nrhs != expectedRhs) {
        mexErrMsgIdAndTxt("referenceSystem:mex:inputCount",
            "Command '%s' takes %d input(s) after the command name; %d given.",
            command, expectedRhs - 1, nrhs - 1);
    }
    if (nlhs > maxLhs) {
        mexErrMsgIdAndTxt("referenceSystem:mex:outputCount",
            "Command '%s' returns at most %d output(s); %d requested.",
            command, maxLhs, nlhs);
    }
}

/* Number of epochs, taken from the first per-epoch argument. */
static mwSize rsEpochCount(const mxArray *first, const char *command)
{
    mwSize n = mxGetNumberOfElements(first);
    if (n == 0) {
        mexErrMsgIdAndTxt("referenceSystem:mex:emptyInput",
            "Command '%s' needs at least one epoch.", command);
    }
    return n;
}

/*
 * Pointer to n values taken from value, broadcasting a scalar if necessary.
 * A scratch buffer is allocated only in the scalar case; scratch is set to
 * NULL otherwise so the caller frees nothing it did not allocate.
 */
static const double *rsExpand(const mxArray *value, mwSize n, const char *name,
                              double **scratch)
{
    mwSize count = mxGetNumberOfElements(value);
    const double *source = mxGetPr(value);
    mwSize k;

    *scratch = NULL;
    if (count == n) {
        return source;
    }
    if (count != 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:sizeMismatch",
            "%s must be scalar or have %lu elements; it has %lu.",
            name, (unsigned long)n, (unsigned long)count);
    }
    *scratch = (double *)mxMalloc(sizeof(double) * n);
    for (k = 0; k < n; k++) {
        (*scratch)[k] = source[0];
    }
    return *scratch;
}

static mxArray *rsColumn(mwSize n, double **data)
{
    mxArray *array = mxCreateDoubleMatrix(n, 1, mxREAL);
    *data = mxGetPr(array);
    return array;
}

/* ---------------------------------------------------------------------- */
/* Thread clamping                                                         */
/* ---------------------------------------------------------------------- */

static void rsApplyThreadClamp(void)
{
    mxArray *task = NULL;
    mxArray *exception;

    if (rsClampChecked) {
        return;
    }
    rsClampChecked = 1;

    /* getCurrentTask belongs to the Parallel Computing Toolbox and returns an
     * empty value outside a worker. If the toolbox is absent the call traps,
     * which is itself the answer: there are no workers. */
    exception = mexCallMATLABWithTrap(1, &task, 0, NULL, "getCurrentTask");
    if (exception == NULL && task != NULL && !mxIsEmpty(task)) {
        rsClampApplied = 1;
        rsSetMaxThreads(1);
    }
    if (task != NULL) {
        mxDestroyArray(task);
    }
    if (exception != NULL) {
        mxDestroyArray(exception);
    }
}

/* ---------------------------------------------------------------------- */
/* Commands                                                                */
/* ---------------------------------------------------------------------- */

static void rsCommandDat(int nlhs, mxArray *plhs[], int nrhs,
                         const mxArray *prhs[])
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *deltaAt;
    double *statusOut;
    int *status;
    mwSize k;

    rsRequireCounts(nrhs, 3, nlhs, 2, "dat");
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    n = rsEpochCount(prhs[1], "dat");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);

    plhs[0] = rsColumn(n, &deltaAt);
    status = (int *)mxMalloc(sizeof(int) * n);
    for (k = 0; k < n; k++) {
        deltaAt[k] = 0.0;
        status[k] = 0;
    }

    (void)rsDeltaAt((int)n, day, sec, deltaAt, status);

    if (nlhs > 1) {
        plhs[1] = rsColumn(n, &statusOut);
        for (k = 0; k < n; k++) {
            statusOut[k] = (double)status[k];
        }
    }

    mxFree(status);
    if (scratch != NULL) {
        mxFree(scratch);
    }
}

/*
 * Chebyshev panel commands (prompt P19). The arithmetic lives in rsCheb.c and
 * is validated by test/c/testCheb.c under plain gcc; these three commands do
 * nothing but marshal, so that the MATLAB builder and the public C API share
 * ONE fit rather than agreeing by inspection. A second implementation in
 * MATLAB would be a second authority, and this toolbox has already paid for
 * two of those (rev. 1.53, rev. 1.81).
 *
 * A non-OK status from rsCheb is a programming error at this boundary - the
 * MATLAB layer validates degree, span and range before calling - so it is
 * raised as an error rather than returned. Decision D3 keeps status codes out
 * of MATLAB return values, not out of C.
 */
static void rsChebRaise(int status, const char *command)
{
    if (status == RS_CHEB_OK) {
        return;
    }
    if (status == RS_CHEB_BAD_DEGREE) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badDegree",
            "%s: degree must be between 1 and %d.", command, RS_CHEB_MAX_DEGREE);
    } else if (status == RS_CHEB_BAD_SPAN) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badSpan",
            "%s: span must be finite and strictly positive.", command);
    } else {
        mexErrMsgIdAndTxt("referenceSystem:mex:outOfPanel",
            "%s: an epoch lies outside the panel.", command);
    }
}

static void rsCommandChebNodes(int nlhs, mxArray *plhs[], int nrhs,
                               const mxArray *prhs[])
{
    double t0, span, degreeValue;
    double *node;
    int degree;

    rsRequireCounts(nrhs, 4, nlhs, 1, "chebnodes");
    rsRequireNumeric(prhs[1], "t0");
    rsRequireNumeric(prhs[2], "span");
    rsRequireNumeric(prhs[3], "degree");
    if (mxGetNumberOfElements(prhs[1]) != 1 ||
        mxGetNumberOfElements(prhs[2]) != 1 ||
        mxGetNumberOfElements(prhs[3]) != 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badSize",
            "chebnodes: t0, span and degree are scalars.");
    }
    t0 = mxGetPr(prhs[1])[0];
    span = mxGetPr(prhs[2])[0];
    degreeValue = mxGetPr(prhs[3])[0];
    degree = (int)degreeValue;

    plhs[0] = rsColumn((mwSize)(degree > 0 ? degree + 1 : 1), &node);
    rsChebRaise(rsChebNodes(t0, span, degree, node), "chebnodes");
}

static void rsCommandChebFit(int nlhs, mxArray *plhs[], int nrhs,
                             const mxArray *prhs[])
{
    mwSize rowCount, columnCount, k;
    const double *value;
    double *coefficient;
    int degree;

    rsRequireCounts(nrhs, 2, nlhs, 1, "chebfit");
    rsRequireNumeric(prhs[1], "value");
    rowCount = mxGetM(prhs[1]);
    columnCount = mxGetN(prhs[1]);
    if (rowCount < 2) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badSize",
            "chebfit: value needs at least two rows, one per fit node.");
    }
    degree = (int)rowCount - 1;
    value = mxGetPr(prhs[1]);

    plhs[0] = mxCreateDoubleMatrix(rowCount, columnCount, mxREAL);
    coefficient = mxGetPr(plhs[0]);

    /* Column-major, so each quantity is already contiguous: column k starts at
     * k*rowCount and rsChebFit reads and writes exactly rowCount doubles. No
     * scratch buffer and no transpose. */
    for (k = 0; k < columnCount; k++) {
        rsChebRaise(rsChebFit(value + k * rowCount, degree,
                              coefficient + k * rowCount), "chebfit");
    }
}

static void rsCommandChebEval(int nlhs, mxArray *plhs[], int nrhs,
                              const mxArray *prhs[])
{
    mwSize rowCount, columnCount, epochCount, k, i;
    const double *coefficient;
    const double *t;
    double t0, span;
    double *value;
    double *rate = NULL;
    int degree, wantRate;

    /* One or two outputs, so rsRequireCounts - which asks for an exact nlhs -
     * cannot express it. The rate is optional because computing it costs a
     * second Clenshaw pass over a derivative coefficient array, and a caller
     * that only wants the value should not pay for one. */
    if (nrhs != 5) {
        mexErrMsgIdAndTxt("referenceSystem:mex:inputCount",
            "chebeval takes the coefficients, t0, span and the epochs.");
    }
    if (nlhs < 1 || nlhs > 2) {
        mexErrMsgIdAndTxt("referenceSystem:mex:outputCount",
            "chebeval returns the value and optionally its rate.");
    }
    rsRequireNumeric(prhs[1], "coefficient");
    rsRequireNumeric(prhs[2], "t0");
    rsRequireNumeric(prhs[3], "span");
    rsRequireNumeric(prhs[4], "t");
    if (mxGetNumberOfElements(prhs[2]) != 1 ||
        mxGetNumberOfElements(prhs[3]) != 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badSize",
            "chebeval: t0 and span are scalars.");
    }
    rowCount = mxGetM(prhs[1]);
    columnCount = mxGetN(prhs[1]);
    if (rowCount < 2) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badSize",
            "chebeval: coefficient needs at least two rows.");
    }
    degree = (int)rowCount - 1;
    coefficient = mxGetPr(prhs[1]);
    t0 = mxGetPr(prhs[2])[0];
    span = mxGetPr(prhs[3])[0];
    epochCount = mxGetNumberOfElements(prhs[4]);
    t = mxGetPr(prhs[4]);

    wantRate = (nlhs == 2);
    plhs[0] = mxCreateDoubleMatrix(epochCount, columnCount, mxREAL);
    value = mxGetPr(plhs[0]);
    if (wantRate) {
        plhs[1] = mxCreateDoubleMatrix(epochCount, columnCount, mxREAL);
        rate = mxGetPr(plhs[1]);
    }

    for (k = 0; k < columnCount; k++) {
        for (i = 0; i < epochCount; i++) {
            rsChebRaise(rsChebEval(coefficient + k * rowCount, degree, t0, span,
                                   t[i], value + k * epochCount + i), "chebeval");
            if (wantRate) {
                rsChebRaise(rsChebEvalDerivative(coefficient + k * rowCount,
                    degree, t0, span, t[i], rate + k * epochCount + i),
                    "chebeval");
            }
        }
    }
}

/*
 * The rotation from a precomputed CIP (prompt P19b).
 *
 * Arguments 1..12 are 'dcm' unchanged; 13, 14 and 15 add X, Y and s. Keeping
 * the leading twelve identical is deliberate: the MATLAB side then builds ONE
 * argument list and appends three, so the two paths cannot disagree about the
 * meaning of the first twelve, and a reader comparing the two commands sees
 * only what actually differs.
 *
 * cipModel and the dX, dY arrays are still passed and still validated even
 * though the core does not read them here. Dropping them would make the two
 * argument lists diverge for no gain and would let a caller supply a model
 * number that means nothing until the day the panel is left out.
 */
static void rsCommandDcmCip(int nlhs, mxArray *plhs[], int nrhs,
                            const mxArray *prhs[])
{
    mwSize n;
    mwSize dimensions[3];
    double *scratch[5];
    const double *ttDay;
    const double *ttSec;
    const double *ut1Day;
    const double *ut1Sec;
    double *rdot = NULL;
    double *rddot = NULL;
    int derivativeOrder;
    int argument;
    int status;
    int k;

    rsRequireCounts(nrhs, 15, nlhs, 3, "dcmcip");
    for (argument = 1; argument <= 14; argument++) {
        rsRequireNumeric(prhs[argument], "argument");
    }

    n = rsEpochCount(prhs[1], "dcmcip");
    for (k = 0; k < 5; k++) {
        scratch[k] = NULL;
    }
    ttDay = mxGetPr(prhs[1]);
    ttSec = rsExpand(prhs[2], n, "ttSecOfDay", &scratch[0]);
    ut1Day = rsExpand(prhs[3], n, "ut1Day", &scratch[1]);
    ut1Sec = rsExpand(prhs[4], n, "ut1SecOfDay", &scratch[2]);

    /* Arguments 5..9 are xp, yp, dX, dY and UT1 - TAI, and 12..14 are X, Y,
     * s. All eight are n-by-3 and the same check covers them, because getting
     * one of them a different length from the polar motion is exactly the
     * mistake that would otherwise read past the end of an array. */
    for (argument = 5; argument <= 14; argument++) {
        if (argument == 10 || argument == 11) {
            continue;
        }
        if (mxGetNumberOfElements(prhs[argument]) != 3 * n) {
            mexErrMsgIdAndTxt("referenceSystem:mex:sizeMismatch",
                "Argument %d of 'dcmcip' must be %lu-by-3; it has %lu elements.",
                argument, (unsigned long)n,
                (unsigned long)mxGetNumberOfElements(prhs[argument]));
        }
    }

    derivativeOrder = (nlhs >= 3) ? 2 : ((nlhs == 2) ? 1 : 0);

    dimensions[0] = 3;
    dimensions[1] = 3;
    dimensions[2] = n;
    plhs[0] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
    if (derivativeOrder >= 1) {
        plhs[1] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
        rdot = mxGetPr(plhs[1]);
    }
    if (derivativeOrder >= 2) {
        plhs[2] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
        rddot = mxGetPr(plhs[2]);
    }

    status = rsRotationItrsToGcrsFromCip((int)n, ttDay, ttSec, ut1Day, ut1Sec,
        mxGetPr(prhs[5]), mxGetPr(prhs[6]), mxGetPr(prhs[7]), mxGetPr(prhs[8]),
        mxGetPr(prhs[9]), mxGetPr(prhs[12]), mxGetPr(prhs[13]), mxGetPr(prhs[14]),
        (int)mxGetScalar(prhs[10]), derivativeOrder,
        mxGetScalar(prhs[11]), mxGetPr(plhs[0]), rdot, rddot);

    for (k = 0; k < 5; k++) {
        if (scratch[k] != NULL) {
            mxFree(scratch[k]);
        }
    }

    if (status == -1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:unknownCipModel",
            "cipModel must be 2006 or 2000; it is %d.",
            (int)mxGetScalar(prhs[10]));
    }
    if (status == -3) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badStep",
            "The central-difference step must be positive; it is %g.",
            mxGetScalar(prhs[11]));
    }
    if (status != 0) {
        mexErrMsgIdAndTxt("referenceSystem:mex:internal",
            "Command 'dcmcip' returned status %d.", status);
    }
}

static void rsCommandDtdb(int nlhs, mxArray *plhs[], int nrhs,
                          const mxArray *prhs[])
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *value;

    /* Two forms rather than two commands: the geocentric call takes the epoch
     * alone, the topocentric call adds the four iauDtdb observer arguments.
     * rsRequireCounts asks for an exact count, so the check is written out. */
    if (nrhs != 3 && nrhs != 7) {
        mexErrMsgIdAndTxt("referenceSystem:mex:inputCount",
            "Command 'dtdb' takes 2 or 6 inputs after the command name; "
            "%d given.", nrhs - 1);
    }
    if (nlhs > 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:outputCount",
            "Command 'dtdb' returns at most 1 output; %d requested.", nlhs);
    }
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    n = rsEpochCount(prhs[1], "dtdb");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);

    plhs[0] = rsColumn(n, &value);

    if (nrhs == 3) {
        rsTdbMinusTt((int)n, day, sec, value);
    } else {
        const char *observerName[4] = {"ut1Fraction", "eastLongitude",
                                       "axisDistance", "equatorDistance"};
        double *observerScratch[4] = {NULL, NULL, NULL, NULL};
        const double *observer[4];
        int j;

        for (j = 0; j < 4; j++) {
            rsRequireNumeric(prhs[3 + j], observerName[j]);
            observer[j] = rsExpand(prhs[3 + j], n, observerName[j],
                                   &observerScratch[j]);
        }
        rsTdbMinusTtAtObserver((int)n, day, sec, observer[0], observer[1],
                               observer[2], observer[3], value);
        for (j = 0; j < 4; j++) {
            if (observerScratch[j] != NULL) {
                mxFree(observerScratch[j]);
            }
        }
    }

    if (scratch != NULL) {
        mxFree(scratch);
    }
}

static void rsCommandBodyState(int nlhs, mxArray *plhs[], int nrhs,
                               const mxArray *prhs[])
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *state;
    double *statusOut;
    int *status;
    int body;
    int origin;
    int result;
    mwSize k;

    rsRequireCounts(nrhs, 5, nlhs, 2, "bodystate");
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    rsRequireNumeric(prhs[3], "body");
    rsRequireNumeric(prhs[4], "origin");
    n = rsEpochCount(prhs[1], "bodystate");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);
    body = (int)mxGetScalar(prhs[3]);
    origin = (int)mxGetScalar(prhs[4]);

    /* 6-by-n so that MATLAB reads one column per epoch with no transpose. */
    plhs[0] = mxCreateDoubleMatrix(6, n, mxREAL);
    state = mxGetPr(plhs[0]);
    status = (int *)mxMalloc(sizeof(int) * n);

    result = rsBodyState((int)n, day, sec, body, origin, state, status);

    if (result == -1 || result == -2) {
        /* The array is left as MATLAB created it - all zeros - and nothing
         * partially filled reaches the caller, which is the rule the rotation
         * commands already follow: a plausible stale state is the failure that
         * would not announce itself. */
        mxFree(status);
        if (scratch != NULL) {
            mxFree(scratch);
        }
        mxDestroyArray(plhs[0]);
        plhs[0] = NULL;
        mexErrMsgIdAndTxt("referenceSystem:mex:badArgument",
            "Command 'bodystate' rejected body %d or origin %d (code %d).",
            body, origin, result);
    }

    if (nlhs >= 2) {
        plhs[1] = rsColumn(n, &statusOut);
        for (k = 0; k < n; k++) {
            statusOut[k] = (double)status[k];
        }
    }

    mxFree(status);
    if (scratch != NULL) {
        mxFree(scratch);
    }
}

static void rsCommandXys(int nlhs, mxArray *plhs[], int nrhs,
                         const mxArray *prhs[], int model, const char *command)
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *x;
    double *y;
    double *s;

    rsRequireCounts(nrhs, 3, nlhs, 3, command);
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    n = rsEpochCount(prhs[1], command);
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);

    plhs[0] = rsColumn(n, &x);
    plhs[1] = rsColumn(n, &y);
    plhs[2] = rsColumn(n, &s);
    (void)rsCipXys((int)n, day, sec, model, x, y, s);

    if (scratch != NULL) {
        mxFree(scratch);
    }
}

static void rsCommandEra00(int nlhs, mxArray *plhs[], int nrhs,
                           const mxArray *prhs[])
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *era;

    rsRequireCounts(nrhs, 3, nlhs, 1, "era00");
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    n = rsEpochCount(prhs[1], "era00");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);

    plhs[0] = rsColumn(n, &era);
    rsEarthRotationAngle((int)n, day, sec, era);

    if (scratch != NULL) {
        mxFree(scratch);
    }
}

static void rsCommandSp00(int nlhs, mxArray *plhs[], int nrhs,
                          const mxArray *prhs[])
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *sp;

    rsRequireCounts(nrhs, 3, nlhs, 1, "sp00");
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    n = rsEpochCount(prhs[1], "sp00");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);

    plhs[0] = rsColumn(n, &sp);
    rsTioLocator((int)n, day, sec, sp);

    if (scratch != NULL) {
        mxFree(scratch);
    }
}

static void rsCommandPom00(int nlhs, mxArray *plhs[], int nrhs,
                           const mxArray *prhs[])
{
    mwSize n;
    mwSize dimensions[3];
    double *scratchY = NULL;
    double *scratchS = NULL;
    const double *xp;
    const double *yp;
    const double *sp;

    rsRequireCounts(nrhs, 4, nlhs, 1, "pom00");
    rsRequireNumeric(prhs[1], "xp");
    rsRequireNumeric(prhs[2], "yp");
    rsRequireNumeric(prhs[3], "sp");
    n = rsEpochCount(prhs[1], "pom00");
    xp = mxGetPr(prhs[1]);
    yp = rsExpand(prhs[2], n, "yp", &scratchY);
    sp = rsExpand(prhs[3], n, "sp", &scratchS);

    dimensions[0] = 3;
    dimensions[1] = 3;
    dimensions[2] = n;
    plhs[0] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
    rsPolarMotionMatrix((int)n, xp, yp, sp, mxGetPr(plhs[0]));

    if (scratchY != NULL) {
        mxFree(scratchY);
    }
    if (scratchS != NULL) {
        mxFree(scratchS);
    }
}

static void rsCommandFa(int nlhs, mxArray *plhs[], int nrhs,
                        const mxArray *prhs[])
{
    mwSize n;
    double *scratchTtSec = NULL;
    double *scratchUt1Day = NULL;
    double *scratchUt1Sec = NULL;
    const double *ttDay;
    const double *ttSec;
    const double *ut1Day = NULL;
    const double *ut1Sec = NULL;
    int hasUt1;

    rsRequireCounts(nrhs, 6, nlhs, 1, "fa");
    rsRequireNumeric(prhs[1], "ttDay");
    rsRequireNumeric(prhs[2], "ttSec");
    rsRequireNumeric(prhs[3], "ut1Day");
    rsRequireNumeric(prhs[4], "ut1Sec");
    rsRequireNumeric(prhs[5], "hasUt1");
    if (mxGetNumberOfElements(prhs[5]) != 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:sizeMismatch",
            "hasUt1 must be a scalar flag.");
    }
    n = rsEpochCount(prhs[1], "fa");
    hasUt1 = (mxGetScalar(prhs[5]) != 0.0) ? 1 : 0;

    ttDay = mxGetPr(prhs[1]);
    ttSec = rsExpand(prhs[2], n, "ttSec", &scratchTtSec);
    if (hasUt1) {
        ut1Day = rsExpand(prhs[3], n, "ut1Day", &scratchUt1Day);
        ut1Sec = rsExpand(prhs[4], n, "ut1Sec", &scratchUt1Sec);
    }

    plhs[0] = mxCreateDoubleMatrix(n, (mwSize)RS_FA_COLUMNS, mxREAL);
    rsFundamentalArguments((int)n, ttDay, ttSec, ut1Day, ut1Sec, hasUt1,
                           mxGetPr(plhs[0]));

    if (scratchTtSec != NULL) {
        mxFree(scratchTtSec);
    }
    if (scratchUt1Day != NULL) {
        mxFree(scratchUt1Day);
    }
    if (scratchUt1Sec != NULL) {
        mxFree(scratchUt1Sec);
    }
}

/*
 * The two tidal commands share a shape: one split epoch in, three per-epoch
 * columns out, no status. They differ only in which core function runs and in
 * which time scale the epoch must be, and the scale is the MATLAB layer's
 * business, not this one's -- subdailyEopCorrection and zonalTideEopCorrection
 * refuse a wrong scale before they ever reach here.
 */
static void rsCommandTidal(int nlhs, mxArray *plhs[], int nrhs,
                           const mxArray *prhs[], int isZonal,
                           const char *command)
{
    mwSize n;
    double *scratch = NULL;
    const double *day;
    const double *sec;
    double *first;
    double *second;
    double *third;

    rsRequireCounts(nrhs, 3, nlhs, 3, command);
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "sec");
    n = rsEpochCount(prhs[1], command);
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "sec", &scratch);

    /* All three outputs are always formed. They come from one pass over the
     * models and the models cost the same whether one column or three is
     * kept, so nargout gating would buy nothing here and would only add a
     * branch that could disagree with the MATLAB wrapper. */
    plhs[0] = rsColumn(n, &first);
    plhs[1] = rsColumn(n, &second);
    plhs[2] = rsColumn(n, &third);

    if (isZonal) {
        rsZonalTideEopCorrection((int)n, day, sec, first, second, third);
    } else {
        rsSubdailyEopCorrection((int)n, day, sec, first, second, third);
    }

    if (scratch != NULL) {
        mxFree(scratch);
    }
}

/* ---------------------------------------------------------------------- */
/* Earth rotation, ITRS to GCRS (prompt P9)                                */
/* ---------------------------------------------------------------------- */

/* [x, y, s] = mexGateway('cip', ttDay, ttSec, cipModel, dX, dY) */
static void rsCommandCip(int nlhs, mxArray *plhs[], int nrhs,
                         const mxArray *prhs[])
{
    mwSize n;
    double *scratchSec = NULL;
    double *scratchX = NULL;
    double *scratchY = NULL;
    const double *day;
    const double *sec;
    const double *dX;
    const double *dY;
    double *x;
    double *y;
    double *s;
    int cipModel;

    rsRequireCounts(nrhs, 6, nlhs, 3, "cip");
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "secOfDay");
    rsRequireNumeric(prhs[3], "cipModel");
    rsRequireNumeric(prhs[4], "dX");
    rsRequireNumeric(prhs[5], "dY");

    n = rsEpochCount(prhs[1], "cip");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "secOfDay", &scratchSec);
    cipModel = (int)mxGetScalar(prhs[3]);
    dX = rsExpand(prhs[4], n, "dX", &scratchX);
    dY = rsExpand(prhs[5], n, "dY", &scratchY);

    plhs[0] = rsColumn(n, &x);
    plhs[1] = rsColumn(n, &y);
    plhs[2] = rsColumn(n, &s);

    if (rsCipCoordinates((int)n, day, sec, cipModel, dX, dY, x, y, s) != 0) {
        mexErrMsgIdAndTxt("referenceSystem:mex:unknownCipModel",
            "cipModel must be 2006 or 2000; it is %d.", cipModel);
    }

    if (scratchSec != NULL) mxFree(scratchSec);
    if (scratchX != NULL) mxFree(scratchX);
    if (scratchY != NULL) mxFree(scratchY);
}

/* q = mexGateway('c2ixys', x, y, s) */
static void rsCommandC2ixys(int nlhs, mxArray *plhs[], int nrhs,
                            const mxArray *prhs[])
{
    mwSize n;
    mwSize dimensions[3];
    double *scratchY = NULL;
    double *scratchS = NULL;
    const double *x;
    const double *y;
    const double *s;

    rsRequireCounts(nrhs, 4, nlhs, 1, "c2ixys");
    rsRequireNumeric(prhs[1], "x");
    rsRequireNumeric(prhs[2], "y");
    rsRequireNumeric(prhs[3], "s");
    n = rsEpochCount(prhs[1], "c2ixys");
    x = mxGetPr(prhs[1]);
    y = rsExpand(prhs[2], n, "y", &scratchY);
    s = rsExpand(prhs[3], n, "s", &scratchS);

    dimensions[0] = 3;
    dimensions[1] = 3;
    dimensions[2] = n;
    plhs[0] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
    rsCelestialToIntermediateMatrix((int)n, x, y, s, mxGetPr(plhs[0]));

    if (scratchY != NULL) mxFree(scratchY);
    if (scratchS != NULL) mxFree(scratchS);
}

/* gst = mexGateway('gst', ut1Day, ut1Sec, ttDay, ttSec, apparent) */
static void rsCommandGst(int nlhs, mxArray *plhs[], int nrhs,
                         const mxArray *prhs[])
{
    mwSize n;
    double *scratchUt1Sec = NULL;
    double *scratchTtDay = NULL;
    double *scratchTtSec = NULL;
    const double *ut1Day;
    const double *ut1Sec;
    const double *ttDay;
    const double *ttSec;
    double *gst;

    rsRequireCounts(nrhs, 6, nlhs, 1, "gst");
    rsRequireNumeric(prhs[1], "ut1Day");
    rsRequireNumeric(prhs[2], "ut1SecOfDay");
    rsRequireNumeric(prhs[3], "ttDay");
    rsRequireNumeric(prhs[4], "ttSecOfDay");
    rsRequireNumeric(prhs[5], "apparent");

    n = rsEpochCount(prhs[1], "gst");
    ut1Day = mxGetPr(prhs[1]);
    ut1Sec = rsExpand(prhs[2], n, "ut1SecOfDay", &scratchUt1Sec);
    ttDay = rsExpand(prhs[3], n, "ttDay", &scratchTtDay);
    ttSec = rsExpand(prhs[4], n, "ttSecOfDay", &scratchTtSec);

    plhs[0] = rsColumn(n, &gst);
    rsGreenwichSiderealTime((int)n, ut1Day, ut1Sec, ttDay, ttSec,
        (int)mxGetScalar(prhs[5]) != 0, gst);

    if (scratchUt1Sec != NULL) mxFree(scratchUt1Sec);
    if (scratchTtDay != NULL) mxFree(scratchTtDay);
    if (scratchTtSec != NULL) mxFree(scratchTtSec);
}

/* npb = mexGateway('pnm06a', ttDay, ttSec) */
static void rsCommandPnm06a(int nlhs, mxArray *plhs[], int nrhs,
                            const mxArray *prhs[])
{
    mwSize n;
    mwSize dimensions[3];
    double *scratchSec = NULL;
    const double *day;
    const double *sec;

    rsRequireCounts(nrhs, 3, nlhs, 1, "pnm06a");
    rsRequireNumeric(prhs[1], "day");
    rsRequireNumeric(prhs[2], "secOfDay");
    n = rsEpochCount(prhs[1], "pnm06a");
    day = mxGetPr(prhs[1]);
    sec = rsExpand(prhs[2], n, "secOfDay", &scratchSec);

    dimensions[0] = 3;
    dimensions[1] = 3;
    dimensions[2] = n;
    plhs[0] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
    rsEquinoxNutationMatrix((int)n, day, sec, mxGetPr(plhs[0]));

    if (scratchSec != NULL) mxFree(scratchSec);
}

/*
 * [R, Rdot, Rddot] = mexGateway('dcm', ttDay, ttSec, ut1Day, ut1Sec,
 *                               xp, yp, dX, dY, ut1MinusTai, cipModel, step)
 *
 * xp, yp, dX, dY and UT1 - TAI are n-by-3, sampled at t-step, t and t+step;
 * the Earth rotation rate and its change are formed from the last in rsCore
 * (decision D128). The number
 * of derivatives computed follows nlhs, which is how the nargout gating of
 * rotationItrsToGcrs reaches the arithmetic: with one output requested the
 * CIP series is evaluated once per epoch instead of three times.
 */
static void rsCommandDcm(int nlhs, mxArray *plhs[], int nrhs,
                         const mxArray *prhs[])
{
    mwSize n;
    mwSize dimensions[3];
    double *scratch[5];
    const double *ttDay;
    const double *ttSec;
    const double *ut1Day;
    const double *ut1Sec;
    double *rdot = NULL;
    double *rddot = NULL;
    int derivativeOrder;
    int argument;
    int status;
    int k;

    rsRequireCounts(nrhs, 12, nlhs, 3, "dcm");
    for (argument = 1; argument <= 11; argument++) {
        rsRequireNumeric(prhs[argument], "argument");
    }

    n = rsEpochCount(prhs[1], "dcm");
    for (k = 0; k < 5; k++) {
        scratch[k] = NULL;
    }
    ttDay = mxGetPr(prhs[1]);
    ttSec = rsExpand(prhs[2], n, "ttSecOfDay", &scratch[0]);
    ut1Day = rsExpand(prhs[3], n, "ut1Day", &scratch[1]);
    ut1Sec = rsExpand(prhs[4], n, "ut1SecOfDay", &scratch[2]);

    for (argument = 5; argument <= 9; argument++) {
        if (mxGetNumberOfElements(prhs[argument]) != 3 * n) {
            mexErrMsgIdAndTxt("referenceSystem:mex:sizeMismatch",
                "Argument %d of 'dcm' must be %lu-by-3; it has %lu elements.",
                argument, (unsigned long)n,
                (unsigned long)mxGetNumberOfElements(prhs[argument]));
        }
    }

    derivativeOrder = (nlhs >= 3) ? 2 : ((nlhs == 2) ? 1 : 0);

    dimensions[0] = 3;
    dimensions[1] = 3;
    dimensions[2] = n;
    plhs[0] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
    if (derivativeOrder >= 1) {
        plhs[1] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
        rdot = mxGetPr(plhs[1]);
    }
    if (derivativeOrder >= 2) {
        plhs[2] = mxCreateNumericArray(3, dimensions, mxDOUBLE_CLASS, mxREAL);
        rddot = mxGetPr(plhs[2]);
    }

    status = rsRotationItrsToGcrs((int)n, ttDay, ttSec, ut1Day, ut1Sec,
        mxGetPr(prhs[5]), mxGetPr(prhs[6]), mxGetPr(prhs[7]), mxGetPr(prhs[8]),
        mxGetPr(prhs[9]), (int)mxGetScalar(prhs[10]), derivativeOrder,
        mxGetScalar(prhs[11]), mxGetPr(plhs[0]), rdot, rddot);

    for (k = 0; k < 5; k++) {
        if (scratch[k] != NULL) {
            mxFree(scratch[k]);
        }
    }

    if (status == -1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:unknownCipModel",
            "cipModel must be 2006 or 2000; it is %d.",
            (int)mxGetScalar(prhs[10]));
    }
    if (status == -3) {
        mexErrMsgIdAndTxt("referenceSystem:mex:badStep",
            "The central-difference step must be positive; it is %g.",
            mxGetScalar(prhs[11]));
    }
    if (status != 0) {
        mexErrMsgIdAndTxt("referenceSystem:mex:internal",
            "Command 'dcm' returned status %d.", status);
    }
}

static void rsCommandInfo(int nlhs, mxArray *plhs[], int nrhs,
                          const mxArray *prhs[])
{
    const char *fieldName[] = {"sofaRelease", "buildDate", "openMp",
                               "threadCount", "clampedToSingleThread",
                               "parallelThreshold", "faColumnCount"};
    const int fieldCount = 7;
    mxArray *info;

    rsRequireCounts(nrhs, 1, nlhs, 1, "info");

    info = mxCreateStructMatrix(1, 1, fieldCount, fieldName);
    mxSetField(info, 0, "sofaRelease", mxCreateString(rsSofaRelease()));
    mxSetField(info, 0, "buildDate", mxCreateString(__DATE__ " " __TIME__));
    mxSetField(info, 0, "openMp",
               mxCreateLogicalScalar(rsOpenMpEnabled() ? 1 : 0));
    mxSetField(info, 0, "threadCount",
               mxCreateDoubleScalar((double)rsGetMaxThreads()));
    mxSetField(info, 0, "clampedToSingleThread",
               mxCreateLogicalScalar(rsClampApplied ? 1 : 0));
    mxSetField(info, 0, "parallelThreshold",
               mxCreateDoubleScalar((double)rsParallelThreshold()));
    mxSetField(info, 0, "faColumnCount",
               mxCreateDoubleScalar((double)RS_FA_COLUMNS));
    plhs[0] = info;
}

/* ---------------------------------------------------------------------- */
/* Dispatch                                                                */
/* ---------------------------------------------------------------------- */

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    char command[RS_MAX_COMMAND_LENGTH];

    if (nrhs < 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:inputCount",
            "mexGateway needs a command name as its first input.");
    }
    if (!mxIsChar(prhs[0]) || mxGetM(prhs[0]) != 1) {
        mexErrMsgIdAndTxt("referenceSystem:mex:commandType",
            "The command must be a char row vector.");
    }
    if (mxGetString(prhs[0], command, RS_MAX_COMMAND_LENGTH) != 0) {
        mexErrMsgIdAndTxt("referenceSystem:mex:unknownCommand",
            "Command name is too long to be a valid command.");
    }

    rsApplyThreadClamp();

    if (strcmp(command, "dat") == 0) {
        rsCommandDat(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "dtdb") == 0) {
        rsCommandDtdb(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "xys06a") == 0) {
        rsCommandXys(nlhs, plhs, nrhs, prhs, 2006, "xys06a");
    } else if (strcmp(command, "xys00a") == 0) {
        rsCommandXys(nlhs, plhs, nrhs, prhs, 2000, "xys00a");
    } else if (strcmp(command, "era00") == 0) {
        rsCommandEra00(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "sp00") == 0) {
        rsCommandSp00(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "pom00") == 0) {
        rsCommandPom00(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "fa") == 0) {
        rsCommandFa(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "subdaily") == 0) {
        rsCommandTidal(nlhs, plhs, nrhs, prhs, 0, "subdaily");
    } else if (strcmp(command, "zonaltide") == 0) {
        rsCommandTidal(nlhs, plhs, nrhs, prhs, 1, "zonaltide");
    } else if (strcmp(command, "dcmcip") == 0) {
        rsCommandDcmCip(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "chebnodes") == 0) {
        rsCommandChebNodes(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "chebfit") == 0) {
        rsCommandChebFit(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "chebeval") == 0) {
        rsCommandChebEval(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "bodystate") == 0) {
        rsCommandBodyState(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "info") == 0) {
        rsCommandInfo(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "cip") == 0) {
        rsCommandCip(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "c2ixys") == 0) {
        rsCommandC2ixys(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "gst") == 0) {
        rsCommandGst(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "pnm06a") == 0) {
        rsCommandPnm06a(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "dcm") == 0) {
        rsCommandDcm(nlhs, plhs, nrhs, prhs);
    } else {
        mexErrMsgIdAndTxt("referenceSystem:mex:unknownCommand",
            "Unknown command '%s'.", command);
    }
}
