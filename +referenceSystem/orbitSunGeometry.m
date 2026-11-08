function [beta, u, info] = orbitSunGeometry(r, v, epoch, options)
%ORBITSUNGEOMETRY Solar beta angle and argument of latitude of a satellite.
%
%   [beta, u] = orbitSunGeometry(r, v, epoch) returns the solar beta angle and
%   the argument of latitude for each of the N inertial states.
%
%   [beta, u] = orbitSunGeometry(r, v, epoch, 'Equator', "gcrs") measures the
%   ascending node from the GCRS equator instead of the true equator of date.
%
%   [beta, u, info] = orbitSunGeometry(...) also returns the Sun direction it
%   used, the argument of latitude of the Sun, and two degeneracy margins.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   r       3xN    double   m      GCRS position, one state per COLUMN. The
%                                  column layout is L2's and rotationGcrsToRsw's,
%                                  not L4's row layout (decision D65).
%   v       3xN    double   m/s    GCRS velocity, one state per column. A
%                                  single column is applied to every state.
%   epoch   1x1    struct   -      Epoch struct, N entries or one, any scale
%                                  except UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default     Description
%   ----        ----   ----     -------     -----------
%   Equator     1x1    string   "cip"       Equator whose pole defines the
%                                           ascending node: "cip", the true
%                                           equator of date, or "gcrs".
%   Source      1x1    string   "sofa"      Sun provider, forwarded to
%                                           geocentricBodyState.
%   Ephemeris   1x1    struct   struct([])  Furnished kernels, forwarded to
%                                           geocentricBodyState.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   beta                1xN    double   rad    Solar beta angle, [-pi/2, pi/2],
%                                              positive when the Sun lies on the
%                                              side of the orbit normal.
%   u                   1xN    double   rad    Argument of latitude, [0, 2*pi).
%   info                1x1    struct   -      Diagnostics.
%   .sunDirection       3xN    double   -      Geocentric Sun unit vector, GCRS.
%   .uSun               1xN    double   rad    Argument of latitude of the Sun's
%                                              projection into the orbit plane,
%                                              so u - uSun is the orbit angle
%                                              measured from orbit noon.
%   .equator            1x1    string   -      The equator that was used.
%   .sineOfPlaneAngle   1xN    double   -      |r x v|/(|r||v|), the margin
%                                              against a rectilinear state, as
%                                              rotationGcrsToRsw reports it.
%   .sineOfNodeAngle    1xN    double   -      |k x h|, the margin against an
%                                              orbit in the chosen equator, for
%                                              which the node is undefined.
%
% METHOD
%   Both quantities are pure geometry of three directions: the orbit normal,
%   the Sun and the pole of an equator. Nothing here is a force model and
%   nothing is an orbit propagation.
%
%       h = (r x v)/|r x v|         orbit normal, the cross-track axis of
%                                   rotationGcrsToRsw and taken from it
%       s = Sun/|Sun|               GEOCENTRIC Sun direction, from
%                                   geocentricBodyState("sun", epoch)
%       beta = asin(h . s)          positive towards the orbit normal
%       n = (k x h)/|k x h|         ascending node direction, k the pole
%       m = h x n                   in plane, a quarter revolution ahead of n
%       u = atan2(rHat . m, rHat . n)   wrapped to [0, 2*pi)
%
%   with uSun the same expression evaluated on s, which is the argument of
%   latitude of the Sun's projection into the orbit plane.
%
%   THE TRIAD IS NOT REBUILT HERE. rotationGcrsToRsw already owns the orbit
%   frame, its degeneracy criterion and its margin, so this function calls it
%   and reads the cross-track row rather than forming r x v a second time. A
%   rectilinear state is therefore refused with that function's identifier and
%   its message, which is the behaviour a caller has already read about.
%
%   WHICH EQUATOR DEFINES THE NODE IS A CHOICE AND IT IS NOT NEGLIGIBLE. The
%   GCRS equator and the true equator of date differ by precession-nutation,
%   which had moved the pole by about 400 arcseconds by 2020, and u shifts by
%   up to that angle divided by the sine of the orbit inclination to the
%   equator - of order 0.1 degrees for a near-polar orbit, with the exact
%   value depending on where the node lies. Geodetic latitude zero in the ITRS
%   is the true equator up to polar motion, so "cip" is the physically
%   meaningful default and is what a latitude-binned analysis wants; "gcrs" is
%   offered so the difference can be measured rather than argued about.
%
%   THE CIP DIRECTION IS TAKEN FROM ITS DEFINITION, NOT FROM A ROTATION. X and
%   Y from cipCoordinates ARE the first two GCRS components of the CIP unit
%   vector, so k = [X; Y; sqrt(1 - X^2 - Y^2)] needs no further machinery and
%   does not drag in the CIO locator, which says nothing about where the pole
%   is. That this equals the third row of rotationGcrsToCirs is asserted by a
%   test rather than relied on by the code.
%
%   THE SUN DIRECTION IS GEOCENTRIC AND THE SATELLITE-CENTRIC ONE IS NOT
%   OFFERED. beta is defined on the geocentric direction. Seen from the
%   satellite the Sun moves by up to |r|/AU, which is 4.6e-5 rad or 9.5
%   arcseconds at a GRACE altitude - far above the accuracy of the Sun model
%   below, so it is a real difference and not a rounding. No consumer has
%   asked for it, and an option nobody needs is a way to get the wrong one.
%
% ACCURACY
%   The geometry is exact to machine precision: four normalisations, three
%   cross products and two arc tangents, no series and no iteration. The
%   accuracy of the ANSWER is that of the three directions it is built from.
%
%     term                                            effect on beta
%     ---------------------------------------------   --------------
%     "sofa" Sun, RMS 8.3e3 m at 1.5e11 m              5.5e-8 rad
%     BCRS versus GCRS caveat of geocentricBodyState   below 1.5e-8 rad
%     geocentric versus satellite-centric Sun          4.6e-5 rad, excluded
%                                                      by definition
%     a 1 mm/s velocity error at 7.5 km/s              1.3e-7 rad
%
%   Input-state errors therefore dominate for any real orbit product, and the
%   Sun model is not the limiting term. For u the same holds, with the choice
%   of equator far above every other term at 2e-3 rad.
%
% ERRORS
%   referenceSystem:orbitSunGeometry:wrongStateSize
%   referenceSystem:orbitSunGeometry:sizeMismatch
%   referenceSystem:orbitSunGeometry:wrongScale
%   referenceSystem:orbitSunGeometry:undefinedNode
%   referenceSystem:rotationGcrsToRsw:zeroState
%   referenceSystem:rotationGcrsToRsw:degenerateOrbitPlane
%       Raised on this function's behalf by the orbit frame it calls: a
%       vanishing state, and a radial velocity for which the orbit normal
%       itself does not exist.
%
% REFERENCES
%   D. A. Vallado (2013), Fundamentals of Astrodynamics and Applications,
%   4th ed., Sect. 2.4 and 3.4, the argument of latitude and the RSW frame.
%   O. Montenbruck and E. Gill (2000), Satellite Orbits, Sect. 3.3.
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5, on X, Y as the
%   GCRS coordinates of the Celestial Intermediate Pole.
%   GRACE-FO Level-1 Data Product User Handbook, JPL D-56935.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2020, 1, 1), "GPS");
%   [beta, u] = referenceSystem.orbitSunGeometry(rGcrs, vGcrs, t);
%   fprintf('beta = %.2f deg\n', rad2deg(beta(1)));
%
% KEYWORDS
%   beta angle, argument of latitude, orbit plane, Sun, eclipse season,
%   orbit noon, GCRS, CIP, GRACE, satellite
%
% See also ROTATIONGCRSTORSW, GEOCENTRICBODYSTATE, CIPCOORDINATES,
%   ROTATIONGCRSTOCIRS, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-09-21 17:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        r double {mustBeReal, mustBeFinite}
        v double {mustBeReal, mustBeFinite}
        epoch (1,1) struct
        options.Equator (1,1) string {mustBeMember(options.Equator, ...
            ["cip", "gcrs"])} = "cip"
        options.Source (1,1) string = "sofa"
        options.Ephemeris struct = struct([])
    end

    if size(r, 1) ~= 3 || ~ismatrix(r)
        error('referenceSystem:orbitSunGeometry:wrongStateSize', ...
            ['r must be 3xN, one state per column; it is %s. Layer L5 uses ', ...
            'the column layout of L2 and rotationGcrsToRsw, not the row ', ...
            'layout of L4 (decision D65).'], mat2str(size(r)));
    end
    if size(v, 1) ~= 3 || ~ismatrix(v)
        error('referenceSystem:orbitSunGeometry:wrongStateSize', ...
            'v must be 3xN, one state per column; it is %s.', mat2str(size(v)));
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale == "UT1"
        error('referenceSystem:orbitSunGeometry:wrongScale', ...
            ['UT1 is an angle and not a uniform time, so neither the Sun ', ...
            'nor the precession-nutation model can be evaluated at it. ', ...
            'Convert with convertTimeScale, which needs the Earth ', ...
            'orientation series to leave UT1.']);
    end

    count = [size(r, 2), size(v, 2), numel(epoch.day)];
    nState = max(count);
    if any(count ~= nState & count ~= 1)
        error('referenceSystem:orbitSunGeometry:sizeMismatch', ...
            ['%d positions, %d velocities and %d epochs: each of the three ', ...
            'must be a single entry or agree with the others.'], ...
            count(1), count(2), count(3));
    end
    if size(r, 2) == 1 && nState > 1
        r = repmat(r, 1, nState);
    end
    if size(v, 2) == 1 && nState > 1
        v = repmat(v, 1, nState);
    end
    if isscalar(epoch.day) && nState > 1
        epoch.day = repmat(epoch.day, nState, 1);
        epoch.sec = repmat(epoch.sec, nState, 1);
    end

    % The orbit frame owns the normal, the degeneracy test and the margin.
    [orbitRotation, rswInfo] = referenceSystem.rotationGcrsToRsw(r, v);
    orbitNormal = permute(orbitRotation(3, :, :), [2 3 1]);

    sunPosition = referenceSystem.geocentricBodyState("sun", epoch, ...
        'Source', options.Source, 'Ephemeris', options.Ephemeris);
    sunDirection = sunPosition./sqrt(sum(sunPosition.^2, 1));

    pole = localEquatorPole(options.Equator, epoch, nState);

    nodeVector = cross(pole, orbitNormal, 1);
    sineOfNodeAngle = sqrt(sum(nodeVector.^2, 1));
    if any(sineOfNodeAngle < 1e-12)
        bad = find(sineOfNodeAngle < 1e-12, 1);
        error('referenceSystem:orbitSunGeometry:undefinedNode', ...
            ['State %d has |k x h| = %.3e: the orbit lies in the %s ', ...
            'equator, so it has no ascending node and the argument of ', ...
            'latitude has no origin to be measured from. It is refused ', ...
            'rather than measured from an arbitrary axis. ', ...
            'info.sineOfNodeAngle reports this margin for states that are ', ...
            'merely close to it.'], bad, sineOfNodeAngle(bad), ...
            options.Equator);
    end
    nodeDirection = nodeVector./sineOfNodeAngle;
    alongNode = cross(orbitNormal, nodeDirection, 1);

    % h and s are unit to a few ulp, so their product can leave [-1, 1] by
    % rounding alone; asin would then return complex and propagate silently.
    projection = min(1, max(-1, sum(orbitNormal.*sunDirection, 1)));
    beta = asin(projection);

    radial = r./sqrt(sum(r.^2, 1));
    u = mod(atan2(sum(radial.*alongNode, 1), ...
        sum(radial.*nodeDirection, 1)), 2*pi);
    uSun = mod(atan2(sum(sunDirection.*alongNode, 1), ...
        sum(sunDirection.*nodeDirection, 1)), 2*pi);

    info = struct( ...
        'sunDirection', sunDirection, ...
        'uSun', uSun, ...
        'equator', options.Equator, ...
        'sineOfPlaneAngle', rswInfo.sineOfPlaneAngle, ...
        'sineOfNodeAngle', sineOfNodeAngle);
end

% =========================== local functions ===========================

function pole = localEquatorPole(equator, epoch, nState)
%LOCALEQUATORPOLE Unit vector of the chosen equator's pole, in GCRS.
%   For "gcrs" the pole is the third GCRS axis by definition. For "cip" it is
%   the Celestial Intermediate Pole, whose GCRS coordinates X and Y are what
%   cipCoordinates returns: the pole is [X; Y; sqrt(1 - X^2 - Y^2)] with no
%   further construction, because that is the definition of X and Y rather
%   than a consequence of it. The CIO locator is not read, since it places the
%   origin of right ascension and says nothing about the pole.
%
%   cipCoordinates needs TT, so the epoch is converted here and not in the
%   caller, which keeps the conversion out of the path that does not need it.
    if equator == "gcrs"
        pole = repmat([0; 0; 1], 1, nState);
        return
    end

    terrestrialTime = referenceSystem.convertTimeScale(epoch, "TT");
    [poleX, poleY] = referenceSystem.cipCoordinates(terrestrialTime);
    poleX = reshape(poleX, 1, []);
    poleY = reshape(poleY, 1, []);
    pole = [poleX; poleY; sqrt(1 - poleX.^2 - poleY.^2)];
end
