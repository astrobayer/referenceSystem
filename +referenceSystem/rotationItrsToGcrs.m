function [R, Rdot, Rddot, info] = rotationItrsToGcrs(epoch, options)
%ROTATIONITRSTOGCRS Terrestrial-to-celestial rotation and its derivatives.
%
%   R = rotationItrsToGcrs(epoch, 'Eop', eop)
%   [R, Rdot] = rotationItrsToGcrs(epoch, 'Eop', eop)
%   [R, Rdot, Rddot, info] = rotationItrsToGcrs(epoch, 'EopFile', file)
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
%                                                         One of Eop or EopFile
%                                                         is required.
%   EopFile                1x1   string    none           File to read instead.
%   EopFormat              1x1   string    auto           Format name for
%                                                         EopFile.
%   ApplyTidalCorrections  1x1   logical   true           Add the diurnal and
%                                                         semidiurnal ocean
%                                                         tide and libration
%                                                         terms.
%   ApplyLengthOfDay       1x1   logical   true           Correct the ERA rate
%                                                         by the observed LOD.
%   CipModel               1x1   string    from eop.meta  Frame of the pole
%                                                         offsets. Overrides
%                                                         the series metadata.
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
%   InterpolationMethod    1x1   string    "linear"       Passed to
%                                                         interpolateEop.
%   Interpolant            1x1   struct    none           Panels from
%                                                         earthOrientationInterpolant.
%                                                         Its tidal setting must
%                                                         match this call's.
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
%   .path              1x1  string   -        "direct" or "interpolated".
%   .sampleSource      1x1  string   -        "series" (direct), "panels"
%                                             (format-2 interpolant) or
%                                             "panels+series" (format-1
%                                             interpolant, LOD from series).
%   .derivativeMethod  1x1  string   -        "none" or "centralDifference".
%   .differenceStep    1x1  double   s        Step actually used, NaN if none.
%   .interpolantResidual
%                      1x1  double   uas      Fit residual of the interpolant,
%                                             NaN on the direct path and for
%                                             an interpolant read from a file,
%                                             which carries no residual.
%   .cipModel          1x1  string   -        Frame the offsets were read in.
%   .tidalCorrections  1x1  logical  -        Whether they were applied.
%   .lengthOfDayApplied
%                      1x1  logical  -        Whether the ERA rate was corrected.
%   .leapSecondSource  1x1  string   -        From leapSecondTable("state").
%   .epochCount        1x1  double   -        N.
%   .dubiousEpochCount 1x1  double   -        Epochs beyond the leap-second
%                                             table's coverage.
%
% METHOD
%   ONE ROTATION, NO DIRECTION FLAG (decision D23). This function returns the
%   ITRS to GCRS rotation, full stop. The inverse is the transpose, exactly,
%   because R is a product of orthogonal factors: use invertRotation for the
%   matrices or applyRotation(..., 'Inverse', true) to apply it without forming
%   them. There is no 'Direction' option and no partner function to keep in
%   step.
%
%   THE SIGNATURE IS [R, Rdot, Rddot, info] (decision D25). Earlier revisions
%   of the design put the fundamental arguments in output slot 2, which made
%   [R, Rdot] silently bind a struct to a variable named Rdot and fail three
%   functions later inside pagemtimes. The fundamental arguments come from
%   referenceSystem.fundamentalArguments, which is public and needed in its own
%   right; taking the same epoch struct is what guarantees they are consistent
%   with the rotation.
%
%   OUTPUTS ARE GATED BY NARGOUT and the gating reaches the arithmetic, not
%   just the return statement. A TILDE IS NOT A DISCARD as far as MATLAB is
%   concerned: [R, ~, ~, info] reports nargout = 4, so the derivatives are
%   computed and info honestly reports centralDifference. Requesting the
%   diagnostics would therefore always cost two derivatives, which is about
%   three times the dominant term for a struct of metadata. 'Derivatives'
%   exists for exactly that call: [R, ~, ~, info] = f(..., 'Derivatives', 0)
%   returns the rotation and the diagnostics for the price of one CIP
%   evaluation. With one output the CIP series is evaluated once
%   per epoch; with two or three it is evaluated three times, at t-h, t and
%   t+h, and those same three evaluations yield both derivatives. Requesting
%   Rdot therefore roughly triples the cost of the dominant term and requesting
%   Rddot adds nothing further.
%
%   ALL THREE DERIVATIVE TERMS ARE INCLUDED (decision D20):
%
%       Rdot' = Wdot R3 Q + W R3dot Q + W R3 Qdot
%
%   Measured magnitudes, as a ratio to the Earth rotation rate and as the
%   velocity error at a 7000 km orbit radius if the term were dropped:
%
%       precession-nutation Qdot            9.3e-8    47 um/s
%       length-of-day correction to omega   2.5e-8    12.5 um/s
%       polar motion Wdot                   2.6e-9    1.3 um/s
%
%   Precession-nutation is the LARGEST of the three, not the smallest. All
%   three are computed and the length-of-day correction defaults on.
%
%   R3(ERA) IS DIFFERENTIATED ANALYTICALLY, not numerically: ERA is linear in
%   UT1 by definition, so dR3/dt = omega dR3/dtheta in closed form, and that
%   closed form is what the precision test compares the assembled Rdot against.
%   Q and W are differentiated by central differences on the matrix elements
%   at t-h, t and t+h. Analytic differentiation of the nutation series would be
%   faster and was rejected: it requires a second copy of SOFA's coefficient
%   tables, which is the two-sources-of-truth pattern this toolbox refuses
%   everywhere else.
%
%   Rddot keeps every second-order term of the product except one:
%
%       Rddot' = Wddot R3 Q + W R3ddot Q + W R3 Qddot
%                + 2(Wdot R3dot Q + Wdot R3 Qdot + W R3dot Qdot)
%
%   with R3ddot = omega^2 d2R3/dtheta2. THE NEGLECTED TERM IS omegadot dR3/dt,
%   the change in the Earth rotation rate itself. From the observed day-to-day
%   change in length of day it is of order 1e-17 rad/s^2 against omega^2 of
%   5.3e-9, nine orders down, and worth 7e-11 m/s^2 at 7000 km. Everything else
%   is kept, including Qddot, which measures 2.0e-17 s^-2 and reaches
%   1.4e-10 m/s^2 - at the GRACE accelerometer noise floor and therefore not
%   negligible.
%
%   THE EOP PIPELINE. The series is interpolated once for the whole arc, at
%   three sample times per epoch when a derivative is wanted, so that Wdot is
%   the derivative of the polar motion actually used and not of a frozen value.
%   With ApplyTidalCorrections true the diurnal and semidiurnal terms from
%   subdailyEopCorrection are added at the same three times. The zonal tide
%   correction is NOT applied and cannot be applied here: it regularises UT1
%   rather than supplying missing signal, and interpolateEop refuses it without
%   an explicit 'Regularize' (decision D30).
%
%   ONE WARNING PER CALL, NAMING THIS FUNCTION (decision D62). Epochs beyond
%   the coverage of the leap-second table are dubious, and leapSecondTable
%   raises its own warning when a UTC conversion crosses them. That warning
%   names leapSecondTable, which is not the function the user called, and it
%   fires once per internal conversion rather than once per call. The condition
%   is therefore determined here, once, from leapSecondTable("validThroughDay")
%   and its matching date,
%   the inner warning is suppressed for the duration of the internal
%   conversions and restored afterwards, and one aggregated warning is raised
%   naming this function and the epoch range. The count is also in
%   info.dubiousEpochCount, so a caller who suppresses the warning can still
%   see it. Note that the bundled SOFA table flags every epoch from 2029 onward
%   as dubious.
%
%   TWO MODES, DIRECT AND INTERPOLATED (decisions D17, D24; delivered by P19).
%   On the direct path the precession-nutation series is evaluated at every
%   epoch and the EOP come from the series. With 'Interpolant' the CIP and the
%   pole come from Chebyshev panels instead, and info.path reads
%   "interpolated". A panel is C-infinity inside itself, which removes the
%   midnight slope discontinuity that piecewise linear EOP interpolation puts
%   into a variable-step integrator's right-hand side. A format-2 interpolant
%   also carries the excess length of day, so no series is read at all (P19c);
%   info.sampleSource records which of the three cases ran. Panels are indexed
%   by UTC MJD, which the second 23:59:60 of a leap-second day does not have,
%   so on the interpolated path a sample inside a leap second - the epoch or
%   either difference shoulder - is refused with insideLeapSecond; the direct
%   path takes it as it takes any other epoch (rev. 1.226).
%
%   SINGLE-EPOCH PATH. With N = 1 the outputs are 3x3, because MATLAB drops a
%   trailing singleton dimension, and no interpolation object, temporary array
%   or vectorised setup is built. This is a branch inside one function and not
%   a separate scalar entry point; section B.9 explains why separate
%   scalar and vector functions were rejected.
%
% ACCURACY
%   THE DIFFERENCE STEP IS MEASURED, NOT ASSUMED (decision D28). Earlier
%   revisions of the design asserted h = 60 s giving 1e-7 relative on Qdot,
%   a figure that had never been established. The h-refinement study run for
%   this session, over twelve epochs spanning 1990 to 2050 against a Romberg
%   reference that was itself validated against a second reference of different
%   base step, gives:
%
%       h [s]   dX/dt error    d2X/dt2 error   worst velocity   worst accel
%       3000    1.9e-16        4.4e-22         1.3e-09 m/s      5.2e-15 m/s^2
%        600    7.5e-18        1.8e-23         5.3e-11 m/s      5.5e-15 m/s^2
%        200    8.4e-19        2.3e-22         6.0e-12 m/s      5.2e-14 m/s^2
%         60    8.2e-20        1.2e-21         1.0e-11 m/s      5.1e-13 m/s^2
%         10    7.5e-20        6.5e-20         7.4e-11 m/s      1.5e-11 m/s^2
%          1    9.8e-19        4.5e-18         5.3e-10 m/s      1.6e-09 m/s^2
%
%   The O(h^2) region runs from 3000 s down to about 200 s and the roundoff
%   plateau begins below about 150 s, set by the intrinsic evaluation noise of
%   the CIP series, which is 4.5e-18 rad rms in X and 5.2e-17 in Y.
%
%   THE DEFAULT IS h = 200 s, the minimum of the combined error normalised
%   against a budget of 1 nm/s in velocity and 1e-10 m/s^2 in acceleration,
%   the latter being the GRACE accelerometer noise floor. At that step the
%   normalised error is 6.0e-3, a margin of 167.
%
%   The wider result is worth more than the number: EVERY STEP FROM 1 s TO
%   1800 s MEETS BOTH BUDGETS, and only 3000 s fails, by a factor 1.3. The
%   choice of h is therefore not critical, which is the opposite of what the
%   unmeasured 60 s figure implied.
%
%   Reproduction of the SOFA cookbook worked example of 2007-04-05
%   (sofa_pn_c.pdf section 5.5), worst matrix element: 2.6e-15, that is
%   5e-4 microarcseconds of rotation.
%
%   Invariants, measured and independent of h:
%       max |R'R - I|                  1.1e-16
%       max |Rdot' R + R' Rdot|        4.2e-19 rad/s
%   The second is the one that catches a sign or transposition error in Rdot,
%   which no magnitude comparison would.
%
%   Equinox-versus-CIO agreement (risk R13b): 4.4e-16 rad worst element, that
%   is 9.1e-5 microarcseconds, over twelve epochs from 1990 to 2050.
%
%   ABSOLUTE ACCURACY IS SET BY THE EOP AND NOT BY ANY OF THE ABOVE. A C04
%   series carries formal errors of about 30 microarcseconds in polar motion
%   and 10 us in Delta UT1, which is 0.9 to 1.5 mm at the Earth's surface. Every
%   algorithmic figure quoted here is five or more orders below that. The
%   tolerances in TestRotation bound algorithmic quantities and are never
%   justified by EOP magnitudes (design principle 15).
%
% ERRORS
%   referenceSystem:rotationItrsToGcrs:eopRequired
%   referenceSystem:rotationItrsToGcrs:conflictingEopSource
%   referenceSystem:rotationItrsToGcrs:unknownCipModel
%   referenceSystem:rotationItrsToGcrs:badInterpolant
%   referenceSystem:rotationItrsToGcrs:tidalMismatch
%   referenceSystem:rotationItrsToGcrs:outsideInterpolant
%   referenceSystem:rotationItrsToGcrs:insideLeapSecond
%   referenceSystem:rotationItrsToGcrs:badDifferenceStep
%   referenceSystem:rotationItrsToGcrs:gatewayMissing
%
% WARNINGS
%   referenceSystem:rotationItrsToGcrs:dubiousYear
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
%   INTERPOLATEEOP, READEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:50 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Eop struct = struct([])
        options.EopFile (1,1) string = ""
        options.EopFormat (1,1) string = ""
        options.ApplyTidalCorrections (1,1) logical = true
        options.ApplyLengthOfDay (1,1) logical = true
        options.CipModel (1,1) string = ""
        options.Layout (1,1) string {mustBeMember(options.Layout, ...
            ["pages", "rows"])} = "pages"
        options.Derivatives (1,1) double {mustBeMember( ...
            options.Derivatives, [-1 0 1 2])} = -1
        options.DifferenceStep (1,1) double = 200
        options.InterpolationMethod (1,1) string = "linear"
        options.Interpolant = []
    end

    useInterpolant = ~isempty(options.Interpolant);
    if useInterpolant
        localCheckInterpolant(options.Interpolant, ...
            options.ApplyTidalCorrections, options.CipModel);
    end

    % nargout drives the derivative order by default, and 'Derivatives'
    % overrides it. The override exists because nargout cannot distinguish
    % [R, ~, ~, info] from [R, Rdot, Rddot, info] - a tilde is a request as far
    % as MATLAB is concerned - so without it a caller who wants the diagnostics
    % pays for two derivatives it discards, which is roughly three times the
    % cost of the dominant term for a struct of metadata.
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
    % plausible-looking array of the right size. A tilde is indistinguishable
    % from a request, so a caller writing [R, ~, ~, info] with Derivatives 0
    % must still have outputs 2 and 3 assigned; [] says "not computed" and
    % cannot be mistaken for a rotation rate.
    Rdot = [];
    Rddot = [];

    % P19c: WHEN THE PANELS CARRY EVERYTHING, NO SERIES IS READ AT ALL.
    % A format-2 interpolant holds the excess length of day beside the other
    % six quantities, which was the last thing the interpolated path needed
    % from interpolateEop. With it present the series call, the sub-daily
    % correction call and the EOP resolution are all skipped - the panels were
    % fitted to the corrected series, so recomputing the corrections and then
    % overwriting the result was work whose output was discarded.
    %
    % A FORMAT-1 INTERPOLANT STILL WORKS AND STILL PAYS. It has no lod
    % channel, so the series is interpolated exactly as before and
    % info.sampleSource says so. An old interpolant on disk is not a defect.
    panelsAreComplete = useInterpolant && ...
        any(string(options.Interpolant.quantity) == "lod");

    if panelsAreComplete
        eop = struct([]);
    else
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

    if panelsAreComplete
        sampled = struct('meta', struct('cipModel', ...
            string(options.Interpolant.meta.cipModel)));
    else
        correction = struct([]);
        if options.ApplyTidalCorrections
            correction = referenceSystem.subdailyEopCorrection(sampleUtc);
        end
        if isempty(correction)
            sampled = referenceSystem.interpolateEop(eop, sampleUtc, ...
                'Method', options.InterpolationMethod);
        else
            sampled = referenceSystem.interpolateEop(eop, sampleUtc, ...
                'Method', options.InterpolationMethod, 'Correction', correction);
        end
    end

    % EVERYTHING DOWNSTREAM OF HERE IS BYTE FOR BYTE THE CODE THE DIRECT PATH
    % RUNS - the reshaping, the UT1 conversion, omega, the derivative
    % machinery. Only where the six or seven sampled quantities came from
    % differs, which is what makes the two paths comparable at 5e-12 on a
    % direction cosine.
    if useInterpolant
        [cipSampleX, cipSampleY, cipSampleS, sampled] = localSampleInterpolant( ...
            options.Interpolant, sampleUtc, sampled);
    end

    cipModel = localResolveCipModel(options, sampled);

    % Reshape the sampled quantities back to N-by-3, the layout the gateway
    % reads as [t-h | t | t+h].
    polarX = reshape(sampled.xp, epochCount, sampleCount);
    polarY = reshape(sampled.yp, epochCount, sampleCount);
    offsetX = reshape(sampled.dX, epochCount, sampleCount);
    offsetY = reshape(sampled.dY, epochCount, sampleCount);
    deltaUt1 = reshape(sampled.dut1, epochCount, sampleCount);
    lengthOfDay = reshape(sampled.lod, epochCount, sampleCount);

    if useInterpolant
        cipX = reshape(cipSampleX, epochCount, sampleCount);
        cipY = reshape(cipSampleY, epochCount, sampleCount);
        cipS = reshape(cipSampleS, epochCount, sampleCount);
    end

    if sampleCount == 1
        polarX = repmat(polarX, 1, 3);
        polarY = repmat(polarY, 1, 3);
        offsetX = repmat(offsetX, 1, 3);
        offsetY = repmat(offsetY, 1, 3);
        if useInterpolant
            cipX = repmat(cipX, 1, 3);
            cipY = repmat(cipY, 1, 3);
            cipS = repmat(cipS, 1, 3);
        end
    end

    epochTt = referenceSystem.convertTimeScale(epochUtc, "TT");
    epochUt1 = referenceSystem.convertTimeScale(epochUtc, "UT1", ...
        'DeltaUt1', deltaUt1(:, min(2, sampleCount)));

    omega = referenceSystem.earthRotationAngleRate();
    if options.ApplyLengthOfDay
        constants = referenceSystem.iersConstants();
        lodAtEpoch = lengthOfDay(:, min(2, sampleCount));
        lodAtEpoch(~isfinite(lodAtEpoch)) = 0;
        omega = omega .* (1 - lodAtEpoch ./ constants.secondsPerDay);
    end
    omega = repmat(omega, epochCount / numel(omega), 1);

    % ONE ARGUMENT LIST, BUILT ONCE, WITH THREE APPENDED ON THE INTERPOLATED
    % PATH. The two gateway commands take the same leading twelve arguments for
    % exactly this reason: assembled separately they would eventually come to
    % disagree about one of them, and the symptom would be a rotation wrong by
    % an amount that looks like a tolerance problem.
    % The step is unread with no derivative requested, but the core still
    % validates it as positive, so a placeholder goes in rather than a zero.
    if derivativeOrder > 0
        stepArgument = step;
    else
        stepArgument = max(step, 1);
    end
    argument = {epochTt.day, epochTt.sec, epochUt1.day, epochUt1.sec, ...
        polarX, polarY, offsetX, offsetY, omega, cipModel, stepArgument};
    if useInterpolant
        command = 'dcmcip';
        argument = [argument, {cipX, cipY, cipS}];
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
        if derivativeOrder > 0
            methodName = "centralDifference";
            usedStep = step;
        else
            methodName = "none";
            usedStep = NaN;
        end
        if useInterpolant
            pathName = "interpolated";
            % AN INTERPOLANT READ FROM A FILE CARRIES NO RESIDUAL, AND THIS
            % LINE ASSUMED ONE. The .eopi format stores the coefficients, the
            % panel geometry, the CIP model and the tidal flag - not the fit
            % residual, which is a property of the BUILD and not of the
            % panels. So every call that asked for info with a file-read
            % interpolant raised MATLAB:nonExistentField, on every revision
            % since P19, and nothing exercised it until a format-1
            % compatibility test did at rev. 1.183.
            %
            % NaN, not zero and not a re-derivation: the residual is unknown
            % here, and a plausible number in its place would be read as a
            % measurement. Rebuild the interpolant to get one.
            if isfield(options.Interpolant.meta, 'residual')
                residual = max(options.Interpolant.meta.residual);
            else
                residual = NaN;
            end
        else
            pathName = "direct";
            residual = NaN;
        end
        if panelsAreComplete
            sampleSource = "panels";
        elseif useInterpolant
            sampleSource = "panels+series";
        else
            sampleSource = "series";
        end
        info = struct( ...
            'path', pathName, ...
            'sampleSource', sampleSource, ...
            'derivativeMethod', methodName, ...
            'differenceStep', usedStep, ...
            'interpolantResidual', residual, ...
            'cipModel', string(sampled.meta.cipModel), ...
            'tidalCorrections', options.ApplyTidalCorrections, ...
            'lengthOfDayApplied', options.ApplyLengthOfDay, ...
            'leapSecondSource', ...
                string(referenceSystem.leapSecondTable("state").source), ...
            'epochCount', epochCount, ...
            'dubiousEpochCount', dubiousCount);
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
            ['An Earth orientation series is required: pass Eop with the ', ...
            'output of readEop, or EopFile with a path. There is no ', ...
            'built-in default and no zero fallback, because a rotation ', ...
            'built from zero EOP is wrong by several metres at the ', ...
            'surface and looks entirely healthy.']);
    end
    if options.EopFormat == ""
        eop = referenceSystem.readEop(options.EopFile);
    else
        eop = referenceSystem.readEop(options.EopFile, ...
            'Format', options.EopFormat);
    end
