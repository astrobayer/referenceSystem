/*
 * iersUtlibr.c -- C port of IERS Conventions (2010) UTLIBR.F.
 * Ported line-for-line from mex/iers/iers_src/UTLIBR.F.
 *
 * DERIVED WORK: see the notice in iersModels.h.
 *
 * THE SINGLE-PRECISION TABLE, which is why this file was rewritten in session
 * S2 and is not obvious from reading either language. The DATA statement of
 * UTLIBR.F writes its coefficients as 0.05, -0.03, -0.3 and so on, WITHOUT a
 * D0 suffix. In Fortran an unsuffixed real literal is default REAL, that is
 * single precision, and is only then promoted into the DOUBLE PRECISION
 * arrays DUT1S, DUT1C, DLODS and DLODC. The stored value of "0.05" is
 * therefore 0.0500000007450580597, not 0.05000000000000000278.
 *
 * The v1 port transcribed the printed decimals as C double literals, which is
 * the arithmetically tidier reading and the wrong one: it misses the routine's
 * own published test case by about 2e-8 relative and disagrees with the
 * original Fortran by the same amount at every epoch. That was measured in S2
 * by compiling UTLIBR.F with gfortran and differencing the two implementations
 * over 2001 epochs spanning 1960 to 2100, not inferred by reading.
 *
 * The coefficient table below is therefore declared float, so that the C
 * compiler stores exactly what the Fortran compiler stores and the promotion
 * to double happens at the same point in the arithmetic. The type is the
 * documentation: anyone who "tidies" it to double will fail the published test
 * case immediately, which is the correct outcome.
 *
 * Physically the distinction is irrelevant -- these coefficients are tabulated
 * to two decimals and carry amplitudes of order one microsecond, so 2e-8 of
 * them is far below anything observable. It matters because the published test
 * case is the only external validation this routine has, and a validation that
 * cannot be reproduced is not a validation.
 *
 * Test cases (from the original header):
 *   rmjd = 44239.1  -> dUT1 =  2.441143834386761746 us
 *                      dLOD = -14.78971247349449492 us/day
 *   rmjd = 55227.4  -> dUT1 = -2.655705844335680244 us
 *                      dLOD =  27.39445826599846967 us/day
 * Validated in test/c/testIersModels.c.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-25 10:40 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "iersModels.h"
#include <math.h>

#define IERS_UTLIBR_TERMS 11
#define IERS_UTLIBR_PI 3.141592653589793238462643
#define IERS_UTLIBR_TWOPI 6.283185307179586476925287
#define IERS_UTLIBR_RMJD0 51544.5
#define IERS_UTLIBR_RAD2SEC (86400.0 / IERS_UTLIBR_TWOPI)

/* IARG(6,11) of the original: multipliers of GMST+pi, l, l', F, D and Omega.
 * INTEGER in Fortran, therefore exact in both languages. */
static const int IERS_UTLIBR_MULTIPLIER[IERS_UTLIBR_TERMS][6] = {
    {2, -2,  0, -2,  0, -2},
    {2,  0,  0, -2, -2, -2},
    {2, -1,  0, -2,  0, -2},
    {2,  1,  0, -2, -2, -2},
    {2,  0,  0, -2,  0, -1},
    {2,  0,  0, -2,  0, -2},
    {2,  1,  0, -2,  0, -2},
    {2,  0, -1, -2,  2, -2},
    {2,  0,  0, -2,  2, -2},
    {2,  0,  0,  0,  0,  0},
    {2,  0,  0,  0,  0, -1}
};

/* DUT1S, DUT1C, DLODS, DLODC of the original, in microseconds and
 * microseconds per day. float, deliberately -- see the header comment. The
 * PER column of the original is tabulated but never used and is omitted. */
static const float IERS_UTLIBR_COEFFICIENT[IERS_UTLIBR_TERMS][4] = {
    { 0.05f, -0.03f,  -0.3f,  -0.6f},
    { 0.06f, -0.03f,  -0.4f,  -0.7f},
    { 0.35f, -0.20f,  -2.4f,  -4.1f},
    { 0.07f, -0.04f,  -0.5f,  -0.8f},
    {-0.07f,  0.04f,   0.5f,   0.8f},
    { 1.75f, -1.01f, -12.2f, -21.3f},
    {-0.05f,  0.03f,   0.3f,   0.6f},
    { 0.04f, -0.03f,  -0.3f,  -0.6f},
    { 0.76f, -0.44f,  -5.5f,  -9.6f},
    { 0.21f, -0.12f,  -1.5f,  -2.6f},
    { 0.06f, -0.04f,  -0.4f,  -0.8f}
};

void iersUtlibr(double rmjd, double *dut1, double *dlod)
{
    double t = (rmjd - IERS_UTLIBR_RMJD0) / 36525.0;
    double gmst;
    double l;
    double lp;
    double f;
    double d;
    double om;
    double argument[6];
    int j;
    int i;

    /* The T-cubed coefficient is written -0.0000062 in the original, again
     * without a D0 suffix. Its contribution is of order 1e-14 s of GMST, so
     * here the single/double distinction really is below the noise, unlike the
     * coefficient table above; the literal is kept exactly as written. */
    gmst = fmod(67310.54841 +
                t * ((8640184.812866 + 3155760000.0) +
                t * (0.093104 +
                t * (-0.0000062))), 86400.0);

    iersFundarg(t, &l, &lp, &f, &d, &om);

    argument[0] = fmod(gmst / IERS_UTLIBR_RAD2SEC + IERS_UTLIBR_PI,
                       IERS_UTLIBR_TWOPI);
    argument[1] = l;
    argument[2] = lp;
    argument[3] = f;
    argument[4] = d;
    argument[5] = om;

    *dut1 = 0.0;
    *dlod = 0.0;
    for (j = 0; j < IERS_UTLIBR_TERMS; j++) {
        double angle = 0.0;
        double sinAngle;
        double cosAngle;

        for (i = 0; i < 6; i++) {
            angle += (double)IERS_UTLIBR_MULTIPLIER[j][i] * argument[i];
        }
        angle = fmod(angle, IERS_UTLIBR_TWOPI);
        sinAngle = sin(angle);
        cosAngle = cos(angle);

        *dut1 += (double)IERS_UTLIBR_COEFFICIENT[j][0] * sinAngle +
                 (double)IERS_UTLIBR_COEFFICIENT[j][1] * cosAngle;
        *dlod += (double)IERS_UTLIBR_COEFFICIENT[j][2] * sinAngle +
                 (double)IERS_UTLIBR_COEFFICIENT[j][3] * cosAngle;
    }
}
