function [era, eraRate] = earthRotationAngle(epoch, options)
%EARTHROTATIONANGLE Earth rotation angle and its rate of advance.
%
%   era = earthRotationAngle(epochUt1)
%   [era, eraRate] = earthRotationAngle(epochUt1)
%   [era, eraRate] = earthRotationAngle(epochUt1, 'LengthOfDay', lod)
%
%   Returns the Earth rotation angle, the angle between the Celestial and the
%   Terrestrial Intermediate Origin measured along the CIP equator, and its
%   time derivative. ERA replaced Greenwich sidereal time as the measure of
%   Earth rotation in the IAU 2000 resolutions: it is rigorously proportional
%   to UT1, which sidereal time is not.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, scale UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name          Size        Type     Default  Description
%   ----          ----        ----     -------  -----------
%   LengthOfDay   1x1 | Nx1   double   0        Excess length of day in
%                                               seconds, the IERS quantity LOD.
%                                               Corrects the rate; does not
%                                               affect the angle.
%
% OUTPUT ARGUMENTS
%   Name      Size   Type     Units    Description
%   ----      ----   ----     -----    -----------
%   era       Nx1    double   rad      Earth rotation angle in [0, 2*pi).
%   eraRate   Nx1    double   rad/s    d(ERA)/dt, corrected for LOD.
%
% METHOD
%   The angle comes from SOFA iauEra00, which evaluates the IAU 2000 defining
%   expression exactly:
%
%       ERA(Tu) = 2*pi * (0.7790572732640 + 1.00273781191135448 * Tu)
%
%   with Tu the UT1 Julian date interval from 2451545.0. Because the expression
%   is linear, the rate of advance is a constant of the definition and needs no
%   differentiation.
%
%   THAT CONSTANT IS NOT THE MEAN ROTATION RATE OF THE EARTH, and the two are
%   easy to confuse because both are written omega. iersConstants supplies
%   earthRotationRate = 7.292115e-5 rad/s, the nominal mean angular velocity of
%   IERS Conventions Table 1.1. The rate of advance of ERA is
%   7.2921151467e-5 rad/s. They differ by 1.47e-12 rad/s, a relative 2.0e-8,
%   which is 10.3 micrometres per second of co-rotation velocity at a low Earth
%   orbit radius of 7000 km. That is the same order as the LOD correction this
%   function offers and two hundred times the polar-motion rate term, so using
%   the wrong one is not a rounding question (decision D63).
%
%   The rate is therefore not a literal here. It is measured once per session
%   from iauEra00 itself, by differencing the angle over a 1000 s interval of
%   UT1, and cached. The difference is exact apart from roundoff because the
%   expression is linear, and it keeps SOFA as the single authority for the
%   defining constant exactly as leapSecondTable keeps iauDat as the single
%   authority for the leap seconds.
%
%   LOD is the excess of the observed length of day over 86400 s. It reduces
%   the rate in proportion:
%
%       omega = omega_ERA * (1 - LOD / 86400)
%
%   which reproduces the IERS relation 72921151.467064 - 0.843994809 * LOD
%   picoradians per second with LOD in milliseconds, to the last digit of both
%   coefficients. Over the supplied 20 C04 fixture LOD reaches 2.18 ms, worth
%   12.5 micrometres per second at 7000 km, so the correction is applied by
%   default wherever a rate is used in this toolbox.
%
%   The angle is unaffected by LOD. LOD describes how fast the Earth is turning
%   now; where it has turned to is already in UT1.
%
% ACCURACY
%   The angle is that of iauEra00, exact to the last place of the defining
%   expression given UT1, so its accuracy is entirely that of the supplied
%   Delta UT1: of order 10 us for an IERS C04 series, which is 7.3e-10 rad of
%   rotation, or 4.6 mm at the equator.
%
%   The derived rate measures 7.292115146706913e-5 rad/s on R2026a/PCWIN64
%   against the exact 7.292115146706979e-5, a difference of 6.8e-19 rad/s
%   carried by the 1000 s differencing interval. At 7000 km that is 4.7
%   picometres per second, six orders below the LOD term it sits beside. See
%   earthRotationAngleRate, which states the reading on every host it has.
%
% ERRORS
%   referenceSystem:earthRotationAngle:wrongScale
%   referenceSystem:earthRotationAngle:sizeMismatch
%   referenceSystem:earthRotationAngle:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.5.3 and Table 1.1.
%   Capitaine, N., Guinot, B. and McCarthy, D.D., 2000, Astron. Astrophys.
%     355, 398 (the definition of ERA).
%   IAU SOFA release 20231011, iauEra00.
%
% EXAMPLE
%   ut1 = referenceSystem.daySecondToEpoch([54195 43199.927926315], "UT1");
%   [era, rate] = referenceSystem.earthRotationAngle(ut1);
%   assert(abs(rad2deg(era) - 13.318492966097) < 1e-10);
%
% KEYWORDS
%   ERA, Earth rotation angle, UT1, CIO, TIO, length of day, LOD, SOFA
%
% See also GREENWICHSIDEREALTIME, ROTATIONITRSTOGCRS, INTERPOLATEEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 21:55 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.LengthOfDay (:,1) double = 0
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "UT1"
        error('referenceSystem:earthRotationAngle:wrongScale', ...
            ['The Earth rotation angle is defined on UT1 and this epoch is ', ...
            '%s. Convert it deliberately with convertTimeScale; substituting ', ...
            'UTC would be wrong by up to 0.9 s of rotation, that is 12 ', ...
            'arcseconds.'], epoch.scale);
    end
    epochCount = numel(epoch.day);

    try
        era = mexGateway('era00', epoch.day, epoch.sec);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:earthRotationAngle:gatewayMissing', ...
                ['The Earth rotation angle comes from SOFA through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end

    % THE OPTION IS VALIDATED BEFORE THE NARGOUT GATE, NOT AFTER IT. The
    % length of day affects only the rate, so the check used to sit below the
    % early return - and a one-output call therefore accepted a wrongly sized
    % LengthOfDay in silence, which made the documented sizeMismatch error
    % unreachable on the toolbox's most common call shape. A function
    % validates what it was handed; what it was asked for decides only what it
    % computes. Found by the P17 category audit in the first S6 run.
    lod = options.LengthOfDay;
    if isscalar(lod)
        lod = repmat(lod, epochCount, 1);
    elseif numel(lod) ~= epochCount
        error('referenceSystem:earthRotationAngle:sizeMismatch', ...
            'LengthOfDay must be scalar or hold %d values; it holds %d.', ...
            epochCount, numel(lod));
    end

    if nargout < 2
        return
    end

    constants = referenceSystem.iersConstants();
    eraRate = referenceSystem.earthRotationAngleRate() .* ...
        (1 - lod ./ constants.secondsPerDay);
end
