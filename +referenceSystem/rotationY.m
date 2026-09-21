function R = rotationY(angle, options)
%ROTATIONY Elementary rotation about the y axis.
%
%   R = rotationY(angle) returns the 3x3xN frame rotation about the y axis
%   through each of the N angles.
%
%   R = rotationY(angle, 'AngleUnit', "deg") takes the angles in degrees.
%   R = rotationY(angle, 'Convention', c) selects the rotation sense from the
%   convention struct; "vector" returns the transpose of "frame".
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units    Description
%   ----    ----   ----     -----    -----------
%   angle   1xN    double   rad|deg  Rotation angles, one per output page. A
%                                    column vector is accepted and used as N
%                                    angles; the unit is set by 'AngleUnit'.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                  Description
%   ----         ----   ----     -------                  -----------
%   AngleUnit    1x1    string   "rad"                    "rad" or "deg".
%   Convention   1x1    struct   attitudeConvention()     Only .sense is read.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   R      3x3xN    double   -      Rotation matrices, one page per angle.
%
% METHOD
%   For the default frame (passive) sense the matrix is
%
%       [ cos(a)   0  -sin(a) ]
%       [   0      1     0    ]
%       [ sin(a)   0   cos(a) ]
%
%   which rotates the reference frame, not the vector: it is the matrix that
%   takes the components of a fixed vector in the old axes to its components in
%   the new ones. This is the sense of SOFA iauRy and of every rotation in
%   this toolbox, so the elementary rotations compose directly with the L2
%   Earth-rotation matrices. With 'Convention' set to the "vector" sense the
%   transpose is returned, which rotates the vector and leaves the axes fixed.
%
%   The whole matrix is built by page assignment rather than by a loop, so N
%   angles cost one sine, one cosine and one allocation.
%
% ACCURACY
%   Exact to machine precision: the four nonzero off-diagonal entries are the
%   sine and cosine of the argument, each correctly rounded, so the product
%   R'*R differs from the identity by at most a few units in the last place
%   (measured 2.2e-16 over the test sweep). Orthogonality does not degrade with
%   the size of the angle, and no angle is out of range.
%
% ERRORS
%   referenceSystem:rotationY:wrongAngleSize
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.4.
%   IAU SOFA release 20231011, routine iauRy.
%
% EXAMPLE
%   R = referenceSystem.rotationY(deg2rad(-20));
%   Renu = referenceSystem.rotationX(pi/2 - lat)*referenceSystem.rotationZ(lon + pi/2);
%
% KEYWORDS
%   rotation, elementary rotation, y axis, frame rotation, passive, direction
%   cosine matrix
%
% See also ROTATIONFROMEULERSEQUENCE, ATTITUDECONVENTION, APPLYROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 02:10 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        angle double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    if ~isempty(angle) && ~isvector(angle)
        error('referenceSystem:rotationY:wrongAngleSize', ...
            'angle must be a vector of N angles; it is %s.', mat2str(size(angle)));
    end
    convention = referenceSystem.attitudeConvention(options.Convention);

    angle = reshape(angle, 1, []);
    if strcmp(options.AngleUnit, "deg")
        angle = deg2rad(angle);
    end

    nAngle = numel(angle);
    cosAngle = reshape(cos(angle), 1, 1, nAngle);
    sinAngle = reshape(sin(angle), 1, 1, nAngle);

    R = zeros(3, 3, nAngle);
    R(1, 1, :) = cosAngle;
    R(1, 3, :) = -sinAngle;
    R(2, 2, :) = 1;
    R(3, 1, :) = sinAngle;
    R(3, 3, :) = cosAngle;

    if strcmp(convention.sense, "vector")
        R = pagetranspose(R);
    end
end
