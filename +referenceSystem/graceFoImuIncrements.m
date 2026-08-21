function [deltaTheta, epoch, info] = graceFoImuIncrements(imu, options)
%GRACEFOIMUINCREMENTS Satellite-Frame angle increments from GRACE-FO IMU1B.
%
%   [deltaTheta, epoch] = graceFoImuIncrements(imu) turns the accumulated,
%   per-gyro, staggered, degree-valued filtered angles of an IMU1B reading into
%   integrated angle increments of the body about the Satellite Frame axes, in
%   radians, over a single common epoch grid. Increment k spans epoch k to
%   epoch k+1, so deltaTheta has one column fewer than epoch has entries.
%
%   [deltaTheta, epoch, info] = graceFoImuIncrements(...) also returns the
%   counter wraps that were repaired, the gyros used, and the gyro-4 residual
%   where a fourth gyro was present.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   imu    1x1    struct   -      Reading from readImu1b. Fields .epoch,
%                                 .gyroId, .filteredAngle and .satellite are
%                                 read; .qualityFlag and .meta are not.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name             Size   Type     Default   Description
%   ----             ----   ----     -------   -----------
%   Method           1x1    string   "pchip"   Interpolant onto the common
%                                              grid: "pchip", "spline" or
%                                              "linear". See ACCURACY: at the
%                                              native 1.1 ms stagger the three
%                                              are indistinguishable.
%   Epoch            1x1    struct   []        Common grid to resolve onto.
%                                              Default is the epochs of the
%                                              lowest-numbered gyro of the
%                                              triad, clipped to the span all
%                                              three cover.
%   WrapThreshold    1x1    double   180       Increment magnitude, degrees,
%                                              above which a sample is a
%                                              counter wrap and not motion.
%   MaxGap           1x1    double   1         Largest spacing, seconds, that
%                                              may be interpolated across.
%   Alignment        1x1    struct   []        Override for
%                                              graceFoImuAlignment. Its
%                                              .satellite must match the data.
%
% OUTPUT ARGUMENTS
%   Name                    Size     Type     Units  Description
%   ----                    ----     ----     -----  -----------
%   deltaTheta              3x(N-1)  double   rad    Integral of the body
%                                                    angular velocity over each
%                                                    interval, resolved in the
%                                                    Satellite Frame.
%   epoch                   1x1      struct   -      Common grid, N entries,
%                                                    GPS scale.
%   info                    1x1      struct   -      Diagnostics.
%   .satellite              1x1      string   -      "C" or "D".
%   .gyroUsed               1x3      double   -      Always [1 2 3] (D83).
%   .gyroPresent            1xG      double   -      What the file held.
%   .alignmentSource        1x1      string   -      Citation of the tables.
%   .interpolationMethod    1x1      string   -      Method that ran.
%   .maxInterpolationShift  1x1      double   s      Largest distance any gyro
%                                                    sample was moved.
%   .largestGap             1x1      double   s      Largest grid spacing.
%   .wrapCount              1x1      double   -      Counter wraps repaired.
%   .wrap                   1xW      struct   -      One entry per wrap, with
%                                                    fields gyroId, sampleIndex,
%                                                    observedJump (deg),
%                                                    substitutedIncrement (deg)
%                                                    and impliedSpan (deg).
%   .gyroFourResidual       1x1      struct   -      .available, and when true
%                                                    .rms and .largest, rad.
%   .triadConditionNumber   1x1      double   -      Noise amplification of the
%                                                    three-axis solve.
%
% METHOD
%   FIVE THINGS HAPPEN, IN THIS ORDER, AND THE ORDER IS THE DESIGN.
%
%   (1) UNWRAP, PER GYRO, ON ITS OWN TIME TAGS. FiltAng is an accumulated
%   counter, not an increment, and it rolls over. Handbook Table 23's field
%   declares valid_range -5758,5758, and that is a declared bound and NOT the
%   turning point: the shipped 2020-01-01 GRACE C product turns at +5757.074194
%   and resumes at -5757.075213, a jump of -11514.149406 deg. Subtracting the
%   declared 2*5758 = 11516 deg would leave 1.844 deg in one increment, which
%   integrates to an attitude that is smooth, orthogonal and wrong. So the span
%   is never assumed. A wrapped increment is detected on magnitude and REPLACED
%   by the local continuation of the neighbouring increments, and the span this
%   implies is reported in info.wrap rather than used.
%
%   (2) BUILD ONE COMMON GRID. The three gyros are not sampled together: they
%   stagger by about 1.1 ms and 2.3 ms, which is a systematic inter-axis offset
%   and not noise, so it does not average away.
%
%   (3) INTERPOLATE THE ANGLE, THEN DIFFERENCE — NOT DIFFERENCE, THEN
%   INTERPOLATE THE RATE. The whole value of an integrated-angle input is that
%   increments telescope: their sum over any span is the total angle turned,
%   exactly. Interpolating a rate and multiplying by dt breaks that and
%   reintroduces the sampling error this function exists to remove. A precision
%   test asserts the telescoping to machine precision.
%
%   (4) CONVERT DEGREES TO RADIANS. Handbook section 3.2.1 states that all
%   Level-1 angles are radians and FiltAng is the exception, declaring
%   units: degrees in its own variables block. It is the one field a converter
%   is most likely to pass through untouched.
%
%   (5) PROJECT, AND THE PROJECTION OF AN INCREMENT IS EXACT. Gyro j measures
%   the component of the body rate along a FIXED axis a_j, so its accumulated
%   increment is a_j' * integral(omega dt) with the axis outside the integral.
%   Three such equations give integral(omega dt) in the IMU frame with no
%   approximation whatever, and Table 24 carries it to the Satellite Frame.
%
%   WHAT THIS FUNCTION RETURNS IS NOT A ROTATION VECTOR. It is the integral of
%   the angular velocity, which equals the rotation vector only when the axis
%   does not move within the interval. The difference is the coning term and it
%   belongs to the attitude integrator, not here; see integrateAttitude, whose
%   rotation-vector method applies exactly that correction.
%
%   GYRO 4 IS A DIAGNOSTIC AND NEVER A CONTRIBUTOR (DECISION D83). The solution
%   always uses the fixed triad 1, 2, 3. Where a fourth gyro is present its
%   increment is compared against the triad's prediction and the residual is
%   reported. A least-squares solution over whatever gyros are present at each
%   epoch is the obvious design and it is wrong: each gyro carries its own
%   bias, three-gyro and four-gyro solutions absorb those biases differently,
%   and the estimated rate therefore STEPS when the fourth sensor appears and
%   steps back when it leaves. Integrated, a train of steps is a random walk
%   manufactured by the estimator out of continuous data, and the attitude
%   stays smooth and orthogonal throughout.
%
%   FEWER THAN THREE GYROS IS REFUSED. Two axes determine a plane; a third
%   component assumed to complete it is a guess wearing the shape of a
%   measurement.
%
% ACCURACY
%   THE INTERPOLATION ONTO THE COMMON GRID IS NOT WHAT LIMITS THIS. Measured on
%   the shipped GRACE C product by holding one sample out of each series and
%   predicting it from its neighbours across a full 125 ms sample, the residual
%   is 1.2e-05 to 1.7e-05 deg for "spline", "pchip" and "linear" alike — the
%   three agree because the residual is the gyro's own noise and not the
%   truncation of any of them. The distance actually interpolated is the
%   stagger, at most 2.3 ms, where linear truncation is of order 4e-09 deg.
%   The Method option therefore exists for a caller-supplied coarse grid and
%   changes nothing at the native cadence. "pchip" is the default because it
%   cannot overshoot, so a data gap cannot manufacture a plausible increment.
%
%   THE REPAIRED WRAP CARRIES THE SCATTER OF THE NEIGHBOURING INCREMENTS. On
%   the shipped product the increments of gyro 1 either side of the wrap are
%   0.006469 deg with a standard deviation of 9.7e-05 deg, so the substituted
%   increment is good to about 0.35 arcsec, against 11514 deg if the wrap were
%   missed and 1.844 deg if the declared counter range were used as the span.
%   There is one such interval per wrap; the shipped day has one, and the
%   fixture that carries it reports an implied span of 11514.1559 deg.
%
%   THE INTER-AXIS STAGGER, IF LEFT UNCORRECTED, IS 0.21 ARCSEC. At the
%   observed 0.0518 deg/s a 1.13 ms offset is 5.85e-05 deg. It is a systematic
%   offset between axes, so it biases rather than averages.
%
%   FILTERING LIMITS WHAT ANY OF THIS CAN BUY, AND IT IS STATED HERE RATHER
%   THAN BURIED. FiltAng is passed through a selectable second-order low-pass
%   filter before it is reported. A low-pass on the angle attenuates exactly
%   the high-frequency content that coning compensation exists to capture, so
%   the published error terms of multi-sample coning algorithms — which assume
%   unfiltered increments — DO NOT TRANSFER to this input and are not quoted.
%   The increments here remain a better input than a sampled rate, because they
%   are integrals rather than point values, but the size of that gain on
%   filtered data has not been measured by this toolbox and no figure is given.
%
%   THE ALIGNMENT TABLES DOMINATE EVERYTHING ABOVE. Solving the shipped GRACE C
%   file with satellite D's tables changes the recovered rate by 1.16e-04 deg/s
%   out of 0.0635, which is 0.18 per cent and invisible at any single epoch, and
%   accumulates to 10.0 deg of attitude error per day. Transposing Table 24
%   costs 328 arcsec for satellite C and 61 arcsec for satellite D, and is
%   likewise invisible in the recovered rate magnitude because that matrix is
%   nearly symmetric. Both are why the satellite is read from the data and the
%   alignment is never a free argument.
%
%   THE CHAIN IS CONFIRMED AGAINST PHYSICS THE TOOLBOX WAS NOT TOLD. The rate
%   recovered from the shipped product is [+0.00010, +0.063457, +0.00018] deg/s
%   — pitch about the Satellite Frame Y axis, which is the nadir-pointing
%   attitude the handbook describes — and 0.063458 deg/s is a 94.55 min period,
%   a 6875.0 km semi-major axis and a 496.8 km altitude for a satellite
%   launched to 491.5 km nineteen months earlier.
%
%   The three-axis solve amplifies gyro noise by at most cond(G) = 2.0004.
%
% ERRORS
%   referenceSystem:graceFoImuIncrements:missingGyro
%   referenceSystem:graceFoImuIncrements:missingField
%   referenceSystem:graceFoImuIncrements:tooFewSamples
%   referenceSystem:graceFoImuIncrements:unsortedEpoch
%   referenceSystem:graceFoImuIncrements:gapTooLarge
%   referenceSystem:graceFoImuIncrements:epochOutOfRange
%   referenceSystem:graceFoImuIncrements:alignmentMismatch
%   referenceSystem:graceFoImuIncrements:wrongScale
%
% REFERENCES
%   Wen, H. Y., et al. (2019), GRACE-FO Level-1 Data Product User Handbook,
%   JPL D-56935, sections 3.2.1, 3.3.3 and 4.2.10, Tables 23 and 24.
%   Savage, P. G. (1998), Strapdown inertial navigation integration algorithm
%   design, part 1, J. Guidance Control Dyn. 21(1), for the increment-versus-
%   rate argument. Its coning error terms assume unfiltered increments.
%
% EXAMPLE
%   fileName = fullfile("test", "fixtures", "imu1bGraceC.txt");
%   imu = referenceSystem.readImu1b(fileName);
%   [deltaTheta, epoch, info] = referenceSystem.graceFoImuIncrements(imu);
%   fprintf("%d wrap(s) repaired\n", info.wrapCount);
%
% KEYWORDS
%   GRACE-FO, IMU1B, gyro, delta-theta, increment, coning, strapdown, attitude
%
% See also READIMU1B, GRACEFOIMUALIGNMENT, INTEGRATEATTITUDE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 21:40 (CEST, UTC+02:00) - session S9, prompt P27
% -------------------------------------------------------------------------

    arguments
        imu (1,1) struct
        options.Method (1,1) string {mustBeMember(options.Method, ...
            ["pchip", "spline", "linear"])} = "pchip"
        options.Epoch = []
        options.WrapThreshold (1,1) double {mustBeReal, mustBePositive} = 180
        options.MaxGap (1,1) double {mustBeReal, mustBePositive} = 1
        options.Alignment = []
    end

    triad = [1, 2, 3];

    localCheckReading(imu);
    alignment = localAlignment(imu, options.Alignment);

    % All time arithmetic is relative to the first record, so the two-part
    % epoch is never collapsed into an absolute second count (decision D9).
    baseEpoch = referenceSystem.daySecondToEpoch( ...
        [imu.epoch.day(1), imu.epoch.sec(1)], imu.epoch.scale);
    recordTime = referenceSystem.secondsBetween(baseEpoch, imu.epoch);

    present = unique(imu.gyroId(:))';
    missing = setdiff(triad, present);
    if ~isempty(missing)
        error('referenceSystem:graceFoImuIncrements:missingGyro', ...
            ['Gyro %s absent. The solution uses the fixed triad 1, 2, 3 ' ...
             '(decision D83) and fewer than three axes cannot determine a ' ...
             'body rate: two axes give a plane, and a third component ' ...
             'assumed to complete it is a guess wearing the shape of a ' ...
             'measurement. Gyros present: %s.'], ...
            strjoin(string(missing), ", "), strjoin(string(present), ", "));
    end

    [continuousAngle, gyroTime, wrap] = localUnwrapAll( ...
        imu, recordTime, [triad, 4], options.WrapThreshold);

    [gridTime, epoch] = localGrid(imu, baseEpoch, gyroTime, triad, options);
    localCheckGrid(gridTime, gyroTime, triad, options.MaxGap);

    % Interpolate the CONTINUOUS angle, then difference, so the increments
    % telescope exactly to the total angle turned over the grid.
    angleOnGrid = zeros(3, numel(gridTime));
    shift = 0;
    for k = 1:3
        j = triad(k);
        angleOnGrid(k, :) = interp1(gyroTime{j}, continuousAngle{j}, ...
            gridTime, options.Method);
        shift = max(shift, localLargestShift(gyroTime{j}, gridTime));
    end
    deltaGyro = deg2rad(diff(angleOnGrid, 1, 2));

    axisMatrix = alignment.gyroAxis(:, triad)';
    deltaImu = axisMatrix \ deltaGyro;
    deltaTheta = alignment.imuToSatelliteFrame * deltaImu;

    info = localDiagnostics(imu, alignment, triad, present, wrap, ...
        options, shift, gridTime, axisMatrix, deltaImu, ...
        continuousAngle, gyroTime);
