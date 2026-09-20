function ingredient = bcrsTransform(epoch, options, scale, functionName)
%BCRSTRANSFORM Coefficients of the GCRS-to-BCRS spatial transformation.
%
%   ingredient = bcrsTransform(epoch, options, scale, name)
%
%   PACKAGE-PRIVATE, AND THE SINGLE PLACE THE CONVENTIONS' EQUATION IS ENCODED.
%   bcrsToGcrs applies the resolution's map and gcrsToBcrs its inverse; both
%   read the coefficients from here, so the two cannot drift apart and there is
%   one thing to check against the Conventions rather than two.
%
%   IAU 2000 RESOLUTION B1.3, SPATIAL PART, AS PRINTED IN SOFFEL ET AL. 2003
%   APPENDIX A1 - which is a strictly larger formula than the one IERS gives:
%
%     X = r + (1/c^2)[ (1/2) v_E (v_E . r) + w_ext r
%                      + r (a_E . r) - (1/2) a_E r^2 ]
%
%   IERS Conventions Eq. (11.18) is the inverse of this with THE TWO
%   ACCELERATION TERMS DROPPED, and Eq. (11.19) adds the TT-to-TDB scale L_C.
%   Both are kept available through the Scale option; the acceleration terms
%   are now always included, because they are in the resolution, they cost
%   nothing, and they are 3 micrometres at GRACE altitude but 1 CENTIMETRE at
%   the Moon - below the 1 mm IERS states for itself in the first case and
%   above it in the second, i.e. they matter exactly where IERS stops.
%
%   The acceleration terms are quadratic in r, so the inverse, gcrsToBcrs,
%   iterates; the correction is 1.5e-8 of r, so two iterations leave roundoff.
%
%   THE VELOCITY follows by differentiating the same expression with respect
%   to t and dividing by dT/dt from the time part of the same resolution:
%
%     dX/dt = rdot + (1/c^2)[ (1/2) a_E (v_E . r) + (1/2) v_E (a_E . r + v_E . rdot)
%                             + w_ext rdot + rdot (a_E . r) + r (a_E . rdot)
%                             - a_E (r . rdot) ]
%     dT/dt = 1 - (1/c^2)[ v_E^2/2 + w_ext + a_E . r + v_E . rdot ]
%
%   w_ext here is the potential alone: a velocity carries no L_C, because the
%   length and time scalings of TT and TDB cancel in it. Terms in dw_ext/dt and
%   da_E/dt are dropped: 5.7e-28 m/s and 6.1e-13 m/s at GRACE altitude.
%
% INPUT ARGUMENTS
%   Name           Size   Type      Units  Description
%   ----           ----   ----      -----  -----------
%   epoch          1x1    struct    -      Epoch struct, N entries.
%   options        1x1    struct    -      Source and Ephemeris, from the caller.
%   scale          1x1    string    -      "none" or "tdbCompatible".
%   functionName   1x1    string    -      Public caller, for the identifiers.
%
% OUTPUT ARGUMENTS
%   Name            Size   Type     Units    Description
%   ----            ----   ----     -----    -----------
%   ingredient          1x1    struct   -      Everything both directions need:
%   .earthVelocity      3xN    double   m/s    Barycentric velocity of the Earth.
%   .earthAcceleration  3xN    double   m/s^2  Its barycentric acceleration.
%   .externalPotential  1xN    double   m^2/s^2 w_ext at the geocentre.
%   .cSquared           1x1    double   m^2/s^2 c squared.
%   .scale, .scaleTerm, .potentialBodies, .reference, .statedUncertainty
%
% METHOD
%   U IS THE NEWTONIAN POTENTIAL AT THE GEOCENTRE EXCLUDING THE EARTH'S OWN
%   MASS, and it is formed from the Sun and the Moon, which is what Conventions
%   section 10.2 names as the bodies that matter. The planets are neglected and
%   the neglect is quantified rather than asserted: Jupiter is the largest of
%   them at GM/r = 1.6e5 m^2/s^2 against the Sun's 8.9e8, so it moves the
%   U/c^2 term by 1.8e-4 relative, which is 12 micrometres at the Earth's
%   surface - an order inside the 1 mm uncertainty Eq. (11.19) states for
%   itself, and four orders inside it once the Moon is included.
%
%   THE EPHEMERIS BARELY MATTERS HERE AND THAT IS WORTH KNOWING. U and V enter
%   only through terms of order 1/c^2, so an error in either is suppressed by
%   1e-8 before it reaches the answer. Measured against the bundled SOFA
%   provider's own error budget: its 2.8 mm/s on the Earth's velocity moves the
%   result by 4.8e-9 m and its 8.3 km on the solar distance by 3.5e-9 m. Both
%   are SIX ORDERS inside the formula's 1 mm. The provider that is hopeless for
%   an absolute barycentric position is entirely adequate for this correction,
%   and a caller should not reach for MICE on account of this function.
%
% ACCURACY
%   The formula's own uncertainty is stated by the Conventions as below 1 mm.
%   Everything neglected here is below that; see METHOD for the numbers.
%
% ERRORS
%   referenceSystem:<caller>:scaleRequired
%   referenceSystem:<caller>:unknownScale
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Eqs. (11.18) and (11.19),
%   and Table 1.1 for c, L_C, GM_sun, GM_earth and the Moon-Earth mass ratio.
%
% EXAMPLE
%   % Not called directly; see gcrsToBcrs.
%
% KEYWORDS
%   BCRS, GCRS, Lorentz, scale, L_C, TT-compatible, TDB-compatible, private
%
% See also GCRSTOBCRS, BCRSTOGCRS, IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 15:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    constants = referenceSystem.iersConstants();

    switch scale
        case ""
            error(sprintf('referenceSystem:%s:scaleRequired', functionName), ...
                ['Scale has no default and must be given as "none" or ', ...
                '"tdbCompatible". The two differ by L_C, which is 9.5 cm at ', ...
                'the Earth''s surface - ninety-five times the 1 mm ', ...
                'uncertainty the Conventions state for the formula itself - ', ...
                'and neither choice is visible in the result. Geocentric ', ...
                'coordinates from an ITRF and the GCRS are TT-compatible and ', ...
                'a JPL ephemeris is TDB-compatible, so "tdbCompatible" is ', ...
                'the usual pairing; "none" is Eq. (11.18), for a caller ', ...
                'handling the scale convention itself.']);
        case "tdbCompatible"
            scaleTerm = constants.lc;
        case "none"
            scaleTerm = 0;
        otherwise
            error(sprintf('referenceSystem:%s:unknownScale', functionName), ...
                'Scale is "%s"; it must be "none" or "tdbCompatible".', scale);
    end

    [~, earthVelocity] = referenceSystem.barycentricBodyState("earth", epoch, ...
        Source = options.Source, Ephemeris = options.Ephemeris);
    sunFromEarth = referenceSystem.geocentricBodyState("sun", epoch, ...
        Source = options.Source, Ephemeris = options.Ephemeris);
    moonFromEarth = referenceSystem.geocentricBodyState("moon", epoch, ...
        Source = options.Source, Ephemeris = options.Ephemeris);

    sunDistance = vecnorm(sunFromEarth);
    moonDistance = vecnorm(moonFromEarth);
    externalPotential = constants.gmSun./sunDistance + ...
        constants.gmMoon./moonDistance;

    % The Earth's barycentric acceleration, from the SAME two bodies that form
    % the potential, so the two are consistent by construction rather than by
    % coincidence. Newtonian order is ample: it enters only through 1/c^2.
    earthAcceleration = constants.gmSun.*sunFromEarth./sunDistance.^3 + ...
        constants.gmMoon.*moonFromEarth./moonDistance.^3;

    cSquared = constants.speedOfLight^2;

    ingredient = struct( ...
        'earthVelocity', earthVelocity, ...
        'earthAcceleration', earthAcceleration, ...
        'externalPotential', externalPotential, ...
        'cSquared', cSquared, ...
        'scale', scale, ...
        'scaleTerm', scaleTerm, ...
        'potentialBodies', "sun and moon; the planets contribute at most " + ...
            "12 micrometres through w_ext, an order inside the formula's " + ...
            "own uncertainty", ...
        'reference', "IAU 2000 Resolution B1.3 (Soffel et al. 2003, " + ...
            "Appendix A1); IERS Conventions (2010) Eq. (11.18) and (11.19) " + ...
            "are its acceleration-free form", ...
        'statedUncertainty', 1e-3);
end
