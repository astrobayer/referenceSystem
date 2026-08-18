function Q = rotationGcrsToCirs(X, Y, s)
%ROTATIONGCRSTOCIRS Celestial-to-intermediate rotation from the CIP and CIO.
%
%   Q = rotationGcrsToCirs(X, Y, s)
%
%   Returns the rotation from the Geocentric Celestial Reference System to the
%   Celestial Intermediate Reference System, built from the CIP coordinates and
%   the CIO locator. This is the precession-nutation-bias factor of the full
%   terrestrial-to-celestial rotation, in the CIO based form.
%
% INPUT ARGUMENTS
%   Name   Size        Type     Units  Description
%   ----   ----        ----     -----  -----------
%   X      Nx1         double   rad    CIP x-coordinate in the GCRS.
%   Y      1x1 | Nx1   double   rad    CIP y-coordinate in the GCRS.
%   s      1x1 | Nx1   double   rad    CIO locator.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   Q      3x3xN    double   -      Rotation GCRS to CIRS, one page per epoch.
%                                   For N = 1 MATLAB drops the trailing
%                                   singleton and the result is 3x3.
%
% METHOD
%   SOFA iauC2ixys, unmodified, evaluated in C. The matrix is
%
%       Q = R3(-(E + s)) * R2(d) * R3(E)
%
%   with E and d the spherical angles of the CIP unit vector, X = sin d cos E
%   and Y = sin d sin E. The construction is exact for any X and Y on the unit
%   sphere; no small-angle approximation is made, which matters because the
%   same function must serve epochs centuries from J2000.0 where the CIP has
%   moved by degrees.
%
%   The function takes X, Y and s rather than an epoch, deliberately. It is the
%   geometry and nothing else, so it can be driven by the modelled CIP from
%   cipCoordinates, by an observed one, or by a perturbed one in a partial
%   derivative study, without any of those having to pretend to be a time. The
%   epoch-driven convenience is rotationItrsToGcrs, which owns the whole chain.
%
%   NO DIRECTION OPTION (decision D23). Q is orthogonal, so the CIRS to GCRS
%   rotation is its transpose and needs no separate function, no flag and no
%   recomputation: use invertRotation, or applyRotation with 'Inverse', true,
%   which passes the transpose straight to pagemtimes at zero cost.
%
% ACCURACY
%   Orthogonality of the returned matrix is better than 1.1e-16 in
%   max |Q'Q - I|, measured over the epoch sweep of TestRotation, which is the
%   accumulation of the three exact plane rotations SOFA composes.
%
%   Against the SOFA cookbook worked example of 2007-04-05 (sofa_pn_c.pdf
%   section 5.5) the matrix elements reproduce to better than 3e-15.
%
%   Consistency with the classical equinox route, which is the independent
%   check that this is the right matrix and not merely a well-conditioned one:
%   Rz(-(ERA - GAST)) times the equinox-based nutation-precession-bias matrix
%   agrees element by element to 4.4e-16, that is 9.1e-5 microarcseconds, over
%   twelve epochs spanning 1990 to 2050.
%
% ERRORS
%   referenceSystem:rotationGcrsToCirs:sizeMismatch
%   referenceSystem:rotationGcrsToCirs:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.4.4, Eq. 5.10.
%   IAU SOFA release 20231011, iauC2ixys.
%
% EXAMPLE
%   tt = referenceSystem.daySecondToEpoch([54195 43265.184], "TT");
%   [X, Y, s] = referenceSystem.cipCoordinates(tt);
%   Q = referenceSystem.rotationGcrsToCirs(X, Y, s);
%   assert(norm(Q' * Q - eye(3)) < 1e-15);
%
% KEYWORDS
%   GCRS, CIRS, CIP, CIO, precession, nutation, rotation matrix, SOFA
%
% See also CIPCOORDINATES, ROTATIONTIRSTOITRS, ROTATIONITRSTOGCRS, APPLYROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        X (:,1) double
        Y (:,1) double
        s (:,1) double
    end

    epochCount = numel(X);
    Y = localBroadcast(Y, epochCount, "Y");
    s = localBroadcast(s, epochCount, "s");

    try
        Q = mexGateway('c2ixys', X, Y, s);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:rotationGcrsToCirs:gatewayMissing', ...
                ['The rotation is assembled in C through the MEX gateway, ', ...
                'which is not built. Run referenceSystem.buildMex once.']);
        end
        rethrow(cause);
    end
end

% -------------------------------------------------------------------------

function value = localBroadcast(value, epochCount, name)
%LOCALBROADCAST Expand a scalar to one value per epoch, or check the length.

    if isscalar(value)
        value = repmat(value, epochCount, 1);
    elseif numel(value) ~= epochCount
        error('referenceSystem:rotationGcrsToCirs:sizeMismatch', ...
            '%s must be scalar or hold %d values; it holds %d.', ...
            name, epochCount, numel(value));
    end
end
