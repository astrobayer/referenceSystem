function W = rotationTirsToItrs(xp, yp, sp)
%ROTATIONTIRSTOITRS Polar motion rotation from the pole coordinates.
%
%   W = rotationTirsToItrs(xp, yp, sp)
%
%   Returns the polar motion matrix, the rotation from the Terrestrial
%   Intermediate Reference System to the International Terrestrial Reference
%   System. It carries the motion of the CIP within the crust-fixed frame and
%   the position of the TIO on the equator.
%
% INPUT ARGUMENTS
%   Name   Size        Type     Units  Description
%   ----   ----        ----     -----  -----------
%   xp     Nx1         double   rad    Pole coordinate x, IERS convention.
%   yp     1x1 | Nx1   double   rad    Pole coordinate y, IERS convention.
%   sp     1x1 | Nx1   double   rad    TIO locator s'.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   W      3x3xN    double   -      Rotation TIRS to ITRS, one page per epoch.
%                                   For N = 1 the result is 3x3.
%
% METHOD
%   SOFA iauPom00, unmodified, evaluated in C:
%
%       W = R1(-yp) * R2(-xp) * R3(s')
%
%   THIS IS THE TRANSPOSE OF THE MATRIX IERS TN36 EQUATION 5.3 CALLS W, and
%   the difference is not cosmetic. Equation 5.3 writes
%
%       W(IERS) = R3(-s') * R2(xp) * R1(yp)
%
%   and equation 5.1 uses it as [GCRS] = Q R W(IERS) [ITRS], so the matrix
%   equation 5.3 defines is the ITRS to TIRS rotation. This function is named
%   for the direction it performs and returns the other one. The two differ by
%   4.7e-06 at the pole rates of 2007, which is 30 metres at the surface: large
%   enough to be obvious in a residual and small enough to survive every
%   orthogonality and round-trip check, since a transpose is still a rotation.
%   The code returns iauPom00.
%
%   RADIANS, NOT ARCSECONDS. The IERS publishes xp and yp in arcseconds and
%   every EOP file carries them that way; readEop converts on the way in and
%   every quantity inside this toolbox is SI. A caller who passes arcseconds
%   here gets a matrix that is still orthogonal, still smooth and wrong by five
%   orders of magnitude, so the unit is stated in the argument table, in the
%   example and here.
%
%   s' IS NOT OPTIONAL AND IS NOT ZERO, though it is very nearly so. The TIO
%   locator is a secular quantity of about -47 microarcseconds per century
%   times the Julian centuries since J2000.0, reaching -12 microarcseconds at
%   2025, which is 0.37 mm at the equator. It comes from SOFA iauSp00 and is
%   supplied by rotationItrsToGcrs automatically; a caller assembling the
%   matrix directly must supply it or state deliberately that zero is good
%   enough for the purpose.
%
%   NO DIRECTION OPTION (decision D23). W is orthogonal, so the ITRS to TIRS
%   rotation is its transpose: use invertRotation, or applyRotation with
%   'Inverse', true.
%
% ACCURACY
%   Orthogonality better than 1.1e-16 in max |W'W - I|.
%
%   The rotation is exact given the pole coordinates, so its accuracy is that
%   of the supplied EOP: about 30 microarcseconds formal error for an IERS C04
%   series, which is 0.9 mm at the equator, and dominates every algorithmic
%   term in this function by many orders.
%
%   Time derivative, for callers assembling their own: measured over the
%   supplied 20 C04 fixture the pole moves at up to 1.23 arcseconds per year,
%   that is 1.9e-13 rad/s, a ratio of 2.6e-9 to the Earth rotation rate and
%   worth 1.3 micrometres per second of velocity at a 7000 km orbit radius.
%   The handover design table quotes 7.1e-9 and 3.6 micrometres per second;
%   that is a conservative bound rather than a measurement, and the measured
%   figure is smaller. rotationItrsToGcrs includes the term either way.
%
% ERRORS
%   referenceSystem:rotationTirsToItrs:sizeMismatch
%   referenceSystem:rotationTirsToItrs:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.4.1, Eq. 5.3.
%   IAU SOFA release 20231011, iauPom00, iauSp00.
%
% EXAMPLE
%   c = referenceSystem.iersConstants();
%   xp = 0.0349282 * c.arcsecondsToRadians;
%   yp = 0.4833163 * c.arcsecondsToRadians;
%   W = referenceSystem.rotationTirsToItrs(xp, yp, 0);
%   assert(norm(W' * W - eye(3)) < 1e-15);
%
% KEYWORDS
%   polar motion, TIRS, ITRS, TIO locator, xp, yp, rotation matrix, SOFA
%
% See also ROTATIONGCRSTOCIRS, ROTATIONITRSTOGCRS, INTERPOLATEEOP, APPLYROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:15 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        xp (:,1) double
        yp (:,1) double
        sp (:,1) double
    end

    epochCount = numel(xp);
    yp = localBroadcast(yp, epochCount, "yp");
    sp = localBroadcast(sp, epochCount, "sp");

    try
        W = mexGateway('pom00', xp, yp, sp);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:rotationTirsToItrs:gatewayMissing', ...
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
        error('referenceSystem:rotationTirsToItrs:sizeMismatch', ...
            '%s must be scalar or hold %d values; it holds %d.', ...
            name, epochCount, numel(value));
    end
end
