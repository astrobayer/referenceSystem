function epoch = gpsWeekToEpoch(week, secondOfWeek)
%GPSWEEKTOEPOCH Epoch from a GPS week number and seconds of week.
%
%   epoch = gpsWeekToEpoch(week, secondOfWeek) converts the GPS broadcast time
%   representation to the canonical epoch struct of handover section B.3. The
%   returned scale is "GPS" by construction.
%
% INPUT ARGUMENTS
%   Name           Size   Type     Units  Description
%   ----           ----   ----     -----  -----------
%   week           Nx1    double   week   Continuous GPS week number, counted
%                                         from week 0 beginning 1980-01-06.
%                                         Must already be unrolled; see METHOD.
%   secondOfWeek   Nx1    double   s      Seconds since 0h of the Sunday that
%                                         begins that week. Scalar is broadcast.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epoch      1x1    struct    -      Canonical epoch, N entries.
%   .day       Nx1    double    d      Integer day number.
%   .sec       Nx1    double    s      Seconds of day.
%   .scale     1x1    string    -      "GPS".
%   .source    1x1    string    -      "gpsWeekToEpoch".
%
% METHOD
%   GPS week 0 begins at 1980-01-06T00:00:00 UTC, which is MJD 44244, and GPS
%   time has run without leap seconds ever since, so
%   day = 44244 + 7*week + floor(secondOfWeek/86400) with the remainder as the
%   seconds of day. The arithmetic is done by normalizeEpoch, which carries
%   exactly because GPS is a uniform scale.
%
%   No scale argument is offered, because this representation names its own
%   scale: a GPS week number is GPS time by definition. Galileo broadcasts the
%   same week and second convention, and GST is nominally equal to GPS time, so
%   a Galileo caller may use this constructor and then convert; the nominal
%   nature of that equality is documented in convertTimeScale. BeiDou counts
%   weeks from a different origin and is deliberately not accepted here.
%
%   The week number must already be unrolled. The broadcast navigation message
%   transmits it in ten bits, so it rolls over every 1024 weeks - in 1999, 2019
%   and next in 2038 - and only the receiver knows which cycle a file belongs
%   to. Guessing the cycle here would be finding M-1 in a new costume: it would
%   be right most of the time and silently 19.6 years wrong otherwise.
%
% ACCURACY
%   Exact. The week and day origins are integers and 604800 and 86400 are
%   exactly representable, so no rounding enters beyond that of secondOfWeek.
%
% ERRORS
%   referenceSystem:gpsWeekToEpoch:sizeMismatch
%   referenceSystem:gpsWeekToEpoch:nonIntegerWeek
%
% REFERENCES
%   IS-GPS-200N, Section 20.3.3.5.2.4 (GPS week number and its rollover).
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%
% EXAMPLE
%   epoch = referenceSystem.gpsWeekToEpoch(2295, 86400*3 + 43200);
%   tai = referenceSystem.convertTimeScale(epoch, "TAI");
%
% KEYWORDS
%   epoch, GPS week, seconds of week, rollover, GNSS
%
% See also MJDTOEPOCH, EPOCHTO, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        week (:,1) double {mustBeReal, mustBeFinite, mustBeNonempty}
        secondOfWeek (:,1) double {mustBeReal, mustBeFinite, mustBeNonempty}
    end

    if any(mod(week, 1) ~= 0)
        error('referenceSystem:gpsWeekToEpoch:nonIntegerWeek', ...
            'The GPS week number must be an integer; index %d holds %.6f.', ...
            find(mod(week, 1) ~= 0, 1), week(find(mod(week, 1) ~= 0, 1)));
    end
    if isscalar(secondOfWeek) && ~isscalar(week)
        secondOfWeek = repmat(secondOfWeek, size(week));
    elseif isscalar(week) && ~isscalar(secondOfWeek)
        week = repmat(week, size(secondOfWeek));
    end
    if numel(week) ~= numel(secondOfWeek)
        error('referenceSystem:gpsWeekToEpoch:sizeMismatch', ...
            ['week and secondOfWeek must have the same number of elements ', ...
            'or one of them must be scalar; they have %d and %d.'], ...
            numel(week), numel(secondOfWeek));
    end

    % GPS week 0 begins 1980-01-06T00:00:00 UTC = MJD 44244.
    gpsWeekZeroDay = 44244;
    daysPerWeek = 7;

    epoch = referenceSystem.normalizeEpoch(struct( ...
        'day', gpsWeekZeroDay + daysPerWeek*week, ...
        'sec', secondOfWeek, ...
        'scale', "GPS", ...
        'source', "gpsWeekToEpoch"));
end
