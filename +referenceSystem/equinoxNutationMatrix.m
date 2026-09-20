function npb = equinoxNutationMatrix(epoch)
%EQUINOXNUTATIONMATRIX Classical nutation-precession-bias matrix, IAU 2006/2000A.
%
%   npb = equinoxNutationMatrix(epochTt)
%
%   Returns the equinox-based rotation from the GCRS to the true equatorial
%   system of date. This is the classical counterpart of the CIO-based
%   rotationGcrsToCirs, and it exists as a VALIDATION ASSET rather than as an
%   alternative transformation path.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, scale TT.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   npb    3x3xN    double   -      GCRS to true equator and equinox of date,
%                                   one page per epoch. For N = 1 the result
%                                   is 3x3.
%
% METHOD
%   SOFA iauPnm06a, unmodified: frame bias, IAU 2006 precession and IAU 2000A
%   nutation composed into one matrix.
%
%   WHY THIS IS PUBLIC AND WHY IT IS NOT A TRANSFORMATION PATH (risk R13b,
%   decision D16). The toolbox transforms through the CIO and the Earth
%   rotation angle, and there is deliberately no user-facing 'Formulation'
%   option choosing between the two conventions: two paths would mean two error
%   budgets, two sets of tests and a silent choice for anyone who did not read
%   the documentation.
%
%   The classical route is kept for one purpose. Combined with
%   greenwichSiderealTime it builds the same rotation by a route that shares
%   almost no arithmetic with the CIO route, so differencing the two is an
%   independent check that the CIO chain is right and not merely
%   self-consistent. TestRotation runs that check over an epoch sweep on every
%   test run. Exposing the ingredient as a function is what makes the check
%   reproducible by a user rather than a private assertion.
%
%   The relation between the two, for a caller who wants to reproduce it:
%
%       Rz(-(ERA - GAST)) * npb  ==  rotationGcrsToCirs(X, Y, s)
%
%   with ERA - GAST the equation of the origins, the distance from the equinox
%   to the CIO.
%
%   NO OBSERVED POLE OFFSETS ARE APPLIED HERE. In the equinox parameterisation
%   the offsets are dPsi and dEpsilon rather than dX and dY, and converting
%   between the two is a separate approximation that readEop owns under
%   decision D56. Mixing it in here would confuse a conversion residual with a
%   model inconsistency, which is exactly what the cross-check exists to
%   separate.
%
% ACCURACY
%   Agreement with the CIO route, measured over twelve epochs spanning 1990 to
%   2050 with no observed offsets on either side: 4.4e-16 rad worst matrix
%   element, that is 9.1e-5 microarcseconds. The two conventions agree at the
%   level of double-precision arithmetic, three orders inside the 1
%   microarcsecond the design asked for.
%
%   Orthogonality better than 1.1e-16 in max |npb'npb - I|.
%
% ERRORS
%   referenceSystem:equinoxNutationMatrix:wrongScale
%   referenceSystem:equinoxNutationMatrix:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.4.5 and 5.5.7.
%   IAU SOFA release 20231011, iauPnm06a.
%   SOFA Tools for Earth Attitude, sofa_pn_c.pdf, sections 5.4 and 5.5.
%
% EXAMPLE
%   tt = referenceSystem.daySecondToEpoch([54195 43265.184], "TT");
%   npb = referenceSystem.equinoxNutationMatrix(tt);
%   assert(norm(npb' * npb - eye(3)) < 1e-15);
%
% KEYWORDS
%   nutation, precession, frame bias, equinox, NPB, cross-check, SOFA
%
% See also ROTATIONGCRSTOCIRS, GREENWICHSIDEREALTIME, ROTATIONITRSTOGCRS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 23:00 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "TT"
        error('referenceSystem:equinoxNutationMatrix:wrongScale', ...
            ['Precession and nutation are functions of TT and this epoch ', ...
            'is %s. Convert it deliberately with convertTimeScale.'], ...
            epoch.scale);
    end

    try
        npb = mexGateway('pnm06a', epoch.day, epoch.sec);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:equinoxNutationMatrix:gatewayMissing', ...
                ['The nutation series is evaluated in C through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end
end
