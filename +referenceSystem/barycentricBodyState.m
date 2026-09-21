function [position, velocity, info] = barycentricBodyState(body, epoch, options)
%BARYCENTRICBODYSTATE Position and velocity of a solar-system body in the BCRS.
%
%   position = barycentricBodyState(body, epoch)
%   [position, velocity] = barycentricBodyState(body, epoch)
%   [position, velocity, info] = barycentricBodyState(body, epoch, Name, Value)
%
%   The state is referred to the solar-system barycentre and oriented with the
%   BCRS, which is ICRS-aligned. Body names come from ephemerisBodies.
%
% INPUT ARGUMENTS
%   Name     Size   Type            Units  Description
%   ----     ----   ----            -----  -----------
%   body     1x1    string | char   -      Body name, any case, e.g. "moon".
%   epoch    1x1    struct          -      Epoch struct, N entries, any scale
%                                          except UT1 (see ERRORS).
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
%   position            3xN    double   m      BCRS position, one column per epoch.
%   velocity            3xN    double   m/s    BCRS velocity, one column per epoch.
%   info                1x1    struct   -      Fields listed below.
%   .body               1x1    string   -      Canonical body name resolved.
%   .naifId             1x1    double   -      NAIF identifier of that body.
%   .source             1x1    string   -      Provider actually used.
%   .model              1x1    string   -      What produced the numbers.
%   .frame              1x1    string   -      "BCRS".
%   .origin             1x1    string   -      "solar system barycentre".
%   .epochScale         1x1    string   -      "TDB", the scale evaluated.
%   .positionError      1x1    double   m      RMS bound, from ephemerisBodies.
%   .velocityError      1x1    double   m/s    RMS bound, from ephemerisBodies.
%   .frameBiasApplied   1x1    logical  -      False for "sofa"; see ACCURACY.
%
% METHOD
%   The function owns the frame and time-scale semantics and delegates the
%   arithmetic, which is decision D26: TDB argument, BCRS orientation, SI units,
%   epoch handling and the accuracy statement are the toolbox's competence; the
%   evaluation of a planetary theory or an SPK segment is not.
%
%   The epoch is converted to TDB with convertTimeScale before evaluation, so a
%   caller may pass TT, TAI, UTC, GPS or any other supported scale and get the
%   same instant. TT differs from TDB by at most 1.7 ms, which is 51 m of Earth
%   motion - three orders below the SOFA provider's error and one order ABOVE
%   the MICE provider's, which is why the conversion is done rather than waved
%   away.
%
%   Outputs are 3xN with one column per epoch, matching the L2 convention that
%   applyRotation and rotationItrsToGcrs already use, NOT the Nx3 convention of
%   L3 and L4 (decision D65). A body state is consumed next to a GCRS satellite
%   vector, so it takes the shape of one.
%
% ACCURACY
%   See ephemerisBodies for the per-body table and for the reason no provider
%   here reaches the GRACE-class tier. info.positionError carries the number for
%   the body actually asked for, on every call, so it never has to be looked up.
%
%   THE FRAME BIAS IS NOT APPLIED BY THE "sofa" PROVIDER AND info SAYS SO.
%   iauEpv00 and iauMoon98 are BCRS and GCRS oriented, but iauPlan94 is referred
%   to the mean equator and equinox of J2000.0, which differs from the ICRS by
%   about 23 mas. That is 6.7 km at Mercury against a model error of 339 km, and
%   500 km at Neptune against 158000 km - between one and three orders inside
%   the model error for every planet. Applying the rotation would imply a
%   precision the theory does not have while introducing a sign that nothing
%   available here could check. The MICE provider returns ICRF directly and
%   reports frameBiasApplied as true because the question does not arise.
%
%   The velocity is per second of TDB. TDB is by construction a linear scaling
%   of TCB chosen to track TT, so its second is an SI second at the geoid to
%   within the periodic terms and no rate factor is applied in the conversion
%   from au/day. A rate factor at the L_B level would be 4.6e-4 m/s on the
%   Earth's velocity and is NOT what the au/day unit of these theories means.
%
% ERRORS
%   referenceSystem:barycentricBodyState:unknownBody
%   referenceSystem:barycentricBodyState:wrongScale
%       Raised for a UT1 epoch. UT1 reaches TDB only through Delta UT1, which
%       this function does not accept, and taking Delta UT1 as zero is a silent
%       error of up to 0.9 s - 27 km of Earth motion, five times the provider's
%       own error. Convert deliberately with convertTimeScale first.
%   referenceSystem:barycentricBodyState:gatewayMissing
%   referenceSystem:barycentricBodyState:providerNotAvailable
%   referenceSystem:barycentricBodyState:staleEphemeris
%       Source "mice": the SPICE pool does not hold exactly the kernels the
%       Ephemeris struct names - a later readEphemeris replaced them, or other
%       code loaded an SPK beside them. Call readEphemeris again.
%   referenceSystem:ephemerisBodies:unknownSource
%
% WARNINGS
%   referenceSystem:barycentricBodyState:outsideModelRange
%       Once per call, whatever N is: at least one epoch lies outside the
%       interval over which the model's stated accuracy holds.
%   referenceSystem:barycentricBodyState:seriesNotConverged
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 10.
%   IAU 2000 Resolution B1.3 (the BCRS and GCRS).
%   IAU SOFA release 20231011, iauEpv00, iauPlan94, iauMoon98.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   [r, v, info] = referenceSystem.barycentricBodyState("moon", t);
%   fprintf('%s to %.0f m RMS\n', info.model, info.positionError);
%
% KEYWORDS
%   BCRS, barycentre, ephemeris, solar system, third body, TDB, SOFA, MICE
%
% See also GEOCENTRICBODYSTATE, EPHEMERISBODIES, READEPHEMERIS, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 10:25 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        body (1,1) string
        epoch (1,1) struct
        options.Source (1,1) string = "sofa"
        options.Ephemeris struct = struct([])
    end

    % The origin is the ONLY difference between this function and
    % geocentricBodyState, and a second copy differing in one integer is what
    % rev. 1.93 recorded going wrong three separate times in the C layer. The
    % two public files stay apart because their ACCURACY blocks make genuinely
    % different claims - a coordinate difference is not a barycentric state -
    % but the arithmetic is shared through the package-private helper.
    [position, velocity, info] = bodyState(body, epoch, options, ...
        "barycentre", "barycentricBodyState");
end
