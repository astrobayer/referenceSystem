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
 * Every fitted quantity at one epoch inside a known panel: the six the rotation
 * needs and, in a format-2 interpolant, the excess length of day as value[6].
 * UNTIL REV. 1.222 THE SEVENTH WAS STRIDDEN OVER, on the reasoning that
 * rsApiRotationRate "differences rather than differentiates". That named the
 * wrong mechanism: the samples are differenced, but the ERA part of Rdot is
 * analytic in omega, and the length of day enters only through omega. Leaving
 * it out cost up to 1.25e-12 1/s against MATLAB on the P19c test arc (rev.
 * 1.220). value must hold RS_API_MAX_QUANTITIES doubles. */
static int rsApiSample(const rsApiInterpolant *ip, int panel, double mjdUtc,
                       double *value)
{
    double panelStart = ip->firstPanelMjd + (double)panel * ip->panelSpan;
    int stride = ip->degree + 1;
    int channels = (ip->quantityCount > 0) ? ip->quantityCount : RS_API_QUANTITIES;
    int q;

    for (q = 0; q < channels && q < RS_API_MAX_QUANTITIES; q++) {
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

/* The shift of difference shoulder `sample`, in SI seconds: -step, 0, +step.
 * Sample 1 is the epoch; an unwanted shoulder sits on the epoch itself rather
 * than being left uninitialised - the core does not read it, and a stale stack
 * value that it might one day read is a defect waiting for a change of mind. */
static double rsApiShift(int sample, double step, int derivativeOrder)
{
    if (derivativeOrder <= 0) {
        return 0.0;
    }
    return (sample == 0) ? -step : ((sample == 2) ? step : 0.0);
}

/*
 * The three labels of the MJD form, each the UTC MJD the panels are read at.
 */
static int rsApiMjdSamples(const rsApiInterpolant *ip, double mjdUtc,
                           double step, int derivativeOrder, double *sampleMjd)
{
    int centrePanel = rsApiPanelIndex(ip, mjdUtc);
    int sample;

    if (centrePanel < 0) {
        return RS_API_OUT_OF_RANGE;
    }
    for (sample = 0; sample < 3; sample++) {
        double shift = rsApiShift(sample, step, derivativeOrder);
        double dayShift = shift / 86400.0;
        int panel = rsApiPanelIndex(ip, mjdUtc + dayShift);
        if (panel < 0) {
            return RS_API_OUT_OF_RANGE;
        }
        /* A SHOULDER ACROSS A LEAP SECOND IS STEP SI SECONDS AWAY, NOT STEP UTC
         * LABEL SECONDS (rev. 1.226). mjdUtc is a UTC label, and across a
         * change in TAI-UTC the label moves by the step MINUS that change.
         * Until this revision the shoulder was taken at the naive label, one
         * second off in every fitted channel, and within one step of
         * 2017-01-01 the rate missed MATLAB's by 1.1e-14 1/s - 77 times D28's
         * 1 nm/s at 7000 km. If the corrected label lands back on the other
         * side of the boundary, the shoulder is inside the leap second itself,
         * which no MJD names: refused, as rotationItrsToGcrs refuses it. */
        if (ip->taiMinusUtc[panel] != ip->taiMinusUtc[centrePanel]) {
            double labelShift = (shift - (ip->taiMinusUtc[panel]
                                          - ip->taiMinusUtc[centrePanel])) / 86400.0;
            int labelled = rsApiPanelIndex(ip, mjdUtc + labelShift);
            if (labelled < 0
                || ip->taiMinusUtc[labelled] != ip->taiMinusUtc[panel]) {
                return RS_API_OUT_OF_RANGE;
            }
            dayShift = labelShift;
        }
        sampleMjd[sample] = mjdUtc + dayShift;
    }
    return RS_API_OK;
}

/* TAI - UTC on the UTC day that begins at MJD day, read from the panel that
 * holds it. Constant across the panel, because a leap second may fall only on
 * a panel boundary. */
static int rsApiDayTai(const rsApiInterpolant *ip, double day, double *tai)
{
    int panel = rsApiPanelIndex(ip, day);
    if (panel < 0) {
        return RS_API_OUT_OF_RANGE;
    }
    *tai = ip->taiMinusUtc[panel];
    return RS_API_OK;
}

/*
 * A UTC day and second carried into range, as daySecondToEpoch carries them:
 * a day is 86400 s plus the change in TAI - UTC at its end. The one second
 * that is no day's own - 23:59:60 of a leap-second day - is RS_API_OUT_OF_RANGE,
 * for the reason given at rsApiRotationRate. So is a day outside the panels,
 * which bounds both loops.
 */
static int rsApiCarry(const rsApiInterpolant *ip, double *day, double *sec)
{
    double taiHere;
    double taiNext;
    double length;

    while (*sec >= 86400.0) {
        if (rsApiDayTai(ip, *day, &taiHere) != RS_API_OK
            || rsApiDayTai(ip, *day + 1.0, &taiNext) != RS_API_OK) {
            return RS_API_OUT_OF_RANGE;
        }
        length = 86400.0 + (taiNext - taiHere);
        if (*sec < length) {
            return RS_API_OUT_OF_RANGE;
        }
        *sec -= length;
        *day += 1.0;
    }
    while (*sec < 0.0) {
        if (rsApiDayTai(ip, *day - 1.0, &taiHere) != RS_API_OK
            || rsApiDayTai(ip, *day, &taiNext) != RS_API_OK) {
            return RS_API_OUT_OF_RANGE;
        }
        *sec += 86400.0 + (taiNext - taiHere);
        *day -= 1.0;
        if (*sec >= 86400.0) {
            return RS_API_OUT_OF_RANGE;
        }
    }
    return RS_API_OK;
}

/*
 * The MJD the panels are read at for a carried day and second, formed as
 * rotationItrsToGcrs forms it: day + sec/86400, held below the next day.
 * WITHOUT THE HOLD, a second in the last 0.3 us of its day rounds up to the
 * next whole MJD and reads the next panel, whose dut1 is a second higher before
 * a leap second - while UT1 is formed from this day's label. The largest
 * double below the next day keeps the panel, written as MATLAB writes it,
 * nextDay - eps(nextDay), so that the two agree bit for bit.
 */
static double rsApiDayMjd(double day, double sec)
{
    double nextDay = day + 1.0;
    double limit = nextDay - (nextafter(nextDay, HUGE_VAL) - nextDay);
    double mjd = day + sec / 86400.0;
    return (mjd > limit) ? limit : mjd;
}

/*
 * The three labels of the day-and-second form. Each shoulder is the epoch's
 * second plus the shift, carried as daySecondToEpoch carries it, which is how
 * rotationItrsToGcrs builds its shoulders. The MJD form cannot do that, since
 * it has no second to carry.
 */
static int rsApiDaySecondSamples(const rsApiInterpolant *ip, double day,
                                 double sec, double step, int derivativeOrder,
                                 double *sampleMjd)
{
    int sample;

    for (sample = 0; sample < 3; sample++) {
        double sampleDay = day;
        double sampleSec = sec + rsApiShift(sample, step, derivativeOrder);
        int status = rsApiCarry(ip, &sampleDay, &sampleSec);
        if (status != RS_API_OK) {
            return status;
        }
        sampleMjd[sample] = rsApiDayMjd(sampleDay, sampleSec);
        if (rsApiPanelIndex(ip, sampleMjd[sample]) < 0) {
            return RS_API_OUT_OF_RANGE;
        }
    }
    return RS_API_OK;
}

/*
 * Every entry point comes here, with the three labels already formed and the
 * epoch as a carried UTC day and second. derivativeOrder is 0 or 1; the
 * three-sample blocking is exactly what the MATLAB path builds, so
 * rsRotationItrsToGcrsFromCip cannot tell the callers apart - which is the
 * whole point.
 */
static int rsApiRotationCore(const rsApiInterpolant *ip, const double *sampleMjd,
                             double utcDay, double utcSec,
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
    double value[RS_API_MAX_QUANTITIES];
    double lengthOfDay = 0.0;          /* s; stays 0 without a lod channel */
    double localR[9];
    double localRdot[9];
    int centrePanel = rsApiPanelIndex(ip, sampleMjd[1]);
    int sample;
    int status;
    int k;

    if (centrePanel < 0) {
        return RS_API_OUT_OF_RANGE;
    }
    for (sample = 0; sample < 3; sample++) {
        int panel = rsApiPanelIndex(ip, sampleMjd[sample]);
        if (panel < 0) {
            return RS_API_OUT_OF_RANGE;
        }
        status = rsApiSample(ip, panel, sampleMjd[sample], value);
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
            ttSec[0] = utcSec + ip->taiMinusUtc[centrePanel] + RS_API_TT_MINUS_TAI;
            ttDay[0] = utcDay;
            ut1Sec[0] = utcSec + value[5];
            ut1Day[0] = utcDay;
            if (ip->quantityCount >= RS_API_MAX_QUANTITIES) {
                lengthOfDay = value[6];
            }
        }
    }

    /* OMEGA IS MATLAB'S DEFAULT, TERM FOR TERM (rev. 1.222). rotationItrsToGcrs
     * takes the ERA slope from earthRotationAngleRate and, with
     * 'ApplyLengthOfDay' true, scales it by (1 - lod / secondsPerDay) at the
     * epoch; rsEarthRotationAngleRate is the same derivation, and the lod is the
     * same channel of the same panels. Until this revision the value here was
     * the nominal 7.292115e-5 with no lod, and rev. 1.220 measured the two
     * omissions at 1.467e-12 and up to 1.25e-12 1/s, partly cancelling to
     * 5.8e-13 against MATLAB's default. Either repaired alone would have
     * widened that gap, which is why both changed together. */
    omega[0] = rsEarthRotationAngleRate() * (1.0 - lengthOfDay / 86400.0);

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

/* The checks every entry point makes before it forms a label. */
static int rsApiCheckCall(const rsApiInterpolant *ip, double step,
                          int derivativeOrder, const double *r, const double *rdot)
{
    int status = rsApiCheck(ip);
    if (status != RS_API_OK) {
        return status;
    }
    if (r == NULL || (derivativeOrder > 0 && (rdot == NULL || !(step > 0.0)))) {
        return RS_API_NULL_ARGUMENT;
    }
    return RS_API_OK;
}

static int rsApiMjdEntry(const rsApiInterpolant *ip, double mjdUtc,
                         double step, int derivativeOrder, double *r, double *rdot)
{
    double sampleMjd[3];
    int status = rsApiCheckCall(ip, step, derivativeOrder, r, rdot);
    if (status != RS_API_OK) {
        return status;
    }
    status = rsApiMjdSamples(ip, mjdUtc, step, derivativeOrder, sampleMjd);
    if (status != RS_API_OK) {
        return status;
    }
    /* The day and second are recovered from the MJD, so UT1 carries the
     * double's 0.63 us resolution; see rsApiRotationDaySecond. */
    return rsApiRotationCore(ip, sampleMjd, floor(mjdUtc),
                             (mjdUtc - floor(mjdUtc)) * 86400.0,
                             step, derivativeOrder, r, rdot);
}

static int rsApiDaySecondEntry(const rsApiInterpolant *ip, double dayUtc,
                               double secUtc, double step, int derivativeOrder,
                               double *r, double *rdot)
{
    double sampleMjd[3];
    double day = dayUtc;
    double sec = secUtc;
    int status = rsApiCheckCall(ip, step, derivativeOrder, r, rdot);
    if (status != RS_API_OK) {
        return status;
    }
    if (!isfinite(dayUtc) || dayUtc != floor(dayUtc) || !isfinite(secUtc)) {
        return RS_API_BAD_EPOCH;
    }
    status = rsApiCarry(ip, &day, &sec);
    if (status != RS_API_OK) {
        return status;
    }
    status = rsApiDaySecondSamples(ip, day, sec, step, derivativeOrder, sampleMjd);
    if (status != RS_API_OK) {
        return status;
    }
    return rsApiRotationCore(ip, sampleMjd, day, sec, step, derivativeOrder,
                             r, rdot);
}

int rsApiRotation(const rsApiInterpolant *interpolant, double mjdUtc,
                  double *r)
{
    return rsApiMjdEntry(interpolant, mjdUtc, 0.0, 0, r, NULL);
}

int rsApiRotationRate(const rsApiInterpolant *interpolant, double mjdUtc,
                      double step, double *r, double *rdot)
{
    return rsApiMjdEntry(interpolant, mjdUtc, step, 1, r, rdot);
}

int rsApiRotationDaySecond(const rsApiInterpolant *interpolant, double dayUtc,
                           double secUtc, double *r)
{
    return rsApiDaySecondEntry(interpolant, dayUtc, secUtc, 0.0, 0, r, NULL);
}

int rsApiRotationRateDaySecond(const rsApiInterpolant *interpolant,
                               double dayUtc, double secUtc, double step,
                               double *r, double *rdot)
{
    return rsApiDaySecondEntry(interpolant, dayUtc, secUtc, step, 1, r, rdot);
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
