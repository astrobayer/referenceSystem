function span = gpsNanosecondSpan()
%GPSNANOSECONDSPAN The int64 GPS-nanosecond representation and its exact span.
%
%   span = gpsNanosecondSpan() returns the origin, the two scale factors and
%   the inclusive bounds of the int64 GPS-nanosecond representation, so that
%   the inbound and the outbound converter describe ONE span rather than two
%   that happen to agree today.
%
%   PACKAGE-PRIVATE, AND THE SINGLE AUTHORITY FOR THAT SPAN.
%   gpsNanosecondsToEpoch bounds its argument with it and epochTo bounds the
%   epoch's day number with it. Neither holds a literal of its own: both
%   DERIVE the bounds here from intmax("int64") and the origin, which is
%   obligation O20 - two instruments deriving from one authority rather than
%   copying it.
%
% INPUT ARGUMENTS
%   (none)
%
% OUTPUT ARGUMENTS
%   Name                 Size   Type    Units  Description
%   ----                 ----   ----    -----  -----------
%   span                 1x1    struct  -      Fields listed below.
%   .originDay           1x1    double  d      MJD at 0h of the origin day,
%                                              51544 = 2000-01-01.
%   .originSecond        1x1    double  s      Seconds of that day at the
%                                              origin, 43200 = 12h.
%   .nanosecondPerDay    1x1    int64   ns     86400e9, one day.
%   .halfDayNanosecond   1x1    int64   ns     43200e9, the origin offset.
%   .maxDayOffset        1x1    double  d      Largest |day - originDay| that
%                                              cannot overflow int64.
%   .lowerNanosecond     1x1    int64   ns     Smallest representable count.
%   .upperNanosecond     1x1    int64   ns     Largest representable count.
%
% METHOD
%   THE ORIGIN IS 2000-01-01 12:00:00 GPS, not the GPS week epoch of 1980. It
%   is the epoch the GRACE and GRACE-FO Level-1B products count their time
%   tags from, and it is MJD 51544 + 43200 s, so it is the J2000.0 MJD of
%   iersConstants read in the GPS scale. Both components are taken from
%   iersConstants rather than written here, exactly as j2000SecondsToEpoch
%   takes them, so the origin has one definition in the toolbox.
%
%   THE BOUND IS DERIVED, NOT CHOSEN. int64 arithmetic in MATLAB SATURATES at
%   intmax rather than wrapping, so an overflow would return a plausible,
%   monotone, wrong count with nothing to catch it - the silent degradation
%   section C.6 forbids. maxDayOffset is the largest whole number of days from
%   the origin for which day*86400e9 plus a full day of nanoseconds still fits,
%
%       maxDayOffset = floor(intmax("int64")/86400e9) - 1 = 106750,
%
%   and the two nanosecond bounds are that offset expressed in the counting
%   origin. The one subtracted is the room the seconds of day and the 12-hour
%   origin need; without it the last representable day would be representable
%   only until noon. The span is MJD -55206 to MJD 158294, that is
%   1707-09-24 to 2292-04-09, which is 292 years either side of the origin.
%
% ACCURACY
%   Exact. Every quantity is an integer that int64 or double represents
%   exactly; no rounding occurs anywhere in this function.
%
% ERRORS
%   (none)
%
% REFERENCES
%   GRACE-FO Level-1 Data Product User Handbook, JPL D-56935, on the
%   continuous seconds past 2000-01-01 12:00:00 GPS used as the time tag.
%   IS-GPS-200N, Section 20.3.3.5.2.4 (GPS time is continuous, no leap
%   seconds).
%   Handover section B.3 (the epoch struct) and decision D6.
%
% EXAMPLE
%   span = gpsNanosecondSpan();
%   assert(span.upperNanosecond > 0 && span.lowerNanosecond < 0);
%
% KEYWORDS
%   GPS, nanoseconds, int64, epoch, overflow, saturation, span
%
% See also GPSNANOSECONDSTOEPOCH, EPOCHTO, IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-09-21 16:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    constants = referenceSystem.iersConstants();
    originDay = floor(constants.mjdJ2000);
    originSecond = (constants.mjdJ2000 - originDay)*constants.secondsPerDay;

    nanosecondPerSecond = int64(1000000000);
    nanosecondPerDay = int64(constants.secondsPerDay)*nanosecondPerSecond;
    halfDayNanosecond = int64(originSecond)*nanosecondPerSecond;

    % Derived from intmax and nothing else; see METHOD for the subtracted day.
    maxDayOffset = double(idivide(intmax('int64'), nanosecondPerDay, 'floor')) - 1;

    span = struct( ...
        'originDay', originDay, ...
        'originSecond', originSecond, ...
        'nanosecondPerDay', nanosecondPerDay, ...
        'halfDayNanosecond', halfDayNanosecond, ...
        'maxDayOffset', maxDayOffset, ...
        'lowerNanosecond', -int64(maxDayOffset)*nanosecondPerDay - halfDayNanosecond, ...
        'upperNanosecond', int64(maxDayOffset)*nanosecondPerDay + ...
            nanosecondPerDay - int64(1) - halfDayNanosecond);
end
