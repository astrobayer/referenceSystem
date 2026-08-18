/*
 * mexStub.h
 * ---------
 * A small stand-in for MATLAB's mex.h, used only so that the control flow of
 * mex/mexGateway.c -- command dispatch, argument validation, broadcasting,
 * output shaping and error paths -- can be exercised with plain gcc where no
 * MATLAB toolchain is present. Ported from the v1 test stub and extended to
 * the API subset the new gateway uses.
 *
 * This is a logic test of the gateway, NOT a substitute for building against
 * the real MATLAB headers. The real build is referenceSystem.buildMex, which
 * finds the genuine mex.h, libmex and libmx.
 *
 * Errors are catchable: mexErrMsgIdAndTxt records the identifier and jumps to
 * the buffer installed by RS_TRY, so a test can assert that a documented
 * identifier is raised instead of aborting the process the way the v1 stub did.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:55 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#ifndef RS_MEX_STUB_H
#define RS_MEX_STUB_H

#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef size_t mwSize;
typedef size_t mwIndex;

typedef enum { mxREAL = 0 } mxComplexity;
typedef enum { mxDOUBLE_CLASS = 6 } mxClassID;

typedef enum {
    RS_STUB_DOUBLE = 0,
    RS_STUB_CHAR,
    RS_STUB_LOGICAL,
    RS_STUB_STRUCT
} rsStubKind;

#define RS_STUB_MAX_FIELDS 16
#define RS_STUB_MAX_NAME 64

typedef struct mxArray {
    rsStubKind kind;
    mwSize rows;
    mwSize cols;
    mwSize pages;
    double *pr;
    char *text;
    int fieldCount;
    char fieldName[RS_STUB_MAX_FIELDS][RS_STUB_MAX_NAME];
    struct mxArray *field[RS_STUB_MAX_FIELDS];
} mxArray;

/* ------------------------------------------------------------------ */
/* Error plumbing                                                      */
/* ------------------------------------------------------------------ */

static jmp_buf rsStubJump;
static int rsStubJumpArmed = 0;
static char rsStubErrorId[160];

#define RS_TRY(body)                                   \
    do {                                               \
        rsStubErrorId[0] = '\0';                       \
        rsStubJumpArmed = 1;                           \
        if (setjmp(rsStubJump) == 0) {                 \
            body;                                      \
        }                                              \
        rsStubJumpArmed = 0;                           \
    } while (0)

static void mexErrMsgIdAndTxt(const char *identifier, const char *format, ...)
{
    va_list arguments;
    snprintf(rsStubErrorId, sizeof(rsStubErrorId), "%s", identifier);
    if (getenv("RS_STUB_VERBOSE") != NULL) {
        va_start(arguments, format);
        fprintf(stderr, "  [%s] ", identifier);
        vfprintf(stderr, format, arguments);
        fprintf(stderr, "\n");
        va_end(arguments);
    }
    if (rsStubJumpArmed) {
        longjmp(rsStubJump, 1);
    }
    exit(2);
}

static void mexWarnMsgIdAndTxt(const char *identifier, const char *format, ...)
{
    (void)identifier;
    (void)format;
}

/* ------------------------------------------------------------------ */
/* Array creation and access                                           */
/* ------------------------------------------------------------------ */

static mxArray *rsStubNew(rsStubKind kind, mwSize rows, mwSize cols, mwSize pages)
{
    mxArray *array = (mxArray *)calloc(1, sizeof(mxArray));
    array->kind = kind;
    array->rows = rows;
    array->cols = cols;
    array->pages = pages;
    if (kind == RS_STUB_DOUBLE || kind == RS_STUB_LOGICAL) {
        array->pr = (double *)calloc(rows * cols * pages, sizeof(double));
    }
    return array;
}

static mxArray *mxCreateDoubleMatrix(mwSize rows, mwSize cols, mxComplexity c)
{
    (void)c;
    return rsStubNew(RS_STUB_DOUBLE, rows, cols, 1);
}

static mxArray *mxCreateNumericArray(mwSize ndim, const mwSize *dims,
                                     mxClassID classId, mxComplexity c)
{
    (void)classId;
    (void)c;
    return rsStubNew(RS_STUB_DOUBLE, dims[0], dims[1], (ndim > 2) ? dims[2] : 1);
}

