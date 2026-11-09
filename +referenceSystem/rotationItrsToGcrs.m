function [R, Rdot, Rddot, info] = rotationItrsToGcrs(epoch, options)
%ROTATIONITRSTOGCRS Terrestrial-to-celestial rotation and its derivatives.
%
%   R = rotationItrsToGcrs(epoch, 'Eop', eop)
%   [R, Rdot] = rotationItrsToGcrs(epoch, 'Eop', eop)
%   [R, Rdot, Rddot, info] = rotationItrsToGcrs(epoch, 'EopFile', file)
%   [R, Rdot] = rotationItrsToGcrs(epoch, 'Interpolant', interpolant)
%
%   Returns the rotation from the International Terrestrial Reference System to
%   the Geocentric Celestial Reference System, and on request its first two
%   time derivatives, which are what a rotating frame demands of velocity and
%   acceleration. The composition is
%
%       R = (W * R3(ERA) * Q)'
%
%   with Q the precession-nutation-bias rotation GCRS to CIRS, R3(ERA) the
%   Earth rotation, and W the polar motion rotation TIRS to ITRS.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries. Any scale; it is
%                                  converted to UTC for the EOP lookup and to
%                                  TT and UT1 for the rotation.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name                   Size  Type      Default        Description
%   ----                   ----  ----      -------        -----------
%   Eop                    1x1   struct    none           Series from readEop.
%   EopFile                1x1   string    none           File to read instead.
%   EopFormat              1x1   string    auto           Format name for
%                                                         EopFile.
%   InterpolationMethod    1x1   string    "lagrange"     Passed to
%                                                         interpolateEop as
%                                                         Method.
%   Interpolant            1x1   struct    none           Panels from
%                                                         earthOrientationInterpolant,
%                                                         instead of a series.
%                                                         Exactly one of Eop,
%                                                         EopFile and
%                                                         Interpolant is
%                                                         required.
%   ApplyTidalCorrections  1x1   logical   true           Add the diurnal and
%                                                         semidiurnal ocean
%                                                         tide and libration
%                                                         terms. Must match
%                                                         an Interpolant's.
%   CipModel               1x1   string    from the data  Frame of the pole
%                                                         offsets. Overrides
%                                                         the series metadata;
%                                                         must match an
%                                                         Interpolant's.
%   Layout                 1x1   string    "pages"        "pages" for 3x3xN,
%                                                         "rows" for the legacy
%                                                         Nx9 form.
%   Derivatives            1x1   double    -1             0, 1 or 2. Overrides
%                                                         the output-count
%                                                         inference; the default
%                                                         -1 means "infer from
%                                                         nargout". See METHOD.
%   DifferenceStep         1x1   double    200            Central-difference
%                                                         step in seconds. The
%                                                         default is measured;
%                                                         see ACCURACY.
%
% OUTPUT ARGUMENTS
%   Name    Size            Type     Units    Description
%   ----    ----            ----     -----    -----------
%   R       3x3xN | Nx9     double   -        Rotation ITRS to GCRS.
%   Rdot    3x3xN | Nx9     double   1/s      First time derivative. EMPTY if
%                                             'Derivatives' suppressed it.
%   Rddot   3x3xN | Nx9     double   1/s^2    Second time derivative. EMPTY if
%                                             'Derivatives' suppressed it.
%   info    1x1             struct   -        Diagnostics, fields below.
%   .path              1x1  string   -        "direct" (series) or
%                                             "interpolated" (panels).
%   .derivativeMethod  1x1  string   -        "none" or "centralDifference".
%   .differenceStep    1x1  double   s        Step actually used, NaN if none.
%   .interpolantResidual
%                      1x1  double   uas      Fit residual of the interpolant,
%                                             NaN on the direct path and for
%                                             an interpolant read from a file.
%   .cipModel          1x1  string   -        Frame the offsets are referred
%                                             to, as used.
%   .tidalCorrections  1x1  logical  -        Whether they were applied.
%   .leapSecondSource  1x1  string   -        From leapSecondTable("state").
%   .epochCount        1x1  double   -        N.
%   .dubiousEpochCount 1x1  double   -        Epochs beyond the leap-second
%                                             table's coverage.
%
% METHOD
%   ONE ROTATION, NO DIRECTION FLAG. The inverse is the transpose, exactly,
%   because R is a product of orthogonal factors: use invertRotation for the
%   matrices or applyRotation(..., 'Inverse', true) to apply it.
%
%   OUTPUTS ARE GATED BY NARGOUT, and the gating reaches the arithmetic. With
%   one output the CIP is evaluated once per epoch; with two or three it is
%   evaluated at t-h, t and t+h, and those three evaluations yield both
%   derivatives. A tilde is not a discard: [R, ~, ~, info] reports nargout 4,
%   so 'Derivatives', 0 exists to get the diagnostics for the price of R.
%
%   RDOT AND RDDOT ARE THE TIME DERIVATIVES OF THE R RETURNED:
%
%       Rdot'  = Wdot R3 Q + W R3dot Q + W R3 Qdot
%       Rddot' = Wddot R3 Q + W R3ddot Q + W R3 Qddot
%                + 2(Wdot R3dot Q + Wdot R3 Qdot + W R3dot Qdot)
%
%   Q and W are differenced on their matrix elements at t-h, t and t+h. R3 is
%   differentiated in closed form, R3dot = omega dR3/dtheta and
%   R3ddot = omega^2 d2R3/dtheta2 + omegadot dR3/dtheta, where the Earth
%   rotation rate is the ERA slope times 1 + d(UT1 - TAI)/dt and omegadot the
%   slope times d2(UT1 - TAI)/dt2, both differenced from the UT1 - TAI of the
%   same three samples. The rate therefore carries the length of day, the
%   zonal tides and the sub-daily tides exactly as the interpolated UT1 does,
%   and nothing from the series' LOD column. Analytic differentiation of the
%   nutation series was rejected because it would need a second copy of
%   SOFA's coefficient tables.
%
%   Term sizes at a 7000 km orbit radius, as a ratio to the Earth rotation
%   rate: precession-nutation Qdot 9.3e-8 (47 um/s); the UT1 rate, excess
%   length of day plus tides, about 2.5e-8 (12.5 um/s), of which the
%   sub-daily tides reach 3.6e-9 (1.8 um/s); polar motion Wdot 2.6e-9
%   (1.3 um/s). In Rddot the sub-daily tides make omegadot reach 3.5e-17
%   rad/s^2, 2.5e-10 m/s^2, and Qddot reaches 1.4e-10 m/s^2 - both at the
%   GRACE accelerometer noise floor, so both are kept.
%
%   THE EOP PIPELINE. On the direct path the series is interpolated once for
%   the whole arc by interpolateEop, at the three sample times per epoch, with
%   its defaults: 4-point Lagrange and the zonal tides removed and restored.
%   With ApplyTidalCorrections true the sub-daily terms from
%   subdailyEopCorrection are added at the same times. On the interpolated
%   path the CIP, the pole and UT1 - UTC come from the Chebyshev panels, which
%   were fitted to that same chain, and no series is read; a series or an
%   interpolation method passed beside an Interpolant is refused.
%
%   LEAP SECONDS. TAI - UTC is taken on each sample's own UTC day, so UT1 - TAI
%   has no step across a leap second and neither does the rate. Panels are
%   indexed by UTC MJD, which the second 23:59:60 does not have, so on the
%   interpolated path a sample inside a leap second - the epoch or either
%   difference shoulder - is refused with insideLeapSecond; the direct path
%   takes it as any other epoch.
%
%   ONE WARNING PER CALL, NAMING THIS FUNCTION. Epochs beyond the coverage of
%   the leap-second table are counted once, the inner leapSecondTable warning
%   is suppressed for the internal conversions, and one aggregated dubiousYear
%   warning is raised. The count is also in info.dubiousEpochCount.
%
%   SINGLE-EPOCH PATH. With N = 1 the outputs are 3x3, because MATLAB drops a
%   trailing singleton dimension, and no vectorised setup is built.
%
% ACCURACY
%   THE DIFFERENCE STEP IS MEASURED. An h-refinement study over twelve epochs
%   from 1990 to 2050 against a validated Romberg reference gives, for the CIP
%   derivatives and the velocity and acceleration they cause at 7000 km:
%
%       h [s]   dX/dt error    d2X/dt2 error   worst velocity   worst accel
%       3000    1.9e-16        4.4e-22         1.3e-09 m/s      5.2e-15 m/s^2
%        600    7.5e-18        1.8e-23         5.3e-11 m/s      5.5e-15 m/s^2
%        200    8.4e-19        2.3e-22         6.0e-12 m/s      5.2e-14 m/s^2
%         60    8.2e-20        1.2e-21         1.0e-11 m/s      5.1e-13 m/s^2
%         10    7.5e-20        6.5e-20         7.4e-11 m/s      1.5e-11 m/s^2
%          1    9.8e-19        4.5e-18         5.3e-10 m/s      1.6e-09 m/s^2
%
%   The O(h^2) region runs from 3000 s to about 200 s and the roundoff plateau
%   of the CIP series (4.5e-18 rad rms in X, 5.2e-17 in Y) begins below 150 s.
%   THE DEFAULT IS h = 200 s, the minimum of the combined error against 1 nm/s
%   and 1e-10 m/s^2; every step from 1 s to 1800 s meets both budgets.
%
%   Rdot against the motion of R itself, logm(R(t-h)' R(t+h))/2h at
%   h = 200 s, at hourly epochs over a day and clear of midnight: 1.1e-16 1/s
%   (7.7e-10 m/s at 7000 km) with the sub-daily tides and 1.05e-16 without,
%   which is that oracle's own floor. Near midnight, within h of a table row,
%   the interpolated pole and UT1 change slope, and the 200 s difference
%   averages across it.
%
%   Reproduction of the SOFA cookbook worked example of 2007-04-05
%   (sofa_pn_c.pdf section 5.5), worst matrix element: 2.6e-15.
%
%   Invariants, independent of h:
%       max |R'R - I|                  1.1e-16
%       max |Rdot' R + R' Rdot|        4.2e-19 rad/s
%
%   Equinox-versus-CIO agreement: 4.4e-16 rad worst element over twelve epochs
%   from 1990 to 2050.
%
%   ABSOLUTE ACCURACY IS SET BY THE EOP. A C04 series carries formal errors of
%   about 30 uas in polar motion and 10 us in Delta UT1, 0.9 to 1.5 mm at the
%   Earth's surface; every algorithmic figure above is far below that.
%
% ERRORS
%   referenceSystem:rotationItrsToGcrs:eopRequired
%   referenceSystem:rotationItrsToGcrs:conflictingEopSource
%   referenceSystem:rotationItrsToGcrs:unknownCipModel
%   referenceSystem:rotationItrsToGcrs:badInterpolant
%   referenceSystem:rotationItrsToGcrs:cipModelMismatch
%   referenceSystem:rotationItrsToGcrs:tidalMismatch
%   referenceSystem:rotationItrsToGcrs:outsideInterpolant
%   referenceSystem:rotationItrsToGcrs:insideLeapSecond
%   referenceSystem:rotationItrsToGcrs:badDifferenceStep
%   referenceSystem:rotationItrsToGcrs:gatewayMissing
%   referenceSystem:interpolateEop:missingValue
%
% WARNINGS
%   referenceSystem:rotationItrsToGcrs:dubiousYear   One per call, when epochs
%       lie beyond the coverage of the leap-second table.
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.
%   IAU SOFA release 20231011, iauXys06a, iauC2ixys, iauEra00, iauSp00,
%     iauPom00.
%   SOFA Tools for Earth Attitude, sofa_pn_c.pdf, section 5.5.
%   Montenbruck, O. and Gill, E., 2000, Satellite Orbits, Sec. 5.3.
%
% EXAMPLE
%   eop = referenceSystem.readEop('eop20c04.txt');
%   utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");
%   [R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop);
%   [rGcrs, vGcrs] = referenceSystem.applyRotation(R, Rdot, rItrs, vItrs);
%   assert(info.path == "direct" && info.derivativeMethod == "centralDifference");
%
% KEYWORDS
%   ITRS, GCRS, ECEF, ECI, Earth rotation, precession, nutation, polar motion,
%   derivative, orbit integration, SOFA
%
% See also CIPCOORDINATES, APPLYROTATION, INVERTROTATION, EARTHROTATIONANGLE,
%   INTERPOLATEEOP, READEOP, EARTHORIENTATIONINTERPOLANT.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:50 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Eop struct = struct([])
        options.EopFile (1,1) string = ""
        options.EopFormat (1,1) string = ""
        options.ApplyTidalCorrections (1,1) logical = true
        options.CipModel (1,1) string = ""
        options.Layout (1,1) string {mustBeMember(options.Layout, ...
            ["pages", "rows"])} = "pages"
        options.Derivatives (1,1) double {mustBeMember( ...
            options.Derivatives, [-1 0 1 2])} = -1
        options.DifferenceStep (1,1) double = 200
        options.InterpolationMethod (1,1) string = ""
        options.Interpolant = []
    end

    useInterpolant = ~isempty(options.Interpolant);
    if useInterpolant
        localCheckInterpolant(options);
    end

    % nargout drives the derivative order by default, and 'Derivatives'
    % overrides it, because nargout cannot tell [R, ~, ~, info] from
    % [R, Rdot, Rddot, info].
    if options.Derivatives >= 0
        derivativeOrder = options.Derivatives;
    else
        derivativeOrder = max(0, min(2, nargout - 1));
    end
    step = options.DifferenceStep;
    if derivativeOrder > 0 && ~(isfinite(step) && step > 0)
        error('referenceSystem:rotationItrsToGcrs:badDifferenceStep', ...
            ['DifferenceStep must be a positive finite number of seconds; ', ...
            'it is %g. The measured optimum is 200 s and every step from ', ...
            '1 s to 1800 s meets the error budget.'], step);
    end

    % An output that was not computed is returned EMPTY, never as a
    % plausible-looking array of the right size.
    Rdot = [];
    Rddot = [];

    if ~useInterpolant
        eop = localResolveEop(options);
    end
    epochUtc = referenceSystem.convertTimeScale(epoch, "UTC");
    epochCount = numel(epochUtc.day);

    [dubiousCount, cleanup] = localBeginDubiousScope(epochUtc);  %#ok<ASGLU>

    % Three sample times per epoch, in one array, so the EOP series is
    % interpolated once for the whole arc rather than three times.
    if derivativeOrder > 0
        offset = [-step, 0, step];
    else
        offset = 0;
    end
    sampleCount = numel(offset);
    sampleUtc = referenceSystem.daySecondToEpoch( ...
        [repmat(epochUtc.day, sampleCount, 1), ...
         reshape(epochUtc.sec + offset, [], 1)], "UTC");

    if useInterpolant
        [cipSampleX, cipSampleY, cipSampleS, sampled] = localSampleInterpolant( ...
            options.Interpolant, sampleUtc);
        cipModelName = string(options.Interpolant.meta.cipModel);
    else
        interpolation = {};
        if options.InterpolationMethod ~= ""
            interpolation = {'Method', options.InterpolationMethod};
        end
        if options.ApplyTidalCorrections
            interpolation = [interpolation, {'Correction', ...
                referenceSystem.subdailyEopCorrection(sampleUtc)}];
        end
        sampled = referenceSystem.interpolateEop(eop, sampleUtc, interpolation{:});
        cipModelName = localResolveCipModelName(options.CipModel, sampled);
    end
    cipModel = localCipModelNumber(cipModelName);

    % UT1 - TAI at every sample, each with the TAI - UTC of its own UTC day, so
    % a difference across a leap second sees no step. The core forms the Earth
    % rotation rate and its change from these.
    ut1MinusTai = reshape(sampled.dut1 - ...
        referenceSystem.leapSecondTable("deltaAT", sampleUtc), epochCount, sampleCount);

    % The sampled quantities as N-by-3, the layout the gateway reads as
    % [t-h | t | t+h]. With no derivative the one sample stands in all three
    % columns; the core does not read the outer two.
    polarX = localThreeColumns(sampled.xp, epochCount, sampleCount);
    polarY = localThreeColumns(sampled.yp, epochCount, sampleCount);
    offsetX = localThreeColumns(sampled.dX, epochCount, sampleCount);
    offsetY = localThreeColumns(sampled.dY, epochCount, sampleCount);
    deltaUt1 = reshape(sampled.dut1, epochCount, sampleCount);
    ut1MinusTai = localThreeColumns(ut1MinusTai, epochCount, sampleCount);

    epochTt = referenceSystem.convertTimeScale(epochUtc, "TT");
    epochUt1 = referenceSystem.convertTimeScale(epochUtc, "UT1", ...
        'DeltaUt1', deltaUt1(:, min(2, sampleCount)));

    % The step is unread with no derivative requested, but the core still
    % validates it as positive, so a placeholder goes in rather than a zero.
    stepArgument = step;
    if derivativeOrder == 0
        stepArgument = max(step, 1);
    end
    argument = {epochTt.day, epochTt.sec, epochUt1.day, epochUt1.sec, ...
        polarX, polarY, offsetX, offsetY, ut1MinusTai, cipModel, stepArgument};
    if useInterpolant
        command = 'dcmcip';
        argument = [argument, {localThreeColumns(cipSampleX, epochCount, sampleCount), ...
            localThreeColumns(cipSampleY, epochCount, sampleCount), ...
            localThreeColumns(cipSampleS, epochCount, sampleCount)}];
    else
        command = 'dcm';
    end

    try
        switch derivativeOrder
            case 0
                R = mexGateway(command, argument{:});
            case 1
                [R, Rdot] = mexGateway(command, argument{:});
            otherwise
                [R, Rdot, Rddot] = mexGateway(command, argument{:});
        end
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:rotationItrsToGcrs:gatewayMissing', ...
                ['The rotation is assembled in C through the MEX gateway, ', ...
                'which is not built. Run referenceSystem.buildMex once.']);
        end
        rethrow(cause);
    end

    if options.Layout == "rows"
        R = localToRows(R);
        if derivativeOrder >= 1
            Rdot = localToRows(Rdot);
        end
        if derivativeOrder >= 2
            Rddot = localToRows(Rddot);
        end
    end

    if nargout >= 4
        info = localInfo(options, useInterpolant, derivativeOrder, step, ...
            cipModelName, epochCount, dubiousCount);
    end
