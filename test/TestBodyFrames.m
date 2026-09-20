classdef TestBodyFrames < matlab.unittest.TestCase
%TESTBODYFRAMES IAU WGCCRE rotational elements and body-fixed frames.
%
%   Covers bodyRotationElements and rotationIcrfToBodyFixed (prompt P23a,
%   WGCCRE 2015 Table 1: the Sun and the eight planets).
%
%   THE REFERENCE TESTS EXIST BECAUSE THE RISK HERE IS A TRANSCRIPTION, NOT AN
%   ALGORITHM. Table 1 is about ninety numbers copied out of a PDF, and a
%   mistyped digit produces a pole that is smooth, orthonormal and wrong -
%   which no round trip, invariant or self-consistency check can see. Every
%   reference test below therefore compares against a quantity THE TABLE DOES
%   NOT CONTAIN: the orbital pole computed as r x v from barycentricBodyState,
%   and the published sidereal rotation periods. Comparing the table with a
%   second copy of the table would prove nothing, which is the argument
%   decision D90 made for the PCK and section H.7.7 replaced with this.
%
%   Written as a whole file rather than assembled by insertion. The last class
%   built by string surgery ended with two functions at classdef level and
%   fourteen unbalanced ends (rev. 1.139).
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-30 22:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    properties (Constant)
        % Bodies of WGCCRE Table 1 that have an orbit to compare against. The
        % Sun is excluded here: its "orbital pole" about the barycentre is not
        % a meaningful comparator.
        orbitingBody = ["mercury", "venus", "mars", "jupiter", "saturn", ...
            "uranus", "neptune"];

        % Published axial tilt (obliquity to the orbit) in degrees, from the
        % planetary literature and NOT from the WGCCRE table. For a RETROGRADE
        % rotator this exceeds 90 degrees, because it is measured to the
        % right-hand-rule spin pole while WGCCRE section 2 tabulates the pole
        % north of the invariable plane - the two differ by 180 degrees.
        publishedTilt = [0.034, 177.36, 25.19, 3.13, 26.73, 97.77, 28.32];

        % Published sidereal rotation period in days, signed by the sense of
        % rotation. Jupiter, Saturn and Uranus are System III (magnetic field),
        % which is what Table 1 footnote (e) says its W refers to. NEPTUNE IS
        % SYSTEM II, 15.96630 h from Karkoschka (2011), which section 5 of the
        % report adopted; using its System III period of 16.11 h here fails by
        % 0.9 per cent and was in fact the first version of this constant.
        publishedPeriod = [58.646, -243.025, 1.02595676, 0.41354, 0.44401, ...
            -0.71833, 15.96630/24];
    end

    methods (Access = private)

        function ephemeris = requireOrientationKernels(testCase)
            %REQUIREORIENTATIONKERNELS Assume MICE and the PCK, or skip.
            %   THE SUITE MUST NOT REQUIRE A DOWNLOAD, so these tests INC on a
            %   machine without the kernels rather than fail. This is the
            %   optional kernel-backed tier section H.7.7 anticipated when it
            %   exempted readEphemeris from reference coverage; that exemption
            %   is now expected to go stale, which is the intended outcome.
            testCase.assumeTrue(exist('cspice_pxform', 'file') == 2 || ...
                exist('cspice_pxform', 'file') == 3, ...
                'MICE is not on the path; the kernel-backed tier is skipped.');
            % D119: THE FOLDER IS ASKED FOR, NOT COMPOSED. This helper built
            % <toolboxRoot>/data from its own mfilename - a third copy of the
            % location after the two D119 deleted in the downloaders - so a
            % user who moved their data with referenceSystem.dataFolder was
            % told the kernels were missing while they sat where they had put
            % them. Run 94 reported exactly that, through D117.
            kernel = fullfile(referenceSystem.dataFolder(), 'pck00011.tpc');
            testCase.assumeTrue(isfile(kernel), ...
                "pck00011.tpc is not in " + referenceSystem.dataFolder() + ...
                "; run setupReferenceSystem(Fetch = ""kernels"").");
            ephemeris = referenceSystem.readEphemeris(string(kernel));
        end

        function requireGateway(testCase)
            %REQUIREGATEWAY Assume the compiled gateway rather than fail without it.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built; run referenceSystem.buildMex.');
        end

        function epoch = sampleEpoch(~, count)
            %SAMPLEEPOCH A TT epoch of COUNT entries, one day apart, at J2000.
            day = 51544 + (0:count - 1).';
            sec = repmat(43200, count, 1);
            epoch = referenceSystem.daySecondToEpoch([day sec], "TT");
        end

        function direction = poleDirection(~, rightAscension, declination)
            %POLEDIRECTION Unit vector of a pole given in the ICRF.
            direction = [cos(declination).*cos(rightAscension); ...
                cos(declination).*sin(rightAscension); sin(declination)];
        end

    end

    methods (Test, TestTags = {'contract'})

        function bodyRotationElements_contract_pckStillRefusesTheEarthAndMoon(testCase)
            % THE REFUSAL FOLLOWS THE BODY INTO THE KERNEL PROVIDER. pck00011
            % still carries IAU_EARTH and IAU_MOON, both the low-precision
            % models the 2015 report removed, so letting Source "pck" answer
            % for them would reintroduce through a second door exactly what
            % Source "iau" refuses at the first.
            testCase.verifyError( ...
                @() referenceSystem.bodyRotationElements("moon", ...
                testCase.sampleEpoch(1), Source = "pck"), ...
                'referenceSystem:bodyRotationElements:moonNotTabulated');
            testCase.verifyError( ...
                @() referenceSystem.bodyRotationElements("earth", ...
                testCase.sampleEpoch(1), Source = "pck"), ...
                'referenceSystem:bodyRotationElements:earthNotTabulated');
        end

        function bodyRotationElements_contract_pckWithoutKernelsIsRefusedClearly(testCase)
            % The seam must refuse with a message that names what is missing,
            % on a machine that has neither MICE nor the kernels.
            try
                referenceSystem.bodyRotationElements("phobos", ...
                    testCase.sampleEpoch(1), Source = "pck");
                testCase.verifyFail('Source "pck" needs an Ephemeris.');
            catch failure
                testCase.verifyTrue(ismember(failure.identifier, ...
                    {'referenceSystem:bodyRotationElements:ephemerisRequired', ...
                    'referenceSystem:bodyRotationElements:miceUnavailable'}), ...
                    ['Unexpected identifier ' failure.identifier]);
            end
        end

        function bodyRotationElements_contract_unknownSourceIsRefused(testCase)
            testCase.verifyError( ...
                @() referenceSystem.bodyRotationElements("mars", ...
                testCase.sampleEpoch(1), Source = "spice"), ...
                'referenceSystem:bodyRotationElements:unknownSource');
        end

        function bodyRotationElements_contract_shapeAndInfoFields(testCase)
            epoch = testCase.sampleEpoch(5);

            [rightAscension, declination, primeMeridian, info] = ...
                referenceSystem.bodyRotationElements("Mars", epoch);

            testCase.verifySize(rightAscension, [1 5]);
            testCase.verifySize(declination, [1 5]);
            testCase.verifySize(primeMeridian, [1 5]);
            testCase.verifyEqual(sort(string(fieldnames(info))), ...
                sort(["body"; "rotationRate"; "sense"; "siderealPeriod"; ...
                "poleDefinition"; "source"; "frame"; "reference"; ...
                "epochScale"]));
            testCase.verifyEqual(info.body, "mars", ...
                'The name is resolved case-insensitively and returned canonical.');
            testCase.verifyEqual(info.epochScale, "TDB");
            testCase.verifySubstring(char(info.poleDefinition), ...
                'invariable plane', ...
                'Every call must state which pole this is.');
        end

        function bodyRotationElements_contract_earthIsRefusedWithTheReportsReason(testCase)
            % The 2015 report REMOVED the Earth expressions (section 10 item 2)
            % because they were poor and were being used anyway. The refusal is
            % the report's decision, not a scoping choice, and it must point at
            % the function that does the job properly.
            % verifyError DOES NOT RETURN THE MException - it returns a
            % missing - so the message cannot be inspected through it.
            % The try/catch idiom used elsewhere in this suite is the
            % portable way to assert the identifier AND what the
            % message must contain.
            try
                referenceSystem.bodyRotationElements("earth", ...
                    testCase.sampleEpoch(1));
                testCase.verifyFail('The Earth must be refused.');
            catch failure
                testCase.verifyEqual(failure.identifier, ...
                    'referenceSystem:bodyRotationElements:earthNotTabulated');
                testCase.verifySubstring(failure.message, 'rotationItrsToGcrs');
            end
        end

        function bodyRotationElements_contract_moonIsRefusedWithTheReportsReason(testCase)
            % Section 10 item 3 removed the low-precision lunar series, so D14's
            % non-defaulting lunar frame arrives from the AUTHORITY rather than
            % from this toolbox's scope. The message must name the kernels.
            % verifyError DOES NOT RETURN THE MException - it returns a
            % missing - so the message cannot be inspected through it.
            % The try/catch idiom used elsewhere in this suite is the
            % portable way to assert the identifier AND what the
            % message must contain.
            try
                referenceSystem.bodyRotationElements("moon", ...
                    testCase.sampleEpoch(1));
                testCase.verifyFail('The Moon must be refused.');
            catch failure
                testCase.verifyEqual(failure.identifier, ...
                    'referenceSystem:bodyRotationElements:moonNotTabulated');
                testCase.verifySubstring(failure.message, 'moon_pa_de440_200625.bpc');
            end
        end

        function bodyRotationElements_contract_unknownBodyNamesTheSupportedSet(testCase)
            % verifyError DOES NOT RETURN THE MException - it returns a
            % missing - so the message cannot be inspected through it.
            % The try/catch idiom used elsewhere in this suite is the
            % portable way to assert the identifier AND what the
            % message must contain.
            try
                referenceSystem.bodyRotationElements("phobos", ...
                    testCase.sampleEpoch(1));
                testCase.verifyFail('An unlisted body must be refused.');
            catch failure
                testCase.verifyEqual(failure.identifier, ...
                    'referenceSystem:bodyRotationElements:unknownBody');
                % Section 6 uses the OPPOSITE pole convention for small
                % bodies, so folding Tables 2 and 3 in would put two
                % meanings behind one output. The message must say so.
                testCase.verifySubstring(failure.message, 'RIGHT-HAND-RULE');
            end
        end

        function bodyRotationElements_contract_ut1EpochIsRefused(testCase)
            epoch = referenceSystem.daySecondToEpoch([51544 43200], "UT1");

            testCase.verifyError( ...
                @() referenceSystem.bodyRotationElements("venus", epoch), ...
                'referenceSystem:bodyRotationElements:wrongScale');
        end

        function rotationIcrfToBodyFixed_contract_shapeAndComposition(testCase)
            epoch = testCase.sampleEpoch(4);

            [rotation, info] = ...
                referenceSystem.rotationIcrfToBodyFixed("jupiter", epoch);

            testCase.verifySize(rotation, [3 3 4], ...
                'One matrix per epoch, page-wise.');
            testCase.verifyEqual(info.composition, ...
                "Rz(W)*Rx(pi/2 - delta0)*Rz(pi/2 + alpha0)");
            testCase.verifyEqual(info.body, "jupiter");
        end

    end

    methods (Test, TestTags = {'reference'})

        function bodyRotationElements_reference_pckAgreesWithTheBundledTable(testCase)
            % THE CHECK D90 ORIGINALLY ASKED FOR, NOW POSSIBLE. pck00011.tpc is
            % the machine-readable encoding of the same WGCCRE tables, produced
            % by NAIF from the report independently of this toolbox's
            % transcription. For the Table 1 bodies BOTH providers exist, so
            % they can be compared - and they travel in opposite directions:
            % "iau" assembles a rotation from transcribed angles, "pck" derives
            % angles from a rotation SPICE built. A mistyped digit anywhere in
            % Table 1 fails here.
            %
            % This is what makes the transcription safe rather than merely
            % plausible: the orbital-pole test bounds it to 0.011 deg, this one
            % bounds it to the tabulated digits.
            ephemeris = testCase.requireOrientationKernels();
            epoch = referenceSystem.daySecondToEpoch([51544 43200], "TT");

            for name = ["sun", testCase.orbitingBody]
                bundled = referenceSystem.rotationIcrfToBodyFixed(name, epoch);
                fromKernel = referenceSystem.rotationIcrfToBodyFixed(name, ...
                    epoch, Source = "pck", Ephemeris = ephemeris);

                % AbsTol 2e-6 on matrix elements is about 0.4 arcsec, which
                % bounds the LAST TABULATED DIGIT of the report rather than any
                % arithmetic: W is given to 1e-6 deg for several bodies and the
                % PCK carries the same rounding. A transcription error moves an
                % element by orders more.
                testCase.verifyEqual(fromKernel, bundled, 'AbsTol', 2e-6, ...
                    sprintf('%s: bundled table and PCK disagree.', name));
            end
        end

        function rotationIcrfToBodyFixed_reference_pckReachesTablesTwoAndThree(testCase)
            % D100: Tables 2 and 3 are READ, not transcribed. This asserts the
            % route actually works for a satellite and for a minor planet -
            % bodies for which no independent orbital-pole oracle exists,
            % which is precisely why they are not transcribed.
            ephemeris = testCase.requireOrientationKernels();
            epoch = referenceSystem.daySecondToEpoch([51544 43200], "TT");

            for name = ["phobos", "io", "titan", "ceres", "vesta"]
                rotation = referenceSystem.rotationIcrfToBodyFixed(name, ...
                    epoch, Source = "pck", Ephemeris = ephemeris);
                % AbsTol 1e-12: SPICE returns an orthonormal matrix and this
                % bounds its roundoff, not any model.
                testCase.verifyEqual(rotation*rotation.', eye(3), ...
                    'AbsTol', 1e-12, ...
                    sprintf('%s frame is not orthonormal.', name));
                testCase.verifyEqual(det(rotation), 1, 'AbsTol', 1e-12);
            end
        end

        function rotationIcrfToBodyFixed_reference_matchesTheProseConstruction(testCase)
            % rotationIcrfToBodyFixed HAD NO reference COVERAGE AND THE SUITE
            % SAID SO. The oracle is the report's own PROSE, section 2 and
            % Figure 1, built from VECTORS rather than as a product of Euler
            % rotations: "the node Q is defined as the node at alpha0 + 90",
            % and "W is the angle measured easterly along the body's equator
            % from Q to B".
            %
            % So z is the pole, x is Q rotated about the pole by W - Rodrigues,
            % not a matrix product - and y closes the set. Two constructions
            % sharing no line of code and only the definition. A wrong
            % 90-degree offset or a transposed rotation survives one of them,
            % never both.
            testCase.requireGateway();
            epoch = referenceSystem.daySecondToEpoch([51544 43200], "TT");

            for name = ["sun", testCase.orbitingBody]
                [rightAscension, declination, primeMeridian] = ...
                    referenceSystem.bodyRotationElements(name, epoch);

                pole = testCase.poleDirection(rightAscension, declination);
                node = [-sin(rightAscension); cos(rightAscension); 0];
                prime = node*cos(primeMeridian) + ...
                    cross(pole, node)*sin(primeMeridian);
                expected = [prime.'; cross(pole, prime).'; pole.'];

                actual = referenceSystem.rotationIcrfToBodyFixed(name, epoch);

                % AbsTol 1e-13: both sides are products and cross products of
                % unit vectors, so a few tens of eps. Measured worst departure
                % 3.1e-16, at Saturn.
                testCase.verifyEqual(actual, expected, 'AbsTol', 1e-13, ...
                    sprintf('%s: Euler product and prose construction disagree.', ...
                    name));
            end
        end

        function bodyRotationElements_reference_polesMatchTheOrbitalPoles(testCase)
            % THE TEST THAT VALIDATES THE TRANSCRIPTION, AND THE ONLY ONE THAT
            % CAN. Each pole is compared with the ORBITAL pole, computed as
            % r x v about the Sun from barycentricBodyState - a quantity Table 1
            % does not contain and could not be copied from. A mistyped digit in
            % alpha0 or delta0 moves the angle by degrees.
            %
            % The comparison is against min(tilt, 180 - tilt) because the
            % published tilt is measured to the right-hand-rule spin pole while
            % WGCCRE tabulates the pole north of the invariable plane; for
            % Venus and Uranus those differ by 180 degrees. All these orbits lie
            % near the invariable plane, so the WGCCRE pole is always the one
            % less than 90 degrees from the orbital pole.
            testCase.requireGateway();
            epoch = referenceSystem.daySecondToEpoch([51544 43200], "TT");

            sunPosition = referenceSystem.barycentricBodyState("sun", epoch);
            [~, sunVelocity] = referenceSystem.barycentricBodyState("sun", epoch);

            for k = 1:numel(testCase.orbitingBody)
                name = testCase.orbitingBody(k);
                [position, velocity] = ...
                    referenceSystem.barycentricBodyState(name, epoch);
                orbitalPole = cross(position - sunPosition, ...
                    velocity - sunVelocity);
                orbitalPole = orbitalPole/norm(orbitalPole);

                [rightAscension, declination] = ...
                    referenceSystem.bodyRotationElements(name, epoch);
                pole = testCase.poleDirection(rightAscension, declination);

                angle = rad2deg(acos(max(-1, min(1, dot(pole, orbitalPole)))));
                expected = min(testCase.publishedTilt(k), ...
                    180 - testCase.publishedTilt(k));

                % AbsTol 0.05 deg bounds two things and neither is the table:
                % the published tilts are quoted to 0.01 to 0.1 deg, and the
                % orbital pole inherits the SOFA provider's model error, which
                % at Jupiter is 7.2e4 km in 7.8e8 km, i.e. 0.005 deg. Measured
                % worst departure 0.011 deg, at Jupiter.
                testCase.verifyEqual(angle, expected, 'AbsTol', 0.05, ...
                    sprintf(['%s pole sits %.3f deg from its orbital pole; ', ...
                    'the published tilt implies %.3f deg.'], name, angle, ...
                    expected));
            end
        end

        function bodyRotationElements_reference_ratesMatchThePublishedPeriods(testCase)
            % 360/Wdot against the published sidereal rotation period. This
            % catches a transposed digit in the one number every caller uses,
            % and it is independent of the pole test: a rate error leaves the
            % pole untouched and vice versa.
            for k = 1:numel(testCase.orbitingBody)
                name = testCase.orbitingBody(k);
                [~, ~, ~, info] = referenceSystem.bodyRotationElements( ...
                    name, testCase.sampleEpoch(1));

                % RelTol 1e-4 bounds the ROUNDING OF THE PUBLISHED COMPARATOR,
                % not the table: the periods above are quoted to five or six
                % figures. Measured worst agreement 2.7e-5, at Venus, whose
                % published 243.025 d carries only six figures.
                testCase.verifyEqual(info.siderealPeriod, ...
                    abs(testCase.publishedPeriod(k)), 'RelTol', 1e-4, ...
                    sprintf('%s sidereal period disagrees.', name));
            end
        end

        function bodyRotationElements_reference_senseAgreesWithTheOrbitalGeometry(testCase)
            % TWO UNRELATED SIGNALS MUST NAME THE SAME TWO PLANETS. The sign of
            % Wdot says which bodies rotate retrograde; independently, a
            % published tilt above 90 degrees says the same thing, because the
            % tilt is measured to the right-hand-rule pole. Venus and Uranus
            % must be the only two, by both measures.
            senseFromRate = strings(0, 1);
            for k = 1:numel(testCase.orbitingBody)
                [~, ~, ~, info] = referenceSystem.bodyRotationElements( ...
                    testCase.orbitingBody(k), testCase.sampleEpoch(1));
                if info.sense == "retrograde"
                    senseFromRate(end + 1, 1) = testCase.orbitingBody(k); %#ok<AGROW>
                end
            end

            senseFromTilt = testCase.orbitingBody(testCase.publishedTilt > 90).';

            testCase.verifyEqual(sort(senseFromRate), sort(senseFromTilt), ...
                'The sign of Wdot and the published tilts must agree.');
            testCase.verifyEqual(sort(senseFromRate), ["uranus"; "venus"]);
        end

    end

    methods (Test, TestTags = {'precision'})

        function rotationIcrfToBodyFixed_precision_mapsThePoleToTheZAxis(testCase)
            % THE SINGLE ASSERTION THAT PROVES THE COMPOSITION. An error in the
            % order of the three rotations, in either 90-degree offset, or in
            % the sense of any one of them moves the pole off the z axis. The
            % pole is rebuilt here from the elements rather than taken from the
            % rotation, so the two sides are independent.
            testCase.requireGateway();
            epoch = referenceSystem.daySecondToEpoch([51544 43200], "TT");

            for name = ["sun", testCase.orbitingBody]
                [rightAscension, declination] = ...
                    referenceSystem.bodyRotationElements(name, epoch);
                pole = testCase.poleDirection(rightAscension, declination);
                rotation = ...
                    referenceSystem.rotationIcrfToBodyFixed(name, epoch);

                % AbsTol 1e-14 is roundoff of a product of three orthonormal
                % 3-by-3 matrices applied to a unit vector - a few tens of eps.
                % Measured worst residual 2.7e-16, at Neptune.
                testCase.verifyEqual(rotation*pole, [0; 0; 1], ...
                    'AbsTol', 1e-14, ...
                    sprintf('%s pole does not map to the z axis.', name));
            end
        end

        function rotationIcrfToBodyFixed_precision_isOrthonormalWithUnitDeterminant(testCase)
            % A rotation that is not orthonormal is not a rotation. Checked over
            % an arc so that a page-wise indexing error in the 3-by-3-by-N
            % assembly cannot hide behind a single correct page.
            epoch = testCase.sampleEpoch(6);
            rotation = referenceSystem.rotationIcrfToBodyFixed("saturn", epoch);

            for k = 1:size(rotation, 3)
                page = rotation(:, :, k);
                % AbsTol 1e-14: roundoff of a 3-by-3 product, a few tens of eps.
                % Measured departure below 3e-16.
                testCase.verifyEqual(page*page.', eye(3), 'AbsTol', 1e-14, ...
                    sprintf('Page %d is not orthonormal.', k));
                testCase.verifyEqual(det(page), 1, 'AbsTol', 1e-14, ...
                    sprintf('Page %d is a reflection, not a rotation.', k));
            end
        end

        function bodyRotationElements_precision_primeMeridianIsWrappedAndAdvances(testCase)
            % W is wrapped to [0, 2*pi) because it accumulates thousands of
            % turns. The wrap must not destroy the advance: over one day Jupiter
            % turns 870.536 degrees, so consecutive daily values differ by that
            % modulo a full turn.
            % SAMPLED IN TDB, NOT TT, AND THAT IS THE WHOLE FIX. W
            % advances uniformly in TDB by definition of the table. The
            % first version sampled a TT grid, on which the TDB step is
            % NOT uniform: TDB - TT varies periodically by up to 1.6 ms,
            % moving Jupiter's daily advance by 1.6e-5 deg - 1.07e-7
            % relative, against an asserted RelTol of 1e-9. The failure
            % was real physics reported as a defect.
            epoch = referenceSystem.daySecondToEpoch( ...
                [(51544:51546).' repmat(43200, 3, 1)], "TDB");
            [~, ~, primeMeridian] = ...
                referenceSystem.bodyRotationElements("jupiter", epoch);

            testCase.verifyTrue(all(primeMeridian >= 0 & ...
                primeMeridian < 2*pi), 'W must be wrapped to [0, 2*pi).');

            step = mod(diff(primeMeridian), 2*pi);
            expected = mod(deg2rad(870.5360000), 2*pi);
            % RelTol 1e-12 bounds ROUNDOFF ALONE: on a TDB grid the step
            % is exactly 870.5360000 deg, and W reaches only about 20 rad
            % before wrapping, where one ulp is 3.6e-15 - some 1.4e-15 of
            % the 2.63 rad step. It bounds the mod arithmetic, not the
            % table.
            testCase.verifyEqual(step, repmat(expected, 1, 2), ...
                'RelTol', 1e-12, 'The daily advance of W is wrong.');
        end

    end

    methods (Test, TestTags = {'speed'})

        function bodyRotationElements_speed_elementsAndTheFrame(testCase)
            % OPEN ITEM B1, THE L5f HALF. Both functions are pure polynomial
            % and trigonometric evaluation with no kernel and no MEX, so the
            % only thing that could make them slow is a per-epoch rebuild of
            % the table - which is exactly the defect section B.9 measured in
            % the rotation chain. Measured rather than assumed, for that
            % reason and no other.
            epoch = testCase.sampleEpoch(1000);

            referenceSystem.bodyRotationElements("mars", epoch);
            referenceSystem.rotationIcrfToBodyFixed("mars", epoch);

            elementTime = zeros(5, 1);
            frameTime = zeros(5, 1);
            for k = 1:5
                start = tic;
                referenceSystem.bodyRotationElements("mars", epoch);
                elementTime(k) = toc(start);
                start = tic;
                referenceSystem.rotationIcrfToBodyFixed("mars", epoch);
                frameTime(k) = toc(start);
            end

            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "bodyRotationElements (N=1000)", 1000, median(elementTime), ...
                0.02, min(elementTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "rotationIcrfToBodyFixed (N=1000)", 1000, median(frameTime), ...
                0.05, min(frameTime)));

            % THE FRAME IS THE ELEMENTS PLUS THREE ELEMENTARY ROTATIONS, so it
            % cannot legitimately cost ten times the elements. If it does, the
            % rotations are being assembled one page at a time rather than by
            % pagemtimes, which is the vectorisation defect this project keeps
            % finding and which no correctness test can see.
            ratio = min(frameTime)/min(elementTime);
            testCase.verifyLessThan(ratio, 10, sprintf( ...
                ['rotationIcrfToBodyFixed costs %.2fx bodyRotationElements. ', ...
                'It is those elements plus three elementary rotations; a ', ...
                'large factor means the pages are being built in a loop.'], ...
                ratio));
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function bodyRotationElements_vectorization_arcMatchesSingleEpochs(testCase)
            epoch = testCase.sampleEpoch(5);
            [arcRightAscension, arcDeclination, arcPrimeMeridian] = ...
                referenceSystem.bodyRotationElements("mercury", epoch);

            for k = 1:numel(epoch.day)
                single = referenceSystem.daySecondToEpoch( ...
                    [epoch.day(k) epoch.sec(k)], "TT");
                [rightAscension, declination, primeMeridian] = ...
                    referenceSystem.bodyRotationElements("mercury", single);
                % AbsTol 0 throughout: the evaluation carries no
                % cross-epoch state, so an arc must be BIT-IDENTICAL to
                % the same epochs one at a time. A non-zero tolerance
                % would hide exactly the blocking or indexing error this
                % looks for.
                testCase.verifyEqual(arcRightAscension(k), rightAscension, ...
                    'AbsTol', 0, sprintf('alpha0 differs at epoch %d.', k));
                testCase.verifyEqual(arcDeclination(k), declination, ...
                    'AbsTol', 0, sprintf('delta0 differs at epoch %d.', k));
                testCase.verifyEqual(arcPrimeMeridian(k), primeMeridian, ...
                    'AbsTol', 0, sprintf('W differs at epoch %d.', k));
            end
        end

    end

end