end

% -------------------------------------------------------------------------
function localCheckReading(imu)
    required = ["epoch", "gyroId", "filteredAngle", "satellite"];
    absent = required(~isfield(imu, required));
    if ~isempty(absent)
        error('referenceSystem:graceFoImuIncrements:missingField', ...
            ['The reading is missing the field(s) %s. Pass the first output ' ...
             'of readImu1b.'], strjoin(absent, ", "));
    end
    if imu.epoch.scale ~= "GPS"
        error('referenceSystem:graceFoImuIncrements:wrongScale', ...
            ['The reading is tagged in %s. IMU1B time tags are GPS time and ' ...
             'readImu1b refuses anything else, so a different scale here ' ...
             'means the epochs were rebuilt somewhere in between.'], ...
            imu.epoch.scale);
    end
end

% -------------------------------------------------------------------------
function alignment = localAlignment(imu, supplied)
    if isempty(supplied)
        alignment = referenceSystem.graceFoImuAlignment(imu.satellite);
        return
    end
    alignment = supplied;
    if ~isfield(alignment, 'satellite') || alignment.satellite ~= imu.satellite
        error('referenceSystem:graceFoImuIncrements:alignmentMismatch', ...
            ['The supplied alignment is for satellite %s and the data is ' ...
             'from satellite %s. The two satellites differ by a rotation of ' ...
             '214.5 arcsec, which is invisible at one epoch and 10.0 deg of ' ...
             'attitude per day.'], ...
            string(alignment.satellite), imu.satellite);
    end
