function bodies = ephemerisBodies(options)
%EPHEMERISBODIES Bodies an ephemeris provider can supply, with their accuracy.
%
%   bodies = ephemerisBodies() lists the bodies of the bundled SOFA provider.
%   bodies = ephemerisBodies(Name, Value) selects a different provider.
%
%   This is the single authority for the mapping from a body NAME to the index
%   the MEX gateway uses, to the NAIF identifier a kernel uses, and to the
%   accuracy the provider achieves for that body (design principle 2).
%   barycentricBodyState and geocentricBodyState both resolve their body
%   argument here rather than carrying a second copy of the list.
%
% INPUT ARGUMENTS
%   (none)
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size    Type      Default   Description
%   ----         ----    ----      -------   -----------
%   Source       1x1     string    "sofa"    Provider: "sofa" or "mice".
%   Ephemeris    1x1     struct    struct([]) Furnished kernel set from
%                                            readEphemeris. Required for
%                                            Source "mice", ignored otherwise.
%
% OUTPUT ARGUMENTS
%   Name              Size   Type     Units  Description
%   ----              ----   ----     -----  -----------
%   bodies            Nx6    table    -      One row per supported body.
%   .Body             Nx1    string   -      Canonical name, the accepted argument.
%   .NaifId           Nx1    double   -      NAIF integer identifier of the body.
%   .Model            Nx1    string   -      What actually produces the state.
%   .PositionError    Nx1    double   m      Barycentric position error, RMS.
%   .VelocityError    Nx1    double   m/s    Barycentric velocity error, RMS.
%   .BodyIndex        Nx1    double   -      Gateway index; do not use elsewhere.
%
% METHOD
%   The SOFA provider composes three models, because SOFA supplies three things
%   and every other body is arithmetic on them:
%
%     Earth     iauEpv00 pvb, the only barycentric vector SOFA produces
%     Sun       pvb - pvh, since the Sun is exactly where the Earth's
%               barycentric and heliocentric vectors differ. No solar theory is
%               involved and the two errors partly cancel
%     Moon      pvb + iauMoon98
%     planets   (pvb - pvh) + iauPlan94, which is heliocentric
%
%   THE NAIF IDENTIFIERS ARE THE ONES DE440 ACTUALLY CONTAINS, which is why
%   Mercury is 1 and not 199. For Mercury and Venus the planet and its system
%   barycentre coincide. For the outer planets they do not, and the SOFA models
%   do not resolve the difference: Jupiter's system barycentre lies up to about
%   200 km from the planet centre against a model error of 71700 km, so the
%   distinction is meaningless at this tier. It is NOT meaningless under the
%   MICE provider, where the caller must ask for 5 or for 599 deliberately.
%
%   PositionError and VelocityError are the model's own published RMS PLUS the
%   4.6 km and 1.4 mm/s of the Earth's barycentric vector, added LINEARLY rather
%   than in quadrature. The two are not independent samples of one distribution
%   - every body here is referred to the same pvb - so a linear sum is the
%   defensible bound and a quadrature sum would be a flattering one.
%
% ACCURACY
%   The figures are those published in the SOFA source headers, not estimates:
%   iauEpv00 against DE405 over 1900-2100, iauPlan94 against DE200 over
%   1960-2025, iauMoon98 against ELP/MPP02 over 1950-2100. Outside those
%   intervals the errors grow and the gateway raises a status the calling
%   function turns into a warning; iauEpv00 doubles by 1800 and 2200.
%
%   THE WORST-CASE FIGURES ARE LARGER THAN THESE AND ARE NOT TABULATED HERE:
%   iauEpv00's barycentric maximum is 13.4 km against an RMS of 4.6, and
%   iauMoon98's is 31.7 km against 6.1. Take the tabulated numbers as typical
%   and multiply by three for a bound.
%
%   NO PROVIDER HERE IS ADEQUATE FOR GRACE-CLASS PRECISE ORBIT DETERMINATION.
%   The lunar third-body term is the binding constraint: at GRACE altitude the
%   Moon's differential acceleration is 1.19e-6 m/s2 and a position error dr
%   propagates as 3*(dr/r)*a, so
%
%     provider            Moon position error   acceleration error   verdict
%     ------------------  -------------------   ------------------   -------
%     SOFA iauMoon98      ~10.7 km              1.0e-10 m/s2         inadequate
%     JPL DE440, ~1 km    ~1 km                 9e-12 m/s2           adequate
%     JPL DE440, ~1 m     ~1 m                  9e-15 m/s2           the target (D13)
%
%   The accelerometer noise floor is about 1e-10 m/s2/sqrt(Hz). The SOFA
%   provider sits ON that floor and is supplied so that the toolbox works out
%   of the box and for coarse, simulation and geometry work. Use the MICE
%   provider for anything that will be compared against real observations.
%
% ERRORS
%   referenceSystem:ephemerisBodies:unknownSource
%   referenceSystem:ephemerisBodies:ephemerisRequired
%
% REFERENCES
%   IAU SOFA release 20231011, iauEpv00, iauPlan94 and iauMoon98 headers.
%   Moisson, X. and Bretagnon, P., 2001, Celest. Mech. Dyn. Astron. 80, 205.
%   Simon, J.L. et al., 1994, Astron. Astrophys. 282, 663.
%   Meeus, J., Astronomical Algorithms, 2nd ed., Willmann-Bell, 1998, p. 337.
%   IAU 2012 Resolution B2 (the astronomical unit as a defining constant).
%
% EXAMPLE
%   bodies = referenceSystem.ephemerisBodies();
%   disp(bodies(bodies.PositionError < 1e4, ["Body" "PositionError"]));
%
% KEYWORDS
%   ephemeris, solar system, body, BCRS, barycentre, SOFA, MICE, NAIF, DE440
%
% See also BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, READEPHEMERIS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 10:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.Source (1,1) string = "sofa"
        options.Ephemeris struct = struct([])
    end

    switch lower(options.Source)
        case "sofa"
            bodies = localSofaRegistry();
        case "mice"
            bodies = localMiceRegistry(options.Ephemeris);
        otherwise
            error('referenceSystem:ephemerisBodies:unknownSource', ...
                ['Source is "%s"; it must be "sofa" (the bundled models) or ', ...
                '"mice" (NAIF kernels through cspice_spkezr).'], options.Source);
    end
