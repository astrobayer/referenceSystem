function [q, stepAngle] = composeRotationVectors(startQuaternion, ...
        rotationVector, renormalizeEvery)
%COMPOSEROTATIONVECTORS Propagate an attitude through a series of rotation vectors.
%
%   [q, stepAngle] = composeRotationVectors(startQuaternion, rotationVector,
%   renormalizeEvery) exponentiates each column of rotationVector and composes
%   it onto the running attitude from the RIGHT, returning the attitude at the
%   start and after every step.
%
%   PACKAGE-PRIVATE. It is the single authority for the exponential map and for
%   the composition loop, reached by integrateAttitude and by
%   integrateAttitudeIncrements. Neither owns a copy. The two functions differ
%   only in how they form their rotation vectors — one from a sampled rate, one
%   from integrated increments — and that difference is the whole of what
%   separates them; everything downstream of it is here.
%
% INPUT ARGUMENTS
%   Name               Size   Type     Units  Description
%   ----               ----   ----     -----  -----------
%   startQuaternion    4x1    double   -      Attitude at the first epoch,
%                                             scalar first, ALREADY unit and
%                                             already in the internal
%                                             convention. Not re-normalised.
%   rotationVector     3xM    double   rad    One rotation vector per interval.
%   renormalizeEvery   1x1    double   -      Steps between renormalisations.
%
% OUTPUT ARGUMENTS
%   Name         Size      Type     Units  Description
%   ----         ----      ----     -----  -----------
%   q            4x(M+1)   double   -      Attitude at each epoch, column one
%                                          being startQuaternion. SIGN
%                                          CONTINUOUS along the series.
%   stepAngle    1xM       double   rad    Magnitude of each rotation vector.
%
% METHOD
%   THE INCREMENT JOINS ON THE RIGHT: q_next = q (x) exp(phi), because phi is
%   resolved in the BODY frame. Exponentiating once per interval makes each
%   step an exact rotation whatever its size, so the attitude cannot leave the
%   unit sphere by an amount that depends on the step.
%
%   THE CANONICAL q0 >= 0 FORM IS DELIBERATELY NOT IMPOSED. The loop never
%   flips a sign, so the series stays continuous through a rotation of 180
%   degrees, where the canonical form is a coin toss and would inject a
%   discontinuity into anything that differentiates the output.
%
%   THE HAMILTON PRODUCT IS LOCAL AND IS NOT multiplyQuaternions, deliberately.
%   The L4b product normalises its result and imposes the canonical sign on
%   every call; inside a 10^4-step loop that is one square root and one sign
%   test per step for a postcondition this loop must then undo. The ALGEBRA is
%   identical and is asserted identical against the L4b authority by
%   integrateAttitude_precision_localProductMatchesTheAuthority at 1e-15.
%
%   ONE NORM, NOT TWO. The step angle and the half-angle sine are both taken
%   from sqrt(sum(v.^2)), where the loop this replaced computed the reported
%   angle with norm() and the propagated angle with sqrt(sum()). The two agree
%   to a unit in the last place and there was no reason for both to exist.
%
% ACCURACY
%   The composition itself is exact to rounding: 10^4 steps of a constant
%   0.032 rad/s rate reproduce the analytic single-axis answer to
%   max|q - exact| = 1.13e-14, which is accumulated rounding alone. What limits
%   a propagation is the rotation vector it is handed, not this function.
%
%   The half-angle sine is evaluated as sin(a/2)/a rather than as a ratio that
%   loses significance at small angles; below 1e-8 rad the series 0.5 - a^2/48
%   is correctly rounded, and the branch is exact to 1e-17 in the overlap.
%
% ERRORS
%   None. Every argument is validated by the caller, which is a package
%   function; this is not reachable from outside the namespace.
%
% REFERENCES
%   Bortz, J. E. (1971), A new mathematical formulation for strapdown inertial
%   navigation, IEEE Trans. Aerospace Electron. Syst. AES-7(1), 61-66.
%
% EXAMPLE
%   q = composeRotationVectors([1; 0; 0; 0], [0.01 0.01; 0 0; 0 0], 1);
%
% KEYWORDS
%   attitude, quaternion, rotation vector, exponential map, strapdown
%
% See also INTEGRATEATTITUDE, INTEGRATEATTITUDEINCREMENTS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 23:55 (CEST, UTC+02:00) - session S9, prompt P27b
% -------------------------------------------------------------------------

    stepCount = size(rotationVector, 2);
    q = zeros(4, stepCount + 1);
    q(:, 1) = startQuaternion;
    stepAngle = sqrt(sum(rotationVector.^2, 1));

    current = startQuaternion;
    for k = 1:stepCount
        current = hamiltonProduct(current, ...
            exponentialQuaternion(rotationVector(:, k), stepAngle(k)));
        if mod(k, renormalizeEvery) == 0 || k == stepCount
            current = current/sqrt(sum(current.^2));
        end
        q(:, k+1) = current;
    end
end

% -------------------------------------------------------------------------

function q = hamiltonProduct(first, second)
%HAMILTONPRODUCT Scalar-first Hamilton product of two unit quaternions.

    q = [first(1)*second(1) - first(2:4).'*second(2:4); ...
        first(1)*second(2:4) + second(1)*first(2:4) + ...
        cross(first(2:4), second(2:4))];
end

% -------------------------------------------------------------------------

function q = exponentialQuaternion(rotationVector, angle)
%EXPONENTIALQUATERNION Unit quaternion of a rotation vector, frame sense.
%   The angle is passed in rather than recomputed, so the value that scales the
%   vector and the value the caller reports are the same number by
%   construction and cannot drift apart.

    if angle < 1e-8
        halfSinc = 0.5 - angle^2/48;
    else
        halfSinc = sin(angle/2)/angle;
    end
    q = [cos(angle/2); rotationVector*halfSinc];
end