end

% -------------------------------------------------------------------------
function [continuousAngle, gyroTime, wrap] = localUnwrapAll(imu, ...
        recordTime, wanted, threshold)
    continuousAngle = cell(1, max(wanted));
    gyroTime = cell(1, max(wanted));
    wrap = struct('gyroId', {}, 'sampleIndex', {}, 'observedJump', {}, ...
        'substitutedIncrement', {}, 'impliedSpan', {});
    for j = wanted
        selected = imu.gyroId == j;
        if ~any(selected)
            continue
        end
        [t, order] = sort(recordTime(selected));
        raw = imu.filteredAngle(selected);
        raw = raw(order);
        if numel(t) < 2
            error('referenceSystem:graceFoImuIncrements:tooFewSamples', ...
                ['Gyro %d has %d sample(s). At least two are needed to form ' ...
                 'one increment.'], j, numel(t));
        end
        if any(diff(t) <= 0)
            error('referenceSystem:graceFoImuIncrements:unsortedEpoch', ...
                ['Gyro %d has repeated or non-increasing time tags after ' ...
                 'sorting, so two records share an epoch. Differencing them ' ...
                 'would divide by zero or silently drop one.'], j);
        end
        [continuousAngle{j}, gyroWrap] = localUnwrap(t, raw, threshold, j);
        wrap = [wrap, gyroWrap]; %#ok<AGROW>
        gyroTime{j} = t;
    end