end

% -------------------------------------------------------------------------

function cipModel = localResolveCipModel(options, sampled)
%LOCALRESOLVECIPMODEL Frame of the pole offsets, from the data or the override.
%
%   This is finding C-2 at its point of use. The frame is a property of the
%   series and travels with it in meta.cipModel; the option overrides it in one
%   place, deliberately, and an unknown value is an error rather than a guess.

    modelName = options.CipModel;
    if modelName == ""
        if isfield(sampled, 'meta') && isfield(sampled.meta, 'cipModel')
            modelName = string(sampled.meta.cipModel);
        end
    end

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
                'it. This is not a defaultable question: the wrong choice ', ...
                'shifts the pole by about 135 microarcseconds at 2025, ', ...
                'which is 4 mm at the surface, and leaves a rotation that ', ...
                'is orthogonal, smooth and entirely plausible.'], modelName);
    end
end

% -------------------------------------------------------------------------

function [dubiousCount, cleanup] = localBeginDubiousScope(epochUtc)
%LOCALBEGINDUBIOUSSCOPE Determine the dubious epochs once and warn once.
%
%   Decision D62. leapSecondTable warns under its own identifier on every UTC
%   conversion that reaches beyond its coverage, which would fire several times
%   per call to this function and name a function the user did not call. The
%   condition is determined here from the same single authority, the inner
%   warning is switched off for the caller's scope and restored by onCleanup,
%   and one aggregated warning is raised.

    % BOTH FORMS COME FROM THE AUTHORITY, rev. 1.216. The day number is what
    % epochUtc.day is compared against and the date is what the message
    % prints; rebuilding the first from the second, as this line did until
    % rev. 1.215, put a copy of the MJD epoch in this file.
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

