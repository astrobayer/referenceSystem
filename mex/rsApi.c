/*
 * rsApi.c
 * -------
 * Implementation of rsApi.h. No mex.h, no MATLAB, no printing.
 *
 * -------------------------------------------------------------------------
 * referenceSystem v2.1
 * Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
 * Created: 2026-07-27 18:00 (CEST, UTC+02:00)
 * -------------------------------------------------------------------------
 */
#include "rsApi.h"
#include "rsCheb.h"
#include "rsCore.h"
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* TT - TAI, seconds. The same literal iersConstants publishes; it is a
 * definition rather than a measurement and cannot drift. */
static const double RS_API_TT_MINUS_TAI = 32.184;

static int rsApiCheck(const rsApiInterpolant *ip)
{
    if (ip == NULL || ip->coefficient == NULL || ip->taiMinusUtc == NULL) {
        return RS_API_NULL_ARGUMENT;
    }
    if (ip->degree < 1 || ip->degree > RS_CHEB_MAX_DEGREE ||
        ip->panelCount < 1 || !(ip->panelSpan > 0.0)) {
        return RS_API_BAD_INTERPOLANT;
    }
    if (ip->cipModel != 2006 && ip->cipModel != 2000) {
        return RS_API_BAD_INTERPOLANT;
    }
    return RS_API_OK;
}

int rsApiPanelIndex(const rsApiInterpolant *interpolant, double mjdUtc)
{
    double offset;
    int index;

    if (rsApiCheck(interpolant) != RS_API_OK) {
        return -1;
    }
    offset = (mjdUtc - interpolant->firstPanelMjd) / interpolant->panelSpan;
    /* NaN fails both comparisons, which is the point of writing it this way. */
    if (!(offset >= 0.0) || !(offset <= (double)interpolant->panelCount)) {
        return -1;
    }
    index = (int)floor(offset);
    /* The very end of the last panel belongs to it, not to the one after. */
    if (index == interpolant->panelCount) {
        index = interpolant->panelCount - 1;
    }
    return index;
}

/* ZERO MEANS SIX, AND THAT IS A PUBLIC-ABI DECISION RATHER THAN A COURTESY.
 * rsApiInterpolant is a struct a caller fills in themselves - the worked RK4
 * propagator does, and so does testApi - so adding a field with no default
 * silently changes the meaning of every existing hand-built interpolant.
 * Adding it WITHOUT the default did exactly that here: quantityCount came out
 * zero, the panel term in the offset vanished, every panel read panel 0's
 * coefficients, and the residual against the direct chain went from 1.16e-16
 * to 6.53e-07 - small enough to look like a tolerance and entirely wrong.
 * Caught by the standalone C suite before the change left the container.
 *
 * The six quantities the rotation needs, at one epoch inside a known panel.
 * A format-2 file carries a seventh, the excess length of day; it is stridden
 * over rather than read, because nothing in this API uses it - rsApiRotationRate
 * differences rather than differentiates. */
static int rsApiSample(const rsApiInterpolant *ip, int panel, double mjdUtc,
                       double *value)
{
    double panelStart = ip->firstPanelMjd + (double)panel * ip->panelSpan;
    int stride = ip->degree + 1;
    int channels = (ip->quantityCount > 0) ? ip->quantityCount : RS_API_QUANTITIES;
    int q;

    for (q = 0; q < RS_API_QUANTITIES; q++) {
        const double *c = ip->coefficient +
            (size_t)((panel * channels) + q) * (size_t)stride;
        int status = rsChebEval(c, ip->degree, panelStart, ip->panelSpan,
                                mjdUtc, &value[q]);
        if (status != RS_CHEB_OK) {
            return RS_API_OUT_OF_RANGE;
        }
    }
    return RS_API_OK;
}

/*
 * Both entry points come here. derivativeOrder is 0 or 1; the three-sample
 * blocking is exactly what the MATLAB path builds, so rsRotationItrsToGcrsFromCip
 * cannot tell the two callers apart - which is the whole point.
 */