end

% -------------------------------------------------------------------------
function [continuous, wrap] = localUnwrap(t, raw, threshold, gyroId)
    % A wrapped increment is not repaired by subtracting a counter span,
    % because the span is not published and the declared valid_range is not
    % the turning point. It is replaced by the local continuation, and the
    % span that implies is reported so a long arc can be checked for
    % consistency rather than trusted.
    increment = diff(raw);
    spacing = diff(t);
    wrapped = abs(increment) > threshold;
    wrap = struct('gyroId', {}, 'sampleIndex', {}, 'observedJump', {}, ...
        'substitutedIncrement', {}, 'impliedSpan', {});
    if any(wrapped)
        if all(wrapped)
            error('referenceSystem:graceFoImuIncrements:tooFewSamples', ...
                ['Every increment of gyro %d exceeds the wrap threshold of ' ...
                 '%g deg, so there is no unwrapped neighbour to continue ' ...
                 'from.'], gyroId, threshold);
        end
        midpoint = (t(1:end-1) + t(2:end))/2;
        rate = increment./spacing;
        substituted = interp1(midpoint(~wrapped), rate(~wrapped), ...
            midpoint(wrapped), 'linear', 'extrap').*spacing(wrapped);
        observed = increment(wrapped);
        index = find(wrapped);
        for k = 1:numel(index)
            wrap(end+1) = struct( ...
                'gyroId', gyroId, ...
                'sampleIndex', index(k), ...
                'observedJump', observed(k), ...
                'substitutedIncrement', substituted(k), ...
                'impliedSpan', abs(observed(k) - substituted(k))); %#ok<AGROW>
        end
        increment(wrapped) = substituted;
    end
    continuous = raw(1) + [0; cumsum(increment)];
