function epoch = gpsNanosecondsToEpoch(nanosecond)
%GPSNANOSECONDSTOEPOCH Epoch from int64 GPS nanoseconds past 2000-01-01 12:00.
%
%   epoch = gpsNanosecondsToEpoch(nanosecond) converts the exact integer time
%   tag of the GRACE and GRACE-FO Level-1B products to the canonical epoch
%   struct of handover section B.3. The returned scale is "GPS" by
%   construction, and the conversion is exact: no intermediate double ever
%   holds the full count.
%
% INPUT ARGUMENTS
%   Name         Size   Type    Units  Description
%   ----         ----   ----    -----  -----------
%   nanosecond   Nx1    int64   ns     Nanoseconds elapsed since
%                                      2000-01-01T12:00:00 GPS. int64 and
%                                      nothing else; a double argument is
%                                      refused rather than converted, see
%                                      METHOD.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epoch      1x1    struct    -      Canonical epoch, N entries.
%   .day       Nx1    double    d      Integer day number.
%   .sec       Nx1    double    s      Seconds of day, [0, 86400).
%   .scale     1x1    string    -      "GPS".
%   .source    1x1    string    -      "gpsNanosecondsToEpoch".
%
% METHOD
%   THE ORIGIN IS 2000-01-01 12:00:00 GPS AND NOT THE GPS WEEK EPOCH. The
%   Level-1B products count continuous seconds from that instant, and the same
%   count scaled to nanoseconds is what the readers of the GRACE-FO toolchain
%   carry. It is MJD 51544 + 43200 s read in the GPS scale, and GPS time has
%   no leap seconds, so the count is a plain elapsed interval.
%
%   A DOUBLE ARGUMENT IS REFUSED, WHICH IS THE WHOLE POINT OF THE FUNCTION.
%   A 2020 tag is about 6.3e17 ns, far above 2^53, so a double cannot hold
%   every value of this representation and a conversion through one loses
%   whole nanoseconds without saying so. An arguments block that declared the
%   type as int64 would CONVERT a double silently, which is the same defect
%   wearing a validator's clothes, so the class is asserted with mustBeA and
%   the argument is left untyped.
%
%   THE SPLIT IS EXACT IN BOTH COMPONENTS. The whole days are separated in
%   int64 by a floored division, so the day number is exact for any input; the
%   remainder is smaller than 86400e9 and therefore below 2^53, so converting
%   it to seconds is the only rounding in the function and it is a relative
%   one of at most eps/2 on a quantity under 86400. Scaling that back by 1e9,
%   which epochTo does, moves the result by less than 0.02 ns, so rounding to
%   the nearest nanosecond recovers the input EXACTLY. The round trip is an
%   identity over the whole representable span, not an approximation to it.
%
%   THE SPAN IS BOUNDED AND THE BOUND IS DERIVED. int64 arithmetic saturates
%   at intmax in MATLAB rather than wrapping, so a count near the limit would
%   otherwise produce a plausible, monotone, wrong epoch. The inclusive bounds
%   come from gpsNanosecondSpan, which is also what epochTo bounds its epoch
%   with, so the two directions describe one span and not two.
%
%   No scale argument is offered. This representation names its own scale, as
%   a GPS week number does: a count of GPS nanoseconds is GPS time by
%   definition. Convert the result with convertTimeScale to work in another.
%
% ACCURACY
%   Exact over the whole representable span, MJD -55206 to MJD 158294, that is
%   1707-09-24 to 2292-04-09. The day number is integer arithmetic throughout.
%   The seconds of day carry one rounding of at most 1.1e-16 relative, which is
%   9.6e-12 s at the end of a day, and the outbound conversion in epochTo
%   removes it: every int64 value in the span survives a round trip bit for
%   bit, which is asserted rather than claimed.
%
% ERRORS
%   referenceSystem:gpsNanosecondsToEpoch:outsideRepresentableSpan
%   MATLAB:validators:mustBeA
%
% REFERENCES
%   GRACE-FO Level-1 Data Product User Handbook, JPL D-56935, Sect. 3, on the
%   continuous seconds past 2000-01-01 12:00:00 GPS used as the time tag.
%   IS-GPS-200N, Section 20.3.3.5.2.4 (GPS time is continuous).
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%
% EXAMPLE
%   epoch = referenceSystem.gpsNanosecondsToEpoch(int64(631108800000000000));
%   assert(epoch.day == 58849 && epoch.sec == 0);   % 2020-01-01 00:00 GPS
%
% KEYWORDS
%   epoch, GPS, nanoseconds, int64, exact, GRACE-FO, Level-1B, time tag
%
% See also EPOCHTO, GPSWEEKTOEPOCH, J2000SECONDSTOEPOCH, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-09-21 16:25 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        nanosecond (:,1) {mustBeA(nanosecond, "int64"), mustBeNonempty}
    end

    span = gpsNanosecondSpan();

    outside = nanosecond < span.lowerNanosecond | ...
        nanosecond > span.upperNanosecond;
    if any(outside)
        first = find(outside, 1);
        error('referenceSystem:gpsNanosecondsToEpoch:outsideRepresentableSpan', ...
            ['Index %d holds %d ns, outside the representable span [%d, %d] ', ...
            'ns, that is MJD %d to MJD %d. int64 arithmetic saturates rather ', ...
            'than wrapping, so a count beyond the span would convert to a ', ...
            'plausible and wrong epoch instead of failing.'], ...
            first, nanosecond(first), span.lowerNanosecond, ...
            span.upperNanosecond, span.originDay - span.maxDayOffset, ...
            span.originDay + span.maxDayOffset);
    end

    % The add cannot saturate: the span above is exactly what bounds it.
    sinceOriginDay = nanosecond + span.halfDayNanosecond;
    dayOffset = idivide(sinceOriginDay, span.nanosecondPerDay, 'floor');
    withinDay = sinceOriginDay - dayOffset*span.nanosecondPerDay;

    epoch = referenceSystem.normalizeEpoch(struct( ...
        'day', span.originDay + double(dayOffset), ...
        'sec', double(withinDay)/1e9, ...
        'scale', "GPS", ...
        'source', "gpsNanosecondsToEpoch"));
end
