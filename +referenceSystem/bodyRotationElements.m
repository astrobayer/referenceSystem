function [rightAscension, declination, primeMeridian, info] = ...
        bodyRotationElements(body, epoch, options)
%BODYROTATIONELEMENTS IAU WGCCRE rotational elements of the Sun and planets.
%
%   [rightAscension, declination, primeMeridian] = bodyRotationElements(body, epoch)
%   [..., info] = bodyRotationElements(body, epoch, Name, Value)
%
%   Evaluates alpha0, delta0 and W of the IAU Working Group on Cartographic
%   Coordinates and Rotational Elements, 2015 report, Table 1. These are the
%   pole direction in the ICRF and the angle from the node Q to the prime
%   meridian, measured along the body equator.
%
%   TWO PROVIDERS, AND WHICH ONE IS RIGHT DEPENDS ON THE BODY.
%
%     Source "iau"  (default)  WGCCRE Table 1, transcribed and bundled: the Sun
%                              and the eight planets. Needs nothing installed.
%     Source "pck"             Any body a furnished SPICE text PCK covers,
%                              which is Tables 1, 2 and 3. Needs MICE and
%                              pck00011.tpc.
%
%   TABLES 2 AND 3 ARE DELIBERATELY NOT TRANSCRIBED (decision D100). They hold
%   more than six hundred tabulated numbers against Table 1's ninety, and -
%   this is the deciding fact - THERE IS NO INDEPENDENT ORACLE FOR THEM. Table
%   1 was validated against orbital poles computed from barycentricBodyState,
%   but de440s.bsp contains no satellite and no asteroid ephemerides, so for a
%   satellite the only available check is cspice_pxform against pck00011.tpc:
%   the very file a transcription would be copying. Shipping six hundred
%   numbers whose only check is their own source is precisely what this project
%   refuses, so those tables are READ FROM THE KERNEL instead. This is the same
%   split barycentricBodyState already makes between "sofa" and "mice".
%
% INPUT ARGUMENTS
%   Name    Size   Type            Units  Description
%   ----    ----   ----            -----  -----------
%   body    1x1    string | char   -      Body name, any case, e.g. "mars".
%   epoch   1x1    struct          -      Epoch struct, N entries, any scale
%                                         except UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default     Description
%   ----         ----   ----     -------     -----------
%   Source       1x1    string   "iau"       "iau" or "pck".
%   Ephemeris    1x1    struct   struct([])  Furnished kernels from
%                                            readEphemeris; required for "pck".
%   Frame        1x1    string   ""          Explicit SPICE frame name for
%                                            Source "pck", overriding
%                                            IAU_<BODY>. This is how the Moon
%                                            and the Earth are reached; see
%                                            ERRORS.
%
% OUTPUT ARGUMENTS
%   Name              Size   Type     Units  Description
%   ----              ----   ----     -----  -----------
%   rightAscension    1xN    double   rad    alpha0, pole right ascension.
%   declination       1xN    double   rad    delta0, pole declination.
%   primeMeridian     1xN    double   rad    W, wrapped to [0, 2*pi).
%   info              1x1    struct   -      Fields listed below.
%   .body             1x1    string   -      Canonical name resolved.
%   .rotationRate     1x1    double   rad/d  Wdot, the linear term. Sign gives
%                                            the sense of rotation.
%   .sense            1x1    string   -      "prograde" or "retrograde".
%   .siderealPeriod   1x1    double   d      360/|Wdot|.
%   .poleDefinition   1x1    string   -      Which pole this is. See ACCURACY.
%   .source           1x1    string   -      Provider actually used.
%   .frame            1x1    string   -      SPICE frame, or "" for "iau".
%   .reference        1x1    string   -      The table implemented.
%   .epochScale       1x1    string   -      "TDB".
%
% METHOD
%   RADIANS OUT, DEGREES IN THE TABLE. The report tabulates degrees; the
%   conversion happens once, here, so that no caller mixes units and no second
%   copy of the table exists in other units. W is wrapped to [0, 2*pi) because
%   it accumulates thousands of turns - Jupiter passes 10^6 degrees within
%   three years of J2000 - and an unwrapped angle loses resolution to the
%   floating-point exponent long before it loses meaning.
%
%   Arguments are formed from the interval since J2000.0 TDB in days (d) and in
%   Julian centuries of 36525 days (T), and WHICH OF THE TWO A PERIODIC TERM
%   USES IS PART OF THE TABLE, not a convention: Mercury's M1..M5 advance in
%   DAYS while Mars's, Jupiter's and Neptune's arguments advance in CENTURIES.
%   Getting that wrong changes a term's period by a factor of 36525 and is the
%   single most likely transcription error in this table, so each term carries
%   its own unit rather than inheriting one.
%
% ACCURACY
%   THE "iau" SOURCE COVERS WGCCRE TABLE 1 ONLY - THE SUN AND THE EIGHT
%   PLANETS - AND THE "pck" SOURCE COVERS FAR MORE (open item B6, decision
%   D100). Tables 2 and 3, which hold the satellites, dwarf planets and minor
%   planets, are deliberately not transcribed: section 6 of the report uses the
%   OPPOSITE pole convention for dwarf planets, minor planets and comets, so
%   folding them into one table would put two conventions behind one argument
%   value. The consequence a caller must know is that the two sources have
%   DIFFERENT DOMAINS, not merely different accuracies: Phobos, Io, Titan,
%   Ceres and Vesta resolve under Source = "pck" and are refused under
%   Source = "iau". Until now only the error message said so; it is stated
%   here as well, because a domain limit discovered from an error is a limit
%   discovered late.
%
%   The report states its expressions are generally accurate to ONE TENTH OF A
%   DEGREE, with Mercury, Mars, Saturn and Uranus carrying more digits to
%   reflect greater confidence. Two decimal digits are given for consistency
%   and trailing zeros on Wdot are for computational consistency, NOT an
%   indication of accuracy far from J2000. At Uranus the report notes the
%   present uncertainty of the prime meridian exceeds a complete rotation.
%
%   THE POLE IS THE ONE NORTH OF THE INVARIABLE PLANE, WHICH IS NOT THE
%   RIGHT-HAND-RULE SPIN POLE FOR A RETROGRADE ROTATOR. For Venus and Uranus
%   the two differ by 180 degrees, so the angle between this pole and the
%   orbital pole is 2.6 and 82.2 degrees while the published axial tilts are
%   177.4 and 97.8 - the supplements. info.poleDefinition states this on every
%   call and info.sense gives the sense of rotation from the sign of Wdot.
%   Section 6 of the report uses the OPPOSITE convention for dwarf planets,
%   minor planets and comets, which is one reason Table 3 is not folded in here.
%
%   THE TRANSCRIPTION WAS VALIDATED AGAINST QUANTITIES THE TABLE DOES NOT
%   CONTAIN, because checking a transcription against a second copy of itself
%   proves nothing. Each pole was compared with the ORBITAL pole computed as
%   r x v from barycentricBodyState, and each rate with the published sidereal
%   period:
%
%     body      pole vs orbital pole      360/Wdot vs published period
%     -------   --------------------      ----------------------------
%     Mercury   0.034 deg vs 0.03          58.646146 d vs 58.646     2.5e-6
%     Venus     2.638 vs 180-177.36       -243.018 d vs -243.025     2.7e-5
%     Mars      25.192 vs 25.19             1.025957 d exact         3.9e-9
%     Jupiter   3.119 vs 3.13               0.413538 d (System III)  4.1e-6
%     Saturn    26.729 vs 26.73             0.444009 d (System III)  1.7e-6
%     Uranus    82.230 vs 180-97.77        -0.718333 d              4.6e-6
%     Neptune   28.318 vs 28.32             15.96630 h (System II)   8.8e-11
%
%   The Neptune check first failed by 0.9 per cent against 16.11 h. That is the
%   SYSTEM III period; the 2015 report adopted System II from Karkoschka (2011)
%   and says so in section 5. The comparator was wrong, not the table - which
%   is the kind of thing only a check against an outside quantity can tell you.
%
% ERRORS
%   referenceSystem:bodyRotationElements:unknownSource
%   referenceSystem:bodyRotationElements:unknownBody
%   referenceSystem:bodyRotationElements:earthNotTabulated
%       The 2015 report REMOVED the approximate expressions for the Earth
%       (section 10, item 2) because their accuracy was poor and they failed
%       near J2000, yet were being used as a recommended model. Use
%       rotationItrsToGcrs, which is what the report points to.
%   referenceSystem:bodyRotationElements:moonNotTabulated
%       The report also removed the low-precision lunar series (section 10,
%       item 3): it is accurate to only about 150 m and the mean-Earth/polar
%       axis frame must come from a lunar ephemeris. This is decision D14's
%       non-defaulting lunar frame arriving from the authority rather than from
%       a scoping choice.
%   referenceSystem:bodyRotationElements:wrongScale
%   referenceSystem:bodyRotationElements:staleEphemeris
%       Source "pck": the SPICE pool does not hold exactly the kernels the
%       Ephemeris struct names - a later readEphemeris replaced them, or other
%       code loaded an SPK beside them. Call readEphemeris again.
%
% REFERENCES
%   Archinal, B. A. et al., 2018, Celest. Mech. Dyn. Astron. 130, 22:
%       "Report of the IAU Working Group on Cartographic Coordinates and
%       Rotational Elements: 2015", Table 1 and Sections 2, 5 and 10.
%   Kuchynka, P. et al., 2014, Icarus 229, 340 (the Mars model).
%   Karkoschka, E., 2011, Icarus 215, 439 (Neptune System II).
%   Stark, A. et al., 2017, J. Geodesy (Mercury after MESSENGER).
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   [a, d, w, info] = referenceSystem.bodyRotationElements("mars", t);
%   fprintf('%s, %s, sidereal day %.6f d\n', info.body, info.sense, ...
%       info.siderealPeriod);
%
% KEYWORDS
%   WGCCRE, IAU, rotational elements, pole, prime meridian, planet, ICRF, body-fixed
%
% See also ROTATIONICRFTOBODYFIXED, BARYCENTRICBODYSTATE, ROTATIONITRSTOGCRS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-30 20:15 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        body (1,1) string
        epoch (1,1) struct
        options.Source (1,1) string = "iau"
        options.Ephemeris struct = struct([])
        options.Frame (1,1) string = ""
    end

    if ~ismember(options.Source, ["iau", "pck"])
        error('referenceSystem:bodyRotationElements:unknownSource', ...
            'Source is "%s"; it must be "iau" or "pck".', options.Source);
    end
    if options.Source == "iau"
        element = localTableOne(lower(body));
    else
        localRefuseAmbiguousFrame(lower(body), options.Frame);
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale == "UT1"
        error('referenceSystem:bodyRotationElements:wrongScale', ...
            ['The epoch is UT1. The table is referred to TDB and this ', ...
            'function does not accept Delta UT1; convert deliberately with ', ...
            'convertTimeScale first.']);
    end
    tdb = referenceSystem.convertTimeScale(epoch, "TDB");

    if options.Source == "pck"
        [~, rightAscension, declination, primeMeridian] = bodyFrameFromPck( ...
            body, tdb, options.Frame, options.Ephemeris, "bodyRotationElements");
        info = localPckInfo(body, options, tdb);
        return
    end

    constants = referenceSystem.iersConstants();
    dayFromJ2000 = (tdb.day - constants.mjdJ2000) + tdb.sec/constants.secondsPerDay;
    century = dayFromJ2000/36525;
    dayFromJ2000 = dayFromJ2000(:).';
    century = century(:).';

    degree = pi/180;
    rightAscension = degree*(element.alpha(1) + element.alpha(2)*century + ...
        localPeriodic(element.alphaTerms, dayFromJ2000, century, @sin));
    declination = degree*(element.delta(1) + element.delta(2)*century + ...
        localPeriodic(element.deltaTerms, dayFromJ2000, century, @cos));
    primeMeridian = degree*(element.w(1) + element.w(2)*dayFromJ2000 + ...
        localPeriodic(element.wTerms, dayFromJ2000, century, @sin));
    primeMeridian = mod(primeMeridian, 2*pi);

    if element.w(2) < 0
        sense = "retrograde";
    else
        sense = "prograde";
    end

    info = struct( ...
        'body', element.name, ...
        'rotationRate', degree*element.w(2), ...
        'sense', sense, ...
        'siderealPeriod', 360/abs(element.w(2)), ...
        'poleDefinition', "north of the invariable plane (WGCCRE section 2), " + ...
            "NOT the right-hand-rule spin pole", ...
        'source', "iau", ...
        'frame', "", ...
        'reference', "IAU WGCCRE 2015 report, Table 1", ...
        'epochScale', "TDB");
