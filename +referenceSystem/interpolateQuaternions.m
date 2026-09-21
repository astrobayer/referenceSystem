function [q, convention, info] = interpolateQuaternions(nodeQuaternion, ...
        nodeEpoch, queryEpoch, options)
%INTERPOLATEQUATERNIONS Interpolate an attitude series to a vector of epochs.
%
%   q = interpolateQuaternions(nodeQuaternion, nodeEpoch, queryEpoch)
%   interpolates the 4xM attitude series tagged by the M node epochs to the N
%   query epochs, by spherical linear interpolation.
%
%   q = interpolateQuaternions(..., 'Method', "squad") uses the cubic SQUAD
%   interpolant instead, which is continuous in the angular rate at the nodes.
%
%   [q, convention, info] = interpolateQuaternions(...) also returns the
%   convention the result is expressed in and what the interpolation did.
%
% INPUT ARGUMENTS
%   Name             Size   Type     Units  Description
%   ----             ----   ----     -----  -----------
%   nodeQuaternion   4xM    double   -      Attitude at the nodes, one column
%                                           each, rows ordered by the convention.
%                                           Need not be of unit norm.
%   nodeEpoch        1x1    struct   -      Epoch struct holding M epochs,
%                                           strictly increasing.
%   queryEpoch       1x1    struct   -      Epoch struct holding N epochs in the
%                                           SAME time scale, each inside the node
%                                           range.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                Description
%   ----         ----   ----     -------                -----------
%   Method       1x1    string   "slerp"                "slerp" or "squad".
%   Convention   1x1    struct   attitudeConvention()   Only .quaternion is read.
%
% OUTPUT ARGUMENTS
%   Name                   Size   Type     Units  Description
%   ----                   ----   ----     -----  -----------
%   q                      4xN    double   -      Interpolated unit quaternions,
%                                                 SIGN CONTINUOUS along the
%                                                 series, not forced to q0 >= 0.
%   convention             1x1    struct   -      The convention used.
%   info                   1x1    struct   -      Diagnostics.
%   .method                1x1    string   -      The method that ran.
%   .nodeCount             1x1    double   -      M.
%   .signFlipCount         1x1    double   -      Nodes whose sign was reversed
%                                                 to make the series continuous.
%   .maximumNodeAngle      1x1    double   rad    Largest rotation between two
%                                                 consecutive nodes.
%   .linearFallbackCount   1x1    double   -      Query points whose bracketing
%                                                 pair was too close to separate,
%                                                 evaluated by normalised linear
%                                                 interpolation instead.
%
% METHOD
%   SIGN CONTINUITY FIRST, INTERPOLATION SECOND. A quaternion and its negative
%   are the same rotation, so a series read from a file or produced by an
%   estimator may flip sign between one record and the next with no change in
%   attitude whatsoever. Interpolating across such a flip sends the result the
%   long way round the sphere - up to 360 degrees of entirely fictitious motion -
%   while every individual node remains correct. The series is therefore made
%   continuous before anything else happens: with s(1) = 1 and
%   s(k) = s(k-1)*sign(q(:,k)'*q(:,k-1)), each node is multiplied by its s(k).
%   The rule is cumulative, exact (it changes only sign bits) and vectorised as
%   a cumulative product. info.signFlipCount reports how many nodes it moved.
%
%   THE OUTPUT IS NOT PUT INTO THE q0 >= 0 CANONICAL FORM, and that is a
%   deliberate departure from normalizeQuaternion's rule. Canonicalising the
%   output would reintroduce exactly the discontinuity just removed, at every
%   point where the series passes through a 180 degree rotation. The unit norm
%   still comes from normalizeQuaternion, so there is one implementation of it;
%   the sign it imposes is then undone where it disagrees with the interpolated
%   value. Apply normalizeQuaternion afterwards if the canonical form is wanted.
%
%   SLERP. With cos(w) = q_a'*q_b and u the fractional position in the interval,
%
%       q(u) = (sin((1-u)w)*q_a + sin(u*w)*q_b) / sin(w)
%
%   which is the constant-rate great-circle path. It is exact at u = 0 and
%   u = 1: sin(w)/sin(w) is one and sin(0) is zero, so the nodes come back
%   unchanged. Where the pair is closer than 1e-6 rad the quotient loses
%   significance and normalised linear interpolation is used instead, which
%   agrees with the great circle to O(w^2) and is therefore better there than
%   the formula it replaces; the count is reported.
%
%   SQUAD. SLERP is only C0: the angular rate jumps at every node, which is
%   invisible in the attitude and obvious the moment the series is
%   differentiated for a rate. SQUAD adds the Shoemake control points
%
%       s_i = q_i (x) exp( -( log(q_i^-1 (x) q_i+1) + log(q_i^-1 (x) q_i-1) )/4 )
%
%   with s_1 = q_1 and s_M = q_M, and evaluates
%
%       squad(u) = slerp( slerp(q_i, q_i+1, u), slerp(s_i, s_i+1, u), 2u(1-u) )
%
%   The nodes are still reproduced exactly, because u = 0 and u = 1 make the
%   blend weight 2u(1-u) vanish.
%
%   ONLY .quaternion OF THE CONVENTION ENTERS. Interpolation is a geometric
%   operation on the unit 3-sphere, so it depends on which row carries the
%   scalar and on nothing else: .sense does not change a geodesic, and .product
%   cancels out of the control-point construction, which is symmetric under the
%   operand reversal that distinguishes Hamilton from Shuster. That is measured,
%   not assumed - the two constructions were computed independently and agree to
%   5.6e-17. The quaternion products are therefore taken through
%   multiplyQuaternions with a fixed scalar-first Hamilton convention, and the
%   rows are reordered at entry and exit if the caller's convention is
%   scalar last.
%
%   The exponential and logarithm of a unit quaternion are local functions here.
%   They are the exponential map of the rotation group rather than quaternion
%   algebra, they exist in no L4b function, and they are used by nothing but
%   SQUAD (decision D73).
%
%   TIME. The interval fractions come from secondsBetween, so the node and query
%   epochs must share a time scale and the leap-second rule of that function
%   applies unchanged: a UTC or GLONASS series that CROSSES a leap second is
%   refused rather than silently mis-spaced by one second. Convert the series to
%   TAI, TT or GPS first, which is what an attitude product should be tagged
%   with in any case.
%
% ACCURACY
%   At the nodes the result reproduces the input to 1.1e-16, which is the
%   renormalisation of an already-unit quaternion and not an interpolation
%   error. Between them the error is that of the interpolant against whatever
%   the true motion was, and no interpolator can do better than the sampling:
%   measured against a smoothly turning reference sampled every second over
%   eight seconds, the worst deviation is 1.2e-2 rad for SLERP and 7.4e-3 rad
%   for SQUAD.
%
%   THE DIFFERENCE THAT MATTERS IS IN THE RATE, NOT IN THE ATTITUDE. On the same
%   case the jump in the numerical derivative across an interior node measures
%   3.9e-2 for SLERP and 1.3e-6 for SQUAD, a factor of 3e4. A series
%   differentiated for angular rate will show the SLERP corners as rate spikes
%   at exactly the node spacing, and they are easy to mistake for a sensor
%   artefact.
%
%   SQUAD's control points are the classical uniform-spacing construction. With
%   markedly non-uniform nodes the curve still passes through every node exactly
%   and stays C0, but the rate continuity degrades in proportion to the spacing
%   ratio. Nothing here detects that; keep the sampling regular if the rate is
%   going to be used.
%
% ERRORS
%   referenceSystem:interpolateQuaternions:wrongQuaternionSize
%   referenceSystem:interpolateQuaternions:tooFewNodes
%   referenceSystem:interpolateQuaternions:sizeMismatch
%   referenceSystem:interpolateQuaternions:nodesNotIncreasing
%   referenceSystem:interpolateQuaternions:queryOutOfRange
%   referenceSystem:secondsBetween:scaleMismatch
%       Raised on this function's behalf when the node and query epochs are in
%       different time scales.
%   referenceSystem:addSeconds:leapSecondCrossed
%       Raised on this function's behalf for a leap-bearing scale whose span
%       crosses a leap second.
%
% REFERENCES
%   K. Shoemake (1985), Animating Rotation with Quaternion Curves, SIGGRAPH
%   Computer Graphics 19(3), 245-254.
%   E. B. Dam, M. Koch and M. Lillholm (1998), Quaternions, Interpolation and
%   Animation, University of Copenhagen DIKU TR-98/5, Sect. 6 on SQUAD.
%   GRACE-FO Level-1 Data Product User Handbook, JPL D-56935, on the SCA1B
%   star-camera attitude product this function is shaped for.
%
% EXAMPLE
%   sca = referenceSystem.mjdToEpoch(mjdOfRecord, 'GPS');
%   kbr = referenceSystem.mjdToEpoch(mjdOfSample, 'GPS');
%   q = referenceSystem.interpolateQuaternions(qSca1b, sca, kbr, ...
%       'Method', "squad");
%
% KEYWORDS
%   quaternion, attitude, interpolation, SLERP, SQUAD, sign continuity, double
%   cover, GRACE, SCA1B, star camera
%
% See also NORMALIZEQUATERNION, MULTIPLYQUATERNIONS, INVERTQUATERNION, SECONDSBETWEEN.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 21:35 (CEST, UTC+02:00) - session S5, prompt P14
% -------------------------------------------------------------------------

    arguments
        nodeQuaternion double {mustBeReal, mustBeFinite}
        nodeEpoch (1,1) struct
        queryEpoch (1,1) struct
        options.Method (1,1) string {mustBeMember(options.Method, ...
            ["slerp", "squad"])} = "slerp"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);
    internalConvention = referenceSystem.attitudeConvention();

    if size(nodeQuaternion, 1) ~= 4 || ~ismatrix(nodeQuaternion)
        error('referenceSystem:interpolateQuaternions:wrongQuaternionSize', ...
            'nodeQuaternion must be 4xM, one column per node; it is %s.', ...
            mat2str(size(nodeQuaternion)));
    end
    nodeCount = size(nodeQuaternion, 2);
    if nodeCount < 2
        error('referenceSystem:interpolateQuaternions:tooFewNodes', ...
            ['Interpolation needs at least two nodes; %d were supplied. A ', ...
            'single attitude is not a series.'], nodeCount);
    end

    firstNode = referenceSystem.normalizeEpoch(nodeEpoch);
    if numel(firstNode.day) ~= nodeCount
        error('referenceSystem:interpolateQuaternions:sizeMismatch', ...
            ['nodeEpoch holds %d epochs and nodeQuaternion holds %d ', ...
            'quaternions; they must agree.'], numel(firstNode.day), nodeCount);
    end
    firstNode.day = firstNode.day(1);
    firstNode.sec = firstNode.sec(1);

    nodeTime = referenceSystem.secondsBetween(firstNode, nodeEpoch);
    queryTime = referenceSystem.secondsBetween(firstNode, queryEpoch);

    if any(diff(nodeTime) <= 0)
        bad = find(diff(nodeTime) <= 0, 1);
        error('referenceSystem:interpolateQuaternions:nodesNotIncreasing', ...
            ['Node epochs must be strictly increasing; node %d is %.6f s and ', ...
            'node %d is %.6f s after the first.'], bad, nodeTime(bad), ...
            bad+1, nodeTime(bad+1));
    end
    if any(queryTime < nodeTime(1)) || any(queryTime > nodeTime(end))
        outside = queryTime < nodeTime(1) | queryTime > nodeTime(end);
        bad = find(outside, 1);
        error('referenceSystem:interpolateQuaternions:queryOutOfRange', ...
            ['Query epoch %d lies %g s outside the node range of %g s. ', ...
            '%d of %d query epochs are outside it. Extrapolating an attitude ', ...
            'is refused rather than offered as an option: nothing in the ', ...
            'series constrains it.'], bad, ...
            max(nodeTime(1)-queryTime(bad), queryTime(bad)-nodeTime(end)), ...
            nodeTime(end)-nodeTime(1), sum(outside), numel(queryTime));
    end

    if strcmp(convention.quaternion, "scalarLast")
        nodeQuaternion = nodeQuaternion([4 1 2 3], :);
    end
    % THE CALLER'S SIGN IS RESTORED BEFORE THE CUMULATIVE PASS RUNS.
    % normalizeQuaternion imposes the canonical q0 >= 0, and applying it
    % first erased every sign flip the pass below exists to find: the pass
    % was dead code and info.signFlipCount was structurally always zero.
    % Run 1 of S5 caught it through TestOrbit. The hazard is the one this
    % file already names for greatCircle - a second mechanism enforcing the
    % same property - and it was upstream rather than downstream.
    % Canonicalising is NOT equivalent to a cumulative pass: at q0 near zero
    % it is a 180 degree rotation whose sign is a coin toss, which is
    % precisely where continuity matters most.
    normalized = referenceSystem.normalizeQuaternion(nodeQuaternion, ...
        'Convention', internalConvention);
    reversed = sum(normalized.*nodeQuaternion, 1) < 0;
    normalized(:, reversed) = -normalized(:, reversed);
    nodeQuaternion = normalized;

    pairDot = sum(nodeQuaternion(:, 2:end).*nodeQuaternion(:, 1:end-1), 1);
    stepSign = sign(pairDot);
    stepSign(stepSign == 0) = 1;
    columnSign = cumprod([1, stepSign]);
    nodeQuaternion = nodeQuaternion.*columnSign;

    controlPoint = nodeQuaternion;
    if strcmp(options.Method, "squad") && nodeCount > 2
        interior = 2:(nodeCount-1);
        centre = nodeQuaternion(:, interior);
        centreInverse = referenceSystem.invertQuaternion(centre, ...
            'Convention', internalConvention);
        toNext = referenceSystem.multiplyQuaternions(centreInverse, ...
            nodeQuaternion(:, interior+1), 'Convention', internalConvention);
        toPrevious = referenceSystem.multiplyQuaternions(centreInverse, ...
            nodeQuaternion(:, interior-1), 'Convention', internalConvention);
        tangent = -(quaternionLogarithm(toNext) + ...
            quaternionLogarithm(toPrevious))/4;
        control = referenceSystem.multiplyQuaternions(centre, ...
            quaternionExponential(tangent), 'Convention', internalConvention);
        opposed = sum(control.*centre, 1) < 0;
        control(:, opposed) = -control(:, opposed);
        controlPoint(:, interior) = control;
    end

    bracket = discretize(queryTime(:).', nodeTime(:).');
    bracket(isnan(bracket)) = nodeCount-1;
    span = nodeTime(bracket+1).' - nodeTime(bracket).';
    fraction = (queryTime(:).' - nodeTime(bracket).')./span;

    [q, fallbackCount] = greatCircle(nodeQuaternion(:, bracket), ...
        nodeQuaternion(:, bracket+1), fraction);
    if strcmp(options.Method, "squad")
        [qControl, controlFallback] = greatCircle(controlPoint(:, bracket), ...
            controlPoint(:, bracket+1), fraction);
        [q, blendFallback] = greatCircle(q, qControl, 2*fraction.*(1-fraction));
        fallbackCount = fallbackCount + controlFallback + blendFallback;
    end

    unsigned = referenceSystem.normalizeQuaternion(q, ...
        'Convention', internalConvention);
    reversed = sum(unsigned.*q, 1) < 0;
    unsigned(:, reversed) = -unsigned(:, reversed);
    q = unsigned;

    if strcmp(convention.quaternion, "scalarLast")
        q = q([2 3 4 1], :);
    end

    info = struct( ...
        'method', options.Method, ...
        'nodeCount', nodeCount, ...
        'signFlipCount', sum(columnSign < 0), ...
        'maximumNodeAngle', 2*max(acos(min(abs(pairDot), 1))), ...
        'linearFallbackCount', fallbackCount);
