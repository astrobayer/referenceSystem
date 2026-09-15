function result = leapSecondTable(command, argument)
%LEAPSECONDTABLE The single leap-second authority of the toolbox.
%
%   deltaAt   = leapSecondTable("deltaAT", epoch)   TAI - UTC per epoch, seconds
%   table     = leapSecondTable("list")             the full step table
%   table     = leapSecondTable("load", file)       install a session override
%   table     = leapSecondTable("reset")            drop the override
%   firstDate = leapSecondTable("validFrom")        start of the coverage
%   firstDay  = leapSecondTable("validFromDay")     the same instant, as an MJD
%   lastDate  = leapSecondTable("validThrough")     end of the coverage
%   lastDay   = leapSecondTable("validThroughDay")  the same instant, as an MJD
%   state     = leapSecondTable("state")            which table is in force
%
%   No other file in this toolbox contains a leap-second value or date. v1
%   carried three independent hardcoded tables, all frozen at 2017-01-01 and
%   free to diverge, which is finding M-2; a contract test now greps the source
%   tree for the pattern and fails if a fourth appears.
%
% INPUT ARGUMENTS
%   Name       Size   Type            Units  Description
%   ----       ----   ----            -----  -----------
%   command    1x1    string | char   -      One of the commands listed above.
%   argument   1x1    struct          -      For "deltaAT": the UTC epoch.
%              1x1    string | char   -      For "load": the file to read.
%                                            Not accepted by other commands.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type        Units  Description
%   ----                ----   ----        -----  -----------
%   result              Nx1    double      s      "deltaAT": TAI - UTC.
%                       Mx2    timetable   -      "list", "load", "reset": the
%                                                 step table, row times the UTC
%                                                 instant each step takes
%                                                 effect, variables mjd (the
%                                                 same instant as an integer
%                                                 MJD) and deltaAt (seconds).
%                       1x1    datetime    -      "validFrom", "validThrough".
%                       1x1    double      d      "validFromDay",
%                                                 "validThroughDay": the same
%                                                 two instants as integer MJD.
%                       1x1    struct      -      "state", fields below.
%   .source             1x1    string      -      "SOFA iauDat" or the override
%                                                 file that replaced it.
%   .stepCount          1x1    double      -      Rows in the active table.
%   .lastChange         1x1    datetime    -      Most recent step.
%   .lastDeltaAt        1x1    double      s      TAI - UTC after that step.
%   .validThrough       1x1    datetime    -      As the command of that name.
%
% METHOD
%   The table is not stored here. It is discovered by asking the bundled,
%   unmodified SOFA iauDat through the MEX gateway for TAI - UTC on every day
%   from 1972-01-01 to 2200-01-01 and recording where the answer changes. There
%   is therefore exactly one copy of the data in the toolbox, in mex/sofa/dat.c,
%   and updating SOFA updates the toolbox with no MATLAB edit at all. The scan
%   is about 83000 iauDat evaluations in one vectorised call, takes a few
%   milliseconds and is cached in a persistent variable for the session.
%
%   The coverage end date of the SOFA table is discovered the same way: iauDat
%   flags a year more than five years beyond its own release with status +1,
%   and validThrough is the day before the first such day. It is not a literal
%   here either.
%
%   EACH COVERAGE BOUND IS PUBLISHED TWICE, AS A DATE AND AS A DAY NUMBER, and
%   the second form is not a convenience. Consumers compare a bound against
%   epoch.day, which is an MJD, so a date-only bound forces every one of them to
%   write days(bound - datetime(1858, 11, 17)) - and that is the MJD epoch,
%   copied out of this file into theirs. Four such copies had accumulated by
%   rev. 1.215, one of them in package code, which is the same shape as finding
%   M-2 one layer down: a constant with no single owner, free to diverge, and
%   invisible to the contract test that greps for leap-second dates because
%   1858-11-17 is not one. The day numbers cost nothing to hand back - both are
%   already cached, one by localScanSofaTable and one by localColumnsOf - and
%   they are what removes the copies.
%
%   AN OVERRIDE MOVES BOTH BOUNDS WHERE IT STATES THEM. validFrom follows the
%   active table's first row. validThrough is the day before the expiry a
%   leap-seconds.list states on its "#@" line, because that is how far its
%   publisher vouches for it; a two-column table states no expiry and keeps
%   the coverage of the bundled SOFA release. "reset" restores both.
%
%   TRAP, measured against SOFA 20231011 and the reason this function
%   range-checks rather than trusting the status. iauDat answers a pre-1960
%   date with status +1 - a warning, not an error - and leaves TAI - UTC at
%   zero. A layer that applied section C.6 mechanically would turn that into a
%   warning and hand back a silent zero. UTC before 1972-01-01 is a rate-based
%   fractional offset that this toolbox's integer-second machinery does not
%   model, so such an epoch is an error here, named as such.
%
%   Section C.6 otherwise applies unchanged: status +1 from a supported epoch
%   becomes one aggregated dubiousYear warning per call, whatever N is, and a
%   negative status becomes an error naming the offending epochs. No numeric
%   status is ever returned.
%
%   Concurrency, section C.9 rule 1. The override lives in a persistent
%   variable, so it lives in the memory of the process that installed it and is
%   invisible inside a parfor worker, which would silently fall back to the
%   SOFA table. Install the override inside the parfor body, or pass the table
%   in as sliced data. leapSecondTable("state") reports which table answered.
%
%   THE COLUMNS "deltaAT" READS ARE DERIVED ONCE, NOT PER CALL (prompt P28b,
%   rev. 1.122). The step days, the offsets, the discretize edges, the date of
%   the first row and the coverage end AS A DAY NUMBER are all fixed for the
%   life of the active table, and are computed when that table is installed:
%   after the SOFA scan, after "load" and after "reset". A profiled single-epoch
%   rotation reached this function six times, four of them on "deltaAT", and
%   each of those four built a datetime for 1858-11-17, subtracted it, called
%   days and floored the result to recover a number the scan already knew, then
%   indexed the timetable three times for columns that had not changed.
%
%   The cache is not an optimisation of the lookup: the lookup was already one
%   discretize on integer day numbers. It removes work that was never a function
%   of the epoch. It cannot go stale, because the only three ways the active
%   table can change are the three places the columns are refreshed, and an
%   override that fails to load leaves both the table and the columns as they
%   were.
%
% ACCURACY
%   Exact. TAI - UTC is an integer number of seconds from 1972-01-01 onward and
%   is returned as such. The only inexactness anywhere near this function is
%   the day-boundary lookup, which is exact because a step always occurs at 0h
%   UTC and the lookup is on the integer day number.
%
% ERRORS
%   referenceSystem:leapSecondTable:gatewayMissing
%   referenceSystem:leapSecondTable:beforeUtcEpoch
%   referenceSystem:leapSecondTable:wrongScale
%   referenceSystem:leapSecondTable:unacceptableDate
%   referenceSystem:leapSecondTable:missingArgument
%   referenceSystem:leapSecondTable:unsupportedFormat
%   referenceSystem:leapSecondTable:unreadableFile
%   MATLAB:validators:mustBeMember
%
% WARNINGS
%   referenceSystem:leapSecondTable:dubiousYear   One per call, however large N is.
%       Raised beyond validThrough: from 2029-01-01 on the bundled SOFA
%       release, because iauDat flags any year more than five beyond its own
%       IYV, or beyond the expiry of a loaded leap-seconds.list. Loading a
%       newer leap-seconds.list moves it.
%
% REFERENCES
%   IAU SOFA release 20231011, iauDat (mex/sofa/dat.c).
%   ITU-R TF.460-6, Standard-frequency and time-signal emissions.
%   IERS Bulletin C; IERS/IANA leap-seconds.list (NTP format).
%   Handover finding M-2, decision D3 and sections C.6 and C.9.
%
% EXAMPLE
%   epoch = referenceSystem.daySecondToEpoch([57754 0], "UTC");
%   assert(referenceSystem.leapSecondTable("deltaAT", epoch) == 37);
%   steps = referenceSystem.leapSecondTable("list");
%
% KEYWORDS
%   leap second, TAI, UTC, deltaAT, iauDat, IERS Bulletin C, override
%
% See also CONVERTTIMESCALE, NORMALIZEEPOCH, MEXINFO.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        command (1,1) string {mustBeMember(command, ...
            ["deltaAT", "list", "load", "reset", "validFrom", "validFromDay", ...
            "validThrough", "validThroughDay", "state"])}
        argument = []
    end

    persistent cachedTable cachedValidThroughDay ...
        overrideTable overrideSource overrideValidThroughDay activeColumns

    % The SOFA table is discovered once per session and then reused. It is
    % needed even when an override is installed: a table that states no expiry
    % keeps the SOFA coverage, and "reset" returns to it.
    if isempty(cachedTable)
        [cachedTable, ~, cachedValidThroughDay] = ...
            localScanSofaTable();
        activeColumns = [];
    end

    % THE DERIVED COLUMNS ARE CACHED AND THE CACHE IS A MEASURED DECISION
    % (prompt P28b, rev. 1.122). Profiled, one single-epoch rotationItrsToGcrs
    % reached this function six times, four of them on "deltaAT", and each of
    % those four rebuilt a datetime for 1858-11-17, subtracted it, called days
    % and floored the result - to recover a day number that has not changed
    % since the table was scanned - and then indexed the timetable three times
    % for columns that are fixed for the life of the active table. The profile
    % counted 5 datetime constructions, 5 datetime subtractions and 14 tabular
    % dot-references per rotation. None of that is a function of the epoch.
    %
    % The refresh points are the three places the ACTIVE table can change: the
    % SOFA scan above, "load" and "reset". The isempty guard below is the net,
    % not the mechanism, and it costs one isempty on a struct. Each refresh
    % happens LAST, after the table it derives from has been assigned, so a
    % failure part way through leaves the previous columns in place rather than
    % a set derived from a table that was never installed.
    if isempty(activeColumns)
        if isempty(overrideTable)
            activeColumns = localColumnsOf(cachedTable, cachedValidThroughDay);
        else
            activeColumns = localColumnsOf(overrideTable, overrideValidThroughDay);
        end
    end

    switch command
        case "load"
            if isempty(argument)
                error('referenceSystem:leapSecondTable:missingArgument', ...
                    'The "load" command needs a file name.');
            end
            [loadedTable, expiryDay] = localReadOverrideFile(string(argument));
            if isnan(expiryDay)
                expiryDay = cachedValidThroughDay;
            end
            overrideTable = loadedTable;
            overrideSource = string(argument);
            overrideValidThroughDay = expiryDay;
            activeColumns = localColumnsOf(overrideTable, overrideValidThroughDay);
            result = overrideTable;

        case "reset"
            overrideTable = [];
            overrideSource = [];
            overrideValidThroughDay = [];
            activeColumns = localColumnsOf(cachedTable, cachedValidThroughDay);
            result = cachedTable;

        case "list"
            result = localActiveTable(cachedTable, overrideTable);

        case "validFrom"
            % THE ACTIVE COLUMNS, NOT THE SOFA SCAN. An override installed with
            % "load" moves this bound, and interpolateEop trims to it.
            result = activeColumns.firstDate;

        case "validFromDay"
            result = activeColumns.mjd(1);

        case "validThrough"
            result = activeColumns.validThrough;

        case "validThroughDay"
            result = activeColumns.validThroughDay;

        case "state"
            activeTable = localActiveTable(cachedTable, overrideTable);
            source = "SOFA iauDat";
            if ~isempty(overrideTable)
                source = "override: " + overrideSource;
            end
            result = struct( ...
                'source', source, ...
                'stepCount', height(activeTable), ...
                'lastChange', activeTable.Time(end), ...
                'lastDeltaAt', activeTable.deltaAt(end), ...
                'validThrough', activeColumns.validThrough);

        case "deltaAT"
            result = localDeltaAt(argument, activeColumns);
    end
