classdef TestFrames < matlab.unittest.TestCase
%TESTFRAMES Layer L3 test suite — terrestrial frame realizations.
%
%   Populated by P10 (ITRF realizations) and P11 (datum transformations).
%
%   The reference literals come from an independent Python implementation of
%   the published models and, where an authority exists, from PROJ 9.5.1
%   through pyproj 3.7.2. The IGN parameter table was re-fetched from its
%   source URL and compared against the v1 transcription row by row before any
%   of this was written.
%
%   Risk R21 governs the L3 conventions: applying the position vector
%   parameters under the coordinate frame convention is a pure sign flip on
%   three rotations that leaves a plausible coordinate, so both conventions
%   carry their own reference literal here and the two are asserted to differ.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% Populated: 2026-07-26 09:10 (CEST, UTC+02:00) by prompts P10 and P11
% -------------------------------------------------------------------------

    properties (Constant)
        % A station in ITRF2020, and the same point in four other frames.
        Station = [4027893.716, 307045.475, 4919473.826]
        Itrf2014At2020 = [4027893.7129082847, 307045.4734710409, ...
            4919473.8263338208]
        Itrf93At2000 = [4027893.6681026383, 307045.5156454599, ...
            4919473.8286906062]
        Itrf2020From2014At2010 = [4027893.7190917153, 307045.4755289591, ...
            4919473.8276661793]
        Itrf2000From2014At2010 = [4027893.7252391344, 307045.4768509364, ...
            4919473.8103292845]

        StationVelocity = [-0.0152, 0.0191, 0.0115]
        VelocityItrf2014At2020 = [-0.015199999993616001, 0.018999999991978, ...
            0.011699999995170001]

        % A Helmert case with arcsecond-level rotations, both conventions.
        HelmertPoint = [-4052051.7643, 4212836.2017, -2545106.0245]
        HelmertTranslation = [0.06155, -0.01087, -0.04019]
        HelmertRotation = [-0.0394924, -0.0327221, -0.0328979]
        HelmertScale = -0.009994
        HelmertPositionVector = [-4052050.5865750117, 4212836.3077053120, ...
            -2545107.4886854435]
        HelmertCoordinateFrame = [-4052052.7379325773, 4212835.9897485180, ...
            -2545104.5898229773]

        % ED50 to WGS84 by Molodensky, from the Hayford 1924 ellipsoid.
        MolodenskyPoint = [52.5, 6.5, 45.0]
        MolodenskyTranslation = [89.5, 93.8, 123.1]
        MolodenskyDeltaSemiMajorAxis = -251.0
        MolodenskyDeltaFlattening = -1.4192702255886366e-05
        MolodenskyResult = [0.91628337025443407, 0.11346774843740481, ...
            396.82127209392593]
    end

    methods (Test, TestTags = {'contract'})

        function itrfParameters_contract_refusesAnUnknownRealization(testCase)
            testCase.verifyError(@() referenceSystem.itrfParameters("ITRF2021"), ...
                'MATLAB:validators:mustBeMember');
        end

        function itrfParameters_contract_listAgreesWithTheNamedForm(testCase)
            % The table is assembled from the same code path as the struct, so
            % the two cannot drift apart; this asserts that they have not.
            itrfTable = referenceSystem.itrfParameters("list");
            named = referenceSystem.itrfParameters("ITRF93");
            row = itrfTable(itrfTable.name == "ITRF93", :);

            testCase.verifyEqual(height(itrfTable), 13);
            testCase.verifyEqual(row.translation, named.translation, ...
                'AbsTol', 0);
            testCase.verifyEqual(row.rotation, named.rotation, 'AbsTol', 0);
            testCase.verifyEqual(row.scale, named.scale, 'AbsTol', 0);
        end

        function convertItrf_contract_refusesAnUnknownFrame(testCase)
            testCase.verifyError(@() referenceSystem.convertItrf( ...
                TestFrames.Station, "ITRF2020", "ETRF2000", 2020.0), ...
                'referenceSystem:convertItrf:unknownFrame');
        end

        function convertItrf_contract_refusesATypoRatherThanPassingItThrough(testCase)
            % Finding m-6: v1 returned upper(name) for anything it did not
            % recognise, so a typo became a frame name and failed elsewhere.
            testCase.verifyError(@() referenceSystem.convertItrf( ...
                TestFrames.Station, "ITRF20014", "ITRF2020", 2020.0), ...
                'referenceSystem:convertItrf:unknownFrame');
        end

        function convertItrf_contract_rejectsAnEpochCountMismatch(testCase)
            testCase.verifyError(@() referenceSystem.convertItrf( ...
                zeros(5, 3), "ITRF2020", "ITRF2014", [2000.0; 2010.0]), ...
                'referenceSystem:convertItrf:epochCountMismatch');
        end

        function convertItrf_contract_rejectsAVelocitySizeMismatch(testCase)
            testCase.verifyError(@() referenceSystem.convertItrf( ...
                zeros(5, 3), "ITRF2020", "ITRF2014", 2020.0, ...
                'Velocity', zeros(4, 3)), ...
                'referenceSystem:convertItrf:velocitySizeMismatch');
        end

        function convertItrf_contract_sameFrameIsTheIdentity(testCase)
            x = referenceSystem.convertItrf(TestFrames.Station, "IGS20", ...
                "ITRF2020", 2020.0);

            % IGS20 resolves to ITRF2020, so this must be bit identical and
            % not merely close: no arithmetic may happen at all.
            testCase.verifyTrue(isequal(x, TestFrames.Station), ...
                'An alias identity must not touch the coordinates.');
        end

        function applyHelmert7_contract_requiresTheConvention(testCase)
            p = TestFrames.helmertParameters();

            testCase.verifyError(@() referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, p, 'Units', "datum"), ...
                'referenceSystem:applyHelmert7:conventionRequired');
        end

        function applyHelmert7_contract_requiresTheUnits(testCase)
            p = TestFrames.helmertParameters();

            testCase.verifyError(@() referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, p, 'Convention', "positionVector"), ...
                'referenceSystem:applyHelmert7:unitsRequired');
        end

        function applyHelmert7_contract_refusesALargeRotation(testCase)
            p = TestFrames.helmertParameters();
            p.rotation = [200.0, 0.0, 0.0];

            testCase.verifyError(@() referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, p, 'Convention', "positionVector", ...
                'Units', "datum"), ...
                'referenceSystem:applyHelmert7:rotationTooLarge');
        end

        function applyHelmert7_contract_refusesAMissingParameter(testCase)
            p = rmfield(TestFrames.helmertParameters(), 'scale');

            testCase.verifyError(@() referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, p, 'Convention', "positionVector", ...
                'Units', "datum"), ...
                'referenceSystem:applyHelmert7:missingParameter');
        end

        function applyMolodensky_contract_refusesAMissingParameter(testCase)
            shift = rmfield(TestFrames.molodenskyShift(), 'deltaFlattening');

            testCase.verifyError(@() referenceSystem.applyMolodensky( ...
                TestFrames.MolodenskyPoint, shift, 'AngleUnit', "deg"), ...
                'referenceSystem:applyMolodensky:missingParameter');
        end

    end

    methods (Test, TestTags = {'reference'})

        function itrfParameters_reference_matchesThePublishedTable(testCase)
            % The published values ARE the transformation, so they are asserted
            % to the last printed digit. ITRF93 is the row that matters: it is
            % the only one with nonzero rotations, and the milliarcsecond to
            % radian conversion is the one that is easy to lose by 1000.
            p = referenceSystem.itrfParameters("ITRF93");
            mas = pi/180/3600*1e-3;

            testCase.verifyEqual(p.epoch, 2015.0);
            testCase.verifyEqual(p.translation, ...
                [-65.8, 1.9, -71.3]*1e-3, 'AbsTol', 1e-15);
            testCase.verifyEqual(p.translationRate, ...
                [-2.8, -0.2, -2.3]*1e-3, 'AbsTol', 1e-15);
            testCase.verifyEqual(p.scale, 4.47e-9, 'AbsTol', 1e-20);
            testCase.verifyEqual(p.rotation, ...
                [-3.36, -4.33, 0.75]*mas, 'AbsTol', 1e-20);
            testCase.verifyEqual(p.rotationRate, ...
                [-0.11, -0.19, 0.07]*mas, 'AbsTol', 1e-20);
            testCase.verifyEqual(p.convention, "positionVector");
        end

        function itrfParameters_reference_recentFramesHaveNoRotation(testCase)
            % Every realization from ITRF2000 onwards is rotation-free against
            % ITRF2020. If a nonzero value appeared here the table would have
            % been edited or a column misread.
            for name = ["ITRF2014", "ITRF2008", "ITRF2005", "ITRF2000"]
                p = referenceSystem.itrfParameters(name);
                testCase.verifyEqual(p.rotation, [0 0 0], 'AbsTol', 0, ...
                    sprintf('%s must have no rotation.', name));
            end
        end

        function convertItrf_reference_matchesPython(testCase)
            % 1e-9 m bounds two evaluations of the same seven-parameter similarity in different
            % languages: 1e-16 relative on a 6.4e6 m coordinate is 6e-10 m. It is not a bound
            % on the published parameters, whose own uncertainty is millimetres.
            x = referenceSystem.convertItrf(TestFrames.Station, "ITRF2020", ...
                "ITRF2014", 2020.0);

            testCase.verifyEqual(x, TestFrames.Itrf2014At2020, 'AbsTol', 1e-9);
        end

        function convertItrf_reference_itrf93CarriesTheRotations(testCase)
            x = referenceSystem.convertItrf(TestFrames.Station, "ITRF2020", ...
                "ITRF93", 2000.0);

            testCase.verifyEqual(x, TestFrames.Itrf93At2000, 'AbsTol', 1e-9);
            % Well above the translation alone: the rotations are being applied.
            testCase.verifyGreaterThan(norm(x - TestFrames.Station), 0.05);
        end

        function convertItrf_reference_inverseLegMatchesPython(testCase)
            % As above: 1e-9 m is about one ulp of a 6.4e6 m coordinate, bounding the exact
            % solve against the same solve performed in Python.
            x = referenceSystem.convertItrf(TestFrames.Station, "ITRF2014", ...
                "ITRF2020", 2010.0);

            testCase.verifyEqual(x, TestFrames.Itrf2020From2014At2010, ...
                'AbsTol', 1e-9);
        end

        function convertItrf_reference_chainingPivotsThroughItrf2020(testCase)
            % 1e-9 m, one ulp of a 6.4e6 m coordinate, now accumulated over two Helmert legs
            % rather than one.
            x = referenceSystem.convertItrf(TestFrames.Station, "ITRF2014", ...
                "ITRF2000", 2010.0);

            testCase.verifyEqual(x, TestFrames.Itrf2000From2014At2010, ...
                'AbsTol', 1e-9);
        end

        function convertItrf_reference_velocityCarriesBothCrossTerms(testCase)
            [~, v] = referenceSystem.convertItrf(TestFrames.Station, ...
                "ITRF2020", "ITRF2014", 2020.0, ...
                'Velocity', TestFrames.StationVelocity);

            testCase.verifyEqual(v, TestFrames.VelocityItrf2014At2020, ...
                'AbsTol', 1e-15);

            % The dominant term is the translation rate; the M*V and Mdot*X
            % cross terms are the small remainder, and they must be present.
            translationRate = ...
                referenceSystem.itrfParameters("ITRF2014").translationRate;
            remainder = v - TestFrames.StationVelocity - translationRate;
            testCase.verifyGreaterThan(max(abs(remainder)), 1e-13, ...
                'The cross terms are small but not zero.');
            testCase.verifyLessThan(max(abs(remainder)), 1e-10);
        end

        function convertItrf_reference_igsAliasesResolve(testCase)
            % AbsTol 0 IS THE CLAIM: an alias must resolve to the same parameter row, so the
            % two calls execute identical arithmetic on identical numbers. Anything but zero
            % would mean the alias reached a different row (obligation O13 is satisfied by
            % there being no second computation at all).
            viaAlias = referenceSystem.convertItrf(TestFrames.Station, ...
                "IGS14", "ITRF2020", 2010.0);
            viaName = referenceSystem.convertItrf(TestFrames.Station, ...
                "ITRF2014", "ITRF2020", 2010.0);

            testCase.verifyEqual(viaAlias, viaName, 'AbsTol', 0, ...
                'IGb14 and IGS14 are ITRF2014 by construction.');
        end

        function applyHelmert7_reference_bothConventionsMatchPython(testCase)
            p = TestFrames.helmertParameters();

            positionVector = referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, p, ...
                'Convention', "positionVector", 'Units', "datum");
            coordinateFrame = referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, p, ...
                'Convention', "coordinateFrame", 'Units', "datum");

            testCase.verifyEqual(positionVector, ...
                TestFrames.HelmertPositionVector, 'AbsTol', 1e-8);
            testCase.verifyEqual(coordinateFrame, ...
                TestFrames.HelmertCoordinateFrame, 'AbsTol', 1e-8);

            % RISK R21 MADE CONCRETE: at these rotations the two conventions
            % are about 3.6 m apart, and neither result looks wrong.
            separation = norm(positionVector - coordinateFrame);
            testCase.verifyGreaterThan(separation, 3.0, sprintf( ...
                'The two conventions differ by %.3f m.', separation));
        end

        function applyHelmert7_reference_unitsAreNotInterchangeable(testCase)
            % The same seven numbers under "datum" and "itrf" must give
            % different answers, which is why neither has a default.
            p = TestFrames.helmertParameters();

            asDatum = referenceSystem.applyHelmert7(TestFrames.HelmertPoint, ...
                p, 'Convention', "positionVector", 'Units', "datum");
            asItrf = referenceSystem.applyHelmert7(TestFrames.HelmertPoint, ...
                p, 'Convention', "positionVector", 'Units', "itrf");

            testCase.verifyGreaterThan(norm(asDatum - asItrf), 1.0);
        end

        function applyMolodensky_reference_matchesPython(testCase)
            % 1e-14 degrees is 1.1e-09 m at the surface and 1e-8 m on the height is one ulp of
            % the ellipsoidal normal: both bound two evaluations of the same differential
            % formulae, not the 16 mm the standard Molodensky form differs from the exact
            % Cartesian route by.
            geodetic = referenceSystem.applyMolodensky( ...
                TestFrames.MolodenskyPoint, TestFrames.molodenskyShift(), ...
                'Ellipsoid', "Hayford1924", 'AngleUnit', "deg");

            testCase.verifyEqual(deg2rad(geodetic(1:2)), ...
                TestFrames.MolodenskyResult(1:2), 'AbsTol', 1e-14);
            testCase.verifyEqual(geodetic(3), ...
                TestFrames.MolodenskyResult(3), 'AbsTol', 1e-8);
        end

    end

    methods (Test, TestTags = {'precision'})

        function convertItrf_precision_roundTripThroughItrf93(testCase)
            % ITRF93 has the largest rotations in the table, so it is the
            % hardest closure and the one that would expose a first-order
            % inverse rather than an exact solve.
            x = referenceSystem.convertItrf(TestFrames.Station, "ITRF2020", ...
                "ITRF93", 2000.0);
            back = referenceSystem.convertItrf(x, "ITRF93", "ITRF2020", 2000.0);

            worst = max(abs(back - TestFrames.Station));
            testCase.verifyLessThan(worst, 1e-8, sprintf( ...
                'ITRF93 round trip closure: %.3e m', worst));
        end

        function convertItrf_precision_positionAndVelocityBothClose(testCase)
            % 1e-9 m is one ulp of a 6.4e6 m coordinate after an exact solve, and 1e-15 m/s is
            % one ulp of a 2e-2 m/s plate velocity. Negating the parameters instead of solving
            % would show at 9.9e-04 m, six orders above this bound (decision D68).
            [x, v] = referenceSystem.convertItrf(TestFrames.Station, ...
                "ITRF2020", "ITRF2014", 2020.0, ...
                'Velocity', TestFrames.StationVelocity);
            [xBack, vBack] = referenceSystem.convertItrf(x, "ITRF2014", ...
                "ITRF2020", 2020.0, 'Velocity', v);

            testCase.verifyEqual(xBack, TestFrames.Station, 'AbsTol', 1e-9);
            testCase.verifyEqual(vBack, TestFrames.StationVelocity, ...
                'AbsTol', 1e-15);
        end

        function convertItrf_precision_chainEqualsTwoExplicitLegs(testCase)
            % AbsTol 0 is sound because both routes perform the same two solves in the same
            % order on the same numbers; this is an identity of execution, not of value
            % (obligation O13).
            chained = referenceSystem.convertItrf(TestFrames.Station, ...
                "ITRF2014", "ITRF2000", 2010.0);
            pivot = referenceSystem.convertItrf(TestFrames.Station, ...
                "ITRF2014", "ITRF2020", 2010.0);
            twoLegs = referenceSystem.convertItrf(pivot, "ITRF2020", ...
                "ITRF2000", 2010.0);

            testCase.verifyEqual(chained, twoLegs, 'AbsTol', 0, ...
                'The chain must BE the two legs, not merely agree with them.');
        end

        function applyHelmert7_precision_inverseIsExactNotNegated(testCase)
            % FINDING M-10. Parameter negation is a linearisation of the
            % inverse; at these rotations it is wrong at the millimetre level
            % while the exact solve closes at 1e-10 m.
            p = TestFrames.helmertParameters();
            p.rotation = [3.0, -2.0, 1.5];
            p.scale = 5.0;

            forward = referenceSystem.applyHelmert7(TestFrames.HelmertPoint, ...
                p, 'Convention', "positionVector", 'Units', "datum");
            exact = referenceSystem.applyHelmert7(forward, p, ...
                'Convention', "positionVector", 'Units', "datum", ...
                'Inverse', true);

            negated = p;
            negated.translation = -p.translation;
            negated.rotation = -p.rotation;
            negated.scale = -p.scale;
            byNegation = referenceSystem.applyHelmert7(forward, negated, ...
                'Convention', "positionVector", 'Units', "datum");

            exactError = max(abs(exact - TestFrames.HelmertPoint));
            negationError = max(abs(byNegation - TestFrames.HelmertPoint));

            testCase.verifyLessThan(exactError, 1e-8, sprintf( ...
                'Exact solve closes to %.3e m', exactError));
            testCase.verifyGreaterThan(negationError, 1e-4, sprintf( ...
                'Negation is wrong by %.3e m, which is the point', ...
                negationError));
        end

        function applyHelmert7_precision_siUnitsAgreeWithDatumUnits(testCase)
            % The unit conversion must be exactly a scaling, so the same
            % transformation expressed two ways must give the same answer.
            datum = TestFrames.helmertParameters();
            si = struct( ...
                'translation', datum.translation, ...
                'rotation', datum.rotation*pi/180/3600, ...
                'scale', datum.scale*1e-6);

            fromDatum = referenceSystem.applyHelmert7( ...
                TestFrames.HelmertPoint, datum, ...
                'Convention', "positionVector", 'Units', "datum");
            fromSi = referenceSystem.applyHelmert7(TestFrames.HelmertPoint, ...
                si, 'Convention', "positionVector", 'Units', "si");

            testCase.verifyEqual(fromSi, fromDatum, 'AbsTol', 1e-9);
        end

        function applyMolodensky_precision_agreesWithTheCartesianRoute(testCase)
            % The measured cost of the linearisation, over a global grid. This
            % is the number the ACCURACY block quotes, asserted rather than
            % asserted-elsewhere: centimetres, not millimetres.
            latitude = (-80:10:80).';
            longitude = repmat(6.5, numel(latitude), 1);
            height = zeros(size(latitude));
            source = [latitude, longitude, height];
            shift = TestFrames.molodenskyShift();

            approximate = referenceSystem.applyMolodensky(source, shift, ...
                'Ellipsoid', "Hayford1924", 'AngleUnit', "deg");

            % The exact route: Cartesian on the source ellipsoid, translate,
            % geodetic on the target ellipsoid.
            xyz = referenceSystem.geodeticToCartesian(source, ...
                'Ellipsoid', "Hayford1924", 'AngleUnit', "deg");
            exact = referenceSystem.cartesianToGeodetic( ...
                xyz + shift.translation, 'Ellipsoid', "WGS84", ...
                'AngleUnit', "deg");

            metrePerDegree = 111320;
            northError = max(abs(approximate(:, 1) - exact(:, 1)))*metrePerDegree;
            upError = max(abs(approximate(:, 3) - exact(:, 3)));

            testCase.verifyLessThan(northError, 0.10, sprintf( ...
                'Standard Molodensky north error: %.3f m', northError));
            testCase.verifyLessThan(upError, 0.10, sprintf( ...
                'Standard Molodensky up error: %.3f m', upError));
        end

        function applyMolodensky_precision_negationInvertsToTheSameOrder(testCase)
            % The documented reverse convention: negate the shift and use the
            % target ellipsoid. It carries the same linearisation error, which
            % is why the tolerance here is centimetres and not nanometres.
            shift = TestFrames.molodenskyShift();
            reverse = struct( ...
                'translation', -shift.translation, ...
                'deltaSemiMajorAxis', -shift.deltaSemiMajorAxis, ...
                'deltaFlattening', -shift.deltaFlattening);

            forward = referenceSystem.applyMolodensky( ...
                TestFrames.MolodenskyPoint, shift, ...
                'Ellipsoid', "Hayford1924", 'AngleUnit', "deg");
            back = referenceSystem.applyMolodensky(forward, reverse, ...
                'Ellipsoid', "WGS84", 'AngleUnit', "deg");

            testCase.verifyEqual(back(3), TestFrames.MolodenskyPoint(3), ...
                'AbsTol', 0.05);
            testCase.verifyEqual(back(1:2), ...
                TestFrames.MolodenskyPoint(1:2), 'AbsTol', 1e-6);
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function convertItrf_vectorization_arrayEqualsLoop(testCase)
            rng(211);
            x = TestFrames.Station + (rand(40, 3) - 0.5)*1e6;
            batch = referenceSystem.convertItrf(x, "ITRF2020", "ITRF93", 2005.0);

            for k = 1:size(x, 1)
                single = referenceSystem.convertItrf(x(k, :), "ITRF2020", ...
                    "ITRF93", 2005.0);
                % One ulp of 4e6 m; see applyHelmert7_vectorization for why
                % this is not AbsTol 0.
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 1e-9, ...
                    sprintf('Row %d must agree to one ulp.', k));
            end
        end

        function convertItrf_vectorization_perPointEpochsGroupCorrectly(testCase)
            % The grouping by unique epoch must give exactly what a per-point
            % call gives, including for epochs supplied out of order.
            rng(223);
            x = TestFrames.Station + (rand(30, 3) - 0.5)*1e5;
            epoch = 2000.0 + randi(4, 30, 1)*5.0;

            batch = referenceSystem.convertItrf(x, "ITRF2020", "ITRF2014", ...
                epoch);

            for k = 1:size(x, 1)
                single = referenceSystem.convertItrf(x(k, :), "ITRF2020", ...
                    "ITRF2014", epoch(k));
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 1e-9);
            end
        end

        function applyHelmert7_vectorization_arrayEqualsLoop(testCase)
            rng(227);
            x = TestFrames.HelmertPoint + (rand(30, 3) - 0.5)*1e5;
            p = TestFrames.helmertParameters();
            batch = referenceSystem.applyHelmert7(x, p, ...
                'Convention', "positionVector", 'Units', "datum");

            for k = 1:size(x, 1)
                single = referenceSystem.applyHelmert7(x(k, :), p, ...
                    'Convention', "positionVector", 'Units', "datum");
                % NOT AbsTol 0. Both calls run the same code; the only
                % difference is that BLAS may block and sum a 30x3 by 3x3
                % product differently from a 1x3 by 3x3 one, so bit-identity
                % is a claim about the library's blocking and not about this
                % function. The bound is one ulp of a coordinate of order
                % 4e6 m, that is 9.3e-10 m. Bit-identity IS asserted where
                % the arithmetic is elementwise, as in geodeticToCartesian,
                % because there it is a property of the code. The S4 run
                % failed here and PASSED the convertItrf pair below on the
                % same unsound claim, which is worse than failing.
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 1e-9);
            end
        end

    end

    methods (Test, TestTags = {'speed'})

        function convertItrf_speed_oneMillionPoints(testCase)
            % SEAM ITEM 5 and finding M-3: v1 looped over points with a 3x3
            % backslash inside the loop. The parameters depend only on the
            % epoch, so a single-epoch array must cost two matrix products
            % regardless of N.
            nPoint = 1e6;
            rng(229);
            x = TestFrames.Station + (rand(nPoint, 3) - 0.5)*1e6;

            % medianDuration(operation, repetitionCount): the count is
            % REQUIRED and has no default, because section D.1 fixes the
            % minimum at three and a default would let a caller take fewer
            % without noticing. The S4 run found this call one short.
            duration = TestPerformance.medianDuration(@() ...
                referenceSystem.convertItrf(x, "ITRF2014", "ITRF2000", ...
                2010.0), 5);
            testCase.log(1, TestPerformance.benchmarkRecord("convertItrf", nPoint, ...
                duration, 0.5));

            testCase.verifyLessThan(duration, 0.5, sprintf( ...
                'convertItrf on %g points took %.3f s', nPoint, duration));
        end

        function geodeticToCartesian_speed_oneMillionPoints(testCase)
            nPoint = 1e6;
            rng(233);
            llh = [(rand(nPoint, 1) - 0.5)*180, (rand(nPoint, 1) - 0.5)*360, ...
                rand(nPoint, 1)*1e4];

            duration = TestPerformance.medianDuration(@() ...
                referenceSystem.geodeticToCartesian(llh, ...
                'AngleUnit', "deg"), 5);
            testCase.log(1, TestPerformance.benchmarkRecord("geodeticToCartesian", nPoint, ...
                duration, 0.5));

            testCase.verifyLessThan(duration, 0.5, sprintf( ...
                'geodeticToCartesian on %g points took %.3f s', nPoint, ...
                duration));
        end

    end

    methods (Static, Access = private)

        function p = helmertParameters()
            %HELMERTPARAMETERS The published test set, in datum units.
            p = struct( ...
                'translation', TestFrames.HelmertTranslation, ...
                'rotation', TestFrames.HelmertRotation, ...
                'scale', TestFrames.HelmertScale);
        end

        function shift = molodenskyShift()
            %MOLODENSKYSHIFT The ED50 to WGS84 shift, Hayford 1924 to WGS84.
            shift = struct( ...
                'translation', TestFrames.MolodenskyTranslation, ...
                'deltaSemiMajorAxis', TestFrames.MolodenskyDeltaSemiMajorAxis, ...
                'deltaFlattening', TestFrames.MolodenskyDeltaFlattening);
        end

    end

end