end

% -------------------------------------------------------------------------
function [gridTime, epoch] = localGrid(~, baseEpoch, gyroTime, triad, options)
    if isempty(options.Epoch)
        first = max(cellfun(@(t) t(1), gyroTime(triad)));
        last = min(cellfun(@(t) t(end), gyroTime(triad)));
        candidate = gyroTime{triad(1)};
        gridTime = candidate(candidate >= first & candidate <= last);
        epoch = referenceSystem.addSeconds( ...
            localRepeatEpoch(baseEpoch, numel(gridTime)), gridTime);
        return
    end
    epoch = options.Epoch;
    if ~isstruct(epoch) || ~isfield(epoch, 'scale') || epoch.scale ~= "GPS"
        error('referenceSystem:graceFoImuIncrements:wrongScale', ...
            ['The supplied Epoch grid must be an epoch struct in the GPS ' ...
             'scale, matching the reading.']);
    end
    gridTime = referenceSystem.secondsBetween(baseEpoch, epoch);
end

% -------------------------------------------------------------------------
function repeated = localRepeatEpoch(baseEpoch, count)
    % addSeconds advances an existing series and does not expand a scalar
    % epoch into N, so the base is repeated first and the offsets go in one
    % per entry.
    repeated = referenceSystem.daySecondToEpoch( ...
        [repmat(baseEpoch.day, count, 1), repmat(baseEpoch.sec, count, 1)], ...
        baseEpoch.scale);
