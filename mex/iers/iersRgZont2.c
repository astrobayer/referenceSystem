/*
 * iersRgZont2.c -- C port of IERS Conventions (2010) RG_ZONT2.F.
 * Ported line-for-line from mex/iers/iers_src/RG_ZONT2.F.
 *
 * Zonal Earth tide effect on the rotation of the Earth: a combination of the
 * Yoder et al. (1981) elastic body tide, the Wahr and Bergen (1986) inelastic
 * body tide and the Kantha et al. (1998) ocean tide models, as recommended by
 * IERS Conventions (2010) Chapter 8, pp. 105-106.  62 terms.
 *
 * DERIVED WORK: see the notice in iersModels.h.  The differences from the
 * original are the language, the name and nothing else.  The 62x5 argument
 * multipliers and the 62x6 coefficients below were extracted mechanically
 * from the DATA statements of RG_ZONT2.F rather than retyped, and then
 * cross-checked term by term against an independent published transcription
 * (xanthospap/iers2010, src/lib/eop/zonal_tides_iers.cpp).  All 62 rows agree
 * except the sine coefficient of the last term, where that transcription
 * carries -1617.268 against the Fortran's -1617.2681; the Fortran is the
 * authority and is what is used here.  The lost digit would be a 1e-8 s error
 * in dUT1, which is 10 ns -- small, but it is exactly the kind of drift that
 * makes a second-hand table the wrong source.
 *
 * Note the sine/cosine asymmetry, which is in the original and is easy to
 * mirror wrongly: dUT1 takes (sin, cos) while dLOD and dOmega take (cos, sin).
 *
 * Test case (from the original header): T = 0.07995893223819302 centuries of
 * TT since J2000.0, that is MJD 54465.
 *   expected: dut    =  7.983287678576557467e-2  seconds
 *             dlod   =  5.035331113978199288e-5  seconds per day
 *             domega = -4.249711616463017e-14    radians per second
 * Validated in test/c/testIersModels.c.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-25 09:45 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "iersModels.h"
#include <math.h>

#define IERS_NZONT 62
#define IERS_RGZ_TWOPI 6.283185307179586476925287

/* One tabulated term: the five lunisolar argument multipliers (l, l', F, D,
 * Omega) and the six coefficients in the order of the original TIDE array,
 * that is dUT1 sin, dUT1 cos, dLOD cos, dLOD sin, dOmega cos, dOmega sin.
 * Units are 1e-4 s, 1e-5 s/day and 1e-14 rad/s; the rescaling is at the end
 * of the routine, exactly as in the original. */
struct iersRgZont2Term {
    int multiplier[5];
    double coefficient[6];
};