end

% -------------------------------------------------------------------------

function eop = localResolveEop(options)
%LOCALRESOLVEEOP Obtain the EOP series from a struct or from a file.

    hasStruct = ~isempty(options.Eop);
    hasFile = options.EopFile ~= "";

    if hasStruct && hasFile
        error('referenceSystem:rotationItrsToGcrs:conflictingEopSource', ...
            ['Both Eop and EopFile were given. Supply one, so that the ', ...
            'series the rotation was built from is never in question.']);
    end
    if hasStruct
        eop = options.Eop;
        return
    end
    if ~hasFile
        error('referenceSystem:rotationItrsToGcrs:eopRequired', ...
            ['An Earth orientation source is required: pass Eop with the ', ...
            'output of readEop, EopFile with a path, or Interpolant with ', ...
            'the output of earthOrientationInterpolant. There is no ', ...
            'built-in default and no zero fallback, because a rotation ', ...
            'built from zero EOP is wrong by several metres at the surface ', ...
            'and looks entirely healthy.']);
    end
    if options.EopFormat == ""
        eop = referenceSystem.readEop(options.EopFile);
    else
        eop = referenceSystem.readEop(options.EopFile, ...
            'Format', options.EopFormat);
    end
end

% -------------------------------------------------------------------------

function modelName = localResolveCipModelName(override, sampled)
%LOCALRESOLVECIPMODELNAME Frame of the pole offsets: the override, else the data.

    modelName = override;
    if modelName == "" && isfield(sampled, 'meta') && ...
            isfield(sampled.meta, 'cipModel')
        modelName = string(sampled.meta.cipModel);
    end