static int rsApiRotationCore(const rsApiInterpolant *ip, double mjdUtc,
                             double step, int derivativeOrder,
                             double *r, double *rdot)
{
    double ttDay[1];
    double ttSec[1];
    double ut1Day[1];
    double ut1Sec[1];
    double omega[1];
    double xp[3];
    double yp[3];
    double dX[3];
    double dY[3];
    double cipX[3];
    double cipY[3];
    double cipS[3];
    double value[RS_API_QUANTITIES];   /* only the first six are read */
    double localR[9];
    double localRdot[9];
    double dayShift;
    int panel;
    int sample;
    int status;
    int k;

    status = rsApiCheck(ip);
    if (status != RS_API_OK) {
        return status;
    }
    if (r == NULL || (derivativeOrder > 0 && (rdot == NULL || !(step > 0.0)))) {
        return RS_API_NULL_ARGUMENT;
    }

    /* Sample 1 is the epoch; 0 and 2 are the difference shoulders and are
     * filled only when a derivative is wanted. An unwanted shoulder is left at
     * the epoch's own value rather than uninitialised - the core does not read
     * it, and a stale stack value that it might one day read is a defect
     * waiting for a change of mind. */
    for (sample = 0; sample < 3; sample++) {
        double shift = 0.0;
        if (derivativeOrder > 0) {
            shift = (sample == 0) ? -step : ((sample == 2) ? step : 0.0);
        }
        dayShift = shift / 86400.0;
        panel = rsApiPanelIndex(ip, mjdUtc + dayShift);
        if (panel < 0) {
            return RS_API_OUT_OF_RANGE;
        }
        status = rsApiSample(ip, panel, mjdUtc + dayShift, value);
        if (status != RS_API_OK) {
            return status;
        }
        cipX[sample] = value[0];
        cipY[sample] = value[1];
        cipS[sample] = value[2];
        xp[sample] = value[3];
        yp[sample] = value[4];
        /* The offsets are already inside X and Y (see rsApi.h). Applying the
         * sampled dX and dY again would be a few hundred microarcseconds. */
        dX[sample] = 0.0;
        dY[sample] = 0.0;
        if (sample == 1) {
            panel = rsApiPanelIndex(ip, mjdUtc);
            ttSec[0] = (mjdUtc - floor(mjdUtc)) * 86400.0
                     + ip->taiMinusUtc[panel] + RS_API_TT_MINUS_TAI;
            ttDay[0] = floor(mjdUtc);
            ut1Sec[0] = (mjdUtc - floor(mjdUtc)) * 86400.0 + value[5];
            ut1Day[0] = floor(mjdUtc);
        }
    }

    omega[0] = 7.292115e-5;

    status = rsRotationItrsToGcrsFromCip(1, ttDay, ttSec, ut1Day, ut1Sec,
        xp, yp, dX, dY, omega, cipX, cipY, cipS,
        ip->cipModel, derivativeOrder,
        (derivativeOrder > 0) ? step : 1.0, localR, localRdot, NULL);
    if (status != 0) {
        return RS_API_INTERNAL;
    }

    /* Written last, so nothing reaches the caller's arrays on a failure. */
    for (k = 0; k < 9; k++) {
        r[k] = localR[k];
    }
    if (derivativeOrder > 0) {
        for (k = 0; k < 9; k++) {
            rdot[k] = localRdot[k];
        }
    }
    return RS_API_OK;
}

int rsApiRotation(const rsApiInterpolant *interpolant, double mjdUtc,
                  double *r)
{
    return rsApiRotationCore(interpolant, mjdUtc, 0.0, 0, r, NULL);
}

int rsApiRotationRate(const rsApiInterpolant *interpolant, double mjdUtc,
                      double step, double *r, double *rdot)
{
    return rsApiRotationCore(interpolant, mjdUtc, step, 1, r, rdot);
}

/* ------------------------------------------------------------------ */
/* Reading a file written by referenceSystem.writeInterpolant          */
/* ------------------------------------------------------------------ */

int rsApiInterpolantSize(const rsApiInterpolant *interpolant)
{
    int channels;
    if (interpolant == NULL) {
        return 0;
    }
    channels = (interpolant->quantityCount > 0)
             ? interpolant->quantityCount : RS_API_QUANTITIES;
    return (interpolant->degree + 1) * channels * interpolant->panelCount;
}

/*
 * cipModel arrives as TEXT, not as a number. The file writes what the EOP
 * series calls the frame - "IAU2006/2000A" - and atoi of that is 0, which is
 * neither of the two legal values and would have been caught only by the model
 * check inside the rotation. Mapping it here, by name, means the file stays
 * readable by a human and the C side never guesses.
 */
static int rsApiParseCipModel(const char *text)
{
    if (strstr(text, "2006") != NULL) {
        return 2006;
    }
    if (strstr(text, "2000") != NULL) {
        return 2000;
    }
    return -1;
}

