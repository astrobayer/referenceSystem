function [q, info, convention] = integrateAttitudeIncrements(initialQuaternion, ...
        deltaTheta, epoch, options)
%INTEGRATEATTITUDEINCREMENTS Propagate attitude over integrated angle increments.
%
%   q = integrateAttitudeIncrements(initialQuaternion, deltaTheta, epoch)
%   propagates the initial attitude through a series of INTEGRATED angle
%   increments of the body frame relative to the navigation frame, resolved in
%   the BODY frame, and returns the attitude at each of the N epochs. Increment
%   k spans epoch k to epoch k+1, so deltaTheta holds N-1 columns.
%
%   [q, info] = integrateAttitudeIncrements(...) also returns what the
%   propagation did, including whether the first interval carried a coning
%   correction, which it cannot.
%
% INPUT ARGUMENTS
%   Name                Size      Type     Units  Description
%   ----                ----      ----     -----  -----------
%   initialQuaternion   4x1       double   -      Attitude at the FIRST epoch,
%                                                 rows ordered by the
%                                                 convention. Need not be of
%                                                 unit norm.
%   deltaTheta          3x(N-1)   double   rad    Integral of the body angular
%                                                 velocity over each interval,
%                                                 body resolved. Column k spans
%                                                 epoch k to epoch k+1.
%   epoch               1x1       struct   -      Epoch struct holding N
%                                                 strictly increasing epochs.
%                                                 The spacing need not be
%                                                 uniform.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name              Size   Type     Default                Description
%   ----              ----   ----     -------                -----------
%   Convention        1x1    struct   attitudeConvention()   .quaternion is read.
%   ConingCorrection  1x1    logical  true                   Include the coning
%                                                            term. False is for
%                                                            demonstrating its
%                                                            effect, not for use.
%   RenormalizeEvery  1x1    double   1                      Steps between
%                                                            renormalisations.
%
% OUTPUT ARGUMENTS
%   Name                       Size   Type      Units  Description
%   ----                       ----   ----      -----  -----------
%   q                          4xN    double    -      Attitude at each epoch,
%                                                      column one being the
%                                                      initial attitude
%                                                      renormalised. SIGN
%                                                      CONTINUOUS.
%   info                       1x1    struct    -      Diagnostics.
%   .method                    1x1    string    -      "rotationVector".
%   .stepCount                 1x1    double    -      N-1.
%   .totalAngle                1x1    double    rad    Accumulated rotation
%                                                      angle.
%   .largestStepAngle          1x1    double    rad    Largest single step.
%   .largestConingAngle        1x1    double    rad    Largest coning term
%                                                      applied, zero when it is
%                                                      switched off.
%   .coningCorrection          1x1    logical   -      Whether it was applied.
%   .firstIntervalUncorrected  1x1    logical   -      True whenever the coning
%                                                      correction is on, since
%                                                      the first interval has
%                                                      no predecessor.
%   .renormalizeEvery          1x1    double    -      The cadence used.
%   convention                 1x1    struct    -      The convention used.
%
% METHOD
%   THIS IS NOT integrateAttitude WITH A DIFFERENT UNIT ON ITS SECOND ARGUMENT,
%   AND THAT IS WHY IT IS A SEPARATE FUNCTION. Section C.7 rule 2 keeps meaning
%   in the name rather than in a flag; an argument whose UNITS depend on an
%   option is the decision D25 and risk R10 failure mode in a new place, where
%   rad and rad/s differ by a factor no validator could catch. The coning term
%   also has a different form here, so the two are not one algorithm with a
%   switch.
%
%   THE ROTATION VECTOR IS NOT THE INTEGRAL OF THE ANGULAR VELOCITY, and the
%   difference is the whole of the correction. Bortz's equation for the
%   rotation vector phi of an interval is
%
%       phi_dot = w + 0.5*cross(phi, w) + (1/12)*cross(phi, cross(phi, w)) + ...
%
%   so to second order phi(T) = alpha(T) + 0.5*integral(cross(alpha, w) dt),
%   with alpha the accumulated increment inside the interval. Model w as linear
%   across the previous and current intervals, of lengths Tp and Tc. The mean
%   rate over an interval is then w at its midpoint, which fixes the slope, and
%   evaluating the integral gives
%
%       phi_k = dTheta_k + Tc^2/(6*Tp*(Tp + Tc)) * cross(dTheta_(k-1), dTheta_k)
%
%   DERIVED HERE, NOT QUOTED. On a uniform grid the weight is exactly 1/12,
%   which is the classical previous-sample coning algorithm; the general form
%   is carried because a real gyro grid is not uniform. GRACE-FO IMU1B jitters
%   by +-3.9 ms about 0.125 s, and assuming 1/12 there is a 3 per cent error on
%   a term that is itself small — but the general form costs two divisions and
%   removes the question.
%
%   THE FIRST INTERVAL CARRIES NO CORRECTION AND info SAYS SO. No increment
%   precedes it, so no single-sample algorithm can correct it. The cost is one
%   interval's worth of coning error, once, and it does not accumulate; it is
%   reported rather than hidden because a caller splitting a long arc into
%   pieces pays it once per piece and should know to overlap instead.
%
%   THE COMPOSITION IS NOT DUPLICATED. Once the rotation vectors exist, this
%   function hands them to the package-private composeRotationVectors, the same
%   authority integrateAttitude uses. The exponential map and the Hamilton
%   product exist once in this toolbox.
%
%   THERE IS NO Method OPTION. Runge-Kutta integrates the quaternion
%   differential equation and needs a RATE; recovering one by dividing the
%   increments by their intervals would throw away exactly the information that
%   makes this function worth having. Offering it would be an option that
%   silently undoes the point of the function.
%
% ACCURACY
%   MEASURED AGAINST THE CLOSED-FORM CONING CASE, WHERE THE INCREMENTS, THE
%   RATE AND THE ATTITUDE ALL HAVE ANALYTIC FORMS, so nothing below is produced
%   by the code under test. Half-cone 3 degrees, cone rate pi/2 rad/s, arc 2 s:
%
%       dt [s]    this function    integrateAttitude    ratio
%       0.0200    7.22e-09 rad     8.63e-06 rad         1194x
%       0.0100    8.95e-10 rad     2.16e-06 rad         2411x
%       0.0050    1.11e-10 rad     5.39e-07 rad         4845x
%       0.0025    1.39e-11 rad     1.35e-07 rad         9714x
%
%   THE RATIO GROWS BECAUSE THE TWO ARE OF DIFFERENT ORDER, not because one is
%   a better version of the other: this function is O(dt^3) and the rate form
%   is O(dt^2). The rate form is limited by reconstructing omega between two
%   samples, which no attitude integrator can repair; an exact increment does
%   not need reconstructing.
%
%   THE CONING TERM EARNS ITS PLACE HERE FAR MORE CLEARLY THAN IT DOES ON
%   RATES. Switching it off costs a factor of 98 at dt = 0.02 s and 797 at
%   dt = 0.0025 s, against a factor of 2 for the rate form, where the
%   trapezoidal reconstruction of omega dominates and masks it.
%
%   THOSE FIGURES ASSUME EXACT INCREMENTS AND ARE AN UPPER BOUND ON WHAT REAL
%   HARDWARE DELIVERS. GRACE-FO IMU1B reports FiltAng, an angle passed through
%   a selectable second-order low-pass filter, and a low-pass attenuates
%   exactly the high-frequency content the coning term exists to capture. The
%   published error terms of multi-sample coning algorithms assume unfiltered
%   increments and DO NOT TRANSFER to that input; this toolbox has not measured
%   the gain on filtered data and quotes no figure for it.
%
%   Sign continuity and unit norm are properties of composeRotationVectors and
%   are stated there.
%
% ERRORS
%   referenceSystem:integrateAttitudeIncrements:wrongQuaternionSize
%   referenceSystem:integrateAttitudeIncrements:wrongIncrementSize
%   referenceSystem:integrateAttitudeIncrements:tooFewEpochs
%   referenceSystem:integrateAttitudeIncrements:sizeMismatch
%   referenceSystem:integrateAttitudeIncrements:samplesNotIncreasing
%
% REFERENCES
%   Bortz, J. E. (1971), A new mathematical formulation for strapdown inertial
%   navigation, IEEE Trans. Aerospace Electron. Syst. AES-7(1), 61-66.
%   Savage, P. G. (1998), Strapdown inertial navigation integration algorithm
%   design, part 1, J. Guidance Control Dyn. 21(1), 19-28.
%
% EXAMPLE
%   fileName = fullfile("test", "fixtures", "imu1bGraceC.txt");
%   imu = referenceSystem.readImu1b(fileName);
%   [deltaTheta, epoch] = referenceSystem.graceFoImuIncrements(imu);
%   q = referenceSystem.integrateAttitudeIncrements([1; 0; 0; 0], ...
%       deltaTheta, epoch);
%
% KEYWORDS
%   attitude, delta-theta, increment, coning, strapdown, gyro, quaternion
%
% See also INTEGRATEATTITUDE, GRACEFOIMUINCREMENTS, ATTITUDECONVENTION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 00:20 (CEST, UTC+02:00) - session S9, prompt P27b
% -------------------------------------------------------------------------

    arguments
        initialQuaternion double {mustBeReal, mustBeFinite}
        deltaTheta double {mustBeReal, mustBeFinite}
        epoch (1,1) struct
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
        options.ConingCorrection (1,1) logical = true
        options.RenormalizeEvery (1,1) double {mustBeInteger, ...
            mustBeGreaterThanOrEqual(options.RenormalizeEvery, 1)} = 1
    end

    convention = referenceSystem.attitudeConvention(options.Convention);
    internalConvention = referenceSystem.attitudeConvention();

    if ~isequal(size(initialQuaternion), [4 1])
        error('referenceSystem:integrateAttitudeIncrements:wrongQuaternionSize', ...
            ['initialQuaternion must be 4x1, the attitude at the first ', ...
            'epoch; it is %s.'], mat2str(size(initialQuaternion)));
    end
    if size(deltaTheta, 1) ~= 3 || ~ismatrix(deltaTheta)
        error('referenceSystem:integrateAttitudeIncrements:wrongIncrementSize', ...
            'deltaTheta must be 3x(N-1), one increment per column; it is %s.', ...
            mat2str(size(deltaTheta)));
    end

    stepCount = size(deltaTheta, 2);
    if stepCount < 1
        error('referenceSystem:integrateAttitudeIncrements:tooFewEpochs', ...
            'Propagation needs at least one increment; none were supplied.');
    end

    firstEpoch = referenceSystem.normalizeEpoch(epoch);
    if numel(firstEpoch.day) ~= stepCount + 1
        error('referenceSystem:integrateAttitudeIncrements:sizeMismatch', ...
            ['epoch holds %d epochs and deltaTheta holds %d increments. An ', ...
            'increment spans an INTERVAL, so there must be exactly one more ', ...
            'epoch than increment.'], numel(firstEpoch.day), stepCount);
    end
    firstEpoch.day = firstEpoch.day(1);
    firstEpoch.sec = firstEpoch.sec(1);
    sampleTime = reshape(referenceSystem.secondsBetween(firstEpoch, epoch), 1, []);

    step = diff(sampleTime);
    if any(step <= 0)
        bad = find(step <= 0, 1);
        error('referenceSystem:integrateAttitudeIncrements:samplesNotIncreasing', ...
            ['Sample epochs must be strictly increasing; sample %d is ', ...
            '%.9f s and sample %d is %.9f s after the first.'], bad, ...
            sampleTime(bad), bad+1, sampleTime(bad+1));
    end

    startQuaternion = initialQuaternion;
    if strcmp(convention.quaternion, "scalarLast")
        startQuaternion = startQuaternion([4 1 2 3]);
    end
    startQuaternion = referenceSystem.normalizeQuaternion(startQuaternion, ...
        'Convention', internalConvention);

    coningAngle = zeros(1, stepCount);
    rotationVector = deltaTheta;
    if options.ConingCorrection && stepCount > 1
        % The weight is Tc^2/(6*Tp*(Tp+Tc)), which is exactly 1/12 on a uniform
        % grid. The first interval has no predecessor and keeps a zero column.
        previous = step(1:end-1);
        current = step(2:end);
        weight = current.^2./(6*previous.*(previous + current));
        coningTerm = [zeros(3, 1), ...
            weight.*cross(deltaTheta(:, 1:end-1), deltaTheta(:, 2:end))];
        rotationVector = rotationVector + coningTerm;
        coningAngle = sqrt(sum(coningTerm.^2, 1));
    end

    [q, stepAngle] = composeRotationVectors(startQuaternion, ...
        rotationVector, options.RenormalizeEvery);

    if strcmp(convention.quaternion, "scalarLast")
        q = q([2 3 4 1], :);
    end

    info = struct( ...
        'method', "rotationVector", ...
        'stepCount', stepCount, ...
        'totalAngle', sum(stepAngle), ...
        'largestStepAngle', max(stepAngle), ...
        'largestConingAngle', max([coningAngle, 0]), ...
        'coningCorrection', options.ConingCorrection, ...
        'firstIntervalUncorrected', options.ConingCorrection, ...
        'renormalizeEvery', options.RenormalizeEvery);
end