function rows = localToRows(pages)
%LOCALTOROWS Nx9 legacy layout, row-major within each 3x3 page.

    rows = reshape(permute(pages, [2 1 3]), 9, [])';
end

function localCheckInterpolant(interpolant, applyTidalCorrections, ...
        cipModelOverride)
%LOCALCHECKINTERPOLANT Refuse an interpolant that does not fit the call.
%   TWO CHECKS, ONE AUTHORITY. P19c asked for the CIP-model refusal and it
%   belongs here rather than in a second function beside it: both are the same
%   question - was this interpolant fitted for the call being made - and two
%   places asking it is how they come to disagree.
%   The tidal check is the one that matters. An interpolant built without the
%   sub-daily ocean tide and libration differs from one built with them by tens
%   of microarcseconds, and nothing about the resulting rotation looks wrong -
%   it is smooth, orthogonal and plausible. Revision 1.91 is the evidence: the
%   builder omitted those terms, a reference test compared it against a chain
%   that omitted them too, and the pair agreed to 1e-14 for two revisions.
%   The mismatch is refused here rather than warned about, because a caller who
%   mixes them gets no signal from the numbers at all.

    required = ["panelStartMjd", "panelSpan", "degree", "quantity", ...
        "coefficient", "meta"];
    missing = required(~isfield(interpolant, required));
    if ~isempty(missing)
        error('referenceSystem:rotationItrsToGcrs:badInterpolant', ...
            ['The interpolant is missing %s. Build it with ', ...
            'referenceSystem.earthOrientationInterpolant.'], ...
            strjoin(missing, ", "));
    end

    if cipModelOverride ~= "" && ...
            string(interpolant.meta.cipModel) ~= cipModelOverride
        error('referenceSystem:rotationItrsToGcrs:cipModelMismatch', ...
            ['The interpolant was fitted against CIP model "%s" and this ', ...
            'call asks for "%s". The observed pole offsets are already ', ...
            'inside the fitted X and Y, so they were referred to the ', ...
            'interpolant''s model when it was built and cannot be reinterpreted ', ...
            'afterwards. Referring offsets to the wrong precession-nutation ', ...
            'model is the most serious defect this toolbox inherited from ', ...
            'v1 - 121 and 135 microarcseconds at 2025, which is 4.2 mm at ', ...
            'the surface - and it is invisible in the resulting rotation.'], ...
            string(interpolant.meta.cipModel), cipModelOverride);
    end

    if interpolant.meta.tidalCorrections ~= applyTidalCorrections
        error('referenceSystem:rotationItrsToGcrs:tidalMismatch', ...
            ['The interpolant was built with ApplyTidalCorrections %d and ', ...
            'this call asks for %d. Mixing them is a difference of tens of ', ...
            'microarcseconds that the resulting rotation gives no sign of, ', ...
            'so it is refused rather than reconciled.'], ...
            interpolant.meta.tidalCorrections, applyTidalCorrections);
    end
