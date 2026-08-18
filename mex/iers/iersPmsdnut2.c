/*
 * iersPmsdnut2.c -- C port of IERS Conventions (2010) PMSDNUT2.F.
 * Ported line-for-line from mex/iers/iers_src/PMSDNUT2.F.
 *
 * DERIVED WORK: see the notice in iersModels.h.
 *
 * SINGLE-PRECISION TABLE: identical situation to iersUtlibr.c, and it was
 * found the same way. The DATA statement of PMSDNUT2.F writes XS, XC, YS and
 * YC without a D0 suffix, so Fortran stores single-precision values and
 * promotes them into the DOUBLE PRECISION arrays. The v1 port used C double
 * literals and therefore missed the published test case, and the original
 * Fortran, by about 2e-8 relative. Measured over 2001 epochs against
 * gfortran-compiled PMSDNUT2.F. The table below is float so that the two
 * languages store the same bits; see iersUtlibr.c for the full argument.
 *
 * IBAND = 1, as the original hard-codes it: only the ten quasi-diurnal terms
 * (J = 16..25 in the Fortran table) are evaluated, and the routine returns
 * before the secular XRATE/YRATE drift is added. This is what IERS
 * Conventions (2010) section 5.5.1.1 recommends and what the original does;
 * the fifteen long-period terms are therefore not transcribed at all, since
 * transcribing unreachable data would invite someone to reach it.
 *
 * Test case (from the original header): rmjd = 54335.0 (2007-08-23)
 *   expected: dx =  24.83144238273364834 uas
 *             dy = -14.09240692041837661 uas
 * Validated in test/c/testIersModels.c.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-25 10:45 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "iersModels.h"
#include <math.h>

#define IERS_PMSDNUT2_TERMS 10
#define IERS_PMSDNUT2_PI 3.141592653589793238462643
#define IERS_PMSDNUT2_TWOPI 6.283185307179586476925287
#define IERS_PMSDNUT2_RMJD0 51544.5
#define IERS_PMSDNUT2_RAD2SEC (86400.0 / IERS_PMSDNUT2_TWOPI)

/* IARG(6,16..25) of the original: multipliers of GMST+pi, l, l', F, D and
 * Omega. INTEGER in Fortran, therefore exact in both languages. */
static const int IERS_PMSDNUT2_MULTIPLIER[IERS_PMSDNUT2_TERMS][6] = {
    {1, -1, 0, -2,  0, -1},
    {1, -1, 0, -2,  0, -2},
    {1,  1, 0, -2, -2, -2},
    {1,  0, 0, -2,  0, -1},
    {1,  0, 0, -2,  0, -2},
    {1, -1, 0,  0,  0,  0},
    {1,  0, 0, -2,  2, -2},
    {1,  0, 0,  0,  0,  0},
    {1,  0, 0,  0,  0, -1},
    {1,  1, 0,  0,  0,  0}
};

/* XS, XC, YS, YC of the original, in microarcseconds. float, deliberately --
 * see the header comment. The PER column is tabulated but never used. */
static const float IERS_PMSDNUT2_COEFFICIENT[IERS_PMSDNUT2_TERMS][4] = {
    { -0.4f,  0.3f, -0.3f,  -0.4f},
    { -2.3f,  1.3f, -1.3f,  -2.3f},
    { -0.4f,  0.3f, -0.3f,  -0.4f},
    { -2.1f,  1.2f, -1.2f,  -2.1f},
    {-11.4f,  6.5f, -6.5f, -11.4f},
    {  0.8f, -0.5f,  0.5f,   0.8f},
    { -4.8f,  2.7f, -2.7f,  -4.8f},
    { 14.3f, -8.2f,  8.2f,  14.3f},
    {  1.9f, -1.1f,  1.1f,   1.9f},
    {  0.8f, -0.4f,  0.4f,   0.8f}
};

void iersPmsdnut2(double rmjd, double pm[2])
{
    double t = (rmjd - IERS_PMSDNUT2_RMJD0) / 36525.0;
    double gmst;
    double l;
    double lp;
    double f;
    double d;
    double om;
    double argument[6];
    int j;
    int i;

    gmst = fmod(67310.54841 +
                t * ((8640184.812866 + 3155760000.0) +
                t * (0.093104 +
                t * (-0.0000062))), 86400.0);

    iersFundarg(t, &l, &lp, &f, &d, &om);

    argument[0] = fmod(gmst / IERS_PMSDNUT2_RAD2SEC + IERS_PMSDNUT2_PI,
                       IERS_PMSDNUT2_TWOPI);
    argument[1] = l;
    argument[2] = lp;
    argument[3] = f;
    argument[4] = d;
    argument[5] = om;

    pm[0] = 0.0;
    pm[1] = 0.0;
    for (j = 0; j < IERS_PMSDNUT2_TERMS; j++) {
        double angle = 0.0;
        double sinAngle;
        double cosAngle;

        for (i = 0; i < 6; i++) {
            angle += (double)IERS_PMSDNUT2_MULTIPLIER[j][i] * argument[i];
        }
        angle = fmod(angle, IERS_PMSDNUT2_TWOPI);
        sinAngle = sin(angle);
        cosAngle = cos(angle);

        pm[0] += (double)IERS_PMSDNUT2_COEFFICIENT[j][0] * sinAngle +
                 (double)IERS_PMSDNUT2_COEFFICIENT[j][1] * cosAngle;
        pm[1] += (double)IERS_PMSDNUT2_COEFFICIENT[j][2] * sinAngle +
                 (double)IERS_PMSDNUT2_COEFFICIENT[j][3] * cosAngle;
    }
}
