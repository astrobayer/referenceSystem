/*
 * iersOrthoEop.c -- C port of IERS Conventions (2010) ORTHO_EOP.F.
 * Ported from mex/iers/iers_src/ORTHO_EOP.F.
 *
 * IMPORTANT TRANSCRIPTION NOTE: the original Fortran DATA statement
 * fills ORTHOW(12,3) in column-major order (Fortran's native storage
 * order), i.e. the flat list of 36 numbers maps to
 * ORTHOW(1,1)..ORTHOW(12,1), then ORTHOW(1,2)..ORTHOW(12,2), then
 * ORTHOW(1,3)..ORTHOW(12,3) -- NOT row-by-row as printed. The mapping
 * below was derived by hand-unrolling that column-major fill and is
 * exercised against the routine's own embedded test case in
 * test/test_tidal.c (MJD=47100 -> dx=-162.8386373279636530 uas,
 * dy=117.7907525842668974 uas, dUT1=-23.39092370609808214 us).
 *
 * Test case (from the original header): MJD = 47100.0
 *   expected: dx    = -162.8386373279636530  microarcseconds
 *             dy    =  117.7907525842668974  microarcseconds
 *             dUT1  =  -23.39092370609808214 microseconds
 */
#include "iersModels.h"

/* orthow[k][j] = ORTHOW(j+1, k+1) in the original 1-based Fortran
 * notation (k: 0=dx, 1=dy, 2=dUT1; j: 0..11) */
static const double orthow[3][12] = {
    /* K=1 (dx) */
    { -6.77832, -14.86323,  0.47884, -1.45303,  0.16406,  0.42030,
       0.09398,  25.73054, -4.77974,  0.28080,  1.94539, -0.73089 },
    /* K=2 (dy) */
    { 14.86283,  -6.77846,  1.45234,  0.47888, -0.42056,  0.16469,
      15.30276,  -4.30615,  0.07564,  2.28321, -0.45717, -1.62010 },
    /* K=3 (dUT1) */
    { -1.76335,   1.03364, -0.27553,  0.34569, -0.12343, -0.10146,
      -0.47119,   1.28997, -0.19336,  0.02724,  0.08955,  0.04726 }
};

void iersOrthoEop(double time_mjd, double eop[3])
{
    double h[12];
    iersCnmtx(time_mjd, h);

    for (int k = 0; k < 3; k++) {
        double s = 0.0;
        for (int j = 0; j < 12; j++) s += h[j] * orthow[k][j];
        eop[k] = s;
    }
}