end

function [cipX, cipY, cipS, sampled] = localSampleInterpolant(interpolant, ...
        sampleUtc, sampled)
%LOCALSAMPLEINTERPOLANT The fitted quantities at the sample epochs, by name.
%   Returns the CIP as three columns and overwrites the pole and UT1 in the
%   struct the direct path built, so that everything downstream is unchanged.
%
%   dX AND dY ARE SET TO ZERO, WHICH IS NOT A SHORTCUT. The observed pole
%   offsets are already inside the fitted X and Y - earthOrientationInterpolant
%   fits the output of cipCoordinates, which has applied them. Leaving the
%   sampled dX and dY in place would apply them a second time, and the error
%   would be a few hundred microarcseconds: too small to look like a bug and
%   far too large to ignore.

    % A SAMPLE INSIDE A LEAP SECOND HAS NO MJD OF ITS OWN (rev. 1.226). UTC
    % 23:59:60.x is second 86400.x of its day, and day + sec/86400 lands it in
    % the NEXT panel, one second late in every fitted channel. Measured at
    % 23:59:60.5 on 2017-01-01 against the direct path: 4.5e-12 on R, inside
    % P19c's bound, but 3.3e-16 1/s on Rdot, over D28's 1 nm/s at 7000 km.
    % Refused rather than returned: the direct path handles the second, and so
    % does a DifferenceStep that keeps the shoulders out of it.
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

    mjd = sampleUtc.day + sampleUtc.sec / 86400;

    % Epochs are grouped by panel so that each panel is evaluated in one
    % vectorised call. discretize returns NaN outside the covered span, which
    % is how an epoch beyond the interpolant is caught here rather than as a
    % divergent extrapolation inside the Chebyshev evaluation.
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

    % CHANNELS ARE SELECTED BY NAME, NEVER BY POSITION (obligation O33). The
    % builder's localQuantityNames is the one authority for the column order
    % and publishes it in .quantity; a literal index here would be a second
    % copy of that order, and rev. 1.182 records what a duplicated magic
    % number eventually does. A required channel that is absent is a defect
    % in the interpolant and raises rather than reading a wrong column.
    quantityName = string(interpolant.quantity(:)).';
    column = @(name) localNamedColumn(value, quantityName, name);

    cipX = column("X");
    cipY = column("Y");
    cipS = column("s");

    sampled.xp = column("xp");
    sampled.yp = column("yp");
    sampled.dut1 = column("dut1");
    sampled.dX = zeros(numel(mjd), 1);
    sampled.dY = zeros(numel(mjd), 1);
    if any(quantityName == "lod")
        % FORMAT 2. With the excess length of day in the panels there is
        % nothing left that the series supplied, which is what P19c set out
        % to achieve. A format-1 interpolant leaves the value interpolateEop
        % already put here, and info.sampleSource records which happened.
        sampled.lod = column("lod");
    end
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
