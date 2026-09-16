function epoch = j2000SecondsToEpoch(secondsFromJ2000, scale)
%J2000SECONDSTOEPOCH Epoch from seconds elapsed since the J2000.0 epoch.
%
%   epoch = j2000SecondsToEpoch(secondsFromJ2000, scale) interprets its input
%   as seconds since 2000-01-01T12:00:00 of the named scale, which is MJD
%   51544.5, and returns the canonical epoch struct of handover section B.3.
%
% INPUT ARGUMENTS
%   Name               Size   Type            Units  Description
%   ----               ----   ----            -----  -----------
%   secondsFromJ2000   Nx1    double          s      Seconds since J2000.0 in
%                                                    the given scale. Negative
%                                                    values precede it.
%   scale              1x1    string | char   -      Time scale, any case, one
%                                                    of the names in timeScale
%                                                    except UTC and GLONASS.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epoch      1x1    struct    -      Canonical epoch, N entries.
%   .day       Nx1    double    d      Integer day number.
%   .sec       Nx1    double    s      Seconds of day.
%   .scale     1x1    string    -      Canonical scale name.
%   .source    1x1    string    -      "j2000SecondsToEpoch".
%
% METHOD
%   The J2000.0 origin is split before the seconds are added, as day 51544 plus
%   43200 s, so the addition happens entirely inside the seconds field and the
%   day number is never disturbed by a rounding. normalizeEpoch then carries.
%
%   This is the representation an orbit integrator naturally produces, which is
%   why it is a first-class constructor rather than something a caller derives.
%   The scale is required: J2000.0 is defined in TT, but a state vector clock
%   may well be counting TAI or GPS seconds from that instant, and assuming TT
%   would be a silent 32.184 s error.
%
%   A LEAP-BEARING SCALE IS REFUSED. Seconds counted in UTC or GLONASS since
%   J2000.0 are not a time: 22 leap seconds lie between J2000.0 and 2017, and
%   a count of labelled seconds does not say which of them it skipped. Count in
%   TAI, TT or GPS and convert the epoch with convertTimeScale.
%
% ACCURACY
%   Exact to the resolution of the input. For an arc of one day the seconds
%   field stays below 1e5, where one unit in the last place is 1.5e-11 s, so
%   the constructor adds nothing measurable. Over a century the input itself
%   reaches 3e9 s, where one unit in the last place is 4.8e-7 s, and that
%   limitation belongs to the caller's representation, not to this function.
%
% ERRORS
%   referenceSystem:j2000SecondsToEpoch:leapBearingScale
%   referenceSystem:timeScale:unknownScale
%
% REFERENCES
%   IAU 1994 Resolution C7 and IERS Conventions (2010), TN36 Ch. 1 (J2000.0).
%
% EXAMPLE
%   epoch = referenceSystem.j2000SecondsToEpoch(7.5e8, "TT");
%   mjd = referenceSystem.epochTo(epoch, "mjd");
%
% KEYWORDS
%   epoch, J2000, seconds since epoch, orbit integration
%
% See also MJDTOEPOCH, DAYSECONDTOEPOCH, EPOCHTO.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        secondsFromJ2000 {mustBeNumeric, mustBeReal, mustBeFinite, mustBeNonempty}
        scale (1,1) string
    end

    scaleInfo = referenceSystem.timeScale(scale);
    if scaleInfo.isLeapBearing
        error('referenceSystem:j2000SecondsToEpoch:leapBearingScale', ...
            ['Seconds since J2000.0 counted in %s are not a time: the leap ', ...
            'seconds since 2000 are skipped by label and the count does not ', ...
            'say which. Count in TAI, TT or GPS, and convert the epoch with ', ...
            'convertTimeScale.'], scaleInfo.name);
    end

    constants = referenceSystem.iersConstants();
    originDay = floor(constants.mjdJ2000);
    originSecond = (constants.mjdJ2000 - originDay)*constants.secondsPerDay;

    epoch = referenceSystem.normalizeEpoch(struct( ...
        'day', originDay, ...
        'sec', originSecond + double(secondsFromJ2000(:)), ...
        'scale', scale, ...
        'source', "j2000SecondsToEpoch"));
end
