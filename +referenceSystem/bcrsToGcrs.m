function [rGcrs, vGcrs, info] = bcrsToGcrs(rBcrs, vBcrs, epoch, options)
%BCRSTOGCRS Express a barycentric-coordinate vector in the GCRS.
%
%   rGcrs = bcrsToGcrs(rBcrs, [], epoch, Scale = "tdbCompatible")
%   [rGcrs, vGcrs] = bcrsToGcrs(rBcrs, vBcrs, epoch, Scale = "tdbCompatible")
%   [rGcrs, vGcrs, info] = bcrsToGcrs(rBcrs, vBcrs, epoch, Name, Value)
%
%   The spatial part of IAU 2000 Resolution B1.3, in the direction it is
%   written, and the inverse of gcrsToBcrs; on request the velocity, with the
%   resolution's time part.
%
%   THE INPUT IS A SEPARATION VECTOR FROM THE GEOCENTRE EXPRESSED IN BCRS
%   COORDINATES, NOT A BARYCENTRIC POSITION. Subtract the Earth's barycentric
%   position first; see METHOD in gcrsToBcrs.
%
% INPUT ARGUMENTS
%   Name    Size   Type      Units  Description
%   ----    ----   ----      -----  -----------
%   rBcrs   3xN    double    m      Geocentric vector in BCRS coordinates, one
%                                   column per epoch, or one column for all.
%   vBcrs   3xN    double    m/s    Its rate per second of BCRS coordinate
%                                   time, or [] for position only.
%   epoch   1x1    struct    -      Epoch struct, N entries, any scale but UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default     Description
%   ----         ----   ----     -------     -----------
%   Scale        1x1    string   NONE        Required; as gcrsToBcrs.
%   Source       1x1    string   "sofa"      Ephemeris provider for U and V.
%   Ephemeris    1x1    struct   struct([])  Kernels, for Source "mice".
%
% OUTPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   rGcrs   3xN    double   m      The vector in GCRS coordinates.
%   vGcrs   3xN    double   m/s    Its rate per second of GCRS coordinate
%                                  time, or [] when vBcrs was [].
%   info    1x1    struct   -      As gcrsToBcrs.
%
% METHOD
%   The map is applied in closed form, X = r + (1/c^2)[ ... ] as gcrsToBcrs
%   writes it, and the velocity is dX/dt divided by dT/dt, with dT/dt from the
%   resolution's time part; see gcrsToBcrs for both equations.
%
% ACCURACY
%   The Conventions' own stated uncertainty, below 1 mm, exactly as gcrsToBcrs.
%   The round trip through both functions closes to 9.3e-10 m at a
%   mid-latitude station, which is roundoff at the 6.4e6 m scale.
%
%   THE VELOCITY IS HELD TO THE RESOLUTION ITSELF: a straight BCRS trajectory
%   is mapped at t - h and t + h, and the difference of the two GCRS vectors
%   is divided by the GCRS time elapsed between the two events, formed from
%   the time part of Resolution B1.3 - 2h less the integral of
%   |V|^2/2 + w and the change in V.r, over c^2. Measured on a 7.6 km/s
%   trajectory at h = 50 s: 1.8e-10 m/s under "none" and 1.9e-10 m/s under
%   "tdbCompatible". Without the dT/dt factor the velocity missed the same
%   oracle by 1.3e-4 m/s and 2.0e-5 m/s.
%
% ERRORS
%   referenceSystem:bcrsToGcrs:scaleRequired
%   referenceSystem:bcrsToGcrs:unknownScale
%   referenceSystem:bcrsToGcrs:sizeMismatch
%   referenceSystem:barycentricBodyState:wrongScale
%
% REFERENCES
%   Soffel, M. et al., 2003, AJ 126, 2687, Appendix A (IAU 2000 Resolution
%       B1.3, space and time parts).
%   IERS Conventions (2010), IERS Technical Note 36, Eq. (11.18) and (11.19),
%       Section 11.2; Table 1.1.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   station = [4517590; 837897; 4442892];
%   b = referenceSystem.gcrsToBcrs(station, [], t, Scale = "tdbCompatible");
%   back = referenceSystem.bcrsToGcrs(b, [], t, Scale = "tdbCompatible");
%   fprintf('round trip %.3e m\n', norm(back - station));
%
% KEYWORDS
%   BCRS, GCRS, barycentric, Lorentz, L_C, velocity, Resolution B1.3
%
% See also GCRSTOBCRS, BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 15:45 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        rBcrs (3,:) double {mustBeReal, mustBeFinite}
        vBcrs (:,:) double {mustBeReal, mustBeFinite}
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
    if ~isempty(vBcrs) && size(vBcrs, 1) ~= 3
        error('referenceSystem:bcrsToGcrs:sizeMismatch', ...
            'vBcrs must have three rows or be empty; it has %d.', ...
            size(vBcrs, 1));
    end

    ingredient = bcrsTransform(epoch, options, options.Scale, "bcrsToGcrs");

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
    rBcrs = broadcastVectors(rBcrs, epochCount, "rBcrs", "bcrsToGcrs");
    if ~isempty(vBcrs)
        vBcrs = broadcastVectors(vBcrs, epochCount, "vBcrs", "bcrsToGcrs");
    end

    [rGcrs, vGcrs] = applyBcrsToGcrs(ingredient, rBcrs, vBcrs);
end