end

% =========================== local functions ===========================

function bodies = localSofaRegistry()
%LOCALSOFAREGISTRY The bundled provider's table.
%
%   BodyIndex MUST match the RS_BODY_* enum of mex/rsCore.h. Nothing in this
%   file can check that, so the agreement is asserted by a contract test that
%   fetches every body and requires its heliocentric distance to fall in the
%   band that body alone occupies - a permuted enum cannot survive it, whereas
%   a test comparing this table against a second copy of the same list would
%   survive it comfortably (obligation O23).

    name = ["sun"; "mercury"; "venus"; "earth"; "moon"; "mars"; "jupiter"; ...
        "saturn"; "uranus"; "neptune"; "earthMoonBarycentre"];

    % Zero-based, in the order of the enum in mex/rsCore.h.
    bodyIndex = (0:10).';

    naifId = [10; 1; 2; 399; 301; 4; 5; 6; 7; 8; 3];

    model = ["iauEpv00 (pvb - pvh)"; "iauPlan94"; "iauPlan94"; "iauEpv00"; ...
        "iauEpv00 + iauMoon98"; "iauPlan94"; "iauPlan94"; "iauPlan94"; ...
        "iauPlan94"; "iauPlan94"; "iauPlan94"];

    % Model RMS + the 4.6 km / 1.4 mm/s of pvb, added linearly. See METHOD.
    positionError = [8.3e3; 3.39e5; 1.06e6; 4.6e3; 1.07e4; 7.69e6; ...
        7.17e7; 1.99e8; 5.64e8; 1.58e8; 2.01e6];

    velocityError = [2.8e-3; 4.38e-1; 8.56e-1; 1.4e-3; 3.74e-2; 1.98; ...
        7.70; 1.94e1; 1.64e1; 1.44e1; 8.16e-1];

    bodies = table(name, naifId, model, positionError, velocityError, ...
        bodyIndex, 'VariableNames', ["Body", "NaifId", "Model", ...
        "PositionError", "VelocityError", "BodyIndex"]);
end

function bodies = localMiceRegistry(ephemeris)
%LOCALMICEREGISTRY The bodies a furnished kernel set actually covers.
%
%   The list is NOT hard-coded: it is whatever the furnished kernels contain,
%   which readEphemeris obtained from cspice_spkobj. A hard-coded list would be
%   a second authority beside the kernel and would go stale the first time a
%   different kernel was furnished - finding M-2 in a new place.

    if isempty(ephemeris)
        error('referenceSystem:ephemerisBodies:ephemerisRequired', ...
            ['Source "mice" reports the bodies the FURNISHED KERNELS ', ...
            'contain, so an Ephemeris struct from readEphemeris is ', ...
            'required. There is no fixed list: de440s.bsp and de440.bsp ', ...
            'cover different intervals and sb441-n16.bsp adds sixteen ', ...
            'asteroids, and answering from a table rather than from the ', ...
            'kernel is how a body gets reported that cannot be evaluated.']);
    end

    bodies = ephemeris.meta.bodies;
end