static mxArray *mxCreateDoubleScalar(double value)
{
    mxArray *array = rsStubNew(RS_STUB_DOUBLE, 1, 1, 1);
    array->pr[0] = value;
    return array;
}

static mxArray *mxCreateLogicalScalar(int value)
{
    mxArray *array = rsStubNew(RS_STUB_LOGICAL, 1, 1, 1);
    array->pr[0] = value ? 1.0 : 0.0;
    return array;
}

static mxArray *mxCreateString(const char *text)
{
    mxArray *array = rsStubNew(RS_STUB_CHAR, 1, strlen(text), 1);
    array->text = (char *)malloc(strlen(text) + 1);
    strcpy(array->text, text);
    return array;
}

static mxArray *mxCreateStructMatrix(mwSize rows, mwSize cols, int fieldCount,
                                     const char **fieldName)
{
    mxArray *array = rsStubNew(RS_STUB_STRUCT, rows, cols, 1);
    int k;
    array->fieldCount = fieldCount;
    for (k = 0; k < fieldCount && k < RS_STUB_MAX_FIELDS; k++) {
        snprintf(array->fieldName[k], RS_STUB_MAX_NAME, "%s", fieldName[k]);
    }
    return array;
}

static void mxSetField(mxArray *array, mwIndex index, const char *name,
                       mxArray *value)
{
    int k;
    (void)index;
    for (k = 0; k < array->fieldCount; k++) {
        if (strcmp(array->fieldName[k], name) == 0) {
            array->field[k] = value;
            return;
        }
    }
}

static mxArray *mxGetField(const mxArray *array, mwIndex index, const char *name)
{
    int k;
    (void)index;
    for (k = 0; k < array->fieldCount; k++) {
        if (strcmp(array->fieldName[k], name) == 0) {
            return array->field[k];
        }
    }
    return NULL;
}

static double *mxGetPr(const mxArray *array) { return array->pr; }
static mwSize mxGetM(const mxArray *array) { return array->rows; }
static mwSize mxGetN(const mxArray *array) { return array->cols; }

static mwSize mxGetNumberOfElements(const mxArray *array)
{
    return array->rows * array->cols * array->pages;
}

static int mxIsDouble(const mxArray *array) { return array->kind == RS_STUB_DOUBLE; }
static int mxIsChar(const mxArray *array) { return array->kind == RS_STUB_CHAR; }
static int mxIsComplex(const mxArray *array) { (void)array; return 0; }
static int mxIsEmpty(const mxArray *array)
{
    return mxGetNumberOfElements(array) == 0;
}
static double mxGetScalar(const mxArray *array) { return array->pr[0]; }

static int mxGetString(const mxArray *array, char *buffer, mwSize length)
{
    if (array->text == NULL) {
        return 1;
    }
    if (strlen(array->text) + 1 > length) {
        return 1;
    }
    strcpy(buffer, array->text);
    return 0;
}

static void mxDestroyArray(mxArray *array)
{
    if (array == NULL) {
        return;
    }
    free(array->pr);
    free(array->text);
    free(array);
}

static void *mxMalloc(size_t bytes) { return malloc(bytes); }
static void mxFree(void *pointer) { free(pointer); }

/* Outside MATLAB there are no parallel workers, so the trap call that the
 * gateway makes to getCurrentTask always reports "not available". Returning a
 * non-NULL exception is exactly what MATLAB does when the Parallel Computing
 * Toolbox is absent, so this exercises the same branch. */
static mxArray *mexCallMATLABWithTrap(int nlhs, mxArray *plhs[], int nrhs,
                                      mxArray *prhs[], const char *name)
{
    (void)nlhs;
    (void)plhs;
    (void)nrhs;
    (void)prhs;
    (void)name;
    return mxCreateString("MATLAB:UndefinedFunction");
}

/* Helpers for the test driver; not part of the real mex API. */
static mxArray *rsStubVector(const double *values, mwSize n)
{
    mxArray *array = mxCreateDoubleMatrix(n, 1, mxREAL);
    memcpy(array->pr, values, n * sizeof(double));
    return array;
}

static mxArray *rsStubScalar(double value) { return mxCreateDoubleScalar(value); }

#endif /* RS_MEX_STUB_H */
