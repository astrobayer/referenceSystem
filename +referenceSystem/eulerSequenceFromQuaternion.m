function [angles, info] = eulerSequenceFromQuaternion(q, options)
%EULERSEQUENCEFROMQUATERNION Euler angles of a quaternion, all twelve sequences.
%
%   angles = eulerSequenceFromQuaternion(q) extracts the 3xN Euler angles of the
%   4xN quaternions for the sequence named by the convention.
%
%   [angles, info] = eulerSequenceFromQuaternion(q) also reports the convention
%   used and which quaternions were at gimbal lock.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   q      4xN    double   -      Quaternions, one column each, in the row order
%                                 named by the convention.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name            Size   Type     Default                Description
%   ----            ----   ----     -------                -----------
%   AngleUnit       1x1    string   "rad"                  Unit of the output.
%   Convention      1x1    struct   attitudeConvention()   .sequence,
%                                                          .rotationType, .sense,
%                                                          .quaternion.
%   LockTolerance   1x1    double   1e-7                   Gimbal-lock threshold.
%
% OUTPUT ARGUMENTS
%   Name     Size   Type     Units    Description
%   ----     ----   ----     -----    -----------
%   angles   3xN    double   rad|deg  Angles in the order the sequence names the
%                                     axes, ranges as eulerSequenceFromRotation.
%   info     1x1    struct   -        As eulerSequenceFromRotation.
%
% METHOD
%   The quaternion is turned into a rotation matrix and the angles are extracted
%   from it by eulerSequenceFromRotation. THE ROUND TRIP IS DELIBERATE AND IT IS
%   EXACT: a matrix built from a unit quaternion is orthogonal to 2.6e-16, and
%   the extraction is a ratio of matrix elements, so nothing is lost.
%
%   The alternative - extracting the angles from the quaternion components
%   directly - would need its own copy of the twelve-sequence index and parity
%   logic, and that logic is the part of this family that is hard to get right:
%   the Python cross-check written before this code found a sign error in one
%   branch of it. A second copy would be a second place for that error to live,
%   which is the two-sources-of-truth pattern (findings M-2, C-2, decision D27).
%   The nine multiplications saved are not worth it. quaternionFromEulerSequence
%   does take the direct path in the other direction, because building is short
%   and shares no logic with the extraction.
%
% ACCURACY
%   Agrees with the matrix route to 4.4e-16 rad, which is the accuracy of the
%   extraction itself; see eulerSequenceFromRotation for the conditioning near
%   gimbal lock and for what the reported lock means.
%
% ERRORS
%   referenceSystem:eulerSequenceFromQuaternion:wrongQuaternionSize
%   referenceSystem:eulerSequenceFromQuaternion:sequenceRequired
%
% WARNINGS
%   referenceSystem:eulerSequenceFromRotation:gimbalLock
%
% REFERENCES
%   E. Bernardes and S. Viollet (2022), Quaternion to Euler angles conversion,
%   PLoS ONE 17(11), e0276302.
%   J. Diebel (2006), Representing Attitude, Stanford University, Sect. 5.
%
% EXAMPLE
%   angles = referenceSystem.eulerSequenceFromQuaternion(q, 'AngleUnit', "deg");
%
% KEYWORDS
%   quaternion, Euler angles, extraction, gimbal lock, attitude, sequence
%
% See also QUATERNIONFROMEULERSEQUENCE, EULERSEQUENCEFROMROTATION, ROTATIONFROMQUATERNION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 04:00 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        q double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
        options.LockTolerance (1,1) double {mustBePositive, mustBeFinite} = 1e-7
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(q, 1) ~= 4 || ~ismatrix(q)
        error('referenceSystem:eulerSequenceFromQuaternion:wrongQuaternionSize', ...
            'q must be 4xN, one column per quaternion; it is %s.', ...
            mat2str(size(q)));
    end
    if strlength(convention.sequence) ~= 3
        error('referenceSystem:eulerSequenceFromQuaternion:sequenceRequired', ...
            ['The convention names no Euler sequence. Set .sequence to one ', ...
            'of the twelve, for example "ZYX".']);
    end

    R = referenceSystem.rotationFromQuaternion(q, 'Convention', convention);
    [angles, info] = referenceSystem.eulerSequenceFromRotation(R, ...
        'AngleUnit', options.AngleUnit, 'Convention', convention, ...
        'LockTolerance', options.LockTolerance);
end