end

% =========================== local functions ===========================

function value = localPeriodic(term, dayFromJ2000, century, trigonometric)
%LOCALPERIODIC Sum of the periodic terms of one element.
%
%   term is an M-by-4 array whose columns are amplitude in degrees, phase in
%   degrees, rate in degrees, and the UNIT OF THE ARGUMENT: 0 for days, 1 for
%   Julian centuries. The unit is per term because the table mixes them -
%   Mercury's arguments advance in days, everything else's in centuries - and
%   inheriting one unit for a whole body would change a period by 36525.

    value = zeros(1, numel(dayFromJ2000));
    for k = 1:size(term, 1)
        if term(k, 4) == 0
            argument = term(k, 2) + term(k, 3)*dayFromJ2000;
        else
            argument = term(k, 2) + term(k, 3)*century;
        end
        value = value + term(k, 1)*trigonometric(argument*pi/180);
    end
end

function element = localTableOne(name)
%LOCALTABLEONE The 2015 report's Table 1, verbatim in degrees.
%
%   alpha and delta are [constant, per Julian century]; w is [constant, per
%   day]. The periodic term arrays are [amplitude, phase, rate, unit] with
%   unit 0 for days and 1 for centuries, as localPeriodic documents.

    none = zeros(0, 4);

    switch name
        case "sun"
            element = struct('name', "sun", ...
                'alpha', [286.13, 0], 'alphaTerms', none, ...
                'delta', [63.87, 0], 'deltaTerms', none, ...
                'w', [84.176, 14.1844000], 'wTerms', none);

        case "mercury"
            % M1..M5 advance in DAYS. See localPeriodic.
            mercuryTerm = [ ...
                 0.01067257, 174.7910857,  4.092335, 0; ...
                -0.00112309, 349.5821714,  8.184670, 0; ...
                -0.00011040, 164.3732571, 12.277005, 0; ...
                -0.00002539, 339.1643429, 16.369340, 0; ...
                -0.00000571, 153.9554286, 20.461675, 0];
            element = struct('name', "mercury", ...
                'alpha', [281.0103, -0.0328], 'alphaTerms', none, ...
                'delta', [61.4155, -0.0049], 'deltaTerms', none, ...
                'w', [329.5988, 6.1385108], 'wTerms', mercuryTerm);

        case "venus"
            element = struct('name', "venus", ...
                'alpha', [272.76, 0], 'alphaTerms', none, ...
                'delta', [67.16, 0], 'deltaTerms', none, ...
                'w', [160.20, -1.4813688], 'wTerms', none);

        case "earth"
            error('referenceSystem:bodyRotationElements:earthNotTabulated', ...
                ['The 2015 WGCCRE report REMOVED the approximate ', ...
                'expressions for the Earth (section 10, item 2): their ', ...
                'accuracy was poor, they failed near J2000, and they were ', ...
                'nonetheless being used as a recommended model. The report ', ...
                'directs users to the IERS. Use rotationItrsToGcrs, which ', ...
                'implements exactly that.']);

        case "moon"
            error('referenceSystem:bodyRotationElements:moonNotTabulated', ...
                ['The 2015 WGCCRE report REMOVED the low-precision lunar ', ...
                'series (section 10, item 3): it is accurate to only about ', ...
                '150 m, and the report requires the mean-Earth/polar axis ', ...
                'orientation to be obtained from a lunar ephemeris. There ', ...
                'is deliberately no default lunar frame here (decision ', ...
                'D14); furnish moon_pa_de440_200625.bpc with ', ...
                'moon_de440_250416.tf through readEphemeris.']);

        case "mars"
            marsAlpha = [ ...
                0.000068, 198.991226, 19139.4819985, 1; ...
                0.000238, 226.292679, 38280.8511281, 1; ...
                0.000052, 249.663391, 57420.7251593, 1; ...
                0.000009, 266.183510, 76560.6367950, 1; ...
                0.419057,  79.398797,     0.5042615, 1];
            marsDelta = [ ...
                0.000051, 122.433576, 19139.9407476, 1; ...
                0.000141,  43.058401, 38280.8753272, 1; ...
                0.000031,  57.663379, 57420.7517205, 1; ...
                0.000005,  79.476401, 76560.6495004, 1; ...
                1.591274, 166.325722,     0.5042615, 1];
            marsW = [ ...
                0.000145, 129.071773, 19140.0328244, 1; ...
                0.000157,  36.352167, 38281.0473591, 1; ...
                0.000040,  56.668646, 57420.9295360, 1; ...
                0.000001,  67.364003, 76560.2552215, 1; ...
                0.000001, 104.792680, 95700.4387578, 1; ...
                0.584542,  95.391654,     0.5042615, 1];
            element = struct('name', "mars", ...
                'alpha', [317.269202, -0.10927547], 'alphaTerms', marsAlpha, ...
                'delta', [54.432516, -0.05827105], 'deltaTerms', marsDelta, ...
                'w', [176.049863, 350.891982443297], 'wTerms', marsW);

        case "jupiter"
            % Ja..Je, shared between alpha and delta with different amplitudes.
            jupiterArgument = [ ...
                 99.360714, 4850.4046; ...
                175.895369, 1191.9605; ...
                300.323162,  262.5475; ...
                114.012305, 6070.2476; ...
                 49.511251,   64.3000];
            jupiterAlpha = [[0.000117; 0.000938; 0.001432; 0.000030; 0.002150], ...
                jupiterArgument, ones(5, 1)];
            jupiterDelta = [[0.000050; 0.000404; 0.000617; -0.000013; 0.000926], ...
                jupiterArgument, ones(5, 1)];
            element = struct('name', "jupiter", ...
                'alpha', [268.056595, -0.006499], 'alphaTerms', jupiterAlpha, ...
                'delta', [64.495303, 0.002413], 'deltaTerms', jupiterDelta, ...
                'w', [284.95, 870.5360000], 'wTerms', none);

        case "saturn"
            element = struct('name', "saturn", ...
                'alpha', [40.589, -0.036], 'alphaTerms', none, ...
                'delta', [83.537, -0.004], 'deltaTerms', none, ...
                'w', [38.90, 810.7939024], 'wTerms', none);

        case "uranus"
            element = struct('name', "uranus", ...
                'alpha', [257.311, 0], 'alphaTerms', none, ...
                'delta', [-15.175, 0], 'deltaTerms', none, ...
                'w', [203.81, -501.1600928], 'wTerms', none);

        case "neptune"
            % N = 357.85 + 52.316 T, shared by all three elements.
            element = struct('name', "neptune", ...
                'alpha', [299.36, 0], ...
                'alphaTerms', [0.70, 357.85, 52.316, 1], ...
                'delta', [43.46, 0], ...
                'deltaTerms', [-0.51, 357.85, 52.316, 1], ...
                'w', [249.978, 541.1397757], ...
                'wTerms', [-0.48, 357.85, 52.316, 1]);

        otherwise
            error('referenceSystem:bodyRotationElements:unknownBody', ...
                ['Body "%s" is not in WGCCRE Table 1. Supported: sun, ', ...
                'mercury, venus, mars, jupiter, saturn, uranus, neptune. ', ...
                'Tables 2 and 3 - the satellites, dwarf planets, minor ', ...
                'planets and comets - are not implemented; the small-body ', ...
                'pole convention in section 6 is the RIGHT-HAND-RULE pole ', ...
                'and differs from the one used here, so folding them into ', ...
                'one function would put two meanings behind one output.'], ...
                name);
    end
