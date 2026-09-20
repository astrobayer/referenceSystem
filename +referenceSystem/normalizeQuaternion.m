function [q, convention] = normalizeQuaternion(q, options)
%NORMALIZEQUATERNION Unit norm and a consistent sign for a quaternion series.
%
%   q = normalizeQuaternion(q) scales each of the 4xN quaternions to unit norm
%   and fixes the sign so that the scalar part is non-negative.
%
%   [q, convention] = normalizeQuaternion(q) also returns the convention.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   q      4xN    double   -      Quaternions, one column each, in the row order
%                                 named by the convention.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default                Description
%   ----         ----   ----     -------                -----------
%   Convention   1x1    struct   attitudeConvention()   .quaternion is read.
%
% OUTPUT ARGUMENTS
%   Name         Size   Type     Units  Description
%   ----         ----   ----     -----  -----------
%   q            4xN    double   -      Unit quaternions with scalar part >= 0.
%   convention   1x1    struct   -      The convention used.
%
% METHOD
%   Two separate jobs, both of which have to be done somewhere and neither of
%   which is arithmetic on the rotation.
%
%   UNIT NORM. A quaternion drifts off the unit sphere through integration or
%   through interpolation. The rotation it then represents is scaled by the
%   square of the norm, so the matrix is no longer orthogonal and its transpose
%   is no longer its inverse.
%
%   CONSISTENT SIGN. q and -q are the same rotation, so nothing downstream that
%   only builds a matrix can tell them apart - but everything that treats the
%   quaternion as a point in R4 can. A sign flip in the middle of a series puts
%   a 180 degree discontinuity into any interpolation, any difference and any
%   filter innovation, and it is invisible in the attitude itself. The rule
%   applied here is q0 >= 0, the same rule quaternionFromRotation applies, so
%   the two agree by construction.
%
%   The rule cannot fix a series that is already discontinuous in a different
%   way; it makes every quaternion lie in the same half of the sphere, which is
%   what an interpolator needs. It is applied per column and is exact: negating
%   a double changes only the sign bit.
%
% ACCURACY
%   The norm after scaling differs from unity by at most one unit in the last
%   place, measured 2.2e-16. The direction is unchanged to the same order; the
%   rotation the quaternion represents is not touched.
%
%   A quaternion with q0 exactly zero is a rotation of exactly 180 degrees and
%   is the one case where the sign rule cannot choose. The tie is broken on the
%   first nonzero component in the order q1, q2, q3, which is documented rather
%   than arbitrary so that two callers agree.
%
% ERRORS
%   referenceSystem:normalizeQuaternion:wrongQuaternionSize
%   referenceSystem:normalizeQuaternion:zeroQuaternion
%
% REFERENCES
%   M. D. Shuster (1993), A Survey of Attitude Representations, JAS 41(4).
%
% EXAMPLE
%   q = referenceSystem.normalizeQuaternion(qFromFile);
%
% KEYWORDS
%   quaternion, normalisation, unit norm, sign convention, double cover,
%   attitude series
%
% See also QUATERNIONFROMROTATION, INVERTQUATERNION, MULTIPLYQUATERNIONS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 03:10 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        q double {mustBeReal, mustBeFinite}
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(q, 1) ~= 4 || ~ismatrix(q)
        error('referenceSystem:normalizeQuaternion:wrongQuaternionSize', ...
            'q must be 4xN, one column per quaternion; it is %s.', ...
            mat2str(size(q)));
    end

    norms = sqrt(sum(q.^2, 1));
    if any(norms < 1e-12)
        bad = find(norms < 1e-12, 1);
        error('referenceSystem:normalizeQuaternion:zeroQuaternion', ...
            'Quaternion %d has norm %.3e and cannot be normalised.', ...
            bad, norms(bad));
    end
    q = q./norms;

    if strcmp(convention.quaternion, "scalarLast")
        scalarRow = 4;
        vectorRow = [1 2 3];
    else
        scalarRow = 1;
        vectorRow = [2 3 4];
    end

    negate = q(scalarRow, :) < 0;
    tie = q(scalarRow, :) == 0;
    if any(tie)
        firstNonzero = zeros(1, sum(tie));
        vectorPart = q(vectorRow, tie);
        for row = 3:-1:1
            firstNonzero(vectorPart(row, :) ~= 0) = vectorPart(row, ...
                vectorPart(row, :) ~= 0);
        end
        negate(tie) = firstNonzero < 0;
    end
    q(:, negate) = -q(:, negate);
end
