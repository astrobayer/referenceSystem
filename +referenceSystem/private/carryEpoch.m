function [day, sec] = carryEpoch(day, sec, isLeapBearing)
%CARRYEPOCH Fold seconds of day into the canonical range, leap-second aware.
%
%   [day, sec] = carryEpoch(day, sec, isLeapBearing) moves whole days between
%   sec and day so that sec ends in [0, 86400) - or in [0, 86401) on a UTC day
%   that ends in a positive leap second - and returns the pair unchanged in
%   every other respect.
%
%   PACKAGE-PRIVATE, AND THE SINGLE AUTHORITY FOR THE CARRY. normalizeEpoch
%   reaches it after validating a caller's epoch; convertTimeScale reaches it
%   directly, for epochs it has just built from one it already normalised. That
%   difference - whether the inputs have been checked - is the whole of what
%   separates the two paths, and everything downstream of it is here. There is
%   no second copy of the leap-second carry anywhere in the toolbox, which is
%   the constraint that outranks the speed this function exists for.
%
%   IT VALIDATES NOTHING AND MUST NOT BE CALLED WITH UNCHECKED INPUT. day must
%   already be an integer-valued Nx1 double, sec an Nx1 double of the same
%   length, and isLeapBearing a logical scalar that is true only for UTC. A
%   caller that cannot guarantee those calls normalizeEpoch instead.
%
% INPUT ARGUMENTS
%   Name            Size   Type      Units  Description
%   ----            ----   ----      -----  -----------
%   day             Nx1    double    d      Integer day number, MJD at 0h of
%                                           the scale. Not checked.
%   sec             Nx1    double    s      Seconds since 0h of that day, any
%                                           value within one day either side
%                                           for a leap-bearing scale. Not
%                                           checked.
%   isLeapBearing   1x1    logical   -      True for UTC and for nothing else.
%                                           A wrong value here is a silent
%                                           one-second error; see METHOD.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ------   -----  -----------
%   day    Nx1    double   d      Integer day number after the carry.
%   sec    Nx1    double   s      Seconds of day, [0, 86400), or [0, 86401) on
%                                 a positive leap-second day in UTC.
%
% METHOD
%   For a uniform scale the carry is exact and unconditional:
%   carry = floor(sec/86400), sec = sec - 86400*carry, day = day + carry. Every
%   operation is an addition or subtraction of an integer number of days or of
%   86400, both exactly representable, so nothing is rounded.
%
%   UTC is different, and this is finding C-3. A UTC day that ends in a positive
%   leap second is 86401 s long, so the plain carry would turn 23:59:60.5 into
%   00:00:00.5 of the next day - a different instant, one second later,
%   silently. The UTC branch therefore asks leapSecondTable for the length of
%   the day before carrying, and iterates at most twice, which is why the input
%   range is restricted to one day either side.
%
%   THE FLAG IS DERIVED BY THE CALLER AND NEVER GUESSED HERE. Both callers
%   take it from a comparison of the canonical scale name against "UTC":
%   normalizeEpoch after the registry lookup it already made, convertTimeScale
%   at a site where the scale is a literal in the source. Passing it in rather than looking it up is the whole point:
%   the registry lookup was 2.84 us of an 8.13 us normalizeEpoch call, made
%   seventeen times per single-epoch rotation, and twelve of those seventeen
%   were re-deriving what the caller already knew (prompt P28b).
%
%   GLONASS is UTC advanced by three hours, so a leap second falls in the middle
%   of a GLONASS day rather than at its end and has no distinct representation
%   in the day-and-second form. GLONASS is therefore carried as a uniform scale
%   and convertTimeScale refuses to produce a GLONASS epoch inside a leap
%   second. Callers must pass isLeapBearing = false for it. That is NOT the
%   registry's isLeapBearing field, which timeScale sets true for GLONASS
%   because a GLONASS interval can span an inserted second (addSeconds
%   refuses one): the flag here means "a UTC day may be 86401 s long", and
%   only UTC has such days.
%
% ACCURACY
%   Exact. No rounding is introduced beyond that already present in the inputs,
%   and a canonical pair passed in comes back bit-identical.
%
% ERRORS
%   referenceSystem:normalizeEpoch:secondsOutOfRange
%
%   THE IDENTIFIER DELIBERATELY NAMES normalizeEpoch AND NOT THIS FUNCTION. It
%   is the identifier this condition has always raised, it is the one the help
%   of normalizeEpoch and convertTimeScale documents, and a package-private
%   function is not a name a caller can act on. Moving the check here must not
%   change what a caller catches.
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   ITU-R TF.460-6, Standard-frequency and time-signal emissions (UTC).
%   Handover section B.3, finding C-3, decision D88 and section H.6.
%
% EXAMPLE
%   [day, sec] = carryEpoch(57753, 86400.5, true);   % the 2016 leap second
%   assert(day == 57753 && sec > 86400);
%
% KEYWORDS
%   epoch, carry, seconds of day, leap second, UTC, canonical form
%
% See also NORMALIZEEPOCH, CONVERTTIMESCALE, LEAPSECONDTABLE.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 11:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;

    if isLeapBearing
        [day, sec] = localCarryUtc(day, sec, secondsPerDay);
        return
    end

    carry = floor(sec/secondsPerDay);
    sec = sec - carry*secondsPerDay;
    day = day + carry;
