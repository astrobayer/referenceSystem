function value = epochTo(epoch, format)
%EPOCHTO Convert an epoch struct to one of the five external representations.
%
%   value = epochTo(epoch, format) returns the epoch in the requested outbound
%   representation. format is one of "mjd", "daySecond", "datetime", "gpsWeek"
%   or "j2000Seconds".
%
% INPUT ARGUMENTS
%   Name     Size   Type            Units  Description
%   ----     ----   ----            -----  -----------
%   epoch    1x1    struct          -      Epoch struct, N entries; see
%                                          normalizeEpoch.
%   format   1x1    string | char   -      Target representation, see above.
%
% OUTPUT ARGUMENTS
%   Name    Size   Type                Units  Description
%   ----    ----   ----                -----  -----------
%   value   Nx1    double | datetime   -      "mjd": decimal MJD, days.
%           Nx2    double              -      "daySecond": [day secondsOfDay].
%           Nx1    datetime            -      "datetime": unzoned instants.
%           Nx2    double              -      "gpsWeek": [week secondOfWeek].
%           Nx1    double              s      "j2000Seconds": seconds since
%                                             2000-01-01T12:00 of the scale.
%
% METHOD
%   The outbound direction is one function where the inbound direction is five
%   (decision D32), and the asymmetry is deliberate rather than an oversight.
%   A constructor receives a bare numeric array, which cannot declare what it
%   is, so the function name has to fix the interpretation - that is what makes
%   finding M-1 unreachable. Every outbound call instead receives an epoch
%   struct, which can only be an epoch, so there is no ambiguity left for five
%   names to resolve and five names would buy symmetry rather than safety
%   (handover section C.7 rule 6).
%
%   Each format is the exact inverse of its constructor: "mjd" of mjdToEpoch,
%   "daySecond" of daySecondToEpoch, and so on. "gpsWeek" is defined only for a
%   GPS epoch and refuses any other scale rather than converting silently,
%   because a week number is a statement about GPS time.
%
%   MJD 0 is 1858-11-17 00:00 by definition; datetimeToEpoch carries the same
%   origin for the inbound direction and a precision test binds the two.
%
% ACCURACY
%   "daySecond" and "gpsWeek" are exact: they move integers and the unmodified
%   seconds field. "mjd" and "j2000Seconds" collapse the split form back into
%   one double and therefore lose resolution - 0.63 us near MJD 60000 for a
%   decimal MJD, 0.48 us near 2100 for seconds from J2000 - so a round trip
%   through them reproduces the original to about two units in the last place
%   and no better. "datetime" resolves about 1 ns and cannot represent an
%   instant inside a positive leap second at all, which is why that case is an
%   error rather than a rounding.
%
% ERRORS
%   referenceSystem:epochTo:wrongScale
%   referenceSystem:epochTo:unrepresentableLeapSecond
%   MATLAB:validators:mustBeMember
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   IS-GPS-200N, Section 20.3.3.5.2.4 (GPS week number).
%   Handover decision D32 and section C.7 rule 6.
%
% EXAMPLE
%   epoch = referenceSystem.daySecondToEpoch([60310 43200], "TT");
%   assert(isequal(referenceSystem.epochTo(epoch, "daySecond"), [60310 43200]));
%
% KEYWORDS
%   epoch, MJD, datetime, GPS week, J2000, round trip
%
% See also MJDTOEPOCH, DAYSECONDTOEPOCH, DATETIMETOEPOCH, GPSWEEKTOEPOCH,
%   J2000SECONDSTOEPOCH.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        format (1,1) string {mustBeMember(format, ...
            ["mjd", "daySecond", "datetime", "gpsWeek", "j2000Seconds"])}
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    constants = referenceSystem.iersConstants();
    secondsPerDay = constants.secondsPerDay;

    switch format
        case "daySecond"
            value = [epoch.day, epoch.sec];

        case "mjd"
            value = epoch.day + epoch.sec/secondsPerDay;

        case "j2000Seconds"
            originDay = floor(constants.mjdJ2000);
            originSecond = (constants.mjdJ2000 - originDay)*secondsPerDay;
            value = (epoch.day - originDay)*secondsPerDay + ...
                (epoch.sec - originSecond);

        case "gpsWeek"
            if epoch.scale ~= "GPS"
                error('referenceSystem:epochTo:wrongScale', ...
                    ['A GPS week number is defined for GPS time only; this ', ...
                    'epoch is %s. Convert with convertTimeScale first.'], ...
                    epoch.scale);
            end
            gpsWeekZeroDay = 44244;
            daysPerWeek = 7;
            elapsedDay = epoch.day - gpsWeekZeroDay;
            week = floor(elapsedDay/daysPerWeek);
            value = [week, (elapsedDay - week*daysPerWeek)*secondsPerDay + epoch.sec];

        case "datetime"
            if any(epoch.sec >= secondsPerDay)
                error('referenceSystem:epochTo:unrepresentableLeapSecond', ...
                    ['datetime has no representation for an instant inside a ', ...
                    'positive leap second; index %d holds %.6f s of day. Use ', ...
                    'the "daySecond" format for such epochs.'], ...
                    find(epoch.sec >= secondsPerDay, 1), ...
                    epoch.sec(find(epoch.sec >= secondsPerDay, 1)));
            end
            % MJD 0 = 1858-11-17 00:00, by definition; see datetimeToEpoch.
            modifiedJulianDateOrigin = datetime(1858, 11, 17, 0, 0, 0);
            value = modifiedJulianDateOrigin + days(epoch.day) + seconds(epoch.sec);
    end
end
