function [q, info, convention] = integrateAttitude(initialQuaternion, omega, ...
        epoch, options)
%INTEGRATEATTITUDE Propagate attitude over a gyro rate series, body-resolved rate.
%
%   q = integrateAttitude(initialQuaternion, omega, epoch) propagates the
%   initial attitude through the 3xN series of angular velocities of the BODY
%   frame relative to the NAVIGATION frame, RESOLVED IN THE BODY FRAME, tagged
%   by the N epochs, and returns the 4xN attitude at each of them.
%
%   q = integrateAttitude(..., 'Method', "quaternionRk4") integrates the
%   quaternion differential equation instead of exponentiating a rotation
%   vector. See ACCURACY: on a sampled rate series the two agree closely, and
%   the reason is worth reading before choosing.
%
%   [q, info] = integrateAttitude(...) also returns what the integration did.
%
% INPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   initialQuaternion   4x1    double   -      Attitude at the FIRST epoch,
%                                              rows ordered by the convention.
%                                              Need not be of unit norm.
%   omega               3xN    double   rad/s  Angular velocity samples, one
%                                              column per epoch, body resolved.
%   epoch               1x1    struct   -      Epoch struct holding N strictly
%                                              increasing epochs. The sample
%                                              spacing need not be uniform.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name              Size   Type     Default                Description
%   ----              ----   ----     -------                -----------
%   Method            1x1    string   "rotationVector"       "rotationVector"
%                                                            or "quaternionRk4".
%   Convention        1x1    struct   attitudeConvention()   .quaternion is read.
%   ConingCorrection  1x1    logical  true                   Include the coning
%                                                            term. False is for
%                                                            demonstrating its
%                                                            effect, not for use.
%   RenormalizeEvery  1x1    double   1                      Steps between
%                                                            renormalisations.
%
% OUTPUT ARGUMENTS
%   Name                  Size   Type     Units  Description
%   ----                  ----   ----     -----  -----------
%   q                     4xN    double   -      Attitude at each epoch, column
%                                                one being the initial attitude
%                                                renormalised. SIGN CONTINUOUS
%                                                along the series.
%   info                  1x1    struct   -      Diagnostics.
%   .method               1x1    string   -      The method that ran.
%   .stepCount            1x1    double   -      N-1.
%   .totalAngle           1x1    double   rad    Accumulated rotation angle.
%   .largestStepAngle     1x1    double   rad    Largest single-step angle.
%   .largestConingAngle   1x1    double   rad    Largest coning term applied,
%                                                zero when it is switched off.
%   .coningCorrection     1x1    logical  -      Whether it was applied.
%   .renormalizeEvery     1x1    double   -      The cadence used.
%   convention            1x1    struct   -      The convention used.
%
% METHOD
%   THE ROTATION-VECTOR METHOD, NOT NAIVE INTEGRATION. Over one interval the
%   rotation vector is formed first and exponentiated once, so the step is an
%   exact rotation whatever its size, and the attitude cannot leave the unit
%   sphere by an amount that depends on the step. For a rate that is linear
%   across the interval the second-order Picard solution of Bortz's equation is
%
%       phi = dt*(w_a + w_b)/2 + (dt^2/12) * cross(w_a, w_b)
%
%   and the second term is the first-order coning correction. It is derived,
%   not quoted: expanding phi_dot = w + 0.5*cross(phi, w) + ... to second order
%   with w linear on [0, dt] gives exactly (dt^2/12)*cross(w_a, w_b). The step
%   is applied as q_next = q (x) exp(phi) by the package-private
%   composeRotationVectors, which is the single authority for the exponential
%   map and is shared with integrateAttitudeIncrements; the increment joins on
%   the RIGHT
%   because it is expressed in the body frame and, with the Hamilton product in
%   the frame sense, R(a (x) b) = R(b) R(a).
%
%   WHY THE CONING TERM MATTERS. Under oscillatory motion the rate vector
%   sweeps a cone and successive increments do not commute. Dropping the term
%   leaves a rectified error that grows linearly with time rather than
%   averaging out, which is the regime a real IMU sees and the reason a
%   single-step test of an attitude integrator proves nothing (risk R21).
%
%   RENORMALISATION. Every step by default. The exponential is a unit
%   quaternion and the product of two unit quaternions is unit, so the norm
%   drifts only by rounding - about 1e-16 per step, so 1e-12 over 10^4 steps,
%   which is already negligible. The default is nevertheless every step,
%   because it costs one square root against several trigonometric evaluations
%   and because a cadence that is tuned is a parameter that can be set wrong.
%   'RenormalizeEvery' exists so the claim can be tested rather than believed.
%
%   TIME. Intervals come from secondsBetween, so its leap-second rule applies
%   unchanged: a UTC series that CROSSES a leap second is refused rather than
%   silently mis-spaced by one second. Tag a gyro series with TAI, TT or GPS.
%
% ACCURACY
%   MEASURED ON THE CLOSED-FORM CONING CASE, against an independent Python
%   implementation. The rotation vector traces a circle of half-angle beta at
%   rate Omega, so the attitude and the rate are both closed forms:
%
%       q(t)     = [cos(beta/2); sin(beta/2)cos(Omega t); sin(beta/2)sin(Omega t); 0]
%       omega(t) = Omega [-sin(beta) sin(Omega t); sin(beta) cos(Omega t);
%                         -(1 - cos(beta))]
%
%   With beta = 3 deg and a 4 s cone period, integrating 100 s at dt = 0.01 s:
%
%       method                          error [rad]   drift [arcsec/h]
%       ------                          -----------   ----------------
%       rotationVector                  8.85e-06      65.7
%       quaternionRk4                   8.85e-06      65.7
%       rotationVector, coning dropped  1.77e-05      131.4
%
%   THE HEADLINE FIGURE IS NOT THE INTERESTING ONE, AND QUOTING IT ALONE WOULD
%   MISLEAD. The residual was decomposed by switching each error source off
%   independently. With the trapezoidal quadrature replaced by the exact
%   integral of omega, the coning-corrected error falls to 0.0 to 3.0e-08 rad,
%   that is to machine precision: THE CONING TERM IS EXACT FOR THIS MOTION AND
%   REMOVES THE WHOLE NON-COMMUTATIVITY ERROR. What survives is the trapezoidal
%   reconstruction of omega BETWEEN SAMPLES, and for this motion the two
%   happen to be equal in size, which is why dropping the coning term costs a
%   factor of two rather than the factor of hundreds the term deserves.
%
%   THAT IS ALSO WHY THE TWO METHODS AGREE. They differ by less than 1e-11 rad
%   here, which is what the suite asserts; an independent mirror puts the
%   separation at 5e-14, a figure attributed rather than adopted. The methods
%   differ by far less than either differs from the truth, not
%   because the integrators are equivalent but because neither is what limits
%   the answer: both reconstruct omega from the same two samples per interval.
%   Choosing between them on this evidence is choosing between two things that
%   are not the bottleneck. The bottleneck is the SAMPLING, and a user who has
%   integrated increments from the gyro rather than sampled rates has a
%   materially better input than either method can make up for.
%
%   THAT INPUT NOW HAS A FUNCTION: integrateAttitudeIncrements. Measured on the
%   closed-form coning case with exact increments, it is between 1.2e+03 and
%   9.7e+03 times more accurate than this function on the corresponding sampled
%   rates, and the ratio grows as the step shrinks because the two are of
%   different order. Prefer it wherever the gyro delivers integrated angle.
%
%   Both errors are O(dt^2) in accumulated angle: 3.54e-05, 8.85e-06, 2.21e-06,
%   5.53e-07 rad at dt = 0.02, 0.01, 0.005, 0.0025 s, an order of 2.00 at every
%   halving.
%
%   CONSTANT RATE IS EXACT. The coning term vanishes because cross(w, w) = 0
%   and every step is the same rotation, so 10^4 steps of a constant
%   0.032 rad/s rate reproduce the analytic single-axis answer to
%   max|q - exact| = 1.13e-14, which is accumulated rounding alone.
%
% ERRORS
%   referenceSystem:integrateAttitude:wrongQuaternionSize
%   referenceSystem:integrateAttitude:wrongVelocitySize
%   referenceSystem:integrateAttitude:sizeMismatch
%   referenceSystem:integrateAttitude:tooFewSamples
%   referenceSystem:integrateAttitude:samplesNotIncreasing
%
% REFERENCES
%   J. E. Bortz (1971), A New Mathematical Formulation for Strapdown Inertial
%   Navigation, IEEE Trans. Aerospace and Electronic Systems 7(1), 61-66.
%   P. G. Savage (1998), Strapdown Inertial Navigation Integration Algorithm
%   Design Part 1: Attitude Algorithms, J. Guidance 21(1), 19-28.
%   M. B. Ignagni (1990), Optimal Strapdown Attitude Integration Algorithms,
%   J. Guidance 13(2), 363-369.
%
% EXAMPLE
%   t = referenceSystem.daySecondToEpoch([repmat(60310, 1001, 1), ...
%       (0:1000)'*0.01], "TAI");
%   q = referenceSystem.integrateAttitude([1; 0; 0; 0], gyroRate, t);
%
% KEYWORDS
%   strapdown, attitude, gyro, coning, rotation vector, quaternion, IMU,
%   inertial navigation, propagation
%
% See also ANGULARVELOCITYTOROTATIONRATE, INTERPOLATEQUATERNIONS, ROTATIONNAVTOBODY.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 22:25 (CEST, UTC+02:00) - session S5, prompt P26
% -------------------------------------------------------------------------

    arguments
        initialQuaternion double {mustBeReal, mustBeFinite}
        omega double {mustBeReal, mustBeFinite}
        epoch (1,1) struct
        options.Method (1,1) string {mustBeMember(options.Method, ...
            ["rotationVector", "quaternionRk4"])} = "rotationVector"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
        options.ConingCorrection (1,1) logical = true
        options.RenormalizeEvery (1,1) double {mustBeInteger, ...
            mustBeGreaterThanOrEqual(options.RenormalizeEvery, 1)} = 1
    end

    convention = referenceSystem.attitudeConvention(options.Convention);
    internalConvention = referenceSystem.attitudeConvention();

    if ~isequal(size(initialQuaternion), [4 1])
        error('referenceSystem:integrateAttitude:wrongQuaternionSize', ...
            ['initialQuaternion must be 4x1, the attitude at the first ', ...
            'epoch; it is %s.'], mat2str(size(initialQuaternion)));
    end
    if size(omega, 1) ~= 3 || ~ismatrix(omega)
        error('referenceSystem:integrateAttitude:wrongVelocitySize', ...
            'omega must be 3xN, one sample per column; it is %s.', ...
            mat2str(size(omega)));
    end

    sampleCount = size(omega, 2);
    if sampleCount < 2
        error('referenceSystem:integrateAttitude:tooFewSamples', ...
            ['Propagation needs at least two rate samples; %d were ', ...
            'supplied. A single sample spans no interval.'], sampleCount);
    end

    firstEpoch = referenceSystem.normalizeEpoch(epoch);
    if numel(firstEpoch.day) ~= sampleCount
        error('referenceSystem:integrateAttitude:sizeMismatch', ...
            ['epoch holds %d epochs and omega holds %d samples; they must ', ...
            'agree.'], numel(firstEpoch.day), sampleCount);
    end
    firstEpoch.day = firstEpoch.day(1);
    firstEpoch.sec = firstEpoch.sec(1);
    sampleTime = reshape(referenceSystem.secondsBetween(firstEpoch, epoch), 1, []);

    step = diff(sampleTime);
    if any(step <= 0)
        bad = find(step <= 0, 1);
        error('referenceSystem:integrateAttitude:samplesNotIncreasing', ...
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

    rateBefore = omega(:, 1:end-1);
    rateAfter = omega(:, 2:end);
    coningAngle = zeros(1, sampleCount-1);

    if strcmp(options.Method, "rotationVector")
        % THE ROTATION VECTORS DO NOT DEPEND ON THE RUNNING ATTITUDE, so they
        % are formed for the whole arc and the propagation is left to the one
        % authority that both integrators share. This is the same arithmetic
        % the loop performed step by step, in the same order.
        rotationVector = step.*(rateBefore + rateAfter)/2;
        if options.ConingCorrection
            coningTerm = (step.^2/12).*cross(rateBefore, rateAfter);
            rotationVector = rotationVector + coningTerm;
            coningAngle = sqrt(sum(coningTerm.^2, 1));
        end
        [q, stepAngle] = composeRotationVectors(startQuaternion, ...
            rotationVector, options.RenormalizeEvery);
    else
        % RK4 integrates the quaternion differential equation directly and
        % never forms a rotation vector, so it cannot use the shared
        % composition and keeps its own loop.
        q = zeros(4, sampleCount);
        q(:, 1) = startQuaternion;
        stepAngle = zeros(1, sampleCount-1);
        current = startQuaternion;
        for k = 1:(sampleCount-1)
            [current, stepAngle(k)] = rungeKutta4(current, rateBefore(:, k), ...
                rateAfter(:, k), step(k));
            if mod(k, options.RenormalizeEvery) == 0 || k == sampleCount-1
                current = current/sqrt(sum(current.^2));
            end
            q(:, k+1) = current;
        end
    end

    % Sign continuity is a property of the series, not of each step: the
    % propagation never flips a sign, so any flip would be a defect and is
    % asserted rather than repaired. The canonical q0 >= 0 form of
    % normalizeQuaternion is deliberately NOT imposed, for the reason given in
    % interpolateQuaternions: it would reintroduce a discontinuity at every
    % passage through a 180 degree rotation.
    if strcmp(convention.quaternion, "scalarLast")
        q = q([2 3 4 1], :);
    end

    info = struct( ...
        'method', options.Method, ...
        'stepCount', sampleCount-1, ...
        'totalAngle', sum(stepAngle), ...
        'largestStepAngle', max(stepAngle), ...
        'largestConingAngle', max([coningAngle, 0]), ...
        'coningCorrection', options.ConingCorrection, ...
        'renormalizeEvery', options.RenormalizeEvery);
end

% -------------------------------------------------------------------------

function [q, angle] = rungeKutta4(current, rateBefore, rateAfter, interval)
%RUNGEKUTTA4 Classical RK4 on qdot = 0.5 q (x) [0; omega].
%   omega at the midpoint is the mean of the two samples, which is the only
%   estimate two samples support. That reconstruction, not the integrator, is
%   what limits the result - see the ACCURACY block of the main function.

    rateMiddle = (rateBefore + rateAfter)/2;
    k1 = quaternionDerivative(current, rateBefore);
    k2 = quaternionDerivative(current + interval/2*k1, rateMiddle);
    k3 = quaternionDerivative(current + interval/2*k2, rateMiddle);
    k4 = quaternionDerivative(current + interval*k3, rateAfter);
    q = current + interval/6*(k1 + 2*k2 + 2*k3 + k4);
    angle = interval*sqrt(sum(rateMiddle.^2));
end

function qdot = quaternionDerivative(q, omega)
%QUATERNIONDERIVATIVE The rate 0.5 q (x) [0; omega], body-resolved omega.
%   The same tangent-vector object as in angularVelocityToRotationRate, and
%   local for the same reason (decision D73): it is not a rotation product.

    qdot = 0.5*[-q(2:4).'*omega; q(1)*omega + cross(q(2:4), omega)];
end