end

function cipModel = localCipModelNumber(modelName)
%LOCALCIPMODELNUMBER The gateway's code for a CIP model name.

    switch modelName
        case "IAU2006/2000A"
            cipModel = 2006;
        case "IAU2000A"
            cipModel = 2000;
        otherwise
            error('referenceSystem:rotationItrsToGcrs:unknownCipModel', ...
                ['The frame of the celestial pole offsets is "%s"; it must ', ...
                'be "IAU2006/2000A" or "IAU2000A". It normally travels with ', ...
                'the series in eop.meta.cipModel; set CipModel to override ', ...
                'it. The wrong choice shifts the pole by about 135 ', ...
                'microarcseconds at 2025, which is 4 mm at the surface, and ', ...
                'leaves a rotation that is orthogonal, smooth and entirely ', ...
                'plausible.'], modelName);
    end
end

% -------------------------------------------------------------------------

function [dubiousCount, cleanup] = localBeginDubiousScope(epochUtc)
%LOCALBEGINDUBIOUSSCOPE Determine the dubious epochs once and warn once.

    validThrough = referenceSystem.leapSecondTable("validThrough");
    lastDay = referenceSystem.leapSecondTable("validThroughDay");
    dubious = epochUtc.day > lastDay;
    dubiousCount = sum(dubious);

    previousState = warning('off', 'referenceSystem:leapSecondTable:dubiousYear');
    cleanup = onCleanup(@() warning(previousState));

    if dubiousCount > 0
        first = find(dubious, 1);
        last = find(dubious, 1, 'last');
        warning('referenceSystem:rotationItrsToGcrs:dubiousYear', ...
            ['%d of %d epochs lie beyond %s, the coverage of the active ', ...
            'leap-second table; the first is index %d at day %d and the ', ...
            'last is index %d at day %d. A leap second announced after the ', ...
            'table was built would make UT1 wrong by one second there, ', ...
            'which is 15 arcseconds of Earth rotation. The count is also in ', ...
            'info.dubiousEpochCount.'], ...
            dubiousCount, numel(dubious), string(validThrough, 'yyyy-MM-dd'), ...
            first, epochUtc.day(first), last, epochUtc.day(last));
    end