end

% =========================== local functions ===========================

function [day, sec] = localCarryUtc(day, sec, secondsPerDay)
%LOCALCARRYUTC Leap-second-aware carry for a UTC epoch.
%   The length of a UTC day is 86400 s plus the leap second inserted at its
%   end, so the carry has to know that length before it can subtract it. Only
%   epochs whose sec already lies outside [0, 86400) can be affected, and the
%   input range is restricted to one day either side so that at most two passes
%   are ever needed; a larger offset is arithmetic the caller should be doing in
%   TAI, where it is unambiguous.
%
%   THE EARLY RETURN IS WHY A MISSING GATEWAY DOES NOT BREAK ORDINARY
%   NORMALISATION. leapSecondTable is consulted only when something actually
%   needs carrying, which a normal arc never does. The profile of one rotation
%   entered this branch thirteen times and left it at the guard every time.
    if ~any(sec < 0 | sec >= secondsPerDay)
        return
    end

    if any(sec < -secondsPerDay | sec >= 2*secondsPerDay)
        offending = find(sec < -secondsPerDay | sec >= 2*secondsPerDay, 1);
        error('referenceSystem:normalizeEpoch:secondsOutOfRange', ...
            ['A UTC epoch must carry sec within one day of its day number, ', ...
            'that is in [-86400, 172800); index %d holds %.6f. Convert to ', ...
            'TAI with convertTimeScale before offsetting a UTC epoch by ', ...
            'more than a day.'], offending, sec(offending));
    end

    leapTable = referenceSystem.leapSecondTable('list');
    changeDay = leapTable.mjd;
    % The first row is the initial TAI-UTC offset at 1972-01-01, not an
    % inserted second, so its step is zero.
    stepSize = [0; diff(leapTable.deltaAt)];

    for pass = 1:2
        over = sec >= secondsPerDay + localLeapAtEndOfDay(day, changeDay, stepSize);
        if any(over)
            sec(over) = sec(over) - secondsPerDay - ...
                localLeapAtEndOfDay(day(over), changeDay, stepSize);
            day(over) = day(over) + 1;
        end

        under = sec < 0;
        if any(under)
            day(under) = day(under) - 1;
            sec(under) = sec(under) + secondsPerDay + ...
                localLeapAtEndOfDay(day(under), changeDay, stepSize);
        end

        if ~any(over) && ~any(under)
            break
        end
    end
end

function leap = localLeapAtEndOfDay(day, changeDay, stepSize)
%LOCALLEAPATENDOFDAY Seconds inserted at the end of each given UTC day.
%   A step recorded at change day d takes effect at 0h of d, so it is the
%   second inserted at the end of day d-1.
    leap = zeros(size(day));
    for k = 1:numel(changeDay)
        leap(day == changeDay(k) - 1) = stepSize(k);
    end
end
