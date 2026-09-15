function eopAtEpoch = interpolateEop(eop, epoch, options)
%INTERPOLATEEOP Interpolate an EOP series to a vector of epochs.
%
%   eopAtEpoch = interpolateEop(eop, epoch)
%   eopAtEpoch = interpolateEop(eop, epoch, 'Correction', correction)
%   eopAtEpoch = interpolateEop(eop, epoch, 'Method', "linear")
%
%   Interpolates the series returned by readEop to the UTC epochs given, once
%   for the whole arc, and returns the values in SI with the metadata of the
%   source series intact. UT1 is interpolated across leap seconds without a
%   step, the zonal tides are removed before interpolating and restored
%   afterwards, and tagged corrections are applied here rather than by the
%   caller.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   eop     1x1    struct   -      Series from readEop, meta included.
%   epoch   1x1    struct   -      Epoch struct, N entries, scale UTC.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name                 Size  Type      Default     Description
%   ----                 ----  ----      -------     -----------
%   Method               1x1   string    "lagrange"  "lagrange" (4-point, as
%                                                    IERS interp.f), "linear"
%                                                    or "spline".
%   ZonalTides           1x1   string    "restore"   "restore" removes the
%                                                    RG_ZONT2 zonal tides from
%                                                    dut1 and lod before
%                                                    interpolating and adds
%                                                    them back at the epoch;
%                                                    "interpolate" interpolates
%                                                    the series as published.
%   ExtrapolationPolicy  1x1   string    "error"     "error", "hold" or "nan".
%   Sigma                1x1   logical   false       Also interpolate the formal
%                                                    errors, for error
%                                                    propagation.
%   Correction           1xK   struct    none        Tagged correction structs
%                                                    from subdailyEopCorrection
%                                                    or zonalTideEopCorrection.
%   Regularize           1x1   logical   false       Permit a correction whose
%                                                    sense is "regularization".
%                                                    See METHOD before setting
%                                                    it.
%
% OUTPUT ARGUMENTS
%   Name                  Size   Type     Units  Description
%   ----                  ----   ----     -----  -----------
%   eopAtEpoch            1x1    struct   -      Values at the epochs.
%   .xp, .yp              Nx1    double   rad    Polar motion.
%   .dut1                 Nx1    double   s      UT1 - UTC.
%   .lod                  Nx1    double   s      Excess length of day. NaN
%                                                where the series publishes
%                                                none; see METHOD.
%   .dX, .dY              Nx1    double   rad    CIP offsets.
%   .sigma                1x1    struct   -      Present only with Sigma=true.
%   .meta                 1x1    struct   -      eop.meta, plus the fields below.
%   .meta.method          1x1    string   -      Interpolation method used.
%   .meta.zonalTides      1x1    string   -      The ZonalTides setting used.
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
%   The whole arc is interpolated in one call. "lagrange" and "linear" are
%   local stencils, so only the table rows they touch are converted and
%   corrected, and the cost does not grow with the length of the series.
%   "spline" is interp1's global not-a-knot fit over the whole table.
%
%   FOUR-POINT LAGRANGE IS THE DEFAULT, as in the IERS interpolation utility
%   interp.f: for an epoch between rows k and k+1 the cubic through rows k-1
%   to k+2 is evaluated, the stencil being shifted inwards at the first and
%   last interval. It needs at least four usable rows.
%
%   LEAP-SECOND-SAFE UT1. UT1 - UTC steps by one second at a leap second,
%   while UT1 - TAI is smooth. The integer TAI - UTC of each row's own UTC day
%   is removed before interpolation and the TAI - UTC of the epoch's own UTC
%   day is added back, so UT1 = UTC + dut1 is continuous through 23:59:60,
%   where the epoch keeps its day number.
%
%   ZONAL TIDES ARE REMOVED, INTERPOLATED ACROSS AND RESTORED (default). A
%   daily series of UT1 carries the fortnightly and monthly zonal tides,
%   whose curvature over one day is what dominates the interpolation error.
%   With ZonalTides "restore" the RG_ZONT2 effect on UT1 and on the length of
%   day is subtracted at the rows, the regularised residual is interpolated,
%   and the effect is added back at the epoch, evaluated on TT. The output is
%   still UT1 - UTC and the excess length of day, not UT1R: this is an
%   interpolation technique, not a correction, and meta.regularized stays
%   false. Polar motion and the CIP offsets are unaffected.
%
%   THE SERIES IS RESTRICTED TO THE MODERN UTC ERA before anything is
%   interpolated. From 1972-01-01 TAI - UTC is an integer; before it UTC ran at
%   its own rate with a fractional offset that this toolbox does not model, and
%   EOP 20 C04 steps by 0.107873 s of UT1 - UTC between MJD 41316 and 41317.
%   Such rows are dropped with one mask for every channel, announced with
%   preUtcRowsIgnored and counted in meta.nPreUtcRowsIgnored. The boundary is
%   leapSecondTable("validFromDay"), so an override moves it. A query epoch
%   before it is refused under every ExtrapolationPolicy with beforeUtcEpoch:
%   the policy governs epochs outside the table, and this one is outside the
%   model.
%
%   MISSING VALUES ARE REFUSED WHERE THEY WOULD REACH A FRAME. A published
%   series can leave fields blank - finals2000A's predictions carry no dX and
%   dY beyond a few weeks and no length of day at all. An interpolated xp, yp,
%   dut1, dX or dY that is not finite at an epoch inside the table is refused
%   with missingValue, naming the channel and the last row that publishes it.
%   lod and the formal errors are returned as NaN where the series has none,
%   because nothing in the toolbox computes with them.
%
%   THE CORRECTION SENSE CONTRACT. Two corrections exist and they are not
%   interchangeable:
%
%     subdailyEopCorrection    sense "additive"        applied by default
%     zonalTideEopCorrection   sense "regularization"  refused by default
%
%   The first supplies the diurnal and semidiurnal signal a daily series does
%   not contain and is added. The second removes signal the series does
%   contain, turning UT1 into UT1R; it is refused unless 'Regularize' is true,
%   and then it is SUBTRACTED and meta.regularized is set.
%
% ACCURACY
%   Interpolation error on UT1, measured on the RG_ZONT2 signal itself over
%   2020 from daily rows against hourly evaluations: linear 35.7 us (16.6 mm
%   at the equator), 4-point Lagrange 1.95 us, and zero with ZonalTides
%   "restore", which removes that signal before any stencil sees it. What
%   remains is the curvature of the regularised series over one day.
%
%   The sub-daily ocean tide and libration signal, up to about 0.5 mas in
%   polar motion and 50 us in UT1, is not an interpolation error; it is
%   supplied by subdailyEopCorrection.
%
%   The leap-second treatment is exact: TAI - UTC is an integer from 1972 on,
%   so removing and restoring it is a shift.
%
%   Applying zonalTideEopCorrection as a correction to an unregularised series
%   without meaning to costs up to 168 ms of UT1 for the full 62-term model,
%   78 m at the equator; this is why 'Regularize' exists.
%
%   Extrapolation is not performed under any policy. "hold" clamps to the edge
%   value, "nan" marks the epochs and "error" refuses.
%
% ERRORS
%   referenceSystem:interpolateEop:wrongScale
%   referenceSystem:interpolateEop:outOfRange
%   referenceSystem:interpolateEop:beforeUtcEpoch
%   referenceSystem:interpolateEop:tooFewUsableRows
%   referenceSystem:interpolateEop:missingValue
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
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.5 and Ch. 8.1.
%   IERS EOP Product Centre, interp.f (LAGINT), the reference interpolation
%     utility.
%
% EXAMPLE
%   eop = referenceSystem.readEop("eopc04_20.1962-now");
%   utc = referenceSystem.daySecondToEpoch([57754*ones(86400,1) (0:86399)'], "UTC");
%   subdaily = referenceSystem.subdailyEopCorrection(utc);
%   e = referenceSystem.interpolateEop(eop, utc, 'Correction', subdaily);
%
% KEYWORDS
%   EOP, interpolation, Lagrange, UT1, leap second, zonal tides, polar motion
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
            ["lagrange", "linear", "spline"])} = "lagrange"
        options.ZonalTides (1,1) string {mustBeMember(options.ZonalTides, ...
            ["restore", "interpolate"])} = "restore"
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
            'through it. Build the series with readEop.']);
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "UTC"
        error('referenceSystem:interpolateEop:wrongScale', ...
            ['An EOP series is tabulated against UTC and this epoch is %s. ', ...
            'Convert it deliberately with convertTimeScale; converting it ', ...
            'here would hide which scale indexed the table.'], epoch.scale);
    end

    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    queryMjd = epoch.day + epoch.sec / secondsPerDay;

    firstUtcDay = referenceSystem.leapSecondTable("validFromDay");
    firstUtcDate = referenceSystem.leapSecondTable("validFrom");

    localRefuseQueryBeforeUtcEpoch(queryMjd, firstUtcDay, firstUtcDate, eop.mjd);
    [eop, nPreUtcRowsIgnored] = localTrimToUtcEpoch(eop, firstUtcDay, ...
        firstUtcDate, eop.meta.series);

    method = options.Method;
    localRequireRows(numel(eop.mjd), method, eop.meta.series);
    tableMjd = eop.mjd;

    unclampedMjd = queryMjd;
    [queryMjd, isOutside, nOutside] = localApplyPolicy(queryMjd, tableMjd, ...
        options.ExtrapolationPolicy);

    % The epoch's own UTC day labels TAI - UTC and the zonal-tide epoch; only a
    % clamped epoch takes the day and second of its clamp, so "hold" returns
    % the edge row.
    queryDay = epoch.day;
    querySecond = epoch.sec;
    clamped = queryMjd ~= unclampedMjd;
    queryDay(clamped) = floor(queryMjd(clamped));
    querySecond(clamped) = (queryMjd(clamped) - queryDay(clamped))*secondsPerDay;
    queryEpoch = referenceSystem.daySecondToEpoch([queryDay, querySecond], "UTC");

    % The rows each epoch's stencil reads, and the rows any stencil reads. The
    % spline is global and reads every row, so it has no per-epoch stencil.
    stencil = localStencil(tableMjd, queryMjd, method);
    if isempty(stencil)
        used = (1:numel(tableMjd))';
    else
        used = unique(stencil(:));
    end
    tableEpoch = referenceSystem.daySecondToEpoch([floor(tableMjd(used)), ...
        (tableMjd(used) - floor(tableMjd(used)))*secondsPerDay], "UTC");

    % UT1 - TAI and the excess length of day, regularised where requested.
    ut1MinusTai = nan(size(tableMjd));
    ut1MinusTai(used) = eop.dut1(used) - ...
        referenceSystem.leapSecondTable("deltaAT", tableEpoch);
    lengthOfDay = nan(size(tableMjd));
    lengthOfDay(used) = eop.lod(used);
    restoreZonal = options.ZonalTides == "restore";
    if restoreZonal
        rowTide = localZonalTide(tableEpoch);
        ut1MinusTai(used) = ut1MinusTai(used) - rowTide.dut1;
        lengthOfDay(used) = lengthOfDay(used) - rowTide.dlod;
    end

    interpolate = @(value) localInterpolate(tableMjd, value, queryMjd, ...
        stencil, method);
    eopAtEpoch = struct( ...
        'xp', interpolate(eop.xp), ...
        'yp', interpolate(eop.yp), ...
        'dut1', interpolate(ut1MinusTai) + ...
            referenceSystem.leapSecondTable("deltaAT", queryEpoch), ...
        'lod', interpolate(lengthOfDay), ...
        'dX', interpolate(eop.dX), ...
        'dY', interpolate(eop.dY));
    if restoreZonal
        queryTide = localZonalTide(queryEpoch);
        eopAtEpoch.dut1 = eopAtEpoch.dut1 + queryTide.dut1;
        eopAtEpoch.lod = eopAtEpoch.lod + queryTide.dlod;
    end

    % The spline skips a missing row rather than propagating it, so its epochs
    % are checked against the two rows that bracket them.
    checkStencil = stencil;
    if isempty(checkStencil)
        checkStencil = localStencil(tableMjd, queryMjd, "linear");
    end
    localRefuseMissingValues(eopAtEpoch, eop, isOutside, queryMjd, ...
        checkStencil, method, eop.meta.series);

    if options.Sigma
        eopAtEpoch.sigma = struct();
        for name = ["xp", "yp", "dut1", "lod", "dX", "dY"]
            eopAtEpoch.sigma.(name) = interpolate(eop.sigma.(name));
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
    eopAtEpoch.meta.method = method;
    eopAtEpoch.meta.zonalTides = options.ZonalTides;
    eopAtEpoch.meta.extrapolationPolicy = options.ExtrapolationPolicy;
    eopAtEpoch.meta.nExtrapolated = nOutside;
    eopAtEpoch.meta.nPreUtcRowsIgnored = nPreUtcRowsIgnored;
    eopAtEpoch.meta.corrections = correctionSource;
    eopAtEpoch.meta.regularized = regularized;