end

% -------------------------------------------------------------------------

function columns = localThreeColumns(value, epochCount, sampleCount)
%LOCALTHREECOLUMNS N-by-3 [t-h | t | t+h], repeating a single sample.

    columns = reshape(value, epochCount, sampleCount);
    if sampleCount == 1
        columns = repmat(columns, 1, 3);
    end
end

function rows = localToRows(pages)
%LOCALTOROWS Nx9 legacy layout, row-major within each 3x3 page.

    rows = reshape(permute(pages, [2 1 3]), 9, [])';
end

function info = localInfo(options, useInterpolant, derivativeOrder, step, ...
        cipModelName, epochCount, dubiousCount)
%LOCALINFO The diagnostics struct.

    methodName = "none";
    usedStep = NaN;
    if derivativeOrder > 0
        methodName = "centralDifference";
        usedStep = step;
    end
    pathName = "direct";
    residual = NaN;
    if useInterpolant
        pathName = "interpolated";
        % An interpolant read from a file carries no residual: the residual is
        % a property of the build, and a plausible number in its place would
        % be read as a measurement.
        if isfield(options.Interpolant.meta, 'residual')
            residual = max(options.Interpolant.meta.residual);
        end
    end
    info = struct( ...
        'path', pathName, ...
        'derivativeMethod', methodName, ...
        'differenceStep', usedStep, ...
        'interpolantResidual', residual, ...
        'cipModel', cipModelName, ...
        'tidalCorrections', options.ApplyTidalCorrections, ...
        'leapSecondSource', ...
            string(referenceSystem.leapSecondTable("state").source), ...
        'epochCount', epochCount, ...
        'dubiousEpochCount', dubiousCount);
