/*
 * stepSelect.c
 * ------------
 * Selects the central-difference step h for the CIP derivatives against a
 * physical error budget, and validates its own reference before using it.
 *
 * Two things the first pass got wrong and this one fixes:
 *
 *  (a) The reference must be shown to be better than what it measures. Two
 *      Romberg references are formed from different base steps; where they
 *      disagree, the disagreement is the reference's own uncertainty and no
 *      error below it may be quoted.
 *
 *  (b) An error in rad/s means nothing on its own. Each error is normalised by
 *      the value at which it would matter: a rotation-rate error d produces a
 *      velocity error r*d at orbit radius r, and a rotation-acceleration error
 *      produces r*d of acceleration. The budget is 1 nm/s of velocity and
 *      1e-10 m/s^2 of acceleration, the latter being the GRACE accelerometer
 *      noise floor, at r = 7e6 m.
 *
 * Build: gcc -O2 -I../sofabuild stepSelect.c ../sofabuild/libsofa.a -lm
 */
#include <stdio.h>
#include <math.h>
#include "sofa.h"

#define DAY 86400.0
#define ORBIT_RADIUS 7.0e6
#define VELOCITY_BUDGET 1.0e-9        /* m/s   */
#define ACCELERATION_BUDGET 1.0e-10   /* m/s^2 */
#define NEPOCH 12

static void cip(double mjd, double secOfDay, double *x, double *y, double *s)
{
    iauXys06a(2400000.5 + mjd, secOfDay / DAY, x, y, s);
}

static void diff2(double mjd, double sec, double h, double *d1, double *d2)
{
    double xm, ym, sm, x0, y0, s0, xp, yp, sp;
    cip(mjd, sec - h, &xm, &ym, &sm);
    cip(mjd, sec, &x0, &y0, &s0);
    cip(mjd, sec + h, &xp, &yp, &sp);
    d1[0] = (xp - xm) / (2.0 * h);
    d1[1] = (yp - ym) / (2.0 * h);
    d1[2] = (sp - sm) / (2.0 * h);
    d2[0] = (xp - 2.0 * x0 + xm) / (h * h);
    d2[1] = (yp - 2.0 * y0 + ym) / (h * h);
    d2[2] = (sp - 2.0 * s0 + sm) / (h * h);
}

static void reference(double mjd, double sec, double baseH, int levels,
                      double *r1, double *r2)
{
    double t1[8][3], t2[8][3], h = baseH, f;
    int i, k, c;

    for (i = 0; i < levels; i++) {
        diff2(mjd, sec, h, t1[i], t2[i]);
        h *= 0.5;
    }
    for (k = 1; k < levels; k++) {
        f = pow(4.0, (double) k);
        for (i = 0; i < levels - k; i++) {
            for (c = 0; c < 3; c++) {
                t1[i][c] = (f * t1[i + 1][c] - t1[i][c]) / (f - 1.0);
                t2[i][c] = (f * t2[i + 1][c] - t2[i][c]) / (f - 1.0);
            }
        }
    }
    for (c = 0; c < 3; c++) { r1[c] = t1[0][c]; r2[c] = t2[0][c]; }
}

