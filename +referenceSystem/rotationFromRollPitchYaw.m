function R = rotationFromRollPitchYaw(rollPitchYaw, options)
%ROTATIONFROMROLLPITCHYAW Rotation matrix from roll, pitch and yaw.
%
%   R = rotationFromRollPitchYaw(rollPitchYaw) builds the 3x3xN rotation from
%   the 3xN angles [roll; pitch; yaw]. This is the intrinsic ZYX Euler sequence
%   under the names navigation users expect.
%
% INPUT ARGUMENTS
%   Name           Size   Type     Units    Description
%   ----           ----   ----     -----    -----------
%   rollPitchYaw   3xN    double   rad|deg  Row 1 roll (about the body x axis),
%                                           row 2 pitch (y), row 3 yaw (z).
%                                           Note the order: it is the reverse of
%                                           the ZYX sequence order.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                Description
%   ----         ----   ----     -------                -----------
%   AngleUnit    1x1    string   "rad"                  "rad" or "deg".
%   Convention   1x1    struct   attitudeConvention()   .sense is read; the
%                                                       sequence must be ZYX
%                                                       intrinsic or empty.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   R      3x3xN    double   -      Rotation matrices, one page per angle set.
%
% METHOD
%   A NAMED SPECIAL CASE, NOT A SECOND IMPLEMENTATION. Roll, pitch and yaw are
%   the intrinsic ZYX Euler angles listed in the reverse order, so this function
%   reverses the rows and calls rotationFromEulerSequence. Writing out the sines
%   and cosines again would be the two-sources-of-truth pattern in miniature;
%   the value here is the vocabulary and the argument order, which is where the
%   mistakes actually happen.
%
%   With the default frame (passive) sense the result is
%   R = rotationX(roll)*rotationY(pitch)*rotationZ(yaw), which takes a vector's
%   components in the local level frame to its components in the body frame.
%   The local level frame is the one named by convention.localFrame: ENU by
%   default, NED under the aerospace preset. THE ANGLES MEAN DIFFERENT THINGS
%   IN THE TWO, because the axes they turn about are different, and that is why
%   the local frame is part of the convention rather than an assumption.
%
%   A convention naming any sequence other than ZYX intrinsic is refused rather
%   than overridden: silently ignoring it would be exactly the failure this
%   toolbox exists to prevent, and both shipped presets already satisfy it.
%
% ACCURACY
%   Exact to machine precision; see rotationFromEulerSequence. Orthogonality
%   residual max|R'R - I| measured 6.7e-16.
%
% ERRORS
%   referenceSystem:rotationFromRollPitchYaw:wrongAngleSize
%   referenceSystem:rotationFromRollPitchYaw:conventionMismatch
%
% REFERENCES
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.2.
%   J. Diebel (2006), Representing Attitude, Stanford University, Sect. 5.2.
%
% EXAMPLE
%   R = referenceSystem.rotationFromRollPitchYaw([0.01; -0.02; 1.57]);
%   Rned = referenceSystem.rotationFromRollPitchYaw(rpy, ...
%       'Convention', referenceSystem.attitudeConvention("aerospace"));
%
% KEYWORDS
%   roll, pitch, yaw, heading, attitude, ZYX, Tait-Bryan, body frame, strapdown
%
% See also ROLLPITCHYAWFROMROTATION, ROTATIONFROMEULERSEQUENCE, ATTITUDECONVENTION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 02:40 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        rollPitchYaw double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(rollPitchYaw, 1) ~= 3 || ~ismatrix(rollPitchYaw)
        error('referenceSystem:rotationFromRollPitchYaw:wrongAngleSize', ...
            'rollPitchYaw must be 3xN, one column per angle set; it is %s.', ...
            mat2str(size(rollPitchYaw)));
    end
    if ~(strcmp(convention.sequence, "ZYX") || strcmp(convention.sequence, "")) ...
            || strcmp(convention.rotationType, "extrinsic")
        error('referenceSystem:rotationFromRollPitchYaw:conventionMismatch', ...
            ['Roll, pitch and yaw are the intrinsic ZYX angles by definition, ', ...
            'but the convention names %s %s. Use rotationFromEulerSequence for ', ...
            'that sequence, or a convention with .sequence = "ZYX" and ', ...
            '.rotationType = "intrinsic" here.'], convention.rotationType, ...
            convention.sequence);
    end

    convention.sequence = "ZYX";
    convention.rotationType = "intrinsic";
    R = referenceSystem.rotationFromEulerSequence(rollPitchYaw(3:-1:1, :), ...
        'AngleUnit', options.AngleUnit, 'Convention', convention);
end
