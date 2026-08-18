/*
 * iersFundarg.c -- C port of IERS Conventions (2010) FUNDARG.F.
 * Lunisolar fundamental arguments, Simon et al. (1994).
 * Ported line-for-line from the original Fortran (see
 * mex/iers/iers_src/FUNDARG.F) to minimize transcription risk.
 *
 * Test case (from the original FUNDARG.F header):
 *   T = 0.07995893223819302 (MJD = 54465)
 *   expected: L  = 2.291187512612069099 rad
 *             LP = 6.212931111003726414 rad
 *             F  = 3.658025792050572989 rad
 *             D  = 4.554139562402433228 rad
 *             OM = -0.5167379217231804489 rad
 * Validated in test/test_tidal.c.
 */
#include "iersModels.h"
#include <math.h>

#define FA_DAS2R 4.848136811095359935899141e-6
#define FA_TURNAS 1296000.0

/* Fortran MOD(a,p) for doubles == C fmod(a,p) (both truncate toward zero) */
static double fmod_f(double a, double p) { return fmod(a, p); }

void iersFundarg(double t, double *l, double *lp, double *f, double *d, double *om)
{
    *l = fmod_f(485868.249036 +
                t * (1717915923.2178 +
                t * (31.8792 +
                t * (0.051635 +
                t * (-0.00024470)))), FA_TURNAS) * FA_DAS2R;

    *lp = fmod_f(1287104.79305 +
                 t * (129596581.0481 +
                 t * (-0.5532 +
                 t * (0.000136 +
                 t * (-0.00001149)))), FA_TURNAS) * FA_DAS2R;

    *f = fmod_f(335779.526232 +
                t * (1739527262.8478 +
                t * (-12.7512 +
                t * (-0.001037 +
                t * (0.00000417)))), FA_TURNAS) * FA_DAS2R;

    *d = fmod_f(1072260.70369 +
                t * (1602961601.2090 +
                t * (-6.3706 +
                t * (0.006593 +
                t * (-0.00003169)))), FA_TURNAS) * FA_DAS2R;

    *om = fmod_f(450160.398036 +
                 t * (-6962890.5431 +
                 t * (7.4722 +
                 t * (0.007702 +
                 t * (-0.00005939)))), FA_TURNAS) * FA_DAS2R;
}
