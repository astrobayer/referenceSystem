function epoch = daySecondToEpoch(daySecond, scale)
%DAYSECONDTOEPOCH Epoch from an Nx2 day-number and seconds-of-day matrix.
%
%   epoch = daySecondToEpoch(daySecond, scale) reads column 1 as the integer
%   day number and column 2 as seconds since 0h of that day, in the given time
%   scale, and returns the canonical epoch struct of handover section B.3.
%
%   This is the lossless constructor and the one to use for precise work: it
%   is the only inbound form that can express an epoch inside a positive leap
%   second, and the only one that carries sub-microsecond resolution over
%   decades without qualification.
%
% INPUT ARGUMENTS
%   Name        Size   Type            Units  Description
%   ----        ----   ----            -----  -----------
%   daySecond   Nx2    double          -      Column 1 day number in days,
%                                             column 2 seconds of day.
%   scale       1x1    string | char   -      Time scale, any case, one of the
%                                             names in timeScale.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epoch      1x1    struct    -      Canonical epoch, N entries.
%   .day       Nx1    double    d      Integer day number.
%   .sec       Nx1    double    s      Seconds of day.
%   .scale     1x1    string    -      Canonical scale name.
%   .source    1x1    string    -      "daySecondToEpoch".
%
% METHOD
%   The two columns are handed to normalizeEpoch unchanged, so the carry and
%   the leap-second rules of that function apply. The input is required to be
%   Nx2 exactly; a 1x2 row is therefore one epoch and never two, which is the
%   ambiguity finding M-1 records v1 as guessing at. mjdToEpoch is the function
%   that reads [60310 43200] as two epochs.
%
% ACCURACY
%   Exact. The day number and the seconds of day are stored as given, so the
%   resolution is that of a double near 86400, which is 1.5e-11 s, and it does
%   not degrade with the epoch. This is the reason the toolbox carries a split
%   epoch at all; see the ACCURACY block of mjdToEpoch for the comparison.
%
% ERRORS
%   referenceSystem:daySecondToEpoch:incorrectNumberOfColumns
%   referenceSystem:timeScale:unknownScale
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   Handover section B.3 and finding M-1.
%
% EXAMPLE
%   % The instant 2016-12-31T23:59:60.5 UTC, inside the leap second.
%   epoch = referenceSystem.daySecondToEpoch([57753 86400.5], "UTC");
%
% KEYWORDS
%   epoch, day number, seconds of day, leap second, split precision
%
% See also MJDTOEPOCH, EPOCHTO, NORMALIZEEPOCH.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        daySecond (:,:) double {mustBeReal, mustBeFinite, mustBeNonempty}
        scale (1,1) string
    end

    if size(daySecond, 2) ~= 2
        error('referenceSystem:daySecondToEpoch:incorrectNumberOfColumns', ...
            ['daySecond must be Nx2, [dayNumber secondsOfDay]; it has %d ', ...
            'columns. For decimal MJD use mjdToEpoch instead.'], ...
            size(daySecond, 2));
    end

    epoch = referenceSystem.normalizeEpoch(struct( ...
        'day', daySecond(:,1), ...
        'sec', daySecond(:,2), ...
        'scale', scale, ...
        'source', "daySecondToEpoch"));
end