end

function localCheckInterpolant(options)
%LOCALCHECKINTERPOLANT Refuse an interpolant that does not fit the call.
%   The panels fix the series, its interpolation, the CIP model and the tidal
%   setting when they are built. A series or a method passed beside them would
%   be silently unused, and a model or a tidal setting that differs cannot be
%   honoured - the offsets and the tides are already inside the fitted
%   channels - so all of these are refused rather than reconciled.

    interpolant = options.Interpolant;
    required = ["panelStartMjd", "panelSpan", "degree", "quantity", ...
        "coefficient", "meta"];
    missing = required(~isfield(interpolant, required));
    if isempty(missing)
        metaRequired = ["cipModel", "tidalCorrections"];
        missingMeta = metaRequired(~isfield(interpolant.meta, metaRequired));
        missing = "meta." + missingMeta;
    end
    if ~isempty(missing)
        error('referenceSystem:rotationItrsToGcrs:badInterpolant', ...
            ['The interpolant is missing %s. Build it with ', ...
            'referenceSystem.earthOrientationInterpolant.'], ...
            strjoin(missing, ", "));
    end

    given = ["Eop", "EopFile", "EopFormat", "InterpolationMethod"];
    isGiven = [~isempty(options.Eop), options.EopFile ~= "", ...
        options.EopFormat ~= "", options.InterpolationMethod ~= ""];
    if any(isGiven)
        error('referenceSystem:rotationItrsToGcrs:conflictingEopSource', ...
            ['%s was given beside an Interpolant. The panels already fix the ', ...
            'series and its interpolation, so it would be silently unused; ', ...
            'pass one source.'], strjoin(given(isGiven), " and "));
    end

    if options.CipModel ~= "" && ...
            string(interpolant.meta.cipModel) ~= options.CipModel
        error('referenceSystem:rotationItrsToGcrs:cipModelMismatch', ...
            ['The interpolant was fitted against CIP model "%s" and this ', ...
            'call asks for "%s". The observed pole offsets are already ', ...
            'inside the fitted X and Y, referred to the interpolant''s ', ...
            'model, and cannot be reinterpreted - 121 and 135 ', ...
            'microarcseconds at 2025, 4.2 mm at the surface, and invisible ', ...
            'in the resulting rotation.'], ...
            string(interpolant.meta.cipModel), options.CipModel);
    end

    if interpolant.meta.tidalCorrections ~= options.ApplyTidalCorrections
        error('referenceSystem:rotationItrsToGcrs:tidalMismatch', ...
            ['The interpolant was built with ApplyTidalCorrections %d and ', ...
            'this call asks for %d. Mixing them is a difference of tens of ', ...
            'microarcseconds that the resulting rotation gives no sign of, ', ...
            'so it is refused rather than reconciled.'], ...
            interpolant.meta.tidalCorrections, options.ApplyTidalCorrections);
    end
