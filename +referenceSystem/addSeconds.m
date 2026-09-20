function epochOut = addSeconds(epochIn, offset)
%ADDSECONDS Advance an epoch by a number of seconds of its own time scale.
%
%   epochOut = addSeconds(epochIn, offset) adds offset seconds to every entry
%   of epochIn and returns the normalised result in the same time scale.
%
% INPUT ARGUMENTS
%   Name       Size        Type     Units  Description
%   ----       ----        ----     -----  -----------
%   epochIn    1x1         struct   -      Epoch struct, N entries.
%   offset     1x1 | Nx1   double   s      Seconds to add. May be negative.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epochOut   1x1    struct    -      Epoch struct, N entries, same scale.
%   .source    1x1    string    -      "addSeconds".
%
% METHOD
%   The offset is added to the seconds field only, and normalizeEpoch performs
%   the carry. Neither the day number nor the offset is ever routed through a
%   decimal MJD, which is what keeps the operation exact over decades.
%
%   On a uniform scale a second of the scale is a second of proper time, so the
%   result is unambiguous. On UTC and GLONASS it is not: an interval that
%   spans a positive leap second contains one more second of proper time than
%   its UTC seconds-of-day arithmetic suggests. This function therefore
%   computes the exact answer where no leap second lies in the interval, and
%   raises an error naming the offending entries where one does, rather than
%   returning a value that is silently one second wrong. Convert to TAI, add
%   there, and convert back - which is unambiguous by construction.
%
% ACCURACY
%   Exact to the resolution of the seconds field, which is 1.5e-11 s near
%   86400 and 2.2e-16 s near 1. Repeated accumulation is bounded by the number
%   of additions times half that resolution, so it depends on where in the day
%   the accumulation happens rather than on how long the toolbox has been
%   running: ten thousand additions of 1e-4 s starting at 0h reproduce 1 s to
%   within 1.1e-12 s, and the precision test asserts better than 1e-9 s. One
%   million additions of 1e-6 s carry the same bound, because the seconds field
%   never leaves [0, 1] in either case.
%
% ERRORS
%   referenceSystem:addSeconds:sizeMismatch
%   referenceSystem:addSeconds:leapSecondCrossed
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   ITU-R TF.460-6 (UTC leap seconds).
%
% EXAMPLE
%   epoch = referenceSystem.daySecondToEpoch([60310 86399.5], "TT");
%   later = referenceSystem.addSeconds(epoch, 1.0);
%   assert(later.day == 60311 && abs(later.sec - 0.5) < 1e-9);
%
% KEYWORDS
%   epoch, arithmetic, offset, leap second, precision
%
% See also SECONDSBETWEEN, NORMALIZEEPOCH, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epochIn (1,1) struct
        offset (:,1) double {mustBeReal, mustBeFinite, mustBeNonempty}
    end

    epochIn = referenceSystem.normalizeEpoch(epochIn);
    epochCount = numel(epochIn.day);

    if isscalar(offset)
        offset = repmat(offset, epochCount, 1);
    elseif numel(offset) ~= epochCount
        error('referenceSystem:addSeconds:sizeMismatch', ...
            ['offset must be scalar or have one value per epoch; it has %d ', ...
            'values for %d epochs.'], numel(offset), epochCount);
    end

    scaleInfo = referenceSystem.timeScale(epochIn.scale);
    if scaleInfo.isLeapBearing
        localRejectLeapCrossing(epochIn, offset, 'addSeconds');
    end

    epochOut = referenceSystem.normalizeEpoch(struct( ...
        'day', epochIn.day, ...
        'sec', epochIn.sec + offset, ...
        'scale', epochIn.scale, ...
        'source', "addSeconds"));
end

% =========================== local functions ===========================

function localRejectLeapCrossing(epoch, offset, functionName)
%LOCALREJECTLEAPCROSSING Error if an interval spans a leap-second insertion.
%   The interval is expressed in UTC days. GLONASS runs three hours ahead of
%   UTC, so its epochs are shifted back before the day numbers are compared;
%   without that shift a leap second falling at 03:00 GLONASS would be
%   attributed to the wrong day.
    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    glonassOffset = 3*3600;

    utcSecond = epoch.sec;
    if epoch.scale == "GLONASS"
        utcSecond = utcSecond - glonassOffset;
    end
    startDay = epoch.day + floor(utcSecond/secondsPerDay);
    endDay = epoch.day + floor((utcSecond + offset)/secondsPerDay);

    leapTable = referenceSystem.leapSecondTable('list');
    changeDay = leapTable.mjd;

    low = min(startDay, endDay);
    high = max(startDay, endDay);
    crossed = false(size(startDay));
    for k = 1:numel(changeDay)
        crossed = crossed | (changeDay(k) > low & changeDay(k) <= high);
    end

    if any(crossed)
        first = find(crossed, 1);
        error(sprintf('referenceSystem:%s:leapSecondCrossed', functionName), ...
            ['%d of %d intervals span a leap-second insertion, so seconds of ', ...
            '%s are not seconds of proper time across them; index %d is the ', ...
            'first. Convert to TAI with convertTimeScale, do the arithmetic ', ...
            'there, and convert back.'], sum(crossed), numel(crossed), ...
            epoch.scale, first);
    end
end
