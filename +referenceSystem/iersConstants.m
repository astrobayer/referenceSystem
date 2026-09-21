function constants = iersConstants()
%IERSCONSTANTS Named IERS, IAU and BIPM constants used throughout the toolbox.
%
%   constants = iersConstants() returns a scalar struct of the defining and
%   nominal constants of the IERS Conventions (2010), the relevant IAU
%   resolutions and the GNSS time-scale definitions. It is the single authority
%   for every one of them (design principle 2): no other file in the toolbox may
%   contain these values as literals.
%
% INPUT ARGUMENTS
%   (none)
%
% OUTPUT ARGUMENTS
%   Name                     Size   Type    Units   Description
%   ----                     ----   ----    -----   -----------
%   constants                1x1    struct  -       Fields listed below.
%   .ttMinusTai              1x1    double  s       TT - TAI, defining offset (+32.184).
%   .lg                      1x1    double  1       L_G, TT/TCG rate ratio, defining.
%   .lb                      1x1    double  1       L_B, TDB/TCB rate ratio, defining.
%   .tdb0                    1x1    double  s       TDB0, TDB/TCB zero-point offset.
%   .gpsMinusTai             1x1    double  s       GPS - TAI, defining offset (-19).
%   .bdtMinusTai             1x1    double  s       BDT - TAI, defining offset (-33).
%   .earthRotationRate       1x1    double  rad/s   omega_earth, nominal mean rate.
%   .eraRatePerUt1Second     1x1    double  rad/s   d(ERA)/d(UT1 second), the
%                                                   ERA formula's defining
%                                                   coefficient. NOT the same
%                                                   as earthRotationRate.
%   .arcsecondsToRadians     1x1    double  rad     Radians per arcsecond, pi/648000.
%   .julianDateOffset        1x1    double  d       JD - MJD = 2400000.5 (SOFA DJM0).
%   .mjdJ2000                1x1    double  d       MJD of J2000.0 = 51544.5 (TT).
%   .secondsPerDay           1x1    double  s       Seconds in one day of TAI, TT or SI.
%   .mjdTai1977              1x1    double  d       MJD of 1977-01-01 0h TAI = 43144.0.
%   .mjdTt1977               1x1    double  d       Same instant expressed in TT.
%   .speedOfLight            1x1    double  m/s     c, defining (299792458).
%   .lc                      1x1    double  1       L_C, mean 1-d(TCG)/d(TCB).
%   .gmSun                   1x1    double  m^3/s^2 Heliocentric gravitational constant.
%   .gmEarth                 1x1    double  m^3/s^2 Geocentric gravitational constant.
%   .moonEarthMassRatio      1x1    double  1       Moon/Earth mass ratio.
%   .gmMoon                  1x1    double  m^3/s^2 Derived: moonEarthMassRatio*gmEarth.
%
% METHOD
%   Every value is either a defining constant fixed by convention or, where
%   marked, a derived quantity computed here from the defining ones so that a
%   second copy cannot drift from the first: arcsecondsToRadians is pi/648000
%   rather than a decimal literal, and mjdTt1977 is mjdTai1977 advanced by
%   ttMinusTai. The 1977 epoch is the common origin of TCG and TCB and is needed
%   in both scales, which is why both forms are supplied.
%
%   Sign convention throughout: a field named aMinusB holds the numerical value
%   of scale a minus scale b, so GPS = TAI + gpsMinusTai.
%
%   THE STRUCT IS BUILT ONCE PER SESSION AND CACHED (prompt P28). The values
%   are compile-time constants of the source, so a persistent has nothing to go
%   stale against, and MATLAB discards it when this file is edited or cleared -
%   the same argument that already justifies the caches in earthRotationAngleRate
%   and leapSecondTable. The reason is measured rather than assumed: the run-14
%   profile of one single-epoch rotationItrsToGcrs call recorded 24 calls to
%   this function, because every helper that needs one constant fetches the
%   whole struct independently. Assembling thirteen name-value pairs 24 times
%   per rotation was about a tenth of that call. The returned struct is a copy,
%   so a caller that modifies it cannot reach the cache.
%
% ACCURACY
%   ttMinusTai, lg, lb, tdb0, gpsMinusTai, bdtMinusTai, julianDateOffset,
%   mjdJ2000 and secondsPerDay are exact by definition; they carry no
%   uncertainty and their double representation is exact except for lg, lb and
%   tdb0, which are rounded to the nearest double (relative error < 1.2e-16).
%   arcsecondsToRadians is the correctly rounded double of pi/648000 and is
%   bit-identical to the SOFA constant DAS2R.
%   mjdTt1977 inherits one rounding of ttMinusTai/secondsPerDay, below 1e-19 d.
%
%   speedOfLight is defining and therefore exact. THE THREE GRAVITATIONAL
%   CONSTANTS ARE MEASURED AND ARE THE ONLY UNCERTAIN VALUES IN THIS STRUCT:
%   gmSun carries 1e10 m^3/s^2 (7.5e-11 relative), gmEarth 8e5 (2e-9 relative)
%   and moonEarthMassRatio 4e-10 (3.3e-8 relative). They enter only the
%   1/c^2 potential term of gcrsToBcrs, where a relative error e produces
%   e*U/c^2*|r| - so gmSun's 7.5e-11 is 4.7e-12 m at the Earth's surface, nine
%   orders inside the 1 mm uncertainty IERS Conventions Eq. (11.19) states for
%   itself. They must NOT be used as a force-model authority: gmEarth is the
%   TCG-compatible value and a gravity field carries its own, consistent with
%   its own coefficients.
%
%   lc is measured, not defining: 2e-17 on 1.48082686741e-8, i.e. 1.4e-9
%   relative, and it includes a 1.15e-16 contribution from terms in c^-4 and
%   from the asteroids. gmMoon is DERIVED here from the ratio and gmEarth
%   rather than stated, so a second copy cannot drift from the first.
%
%   eraRatePerUt1Second AND earthRotationRate ARE DIFFERENT NUMBERS AND THE
%   DIFFERENCE IS NOT ROUNDING. The first is 2*pi*1.00273781191135448/86400 =
%   7.292115146706980e-5, the exact slope of the ERA formula in UT1; the second
%   is 7.292115e-5, a nominal mean rate. They differ by 2.0e-8 relative. Use
%   eraRatePerUt1Second for any PARTIAL DERIVATIVE with respect to Delta UT1 -
%   rotationItrsToGcrsPartials does - because ERA is exactly linear in UT1 and
%   that slope is exact. Length of day does NOT enter it: LOD governs how UT1
%   relates to TAI, not the ERA formula, so this coefficient is the same at
%   every epoch.
%
%   earthRotationRate is the only nominal value: it is the mean rate, and the
%   instantaneous rate departs from it with the excess length of day by up to
%   about 2e-8 relative (1.7e-12 rad/s for LOD = 2 ms). Integrated over one day
%   that is 1.5e-7 rad, about 0.9 m at the equator, so this constant must never
%   be used to propagate an angle. Use earthRotationAngle for the angle and
%   interpolateEop for the rate; earthRotationRate is for scaling and for
%   order-of-magnitude work only.
%
% ERRORS
%   (none)
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Tables 1.1 and 1.2.
%   IAU 2000 Resolution B1.9 (L_G); IAU 2006 Resolution B3 (L_B, TDB0).
%   IAU SOFA sofa.h, constants DAS2R, DJM0, DJM00, DAYSEC, TTMTAI.
%   IERS Conventions (2010), Table 1.1 for c, L_C, GM_sun, GM_earth and the
%   Moon-Earth mass ratio; the GM values are TCB- and TCG-compatible
%   respectively, as that table footnotes.
%
% EXAMPLE
%   c = referenceSystem.iersConstants();
%   arcsec = 0.15;
%   angleInRadians = arcsec*c.arcsecondsToRadians;
%
% KEYWORDS
%   IERS, IAU, constants, TT, TAI, TCG, TCB, TDB, GPS, BDT, MJD, arcsecond
%
% See also TOOLBOXVERSION, ELLIPSOIDPARAMETERS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 11:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