end

% =========================== local functions ===========================

function localRefuseQueryBeforeUtcEpoch(queryMjd, firstUtcDay, firstUtcDate, tableMjd)
%LOCALREFUSEQUERYBEFOREUTCEPOCH Refuse an epoch the toolbox cannot represent.
%   The extrapolation policy governs epochs outside the TABLE; this one is
%   outside the MODEL, so no policy relaxes it.

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
%   One mask for every channel, so that dut1 and xp are interpolated from the
%   same rows. A series that already begins in the modern era is returned
%   untouched and nothing is announced.

    keep = eop.mjd >= firstUtcDay;
    nIgnored = sum(~keep);
    if nIgnored == 0
        return
    end

    nKept = sum(keep);
    if nKept < 2
        error('referenceSystem:interpolateEop:tooFewUsableRows', ...
            ['The %s series holds %d rows of which %d are at or after %s ', ...
            '(MJD %d), fewer than an interpolation needs. UTC before that ', ...
            'date is a rate-based fractional offset that this toolbox does ', ...
            'not model, so the earlier rows cannot be used.'], ...
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

function localRequireRows(rowCount, method, seriesName)
%LOCALREQUIREROWS The rows a method's stencil needs: four for Lagrange, two
%   otherwise.

    needed = 2;
    if method == "lagrange"
        needed = 4;
    end
    if rowCount < needed
        error('referenceSystem:interpolateEop:tooFewUsableRows', ...
            ['The %s series holds %d usable rows and Method "%s" needs at ', ...
            'least %d.'], seriesName, rowCount, method, needed);
    end
end

function stencil = localStencil(tableMjd, queryMjd, method)
%LOCALSTENCIL Table rows each query reads, one row per query.
%   "lagrange" reads four rows, k-1 to k+2 for an epoch between rows k and
%   k+1, shifted inwards at the edges; "linear" reads k and k+1; "spline" is
%   global and returns an empty stencil. queryMjd lies inside the table here,
%   clamped by the policy where it did not.

    rowCount = numel(tableMjd);
    if method == "spline"
        stencil = zeros(numel(queryMjd), 0);
        return
    end

    interval = discretize(queryMjd, tableMjd);
    % An epoch marked for NaN by the policy has been clamped, so it has an
    % interval; discretize returns NaN only for a non-finite epoch.
    interval(isnan(interval)) = 1;
    if method == "linear"
        stencil = interval + [0, 1];
    else
        first = min(max(interval - 1, 1), rowCount - 3);
        stencil = first + (0:3);
    end
end

function value = localInterpolate(tableMjd, tableValue, queryMjd, stencil, method)
%LOCALINTERPOLATE One channel at the query epochs.
%   Each epoch is evaluated from its own stencil with no reduction across
%   epochs, so an arc and a loop over its epochs agree bit for bit.

    if method == "spline"
        % Rows without a value are left out of the fit here, as interp1 would
        % leave them out with a warning of its own; the caller refuses an
        % epoch they bracket, and a channel with fewer than two values is
        % returned as NaN.
        finite = isfinite(tableValue);
        if sum(finite) < 2
            value = nan(size(queryMjd));
            return
        end
        value = interp1(tableMjd(finite), tableValue(finite), queryMjd, 'spline');
        return
    end

    x = reshape(tableMjd(stencil), size(stencil));
    y = reshape(tableValue(stencil), size(stencil));
    q = queryMjd(:);
    if method == "linear"
        fraction = (q - x(:, 1)) ./ (x(:, 2) - x(:, 1));
        value = y(:, 1) + fraction .* (y(:, 2) - y(:, 1));
        return
    end

    value = zeros(numel(q), 1);
    for a = 1:4
        weight = ones(numel(q), 1);
        for b = [1:a-1, a+1:4]
            weight = weight .* (q - x(:, b)) ./ (x(:, a) - x(:, b));
        end
        value = value + weight .* y(:, a);
    end
end

function tide = localZonalTide(utc)
%LOCALZONALTIDE The RG_ZONT2 effect on UT1 and the length of day at UTC epochs.
%   The model is defined on TT; the epoch is converted rather than substituted.

    tide = referenceSystem.zonalTideEopCorrection( ...
        referenceSystem.convertTimeScale(utc, "TT"));
end

function localRefuseMissingValues(eopAtEpoch, eop, isOutside, queryMjd, ...
        stencil, method, seriesName)
%LOCALREFUSEMISSINGVALUES A frame quantity that is not finite inside the table.
%   stencil holds the rows each epoch read, or for the spline the two rows
%   that bracket it.

    for name = ["xp", "yp", "dut1", "dX", "dY"]
        rowValue = eop.(name);
        missing = (~isfinite(eopAtEpoch.(name)) | ...
            any(~isfinite(reshape(rowValue(stencil), size(stencil))), 2)) & ~isOutside;
        if ~any(missing)
            continue
        end
        first = find(missing, 1);
        published = find(isfinite(rowValue), 1, 'last');
        if isempty(published)
            publishedText = "publishes no " + name + " at all";
        else
            publishedText = sprintf('publishes %s through MJD %.2f', name, ...
                eop.mjd(published));
        end
        rows = [min(stencil(first, :)), max(stencil(first, :))];
        error('referenceSystem:interpolateEop:missingValue', ...
            ['%d of %d epochs have no %s: the %s series %s, and the %s ', ...
            'stencil of the first, MJD %.6f, reads rows MJD %.2f to %.2f. ', ...
            'A frame built from a missing value is not a frame. Shorten the ', ...
            'arc, or use a series that carries %s there.'], ...
            sum(missing), numel(missing), name, seriesName, publishedText, ...
            method, queryMjd(first), eop.mjd(rows(1)), eop.mjd(rows(2)), name);
    end
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
