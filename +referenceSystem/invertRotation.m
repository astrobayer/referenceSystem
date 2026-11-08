function [Rinv, RdotInv, RddotInv] = invertRotation(R, Rdot, Rddot, options)
%INVERTROTATION Inverse of a rotation and of its time derivatives.
%
%   Rinv = invertRotation(R)
%   [Rinv, RdotInv] = invertRotation(R, Rdot)
%   [Rinv, RdotInv, RddotInv] = invertRotation(R, Rdot, Rddot)
%   ... = invertRotation(..., 'Verify', true)
%
%   Returns the transposed set. For an orthogonal rotation the transpose is the
%   inverse exactly, and the derivative of the inverse is the transpose of the
%   derivative, so no arithmetic beyond the transposition is needed or done.
%
% INPUT ARGUMENTS
%   Name    Size     Type     Units    Description
%   ----    ----     ----     -----    -----------
%   R       3x3xN    double   -        Rotation, one page per epoch.
%   Rdot    3x3xN    double   1/s      First time derivative, optional.
%   Rddot   3x3xN    double   1/s^2    Second time derivative, optional.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name     Size   Type      Default   Description
%   ----     ----   ----      -------   -----------
%   Verify   1x1    logical   false     Check max |R'R - I| and error if it
%                                       exceeds 1e-12. Off by default; see
%                                       METHOD.
%
% OUTPUT ARGUMENTS
%   Name       Size     Type     Units    Description
%   ----       ----     ----     -----    -----------
%   Rinv       3x3xN    double   -        Transposed rotation.
%   RdotInv    3x3xN    double   1/s      Transposed first derivative.
%   RddotInv   3x3xN    double   1/s^2    Transposed second derivative.
%
% METHOD
%   R is a product of plane rotations, so R' R = I to about 1e-16 and R' is the
%   inverse with nothing to solve. Differentiating R' R = I gives
%   Rdot' R + R' Rdot = 0, from which d(R')/dt = (dR/dt)' - that is, the
%   transposed derivative is the derivative of the transpose, and the same
%   holds at second order. The whole function is therefore three pagetranspose
%   calls, and the reason it exists at all is that writing R.' by hand for a
%   3x3xN array transposes the wrong two dimensions.
%
%   ORTHOGONALITY IS A PROPERTY OF HOW R WAS BUILT, NOT OF THIS FUNCTION. The
%   rotations this toolbox returns are guaranteed orthogonal because section
%   B.9.1 rule 1 forbids interpolating a rotation matrix: interpolation is done
%   on the angles and the matrix is rebuilt, precisely so that this guarantee
%   survives. A matrix a caller built some other way - averaged, interpolated
%   element by element, read from a file, accumulated over an integration -
%   carries no such guarantee, and for such a matrix the transpose is only an
%   approximate inverse.
%
%   'Verify' exists for that case and defaults OFF. It is useful in a test and
%   wasteful in a hot loop, where it would add a full page product per call to
%   check a property that holds by construction. When it is on, the tolerance
%   is 1e-12 rather than 1e-15: the point is to catch a matrix that is not a
%   rotation at all, not to re-measure the last bits of one that is.
%
%   PREFER APPLYROTATION WHERE YOU CAN. If the inverse is wanted only in order
%   to apply it, applyRotation(..., 'Inverse', true) passes the transposition
%   to the BLAS as a flag and never forms the transposed array. This function
%   is for callers who want the matrices themselves.
%
% ACCURACY
%   Exact. A transposition moves values and does not compute, so the outputs
%   are bit-identical to the inputs, rearranged.
%
%   The claim that the transpose is the inverse is measured rather than
%   asserted: over the epoch sweep in TestRotation, max |R*R' - I| measures
%   4.4e-16, which is two units in the last place. That is the accumulation of
%   a three-term dot product of numbers of order unity and is what an exact
%   transpose of an orthogonal matrix is expected to give; the bound asserted
%   in the test is 1e-15, a few ulp, and not a measured constant.
%
%   An earlier revision of this block quoted 1.2e-16, imported from a C-level
%   measurement of R'R at a single epoch. That is a different product in a
%   different order over a different number of pages, and the test built on it
%   failed on its first run. A tolerance is a claim about which error
%   dominates (handover obligation O8): here the dominant error is
%   floating-point summation, whose scale is ulp, not a number carried over
%   from another experiment.
%
% ERRORS
%   referenceSystem:invertRotation:wrongMatrixSize
%   referenceSystem:invertRotation:notOrthogonal
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.1.
%
% EXAMPLE
%   [R, Rdot] = referenceSystem.rotationItrsToGcrs(epoch, 'Eop', eop);
%   [Rgcrs2itrs, RdotGcrs2itrs] = referenceSystem.invertRotation(R, Rdot);
%
% KEYWORDS
%   rotation, inverse, transpose, orthogonality, pagetranspose
%
% See also APPLYROTATION, ROTATIONITRSTOGCRS, ROTATIONGCRSTOCIRS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:35 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        R double
        Rdot double = zeros(3, 3, 0)
        Rddot double = zeros(3, 3, 0)
        options.Verify (1,1) logical = false
    end

    localCheck(R, "R");
    if options.Verify
        product = pagemtimes(R, 'transpose', R, 'none');
        residual = max(abs(product - eye(3)), [], 'all');
        if residual > 1e-12
            error('referenceSystem:invertRotation:notOrthogonal', ...
                ['max |R''R - I| is %.3e, above the 1e-12 bound, so the ', ...
                'transpose is not the inverse of this matrix. A rotation ', ...
                'built by interpolating matrix elements loses orthogonality ', ...
                'this way; interpolate the angles and rebuild the matrix ', ...
                'instead.'], residual);
        end
    end

    Rinv = pagetranspose(R);

    if nargout >= 2
        localCheck(Rdot, "Rdot");
        RdotInv = pagetranspose(Rdot);
    end
    if nargout >= 3
        localCheck(Rddot, "Rddot");
        RddotInv = pagetranspose(Rddot);
    end
end

% -------------------------------------------------------------------------

function localCheck(matrix, name)
%LOCALCHECK Require a 3x3 or 3x3xN array.

    if size(matrix, 1) ~= 3 || size(matrix, 2) ~= 3 || ndims(matrix) > 3
        error('referenceSystem:invertRotation:wrongMatrixSize', ...
            '%s must be 3x3 or 3x3xN; it is %s.', name, mat2str(size(matrix)));
    end
end