end

% =========================== local functions ===========================

function columns = localColumnsOf(activeTable, validThroughDay)
%LOCALCOLUMNSOF The plain arrays localDeltaAt needs, taken out of the timetable.
%   Everything here is fixed for the life of the active table: the step days,
%   the offsets, the discretize edges, the date of the first row, which the
%   beforeUtcEpoch message prints, and the coverage end as a day and a date.
    stepDay = activeTable.mjd;
    columns = struct( ...
        'mjd', stepDay, ...
        'deltaAt', activeTable.deltaAt, ...
        'edges', [stepDay; Inf], ...
        'firstDate', activeTable.Time(1), ...
        'validThroughDay', validThroughDay, ...
        'validThrough', localDatetimeOfMjd(validThroughDay));
end

function activeTable = localActiveTable(cachedTable, overrideTable)
%LOCALACTIVETABLE The override if one is installed, otherwise the SOFA table.
    if ~isempty(overrideTable)
        activeTable = overrideTable;
    else
        activeTable = cachedTable;
    end
end

function deltaAt = localDeltaAt(epochIn, columns)
%LOCALDELTAAT TAI - UTC for each entry of a UTC epoch.
%   The lookup is on the integer day number alone. A step takes effect at 0h
%   UTC, so TAI - UTC is constant across a UTC day, and a day-based lookup is
%   therefore exact and - unlike a lookup on the decimal MJD - gives the
%   pre-step value throughout a positive leap second, which is finding C-3.
%
%   columns holds the step days, the offsets, the discretize edges, the date
%   of the first row and the coverage end, all derived once when the active
%   table was installed, so no datetime arithmetic happens on the normal path.
    if isempty(epochIn) || ~isstruct(epochIn)
        error('referenceSystem:leapSecondTable:missingArgument', ...
            'The "deltaAT" command needs a UTC epoch struct.');
    end

    epoch = referenceSystem.normalizeEpoch(epochIn);
    if epoch.scale ~= "UTC"
        error('referenceSystem:leapSecondTable:wrongScale', ...
            ['TAI - UTC is defined for a UTC epoch; this one is %s. ', ...
            'Converting it here would hide which scale the caller meant.'], ...
            epoch.scale);
    end

    tooEarly = epoch.day < columns.mjd(1);
    if any(tooEarly)
        error('referenceSystem:leapSecondTable:beforeUtcEpoch', ...
            ['%d of %d epochs precede %s, where UTC is a rate-based ', ...
            'fractional offset that this toolbox does not model; index %d ', ...
            'is the first, at day %d. Note that SOFA iauDat answers such a ', ...
            'date with a warning and a zero, not with an error.'], ...
            sum(tooEarly), numel(tooEarly), ...
            string(columns.firstDate, 'yyyy-MM-dd'), ...
            find(tooEarly, 1), epoch.day(find(tooEarly, 1)));
    end

    index = discretize(epoch.day, columns.edges);
    deltaAt = columns.deltaAt(index);

    dubious = epoch.day > columns.validThroughDay;
    if any(dubious)
        first = find(dubious, 1);
        last = find(dubious, 1, 'last');
        warning('referenceSystem:leapSecondTable:dubiousYear', ...
            ['%d of %d epochs lie beyond %s, the coverage of the active ', ...
            'leap-second table; the first is index %d at day %d and the ', ...
            'last is index %d at day %d. Leap seconds cannot be predicted, ', ...
            'so a step announced after the table was built would make these ', ...
            'values wrong by one second. Load a newer IERS leap-seconds.list, ', ...
            'whose expiry sets the coverage, with leapSecondTable("load", ', ...
            'file), or suppress this identifier.'], ...
            sum(dubious), numel(dubious), string(columns.validThrough, 'yyyy-MM-dd'), ...
            first, epoch.day(first), last, epoch.day(last));
    end
