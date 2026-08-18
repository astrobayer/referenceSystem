function epoch = datetimeToEpoch(t, scale)
%DATETIMETOEPOCH Epoch from a MATLAB datetime array.
%
%   epoch = datetimeToEpoch(t, scale) converts a datetime array to the
%   canonical epoch struct of handover section B.3, reading the datetimes as
%   instants of the named time scale.
%
% INPUT ARGUMENTS
%   Name    Size   Type            Units  Description
%   ----    ----   ----            -----  -----------
%   t       Nx1    datetime        -      Instants. A zoned datetime is
%                                         converted to UTC first and then only
%                                         scale "UTC" is accepted.
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
%   .source    1x1    string    -      "datetimeToEpoch".
%
% METHOD
%   MJD 0 is 1858-11-17 00:00 by definition, so the day number is the whole
%   number of days from that origin and the seconds of day are the remainder,
%   both taken with datetime arithmetic rather than through datenum: a datenum
%   near the present resolves only about 10 us, which would destroy the
%   precision the epoch type exists to keep.
%
%   An unzoned datetime carries no claim about its scale, so the caller states
%   it. A zoned datetime does carry one - it is civil time, hence UTC - so it
%   is converted to UTC and any scale other than "UTC" is refused rather than
%   silently reinterpreted.
%
%   The scale is required and has no default. A default would be a guess, and
%   handing a UTC timetable to a TT-expecting routine is exactly the class of
%   bug the scale field was introduced to remove.
%
% ACCURACY
%   MATLAB datetime resolves about 1 ns over the range of interest, so the
%   conversion is exact at the level this toolbox works at but does not reach
%   the 1.5e-11 s resolution of daySecondToEpoch. datetime knows nothing about
%   leap seconds, so a UTC instant inside a positive leap second cannot be
%   expressed here at all; use daySecondToEpoch for that.
%
% ERRORS
%   referenceSystem:datetimeToEpoch:zonedScaleMismatch
%   referenceSystem:timeScale:unknownScale
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1.
%   ITU-R TF.460-6 (UTC and leap seconds).
%
% EXAMPLE
%   epoch = referenceSystem.datetimeToEpoch(datetime(2024,1,1,12,0,0), "TT");
%   assert(epoch.sec == 43200);
%
% KEYWORDS
%   epoch, datetime, MJD, time zone, UTC
%
% See also MJDTOEPOCH, DAYSECONDTOEPOCH, EPOCHTO.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        t (:,:) datetime {mustBeNonempty}
        scale (1,1) string
    end

    scaleInfo = referenceSystem.timeScale(scale);
    t = t(:);

    if ~isempty(t.TimeZone)
        if scaleInfo.name ~= "UTC"
            error('referenceSystem:datetimeToEpoch:zonedScaleMismatch', ...
                ['A zoned datetime is civil time and therefore UTC, but the ', ...
                'scale given is %s. Strip the time zone if the instants are ', ...
                'really %s.'], scaleInfo.name, scaleInfo.name);
        end
        t.TimeZone = 'UTC';
        t.TimeZone = '';
    end

    % MJD 0 = 1858-11-17 00:00, by definition. epochTo carries the same origin
    % for the inverse direction and a precision test binds the two together.
    modifiedJulianDateOrigin = datetime(1858, 11, 17, 0, 0, 0);
    elapsed = t - modifiedJulianDateOrigin;
    day = floor(days(elapsed));

    epoch = referenceSystem.normalizeEpoch(struct( ...
        'day', day, ...
        'sec', seconds(elapsed - days(day)), ...
        'scale', scaleInfo.name, ...
        'source', "datetimeToEpoch"));
end
