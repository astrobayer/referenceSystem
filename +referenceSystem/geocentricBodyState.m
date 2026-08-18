function [position, velocity, info] = geocentricBodyState(body, epoch, options)
%GEOCENTRICBODYSTATE Position and velocity of a solar-system body from the Earth.
%
%   position = geocentricBodyState(body, epoch)
%   [position, velocity] = geocentricBodyState(body, epoch)
%   [position, velocity, info] = geocentricBodyState(body, epoch, Name, Value)
%
%   The state is the BCRS coordinate difference between the body and the Earth's
%   centre of mass. READ THE ACCURACY BLOCK BEFORE CALLING IT A GCRS STATE: it
%   is not one, and the difference is stated there with its size.
%
% INPUT ARGUMENTS
%   Name     Size   Type            Units  Description
%   ----     ----   ----            -----  -----------
%   body     1x1    string | char   -      Body name, any case, e.g. "moon".
%   epoch    1x1    struct          -      Epoch struct, N entries, any scale
%                                          except UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default     Description
%   ----         ----   ----     -------     -----------
%   Source       1x1    string   "sofa"      Provider: "sofa" or "mice".
%   Ephemeris    1x1    struct   struct([])  Furnished kernels from
%                                            readEphemeris; required for "mice".
%
% OUTPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   position            3xN    double   m      Body minus Earth, one column per epoch.
%   velocity            3xN    double   m/s    Its time derivative.
%   info                1x1    struct   -      As barycentricBodyState, with
%                                              .frame naming the caveat below.
%
% METHOD
%   Both states are evaluated at the same TDB instant and differenced. For the
%   Moon under the "sofa" provider this returns iauMoon98 exactly, because the
%   Moon's barycentric vector was built as the Earth's plus iauMoon98 and the
%   subtraction removes what the addition put there - a round trip that a
%   precision test asserts to 1e-5 m, which is the roundoff of an addition and
%   subtraction at the 1e11 m scale and not a tolerance chosen to pass.
%
% ACCURACY
%   THIS IS A COORDINATE DIFFERENCE IN THE BCRS, NOT A GCRS STATE, AND THE TWO
%   ARE NOT THE SAME VECTOR. The transformation to GCRS spatial coordinates
%   carries a Lorentz term and a scale term of combined relative size about
%   1.5e-8 (the constant L_C), so the GCRS distance exceeds this one by
%
%     body      distance      omitted term
%     -------   ----------    ------------
%     Moon      3.8e8 m       about 6 m
%     Sun       1.5e11 m      about 2.2 km
%     Jupiter   7.8e11 m      about 12 km
%
%   For the "sofa" provider every one of those is far below the model error
%   tabulated by ephemerisBodies - 6 m against 10700 m for the Moon - so the
%   distinction cannot be observed. UNDER THE "mice" PROVIDER IT IS THE
%   DOMINANT ERROR, and 6 m on the Moon is well above the 1 m tier decision D13
%   adopts as the design target.
%
%   NO 'Frame' OPTION IS OFFERED AND THAT IS A DECISION, NOT AN OMISSION. The
%   BCRS-to-GCRS transformation of IERS Conventions Ch. 10 is an expansion in
%   the distance from the Earth and is valid only in its vicinity; applying it
%   to Jupiter's geocentric vector would be using a formula outside its domain
%   and getting a smooth, plausible, wrong answer - this domain's signature
%   failure. A caller who needs rigorous GCRS coordinates for a near-Earth body
%   applies bcrsToGcrs to this result and reads that function's own stated
%   validity limit.
%
%   Everything ephemerisBodies says about the provider tiers applies unchanged;
%   info.positionError carries the number for the body asked for.
%
% ERRORS
%   referenceSystem:geocentricBodyState:unknownBody
%   referenceSystem:geocentricBodyState:wrongScale
%   referenceSystem:geocentricBodyState:gatewayMissing
%   referenceSystem:geocentricBodyState:providerNotAvailable
%
% WARNINGS
%   referenceSystem:geocentricBodyState:outsideModelRange
%   referenceSystem:geocentricBodyState:seriesNotConverged
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 10, Eq. (10.12).
%   IAU 2000 Resolution B1.3 and B1.5 (L_C and the BCRS/GCRS relation).
%   IAU SOFA release 20231011, iauEpv00, iauPlan94, iauMoon98.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   rMoon = referenceSystem.geocentricBodyState("moon", t);
%   fprintf('geocentric lunar distance %.1f km\n', vecnorm(rMoon)/1000);
%
% KEYWORDS
%   geocentric, GCRS, BCRS, ephemeris, third body, Moon, Sun, TDB
%
% See also BARYCENTRICBODYSTATE, EPHEMERISBODIES, READEPHEMERIS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 10:50 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        body (1,1) string
        epoch (1,1) struct
        options.Source (1,1) string = "sofa"
        options.Ephemeris struct = struct([])
    end

    [position, velocity, info] = bodyState(body, epoch, options, ...
        "geocentre", "geocentricBodyState");
end