static const struct iersRgZont2Term IERS_RGZ_TERM[IERS_NZONT] = {
    { {  1,  0,  2,  2,  2 }, {      -0.0235,   0.0000,     0.2617,   0.0000,    -0.2209,   0.0000 } },
    { {  2,  0,  2,  0,  1 }, {      -0.0404,   0.0000,     0.3706,   0.0000,    -0.3128,   0.0000 } },
    { {  2,  0,  2,  0,  2 }, {      -0.0987,   0.0000,     0.9041,   0.0000,    -0.7630,   0.0000 } },
    { {  0,  0,  2,  2,  1 }, {      -0.0508,   0.0000,     0.4499,   0.0000,    -0.3797,   0.0000 } },
    { {  0,  0,  2,  2,  2 }, {      -0.1231,   0.0000,     1.0904,   0.0000,    -0.9203,   0.0000 } },
    { {  1,  0,  2,  0,  0 }, {      -0.0385,   0.0000,     0.2659,   0.0000,    -0.2244,   0.0000 } },
    { {  1,  0,  2,  0,  1 }, {      -0.4108,   0.0000,     2.8298,   0.0000,    -2.3884,   0.0000 } },
    { {  1,  0,  2,  0,  2 }, {      -0.9926,   0.0000,     6.8291,   0.0000,    -5.7637,   0.0000 } },
    { {  3,  0,  0,  0,  0 }, {      -0.0179,   0.0000,     0.1222,   0.0000,    -0.1031,   0.0000 } },
    { { -1,  0,  2,  2,  1 }, {      -0.0818,   0.0000,     0.5384,   0.0000,    -0.4544,   0.0000 } },
    { { -1,  0,  2,  2,  2 }, {      -0.1974,   0.0000,     1.2978,   0.0000,    -1.0953,   0.0000 } },
    { {  1,  0,  0,  2,  0 }, {      -0.0761,   0.0000,     0.4976,   0.0000,    -0.4200,   0.0000 } },
    { {  2,  0,  2, -2,  2 }, {       0.0216,   0.0000,    -0.1060,   0.0000,     0.0895,   0.0000 } },
    { {  0,  1,  2,  0,  2 }, {       0.0254,   0.0000,    -0.1211,   0.0000,     0.1022,   0.0000 } },
    { {  0,  0,  2,  0,  0 }, {      -0.2989,   0.0000,     1.3804,   0.0000,    -1.1650,   0.0000 } },
    { {  0,  0,  2,  0,  1 }, {      -3.1873,   0.2010,    14.6890,   0.9266,   -12.3974,  -0.7820 } },
    { {  0,  0,  2,  0,  2 }, {      -7.8468,   0.5320,    36.0910,   2.4469,   -30.4606,  -2.0652 } },
    { {  2,  0,  0,  0, -1 }, {       0.0216,   0.0000,    -0.0988,   0.0000,     0.0834,   0.0000 } },
    { {  2,  0,  0,  0,  0 }, {      -0.3384,   0.0000,     1.5433,   0.0000,    -1.3025,   0.0000 } },
    { {  2,  0,  0,  0,  1 }, {       0.0179,   0.0000,    -0.0813,   0.0000,     0.0686,   0.0000 } },
    { {  0, -1,  2,  0,  2 }, {      -0.0244,   0.0000,     0.1082,   0.0000,    -0.0913,   0.0000 } },
    { {  0,  0,  0,  2, -1 }, {       0.0470,   0.0000,    -0.2004,   0.0000,     0.1692,   0.0000 } },
    { {  0,  0,  0,  2,  0 }, {      -0.7341,   0.0000,     3.1240,   0.0000,    -2.6367,   0.0000 } },
    { {  0,  0,  0,  2,  1 }, {      -0.0526,   0.0000,     0.2235,   0.0000,    -0.1886,   0.0000 } },
    { {  0, -1,  0,  2,  0 }, {      -0.0508,   0.0000,     0.2073,   0.0000,    -0.1749,   0.0000 } },
    { {  1,  0,  2, -2,  1 }, {       0.0498,   0.0000,    -0.1312,   0.0000,     0.1107,   0.0000 } },
    { {  1,  0,  2, -2,  2 }, {       0.1006,   0.0000,    -0.2640,   0.0000,     0.2228,   0.0000 } },
    { {  1,  1,  0,  0,  0 }, {       0.0395,   0.0000,    -0.0968,   0.0000,     0.0817,   0.0000 } },
    { { -1,  0,  2,  0,  0 }, {       0.0470,   0.0000,    -0.1099,   0.0000,     0.0927,   0.0000 } },
    { { -1,  0,  2,  0,  1 }, {       0.1767,   0.0000,    -0.4115,   0.0000,     0.3473,   0.0000 } },
    { { -1,  0,  2,  0,  2 }, {       0.4352,   0.0000,    -1.0093,   0.0000,     0.8519,   0.0000 } },
    { {  1,  0,  0,  0, -1 }, {       0.5339,   0.0000,    -1.2224,   0.0000,     1.0317,   0.0000 } },
    { {  1,  0,  0,  0,  0 }, {      -8.4046,   0.2500,    19.1647,   0.5701,   -16.1749,  -0.4811 } },
    { {  1,  0,  0,  0,  1 }, {       0.5443,   0.0000,    -1.2360,   0.0000,     1.0432,   0.0000 } },
    { {  0,  0,  0,  1,  0 }, {       0.0470,   0.0000,    -0.1000,   0.0000,     0.0844,   0.0000 } },
    { {  1, -1,  0,  0,  0 }, {      -0.0555,   0.0000,     0.1169,   0.0000,    -0.0987,   0.0000 } },
    { { -1,  0,  0,  2, -1 }, {       0.1175,   0.0000,    -0.2332,   0.0000,     0.1968,   0.0000 } },
    { { -1,  0,  0,  2,  0 }, {      -1.8236,   0.0000,     3.6018,   0.0000,    -3.0399,   0.0000 } },
    { { -1,  0,  0,  2,  1 }, {       0.1316,   0.0000,    -0.2587,   0.0000,     0.2183,   0.0000 } },
    { {  1,  0, -2,  2, -1 }, {       0.0179,   0.0000,    -0.0344,   0.0000,     0.0290,   0.0000 } },
    { { -1, -1,  0,  2,  0 }, {      -0.0855,   0.0000,     0.1542,   0.0000,    -0.1302,   0.0000 } },
    { {  0,  2,  2, -2,  2 }, {      -0.0573,   0.0000,     0.0395,   0.0000,    -0.0333,   0.0000 } },
    { {  0,  1,  2, -2,  1 }, {       0.0329,   0.0000,    -0.0173,   0.0000,     0.0146,   0.0000 } },
    { {  0,  1,  2, -2,  2 }, {      -1.8847,   0.0000,     0.9726,   0.0000,    -0.8209,   0.0000 } },
    { {  0,  0,  2, -2,  0 }, {       0.2510,   0.0000,    -0.0910,   0.0000,     0.0768,   0.0000 } },
    { {  0,  0,  2, -2,  1 }, {       1.1703,   0.0000,    -0.4135,   0.0000,     0.3490,   0.0000 } },
    { {  0,  0,  2, -2,  2 }, {     -49.7174,   0.4330,    17.1056,   0.1490,   -14.4370,  -0.1257 } },
    { {  0,  2,  0,  0,  0 }, {      -0.1936,   0.0000,     0.0666,   0.0000,    -0.0562,   0.0000 } },
    { {  2,  0,  0, -2, -1 }, {       0.0489,   0.0000,    -0.0154,   0.0000,     0.0130,   0.0000 } },
    { {  2,  0,  0, -2,  0 }, {      -0.5471,   0.0000,     0.1670,   0.0000,    -0.1409,   0.0000 } },
    { {  2,  0,  0, -2,  1 }, {       0.0367,   0.0000,    -0.0108,   0.0000,     0.0092,   0.0000 } },
    { {  0, -1,  2, -2,  1 }, {      -0.0451,   0.0000,     0.0082,   0.0000,    -0.0069,   0.0000 } },
    { {  0,  1,  0,  0, -1 }, {       0.0921,   0.0000,    -0.0167,   0.0000,     0.0141,   0.0000 } },
    { {  0, -1,  2, -2,  2 }, {       0.8281,   0.0000,    -0.1425,   0.0000,     0.1202,   0.0000 } },
    { {  0,  1,  0,  0,  0 }, {     -15.8887,   0.1530,     2.7332,   0.0263,    -2.3068,  -0.0222 } },
    { {  0,  1,  0,  0,  1 }, {      -0.1382,   0.0000,     0.0225,   0.0000,    -0.0190,   0.0000 } },
    { {  1,  0,  0, -1,  0 }, {       0.0348,   0.0000,    -0.0053,   0.0000,     0.0045,   0.0000 } },
    { {  2,  0, -2,  0,  0 }, {      -0.1372,   0.0000,    -0.0079,   0.0000,     0.0066,   0.0000 } },
    { { -2,  0,  2,  0,  1 }, {       0.4211,   0.0000,    -0.0203,   0.0000,     0.0171,   0.0000 } },
    { { -1,  1,  0,  1,  0 }, {      -0.0404,   0.0000,     0.0008,   0.0000,    -0.0007,   0.0000 } },
    { {  0,  0,  0,  0,  2 }, {       7.8998,   0.0000,     0.1460,   0.0000,    -0.1232,   0.0000 } },
    { {  0,  0,  0,  0,  1 }, {   -1617.2681,   0.0000,   -14.9471,   0.0000,    12.6153,   0.0000 } }
};

