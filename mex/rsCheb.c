/*
 * rsCheb.c
 * --------
 * Implementation of rsCheb.h. No mex.h, no SOFA, no printing (section C.4).
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-27 09:40 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "rsCheb.h"
#include <math.h>

/* pi to the last representable bit. Not M_PI: that macro is not in C89 or in
 * strict C99, and MinGW hides it behind _USE_MATH_DEFINES, so a build that
 * happened to omit the define would silently fall back to whatever else was in
 * scope. This toolbox is built by MinGW on Windows and gcc on Linux and must
 * produce the same coefficients on both (decision D31). */
static const double RS_PI = 3.14159265358979323846;

static int rsChebCheckDegree(int degree)
{
    if (degree < 1 || degree > RS_CHEB_MAX_DEGREE) {
        return RS_CHEB_BAD_DEGREE;
    }
    return RS_CHEB_OK;
}

static int rsChebCheckSpan(double span)
{
    /* The comparison is written so that a NaN span fails: NaN > 0 is false. */
    if (!(span > 0.0) || !(span < HUGE_VAL)) {
        return RS_CHEB_BAD_SPAN;
    }
    return RS_CHEB_OK;
}

/* Map t to the fit variable and reject anything outside the panel. */
static int rsChebMap(double t0, double span, double t, double *u)
{
    double scaled;
    int status = rsChebCheckSpan(span);
    if (status != RS_CHEB_OK) {
        return status;
    }
    scaled = 2.0 * (t - t0) / span - 1.0;
    if (!(fabs(scaled) <= 1.0 + RS_CHEB_EDGE_SLACK)) {
        return RS_CHEB_OUT_OF_PANEL;
    }
    *u = scaled;
    return RS_CHEB_OK;
}

/* Clenshaw for f(u) = sum_{k=0}^{n} c[k] T_k(u), c[0] not halved. */
static double rsChebClenshaw(const double *c, int degree, double u)
{
    double previous = 0.0;   /* b_{k+1} */
    double current = 0.0;    /* b_k     */
    double next;
    int k;

    for (k = degree; k >= 1; k--) {
        next = 2.0 * u * current - previous + c[k];
        previous = current;
        current = next;
    }
    return u * current - previous + c[0];
}

int rsChebNodes(double t0, double span, int degree, double *node)
{
    int status = rsChebCheckDegree(degree);
    int j;

    if (status != RS_CHEB_OK) {
        return status;
    }
    status = rsChebCheckSpan(span);
    if (status != RS_CHEB_OK) {
        return status;
    }

    for (j = 0; j <= degree; j++) {
        double u = cos(RS_PI * (double)j / (double)degree);
        node[j] = t0 + 0.5 * span * (u + 1.0);
    }
    return RS_CHEB_OK;
}

int rsChebFit(const double *value, int degree, double *coefficient)
{
    int status = rsChebCheckDegree(degree);
    int k, j;

    if (status != RS_CHEB_OK) {
        return status;
    }

    for (k = 0; k <= degree; k++) {
        double sum = 0.0;
        for (j = 0; j <= degree; j++) {
            /* The endpoint samples enter at half weight: the Lobatto grid
             * counts them once each while the interior points stand for two
             * halves of the periodic extension. */
            double weight = (j == 0 || j == degree) ? 0.5 : 1.0;
            sum += weight * value[j]
                 * cos(RS_PI * (double)j * (double)k / (double)degree);
        }
        sum *= 2.0 / (double)degree;
        if (k == 0 || k == degree) {
            sum *= 0.5;
        }
        coefficient[k] = sum;
    }
    return RS_CHEB_OK;
}

int rsChebEval(const double *coefficient, int degree,
               double t0, double span, double t, double *result)
{
    double u;
    int status = rsChebCheckDegree(degree);

    if (status != RS_CHEB_OK) {
        return status;
    }
    status = rsChebMap(t0, span, t, &u);
    if (status != RS_CHEB_OK) {
        return status;   /* result untouched, by contract */
    }
    *result = rsChebClenshaw(coefficient, degree, u);
    return RS_CHEB_OK;
}

int rsChebEvalDerivative(const double *coefficient, int degree,
                         double t0, double span, double t, double *result)
{
    double derivative[RS_CHEB_MAX_DEGREE + 2];
    double u;
    int status = rsChebCheckDegree(degree);
    int k;

    if (status != RS_CHEB_OK) {
        return status;
    }
    status = rsChebMap(t0, span, t, &u);
    if (status != RS_CHEB_OK) {
        return status;
    }

    if (degree == 1) {
        /* d/du of c0 + c1 u is c1; the recurrence below needs degree >= 2. */
        *result = coefficient[1] * 2.0 / span;
        return RS_CHEB_OK;
    }

    /* Standard descending recurrence for the coefficients of f'. The identity
     * behind it is d_{k-1} - d_{k+1} = 2 k c_k, applied downward from
     * d_{degree} = d_{degree+1} = 0. The k = 0 term carries the usual factor of
     * two, which is where a sign or a factor is most often lost - so
     * testCheb.c checks the whole derivative against a central difference of
     * the fit itself rather than trusting the algebra. */
    derivative[degree] = 0.0;
    derivative[degree - 1] = 2.0 * (double)degree * coefficient[degree];
    for (k = degree - 2; k >= 1; k--) {
        derivative[k] = derivative[k + 2]
                      + 2.0 * (double)(k + 1) * coefficient[k + 1];
    }
    derivative[0] = 0.5 * derivative[2] + coefficient[1];

    /* Chain rule: du/dt = 2 / span. */
    *result = rsChebClenshaw(derivative, degree - 1, u) * 2.0 / span;
    return RS_CHEB_OK;
}

int rsChebNodeResidual(const double *coefficient, const double *value,
                       int degree, double *residual)
{
    double worst = 0.0;
    int status = rsChebCheckDegree(degree);
    int j;

    if (status != RS_CHEB_OK) {
        return status;
    }

    for (j = 0; j <= degree; j++) {
        double u = cos(RS_PI * (double)j / (double)degree);
        double difference = fabs(rsChebClenshaw(coefficient, degree, u)
                                 - value[j]);
        if (difference > worst) {
            worst = difference;
        }
    }
    *residual = worst;
    return RS_CHEB_OK;
}
