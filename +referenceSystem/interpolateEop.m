function eopAtEpoch = interpolateEop(eop, epoch, options)
%INTERPOLATEEOP Interpolate an EOP series to a vector of epochs.
%
%   eopAtEpoch = interpolateEop(eop, epoch)
%   eopAtEpoch = interpolateEop(eop, epoch, 'Correction', correction)
%   eopAtEpoch = interpolateEop(eop, epoch, 'Method', "spline")
%
%   Interpolates the series returned by readEop to the UTC epochs given, once
%   for the whole arc, and returns the values in SI with the metadata of the
%   source series intact. UT1 is interpolated in a leap-second-safe way and
%   tagged corrections are applied here rather than by the caller.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   eop     1x1    struct   -      Series from readEop, meta included.
%   epoch   1x1    struct   -      Epoch struct, N entries, scale UTC.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name                 Size  Type      Default   Description
%   ----                 ----  ----      -------   -----------
%   Method               1x1   string    "linear"  "linear" or "spline".
%   ExtrapolationPolicy  1x1   string    "error"   "error", "hold" or "nan".
%   Sigma                1x1   logical   false     Also interpolate the formal
%                                                  errors, for error propagation.
%   Correction           1xK   struct    none      Tagged correction structs
%                                                  from subdailyEopCorrection
%                                                  or zonalTideEopCorrection.
%   Regularize           1x1   logical   false     Permit a correction whose
%                                                  sense is "regularization".
%                                                  See METHOD before setting it.
%
% OUTPUT ARGUMENTS
%   Name                  Size   Type     Units  Description
%   ----                  ----   ----     -----  -----------
%   eopAtEpoch            1x1    struct   -      Values at the epochs.
%   .xp, .yp              Nx1    double   rad    Polar motion.
%   .dut1                 Nx1    double   s      UT1 - UTC.
%   .lod                  Nx1    double   s      Excess length of day.
%   .dX, .dY              Nx1    double   rad    CIP offsets.
%   .sigma                1x1    struct   -      Present only with Sigma=true.
%   .meta                 1x1    struct   -      eop.meta, plus the fields below.
%   .meta.method          1x1    string   -      Interpolation method used.
%   .meta.extrapolationPolicy
%                         1x1    string   -      Policy in force.
%   .meta.nExtrapolated   1x1    double   -      Epochs outside the table.
%   .meta.nPreUtcRowsIgnored
%                         1x1    double   -      Series rows dropped because
%                                                they precede the first row of
%                                                leapSecondTable. See METHOD.
%   .meta.corrections     1xK    string   -      Source of each correction
%                                                applied, "" where none.
%   .meta.regularized     1x1    logical  -      True where a regularization
%                                                correction was applied, so
%                                                dut1 is UT1R - UTC.
%
% METHOD
%   The whole arc is interpolated in one call. Interpolating per epoch is a
%   defect, not a style choice: it turns one sorted lookup into N of them.
%
%   LEAP-SECOND-SAFE UT1, which is handover approximation #4 and the single
%   most likely defect in this layer. UT1 - UTC steps by one second at a leap
%   second, so interpolating it directly smears a fraction of that second
%   across the surrounding days. UT1 - TAI is smooth across the step, so the
%   integer TAI - UTC is removed from the tabulated values before
%   interpolation and the value at the query epoch is added back. This is what
%   the IERS interp.f utility does. v1 did it too, and did it with a hardcoded
%   leap table of its own, frozen at 2017 (finding M-2); the table here is
%   leapSecondTable, which is the only leap-second authority in the toolbox, and
%   the lookup is vectorised rather than an arrayfun per row.
%
%   THE SERIES IS RESTRICTED TO THE MODERN UTC ERA BEFORE ANYTHING IS
%   INTERPOLATED, which is the leap-second argument above taken one step
%   further back. From 1972-01-01 TAI - UTC is an integer, so removing it is a
%   shift and the reconstruction is exact. Before that date UTC ran at its own
%   rate with a fractional offset, which this toolbox does not model, and such
%   rows cannot enter the stencil at all: the published EOP 20 C04 series steps
%   by 0.107873 s of UT1 - UTC between MJD 41316 and 41317 - the last
%   fractional step, not a leap second - and no removal of an integer TAI - UTC
%   makes that continuous.
%
%   WHAT THOSE ROWS COST WAS MEASURED, NOT ASSUMED, over the 111-row fixture
%   that straddles the date. Under "linear" they are invisible away from the
%   boundary - the difference is exactly zero, a linear stencil being two nodes
%   wide - and the whole 0.1079 s, about 50 m at the equator, is smeared only
%   into 1971-12-31 itself. Under "spline" they are never invisible: interp1's
%   spline is a global not-a-knot fit, so fifty pre-1972 rows move dut1 by up
%   to 2.1e-4 s, some 99 mm at the equator, at EVERY epoch of the series, and
%   xp by 0.4 uas. That second case is what decides the design: restricting
%   only the leap-second conversion to a window, and leaving the fit alone,
%   would have left it in place and silent.
%
%   Those rows are therefore dropped once, with one mask for every channel so
%   that dut1 and xp are interpolated from the same table, and the drop is
%   announced with preUtcRowsIgnored and counted in meta.nPreUtcRowsIgnored.
%   The boundary is not a literal here: it is leapSecondTable("validFromDay"),
%   so an override installed with leapSecondTable("load", file) moves it. A
%   series that already begins in the modern era loses no row and its result is
%   bit-identical to what it was before this rule existed.
%
%   A QUERY epoch before that boundary is refused under every
%   ExtrapolationPolicy, with beforeUtcEpoch. The policy governs epochs outside
%   the TABLE, which is a property of the file the caller supplied; this one is
%   outside the MODEL, and no option can relax that. Until this rule existed
%   the whole call failed inside leapSecondTable instead, naming rows the query
%   never used, which is how an epoch in 2020 came to be reported as preceding
%   1972 whenever the series shipped with this toolbox was passed whole.
%
%   THE CORRECTION SENSE CONTRACT, decision D30. Two corrections exist and they
%   are not interchangeable:
%
%     subdailyEopCorrection    sense "additive"        applied by default
%     zonalTideEopCorrection   sense "regularization"  refused by default
%
%   The first supplies signal that a daily series does not contain: the diurnal
%   and semidiurnal ocean tide and libration terms, sampled out by a series
%   tabulated once a day. Adding it is what makes the series usable at
%   sub-daily resolution, which is why it is accepted without ceremony.
%
%   The second is the opposite. A C04 series already contains the zonal tide
%   signal, as observed, so the zonal correction is not missing signal to add
%   but existing signal to remove, and only for a user who specifically wants
%   regularised UT1R. Applying it as though it were additive is a large error
%   in the wrong direction, and it is invisible: the result is a
%   plausible-looking rotation.
%
%   Documentation is not sufficient protection against that, so the correction
%   carries a sense tag that travels with the numbers and cannot be lost the way
%   a comment can, and this function refuses a "regularization" correction
%   unless 'Regularize' is true. The sign, stated because getting it backwards
%   is the whole hazard: with Regularize true the correction is SUBTRACTED, so
%   that dut1 becomes UT1R - UTC, and meta.regularized records that it happened.
%
% ACCURACY
%   Linear interpolation of a daily-tabulated series is the IERS-recommended
%   treatment and is the default here. Its error is the curvature of the
%   underlying signal over one day: about 0.1 mas peak in polar motion, which is
%   3 mm at the Earth's surface, and a few microseconds in UT1. Spline
%   interpolation reduces the curvature error but overshoots near gaps and
%   series edges, which is why it is offered and not defaulted.
%
%   That figure is the error of the interpolation, not of the series. The
%   sub-daily signal that a daily series cannot carry at all is larger, up to
%   about 0.5 mas in polar motion and 50 microseconds in UT1, and is supplied by
%   subdailyEopCorrection rather than by any choice of interpolation method.
%
%   The leap-second treatment is exact, not approximate: TAI - UTC is an integer
%   number of seconds from 1972 onward and removing it is a shift, so UT1 - TAI
%   is interpolated with no step and the reconstruction adds back an integer.
%
%   That exactness is what the 1972-01-01 restriction protects. UT1 - UTC steps
%   across that date by an amount that is not an integer, so no removal of
%   TAI - UTC makes it continuous, and the rows before it are dropped rather
%   than interpolated through; METHOD carries the measured size of what they
%   would otherwise contribute under each method. Dropping them costs nothing
%   at any epoch this toolbox can work with, because UT1 - UTC there is not
%   representable in the first place.
%
%   Applying zonalTideEopCorrection to an unregularised series, or applying it
%   with the wrong sign, costs up to 168 ms of UT1 for the full 62-term model
%   and about 2.1 ms for its short-period part alone. Both measured in session
%   S2 over one 18.6-year nodal period. At the equator 1 ms of UT1 is 0.465 m of
%   surface displacement, so these are metre-level and tens-of-metre-level
%   errors, not the millimetre-level ones the handover previously stated. This
%   is why the flag exists.
%
%   Extrapolation is not performed under any policy. "hold" clamps to the edge
%   value, which is a statement that nothing is known beyond the table rather
%   than a prediction; "nan" marks the epochs; "error" refuses. Polynomial
%   extrapolation of an EOP series is never appropriate and is not offered.
%
% ERRORS
%   referenceSystem:interpolateEop:wrongScale
%   referenceSystem:interpolateEop:outOfRange
%   referenceSystem:interpolateEop:beforeUtcEpoch
%   referenceSystem:interpolateEop:tooFewUsableRows
%   referenceSystem:interpolateEop:wrongCorrectionSense
%   referenceSystem:interpolateEop:missingMeta
%   referenceSystem:interpolateEop:sizeMismatch
%
% WARNINGS
%   referenceSystem:interpolateEop:extrapolatedEop   One per call, however
%       large N is. Raised only under 'ExtrapolationPolicy' "hold", naming how
%       many epochs were clamped to an edge value of the table.
%   referenceSystem:interpolateEop:preUtcRowsIgnored   One per call. Raised
%       when the series reaches back before the first row of leapSecondTable,
%       naming how many rows were dropped and what remains. See METHOD.
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.5.
%   IERS EOP Product Centre, interp.f, the reference interpolation utility.
%
% EXAMPLE
%   eop = referenceSystem.readEop("eopc04_20.1962-now");
%   utc = referenceSystem.daySecondToEpoch([57754*ones(86400,1) (0:86399)'], "UTC");
%   subdaily = referenceSystem.subdailyEopCorrection(utc);
%   e = referenceSystem.interpolateEop(eop, utc, 'Correction', subdaily);
%
% KEYWORDS
%   EOP, interpolation, UT1, leap second, polar motion, regularization
%
% See also READEOP, SUBDAILYEOPCORRECTION, ZONALTIDEEOPCORRECTION, LEAPSECONDTABLE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 11:55 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        eop (1,1) struct
        epoch (1,1) struct
        options.Method (1,1) string {mustBeMember(options.Method, ...
            ["linear", "spline"])} = "linear"
        options.ExtrapolationPolicy (1,1) string ...
            {mustBeMember(options.ExtrapolationPolicy, ...
            ["error", "hold", "nan"])} = "error"
        options.Sigma (1,1) logical = false
        options.Correction struct = struct([])
        options.Regularize (1,1) logical = false
    end

    if ~isfield(eop, 'meta') || ~isfield(eop.meta, 'series')
        error('referenceSystem:interpolateEop:missingMeta', ...
            ['The eop struct has no meta substruct. Metadata travels with ', ...
            'the data in this toolbox: cipModel reaches cipCoordinates ', ...
            'through it, and dropping it is finding C-2 reintroduced. Build ', ...
            'the series with readEop.']);
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "UTC"
        error('referenceSystem:interpolateEop:wrongScale', ...
            ['An EOP series is tabulated against UTC and this epoch is %s. ', ...
            'Convert it deliberately with convertTimeScale; converting it ', ...
            'here would hide which scale indexed the table.'], epoch.scale);
    end

    queryMjd = epoch.day + epoch.sec / referenceSystem.iersConstants().secondsPerDay;

    % THE BOUNDARY OF THE MODERN UTC ERA IS READ FROM THE LEAP-SECOND TABLE
    % AND IS NOT A LITERAL HERE, so a session override installed with
    % leapSecondTable("load", file) moves it. Rev. 1.215 took the first row of
    % the "list" timetable apart to get this; rev. 1.216 asks for the bound by
    % name, in both the form that is compared and the form that is printed.
    firstUtcDay = referenceSystem.leapSecondTable("validFromDay");
    firstUtcDate = referenceSystem.leapSecondTable("validFrom");

    localRefuseQueryBeforeUtcEpoch(queryMjd, firstUtcDay, firstUtcDate, eop.mjd);
    [eop, nPreUtcRowsIgnored] = localTrimToUtcEpoch(eop, firstUtcDay, ...
        firstUtcDate, eop.meta.series);

    tableMjd = eop.mjd;

    [queryMjd, isOutside, nOutside] = localApplyPolicy(queryMjd, tableMjd, ...
        options.ExtrapolationPolicy);

    method = char(options.Method);
    eopAtEpoch = struct( ...
        'xp', interp1(tableMjd, eop.xp, queryMjd, method), ...
        'yp', interp1(tableMjd, eop.yp, queryMjd, method), ...
        'dut1', localInterpolateDut1(tableMjd, eop.dut1, queryMjd, method), ...
        'lod', interp1(tableMjd, eop.lod, queryMjd, method), ...
        'dX', interp1(tableMjd, eop.dX, queryMjd, method), ...
        'dY', interp1(tableMjd, eop.dY, queryMjd, method));

    if options.Sigma
        eopAtEpoch.sigma = struct();
        for name = ["xp", "yp", "dut1", "lod", "dX", "dY"]
            eopAtEpoch.sigma.(name) = interp1(tableMjd, eop.sigma.(name), ...
                queryMjd, method);
        end
    end

    if any(isOutside)
        for name = ["xp", "yp", "dut1", "lod", "dX", "dY"]
            eopAtEpoch.(name)(isOutside) = NaN;
        end
    end

    [eopAtEpoch, correctionSource, regularized] = localApplyCorrections( ...
        eopAtEpoch, options.Correction, options.Regularize, eop.meta.series, ...
        numel(queryMjd));

    eopAtEpoch.meta = eop.meta;
    eopAtEpoch.meta.method = options.Method;
    eopAtEpoch.meta.extrapolationPolicy = options.ExtrapolationPolicy;
    eopAtEpoch.meta.nExtrapolated = nOutside;
    eopAtEpoch.meta.nPreUtcRowsIgnored = nPreUtcRowsIgnored;
    eopAtEpoch.meta.corrections = correctionSource;
    eopAtEpoch.meta.regularized = regularized;
end

% =========================== local functions ===========================

function localRefuseQueryBeforeUtcEpoch(queryMjd, firstUtcDay, firstUtcDate, tableMjd)
%LOCALREFUSEQUERYBEFOREUTCEPOCH Refuse an epoch the toolbox cannot represent.
%   The extrapolation policy governs epochs outside the TABLE, which is a
%   property of the file the caller supplied. This one is outside the MODEL, so
%   no policy relaxes it and the refusal is unconditional. It is raised here,
%   under this function's own identifier, rather than left to leapSecondTable:
%   a caller who asked for 2020 must not read that their epoch precedes 1972.

    tooEarly = queryMjd < firstUtcDay;
    if ~any(tooEarly)
        return
    end

    first = find(tooEarly, 1);
    error('referenceSystem:interpolateEop:beforeUtcEpoch', ...
        ['%d of %d query epochs precede %s (MJD %d), where UTC is a ', ...
        'rate-based fractional offset that this toolbox does not model; ', ...
        'index %d is the first, at MJD %.6f. That is a limit of the ', ...
        'toolbox and not of the series, which spans MJD %.2f to %.2f, so ', ...
        'no ExtrapolationPolicy relaxes it.'], ...
        sum(tooEarly), numel(tooEarly), string(firstUtcDate, 'yyyy-MM-dd'), ...
        firstUtcDay, first, queryMjd(first), tableMjd(1), tableMjd(end));
end

function [eop, nIgnored] = localTrimToUtcEpoch(eop, firstUtcDay, firstUtcDate, seriesName)
%LOCALTRIMTOUTCEPOCH Drop the rows that precede the modern UTC era, once.
%   ONE MASK FOR EVERY CHANNEL, so that dut1 and xp are interpolated from the
%   same rows. Cutting only the channel that needs it would give one result two
%   tables, and under "spline" - a global fit rather than a local stencil - two
%   different fits as well.
%
%   The early return is what makes the rule free: a series that already begins
%   in the modern era is not copied, not masked and not announced, so its
%   result is bit-identical to what it was before this function existed.

    keep = eop.mjd >= firstUtcDay;
    nIgnored = sum(~keep);
    if nIgnored == 0
        return
    end

    nKept = sum(keep);
    if nKept < 2
        error('referenceSystem:interpolateEop:tooFewUsableRows', ...
            ['The %s series holds %d rows of which %d are at or after %s ', ...
            '(MJD %d), fewer than the two an interpolation needs. UTC ', ...
            'before that date is a rate-based fractional offset that this ', ...
            'toolbox does not model, so the earlier rows cannot be used.'], ...
            seriesName, numel(keep), nKept, ...
            string(firstUtcDate, 'yyyy-MM-dd'), firstUtcDay);
    end

    for name = ["mjd", "xp", "yp", "dut1", "lod", "dX", "dY"]
        eop.(name) = eop.(name)(keep);
    end
    if isfield(eop, 'sigma')
        for name = string(fieldnames(eop.sigma))'
            eop.sigma.(name) = eop.sigma.(name)(keep);
        end
    end

    warning('referenceSystem:interpolateEop:preUtcRowsIgnored', ...
        ['%d of %d rows of the %s series precede %s (MJD %d) and were ', ...
        'ignored. UTC before that date is a rate-based fractional offset ', ...
        'that this toolbox does not model, so those rows cannot enter a ', ...
        'leap-second-safe UT1 interpolation. The %d rows that remain span ', ...
        'MJD %.2f to %.2f.'], ...
        nIgnored, numel(keep), seriesName, ...
        string(firstUtcDate, 'yyyy-MM-dd'), firstUtcDay, ...
        nKept, eop.mjd(1), eop.mjd(end));
end

function dut1 = localInterpolateDut1(tableMjd, tableDut1, queryMjd, method)
%LOCALINTERPOLATEDUT1 Interpolate UT1 - UTC across leap seconds without a step.
%   UT1 - TAI is continuous where UT1 - UTC is not, so the integer TAI - UTC is
%   removed before interpolating and added back afterwards. Both lookups are
%   vectorised; v1 called arrayfun once per table row and once per epoch.
%
%   NEITHER LOOKUP NEEDS A RANGE GUARD AND ONE MUST NOT BE ADDED HERE. The
%   caller has already refused a query before the modern UTC era and trimmed
%   the table to it, so every row and every epoch reaching this function is
%   inside leapSecondTable's domain by construction. A guard here would be a
%   second answer to the same question and would eventually give a different
%   one.

    tableEpoch = referenceSystem.daySecondToEpoch( ...
        [floor(tableMjd), (tableMjd - floor(tableMjd)) * 86400], "UTC");
    queryEpoch = referenceSystem.daySecondToEpoch( ...
        [floor(queryMjd), (queryMjd - floor(queryMjd)) * 86400], "UTC");

    tableDeltaAt = referenceSystem.leapSecondTable("deltaAT", tableEpoch);
    queryDeltaAt = referenceSystem.leapSecondTable("deltaAT", queryEpoch);

    ut1MinusTai = tableDut1 - tableDeltaAt;
    dut1 = interp1(tableMjd, ut1MinusTai, queryMjd, method) + queryDeltaAt;
end

function [queryMjd, isOutside, nOutside] = localApplyPolicy(queryMjd, tableMjd, policy)
%LOCALAPPLYPOLICY Enforce the extrapolation policy, one warning for the arc.

    lo = tableMjd(1);
    hi = tableMjd(end);
    isOutside = queryMjd < lo | queryMjd > hi;
    nOutside = sum(isOutside);

    if nOutside == 0
        isOutside = false(size(queryMjd));
        return
    end

    switch policy
        case "error"
            first = find(isOutside, 1);
            error('referenceSystem:interpolateEop:outOfRange', ...
                ['%d of %d epochs fall outside the EOP table range ', ...
                '[%.2f, %.2f]; the first is MJD %.6f. Extend the series, or ', ...
                'pass ''ExtrapolationPolicy'' as "hold" to clamp to the edge ', ...
                'value or "nan" to mark them.'], nOutside, numel(queryMjd), ...
                lo, hi, queryMjd(first));
        case "hold"
            warning('referenceSystem:interpolateEop:extrapolatedEop', ...
                ['%d of %d epochs fall outside the EOP table range ', ...
                '[%.2f, %.2f] and were clamped to the nearest edge value. ', ...
                'The clamp is a statement that nothing is known beyond the ', ...
                'table, not a prediction.'], nOutside, numel(queryMjd), lo, hi);
            queryMjd = min(max(queryMjd, lo), hi);
            isOutside = false(size(queryMjd));
        case "nan"
            queryMjd = min(max(queryMjd, lo), hi);
    end
end

function [eopAtEpoch, source, regularized] = localApplyCorrections(eopAtEpoch, ...
    correction, allowRegularization, seriesName, epochCount)
%LOCALAPPLYCORRECTIONS The D30 sense contract, enforced at the consumer.

    source = strings(1, 0);
    regularized = false;

    if isempty(correction)
        return
    end

    for k = 1:numel(correction)
        item = correction(k);
        if ~isfield(item, 'sense')
            error('referenceSystem:interpolateEop:wrongCorrectionSense', ...
                ['Correction %d carries no sense field. Every correction in ', ...
                'this toolbox states what its numbers are for, so that an ', ...
                'additive term and a regularization term cannot be ', ...
                'confused. Build it with subdailyEopCorrection or ', ...
                'zonalTideEopCorrection.'], k);
        end

        switch item.sense
            case "additive"
                sign = 1;
            case "regularization"
                if ~allowRegularization
                    error('referenceSystem:interpolateEop:wrongCorrectionSense', ...
                        ['Correction %d has sense "regularization" and ', ...
                        '''Regularize'' is false, so it was refused.\n', ...
                        'The %s series already contains the zonal tide ', ...
                        'signal as observed. This correction removes it, ', ...
                        'giving regularised UT1R; it is not missing signal ', ...
                        'to add. Applying it here without meaning to costs ', ...
                        'up to 168 ms of UT1, which is 78 m at the equator.\n', ...
                        'Pass ''Regularize'', true if you genuinely want ', ...
                        'UT1R - UTC in the dut1 field, and note that ', ...
                        'everything downstream then works in UT1R.'], ...
                        k, seriesName);
                end
                sign = -1;
                regularized = true;
            otherwise
                error('referenceSystem:interpolateEop:wrongCorrectionSense', ...
                    ['Correction %d has sense "%s", which is not a sense ', ...
                    'this function knows. The two defined values are ', ...
                    '"additive" and "regularization".'], k, item.sense);
        end

        for name = ["dxp", "dyp", "dut1", "dlod"]
            [target, present] = localTargetField(name, item);
            if ~present
                continue
            end
            value = item.(name);
            if numel(value) ~= epochCount
                error('referenceSystem:interpolateEop:sizeMismatch', ...
                    ['Correction %d holds %d values of %s for %d epochs. ', ...
                    'A correction must be evaluated at the same epochs as ', ...
                    'the interpolation.'], k, numel(value), name, epochCount);
            end
            eopAtEpoch.(target) = eopAtEpoch.(target) + sign * value(:);
        end
        source(end+1) = item.source; %#ok<AGROW> loop runs over a handful of corrections
    end
end

function [target, present] = localTargetField(name, item)
%LOCALTARGETFIELD Which eop field a correction field adds to.

    map = struct('dxp', 'xp', 'dyp', 'yp', 'dut1', 'dut1', 'dlod', 'lod');
    target = map.(name);
    present = isfield(item, name);
end