void iersRgZont2(double t, double *dut, double *dlod, double *domega)
{
    double l;
    double lp;
    double f;
    double d;
    double om;
    double argument[5];
    int j;
    int i;

    iersFundarg(t, &l, &lp, &f, &d, &om);
    argument[0] = l;
    argument[1] = lp;
    argument[2] = f;
    argument[3] = d;
    argument[4] = om;

    *dut = 0.0;
    *dlod = 0.0;
    *domega = 0.0;

    for (j = 0; j < IERS_NZONT; j++) {
        const struct iersRgZont2Term *term = &IERS_RGZ_TERM[j];
        double arg = 0.0;
        double sinArg;
        double cosArg;

        for (i = 0; i < 5; i++) {
            arg += (double)term->multiplier[i] * argument[i];
        }
        /* Fortran MOD truncates toward zero, so the original follows it with
         * an explicit add of 2pi for a negative result. Reproduced verbatim. */
        arg = fmod(arg, IERS_RGZ_TWOPI);
        if (arg < 0.0) {
            arg += IERS_RGZ_TWOPI;
        }
        sinArg = sin(arg);
        cosArg = cos(arg);

        *dut += term->coefficient[0] * sinArg + term->coefficient[1] * cosArg;
        *dlod += term->coefficient[2] * cosArg + term->coefficient[3] * sinArg;
        *domega += term->coefficient[4] * cosArg + term->coefficient[5] * sinArg;
    }

    *dut *= 1.0e-4;
    *dlod *= 1.0e-5;
    *domega *= 1.0e-14;
}
