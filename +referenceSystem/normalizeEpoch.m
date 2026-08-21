function epochOut = normalizeEpoch(epochIn)
%NORMALIZEEPOCH Validate an epoch struct and put it in canonical form.
%
%   epochOut = normalizeEpoch(epochIn) checks that epochIn is a well formed
%   epoch as defined in handover section B.3, returns its fields as Nx1 double
%   columns, forces day to an integer day number and folds sec into the
%   half-open interval [0, 86400) - or [0, 86401) on a UTC day that ends in a
%   positive leap second.
%
%   Every L0 to L2 function calls this on entry, so an epoch that reaches any
%   arithmetic has already been validated exactly once, in one place.
%
% INPUT ARGUMENTS
%   Name          Size   Type            Units  Description
%   ----          ----   ----            -----  -----------
%   epochIn       1x1    struct          -      Epoch struct, fields below.
%   .day          Nx1    double          d      Day number, MJD at 0h of the
%                                               scale. Scalar is broadcast.
%   .sec          Nx1    double          s      Seconds since 0h of that day.
%                                               Scalar is broadcast.
%   .scale        1x1    string | char   -      Time scale, any case, one of
%                                               the names in timeScale.
%   .source       1x1    string | char   -      Provenance, free text.
%                                               Optional on input.
%
% OUTPUT ARGUMENTS
%   Name          Size   Type      Units  Description
%   ----          ----   ----      -----  -----------
%   epochOut      1x1    struct    -      Canonical epoch.
%   .day          Nx1    double    d      Integer day number.
%   .sec          Nx1    double    s      Seconds of day, [0, 86400), or
%                                         [0, 86401) on a positive leap-second
%                                         day in UTC.
%   .scale        1x1    string    -      Canonical upper-case scale name.
%   .source       1x1    string    -      Provenance, unchanged or "unspecified".
%
% METHOD
%   The split day-and-second form is the reason this toolbox holds sub-
%   microsecond resolution over decades: a decimal MJD near 60000 resolves only
%   about 0.6 us in double precision, which is coarser than a GRACE KBR sample.
%   Normalisation therefore never round-trips through a decimal MJD.
%
%   THE CARRY IS DELEGATED, THE VALIDATION IS NOT. Since prompt P28b this
%   function validates and then calls the package-private carryEpoch, which is
%   the single implementation of the carry in the toolbox. convertTimeScale
%   reaches the same function directly for epochs it has just built from one it
%   already normalised, and that is the whole difference between the two paths.
%   The description below is of what carryEpoch does and is kept here because
%   this is the entry a caller uses.
%
%   For a uniform scale the carry is exact and unconditional:
%   carry = floor(sec/86400), sec = sec - 86400*carry, day = day + carry. A
%   fractional part of day is folded into sec by the same relation before the
%   carry, which is exact because a day of a uniform scale is 86400 s long.
%
%   UTC is different, and this is finding C-3. A UTC day that ends in a
%   positive leap second is 86401 s long, so the plain carry would turn
%   23:59:60.5 into 00:00:00.5 of the next day, a different instant one second
%   later, silently. The UTC branch therefore asks leapSecondTable for the length
%   of the day before carrying, and iterates at most twice - which is why the
%   input range is restricted, see ERRORS. For the same reason a non-integer
%   day is rejected rather than folded in UTC: the fold would assume an 86400 s
%   day.
%
%   GLONASS is UTC advanced by three hours, so a leap second falls at 03:00:00
%   in the middle of a GLONASS day rather than at its end, and the leap second
%   itself has no distinct representation in the day-and-second form. GLONASS
%   is therefore normalised as a uniform scale here, and convertTimeScale
%   refuses to produce a GLONASS epoch that would fall inside a leap second.
%
%   leapSecondTable is consulted only for a UTC epoch whose sec lies outside
%   [0, 86400), which is the rare path. A normal arc never touches it, so a
%   missing MEX gateway does not make ordinary normalisation fail.
%
% ACCURACY
%   Exact. Every operation is an addition or subtraction of an integer number
%   of days or of 86400, both exactly representable, so no rounding is
%   introduced beyond that already present in the inputs. Round-trip through
%   normalizeEpoch is bit-identical for an already canonical epoch.
%
% ERRORS
%   referenceSystem:normalizeEpoch:missingField
%   referenceSystem:normalizeEpoch:badFieldType
%   referenceSystem:normalizeEpoch:sizeMismatch
%   referenceSystem:normalizeEpoch:nonIntegerDay
%   referenceSystem:normalizeEpoch:secondsOutOfRange
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   ITU-R TF.460-6, Standard-frequency and time-signal emissions (UTC).
%   Handover section B.3 (the epoch type) and finding C-3.
%
% EXAMPLE
%   epoch = referenceSystem.daySecondToEpoch([57753 86400.5], "UTC");
%   epoch = referenceSystem.normalizeEpoch(epoch);
%   assert(epoch.day == 57753 && epoch.sec > 86400);   % the 2016 leap second
%
% KEYWORDS
%   epoch, MJD, seconds of day, leap second, UTC, normalisation
%
% See also TIMESCALE, LEAPSECONDS, DAYSECONDTOEPOCH, EPOCHTO, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epochIn (1,1) struct
    end

    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;

    for fieldName = ["day", "sec", "scale"]
        if ~isfield(epochIn, fieldName)
            error('referenceSystem:normalizeEpoch:missingField', ...
                'An epoch struct needs the field "%s".', fieldName);
        end
    end

    day = epochIn.day;
    sec = epochIn.sec;
    if ~isnumeric(day) || ~isreal(day) || ~isnumeric(sec) || ~isreal(sec)
        error('referenceSystem:normalizeEpoch:badFieldType', ...
            'The day and sec fields must be real numeric arrays.');
    end
    if ~all(isfinite(day(:))) || ~all(isfinite(sec(:)))
        error('referenceSystem:normalizeEpoch:badFieldType', ...
            'The day and sec fields must be finite.');
    end

    day = double(day(:));
    sec = double(sec(:));
    if isscalar(day) && ~isscalar(sec)
        day = repmat(day, size(sec));
    elseif isscalar(sec) && ~isscalar(day)
        sec = repmat(sec, size(day));
    end
    if numel(day) ~= numel(sec)
        error('referenceSystem:normalizeEpoch:sizeMismatch', ...
            ['The day and sec fields must have the same number of elements ', ...
            'or one of them must be scalar; they have %d and %d.'], ...
            numel(day), numel(sec));
    end

    if ~(isstring(epochIn.scale) || ischar(epochIn.scale)) || ...
            numel(string(epochIn.scale)) ~= 1
        error('referenceSystem:normalizeEpoch:badFieldType', ...
            'The scale field must be a string or char scalar.');
    end
    scaleInfo = referenceSystem.timeScale(string(epochIn.scale));

    source = "unspecified";
    if isfield(epochIn, 'source') && ...
            (isstring(epochIn.source) || ischar(epochIn.source)) && ...
            isscalar(string(epochIn.source))
        source = string(epochIn.source);
    end

    isLeapBearingDay = scaleInfo.name == "UTC";

    dayFraction = day - floor(day);
    if any(dayFraction ~= 0)
        if isLeapBearingDay
            error('referenceSystem:normalizeEpoch:nonIntegerDay', ...
                ['A UTC epoch needs an integer day number: folding a ', ...
                'fractional day into seconds assumes an 86400 s day, which ', ...
                'is wrong on a leap-second day. First offending index: %d.'], ...
                find(dayFraction ~= 0, 1));
        end
        sec = sec + dayFraction*secondsPerDay;
        day = floor(day);
    end

    % THE CARRY ITSELF IS NOT HERE. It is the package-private carryEpoch, which
    % convertTimeScale also reaches directly for epochs it has just built from
    % one it already normalised. This function is the VALIDATING entry to that
    % single implementation; there is no second copy of the leap-second carry
    % (prompt P28b, decision D88).
    [day, sec] = carryEpoch(day, sec, isLeapBearingDay);

    epochOut = struct('day', day, 'sec', sec, 'scale', scaleInfo.name, ...
        'source', source);
end
