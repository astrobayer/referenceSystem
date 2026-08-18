function [rBcrs, vBcrs, info] = gcrsToBcrs(rGcrs, vGcrs, epoch, options)
%GCRSTOBCRS Express a geocentric vector in barycentric (BCRS) coordinates.
%
%   rBcrs = gcrsToBcrs(rGcrs, epoch, Scale = "tdbCompatible")
%   [rBcrs, info] = gcrsToBcrs(rGcrs, epoch, Name, Value)
%
%   Applies IERS Conventions (2010) Eq. (11.19), or Eq. (11.18) with
%   Scale "none": the Lorentz contraction along the Earth's barycentric
%   velocity, the scaling by the external gravitational potential, and - for
%   "tdbCompatible" - the TT-to-TDB length scale L_C.
%
%   IT RETURNS THE SAME SEPARATION VECTOR IN DIFFERENT COORDINATES, NOT A
%   BARYCENTRIC POSITION. See METHOD; the distinction is four orders of
%   magnitude wide and is the first thing to get right about this function.
%
% INPUT ARGUMENTS
%   Name    Size   Type      Units  Description
%   ----    ----   ----      -----  -----------
%   rGcrs   3xN    double    m      Geocentric vector in the GCRS, one column
%                                   per epoch, or one column for all epochs.
%   vGcrs   3xN    double    m/s    Velocity per unit of the SOURCE frame's
%                                   coordinate time. PASS [] FOR POSITION ONLY.
%   epoch   1x1    struct    -      Epoch struct, N entries, any scale but UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default     Description
%   ----         ----   ----     -------     -----------
%   Scale        1x1    string   NONE        Required. "tdbCompatible" applies
%                                            Eq. (11.19); "none" applies
%                                            Eq. (11.18). See ERRORS.
%   Source       1x1    string   "sofa"      Ephemeris provider for U and V.
%   Ephemeris    1x1    struct   struct([])  Kernels, for Source "mice".
%
% OUTPUT ARGUMENTS
%   Name                   Size   Type     Units    Description
%   ----                   ----   ----     -----    -----------
%   rBcrs                  3xN    double   m        The vector in BCRS coordinates.
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
%       xBcrs = barycentricBodyState("earth", epoch) + gcrsToBcrs(rGcrs, ...)
%
%   and that addition is deliberately left to the caller, because the two
%   quantities have accuracies four orders apart and combining them silently
%   would hide which one dominates. This function is good to the Conventions'
%   stated 1 mm; the Earth's barycentric position from the bundled SOFA
%   provider is good to 4.6 km. Adding them without noticing produces a number
%   whose 1 mm claim is nonsense.
%
%   THE TRANSFORMATION IS EXACTLY LINEAR AND THAT IS WHY THE INVERSE IS EXACT.
%   Both equations have the form r_out = M r_in with M = alpha*I + beta*V*V',
%   a rank-one update of a scaled identity, so bcrsToGcrs inverts it in closed
%   form by Sherman-Morrison rather than by negating parameters (decision D68's
%   rule, met here by an exact solution rather than by an accurate one).
%
%   U and V come from barycentricBodyState and geocentricBodyState, so P22a is
%   a genuine dependency and not a convenience. They enter only at order 1/c^2,
%   which is why the bundled provider suffices - see ACCURACY.
%
% ACCURACY
%   The Conventions state their own uncertainty for Eq. (11.19) as BELOW 1 mm,
%   and that is the accuracy of this function. Every quantity neglected inside
%   it is smaller than that and is quantified in the private helper: the
%   planets contribute at most 12 micrometres through U, the Moon 0.9
%   micrometres, and the measured uncertainties of GM_sun and L_C are nine and
%   six orders below the millimetre respectively.
%
%   THE EPHEMERIS IS ALMOST IRRELEVANT HERE, WHICH IS COUNTER-INTUITIVE AND
%   WORTH STATING. U and V reach the answer only through 1/c^2 terms, so their
%   errors are suppressed by 1e-8. Measured against the bundled SOFA provider's
%   own budget: 2.8 mm/s on the Earth's velocity moves the result by 4.8e-9 m,
%   and 8.3 km on the solar distance by 3.5e-9 m - six orders inside the 1 mm.
%   Do not reach for MICE on account of this function.
%
%   TERM SIZES AT A MID-LATITUDE STATION (|r| = 6391 km), measured, so that the
%   choice of Scale is a decision taken with the numbers in view:
%
%     L_C scale term          -0.0947 m   (present only for "tdbCompatible")
%     U/c^2 potential term    -0.0631 m
%     Lorentz term             +0.0322 m  (maximum, when r is along V)
%     total, "tdbCompatible"  -0.1715 m
%     total, "none"           -0.0769 m
%
%   THE VELOCITY IS NOW PROVIDED, FROM IAU 2000 RESOLUTION B1.3, AND THE TERM
%   THAT COULD NOT BE PINNED DOWN AT REV. 1.132 IS ITS dT/dt FACTOR:
%   1 - (v_E^2/2 + w_ext + a_E.r + v_E.v)/c^2, which is 1.5e-8 - on 31 km/s
%   that is 4.7e-4 m/s, four thousand times the 1e-7 m/s a KBR reduction works
%   at. Refusing to guess it was right. Validated by central difference at six
%   step sizes: the residual falls by exactly four at each halving, order 2.00
%   throughout, so it is the difference's own truncation and not a formula
%   error. Superseded note follows.
%
%   NO VELOCITY TRANSFORMATION IS PROVIDED AND THAT IS NOT AN OVERSIGHT. The
%   IERS Conventions (2010) give Eqs. (11.18) and (11.19) for POSITION and
%   state no transformation for velocity anywhere in Chapters 10 or 11.
%   Differentiating (11.18) would need the Earth's barycentric acceleration and
%   dU/dt, which are available, but also the rate relation between the two
%   frames' time arguments, which is a convention question rather than an
%   arithmetic one and whose size - d(TDB-TT)/dt is about 3.3e-10, i.e. 2.5e-6
%   m/s at 7.5 km/s - is twenty-five times the 1e-7 m/s tier a KBR or LRI
%   reduction works at. Supplying a velocity derived from a rule this document
%   does not state would produce something smooth, self-consistent and wrong at
%   exactly the level the function exists to reach.
%
% ERRORS
%   referenceSystem:gcrsToBcrs:scaleRequired
%       Scale has no default. The two settings differ by 9.5 cm at the Earth's
%       surface, ninety-five times the formula's own uncertainty, and neither
%       is visible in the result - decision D67's rule, applied again.
%   referenceSystem:gcrsToBcrs:unknownScale
%   referenceSystem:gcrsToBcrs:sizeMismatch
%   referenceSystem:barycentricBodyState:wrongScale
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, G. Petit and B. Luzum
%       (eds.), Eq. (11.18) and Eq. (11.19), Section 11.2; Table 1.1.
%   IAU 2000 Resolutions B1.3 and B1.5 (the BCRS, GCRS and L_C).
%   Klioner, S. A. et al., 2010, Proc. IAU Symp. 261.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   station = [4517590; 837897; 4442892];
%   rBcrs = referenceSystem.gcrsToBcrs(station, t, Scale = "tdbCompatible");
%   fprintf('length changes by %.4f m\n', norm(rBcrs) - norm(station));
%
% KEYWORDS
%   BCRS, GCRS, barycentric, Lorentz, L_C, TT-compatible, TDB-compatible, scale
%
% See also BCRSTOGCRS, BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, ITERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
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
            ['vGcrs must have three rows or be empty; it has %d.'], ...
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
