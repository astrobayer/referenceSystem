function epoch = mjdToEpoch(mjd, scale)
%MJDTOEPOCH Epoch from a decimal Modified Julian Date.
%
%   epoch = mjdToEpoch(mjd, scale) interprets every element of mjd as one
%   decimal MJD in the given time scale and returns the canonical epoch struct
%   of handover section B.3.
%
% INPUT ARGUMENTS
%   Name    Size   Type            Units  Description
%   ----    ----   ----            -----  -----------
%   mjd     Nx1    double          d      Decimal Modified Julian Dates. Any
%                                         shape is accepted and read in column
%                                         order.
%   scale   1x1    string | char   -      Time scale, any case, one of the
%                                         names in timeScale.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epoch      1x1    struct    -      Canonical epoch, N entries.
%   .day       Nx1    double    d      Integer day number.
%   .sec       Nx1    double    s      Seconds of day.
%   .scale     1x1    string    -      Canonical scale name.
%   .source    1x1    string    -      "mjdToEpoch".
%
% METHOD
%   day = floor(mjd) and sec = (mjd - day)*86400. There is no shape guessing
%   and no Format argument: this function takes decimal MJD and nothing else,
%   which is what makes finding M-1 structurally impossible. In v1 the input
%   [60310 43200] was ambiguous between two epochs and one day-plus-seconds
%   pair, and mjd_normalize guessed. Here mjdToEpoch([60310 43200]) is
%   unambiguously two epochs and daySecondToEpoch([60310 43200]) is
%   unambiguously one. Do not add a wrapper that accepts either.
%
%   For a UTC input the leap second itself is not reachable through this
%   constructor, because a decimal MJD has no room for a 86400.5 s day; use
%   daySecondToEpoch for an epoch inside a leap second.
%
% ACCURACY
%   The split form is exact; the resolution is that of the decimal MJD handed
%   in. Near MJD 60000 one unit in the last place of a double is 7.3e-12 d,
%   which is 0.63 us, so a decimal MJD cannot express a GRACE KBR sample
%   interval and this constructor cannot recover what the caller has already
%   lost. Use daySecondToEpoch or j2000SecondsToEpoch where that matters.
%   Round-trip mjdToEpoch then epochTo(...,"mjd") reproduces the input to
%   within two units in the last place of the input, measured 1.5e-11 d over
%   1962 to 2100.
%
% ERRORS
%   referenceSystem:timeScale:unknownScale
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   Handover section B.3 and finding M-1.
%
% EXAMPLE
%   epoch = referenceSystem.mjdToEpoch([60310.5; 60311.5], "TT");
%   assert(all(epoch.sec == 43200));
%
% KEYWORDS
%   epoch, MJD, Modified Julian Date, time scale
%
% See also DAYSECONDTOEPOCH, DATETIMETOEPOCH, EPOCHTO, NORMALIZEEPOCH.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        mjd {mustBeNumeric, mustBeReal, mustBeFinite, mustBeNonempty}
        scale (1,1) string
    end

    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    mjd = double(mjd(:));
    day = floor(mjd);

    epoch = referenceSystem.normalizeEpoch(struct( ...
        'day', day, ...
        'sec', (mjd - day)*secondsPerDay, ...
        'scale', scale, ...
        'source', "mjdToEpoch"));
end
