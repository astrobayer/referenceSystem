function epochOut = convertTimeScale(epochIn, scaleOut, options)
%CONVERTTIMESCALE Convert an epoch between any two supported time scales.
%
%   epochOut = convertTimeScale(epochIn, scaleOut)
%   epochOut = convertTimeScale(epochIn, scaleOut, Name, Value)
%
%   Supported scales are TAI, TT, TDB, TCG, TCB, UTC, UT1, GPS, GST, BDT and
%   GLONASS. This is the single point of access for time in the toolbox; with
%   the namespace in place, referenceSystem.convertTimeScale is already that,
%   and no convenience wrapper is provided (design principle 12).
%
% INPUT ARGUMENTS
%   Name       Size   Type            Units  Description
%   ----       ----   ----            -----  -----------
%   epochIn    1x1    struct          -      Epoch struct, N entries.
%   scaleOut   1x1    string | char   -      Target scale, any case.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size        Type     Default  Description
%   ----         ----        ----     -------  -----------
%   DeltaUt1     1x1 | Nx1   double   none     UT1 - UTC in seconds, the IERS
%                                              quantity written Delta UT1.
%                                              Scalar or one value per epoch.
%                                              Used only when UT1 is the source
%                                              or the target scale. OMITTING IT
%                                              THERE MEANS ZERO AND WARNS: zero
%                                              can be wrong by up to 0.9 s,
%                                              which is 15 arcseconds of Earth
%                                              rotation, and nothing in the
%                                              result shows it. Pass an
%                                              explicit 0 to accept zero
%                                              silently. See WARNINGS.
%   Observer     3x1 | 3xN   double   [0;0;0]  Observer position in the ITRS,
%                                              metres, one column per epoch or
%                                              one for all. Used only when TDB
%                                              or TCB is the source or the
%                                              target scale. The default is the
%                                              geocentre, for which the
%                                              topocentric terms vanish exactly.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type      Units  Description
%   ----       ----   ----      -----  -----------
%   epochOut   1x1    struct    -      Epoch struct, N entries, in scaleOut.
%   .source    1x1    string    -      "convertTimeScale from <scaleIn>".
%
% METHOD
%   Hub and spoke through TAI, as in v1, because that design was right: every
%   scale has exactly one defined relation to TAI, so eleven scales need eleven
%   relations rather than fifty-five, and a new scale costs one function arm.
%
%     TT   = TAI + 32.184 s                                   exact, defining
%     GPS  = TAI - 19 s,  GST = GPS,  BDT = TAI - 33 s        see ACCURACY
%     UTC  = TAI - Delta AT                                   leapSecondTable
%     UT1  = UTC + Delta UT1                                  measured, IERS
%     GLONASS = UTC + 3 h                                     defining
%     TCG  = TT  + L_G/(1 - L_G)*(TT - T0)                    IAU 2000 B1.9
%     TDB  = TT  + (TDB - TT)                                 SOFA iauDtdb
%     TCB  = TDB + L_B/(1 - L_B)*(TDB - T0) - TDB0/(1 - L_B)  IAU 2006 B3
%
%   with T0 the instant 1977-01-01T00:00:32.184 TAI, taken from iersConstants
%   rather than restated here.
%
%   Finding C-1, and why the v1 TDB series is gone rather than repaired. The v1
%   fbSeries table was numerically corrupted: amplitudes stood in SOFA order
%   while frequencies and phases were misaligned from the second row onward,
%   several rows were duplicated and the T-polynomial groups were absent. Its
%   claimed accuracy of 2 ns was wrong by three orders of magnitude - measured
%   against SOFA, the table is in error by up to 1.7e-4 s over 2020 to 2024.
%   TDB - TT is now obtained from the unmodified SOFA iauDtdb through the MEX
%   gateway, and the regression test asserts agreement with the published
%   Astronomical Almanac approximation to better than 3e-5 s, a tolerance that
%   the corrupted table fails by a wide margin.
%
%   TDB to TT inverts that relation by evaluating iauDtdb at the TDB argument
%   instead of at the TT one. SOFA states the argument may be either; the two
%   differ by at most 1.7 ms and the rate of TDB - TT is below 3e-8, so the
%   inversion error stays under 1e-10 s and no iteration is needed.
%
%   Finding C-3, and why UTC survives a leap second. TAI - UTC is looked up on
%   the integer day number, never on a decimal MJD, so it keeps its pre-step
%   value throughout the leap second. In the other direction the UTC day is
%   found by trying the TAI day first and stepping back one day when the
%   seconds go negative, which lands an instant inside the leap second on the
%   preceding day with a seconds-of-day value at or above 86400 - the one
%   representation that exists for it. UTC to TAI to UTC across
%   2016-12-31T23:59:60 is therefore the exact identity, and a regression test
%   asserts it.
%
%   GLONASS cannot represent the leap second at all: it runs three hours ahead
%   of UTC, so the inserted second falls in the middle of a GLONASS day where
%   the day-and-second form has no room for it. Converting such an instant to
%   GLONASS is an error rather than a silent collision with the second before.
%
% ACCURACY
%   TT, GPS, BDT, TCG, TCB and the TAI hub are exact to the resolution of the
%   epoch, about 1.5e-11 s: every offset is a defining constant and every
%   operation is a single addition inside the seconds field.
%
%   TDB - TT carries the accuracy of SOFA iauDtdb, which reproduces the
%   Fairhead and Bretagnon series to a few nanoseconds at the geocentre. With
%   Observer left at the geocentre the topocentric terms vanish identically, so
%   that value is exact for a geocentric epoch rather than an approximation of
%   one.
%
%   THE TOPOCENTRIC TERM IS NOT SMALL AND ITS SIZE IS MEASURED, NOT QUOTED.
%   Swept over one day at MJD 60000 with iauDtdb through the gateway, a station
%   on the equator departs from the geocentric value by -1.990e-6 to +1.992e-6 s
%   - about 4 us peak to peak, three orders above the series' own accuracy. A
%   station at the pole shows 5.8e-9 s peak to peak about a constant offset of
%   -7.7e-7 s, because the diurnal term is proportional to the distance from the
%   spin axis and vanishes there while the term in the distance north of the
%   equator does not. Anything correlating a clock at a station, and any
%   GRACE-like KBR or LRI reduction, needs Observer set.
%
%   THE UT1 FRACTION iauDtdb ASKS FOR IS OBTAINED HERE FROM UTC PLUS DeltaUt1,
%   AND THE COST OF GETTING IT WRONG IS BOUNDED RATHER THAN ASSUMED. The
%   topocentric term is diurnal with an amplitude of 2 us, so its rate is
%   1.5e-10 s per second of UT error; taking DeltaUt1 as zero, an error of at
%   most 0.9 s, moves TDB - TT by at most 1.3e-10 s. That is below the series'
%   own few-nanosecond accuracy, so DeltaUt1 is used when supplied and its
%   absence is not an error.
%
%   UTC is exact given the leap-second table; see leapSecondTable for the coverage
%   of that table and for the warning raised beyond it. UT1 is exact given
%   Delta UT1, whose own accuracy is that of the IERS series supplied, of order
%   10 us for the C04 product and 20 to 30 us for a prediction.
%
%   GST = GPS and BDT = TAI - 33 s are nominal, not realised. The broadcast
%   system times differ from these definitions at the few-nanosecond to
%   few-tens-of-nanosecond level, and the offsets are themselves broadcast
%   quantities. Anything that needs the realised offset must apply it
%   separately; this function returns the definitional value.
%
% ERRORS
%   referenceSystem:convertTimeScale:sizeMismatch
%   referenceSystem:convertTimeScale:unrepresentableLeapSecond
%   referenceSystem:convertTimeScale:gatewayMissing
%   referenceSystem:convertTimeScale:beforeUtcEpoch
%       Raised by this function when a TAI epoch maps to a UTC day before the
%       leap-second table begins. leapSecondTable raises an identifier of its
%       own name for its own range check; the two are distinct conditions in
%       distinct functions and are catchable separately.
%   referenceSystem:timeScale:unknownScale
%
% WARNINGS
%   referenceSystem:convertTimeScale:deltaUt1Defaulted   Raised once per call
%       when UT1 is the source or the target scale and DeltaUt1 was omitted.
%       The conversion proceeds with zero, and the caller is told what that
%       costs. An EXPLICIT 'DeltaUt1', 0 is a decision and does not warn -
%       decision D67's rule that a consequential physical choice is never
%       silently defaulted, applied here (decision D113).
%   referenceSystem:leapSecondTable:dubiousYear   Raised once per call by
%       leapSecondTable when an epoch lies beyond the table's coverage.
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1 and Table 1.1.
%   IAU 2000 Resolution B1.9 (L_G); IAU 2006 Resolution B3 (L_B, TDB0).
%   IAU SOFA release 20231011, iauDtdb and iauDat.
%   Fairhead, L. and Bretagnon, P., 1990, Astron. Astrophys. 229, 240.
%   Handover findings C-1 and C-3.
%
% EXAMPLE
%   utc = referenceSystem.daySecondToEpoch([57753 86400.5], "UTC");
%   tai = referenceSystem.convertTimeScale(utc, "TAI");
%   back = referenceSystem.convertTimeScale(tai, "UTC");
%   assert(back.day == utc.day && back.sec == utc.sec);
%
% KEYWORDS
%   time scale, TAI, TT, TDB, TCG, TCB, UTC, UT1, GPS, BDT, GLONASS, leap second
%
% See also TIMESCALE, LEAPSECONDS, NORMALIZEEPOCH, EPOCHTO.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:55 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epochIn (1,1) struct
        scaleOut (1,1) string
        % zeros(0, 1) and not []: a (:,1) constraint rejects a 0-by-0 empty
        % (rev. 1.147's finding), and the empty default is what lets an
        % OMITTED DeltaUt1 be told apart from an explicit zero below.
        options.DeltaUt1 (:,1) double {mustBeReal, mustBeFinite} = zeros(0, 1)
        options.Observer (3,:) double {mustBeReal, mustBeFinite} = [0; 0; 0]
    end

    epoch = referenceSystem.normalizeEpoch(epochIn);
    targetScale = referenceSystem.timeScale(scaleOut).name;
    sourceScale = epoch.scale;
    epochCount = numel(epoch.day);

    deltaUt1 = options.DeltaUt1;
    deltaUt1Supplied = ~isempty(deltaUt1);
    if ~deltaUt1Supplied
        deltaUt1 = 0;
    end
    if isscalar(deltaUt1)
        deltaUt1 = repmat(deltaUt1, epochCount, 1);
    elseif numel(deltaUt1) ~= epochCount
        error('referenceSystem:convertTimeScale:sizeMismatch', ...
            ['DeltaUt1 must be scalar or hold one value per epoch; it holds ', ...
            '%d values for %d epochs.'], numel(deltaUt1), epochCount);
    end

    if sourceScale == targetScale
        epochOut = epoch;
        epochOut.source = "convertTimeScale from " + sourceScale;
        return
    end

    % A UT1 CONVERSION WITH NO DeltaUt1 IS NOT REFUSED, BUT IT IS NOT SILENT
    % EITHER (decision D113). Delta UT1 is a measured quantity that reaches
    % +/-0.9 s; taken as zero it moves the epoch by up to 15 arcseconds of
    % Earth rotation - hundreds of metres at the surface - and the result
    % carries no sign of it. D67's rule is that a consequential physical
    % choice is never silently defaulted: an explicit 'DeltaUt1', 0 is a
    % decision and passes quietly, an omission warns once, after the
    % same-scale early return because no conversion means nothing was assumed.
    if ~deltaUt1Supplied && (sourceScale == "UT1" || targetScale == "UT1")
        warning('referenceSystem:convertTimeScale:deltaUt1Defaulted', ...
            ['A UT1 conversion was requested and DeltaUt1 was not given, so ', ...
            'UT1 - UTC is taken as ZERO. The true value reaches +/-0.9 s, ', ...
            'which is 15 arcseconds of Earth rotation. Pass DeltaUt1 from ', ...
            'an interpolated EOP series (interpolateEop returns it as ', ...
            '.dut1), or pass an explicit 0 to accept zero silently. If ', ...
            'this call was made on your behalf by another function that ', ...
            'received a UT1-tagged epoch, convert that epoch to UTC or ', ...
            'TAI deliberately, with your DeltaUt1, before handing it on.']);
    end

    observer = localObserverTerms(options.Observer, epoch, deltaUt1, epochCount);

    tai = localToTai(epoch, deltaUt1, observer);
    epochOut = localFromTai(tai, targetScale, deltaUt1, observer);
    epochOut.source = "convertTimeScale from " + sourceScale;
end

% =========================== local functions ===========================

function tai = localToTai(epoch, deltaUt1, observer)
%LOCALTOTAI Move any supported scale onto the TAI hub.
    constants = referenceSystem.iersConstants();

    switch epoch.scale
        case "TAI"
            tai = epoch;
        case "TT"
            tai = localShift(epoch, -constants.ttMinusTai, "TAI");
        case {"GPS", "GST"}
            tai = localShift(epoch, -constants.gpsMinusTai, "TAI");
        case "BDT"
            tai = localShift(epoch, -constants.bdtMinusTai, "TAI");
        case "UTC"
            tai = localUtcToTai(epoch);
        case "GLONASS"
            utc = localShift(epoch, -3*3600, "UTC");
            tai = localUtcToTai(utc);
        case "UT1"
            utc = localShift(epoch, -deltaUt1, "UTC");
            tai = localUtcToTai(utc);
        case "TCG"
            tt = localShift(epoch, ...
                -constants.lg*localSecondsFrom1977(epoch, constants), "TT");
            tai = localShift(tt, -constants.ttMinusTai, "TAI");
        case "TDB"
            tt = localShift(epoch, -localTdbMinusTt(epoch, observer), "TT");
            tai = localShift(tt, -constants.ttMinusTai, "TAI");
        case "TCB"
            tdb = localShift(epoch, ...
                -constants.lb*localSecondsFrom1977(epoch, constants) + ...
                constants.tdb0, "TDB");
            tt = localShift(tdb, -localTdbMinusTt(tdb, observer), "TT");
            tai = localShift(tt, -constants.ttMinusTai, "TAI");
    end
end

function epochOut = localFromTai(tai, targetScale, deltaUt1, observer)
%LOCALFROMTAI Move a TAI epoch onto any supported scale.
    constants = referenceSystem.iersConstants();

    switch targetScale
        case "TAI"
            epochOut = tai;
        case "TT"
            epochOut = localShift(tai, constants.ttMinusTai, "TT");
        case {"GPS", "GST"}
            epochOut = localShift(tai, constants.gpsMinusTai, targetScale);
        case "BDT"
            epochOut = localShift(tai, constants.bdtMinusTai, "BDT");
        case "UTC"
            epochOut = localTaiToUtc(tai);
        case "GLONASS"
            utc = localTaiToUtc(tai);
            if any(utc.sec >= constants.secondsPerDay)
                first = find(utc.sec >= constants.secondsPerDay, 1);
                error('referenceSystem:convertTimeScale:unrepresentableLeapSecond', ...
                    ['GLONASS runs three hours ahead of UTC, so an inserted ', ...
                    'leap second falls inside a GLONASS day and has no ', ...
                    'representation in the day-and-second form; index %d is ', ...
                    'such an instant. Keep it in UTC or TAI.'], first);
            end
            epochOut = localShift(utc, 3*3600, "GLONASS");
        case "UT1"
            utc = localTaiToUtc(tai);
            epochOut = localShift(utc, deltaUt1, "UT1");
        case "TCG"
            tt = localShift(tai, constants.ttMinusTai, "TT");
            elapsed = localSecondsFrom1977(tt, constants);
            epochOut = localShift(tt, ...
                constants.lg/(1 - constants.lg)*elapsed, "TCG");
        case "TDB"
            tt = localShift(tai, constants.ttMinusTai, "TT");
            epochOut = localShift(tt, localTdbMinusTt(tt, observer), "TDB");
        case "TCB"
            tt = localShift(tai, constants.ttMinusTai, "TT");
            tdb = localShift(tt, localTdbMinusTt(tt, observer), "TDB");
            elapsed = localSecondsFrom1977(tdb, constants);
            epochOut = localShift(tdb, ...
                constants.lb/(1 - constants.lb)*elapsed - ...
                constants.tdb0/(1 - constants.lb), "TCB");
    end
end

function epochOut = localShift(epoch, offset, scale)
%LOCALSHIFT Add seconds to an epoch and relabel it, in one carry.
%   addSeconds is not reused here: it refuses a leap-bearing scale, which is
%   the right rule for a user offsetting a UTC epoch and the wrong one inside
%   a hub conversion, where the leap second is exactly what is being handled.
%
%   IT CARRIES RATHER THAN NORMALISES, AND THAT IS PROMPT P28b's LARGEST SINGLE
%   ITEM. The epoch reaching here was normalised on entry to convertTimeScale
%   or produced by a previous shift, so its day is already an integer and its
%   fields are already the right types; only sec has moved. The full
%   normalizeEpoch re-ran the field sweep, the type checks and a time-scale
%   registry lookup on every one of them. Profiled, a single-epoch rotation
%   reached this function four times and normalizeEpoch seventeen, and the
%   registry lookup alone was 2.84 us of an 8.13 us call.
%
%   THE LEAP-BEARING FLAG IS DERIVED, NOT PASSED. Every call site here supplies
%   scale as a literal or as a canonical name already taken from the registry,
%   so scale == "UTC" is the same information the registry would return, at one
%   string comparison. It is derived rather than handed in at each site because
%   a wrong flag is a silent one-second error, and a value computed in one place
%   cannot be got wrong at eight.
    [day, sec] = carryEpoch(epoch.day, epoch.sec + offset, scale == "UTC");
    epochOut = struct('day', day, 'sec', sec, 'scale', scale, ...
        'source', epoch.source);
end

function elapsed = localSecondsFrom1977(epoch, constants)
%LOCALSECONDSFROM1977 Seconds from the TCG and TCB origin, in split form.
%   The origin is 1977-01-01T00:00:32.184 TAI expressed in TT, so the day
%   difference is taken first and exactly, and only then are the seconds added.
    originDay = floor(constants.mjdTt1977);
    originSecond = (constants.mjdTt1977 - originDay)*constants.secondsPerDay;
    elapsed = (epoch.day - originDay)*constants.secondsPerDay + ...
        (epoch.sec - originSecond);
end

function observer = localObserverTerms(position, epoch, deltaUt1, epochCount)
%LOCALOBSERVERTERMS Turn an ITRS position into the four arguments iauDtdb takes.
%
%   Empty means the geocentre, and the geocentre is expressed as an EMPTY value
%   rather than as four zero arrays so that the geocentric call reaches the
%   two-argument gateway command it has always reached. Zeros would give the
%   same number through a longer path, and a path only some callers exercise is
%   a path that rots.
%
%   iauDtdb wants the distance from the spin axis and the distance north of the
%   equatorial plane. Those are hypot(x, y) and z of the ITRS vector, and the
%   east longitude is atan2(y, x). No ellipsoid enters: these are cylindrical
%   coordinates of a Cartesian position, not geodetic ones, which is why
%   ellipsoidParameters is not consulted and no ellipsoid can be got wrong here.
%
%   THE UNITS HANDED OVER ARE SI. The kilometres iauDtdb actually wants are
%   applied inside rsCore, so this function and its caller never see them.

    if all(position(:) == 0)
        observer = [];
        return
    end

    if size(position, 2) == 1
        position = repmat(position, 1, epochCount);
    elseif size(position, 2) ~= epochCount
        error('referenceSystem:convertTimeScale:sizeMismatch', ...
            ['Observer must have one column or one column per epoch; it has ', ...
            '%d columns for %d epochs.'], size(position, 2), epochCount);
    end

    % UT1 as a fraction of one day. The epoch is taken to UTC through the
    % GEOCENTRIC path - observer empty - which is not circular: the value used
    % there differs from the topocentric one by at most 2 us, and 2 us of UT
    % moves the topocentric term by 3e-16 s.
    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    utc = localTaiToUtc(localToTai(epoch, deltaUt1, []));
    ut1Second = utc.sec + deltaUt1;

    observer = struct( ...
        'ut', mod(ut1Second, secondsPerDay)/secondsPerDay, ...
        'eastLongitude', atan2(position(2, :).', position(1, :).'), ...
        'axisDistance', hypot(position(1, :).', position(2, :).'), ...
        'equatorDistance', position(3, :).');
end

function value = localTdbMinusTt(epoch, observer)
%LOCALTDBMINUSTT TDB - TT in seconds from SOFA iauDtdb through the gateway.
    try
        if isempty(observer)
            value = mexGateway('dtdb', epoch.day, epoch.sec);
        else
            value = mexGateway('dtdb', epoch.day, epoch.sec, observer.ut, ...
                observer.eastLongitude, observer.axisDistance, ...
                observer.equatorDistance);
        end
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:convertTimeScale:gatewayMissing', ...
                ['TDB needs SOFA iauDtdb through the MEX gateway, which is ', ...
                'not built. Run referenceSystem.buildMex once.']);
        end
        rethrow(cause);
    end
end

function tai = localUtcToTai(utc)
%LOCALUTCTOTAI TAI from UTC. The lookup is on the day number, so it is exact
%   through a leap second, which is finding C-3.
    deltaAt = referenceSystem.leapSecondTable("deltaAT", utc);
    tai = localShift(utc, deltaAt, "TAI");
end

function utc = localTaiToUtc(tai)
%LOCALTAITOUTC UTC from TAI, including instants inside a leap second.
%   A UTC day D begins at TAI = D*86400 + deltaAt(D). Trying D = the TAI day
%   first and stepping back one day when the seconds go negative therefore
%   places an instant inside a leap second on the preceding day with a
%   seconds-of-day value at or above 86400, which is its only representation.
%   Two discretize lookups on integer day numbers replace the O(N*M) find loop
%   of v1 and are exact, because a step always occurs at 0h UTC.
    secondsPerDay = referenceSystem.iersConstants().secondsPerDay;
    stepTable = referenceSystem.leapSecondTable("list");
    edges = [stepTable.mjd; Inf];

    candidateDay = tai.day;
    index = discretize(candidateDay, edges);
    if any(isnan(index))
        first = find(isnan(index), 1);
        error('referenceSystem:convertTimeScale:beforeUtcEpoch', ...
            ['%d of %d TAI epochs precede the start of the leap-second ', ...
            'table; index %d is the first, at day %d.'], ...
            sum(isnan(index)), numel(index), first, tai.day(first));
    end
    secondOfDay = tai.sec - stepTable.deltaAt(index);

    stepBack = secondOfDay < 0;
    if any(stepBack)
        previousDay = candidateDay(stepBack) - 1;
        previousIndex = discretize(previousDay, edges);
        if any(isnan(previousIndex))
            first = find(isnan(previousIndex), 1);
            error('referenceSystem:convertTimeScale:beforeUtcEpoch', ...
                ['A TAI epoch maps to a UTC day before the leap-second ', ...
                'table begins; day %d.'], previousDay(first));
        end
        candidateDay(stepBack) = previousDay;
        secondOfDay(stepBack) = tai.sec(stepBack) - ...
            stepTable.deltaAt(previousIndex) + secondsPerDay;
    end

    % Same argument as localShift: candidateDay came from an already normalised
    % TAI epoch and is integer by construction, so the carry is all that is
    % needed and the validation would only re-derive what is known.
    [day, sec] = carryEpoch(candidateDay, secondOfDay, true);
    utc = struct('day', day, 'sec', sec, 'scale', "UTC", 'source', tai.source);
end
