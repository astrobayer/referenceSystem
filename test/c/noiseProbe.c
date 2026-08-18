/*
 * noiseProbe.c
 * ------------
 * Measures the intrinsic evaluation noise of iauXys06a, which sets the
 * roundoff floor of any finite-difference derivative built on it. The step
 * study cannot be read until this number is known: an error curve that stops
 * falling may have hit the function's noise or may have hit the reference's,
 * and those call for different conclusions (obligation O8).
 *
 * Method: over a window of +/- 1 hour, sample X, Y, s at 201 points and fit a
 * degree-6 polynomial by least squares. Over one hour the CIP is smooth far
 * beyond degree 6 -- the fastest term in the IAU 2006/2000A series has a
 * period of about five days -- so the fit residual is evaluation noise and
 * nothing else.
 *
 * The second measurement is the argument granularity: the smallest change in
 * the SOFA two-part date that the representation can express at this epoch.
 */
#include <stdio.h>
#include <math.h>
#include "sofa.h"

#define DAY 86400.0
#define NSAMPLE 201
#define NDEG 6

static void fitResidual(const double *t, const double *f, int n, int deg,
                        double *rms, double *peak)
{
    /* Normal equations on a scaled abscissa; deg is small so this is stable
     * enough for a residual measurement, and the residual is checked against
     * a second degree to confirm it is not a fit artefact. */
    double a[NDEG + 1][NDEG + 2];
    double c[NDEG + 1];
    int i, j, k, m = deg + 1;
    double tmax = 0.0;

    for (i = 0; i < n; i++) {
        if (fabs(t[i]) > tmax) tmax = fabs(t[i]);
    }
    for (j = 0; j < m; j++) {
        for (k = 0; k < m; k++) {
            double s = 0.0;
            for (i = 0; i < n; i++) s += pow(t[i] / tmax, j + k);
            a[j][k] = s;
        }
        {
            double s = 0.0;
            for (i = 0; i < n; i++) s += f[i] * pow(t[i] / tmax, j);
            a[j][m] = s;
        }
    }
    for (j = 0; j < m; j++) {
        int piv = j;
        for (k = j + 1; k < m; k++) {
            if (fabs(a[k][j]) > fabs(a[piv][j])) piv = k;
        }
        for (k = 0; k <= m; k++) {
            double tmp = a[j][k]; a[j][k] = a[piv][k]; a[piv][k] = tmp;
        }
        for (k = j + 1; k < m; k++) {
            double fct = a[k][j] / a[j][j];
            for (i = j; i <= m; i++) a[k][i] -= fct * a[j][i];
        }
    }
    for (j = m - 1; j >= 0; j--) {
        double s = a[j][m];
        for (k = j + 1; k < m; k++) s -= a[j][k] * c[k];
        c[j] = s / a[j][j];
    }
    *rms = 0.0; *peak = 0.0;
    for (i = 0; i < n; i++) {
        double v = 0.0, r;
        for (j = m - 1; j >= 0; j--) v = v * (t[i] / tmax) + c[j];
        r = f[i] - v;
        *rms += r * r;
        if (fabs(r) > *peak) *peak = fabs(r);
    }
    *rms = sqrt(*rms / n);
}

int main(void)
{
    double t[NSAMPLE], fx[NSAMPLE], fy[NSAMPLE], fs[NSAMPLE];
    double rms, peak;
    double mjd = 54195.0, sec0 = 43200.0;
    int i;

    for (i = 0; i < NSAMPLE; i++) {
        double dt = -3600.0 + 7200.0 * i / (NSAMPLE - 1.0);
        double d1 = 2400000.5 + mjd;
        double d2 = (sec0 + dt) / DAY;
        t[i] = dt;
        iauXys06a(d1, d2, &fx[i], &fy[i], &fs[i]);
    }

    printf("Evaluation noise of iauXys06a over a two-hour window\n");
    printf("(degree-6 least-squares residual, 201 samples)\n\n");
    printf("%4s %14s %14s %14s\n", "deg", "rms [rad]", "peak [rad]", "quantity");
    fitResidual(t, fx, NSAMPLE, 6, &rms, &peak);
    printf("%4d %14.4e %14.4e   X\n", 6, rms, peak);
    fitResidual(t, fy, NSAMPLE, 6, &rms, &peak);
    printf("%4d %14.4e %14.4e   Y\n", 6, rms, peak);
    fitResidual(t, fs, NSAMPLE, 6, &rms, &peak);
    printf("%4d %14.4e %14.4e   s\n", 6, rms, peak);

    printf("\nSame with degree 4, to show the residual is noise and not a\n"
           "truncated fit (an unconverged fit falls when the degree rises):\n\n");
    fitResidual(t, fx, NSAMPLE, 4, &rms, &peak);
    printf("%4d %14.4e %14.4e   X\n", 4, rms, peak);
    fitResidual(t, fy, NSAMPLE, 4, &rms, &peak);
    printf("%4d %14.4e %14.4e   Y\n", 4, rms, peak);
    fitResidual(t, fs, NSAMPLE, 4, &rms, &peak);
    printf("%4d %14.4e %14.4e   s\n", 4, rms, peak);

    printf("\nArgument granularity at this epoch:\n");
    {
        double d2 = sec0 / DAY;
        double u = nextafter(d2, 2.0) - d2;
        printf("  ulp of the fraction-of-day argument  %.4e day = %.4e s\n",
               u, u * DAY);
    }
    printf("  machine epsilon                      %.4e\n", 2.220446049250313e-16);
    printf("  eps * |X|                            %.4e rad\n",
           2.220446049250313e-16 * 7.12e-4);

    return 0;
}
