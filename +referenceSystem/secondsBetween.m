function interval = secondsBetween(fromEpoch, toEpoch)
%SECONDSBETWEEN Seconds elapsed from one epoch to another in the same scale.
%
%   interval = secondsBetween(fromEpoch, toEpoch) returns toEpoch minus
%   fromEpoch in seconds. Both epochs must be in the same time scale.
%
% INPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   fromEpoch   1x1    struct   -      Epoch struct, N entries or one entry.
%   toEpoch     1x1    struct   -      Epoch struct, N entries or one entry.
%
%   The arguments are not named epochFrom and epochTo, which would read better,
%   because epochTo is the name of a sibling function: a parameter of that name
%   would shadow it inside this file and would be reported by the section C.5
%   namespace scan, which flags any bare occurrence of a sibling name.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type     Units  Description
%   ----       ----   ----     -----  -----------
%   interval   Nx1    double   s      Elapsed seconds, positive when toEpoch
%                                     follows fromEpoch.
%
% METHOD
%   interval = (dayTo - dayFrom)*86400 + (secTo - secFrom). The day difference
%   is an exact integer subtraction and the seconds difference stays below
%   86401 in magnitude, so no cancellation of large nearly-equal numbers occurs
%   and the result is exact to the resolution of the seconds fields. Forming
%   the same quantity from two decimal MJDs would lose about 1 us per operand.
%
%   The scales must match. Differencing a TT epoch against a TAI one is a
%   32.184 s error that no test of the result would reveal, so it is refused
%   rather than computed. As in addSeconds, an interval that spans a leap
%   second is refused on UTC and GLONASS, because the count of seconds of day
%   between two such epochs is not the elapsed proper time.
%
% ACCURACY
%   Exact to about 1.5e-11 s for intervals within a day and about 2e-9 s for
%   intervals of a century, both set by the representation of the operands
%   rather than by this function.
%
% ERRORS
%   referenceSystem:secondsBetween:scaleMismatch
%   referenceSystem:secondsBetween:sizeMismatch
%   referenceSystem:addSeconds:leapSecondCrossed  (raised on a leap-bearing
%       scale; the check is delegated to addSeconds so that one implementation
%       of it exists rather than two, and it therefore keeps that identifier)
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%
% EXAMPLE
%   a = referenceSystem.daySecondToEpoch([60310 0], "TT");
%   b = referenceSystem.daySecondToEpoch([60311 43200], "TT");
%   assert(referenceSystem.secondsBetween(a, b) == 129600);
%
% KEYWORDS
%   epoch, interval, elapsed time, difference, precision
%
% See also ADDSECONDS, NORMALIZEEPOCH, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        fromEpoch (1,1) struct
        toEpoch (1,1) struct
    end

    fromEpoch = referenceSystem.normalizeEpoch(fromEpoch);
    toEpoch = referenceSystem.normalizeEpoch(toEpoch);

    if fromEpoch.scale ~= toEpoch.scale
        error('referenceSystem:secondsBetween:scaleMismatch', ...
            ['Both epochs must be in the same time scale; they are %s and ', ...
            '%s. Convert one with convertTimeScale first.'], ...
            fromEpoch.scale, toEpoch.scale);
    end

    countFrom = numel(fromEpoch.day);
    countTo = numel(toEpoch.day);
    if countFrom ~= countTo && countFrom ~= 1 && countTo ~= 1
        error('referenceSystem:secondsBetween:sizeMismatch', ...
            ['The two epochs must hold the same number of entries or one of ', ...
            'them must hold exactly one; they hold %d and %d.'], ...
            countFrom, countTo);
    end

    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    interval = (toEpoch.day - fromEpoch.day)*secondsPerDay + ...
        (toEpoch.sec - fromEpoch.sec);

    scaleInfo = referenceSystem.timeScale(fromEpoch.scale);
    if scaleInfo.isLeapBearing
        % One implementation of the leap-crossing rule, not two: advancing
        % fromEpoch by the interval just computed must reach toEpoch, and
        % addSeconds refuses exactly the intervals for which that is untrue.
        anchor = fromEpoch;
        if isscalar(anchor.day) && numel(interval) > 1
            anchor.day = repmat(anchor.day, size(interval));
            anchor.sec = repmat(anchor.sec, size(interval));
        end
        referenceSystem.addSeconds(anchor, interval);
    end
end
