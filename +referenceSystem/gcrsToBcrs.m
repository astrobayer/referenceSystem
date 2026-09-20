function [rBcrs, vBcrs, info] = gcrsToBcrs(rGcrs, vGcrs, epoch, options)
%GCRSTOBCRS Express a geocentric vector in barycentric (BCRS) coordinates.
%
%   rBcrs = gcrsToBcrs(rGcrs, [], epoch, Scale = "tdbCompatible")
%   [rBcrs, vBcrs] = gcrsToBcrs(rGcrs, vGcrs, epoch, Scale = "tdbCompatible")
%   [rBcrs, vBcrs, info] = gcrsToBcrs(rGcrs, vGcrs, epoch, Name, Value)
%
%   Applies the spatial part of IAU 2000 Resolution B1.3 in the direction
%   GCRS to BCRS: the Lorentz contraction along the Earth's barycentric
%   velocity, the scaling by the external gravitational potential, the two
%   acceleration terms and - for "tdbCompatible" - the TT-to-TDB length scale
%   L_C. Without the acceleration terms this is IERS Conventions (2010)
%   Eq. (11.19), or Eq. (11.18) with Scale "none". On request the velocity is
%   transformed with the same resolution's time part.
%
%   IT RETURNS THE SAME SEPARATION VECTOR IN DIFFERENT COORDINATES, NOT A
%   BARYCENTRIC POSITION. See METHOD.
%
% INPUT ARGUMENTS
%   Name    Size   Type      Units  Description
%   ----    ----   ----      -----  -----------
%   rGcrs   3xN    double    m      Geocentric vector in the GCRS, one column
%                                   per epoch, or one column for all epochs.
%   vGcrs   3xN    double    m/s    Its rate per second of GCRS coordinate
%                                   time, or [] for position only.
%   epoch   1x1    struct    -      Epoch struct, N entries, any scale but UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default     Description
%   ----         ----   ----     -------     -----------
%   Scale        1x1    string   NONE        Required. "tdbCompatible" (GCRS in
%                                            TT-compatible and BCRS in
%                                            TDB-compatible units) or "none"
%                                            (TCG and TCB). See ERRORS.
%   Source       1x1    string   "sofa"      Ephemeris provider for U and V.
%   Ephemeris    1x1    struct   struct([])  Kernels, for Source "mice".
%
% OUTPUT ARGUMENTS
%   Name                   Size   Type     Units    Description
%   ----                   ----   ----     -----    -----------
%   rBcrs                  3xN    double   m        The vector in BCRS coordinates.
%   vBcrs                  3xN    double   m/s      Its rate per second of BCRS
%                                                   coordinate time, or [] when
%                                                   vGcrs was [].
%   info                   1x1    struct   -        Fields listed below.
%   .scale                 1x1    string   -        The Scale actually applied.
%   .scaleTerm             1x1    double   1        L_C, or 0 for "none".
%   .externalPotential     1xN    double   m^2/s^2  U at the geocentre.
%   .potentialBodies       1x1    string   -        Bodies summed into U.
%   .reference             1x1    string   -        Equations implemented.
%   .statedUncertainty     1x1    double   m        1e-3, the Conventions' own.
%
% METHOD
%   THIS IS A CHANGE OF COORDINATES FOR A VECTOR, NOT A CHANGE OF ORIGIN. The
%   barycentric POSITION of the point is
%
%       xBcrs = barycentricBodyState("earth", epoch) + gcrsToBcrs(rGcrs, [], ...)
%
%   and that addition is left to the caller, because the two quantities have
%   accuracies four orders apart: this function is good to the Conventions'
%   stated 1 mm, while the Earth's barycentric position from the bundled SOFA
%   provider is good to 4.6 km.
%
%   THE FORWARD MAP IS THE RESOLUTION'S, AND THIS DIRECTION INVERTS IT. The
%   resolution gives the GCRS vector X in terms of the BCRS separation r,
%
%       X = r + (1/c^2)[ (1/2) V (V.r) + w r + r (A.r) - (1/2) A |r|^2 ]
%
%   with V and A the Earth's barycentric velocity and acceleration and w the
%   external potential, plus L_C c^2 for "tdbCompatible". bcrsToGcrs applies it
%   in closed form; this function solves it by fixed-point iteration, because
%   the acceleration terms are quadratic in r. The correction is 1.5e-8 of r,
%   so two iterations leave roundoff.
%
%   THE VELOCITY. Along a trajectory r(t), dX/dt follows from the map, and the
%   GCRS rate is dX/dT = (dX/dt) / (dT/dt), with
%
%       dT/dt = 1 - (1/c^2)[ |V|^2/2 + w + A.r + V.rdot ]
%
%   from the time part of the same resolution. Rates carry no L_C: the length
%   and the time scalings cancel in a velocity. Terms in dw/dt and dA/dt are
%   dropped: 5.7e-28 m/s and 6.1e-13 m/s at GRACE altitude.
%
%   U and V come from barycentricBodyState and geocentricBodyState (Sun and
%   Moon; the planets contribute at most 12 micrometres through U).
%
% ACCURACY
%   The Conventions state their own uncertainty for the position as below
%   1 mm, and that is the accuracy of this function. The ephemeris barely
%   matters: U and V enter only at order 1/c^2, so the bundled provider's
%   2.8 mm/s on the Earth's velocity moves the result by 4.8e-9 m and its
%   8.3 km on the solar distance by 3.5e-9 m.
%
%   TERM SIZES AT A MID-LATITUDE STATION (|r| = 6391 km), measured:
%
%     L_C scale term          -0.0947 m   (present only for "tdbCompatible")
%     U/c^2 potential term    -0.0631 m
%     Lorentz term             +0.0322 m  (maximum, when r is along V)
%
%   THE VELOCITY is held to a difference of the position map over the
%   resolution's own time transformation; see the ACCURACY of bcrsToGcrs:
%   1.9e-10 m/s, where leaving out the time factor misses by 1.3e-4 m/s under
%   "none" and 2.0e-5 m/s under "tdbCompatible".
%
% ERRORS
%   referenceSystem:gcrsToBcrs:scaleRequired
%       Scale has no default. The two settings differ by 9.5 cm at the Earth's
%       surface, ninety-five times the formula's own uncertainty, and neither
%       is visible in the result.
%   referenceSystem:gcrsToBcrs:unknownScale
%   referenceSystem:gcrsToBcrs:sizeMismatch
%   referenceSystem:barycentricBodyState:wrongScale
%
% REFERENCES
%   Soffel, M. et al., 2003, AJ 126, 2687, Appendix A (IAU 2000 Resolution
%       B1.3, space and time parts).
%   IERS Conventions (2010), IERS Technical Note 36, G. Petit and B. Luzum
%       (eds.), Eq. (11.18) and Eq. (11.19), Section 11.2; Table 1.1.
%   IAU 2000 Resolutions B1.3 and B1.5 (the BCRS, GCRS and L_C).
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   station = [4517590; 837897; 4442892];
%   rBcrs = referenceSystem.gcrsToBcrs(station, [], t, Scale = "tdbCompatible");
%   fprintf('length changes by %.4f m\n', norm(rBcrs) - norm(station));
%
% KEYWORDS
%   BCRS, GCRS, barycentric, Lorentz, L_C, TT-compatible, TDB-compatible, scale
%
% See also BCRSTOGCRS, BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 15:35 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        rGcrs (3,:) double {mustBeReal, mustBeFinite}
        vGcrs (:,:) double {mustBeReal, mustBeFinite}
        epoch (1,1) struct
        options.Scale (1,1) string = ""
        options.Source (1,1) string = "sofa"
        options.Ephemeris struct = struct([])
    end

    % REQUIRED, NOT OPTIONAL, AND THE SIZE IS CHECKED HERE INSTEAD.
    % Giving this a default made it optional, and MATLAB forbids a
    % REQUIRED argument (epoch) after an optional one - a hard
    % arguments-block error that took out seven tests at once. It is
    % now required and accepts [] for position only, which a (3,:)
    % size constraint would reject because [] is 0-by-0.
    if ~isempty(vGcrs) && size(vGcrs, 1) ~= 3
        error('referenceSystem:gcrsToBcrs:sizeMismatch', ...
            'vGcrs must have three rows or be empty; it has %d.', ...
            size(vGcrs, 1));
    end

    ingredient = bcrsTransform(epoch, options, options.Scale, "gcrsToBcrs");

    % INFO IS THE DOCUMENTED OUTPUT AND THE INGREDIENTS ARE NOT. Returning
    % bcrsTransform's struct directly leaked earthVelocity,
    % earthAcceleration and cSquared into a field list the help does not
    % list and a contract test does - which is the test doing its job.
    info = struct( ...
        'scale', ingredient.scale, ...
        'scaleTerm', ingredient.scaleTerm, ...
        'externalPotential', ingredient.externalPotential, ...
        'potentialBodies', ingredient.potentialBodies, ...
        'reference', ingredient.reference, ...
        'statedUncertainty', ingredient.statedUncertainty);

    epochCount = size(ingredient.earthVelocity, 2);
    rGcrs = broadcastVectors(rGcrs, epochCount, "rGcrs", "gcrsToBcrs");
    if ~isempty(vGcrs)
        vGcrs = broadcastVectors(vGcrs, epochCount, "vGcrs", "gcrsToBcrs");
    end

    [rBcrs, vBcrs] = applyGcrsToBcrs(ingredient, rGcrs, vGcrs);
end
