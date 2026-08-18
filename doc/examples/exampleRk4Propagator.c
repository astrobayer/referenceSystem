/*
 * exampleRk4Propagator.c - a minimal orbit propagator linking referenceSystem's
 * public C API, written for prompt P19.
 *
 * WHAT THIS EXAMPLE IS FOR. Section B.9 of the handover measures MATLAB's own
 * call overhead at roughly 5 to 15 microseconds and states plainly that it
 * cannot be optimised away: an integrator that evaluates its right-hand side
 * a hundred thousand times per arc pays that overhead a hundred thousand
 * times, whatever the arithmetic underneath costs. rsApiRotation evaluates in
 * about 0.56 microseconds on the reference host, measured by test/c/testApi.c.
 * That difference - not the accuracy, which is identical - is the whole reason
 * the C API exists.
 *
 * WHAT IT IS NOT. The force model here is a point mass plus J2. It is the
 * smallest thing that makes the ITRS-to-GCRS rotation matter, because J2 is
 * expressed in the Earth-fixed frame while the state is integrated in the
 * inertial one. It is NOT a precise orbit determination force model: no
 * third bodies, no solid Earth or ocean tides, no drag, no radiation
 * pressure, no relativistic correction. Do not mistake it for one.
 *
 * BUILD (from the distribution root):
 *
 *   cc -O2 -std=c99 -Imex -Imex/sofa -Imex/iers \
 *      doc/examples/exampleRk4Propagator.c mex/rsApi.c mex/rsCore.c \
 *      mex/rsCheb.c mex/sofa/[all].c mex/iers/[all].c -lm -o rk4
 *
 *   (glob the two source directories; they are written out here because
 *   an asterisk-slash inside a C block comment ends it.)
 *
 * RUN:
 *
 *   % in MATLAB, once, to produce the interpolant file
 *   eop  = referenceSystem.readEop("data/eopc04_20.1962-now");
 *   span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
 *   referenceSystem.writeInterpolant( ...
 *       referenceSystem.earthOrientationInterpolant(span, 'Eop', eop), ...
 *       "arc.eopi");
 *
 *   ./rk4 arc.eopi
 *
 * OWNERSHIP AND THREAD SAFETY (risk R11). This library never allocates. The
 * caller owns every buffer and the two-call protocol below is how it learns
 * the sizes. rsApiRotation and rsApiRotationRate take the interpolant as
 * const and hold no state between calls, so any number of threads may share
 * ONE interpolant concurrently. Filling it with rsApiReadInterpolant is not
 * thread safe and must complete before the threads start.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-08-03 17:10 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */

#include "rsApi.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

/* Geocentric gravitational constant, m^3/s^2, and the reference radius and J2
 * that go with it. IERS Conventions (2010) Table 1.1 and the EGM zonal term.
 * A real force model takes these from its gravity field file, together with
 * the field's own reference radius, and never from a header like this one. */
static const double GM = 3.986004418e14;
static const double RADIUS = 6378136.3;
static const double J2 = 1.0826359e-3;
static const double SECONDS_PER_DAY = 86400.0;

/* Acceleration in the GCRS at one epoch, for a state [x y z vx vy vz]. */
static int acceleration(const rsApiInterpolant *interpolant, double mjdUtc,
                        const double *state, double *result)
{
    double r[9];
    double fixed[3];
    double fixedAcceleration[3];
    double distance;
    double ratio;
    double zonal;
    int status;
    int i;
    int j;

    /* THE ROTATION IS WHY THIS EXAMPLE EXISTS. J2 is a property of the Earth,
     * so it is evaluated in the Earth-fixed frame; the state is integrated in
     * the inertial one. Every right-hand-side evaluation therefore needs one
     * ITRS-to-GCRS rotation, which is exactly the call an integrator cannot
     * afford to make through MATLAB. */
    status = rsApiRotation(interpolant, mjdUtc, r);
    if (status != RS_API_OK) {
        return status;
    }

    /* r is column-major and maps ITRS to GCRS, so its TRANSPOSE maps the
     * inertial position into the Earth-fixed frame. */
    for (i = 0; i < 3; i++) {
        fixed[i] = 0.0;
        for (j = 0; j < 3; j++) {
            fixed[i] += r[i + 3 * j] * state[j];
        }
    }

    distance = sqrt(fixed[0] * fixed[0] + fixed[1] * fixed[1] +
                    fixed[2] * fixed[2]);
    ratio = RADIUS / distance;
    zonal = 1.5 * J2 * ratio * ratio;

    {
        double sine = fixed[2] / distance;
        double common = -GM / (distance * distance * distance);
        double lateral = common * (1.0 - zonal * (5.0 * sine * sine - 1.0));
        fixedAcceleration[0] = lateral * fixed[0];
        fixedAcceleration[1] = lateral * fixed[1];
        fixedAcceleration[2] = common * fixed[2] *
            (1.0 - zonal * (5.0 * sine * sine - 3.0));
    }

    /* Back to the GCRS: r itself, not its transpose. */
    for (i = 0; i < 3; i++) {
        result[i] = state[3 + i];
        result[3 + i] = 0.0;
        for (j = 0; j < 3; j++) {
            result[3 + i] += r[j + 3 * i] * fixedAcceleration[j];
        }
    }
    return RS_API_OK;
}

