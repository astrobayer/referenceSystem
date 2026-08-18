/*
 * rsCheb.h
 * --------
 * Chebyshev panel interpolation for the Earth orientation chain (prompt P19).
 * Numerical core only: this file knows nothing about SOFA, about the IERS
 * models, about MATLAB or about what the six quantities mean.
 *
 * WHY THE FIT DOES NOT SAMPLE ANYTHING ITSELF
 *   rsChebFit takes VALUES, not a callback. The caller asks rsChebNodes where
 *   to sample, evaluates whatever it likes there - SOFA iauXys06a, the IERS
 *   sub-daily models, a measured series - and hands the values back. That
 *   keeps this file free of every dependency the rest of the toolbox carries,
 *   lets test/c/testCheb.c fit analytic functions with known derivatives, and
 *   means the public C API of P19 can be served from precomputed coefficients
 *   without linking SOFA at all.
 *
 * PANEL GEOMETRY (decision D82, measured in handover section B.9.2)
 *   One day per panel, degree 20, aligned to the rows of the EOP series. The
 *   binding quantity is not the CIP - which reaches its double-precision floor
 *   at degree 8 over a day - but the sub-daily ocean tide and libration, whose
 *   semi-diurnal terms need degree 20 to reach 2.6e-7 uas. Risk R5's proposed
 *   300 s node spacing was aimed at the CIP and was over-conservative by about
 *   a factor of fifteen.
 *
 * WHY CHEBYSHEV AND NOT A SPLINE
 *   Three reasons, in increasing order of importance. Convergence is spectral,
 *   so degree buys accuracy geometrically rather than algebraically. The
 *   derivative is ANALYTIC - rsChebEvalDerivative differentiates the
 *   polynomial, it does not difference the function - which matters because the
 *   direct path obtains Rdot by finite differencing with a step chosen under
 *   decision D28. And the fit is C-infinity inside a panel, so a variable-step
 *   integrator does not meet the midnight slope discontinuity that piecewise
 *   linear EOP interpolation puts in its right-hand side (section B.9.1).
 *
 * CONVENTION
 *   Coefficients are the plain expansion f(u) = sum_{k=0}^{n} c[k] T_k(u) on
 *   u in [-1, 1]; c[0] is NOT halved. u maps to time by
 *   u = 2 (t - t0) / span - 1. Every function here is re-entrant and writes
 *   only through its output pointers (section C.9).
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-27 09:40 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#ifndef RS_CHEB_H
#define RS_CHEB_H

#ifdef __cplusplus
extern "C" {
#endif

/* Largest degree rsChebFit will accept. Degree 20 is decision D82; the ceiling
 * is well above it so that a caller may trade memory for margin, and so that
 * test/c/testCheb.c can drive the fit into its roundoff floor. */
#define RS_CHEB_MAX_DEGREE 64

/* Status codes. Returned, never printed - this library does not warn (D3). */
#define RS_CHEB_OK              0
#define RS_CHEB_BAD_DEGREE      1   /* degree < 1 or > RS_CHEB_MAX_DEGREE     */
#define RS_CHEB_BAD_SPAN        2   /* span not finite and strictly positive  */
#define RS_CHEB_OUT_OF_PANEL    3   /* |u| > 1 + RS_CHEB_EDGE_SLACK           */

/* How far outside a panel rsChebEval will still evaluate. One part in 1e9 of
 * the half-span, which at a one-day panel is about 40 microseconds: enough to
 * absorb the rounding of a panel-boundary epoch, far too little to let a caller
 * extrapolate. A Chebyshev fit diverges outside its interval, so this margin is
 * a rounding allowance and must never be widened into a usable tolerance. */
#define RS_CHEB_EDGE_SLACK 1.0e-9

/*
 * Node positions of a degree-n fit, in the caller's own time variable.
 * Chebyshev-Gauss-Lobatto: node[j] = t0 + span/2 * (cos(pi j / n) + 1), so
 * node[0] is the END of the panel and node[n] the start. The order is not
 * reversed for tidiness because rsChebFit consumes the same order, and a fit
 * that silently disagreed with its own node list about direction would be a
 * quiet sign error in every derivative.
 *
 * node   (n+1) doubles, written
 * Returns RS_CHEB_OK, RS_CHEB_BAD_DEGREE or RS_CHEB_BAD_SPAN.
 */
int rsChebNodes(double t0, double span, int degree, double *node);

/*
 * Fit one quantity from its values at the rsChebNodes points.
 *
 * value         (n+1) doubles, read, in rsChebNodes order
 * coefficient   (n+1) doubles, written
 * Returns RS_CHEB_OK or RS_CHEB_BAD_DEGREE.
 *
 * Cost is O(n^2) and the fit happens once per panel, so the direct summation
 * is used rather than an FFT: at degree 20 that is 441 cosines against the
 * complexity of carrying a transform, and the transform would have to be
 * bit-reproducible across thread counts to satisfy decision D31.
 */
int rsChebFit(const double *value, int degree, double *coefficient);

/*
 * Evaluate the fit at time t.
 *
 * result   1 double, written; untouched if the return is not RS_CHEB_OK, so a
 *          failed evaluation cannot be mistaken for a computed NaN (C.6 rule 5).
 */
int rsChebEval(const double *coefficient, int degree,
               double t0, double span, double t, double *result);

/*
 * Evaluate the ANALYTIC first derivative at time t, in units of the quantity
 * per unit of t. Differentiates the polynomial; no step size is involved and
 * decision D28 does not apply.
 */
int rsChebEvalDerivative(const double *coefficient, int degree,
                         double t0, double span, double t, double *result);

/*
 * Worst absolute difference between the fit and the values it was built from,
 * evaluated at the fit nodes. Zero to roundoff by construction, so this is a
 * cheap self-check of the coefficients rather than an accuracy estimate; the
 * honest residual needs samples the fit has NOT seen and is computed by the
 * MATLAB layer, which owns the sampling.
 */
int rsChebNodeResidual(const double *coefficient, const double *value,
                       int degree, double *residual);

#ifdef __cplusplus
}
#endif

#endif /* RS_CHEB_H */