end

function [stepTable, validThrough, validThroughDay] = localScanSofaTable()
%LOCALSCANSOFATABLE Discover the SOFA leap-second table by evaluating iauDat.
%   The scan window is a search domain, not data: it starts before any leap
%   second could exist and ends well beyond any plausible use, and the table is
%   whatever iauDat reports inside it.
%
%   The coverage end is returned BOTH as a date and as a day number. The scan
%   already holds the day number; returning only the date meant every deltaAT
%   call converted it back, which is the cost prompt P28b removed.
    scanFirstDay = localMjdOfDatetime(datetime(1972, 1, 1));
    scanLastDay = localMjdOfDatetime(datetime(2200, 1, 1));
    day = (scanFirstDay:scanLastDay)';

    [deltaAt, status] = localCallGateway(day);

    if any(status < 0)
        first = find(status < 0, 1);
        error('referenceSystem:leapSecondTable:unacceptableDate', ...
            ['SOFA iauDat rejected day %d during the leap-second scan with ', ...
            'code %d. The bundled SOFA source may be damaged.'], ...
            day(first), status(first));
    end

    isStep = [true; diff(deltaAt) ~= 0];
    stepDay = day(isStep);
    stepValue = deltaAt(isStep);

    stepTable = timetable(localDatetimeOfMjd(stepDay), stepDay, stepValue, ...
        'VariableNames', {'mjd', 'deltaAt'});

    lastGood = find(status == 0, 1, 'last');
    validThroughDay = day(lastGood);
    validThrough = localDatetimeOfMjd(validThroughDay);