end

% -------------------------------------------------------------------------
function localCheckGrid(gridTime, gyroTime, triad, maxGap)
    if numel(gridTime) < 2
        error('referenceSystem:graceFoImuIncrements:tooFewSamples', ...
            ['The common grid holds %d epoch(s). At least two are needed to ' ...
             'form one increment; the three gyro series may not overlap.'], ...
            numel(gridTime));
    end
    if any(diff(gridTime) <= 0)
        error('referenceSystem:graceFoImuIncrements:unsortedEpoch', ...
            'The common grid is not strictly increasing.');
    end
    largest = max(diff(gridTime));
    if largest > maxGap
        error('referenceSystem:graceFoImuIncrements:gapTooLarge', ...
            ['The grid has a spacing of %g s against a MaxGap of %g s. ' ...
             'Interpolating across it would report the spacecraft''s motion ' ...
             'over the gap as a measurement of it. Raise MaxGap knowingly or ' ...
             'split the arc.'], largest, maxGap);
    end
    for k = 1:numel(triad)
        t = gyroTime{triad(k)};
        if gridTime(1) < t(1) || gridTime(end) > t(end)
            error('referenceSystem:graceFoImuIncrements:epochOutOfRange', ...
                ['The grid spans %.6f to %.6f s from the first record and ' ...
                 'gyro %d covers %.6f to %.6f s. Extrapolating a gyro ' ...
                 'counter returns a plausible angle that was never ' ...
                 'measured.'], gridTime(1), gridTime(end), triad(k), ...
                t(1), t(end));
        end
    end
end

% -------------------------------------------------------------------------
function shift = localLargestShift(sourceTime, gridTime)
    % How far the nearest source sample is from each grid epoch, which is the
    % distance actually interpolated.
    nearest = interp1(sourceTime, sourceTime, gridTime, 'nearest', 'extrap');
    shift = max(abs(nearest - gridTime));
end

% -------------------------------------------------------------------------
function info = localDiagnostics(imu, alignment, triad, present, wrap, ...
        options, shift, gridTime, axisMatrix, deltaImu, ...
        continuousAngle, gyroTime)
    residual = struct('available', false, 'rms', NaN, 'largest', NaN);
    if ismember(4, present)
        measured = deg2rad(diff(interp1(gyroTime{4}, continuousAngle{4}, ...
            gridTime, options.Method)));
        predicted = alignment.gyroAxis(:, 4)' * deltaImu;
        difference = measured(:)' - predicted;
        residual = struct('available', true, ...
            'rms', sqrt(mean(difference.^2)), ...
            'largest', max(abs(difference)));
    end
    info = struct( ...
        'satellite', imu.satellite, ...
        'gyroUsed', triad, ...
        'gyroPresent', present, ...
        'alignmentSource', alignment.source, ...
        'interpolationMethod', options.Method, ...
        'maxInterpolationShift', shift, ...
        'largestGap', max(diff(gridTime)), ...
        'wrapCount', numel(wrap), ...
        'wrap', wrap, ...
        'gyroFourResidual', residual, ...
        'triadConditionNumber', cond(axisMatrix));
end
