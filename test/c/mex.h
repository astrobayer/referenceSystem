/* mex.h
 * -----
 * Redirect shim used only when mex/mexGateway.c is compiled standalone with
 * gcc by runStandaloneTests.sh, where no MATLAB is present. The real MATLAB
 * build never sees this file: test/c is not on the include path of
 * referenceSystem.buildMex, which finds the genuine mex.h first.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-24 18:55 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "mexStub.h"