%#codegen

    persistent cachedConstants

    if ~isempty(cachedConstants)
        constants = cachedConstants;
        return
    end

    ttMinusTai = 32.184;
    secondsPerDay = 86400.0;
    mjdTai1977 = 43144.0;
    gmEarth = 3.986004418e14;
    moonEarthMassRatio = 0.0123000371;

    constants = struct( ...
        'ttMinusTai', ttMinusTai, ...
        'lg', 6.969290134e-10, ...
        'lb', 1.550519768e-8, ...
        'tdb0', -6.55e-5, ...
        'gpsMinusTai', -19.0, ...
        'bdtMinusTai', -33.0, ...
        'earthRotationRate', 7.292115e-5, ...
        'eraRatePerUt1Second', 2*pi*1.00273781191135448/86400, ...
        'arcsecondsToRadians', pi/648000.0, ...
        'julianDateOffset', 2400000.5, ...
        'mjdJ2000', 51544.5, ...
        'secondsPerDay', secondsPerDay, ...
        'mjdTai1977', mjdTai1977, ...
        'mjdTt1977', mjdTai1977 + ttMinusTai/secondsPerDay, ...
        'speedOfLight', 299792458.0, ...
        'lc', 1.48082686741e-8, ...
        'gmSun', 1.32712442099e20, ...
        'gmEarth', gmEarth, ...
        'moonEarthMassRatio', moonEarthMassRatio, ...
        'gmMoon', moonEarthMassRatio*gmEarth);

    % Stored LAST. A failure part way through then leaves nothing cached rather
    % than serving a half-built struct on every later call (rev. 1.78).
    cachedConstants = constants;
end