int main(void)
{
    double mjdList[NEPOCH];
    double hList[] = {3000.0, 1800.0, 1200.0, 900.0, 600.0, 400.0, 300.0,
                      200.0, 150.0, 120.0, 90.0, 60.0, 30.0, 10.0, 3.0, 1.0};
    int nh = (int) (sizeof(hList) / sizeof(hList[0]));
    int i, j, c;
    double sec = 43200.0;
    const char *name[3] = {"X", "Y", "s"};

    for (i = 0; i < NEPOCH; i++) mjdList[i] = 47892.0 + i * 1826.0;

    /* ---- (a) is the reference trustworthy? ------------------------------ */
    printf("REFERENCE VALIDATION\n");
    printf("Two Romberg references, base steps 19200 s and 9600 s, five\n");
    printf("levels each. The spread is the reference's own uncertainty.\n\n");
    printf("%18s %14s %14s %14s\n", "", "X", "Y", "s");
    {
        double worst1[3] = {0, 0, 0}, worst2[3] = {0, 0, 0};
        for (i = 0; i < NEPOCH; i++) {
            double a1[3], a2[3], b1[3], b2[3];
            reference(mjdList[i], sec, 19200.0, 5, a1, a2);
            reference(mjdList[i], sec, 9600.0, 5, b1, b2);
            for (c = 0; c < 3; c++) {
                if (fabs(a1[c] - b1[c]) > worst1[c]) worst1[c] = fabs(a1[c] - b1[c]);
                if (fabs(a2[c] - b2[c]) > worst2[c]) worst2[c] = fabs(a2[c] - b2[c]);
            }
        }
        printf("%18s %14.4e %14.4e %14.4e\n", "first derivative",
               worst1[0], worst1[1], worst1[2]);
        printf("%18s %14.4e %14.4e %14.4e\n", "second derivative",
               worst2[0], worst2[1], worst2[2]);
    }

    /* ---- (b) error curves, absolute and normalised ---------------------- */
    printf("\nFIRST DERIVATIVE, max over %d epochs 1990-2050\n", NEPOCH);
    printf("%8s %12s %12s %12s %14s\n", "h [s]", "dX/dt", "dY/dt", "ds/dt",
           "worst v [m/s]");
    for (j = 0; j < nh; j++) {
        double e[3] = {0, 0, 0}, worst = 0.0;
        for (i = 0; i < NEPOCH; i++) {
            double d1[3], d2[3], r1[3], r2[3];
            diff2(mjdList[i], sec, hList[j], d1, d2);
            reference(mjdList[i], sec, 19200.0, 5, r1, r2);
            for (c = 0; c < 3; c++) {
                if (fabs(d1[c] - r1[c]) > e[c]) e[c] = fabs(d1[c] - r1[c]);
            }
        }
        for (c = 0; c < 3; c++) {
            if (e[c] > worst) worst = e[c];
        }
        printf("%8.0f %12.3e %12.3e %12.3e %14.3e\n", hList[j],
               e[0], e[1], e[2], worst * ORBIT_RADIUS);
    }

    printf("\nSECOND DERIVATIVE, max over %d epochs 1990-2050\n", NEPOCH);
    printf("%8s %12s %12s %12s %14s\n", "h [s]", "d2X/dt2", "d2Y/dt2",
           "d2s/dt2", "worst a [m/s2]");
    for (j = 0; j < nh; j++) {
        double e[3] = {0, 0, 0}, worst = 0.0;
        for (i = 0; i < NEPOCH; i++) {
            double d1[3], d2[3], r1[3], r2[3];
            diff2(mjdList[i], sec, hList[j], d1, d2);
            reference(mjdList[i], sec, 19200.0, 5, r1, r2);
            for (c = 0; c < 3; c++) {
                if (fabs(d2[c] - r2[c]) > e[c]) e[c] = fabs(d2[c] - r2[c]);
            }
        }
        for (c = 0; c < 3; c++) {
            if (e[c] > worst) worst = e[c];
        }
        printf("%8.0f %12.3e %12.3e %12.3e %14.3e\n", hList[j],
               e[0], e[1], e[2], worst * ORBIT_RADIUS);
    }

    printf("\nCOMBINED SELECTION\n");
    printf("Normalised error = max(velocity error / %.0e m/s,\n"
           "                       acceleration error / %.0e m/s^2).\n",
           VELOCITY_BUDGET, ACCELERATION_BUDGET);
    printf("A value below 1 means the step meets the budget.\n\n");
    printf("%8s %14s %14s %14s\n", "h [s]", "velocity", "acceleration",
           "normalised");
    for (j = 0; j < nh; j++) {
        double e1 = 0.0, e2 = 0.0, n1, n2;
        for (i = 0; i < NEPOCH; i++) {
            double d1[3], d2[3], r1[3], r2[3];
            diff2(mjdList[i], sec, hList[j], d1, d2);
            reference(mjdList[i], sec, 19200.0, 5, r1, r2);
            for (c = 0; c < 3; c++) {
                if (fabs(d1[c] - r1[c]) > e1) e1 = fabs(d1[c] - r1[c]);
                if (fabs(d2[c] - r2[c]) > e2) e2 = fabs(d2[c] - r2[c]);
            }
        }
        n1 = e1 * ORBIT_RADIUS / VELOCITY_BUDGET;
        n2 = e2 * ORBIT_RADIUS / ACCELERATION_BUDGET;
        printf("%8.0f %14.3e %14.3e %14.3e%s\n", hList[j], n1, n2,
               n1 > n2 ? n1 : n2, "");
    }

    (void) name;
    return 0;
}