end

function [cipX, cipY, cipS, sampled] = localSampleInterpolant(interpolant, sampleUtc)
%LOCALSAMPLEINTERPOLANT The fitted quantities at the sample epochs, by name.
%   Returns the CIP as columns and the pole and UT1 - UTC in the struct shape
%   interpolateEop returns, so that everything downstream is shared. dX and dY
%   are zero: the observed pole offsets are already inside the fitted X and Y,
%   and applying them again would be a few hundred microarcseconds.

    % A sample inside a leap second has no MJD of its own: 23:59:60.x read as
    % day + sec/86400 lands in the next panel, one second late.
    inside = sampleUtc.sec >= 86400;
    if any(inside)
        error('referenceSystem:rotationItrsToGcrs:insideLeapSecond', ...
            ['%d of %d sample epochs fall inside the leap second at the end ', ...
            'of MJD %d. Interpolant panels are indexed by MJD, which that ', ...
            'second does not have. Use the direct path (omit ''Interpolant'') ', ...
            'for these epochs, or a DifferenceStep that keeps the difference ', ...
            'shoulders out of the leap second.'], sum(inside), numel(inside), ...
            sampleUtc.day(find(inside, 1)));
    end

    % A sample in the last 0.3 us of its day stays on that day: there
    % day + sec/86400 would round up to the next whole MJD and read the next
    % panel, whose dut1 is a second higher before a leap second.
    nextDay = sampleUtc.day + 1;
    mjd = min(sampleUtc.day + sampleUtc.sec / 86400, nextDay - eps(nextDay));

    edge = [interpolant.panelStartMjd; ...
        interpolant.panelStartMjd(end) + interpolant.panelSpan];
    panelIndex = discretize(mjd, edge);
    if any(isnan(panelIndex))
        error('referenceSystem:rotationItrsToGcrs:outsideInterpolant', ...
            ['%d of %d sample epochs lie outside the interpolant, which ', ...
            'covers MJD %.6f to %.6f. A Chebyshev panel diverges outside ', ...
            'its interval, so this is refused rather than extrapolated.'], ...
            sum(isnan(panelIndex)), numel(panelIndex), edge(1), edge(end));
    end

    value = zeros(numel(mjd), numel(interpolant.quantity));
    for k = unique(panelIndex)'
        inPanel = panelIndex == k;
        value(inPanel, :) = referenceSystem.evaluateInterpolant( ...
            interpolant, mjd(inPanel), k);
    end

    % Channels are selected by name, never by position: .quantity is the one
    % authority for the column order.
    quantityName = string(interpolant.quantity(:)).';
    column = @(name) localNamedColumn(value, quantityName, name);

    cipX = column("X");
    cipY = column("Y");
    cipS = column("s");
    sampled = struct( ...
        'xp', column("xp"), ...
        'yp', column("yp"), ...
        'dut1', column("dut1"), ...
        'dX', zeros(numel(mjd), 1), ...
        'dY', zeros(numel(mjd), 1));
end

function one = localNamedColumn(value, quantityName, name)
%LOCALNAMEDCOLUMN One fitted channel, located by its published name.

    hit = find(quantityName == name, 1);
    if isempty(hit)
        error('referenceSystem:rotationItrsToGcrs:badInterpolant', ...
            ['The interpolant does not carry the fitted channel "%s"; it ', ...
            'carries %s. Build it with ', ...
            'referenceSystem.earthOrientationInterpolant.'], name, ...
            strjoin(quantityName, ", "));
    end
    one = value(:, hit);
end
