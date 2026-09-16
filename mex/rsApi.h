/*
 * rsApi.h
 * -------
 * The public C interface to the ITRS to GCRS rotation (prompt P19).
 *
 * WHAT THIS IS FOR
 *   An orbit integrator written in C or Fortran needs R(t) inside its right
 *   hand side, several times per step, for millions of steps. Reaching MATLAB
 *   for each one is not an option, and evaluating the IAU 2006/2000A series
 *   there costs about fifty microseconds per call. This header lets such a
 *   program link the toolbox directly and evaluate precomputed Chebyshev
 *   panels instead, with MATLAB nowhere in the loop.
 *
 * WHAT IT IS NOT
 *   It is not a second implementation. rsApiRotation assembles nothing: it
 *   evaluates the panels through rsCheb.c and hands the result to
 *   rsRotationItrsToGcrsFromCip, which is the same function the MATLAB path
 *   calls through the gateway. A C program and a MATLAB script therefore
 *   produce the same matrix from the same panels, bit for bit, and that is
 *   asserted rather than assumed - see test/c/testApi.c.
 *
 * THE CALLER OWNS THE COEFFICIENTS
 *   rsApiInterpolant holds POINTERS. Nothing here allocates, frees, or copies
 *   the panel data, so the same coefficients may be shared by every thread of
 *   a parallel integration without a lock. The struct is small and is meant to
 *   be passed by pointer and read concurrently; every function here is
 *   re-entrant and writes only through its output arguments.
 *
 * COEFFICIENT LAYOUT
 *   coefficient[((panel * quantityCount) + quantity) * (degree + 1) + k]
 *   quantity 0..5 = X, Y, s, xp, yp, dut1, the order
 *   earthOrientationInterpolant publishes in .quantity; older files carry a
 *   seventh channel, lod, which is read over and not used.
 *   Panel-major so that
 *   one panel is contiguous: an integrator stays inside one panel for a whole
 *   day and should not stride across the array to do it.
 *
 *   X, Y AND s ALREADY CARRY THE OBSERVED POLE OFFSETS. The builder fits the
 *   output of cipCoordinates, which has applied dX and dY, so they must not be
 *   applied again here and are not.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-27 18:00 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#ifndef RS_API_H
#define RS_API_H

#ifdef __cplusplus
extern "C" {
#endif

#define RS_API_QUANTITIES 6      /* format 1: X Y s xp yp dut1            */
#define RS_API_MAX_QUANTITIES 7  /* format 2 appends lod                  */

#define RS_API_OK              0
#define RS_API_NULL_ARGUMENT   1
#define RS_API_BAD_INTERPOLANT 2
#define RS_API_OUT_OF_RANGE    3   /* the epoch is not inside any panel */
#define RS_API_INTERNAL        4
#define RS_API_BAD_FILE        5   /* unreadable, wrong version, malformed   */
#define RS_API_BUFFER_TOO_SMALL 6  /* see rsApiInterpolantSize               */
#define RS_API_BAD_EPOCH       7   /* day not whole, or not finite (rev. 1.236) */

/*
 * A set of Chebyshev panels and the constants needed to turn UTC into the two
 * time scales the rotation runs on.
 *
 *   degree         Chebyshev degree; 20 is decision D82
 *   panelCount     number of consecutive panels
 *   panelSpan      panel length in days; 1.0 is decision D82
 *   firstPanelMjd  UTC Modified Julian Date at which panel 0 begins
 *   quantityCount  channels per panel, 6 or 7, and ZERO MEANS SIX, so an
 *                  interpolant built by hand before this field existed keeps
 *                  its meaning. Any other value is RS_API_BAD_INTERPOLANT.
 *                  Read from the file's own quantity line. The rotation reads
 *                  the first six; what the count buys is correct striding
 *                  over a seventh.
 *   coefficient    [(degree+1) * quantityCount * panelCount], layout above
 *   taiMinusUtc    [panelCount] seconds, the leap second count on each panel.
 *                  ONE VALUE PER PANEL RATHER THAN ONE FOR THE WHOLE SET,
 *                  because a leap second falls on a panel boundary by
 *                  construction - panels are aligned to whole UTC days - so a
 *                  set spanning one is still exactly represented.
 *   cipModel       2006 or 2000; unread while panels are supplied, validated
 *                  so that it cannot start meaning something later
 */
typedef struct {
    int degree;
    int quantityCount;
    int panelCount;
    double panelSpan;
    double firstPanelMjd;
    const double *coefficient;
    const double *taiMinusUtc;
    int cipModel;
} rsApiInterpolant;

/*
 * The rotation from ITRS to GCRS at one UTC epoch.
 *
 *   mjdUtc   UTC Modified Julian Date
 *   r        [9] the matrix, column-major, as MATLAB stores a 3-by-3 page
 *
 * Returns RS_API_OK, or one of the codes above. On anything but OK, r is
 * untouched: a failed call cannot be mistaken for a computed matrix.
 *
 * AN MJD DOUBLE RESOLVES 0.63 us NEAR THE PRESENT. The rotation is exactly what
 * the MJD names, but the instant the caller meant can be half of that away, and
 * the Earth turns 2.3e-11 rad in that: 4.6 times P19c's 5e-12. Measured against
 * MATLAB, 2.15e-11 on R and 1.57e-15 1/s on Rdot. In the last 0.3 us before a
 * leap second the nearest MJD is the next day's 0h, a whole SI second later,
 * and the rotation is 7.2e-5 rad out. An integrator that carries its time as a
 * day and a second should call rsApiRotationDaySecond below, which has neither
 * limit.
 */