end

function [deltaAt, status] = localCallGateway(day)
%LOCALCALLGATEWAY The only call to the MEX gateway in the whole toolbox.
%   Seam contract S1 item 2: every consumer of leap seconds reaches the table
%   through this function, so the override is observed everywhere by
%   construction rather than by discipline. A static test asserts that no other
%   package file mentions the 'dat' command.
    try
        [deltaAt, status] = mexGateway('dat', day, zeros(size(day)));
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:leapSecondTable:gatewayMissing', ...
                ['The MEX gateway is not built, so the leap-second table ', ...
                'cannot be read. Run referenceSystem.buildMex once.']);
        end
        rethrow(cause);
    end
end

function [stepTable, validThroughDay] = localReadOverrideFile(fileName)
%LOCALREADOVERRIDEFILE Read a session override from a leap-second file.
%   Two formats are accepted: the IERS and IANA leap-seconds.list, whose data
%   lines carry the NTP time stamp of the step and the TAI - UTC that follows
%   it and whose "#@" line carries the NTP time stamp of its expiry, and a
%   plain two-column text table of [dayNumber deltaAt]. validThroughDay is the
%   day before that expiry, or NaN when the file states none. IERS Bulletin
%   C is deliberately not parsed: it is prose that announces a step rather than
%   a table, and a parser for it would be a guessing machine of the kind
%   finding M-1 warns about. Convert it to either accepted format instead.
    if ~isfile(fileName)
        error('referenceSystem:leapSecondTable:unreadableFile', ...
            'Cannot read the leap-second file "%s".', fileName);
    end

    fileText = string(fileread(fileName));
    line = strtrim(split(fileText, newline));
    ntpEpochDay = 15020;
    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    validThroughDay = NaN;
    expiry = line(startsWith(line, "#@"));
    if ~isempty(expiry)
        stamp = sscanf(char(extractAfter(expiry(1), "#@")), '%f', 1);
        if ~isempty(stamp)
            validThroughDay = floor(stamp/secondsPerDay + ntpEpochDay) - 1;
        end
    end
    line = line(strlength(line) > 0 & ~startsWith(line, "#"));

    if isempty(line)
        error('referenceSystem:leapSecondTable:unsupportedFormat', ...
            ['"%s" holds no data lines. Expected a leap-seconds.list file ', ...
            'or a two-column [dayNumber deltaAt] table.'], fileName);
    end

    value = zeros(numel(line), 2);
    for k = 1:numel(line)
        token = sscanf(char(line(k)), '%f %f', 2);
        if numel(token) ~= 2
            error('referenceSystem:leapSecondTable:unsupportedFormat', ...
                ['Line %d of "%s" is not two numbers. Expected a ', ...
                'leap-seconds.list file or a two-column table.'], k, fileName);
        end
        value(k,:) = token(:)';
    end

    % A leap-seconds.list stamp counts seconds from 1900-01-01, which is
    % MJD 15020 by definition of the NTP epoch. Anything that large cannot be
    % a day number, so the two formats are told apart by magnitude rather than
    % by a flag the caller could get wrong.
    isNtpFormat = all(value(:,1) > 1e6);
    if isNtpFormat
        stepDay = value(:,1)/secondsPerDay + ntpEpochDay;
    else
        stepDay = value(:,1);
    end

    if any(mod(stepDay, 1) ~= 0)
        error('referenceSystem:leapSecondTable:unsupportedFormat', ...
            ['Step dates in "%s" are not whole days; a leap second always ', ...
            'takes effect at 0h UTC.'], fileName);
    end

    [stepDay, order] = sort(stepDay);
    stepValue = value(order, 2);
    stepTable = timetable(localDatetimeOfMjd(stepDay), stepDay, stepValue, ...
        'VariableNames', {'mjd', 'deltaAt'});
end

function day = localMjdOfDatetime(t)
%LOCALMJDOFDATETIME Integer day number of a calendar date. MJD 0 = 1858-11-17.
%   The origin is formed in one place since rev. 1.230: modifiedJulianDateOrigin.
    day = floor(days(t - modifiedJulianDateOrigin()));
end

function t = localDatetimeOfMjd(day)
%LOCALDATETIMEOFMJD Calendar date of an integer day number.
    t = modifiedJulianDateOrigin() + days(day);
end
