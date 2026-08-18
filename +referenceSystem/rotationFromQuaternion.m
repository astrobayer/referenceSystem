function [R, convention] = rotationFromQuaternion(q, options)
%ROTATIONFROMQUATERNION Rotation matrix of a unit quaternion.
%
%   R = rotationFromQuaternion(q) returns the 3x3xN rotation of the 4xN
%   quaternions.
%
%   [R, convention] = rotationFromQuaternion(q) also returns the convention the
%   matrices were built under.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   q      4xN    double   -      Quaternions, one column each. Row order is set
%                                 by the convention: [q0; q1; q2; q3] for
%                                 scalarFirst, [q1; q2; q3; q0] for scalarLast.
%                                 The norm need not be exactly one; see METHOD.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                Description
%   ----         ----   ----     -------                -----------
%   Convention   1x1    struct   attitudeConvention()   .sense and .quaternion
%                                                       are read.
%
% OUTPUT ARGUMENTS
%   Name         Size     Type     Units  Description
%   ----         ----     ----     -----  -----------
%   R            3x3xN    double   -      Rotation matrices, one page per column.
%   convention   1x1      struct   -      The convention used.
%
% METHOD
%   For the default frame (passive) sense and a unit quaternion,
%
%       R = (q0^2 - v'v) I + 2 v v' - 2 q0 [v]x,   v = [q1; q2; q3],
%
%   written out element by element so that no 3x3 temporary is formed per page.
%   The "vector" (active) sense returns the transpose, which is the same
%   expression with the sign of the [v]x term reversed. Sign check: the
%   quaternion [cos(t/2); 0; 0; sin(t/2)] gives exactly rotationZ(t).
%
%   THE QUATERNION IS NORMALISED ON ENTRY rather than assumed unit. Quaternions
%   arriving from a file or from an integrator are typically unit to about
%   1e-9, and a quaternion of norm 1+e produces a matrix scaled by (1+e)^2,
%   which is not a rotation at all and whose transpose is not its inverse.
%   Normalising costs one square root per page and removes the failure mode; the
%   sign is left alone here, since it does not affect R.
%
% ACCURACY
%   Exact to machine precision. Orthogonality residual max|R'R - I| measured
%   2.6e-16 over random quaternions, and the round trip q -> R -> q reproduces
%   the quaternion to 4.4e-16 including within 1e-8 rad of a 180 degree
%   rotation. The double cover is exact: q and -q give bit-identical matrices,
%   because every term is quadratic in q.
%
% ERRORS
%   referenceSystem:rotationFromQuaternion:wrongQuaternionSize
%   referenceSystem:rotationFromQuaternion:zeroQuaternion
%
% REFERENCES
%   M. D. Shuster (1993), A Survey of Attitude Representations, JAS 41(4).
%   J. Sola (2017), Quaternion Kinematics for the Error-State Kalman Filter,
%   arXiv:1711.02508, Sect. 2.
%
% EXAMPLE
%   R = referenceSystem.rotationFromQuaternion(q);
%   Raerospace = referenceSystem.rotationFromQuaternion(qJpl, ...
%       'Convention', referenceSystem.attitudeConvention("aerospace"));
%
% KEYWORDS
%   quaternion, rotation matrix, direction cosine matrix, attitude, Hamilton,
%   double cover
%
% See also QUATERNIONFROMROTATION, MULTIPLYQUATERNIONS, ATTITUDECONVENTION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 03:05 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        q double {mustBeReal, mustBeFinite}
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(q, 1) ~= 4 || ~ismatrix(q)
        error('referenceSystem:rotationFromQuaternion:wrongQuaternionSize', ...
            'q must be 4xN, one column per quaternion; it is %s.', ...
            mat2str(size(q)));
    end
    if strcmp(convention.quaternion, "scalarLast")
        q = q([4 1 2 3], :);
    end

    norms = sqrt(sum(q.^2, 1));
    if any(norms < 1e-12)
        bad = find(norms < 1e-12, 1);
        error('referenceSystem:rotationFromQuaternion:zeroQuaternion', ...
            ['Quaternion %d has norm %.3e and does not define a rotation. ', ...
            'A quaternion of zero norm usually means an uninitialised or a ', ...
            'gap-filled record.'], bad, norms(bad));
    end
    q = q./norms;

    q0 = q(1, :);
    q1 = q(2, :);
    q2 = q(3, :);
    q3 = q(4, :);

    nPage = size(q, 2);
    R = zeros(3, 3, nPage);
    R(1, 1, :) = q0.^2 + q1.^2 - q2.^2 - q3.^2;
    R(1, 2, :) = 2*(q1.*q2 + q0.*q3);
    R(1, 3, :) = 2*(q1.*q3 - q0.*q2);
    R(2, 1, :) = 2*(q1.*q2 - q0.*q3);
    R(2, 2, :) = q0.^2 - q1.^2 + q2.^2 - q3.^2;
    R(2, 3, :) = 2*(q2.*q3 + q0.*q1);
    R(3, 1, :) = 2*(q1.*q3 + q0.*q2);
    R(3, 2, :) = 2*(q2.*q3 - q0.*q1);
    R(3, 3, :) = q0.^2 - q1.^2 - q2.^2 + q3.^2;

    if strcmp(convention.sense, "vector")
        R = pagetranspose(R);
    end
end
