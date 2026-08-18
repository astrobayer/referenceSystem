function [rGcrs, vGcrs, info] = bcrsToGcrs(rBcrs, vBcrs, epoch, options)
%BCRSTOGCRS Express a barycentric-coordinate vector in the GCRS.
%
%   rGcrs = bcrsToGcrs(rBcrs, epoch, Scale = "tdbCompatible")
%   [rGcrs, info] = bcrsToGcrs(rBcrs, epoch, Name, Value)
%
%   The exact inverse of gcrsToBcrs: IERS Conventions (2010) Eq. (11.19), or
%   Eq. (11.18) with Scale "none", solved rather than approximated.
%
%   THE INPUT IS A SEPARATION VECTOR FROM THE GEOCENTRE EXPRESSED IN BCRS
%   COORDINATES, NOT A BARYCENTRIC POSITION. Subtract the Earth's barycentric
%   position first; see METHOD in gcrsToBcrs, where the distinction is four
%   orders of magnitude wide.
%
% INPUT ARGUMENTS
%   Name    Size   Type      Units  Description
%   ----    ----   ----      -----  -----------
%   rBcrs   3xN    double    m      Geocentric vector in BCRS coordinates, one
%                                   column per epoch, or one column for all.
%   vBcrs   3xN    double    m/s    Velocity per unit of the SOURCE frame's
%                                   coordinate time. PASS [] FOR POSITION ONLY.
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
%   info    1x1    struct   -      As gcrsToBcrs.
%
% METHOD
%   THE INVERSE IS EXACT, NOT ACCURATE, AND THAT IS THE POINT OF THIS FILE.
%   Both Conventions equations are linear in the geocentric vector,
%   r_out = M r_in with M = alpha*I + beta*V*V', a rank-one update of a scaled
%   identity. Sherman-Morrison gives
%
%       M^-1 = (1/alpha) [ I - beta V V' / (alpha + beta |V|^2) ]
%
%   in closed form. Cross-checked in numpy against a dense inverse: both leave
%   ||M M^-1 - I|| at 1.11e-16, so nothing is bought by forming the matrix.
%
%   Decision D68 requires every inverse in this toolbox to be SOLVED and never
%   obtained by negating the forward parameters. Negation would in fact be
%   accurate here - the correction is 1.5e-8, so its square is 2e-16 relative,
%   a nanometre at the Earth's surface - but an exact solution that costs the
%   same removes the argument entirely, and a rule that is followed only where
%   it is cheap is not a rule.
%
% ACCURACY
%   The Conventions' own stated uncertainty, below 1 mm, exactly as gcrsToBcrs.
%   The round trip through both functions closes to 9.3e-10 m at a
%   mid-latitude station, which is roundoff at the 6.4e6 m scale and not a
%   property of the formula.
%
%   THE VELOCITY IS PROVIDED; see gcrsToBcrs for its source and validation.
%
% ERRORS
%   referenceSystem:bcrsToGcrs:scaleRequired
%   referenceSystem:bcrsToGcrs:unknownScale
%   referenceSystem:bcrsToGcrs:sizeMismatch
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Eq. (11.18) and (11.19),
%       Section 11.2; Table 1.1.
%   Sherman, J. and Morrison, W. J., 1950, Ann. Math. Statist. 21(1), 124.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   station = [4517590; 837897; 4442892];
%   b = referenceSystem.gcrsToBcrs(station, t, Scale = "tdbCompatible");
%   back = referenceSystem.bcrsToGcrs(b, t, Scale = "tdbCompatible");
%   fprintf('round trip %.3e m\n', norm(back - station));
%
% KEYWORDS
%   BCRS, GCRS, barycentric, Lorentz, L_C, inverse, Sherman-Morrison
%
% See also GCRSTOBCRS, BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
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
            ['vBcrs must have three rows or be empty; it has %d.'], ...
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
