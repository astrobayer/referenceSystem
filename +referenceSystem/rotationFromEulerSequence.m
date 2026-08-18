function R = rotationFromEulerSequence(angles, options)
%ROTATIONFROMEULERSEQUENCE Rotation matrix from an Euler angle sequence.
%
%   R = rotationFromEulerSequence(angles) builds the 3x3xN rotation from the
%   3xN angles, using the sequence and the intrinsic or extrinsic rule named by
%   the convention. All twelve sequences are supported.
%
%   R = rotationFromEulerSequence(angles, 'Convention', c) selects the
%   sequence, the rotation type and the sense.
%   R = rotationFromEulerSequence(angles, 'AngleUnit', "deg") takes degrees.
%
% INPUT ARGUMENTS
%   Name     Size   Type     Units    Description
%   ----     ----   ----     -----    -----------
%   angles   3xN    double   rad|deg  Rotation angles, in the order in which the
%                                     sequence names the axes: row 1 is the
%                                     rotation about the first named axis. A 3x1
%                                     column is one set; N columns are N sets.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                Description
%   ----         ----   ----     -------                -----------
%   AngleUnit    1x1    string   "rad"                  "rad" or "deg".
%   Convention   1x1    struct   attitudeConvention()   .sequence, .rotationType
%                                                       and .sense are read.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   R      3x3xN    double   -      Rotation matrices, one page per angle set.
%
% METHOD
%   THE EXTRINSIC FORM IS PRIMITIVE and the intrinsic form is derived from it,
%   rather than writing twenty-four cases. For an extrinsic sequence (i,j,k),
%   whose rotations are all about the fixed space axes, the matrices multiply in
%   the order the sequence is written:
%
%       R = A_i(a1) * A_j(a2) * A_k(a3)
%
%   with A the elementary frame rotations rotationX, rotationY, rotationZ. The
%   intrinsic form, whose rotations are about the axes carried by the body, is
%   the exact reversal of both the sequence and the angles:
%
%       intrinsic (i,j,k) with (a1,a2,a3)  ==  extrinsic (k,j,i) with (a3,a2,a1)
%
%   so intrinsic ZYX equals extrinsic XYZ with the angles reversed. This is an
%   identity, not an approximation, and it is asserted as a precision test.
%
%   With the default frame (passive) sense and the intrinsic ZYX sequence,
%   angles = [yaw; pitch; roll] gives the classical
%   R = rotationX(roll)*rotationY(pitch)*rotationZ(yaw), the matrix that takes
%   a vector's components in the local level frame to its components in the
%   body frame. Sign check: with yaw = +30 deg alone, the east axis of the ENU
%   frame maps to R*[1;0;0] = [cos30; -sin30; 0], that is, the body x axis has
%   swung 30 degrees towards north, which is a positive right-handed rotation
%   about up.
%
%   THE SEQUENCE IS READ FROM THE CONVENTION AND FROM NOWHERE ELSE. There is no
%   'Sequence' argument, because a sequence given in two places is a sequence
%   that can disagree with itself, and no wrong combination of sequence and
%   rotation type produces a matrix that looks wrong. Use a different sequence
%   by deriving a convention that names it; the derived struct is validated on
%   entry like any other.
%
% ACCURACY
%   Exact to machine precision. The matrix is a product of three exact
%   elementary rotations, so the orthogonality residual max|R'R - I| is a few
%   units in the last place; measured 6.7e-16 over the random sweep of all
%   twelve sequences in TestRotationAlgebra. There is no angle at which the
%   construction degrades: gimbal lock is a property of the inverse problem,
%   not of this one.
%
% ERRORS
%   referenceSystem:rotationFromEulerSequence:wrongAngleSize
%   referenceSystem:rotationFromEulerSequence:sequenceRequired
%
% REFERENCES
%   J. Diebel (2006), Representing Attitude: Euler Angles, Unit Quaternions,
%   and Rotation Vectors, Stanford University, Sect. 5.
%   M. D. Shuster (1993), A Survey of Attitude Representations, JAS 41(4).
%
% EXAMPLE
%   R = referenceSystem.rotationFromEulerSequence([yaw; pitch; roll]);
%
%   c = referenceSystem.attitudeConvention();
%   c.sequence = "ZXZ";
%   c.source = "classical Euler angles";
%   R = referenceSystem.rotationFromEulerSequence(angles, 'Convention', c);
%
% KEYWORDS
%   Euler angles, sequence, intrinsic, extrinsic, Tait-Bryan, rotation matrix,
%   direction cosine matrix, attitude
%
% See also EULERSEQUENCEFROMROTATION, ROTATIONFROMROLLPITCHYAW, ATTITUDECONVENTION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 02:20 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        angles double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(angles, 1) ~= 3 || ~ismatrix(angles)
        error('referenceSystem:rotationFromEulerSequence:wrongAngleSize', ...
            'angles must be 3xN, one column per angle set; it is %s.', ...
            mat2str(size(angles)));
    end
    if strlength(convention.sequence) ~= 3
        error('referenceSystem:rotationFromEulerSequence:sequenceRequired', ...
            ['The convention names no Euler sequence. Set .sequence to one ', ...
            'of the twelve, for example "ZYX".']);
    end

    if strcmp(options.AngleUnit, "deg")
        angles = deg2rad(angles);
    end

    sequence = char(convention.sequence);
    if strcmp(convention.rotationType, "intrinsic")
        sequence = sequence(end:-1:1);
        angles = angles(end:-1:1, :);
    end

    R = pagemtimes(pagemtimes( ...
        elementary(sequence(1), angles(1, :)), ...
        elementary(sequence(2), angles(2, :))), ...
        elementary(sequence(3), angles(3, :)));

    if strcmp(convention.sense, "vector")
        R = pagetranspose(R);
    end
end

% -------------------------------------------------------------------------

function A = elementary(axis, angle)
%ELEMENTARY One elementary frame rotation, dispatched on the axis letter.
%   Held local rather than calling the sibling rotationX/Y/Z so that the
%   convention is applied once, at the end, to the assembled product instead of
%   three times to the factors - which would transpose the factors without
%   reversing their order and silently give the wrong matrix for the "vector"
%   sense. The arithmetic is identical to the siblings and the agreement is a
%   reference test.

    nAngle = numel(angle);
    cosAngle = reshape(cos(angle), 1, 1, nAngle);
    sinAngle = reshape(sin(angle), 1, 1, nAngle);
    A = zeros(3, 3, nAngle);

    if axis == 'X'
        A(1, 1, :) = 1;
        A(2, 2, :) = cosAngle;
        A(2, 3, :) = sinAngle;
        A(3, 2, :) = -sinAngle;
        A(3, 3, :) = cosAngle;
    elseif axis == 'Y'
        A(1, 1, :) = cosAngle;
        A(1, 3, :) = -sinAngle;
        A(2, 2, :) = 1;
        A(3, 1, :) = sinAngle;
        A(3, 3, :) = cosAngle;
    else
        A(1, 1, :) = cosAngle;
        A(1, 2, :) = sinAngle;
        A(2, 1, :) = -sinAngle;
        A(2, 2, :) = cosAngle;
        A(3, 3, :) = 1;
    end
end
