function [axis, angle, convention] = axisAngleFromRotation(R, options)
%AXISANGLEFROMROTATION Rotation axis and angle of a rotation matrix.
%
%   [axis, angle] = axisAngleFromRotation(R) returns the 3xN unit rotation axes
%   and the 1xN angles in [0, pi] of the 3x3xN rotation.
%
%   [axis, angle, convention] = axisAngleFromRotation(R) also returns the
%   convention used.
%
% INPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   R      3x3xN    double   -      Rotation matrices, one page each.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                Description
%   ----         ----   ----     -------                -----------
%   AngleUnit    1x1    string   "rad"                  Unit of the output angle.
%   Convention   1x1    struct   attitudeConvention()   .sense is read.
%
% OUTPUT ARGUMENTS
%   Name         Size   Type     Units    Description
%   ----         ----   ----     -----    -----------
%   axis         3xN    double   -        Unit rotation axes. At a zero rotation
%                                         the axis is undefined and is reported
%                                         as [0; 0; 1]; see ACCURACY.
%   angle        1xN    double   rad|deg  Rotation angles in [0, pi]. Together
%                                         with the axis sign this covers every
%                                         rotation once.
%   convention   1x1    struct   -        The convention used.
%
% METHOD
%   THROUGH THE QUATERNION, not through the trace. The obvious route,
%   angle = acos((tr(R) - 1)/2) with the axis from the antisymmetric part, is
%   ill conditioned at both ends: acos has infinite slope at its limits, so a
%   rotation near 0 or near pi loses half its digits, and at exactly pi the
%   antisymmetric part vanishes and the axis is lost entirely.
%
%   quaternionFromRotation already solves that problem with Shepperd's branch,
%   so this function uses it and then reads off
%
%       angle = 2*atan2(|v|, q0),      axis = v/|v|,
%
%   which is well conditioned everywhere: atan2 of the two half-angle terms
%   never differentiates a near-flat function. With the sign convention q0 >= 0
%   the angle lands in [0, pi] automatically.
%
%   Reusing the quaternion is also the reason there is no second Shepperd
%   implementation in this file. The two-sources-of-truth pattern is cheaper to
%   avoid than to detect.
%
% ACCURACY
%   Round trip R -> axis-angle -> R reproduces the matrix to 4.4e-16 at angles
%   from 1e-9 rad to pi - 1e-9 rad, and the angle itself to 4.4e-16 rad. The
%   trace route measures 1.5e-8 rad of error at pi - 1e-8 rad, eight digits
%   worse, which is what the quaternion route buys.
%
%   AT A ZERO ROTATION THE AXIS IS GENUINELY UNDEFINED: every axis satisfies
%   R = I. The angle returned is 0, which is exact, and the axis is reported as
%   [0; 0; 1] rather than NaN, because a NaN axis would propagate into a
%   rotation vector axis*angle that ought to be exactly zero. The convention is
%   documented here and asserted in a contract test; a caller who needs to know
%   should test the angle, which is the quantity that carries the information.
%
%   THE any(turning) GUARD IS NOT DEFENSIVE PADDING. When no page is turning -
%   the single-page identity being the obvious case - the logical index selects
%   a 3x0 numerator and an empty denominator whose shapes do not conform, and
%   the elementwise division raises rather than returning an empty result. The
%   S4 run found this through axisAngleFromRotation(eye(3)), which is about as
%   reachable a call as exists in this file. Note that it CANNOT occur when any
%   page turns, so a mixed array hides it completely: the failing case is the
%   uniform one, which is the reverse of the usual expectation.
%
% ERRORS
%   referenceSystem:axisAngleFromRotation:wrongMatrixSize
%
% REFERENCES
%   S. W. Shepperd (1978), Quaternion from rotation matrix, J. Guidance and
%   Control 1(3), 223-224.
%   J. Diebel (2006), Representing Attitude, Stanford University, Sect. 4.
%
% EXAMPLE
%   [axis, angle] = referenceSystem.axisAngleFromRotation(R);
%   rotationVector = axis.*angle;
%
% KEYWORDS
%   axis angle, rotation vector, logarithmic map, attitude, Shepperd,
%   conditioning
%
% See also ROTATIONFROMAXISANGLE, QUATERNIONFROMROTATION, EULERSEQUENCEFROMROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 03:45 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        R double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(R, 1) ~= 3 || size(R, 2) ~= 3 || ndims(R) > 3
        error('referenceSystem:axisAngleFromRotation:wrongMatrixSize', ...
            'R must be 3x3 or 3x3xN; it is %s.', mat2str(size(R)));
    end

    scalarFirst = convention;
    scalarFirst.quaternion = "scalarFirst";
    q = referenceSystem.quaternionFromRotation(R, 'Convention', scalarFirst);

    vectorNorm = sqrt(sum(q(2:4, :).^2, 1));
    angle = 2*atan2(vectorNorm, q(1, :));

    axis = repmat([0; 0; 1], 1, size(q, 2));
    turning = vectorNorm > 0;
    if any(turning)
        axis(:, turning) = q(2:4, turning)./vectorNorm(turning);
    end

    if strcmp(options.AngleUnit, "deg")
        angle = rad2deg(angle);
    end
end