end

function localRefuseAmbiguousFrame(name, frameName)
%LOCALREFUSEAMBIGUOUSFRAME The Earth and Moon traps that survive into the PCK.
%
%   pck00011.tpc STILL CARRIES IAU_EARTH AND IAU_MOON, and both are the
%   low-precision models the 2015 report removed (section 10, items 2 and 3).
%   Letting Source "pck" answer for them would quietly reintroduce exactly what
%   Source "iau" refuses, through a different door. So the refusal follows the
%   body into the kernel provider, and is lifted only when the caller names a
%   frame explicitly - which is decision D14's rule that the lunar frame must
%   be chosen, never defaulted.

    if frameName ~= ""
        return
    end
    switch name
        case "earth"
            error('referenceSystem:bodyRotationElements:earthNotTabulated', ...
                ['IAU_EARTH exists in the PCK but is the low-precision ', ...
                'model the 2015 report removed (section 10, item 2). Use ', ...
                'rotationItrsToGcrs, or name the frame deliberately with ', ...
                'Frame = "ITRF93" if a SPICE frame is what you want.']);
        case "moon"
            error('referenceSystem:bodyRotationElements:moonNotTabulated', ...
                ['IAU_MOON exists in the PCK but is the low-precision ', ...
                'series the 2015 report removed (section 10, item 3), ', ...
                'accurate to about 150 m. THE LUNAR FRAME MUST BE CHOSEN ', ...
                'AND NEVER DEFAULTED (decision D14): pass Frame = ', ...
                '"MOON_ME" for the mean-Earth/polar-axis frame that ', ...
                'cartographic products use, or Frame = "MOON_PA" for the ', ...
                'principal-axis frame the ephemeris integrates. They differ ', ...
                'by about 860 m on the surface. Both need ', ...
                'moon_pa_de440_200625.bpc and moon_de440_250416.tf.']);
    end