int rsApiRotation(const rsApiInterpolant *interpolant, double mjdUtc,
                  double *r);

/*
 * The rotation and its time derivative, in units of per second.
 *
 *   step   central-difference step in seconds, > 0. The same construction the
 *          direct path uses under decision D28, so the two agree; the panels
 *          could be differentiated analytically instead and that is a separate
 *          prompt, not a variation to be slipped in here.
 *   rdot   [9], may not be NULL
 *
 * RDOT IS THE TIME DERIVATIVE OF R (decision D128). The Earth rotation rate is
 * the ERA slope times 1 + d(UT1 - TAI)/dt, the derivative taken as the central
 * difference of the dut1 panels at the same three samples as the CIP and the
 * pole, each less the TAI - UTC of its own panel, which is what
 * referenceSystem.rotationItrsToGcrs does with the same panels.
 *
 * LEAP SECONDS (rev. 1.226). The shoulders are step SI seconds either side, so
 * a shoulder beyond a change in taiMinusUtc is taken at the label that instant
 * has - the naive label is one second off. A shoulder that lands inside the
 * leap second itself, which no MJD names, returns RS_API_OUT_OF_RANGE: the
 * window is one second wide at each of +step and -step from the leap second.
 */
int rsApiRotationRate(const rsApiInterpolant *interpolant, double mjdUtc,
                      double step, double *r, double *rdot);

/*
 * The same two, at a UTC epoch given as a day and a second (rev. 1.236), the
 * form referenceSystem.rotationItrsToGcrs takes. For the same day and second
 * the matrices are MATLAB's: the difference shoulders are built and carried as
 * MATLAB builds them, and the panels are read at the same MJD.
 *
 *   dayUtc   UTC Modified Julian Date of the day, a whole number
 *   secUtc   UTC seconds since 0h of that day. Values outside [0, 86400) are
 *            carried into the neighbouring days as daySecondToEpoch carries
 *            them, with a day 86401 s long before a leap second. That makes
 *            [86400, 86401) on such a day the leap second itself.
 *
 * WHY A SECOND FORM. UT1 is formed from the second itself, so this form does
 * not have the MJD form's 0.63 us limit. The panels are still read at
 * day + sec/86400, as MATLAB reads them. In 0.63 us the fastest fitted angle,
 * X under precession at 3.1e-12 rad/s, moves 1.9e-18 rad, against 4.6e-11 for
 * the Earth rotation angle, so only the angle needed the second.
 *
 * An epoch or shoulder inside a leap second returns RS_API_OUT_OF_RANGE, as
 * rsApiRotationRate describes. So does one outside the panels. A day that is
 * not a whole number, or a day or second that is not finite, returns
 * RS_API_BAD_EPOCH.
 */
int rsApiRotationDaySecond(const rsApiInterpolant *interpolant, double dayUtc,
                           double secUtc, double *r);

int rsApiRotationRateDaySecond(const rsApiInterpolant *interpolant,
                               double dayUtc, double secUtc, double step,
                               double *r, double *rdot);

/*
 * The index of the panel containing an epoch, or -1 if none does.
 *
 * Exposed because an integrator can hoist it: the panel changes once a day
 * while the right hand side is evaluated thousands of times, and a caller that
 * knows it has not left the panel can skip the search. The rotation functions
 * call this themselves, so using it is an optimisation and never a
 * requirement.
 */
int rsApiPanelIndex(const rsApiInterpolant *interpolant, double mjdUtc);

/*
 * Read a file written by MATLAB's referenceSystem.writeInterpolant.
 *
 * TWO-CALL PROTOCOL, BECAUSE THIS LIBRARY DOES NOT ALLOCATE. Call once with
 * both buffers NULL: the header is parsed, degree, panelCount, panelSpan,
 * firstPanelMjd and cipModel are filled, and the caller can then size its
 * arrays with rsApiInterpolantSize. Call again with the buffers to fill them.
 * The alternative would be for the library to malloc and the caller to
 * remember to free, which is the arrangement that leaks in an integrator that
 * reloads panels once a day for a month.
 *
 *   coefficient      NULL, or at least rsApiInterpolantSize(ip) doubles
 *   taiMinusUtc      NULL, or at least ip->panelCount doubles
 *
 * Returns RS_API_OK, RS_API_BAD_FILE or RS_API_BUFFER_TOO_SMALL. On anything
 * but OK the interpolant is left unusable rather than half filled: its
 * coefficient pointer is set to NULL, so a caller that ignores the return
 * value gets RS_API_NULL_ARGUMENT from the next call rather than a rotation
 * built out of whatever was in the buffer.
 */
int rsApiReadInterpolant(const char *path, rsApiInterpolant *interpolant,
                         double *coefficient, int coefficientLength,
                         double *taiMinusUtc, int taiLength);

/* Number of doubles the coefficient array needs:
 * (degree+1) * quantityCount * panelCount, with quantityCount 0 meaning 6. */
int rsApiInterpolantSize(const rsApiInterpolant *interpolant);

#ifdef __cplusplus
}
#endif

#endif /* RS_API_H */