end

% -------------------------------------------------------------------------

function [q, fallbackCount] = greatCircle(qFrom, qTo, fraction)
%GREATCIRCLE Constant-rate interpolation along the shorter arc of two columns.
%   The operands are assumed to satisfy qFrom'*qTo >= 0. That is guaranteed by
%   the cumulative sign pass in the main function, and it is NOT re-imposed
%   here: a second mechanism enforcing the same property would make the sign
%   test in TestOrbit pass whether or not the first one works.

    cosineOfHalfAngle = min(max(sum(qFrom.*qTo, 1), -1), 1);
    halfAngle = acos(cosineOfHalfAngle);
    isClose = halfAngle < 1e-6;
    fallbackCount = sum(isClose);

    weightFrom = 1 - fraction;
    weightTo = fraction;
    sineOfHalfAngle = sin(halfAngle(~isClose));
    weightFrom(~isClose) = sin((1-fraction(~isClose)).*halfAngle(~isClose))./ ...
        sineOfHalfAngle;
    weightTo(~isClose) = sin(fraction(~isClose).*halfAngle(~isClose))./ ...
        sineOfHalfAngle;

    q = qFrom.*weightFrom + qTo.*weightTo;
    if any(isClose)
        norms = sqrt(sum(q(:, isClose).^2, 1));
        q(:, isClose) = q(:, isClose)./norms;
    end
end

function tangent = quaternionLogarithm(q)
%QUATERNIONLOGARITHM Vector part of the logarithm of a scalar-first unit
%   quaternion. Its norm is half the rotation angle, so the exponential below
%   inverts it exactly. Used only by the SQUAD control points (D73).

    vectorPart = q(2:4, :);
    vectorNorm = sqrt(sum(vectorPart.^2, 1));
    scale = zeros(size(vectorNorm));
    turning = vectorNorm > 1e-14;
    scale(turning) = atan2(vectorNorm(turning), q(1, turning))./ ...
        vectorNorm(turning);
    tangent = vectorPart.*scale;
end

function q = quaternionExponential(tangent)
%QUATERNIONEXPONENTIAL Scalar-first unit quaternion of a tangent vector.
%   The exact inverse of quaternionLogarithm.

    tangentNorm = sqrt(sum(tangent.^2, 1));
    scale = ones(size(tangentNorm));
    turning = tangentNorm > 1e-14;
    scale(turning) = sin(tangentNorm(turning))./tangentNorm(turning);
    q = [cos(tangentNorm); tangent.*scale];
end