/* One classical fourth-order Runge-Kutta step of h seconds. */
static int rk4Step(const rsApiInterpolant *interpolant, double *mjdUtc,
                   double *state, double h)
{
    double k1[6];
    double k2[6];
    double k3[6];
    double k4[6];
    double trial[6];
    double dayStep = h / SECONDS_PER_DAY;
    int i;

    if (acceleration(interpolant, *mjdUtc, state, k1) != RS_API_OK) {
        return 1;
    }
    for (i = 0; i < 6; i++) {
        trial[i] = state[i] + 0.5 * h * k1[i];
    }
    if (acceleration(interpolant, *mjdUtc + 0.5 * dayStep, trial, k2)
            != RS_API_OK) {
        return 1;
    }
    for (i = 0; i < 6; i++) {
        trial[i] = state[i] + 0.5 * h * k2[i];
    }
    if (acceleration(interpolant, *mjdUtc + 0.5 * dayStep, trial, k3)
            != RS_API_OK) {
        return 1;
    }
    for (i = 0; i < 6; i++) {
        trial[i] = state[i] + h * k3[i];
    }
    if (acceleration(interpolant, *mjdUtc + dayStep, trial, k4) != RS_API_OK) {
        return 1;
    }
    for (i = 0; i < 6; i++) {
        state[i] += h / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
    }
    *mjdUtc += dayStep;
    return 0;
}

int main(int argc, char *argv[])
{
    rsApiInterpolant interpolant;
    double *coefficient = NULL;
    double *taiMinusUtc = NULL;
    double state[6];
    double mjdUtc;
    double firstEnergy;
    double lastEnergy;
    const char *path = (argc > 1) ? argv[1] : "arc.eopi";
    int size;
    int status;
    int step;

    /* TWO-CALL PROTOCOL. First call with NULL buffers to learn the sizes, then
     * allocate, then fill. The library never mallocs, so nothing here can leak
     * on its behalf. */
    status = rsApiReadInterpolant(path, &interpolant, NULL, 0, NULL, 0);
    if (status != RS_API_OK) {
        fprintf(stderr, "cannot read %s (status %d)\n", path, status);
        return 1;
    }
    size = rsApiInterpolantSize(&interpolant);
    coefficient = malloc((size_t)size * sizeof(double));
    taiMinusUtc = malloc((size_t)interpolant.panelCount * sizeof(double));
    if (coefficient == NULL || taiMinusUtc == NULL) {
        fprintf(stderr, "out of memory\n");
        free(coefficient);
        free(taiMinusUtc);
        return 1;
    }
    status = rsApiReadInterpolant(path, &interpolant, coefficient, size,
                                  taiMinusUtc, interpolant.panelCount);
    if (status != RS_API_OK) {
        fprintf(stderr, "cannot fill %s (status %d)\n", path, status);
        free(coefficient);
        free(taiMinusUtc);
        return 1;
    }

    printf("interpolant: degree %d, %d panel(s), span %g d, first MJD %g\n",
           interpolant.degree, interpolant.panelCount, interpolant.panelSpan,
           interpolant.firstPanelMjd);

    /* A circular orbit at about 500 km, inclined, expressed in the GCRS. */
    mjdUtc = interpolant.firstPanelMjd + 0.1;
    state[0] = 6878137.0;
    state[1] = 0.0;
    state[2] = 0.0;
    state[3] = 0.0;
    state[4] = sqrt(GM / state[0]) * cos(1.7);
    state[5] = sqrt(GM / state[0]) * sin(1.7);

    firstEnergy = 0.5 * (state[3] * state[3] + state[4] * state[4] +
                         state[5] * state[5]) -
        GM / sqrt(state[0] * state[0] + state[1] * state[1] +
                  state[2] * state[2]);

    for (step = 0; step < 5670; step++) {          /* one revolution at 1 s */
        if (rk4Step(&interpolant, &mjdUtc, state, 1.0) != 0) {
            fprintf(stderr, "step %d left the interpolant's interval\n", step);
            break;
        }
    }

    lastEnergy = 0.5 * (state[3] * state[3] + state[4] * state[4] +
                        state[5] * state[5]) -
        GM / sqrt(state[0] * state[0] + state[1] * state[1] +
                  state[2] * state[2]);

    printf("after %d steps: r = (%.1f, %.1f, %.1f) m\n", step,
           state[0], state[1], state[2]);
    /* Energy is NOT conserved exactly here and should not be: J2 makes the
     * orbit non-Keplerian, so this number reports the integrator's behaviour
     * and not a physical invariant. It is printed because a sudden change in
     * it is the cheapest sign that something has gone wrong. */
    printf("relative energy change: %.3e\n",
           fabs((lastEnergy - firstEnergy) / firstEnergy));

    free(coefficient);
    free(taiMinusUtc);
    return 0;
}