int rsApiReadInterpolant(const char *path, rsApiInterpolant *interpolant,
                         double *coefficient, int coefficientLength,
                         double *taiMinusUtc, int taiLength)
{
    char line[512];
    FILE *stream;
    int version = 0;
    int seenCoefficient = 0;
    int panel;
    int k;

    if (path == NULL || interpolant == NULL) {
        return RS_API_NULL_ARGUMENT;
    }
    interpolant->coefficient = NULL;
    interpolant->taiMinusUtc = NULL;
    interpolant->degree = 0;
    interpolant->panelCount = 0;
    interpolant->panelSpan = 0.0;
    interpolant->firstPanelMjd = 0.0;
    interpolant->cipModel = 0;
    interpolant->quantityCount = 0;

    stream = fopen(path, "r");
    if (stream == NULL) {
        return RS_API_BAD_FILE;
    }

    while (fgets(line, (int)sizeof line, stream) != NULL) {
        char text[128];
        if (sscanf(line, "referenceSystemInterpolant %d", &version) == 1) {
            /* An unknown version is refused rather than read hopefully: a
             * format that changed and a reader that guessed would produce
             * coefficients that are plausible and wrong. */
            if (version != 1 && version != 2) {
                fclose(stream);
                return RS_API_BAD_FILE;
            }
            /* FORMAT 1 FILES STAY READABLE, AND THAT IS THE POINT OF THE
             * VERSION RATHER THAN A COURTESY. The committed arc.eopi fixture
             * is format 1 and is the only end-to-end evidence that C reads
             * what MATLAB wrote; a format bump that invalidated it would have
             * destroyed the check while claiming to extend it. The default
             * below is overwritten if the file names its quantities. */
            interpolant->quantityCount = (version == 1) ? 6 : 7;
            continue;
        }
        if (sscanf(line, "degree %d", &interpolant->degree) == 1) continue;
        if (sscanf(line, "panelCount %d", &interpolant->panelCount) == 1) continue;
        if (sscanf(line, "panelSpan %lf", &interpolant->panelSpan) == 1) continue;
        if (sscanf(line, "firstPanelMjd %lf", &interpolant->firstPanelMjd) == 1) continue;
        if (sscanf(line, "cipModel %127s", text) == 1) {
            interpolant->cipModel = rsApiParseCipModel(text);
            continue;
        }
        if (strncmp(line, "quantity ", 9) == 0) {
            /* COUNTED FROM THE FILE, NOT INFERRED FROM THE VERSION. The file
             * names its channels; a reader that trusted the version number
             * instead would stride correctly only for as long as the two
             * never disagreed, and would then be wrong in a way that produces
             * smooth, plausible coefficients. */
            const char *cursor = line + 9;
            int count = 0;
            while (*cursor != '\0') {
                while (*cursor == ' ' || *cursor == '\t') cursor++;
                if (*cursor == '\0' || *cursor == '\n' || *cursor == '\r') break;
                count++;
                while (*cursor != '\0' && *cursor != ' ' && *cursor != '\t' &&
                       *cursor != '\n' && *cursor != '\r') cursor++;
            }
            if (count < RS_API_QUANTITIES || count > RS_API_MAX_QUANTITIES) {
                fclose(stream);
                return RS_API_BAD_FILE;
            }
            interpolant->quantityCount = count;
            continue;
        }
        if (strncmp(line, "taiMinusUtc", 11) == 0) {
            const char *cursor = line + 11;
            for (k = 0; k < interpolant->panelCount; k++) {
                double value;
                int consumed = 0;
                if (sscanf(cursor, " %lf%n", &value, &consumed) != 1) {
                    fclose(stream);
                    return RS_API_BAD_FILE;
                }
                if (taiMinusUtc != NULL) {
                    if (k >= taiLength) {
                        fclose(stream);
                        return RS_API_BUFFER_TOO_SMALL;
                    }
                    taiMinusUtc[k] = value;
                }
                cursor += consumed;
            }
            continue;
        }
        if (strncmp(line, "coefficient", 11) == 0) {
            seenCoefficient = 1;
            break;
        }
    }

    /* BOTH VERSIONS, HERE AS WELL AS AT THE VERSION LINE. Until rev. 1.221
     * this test still read "version != 1": the version line admitted format 2
     * and this check then refused it, so every file writeInterpolant has
     * written since P19c came back RS_API_BAD_FILE. The only file the C suite
     * read was the format-1 fixture, which is why nothing noticed; testApi
     * now reads a format-2 one too. */
    if ((version != 1 && version != 2) || !seenCoefficient || interpolant->degree < 1 ||
        interpolant->panelCount < 1 || interpolant->cipModel < 0 ||
        !(interpolant->panelSpan > 0.0)) {
        fclose(stream);
        return RS_API_BAD_FILE;
    }

    /* Header only: the caller now knows how much to allocate. */
    if (coefficient == NULL) {
        fclose(stream);
        return RS_API_OK;
    }
    if (coefficientLength < rsApiInterpolantSize(interpolant)) {
        fclose(stream);
        return RS_API_BUFFER_TOO_SMALL;
    }

    /* One value per line, panel-major and quantity-major within a panel, the
     * layout writeInterpolant emits and this header documents. A file with
     * too few values is a parse failure rather than a partly filled array. */
    for (k = 0; k < rsApiInterpolantSize(interpolant); k++) {
        if (fscanf(stream, "%lf", &coefficient[k]) != 1) {
            fclose(stream);
            return RS_API_BAD_FILE;
        }
    }
    fclose(stream);

    interpolant->coefficient = coefficient;
    interpolant->taiMinusUtc = taiMinusUtc;
    (void)panel;
    return RS_API_OK;
}
