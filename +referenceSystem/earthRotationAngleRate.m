function rate = earthRotationAngleRate()
%EARTHROTATIONANGLERATE Rate of advance of the Earth rotation angle.
%
%   rate = earthRotationAngleRate()
%
%   Returns d(ERA)/dt in radians per second: the constant of the IAU 2000
%   definition of the Earth rotation angle, uncorrected for the excess length
%   of day. It is the single authority for that constant in this toolbox.
%
% INPUT ARGUMENTS
%   none.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units    Description
%   ----   ----   ----     -----    -----------
%   rate   1x1    double   rad/s    d(ERA)/dt, nominal.
%
% METHOD
%   Not a literal. ERA is linear in UT1 by definition,
%
%       ERA(Tu) = 2*pi * (0.7790572732640 + 1.00273781191135448 * Tu)
%
%   so its rate is obtained exactly by differencing SOFA iauEra00 over a
%   1000 s interval of UT1 and dividing. That keeps the bundled SOFA release
%   as the one authority for the defining constant, in the same way that
%   leapSecondTable derives its table from iauDat instead of storing one: a
%   SOFA update propagates with no MATLAB edit, and there is no second copy to
%   drift.
%
%   The value is cached in a persistent variable, so the two gateway calls
%   happen once per MATLAB session and never inside a hot loop. Clearing the
%   function discards the cache.
%
%   THIS FUNCTION EXISTS BECAUSE THE OBVIOUS CONSTANT IS THE WRONG ONE
%   (decision D63). iersConstants.earthRotationRate is 7.292115e-5 rad/s, the
%   nominal mean angular velocity of the Earth from IERS Conventions Table 1.1.
%   The rate of advance of ERA is 7.2921151467e-5 rad/s. The relative
%   difference is 2.0e-8, which reaches 10.3 micrometres per second of
%   co-rotation velocity at a 7000 km orbit radius, above the length-of-day
%   term and two hundred times the polar-motion rate term of the same
%   derivative. Without this function the two constants would be one call site
%   apart and indistinguishable by inspection, which is finding M-2 in a new
%   costume.
%
%   Interval choice. 1000 s advances ERA by 0.073 rad, large enough that the
%   difference of two angles of order unity keeps 14 significant digits, and
%   small enough that no wrap of iauEra00 into [0, 2*pi) can fall inside it.
%
% ACCURACY
%   Measured 7.292115146705669e-5 rad/s against the exact defining value
%   7.292115146706979e-5, a difference of 1.3e-18 rad/s carried entirely by the
%   differencing interval. At 7000 km that is 9 picometres per second.
%
% ERRORS
%   referenceSystem:earthRotationAngleRate:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.5.3, Eq. 5.15.
%   Capitaine, N., Guinot, B. and McCarthy, D.D., 2000, Astron. Astrophys.
%     355, 398.
%   IAU SOFA release 20231011, iauEra00.
%
% EXAMPLE
%   omega = referenceSystem.earthRotationAngleRate();
%   assert(abs(omega - 7.2921151467e-5) < 1e-15);
%
% KEYWORDS
%   ERA, Earth rotation rate, omega, UT1, sidereal, constant, SOFA
%
% See also EARTHROTATIONANGLE, IERSCONSTANTS, ROTATIONITRSTOGCRS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:00 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    persistent cachedRate

    if ~isempty(cachedRate)
        rate = cachedRate;
        return
    end

    interval = 1000.0;
    day = [51544; 51544];
    sec = [0; interval];

    try
        era = mexGateway('era00', day, sec);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:earthRotationAngleRate:gatewayMissing', ...
                ['The Earth rotation angle comes from SOFA through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end

    cachedRate = (era(2) - era(1)) / interval;
    rate = cachedRate;
end
