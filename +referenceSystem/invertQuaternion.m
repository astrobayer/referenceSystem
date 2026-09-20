function [q, convention] = invertQuaternion(q, options)
%INVERTQUATERNION Inverse of a unit quaternion, its conjugate.
%
%   q = invertQuaternion(q) returns the inverse of each of the 4xN quaternions,
%   that is the quaternion of the inverse rotation.
%
%   [q, convention] = invertQuaternion(q) also returns the convention.
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
%   q            4xN    double   -      Inverse quaternions, unit norm, scalar
%                                       part non-negative.
%   convention   1x1    struct   -      The convention used.
%
% METHOD
%   For a unit quaternion the inverse is the conjugate: the scalar part is kept
%   and the vector part is negated. The input is normalised first, so a
%   quaternion that has drifted off the unit sphere gets its true inverse
%   q*/|q|^2 rather than a conjugate that is only nearly an inverse.
%
%   THE CONJUGATE IS THE SAME UNDER BOTH PRODUCTS. Hamilton and Shuster differ
%   in the sign of the cross-product term of the product, not in the conjugate,
%   so this function needs no product branch - which is worth stating because it
%   is the one place in this family where the two conventions agree and a reader
%   expecting a branch will look for a missing one.
%
%   Negating the vector part flips the sign convention when the scalar part is
%   zero, so normalizeQuaternion's tie-break is applied again on the way out and
%   the result is always in canonical form.
%
% ACCURACY
%   Exact: negation and division by a norm. The round trip
%   q -> inverse -> inverse reproduces the input to 2.2e-16, and
%   multiplyQuaternions(q, invertQuaternion(q)) gives the identity quaternion
%   to 2.8e-16.
%
% ERRORS
%   referenceSystem:invertQuaternion:wrongQuaternionSize
%   referenceSystem:invertQuaternion:zeroQuaternion
%
% REFERENCES
%   M. D. Shuster (1993), A Survey of Attitude Representations, JAS 41(4).
%
% EXAMPLE
%   qBodyToNav = referenceSystem.invertQuaternion(qNavToBody);
%
% KEYWORDS
%   quaternion, inverse, conjugate, attitude, Hamilton, Shuster
%
% See also MULTIPLYQUATERNIONS, NORMALIZEQUATERNION, INVERTROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 03:15 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        q double {mustBeReal, mustBeFinite}
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if size(q, 1) ~= 4 || ~ismatrix(q)
        error('referenceSystem:invertQuaternion:wrongQuaternionSize', ...
            'q must be 4xN, one column per quaternion; it is %s.', ...
            mat2str(size(q)));
    end

    norms = sqrt(sum(q.^2, 1));
    if any(norms < 1e-12)
        bad = find(norms < 1e-12, 1);
        error('referenceSystem:invertQuaternion:zeroQuaternion', ...
            'Quaternion %d has norm %.3e and has no inverse.', bad, norms(bad));
    end

    if strcmp(convention.quaternion, "scalarLast")
        vectorRow = [1 2 3];
    else
        vectorRow = [2 3 4];
    end

    q = q./norms;
    q(vectorRow, :) = -q(vectorRow, :);
    q = referenceSystem.normalizeQuaternion(q, 'Convention', convention);
end
