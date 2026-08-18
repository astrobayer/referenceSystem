function [rollPitchYaw, info] = rollPitchYawFromRotation(R, options)
%ROLLPITCHYAWFROMROTATION Roll, pitch and yaw of a rotation.
%
%   rollPitchYaw = rollPitchYawFromRotation(R) extracts the 3xN angles
%   [roll; pitch; yaw] from the 3x3xN rotation, that is, the intrinsic ZYX Euler
%   angles in the order navigation users expect.
%
%   [rollPitchYaw, info] = rollPitchYawFromRotation(R) also reports the
%   convention used and which pages were at gimbal lock.
%
% INPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   R      3x3xN    double   -      Rotation matrices, one page per angle set.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name            Size   Type     Default                Description
%   ----            ----   ----     -------                -----------
%   AngleUnit       1x1    string   "rad"                  Unit of the output.
%   Convention      1x1    struct   attitudeConvention()   .sense is read; the
%                                                          sequence must be ZYX
%                                                          intrinsic or empty.
%   LockTolerance   1x1    double   1e-7                   Gimbal-lock threshold.
%
% OUTPUT ARGUMENTS
%   Name           Size   Type     Units    Description
%   ----           ----   ----     -----    -----------
%   rollPitchYaw   3xN    double   rad|deg  Row 1 roll, row 2 pitch, row 3 yaw.
%                                           Pitch lies in [-pi/2, pi/2]; roll and
%                                           yaw lie in (-pi, pi].
%   info           1x1    struct   -        As eulerSequenceFromRotation.
%
% METHOD
%   The rows of eulerSequenceFromRotation's ZYX intrinsic output, reversed. See
%   that function for the extraction itself; nothing is recomputed here.
%
%   GIMBAL LOCK IS AT PITCH = PLUS OR MINUS 90 DEGREES, where the roll and yaw
%   axes coincide and only their difference is determined. The convention there
%   is yaw = 0 with the whole of the determined combination carried by roll, and
%   one warning is raised per call stating how many pages were affected. A
%   vehicle passing through the vertical therefore produces a warning and a
%   discontinuity in roll and yaw, which is a property of the parameterisation
%   and not of this code; integrate attitude as a quaternion or a matrix and
%   convert for display only.
%
% ACCURACY
%   Round trip to a few units in the last place away from the singularity,
%   measured 8.9e-16 on the matrix and 4.4e-16 rad on the angles. Within the
%   default 1e-7 threshold of vertical pitch, roll and yaw individually carry
%   about 1e-9 rad while their difference and the rebuilt matrix stay exact.
%
% ERRORS
%   referenceSystem:rollPitchYawFromRotation:wrongMatrixSize
%   referenceSystem:rollPitchYawFromRotation:conventionMismatch
%
% WARNINGS
%   referenceSystem:eulerSequenceFromRotation:gimbalLock
%
% REFERENCES
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.2.
%
% EXAMPLE
%   rpy = referenceSystem.rollPitchYawFromRotation(R, 'AngleUnit', "deg");
%
% KEYWORDS
%   roll, pitch, yaw, heading, attitude, gimbal lock, ZYX, body frame
%
% See also ROTATIONFROMROLLPITCHYAW, EULERSEQUENCEFROMROTATION, ATTITUDECONVENTION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 02:45 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        R double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
        options.LockTolerance (1,1) double {mustBePositive, mustBeFinite} = 1e-7
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(R, 1) ~= 3 || size(R, 2) ~= 3 || ndims(R) > 3
        error('referenceSystem:rollPitchYawFromRotation:wrongMatrixSize', ...
            'R must be 3x3 or 3x3xN; it is %s.', mat2str(size(R)));
    end
    if ~(strcmp(convention.sequence, "ZYX") || strcmp(convention.sequence, "")) ...
            || strcmp(convention.rotationType, "extrinsic")
        error('referenceSystem:rollPitchYawFromRotation:conventionMismatch', ...
            ['Roll, pitch and yaw are the intrinsic ZYX angles by definition, ', ...
            'but the convention names %s %s.'], convention.rotationType, ...
            convention.sequence);
    end

    convention.sequence = "ZYX";
    convention.rotationType = "intrinsic";
    [angles, info] = referenceSystem.eulerSequenceFromRotation(R, ...
        'AngleUnit', options.AngleUnit, 'Convention', convention, ...
        'LockTolerance', options.LockTolerance);
    rollPitchYaw = angles(3:-1:1, :);
end