end

function info = localPckInfo(body, options, tdb)
%LOCALPCKINFO Provenance for the kernel provider.
%
%   THE ROTATION RATE IS MEASURED, NOT READ. SPICE exposes no Wdot, so it is
%   estimated from W at two epochs one hour apart and unwrapped. That is enough
%   to report the sense of rotation and a sidereal period, and info says the
%   figure is estimated so that nobody mistakes it for a tabulated constant.

    frameName = options.Frame;
    if frameName == ""
        frameName = "IAU_" + upper(body);
    end

    probe = tdb;
    probe.day = tdb.day(1) + [0; 0];
    probe.sec = tdb.sec(1) + [0; 3600];
    [~, ~, ~, probeW] = bodyFrameFromPck(body, referenceSystem.normalizeEpoch( ...
        probe), options.Frame, options.Ephemeris, "bodyRotationElements");
    step = mod(probeW(2) - probeW(1) + pi, 2*pi) - pi;
    rotationRate = step*24;

    if rotationRate < 0
        sense = "retrograde";
    else
        sense = "prograde";
    end

    info = struct( ...
        'body', lower(body), ...
        'rotationRate', rotationRate, ...
        'sense', sense, ...
        'siderealPeriod', 2*pi/abs(rotationRate), ...
        'poleDefinition', "as encoded by the furnished PCK; WGCCRE section 2 " + ...
            "for planets and satellites, section 6 (right-hand rule) for " + ...
            "dwarf planets, minor planets and comets", ...
        'source', "pck", ...
        'frame', frameName, ...
        'reference', "furnished SPICE PCK via cspice_pxform", ...
        'epochScale', "TDB");
end
