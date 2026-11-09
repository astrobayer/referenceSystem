classdef TestCoordinates < matlab.unittest.TestCase
%TESTCOORDINATES Layer L4 test suite — coordinate representations.
%
%   Populated by P12 (geodetic, Cartesian, local level, spherical) and P13
%   (UTM and heights).
%
%   The literals were produced by an independent Python implementation and,
%   where an authority exists, by PROJ 9.5.1 through pyproj 3.7.2. The PROJ
%   figures are carried as separate constants with their own looser tolerances,
%   so that a test failure says which of the two it disagrees with: an exact
%   match against the Python literal with a 0.05 mm gap to PROJ is the
%   documented Krueger truncation, while a gap to both is a defect.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% Populated: 2026-07-26 08:40 (CEST, UTC+02:00) by prompts P12 and P13
% -------------------------------------------------------------------------

    properties (Constant)
        % Reference station, GRS80. Degrees and metres.
        StationGeodetic = [49.144969, 12.877940, 665.0]
        StationCartesian = [4075532.4772346476, 931770.21864193969, ...
            4801623.4209741941]

        % A target 105 km away, and the same point in three representations.
        TargetGeodetic = [50.0, 13.5, 1200.0]
        TargetEnu = [44606.558644962417, 95294.772193809113, ...
            -333.11224214075196]
        TargetAzimuthElevation = [0.4377955650340723, ...
            -0.0031659123092131242, 105218.58032392524]

        % Spherical form of the station's Cartesian position, radians and metres.
        StationSpherical = [0.85441692986665685, 0.22476245387427854, ...
            6366611.9867783962]

        % UTM, GRS80. This implementation, then PROJ 9.5.1 for the same
        % point. The station is at 12.877940 E, so its STANDARD zone is 33,
        % whose central meridian is 15 E: floor((12.87794 + 180)/6) + 1 = 33,
        % and the zone 32/33 boundary in Germany is at 12 E. The S4 run caught
        % this as a wrong expectation in this file - the code had it right -
        % and the zone 32 literals are kept below rather than deleted, because
        % forcing a survey into a neighbouring zone across a boundary is the
        % documented reason 'Zone' exists and now has a reference case.
        StationUtm = [345243.20330925041, 5445739.60351230484]
        StationUtmProj = [345243.20331225690, 5445739.60368369520]
        StationUtmZone32 = [782787.18745360733, 5450815.02634494845]
        StationUtmZone32Proj = [782787.18744807690, 5450815.02651743405]
        SydneyGeodetic = [-33.858611, 151.214167]
        SydneyUtm = [334799.23347988032, 6252086.1000222228]
        SydneyUtmProj = [334799.23347572226, 6252086.0999992164]
    end

    methods (Test, TestTags = {'contract'})

        function geodeticToCartesian_contract_rejectsATransposedArray(testCase)
            % Nx3, one point per row. A 3xN array of three points is a common
            % mistake at the L2 boundary, where the layout is the other way up.
            testCase.verifyError(@() ...
                referenceSystem.geodeticToCartesian(zeros(3, 7)), ...
                'referenceSystem:geodeticToCartesian:wrongPointSize');
        end

        function geodeticToCartesian_contract_squareArrayIsThreePoints(testCase)
            % The documented resolution of the ambiguity: a 3x3 input is three
            % points, never one transposed triple, and it must not error.
            xyz = referenceSystem.geodeticToCartesian(zeros(3, 3));

            testCase.verifySize(xyz, [3 3]);
        end

        function geodeticToCartesian_contract_rejectsALatitudeOutOfRange(testCase)
            % A Cartesian triple passed in as geodetic looks exactly like this,
            % which is the reason the guard exists.
            testCase.verifyError(@() referenceSystem.geodeticToCartesian( ...
                TestCoordinates.StationCartesian), ...
                'referenceSystem:geodeticToCartesian:latitudeOutOfRange');
        end

        function cartesianToGeodetic_contract_refusesTheGeocentricRegion(testCase)
            testCase.verifyError(@() ...
                referenceSystem.cartesianToGeodetic([0 0 0]), ...
                'referenceSystem:cartesianToGeodetic:nearGeocentre');
        end

        function cartesianToEnu_contract_refusesAnOriginCountMismatch(testCase)
            testCase.verifyError(@() referenceSystem.cartesianToEnu( ...
                zeros(5, 3), zeros(2, 3)), ...
                'referenceSystem:cartesianToEnu:originCountMismatch');
        end

        function cartesianToEnu_contract_cartesianOriginUnderTheGeodeticDefault(testCase)
            % The default 'OriginFormat' is "geodetic" and a Cartesian origin
            % supplied under it must fail loudly on the latitude guard rather
            % than produce a plausibly tilted frame.
            testCase.verifyError(@() referenceSystem.cartesianToEnu( ...
                TestCoordinates.StationCartesian, ...
                TestCoordinates.StationCartesian), ...
                'referenceSystem:geodeticToCartesian:latitudeOutOfRange');
        end

        function enuToNed_contract_rejectsAWrongWidth(testCase)
            testCase.verifyError(@() referenceSystem.enuToNed(zeros(4, 2)), ...
                'referenceSystem:enuToNed:wrongPointSize');
        end

        function geodeticToUtm_contract_rejectsAZoneOutOfRange(testCase)
            testCase.verifyError(@() referenceSystem.geodeticToUtm( ...
                TestCoordinates.StationGeodetic(1:2), 'AngleUnit', "deg", ...
                'Zone', 61), 'referenceSystem:geodeticToUtm:zoneOutOfRange');
        end

        function utmToGeodetic_contract_requiresAValidHemisphere(testCase)
            testCase.verifyError(@() referenceSystem.utmToGeodetic( ...
                TestCoordinates.StationUtm, 32, 0), ...
                'referenceSystem:utmToGeodetic:invalidHemisphere');
        end

        function geoidUndulation_contract_refusesAPointOutsideTheGrid(testCase)
            grid = TestCoordinates.regionalGrid();

            testCase.verifyError(@() referenceSystem.geoidUndulation( ...
                [30 12], grid, 'AngleUnit', "deg"), ...
                'referenceSystem:geoidUndulation:outsideGrid');
        end

        function geoidUndulation_contract_refusesAMalformedGrid(testCase)
            grid = TestCoordinates.regionalGrid();
            grid = rmfield(grid, 'undulation');

            testCase.verifyError(@() referenceSystem.geoidUndulation( ...
                [49 12], grid, 'AngleUnit', "deg"), ...
                'referenceSystem:geoidUndulation:malformedGrid');
        end

        function ellipsoidalToOrthometric_contract_refusesImplicitExpansion(testCase)
            % A column of heights against a row of undulations would expand to a
            % matrix of every combination without a word.
            testCase.verifyError(@() ...
                referenceSystem.ellipsoidalToOrthometric(zeros(5, 1), ...
                zeros(1, 5)), ...
                'referenceSystem:ellipsoidalToOrthometric:sizeMismatch');
        end

    end

    methods (Test, TestTags = {'reference'})

        function geodeticToCartesian_reference_matchesProj(testCase)
            xyz = referenceSystem.geodeticToCartesian( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            % PROJ agrees bit for bit here; both evaluate the same closed form.
            testCase.verifyEqual(xyz, TestCoordinates.StationCartesian, ...
                'AbsTol', 1e-8);
        end

        function cartesianToGeodetic_reference_matchesTheStation(testCase)
            % 1e-12 degrees is 1.1e-07 m at the surface and bounds the convergence of the
            % iterative inverse against its own stopping criterion; 1e-8 m on the height is
            % 1.6e-15 relative on a 6.4e6 m radius, a few ulp of the ellipsoidal normal.
            llh = referenceSystem.cartesianToGeodetic( ...
                TestCoordinates.StationCartesian, 'AngleUnit', "deg");

            testCase.verifyEqual(llh(1:2), ...
                TestCoordinates.StationGeodetic(1:2), 'AbsTol', 1e-12);
            testCase.verifyEqual(llh(3), TestCoordinates.StationGeodetic(3), ...
                'AbsTol', 1e-8);
        end

        function cartesianToEnu_reference_matchesPython(testCase)
            % 1e-8 m is about 1e-15 relative on the 6.4e6 m origin radius the difference is
            % formed against: it bounds two evaluations of the same subtraction and rotation
            % in different languages, not any geodetic quantity.
            target = referenceSystem.geodeticToCartesian( ...
                TestCoordinates.TargetGeodetic, 'AngleUnit', "deg");
            enu = referenceSystem.cartesianToEnu(target, ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            testCase.verifyEqual(enu, TestCoordinates.TargetEnu, 'AbsTol', 1e-8);
        end

        function enuToAzimuthElevation_reference_matchesPython(testCase)
            % 1e-14 rad is a few ulp of an atan2 of quantities of order unity; 1e-7 m is 1e-12
            % relative on the 1.05e5 m slant range and bounds the square root of a sum of
            % three squares.
            ael = referenceSystem.enuToAzimuthElevation( ...
                TestCoordinates.TargetEnu);

            testCase.verifyEqual(ael(1:2), ...
                TestCoordinates.TargetAzimuthElevation(1:2), 'AbsTol', 1e-14);
            testCase.verifyEqual(ael(3), ...
                TestCoordinates.TargetAzimuthElevation(3), 'AbsTol', 1e-7);
        end

        function enuToAzimuthElevation_reference_cardinalDirectionsByHand(testCase)
            % The one assertion that pins the clockwise-from-North convention.
            % atan2(n, e) instead of atan2(e, n) would put East at 0 and North
            % at pi/2, still in range and still smooth.
            ael = referenceSystem.enuToAzimuthElevation( ...
                [0 1 0; 1 0 0; 0 -1 0; -1 0 0], 'AngleUnit', "deg");

            testCase.verifyEqual(ael(:, 1), [0; 90; 180; 270], 'AbsTol', 1e-12, ...
                'North 0, East 90, South 180, West 270.');
        end

        function cartesianToSpherical_reference_matchesPython(testCase)
            % 1e-14 rad is a few ulp of an atan2 of quantities of order unity; 1e-7 m is 1.6e-14
            % relative on the 6.4e6 m geocentric radius and bounds the square root of a sum of
            % three squares.
            spherical = referenceSystem.cartesianToSpherical( ...
                TestCoordinates.StationCartesian);

            testCase.verifyEqual(spherical(1:2), ...
                TestCoordinates.StationSpherical(1:2), 'AbsTol', 1e-14);
            testCase.verifyEqual(spherical(3), ...
                TestCoordinates.StationSpherical(3), 'AbsTol', 1e-7);
        end

        function cartesianToSpherical_reference_geocentricIsNotGeodetic(testCase)
            % The two differ by up to 11.5 arcminutes and this asserts that the
            % difference is present, so that a silent swap of the two would
            % fail here rather than 21 km downstream.
            geocentric = referenceSystem.cartesianToSpherical( ...
                TestCoordinates.StationCartesian, 'AngleUnit', "deg");
            geodetic = referenceSystem.cartesianToGeodetic( ...
                TestCoordinates.StationCartesian, 'AngleUnit', "deg");

            difference = abs(geodetic(1) - geocentric(1))*60;
            testCase.verifyGreaterThan(difference, 10.0, ...
                'At 49 degrees the two latitudes differ by about 11 arcminutes.');
            testCase.verifyEqual(geocentric(2), geodetic(2), 'AbsTol', 1e-12, ...
                'The longitude is identical in the two systems.');
        end

        function rotationEcefToEnu_reference_matchesTheExplicitMatrix(testCase)
            % The composed form against the trigonometric one written out. The
            % explicit matrix is the reference here precisely because the
            % implementation deliberately does not contain it.
            latitude = deg2rad(TestCoordinates.StationGeodetic(1));
            longitude = deg2rad(TestCoordinates.StationGeodetic(2));
            expected = [ ...
                -sin(longitude), cos(longitude), 0; ...
                -sin(latitude)*cos(longitude), -sin(latitude)*sin(longitude), ...
                cos(latitude); ...
                cos(latitude)*cos(longitude), cos(latitude)*sin(longitude), ...
                sin(latitude)];

            R = referenceSystem.rotationEcefToEnu( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            testCase.verifyEqual(R, expected, 'AbsTol', 1e-15);
        end

        function geodeticToUtm_reference_matchesPythonAndProj(testCase)
            [en, zone, hemisphere] = referenceSystem.geodeticToUtm( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            testCase.verifyEqual(zone, 33, ...
                '12.878 E is east of the 12 E boundary, so zone 33.');
            testCase.verifyEqual(hemisphere, 1);
            testCase.verifyEqual(en, TestCoordinates.StationUtm, 'AbsTol', 1e-6, ...
                'Against the independent Python implementation of the series.');
            % The gap to PROJ is the documented n^3 truncation, not a defect:
            % 3.0e-06 m in easting and 1.7e-04 m in northing, the northing term
            % being the meridian arc series and independent of the offset from
            % the central meridian.
            testCase.verifyEqual(en, TestCoordinates.StationUtmProj, ...
                'AbsTol', 5e-4, 'Against PROJ 9.5.1, at the truncation level.');
        end

        function geodeticToUtm_reference_forcedZoneCrossesTheBoundary(testCase)
            % The station forced into zone 32, its western neighbour. This is
            % what 'Zone' is for, and the easting of 782787 m - 283 km east of
            % the 9 E central meridian - is the visible cost of it.
            en = referenceSystem.geodeticToUtm( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg", ...
                'Zone', 32);

            testCase.verifyEqual(en, TestCoordinates.StationUtmZone32, ...
                'AbsTol', 1e-6);
            testCase.verifyEqual(en, TestCoordinates.StationUtmZone32Proj, ...
                'AbsTol', 5e-4, 'PROJ EPSG:32632 for the same point.');
        end

        function geodeticToUtm_reference_southernHemisphere(testCase)
            % 1e-6 m bounds the arithmetic against this toolbox's own recorded value, which is
            % a few ulp of a 6.3e6 m northing. The 1e-4 m against PROJ bounds the n^3 KRUEGER
            % TRUNCATION, measured at 6.3e-05 m near the central meridian and 1.1e-04 m at 20
            % degrees off it - a truncation bound, to be re-derived and not relaxed.
            [en, zone, hemisphere] = referenceSystem.geodeticToUtm( ...
                TestCoordinates.SydneyGeodetic, 'AngleUnit', "deg");

            testCase.verifyEqual(zone, 56);
            testCase.verifyEqual(hemisphere, -1);
            testCase.verifyEqual(en, TestCoordinates.SydneyUtm, 'AbsTol', 1e-6);
            testCase.verifyEqual(en, TestCoordinates.SydneyUtmProj, ...
                'AbsTol', 1e-4);
        end

        function geodeticToUtm_reference_zoneExceptionsAreOptional(testCase)
            % Southern Norway: zone 31 by the plain rule, zone 32 with the
            % widening. Both are correct answers to different questions, which
            % is why the exception must be asked for.
            point = [61.0, 5.0];

            [~, plain] = referenceSystem.geodeticToUtm(point, ...
                'AngleUnit', "deg");
            [~, widened] = referenceSystem.geodeticToUtm(point, ...
                'AngleUnit', "deg", 'ZoneException', "norway");

            testCase.verifyEqual(plain, 31);
            testCase.verifyEqual(widened, 32);
        end

        function geodeticToUtm_reference_latitudeBands(testCase)
            [~, ~, ~, band] = referenceSystem.geodeticToUtm( ...
                [0.5 0; 49.14 12; -33.86 151; 83 20; 88 20], ...
                'AngleUnit', "deg");

            testCase.verifyEqual(band, ["N"; "U"; "H"; "X"; ""], ...
                'Bands omit I and O; X spans 12 degrees; outside is empty.');
        end

        function ellipsoidalToOrthometric_reference_isTheDefinition(testCase)
            % H = h - N is one subtraction of numbers of order 1e2 m, so 1e-12 m is a few ulp.
            % What the test is really about is the SIGN of N, which is 100 m of height.
            H = referenceSystem.ellipsoidalToOrthometric(665.0, 46.5);
            testCase.verifyEqual(H, 618.5, 'AbsTol', 1e-12);
        end

    end

    methods (Test, TestTags = {'precision'})

        function cartesianToGeodetic_precision_roundTripOverTheGlobe(testCase)
            latitude = linspace(-90, 90, 181).';
            longitude = repmat(-179.0, 181, 1);
            worstHeight = 0;
            worstLatitude = 0;

            for height = [-10000, 0, 1e5, 4e7]
                llh = [latitude, longitude, repmat(height, 181, 1)];
                xyz = referenceSystem.geodeticToCartesian(llh, ...
                    'AngleUnit', "deg");
                back = referenceSystem.cartesianToGeodetic(xyz, ...
                    'AngleUnit', "deg");

                worstLatitude = max(worstLatitude, ...
                    max(abs(back(:, 1) - llh(:, 1))));
                worstHeight = max(worstHeight, max(abs(back(:, 3) - llh(:, 3))));
            end

            % A few ulp on coordinates of order 1e7 m; not an empirical bound.
            testCase.verifyLessThan(worstLatitude, 1e-12, sprintf( ...
                'Worst latitude round trip: %.3e deg', worstLatitude));
            testCase.verifyLessThan(worstHeight, 1e-6, sprintf( ...
                'Worst height round trip: %.3e m', worstHeight));
        end

        function cartesianToGeodetic_precision_exactlyAtThePole(testCase)
            % Longitude is undefined on the axis and is returned as exactly 0
            % by the documented convention; latitude and height stay exact.
            ellipsoid = referenceSystem.ellipsoidParameters("GRS80");
            llh = referenceSystem.cartesianToGeodetic([0 0 ellipsoid.b + 100]);

            testCase.verifyEqual(llh(1), pi/2, 'AbsTol', 1e-15);
            testCase.verifyEqual(llh(2), 0);
            testCase.verifyEqual(llh(3), 100, 'AbsTol', 1e-8);
        end

        function geodeticToCartesian_precision_grs80AgainstWgs84IsVisible(testCase)
            % The default changed from WGS84 in v1 to GRS80 here, and the
            % difference is above this toolbox's own accuracy target, so it is
            % asserted rather than described.
            grs80 = referenceSystem.geodeticToCartesian([90 0 0], ...
                'AngleUnit', "deg");
            wgs84 = referenceSystem.geodeticToCartesian([90 0 0], ...
                'AngleUnit', "deg", 'Ellipsoid', "WGS84");

            difference = abs(grs80(3) - wgs84(3));
            testCase.verifyGreaterThan(difference, 1e-5);
            testCase.verifyLessThan(difference, 1e-3, sprintf( ...
                'Polar radius difference GRS80 to WGS84: %.3e m', difference));
        end

        function cartesianToEnu_precision_roundTripAtTenThousandKilometres(testCase)
            rng(71);
            enu = (rand(200, 3) - 0.5)*2e7;
            xyz = referenceSystem.enuToCartesian(enu, ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");
            back = referenceSystem.cartesianToEnu(xyz, ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            worst = max(abs(back - enu), [], 'all');
            testCase.verifyLessThan(worst, 1e-6, sprintf( ...
                'Differencing two 1e7 m coordinates costs this: %.3e m', worst));
        end

        function cartesianToEnu_precision_originFormatsAgree(testCase)
            % The M-7 fix: position and orientation come from ONE argument, so
            % the two ways of naming the same origin must agree exactly.
            target = referenceSystem.geodeticToCartesian( ...
                TestCoordinates.TargetGeodetic, 'AngleUnit', "deg");
            originCartesian = referenceSystem.geodeticToCartesian( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            fromGeodetic = referenceSystem.cartesianToEnu(target, ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");
            fromCartesian = referenceSystem.cartesianToEnu(target, ...
                originCartesian, 'OriginFormat', "cartesian");

            testCase.verifyEqual(fromCartesian, fromGeodetic, 'AbsTol', 1e-8);
        end

        function rotationEcefToNed_precision_isAProperRotation(testCase)
            % A determinant is a sum of six triple products of sines and cosines of order
            % unity, so 1e-14 is a few ulp of that sum. PROPER is the claim: an improper
            % rotation is a reflection and would still be orthogonal.
            rng(73);
            origin = [(rand(1, 50) - 0.5)*180; (rand(1, 50) - 0.5)*360].';
            R = referenceSystem.rotationEcefToNed(origin, 'AngleUnit', "deg");

            residual = max(abs(pagemtimes(R, 'transpose', R, 'none') - ...
                eye(3)), [], 'all');
            determinant = zeros(1, 50);
            for k = 1:50
                determinant(k) = det(R(:, :, k));
            end

            testCase.verifyLessThan(residual, 1e-14);
            testCase.verifyEqual(determinant, ones(1, 50), 'AbsTol', 1e-14, ...
                'The axis exchange and the sign flip each contribute -1.');
        end

        function enuToNed_precision_agreesWithTheRotationPair(testCase)
            % Two independent routes to the same local frame: exchange the
            % components, or build the NED rotation directly.
            target = referenceSystem.geodeticToCartesian( ...
                TestCoordinates.TargetGeodetic, 'AngleUnit', "deg");
            origin = referenceSystem.geodeticToCartesian( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");

            enu = referenceSystem.cartesianToEnu(target, ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");
            viaExchange = referenceSystem.enuToNed(enu);

            R = referenceSystem.rotationEcefToNed( ...
                TestCoordinates.StationGeodetic, 'AngleUnit', "deg");
            direct = (target - origin)*R.';

            testCase.verifyEqual(viaExchange, direct, 'AbsTol', 1e-8);
        end

        function enuToNed_precision_roundTripIsBitIdentical(testCase)
            rng(77);
            enu = (rand(50, 3) - 0.5)*1e5;
            back = referenceSystem.nedToEnu(referenceSystem.enuToNed(enu));

            testCase.verifyTrue(isequal(back, enu), ...
                'Indexing and a sign change only; no arithmetic.');
        end

        function utmToGeodetic_precision_roundTripInsideTheZone(testCase)
            latitude = linspace(-79, 83, 60).';
            longitude = 9.0 + linspace(-3, 3, 60).';
            llh = [latitude, longitude];

            [en, zone, hemisphere] = referenceSystem.geodeticToUtm(llh, ...
                'AngleUnit', "deg");
            back = referenceSystem.utmToGeodetic(en, zone, hemisphere, ...
                'AngleUnit', "deg");

            worst = max(abs(back - llh), [], 'all')*111320;

            % MEASURED, not assumed: 7.4e-04 m, worst near +-55 degrees, and
            % reproduced to the same digits by the independent Python
            % implementation - so it is the METHOD, not this code. The forward
            % and inverse n^3 series are inverse to O(n^3) only; they are not
            % exact inverses of each other, and the residual decomposes as
            % 1.7e-04 m from the forward meridian arc and 5.9e-04 m from the
            % inverse rectifying-latitude series. The original 1e-9 deg bound
            % was a guess at machine precision and was wrong by four orders;
            % see handover section A.3 #14, corrected in revision 1.53.
            testCase.verifyLessThan(worst, 1.5e-3, sprintf( ...
                'Worst UTM round trip: %.3e m of ground distance', worst));
        end

        function azimuthElevationToEnu_precision_roundTrip(testCase)
            % 1e-12 rad bounds an angle recovered through an atan2 after two trigonometric
            % products; the relative 1e-14 on the range bounds a square root of a sum of three
            % squares. Both are floating-point bounds and neither is a pointing accuracy.
            rng(83);
            ael = [rand(100, 1)*2*pi, (rand(100, 1) - 0.5)*pi*0.98, ...
                rand(100, 1)*1e6];
            back = referenceSystem.enuToAzimuthElevation( ...
                referenceSystem.azimuthElevationToEnu(ael));

            testCase.verifyEqual(back(:, 1), ael(:, 1), 'AbsTol', 1e-12);
            testCase.verifyEqual(back(:, 2), ael(:, 2), 'AbsTol', 1e-12);
            testCase.verifyEqual(back(:, 3), ael(:, 3), 'RelTol', 1e-14);
        end

        function orthometricToEllipsoidal_precision_isTheExactInverse(testCase)
            % The pair is one addition and one subtraction, so 1e-11 m is a few ulp of heights
            % of order 1e3 m. There is no model error here to bound.
            rng(89);
            h = (rand(100, 1) - 0.2)*3000;
            N = (rand(100, 1) - 0.5)*100;

            back = referenceSystem.orthometricToEllipsoidal( ...
                referenceSystem.ellipsoidalToOrthometric(h, N), N);

            testCase.verifyEqual(back, h, 'AbsTol', 1e-11);
        end

        function geoidUndulation_precision_reproducesAPlanarField(testCase)
            % A field that is exactly linear in latitude and longitude is
            % reproduced exactly by bilinear interpolation, so any error here
            % is an indexing error and not an interpolation error.
            grid = TestCoordinates.regionalGrid();
            query = [49.13, 12.37; 48.5, 11.0; 50.9, 13.9];
            expected = 40.0 + 0.5*(query(:, 1) - 48.0) + ...
                0.25*(query(:, 2) - 10.0);

            undulation = referenceSystem.geoidUndulation(query, grid, ...
                'AngleUnit', "deg");

            testCase.verifyEqual(undulation, expected, 'AbsTol', 1e-10);
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function enuToAzimuthElevation_diagnostics_zeroRangeGivesNaNElevation(testCase)
            % Section C.6 rule 5: undefined but valid, so NaN and not an error.
            % The range, which carries the information, stays exactly zero.
            ael = referenceSystem.enuToAzimuthElevation([0 0 0]);

            testCase.verifyEqual(ael(1), 0);
            testCase.verifyTrue(isnan(ael(2)));
            testCase.verifyEqual(ael(3), 0);
        end

        function cartesianToSpherical_diagnostics_geocentreGivesNaNLatitude(testCase)
            spherical = referenceSystem.cartesianToSpherical([0 0 0]);

            testCase.verifyTrue(isnan(spherical(1)));
            testCase.verifyEqual(spherical(3), 0);
        end

        function geoidUndulation_diagnostics_longitudeWrapsIntoTheGrid(testCase)
            % A grid on 0 to 360 and a query at a negative longitude must meet.
            grid = TestCoordinates.regionalGrid();
            grid.longitude = grid.longitude + 350;      % now 360 to 366

            positive = referenceSystem.geoidUndulation([49.0, 362.0], grid, ...
                'AngleUnit', "deg");
            wrapped = referenceSystem.geoidUndulation([49.0, 2.0], grid, ...
                'AngleUnit', "deg");

            testCase.verifyEqual(wrapped, positive, 'AbsTol', 1e-12);
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function geodeticToCartesian_vectorization_arrayEqualsLoop(testCase)
            % AbsTol 0 IS SOUND HERE because the map is elementwise: no matrix product and no
            % reduction stands between a row and its result, so the batch and the single call
            % execute identical arithmetic on identical numbers (obligation O13).
            rng(97);
            llh = [(rand(30, 1) - 0.5)*180, (rand(30, 1) - 0.5)*360, ...
                rand(30, 1)*1e4];
            batch = referenceSystem.geodeticToCartesian(llh, 'AngleUnit', "deg");

            for k = 1:size(llh, 1)
                single = referenceSystem.geodeticToCartesian(llh(k, :), ...
                    'AngleUnit', "deg");
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 0, ...
                    sprintf('Row %d must be bit identical to the scalar call.', ...
                    k));
            end
        end

        function cartesianToGeodetic_vectorization_arrayEqualsLoop(testCase)
            % AbsTol 0 is sound because the iteration is elementwise per row: no reduction
            % crosses rows, so batch and single execute identical arithmetic (obligation O13).
            rng(101);
            llh = [(rand(30, 1) - 0.5)*180, (rand(30, 1) - 0.5)*360, ...
                rand(30, 1)*1e4];
            xyz = referenceSystem.geodeticToCartesian(llh, 'AngleUnit', "deg");
            batch = referenceSystem.cartesianToGeodetic(xyz);

            for k = 1:size(xyz, 1)
                single = referenceSystem.cartesianToGeodetic(xyz(k, :));
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 0);
            end
        end

        function cartesianToEnu_vectorization_perPointOriginsEqualTheLoop(testCase)
            % 1e-9 m RATHER THAN ZERO because this leg passes through a 3x3 by 3xN product,
            % where BLAS may block the larger operand differently (obligation O13). 1e-9 m is
            % about one ulp of the 6.4e6 m origin radius.
            rng(103);
            origin = [(rand(20, 1) - 0.5)*160, (rand(20, 1) - 0.5)*360, ...
                rand(20, 1)*100];
            target = referenceSystem.geodeticToCartesian(origin + ...
                [0.01, 0.01, 50], 'AngleUnit', "deg");

            batch = referenceSystem.cartesianToEnu(target, origin, ...
                'AngleUnit', "deg");

            for k = 1:20
                single = referenceSystem.cartesianToEnu(target(k, :), ...
                    origin(k, :), 'AngleUnit', "deg");
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 1e-9);
            end
        end

        function geodeticToUtm_vectorization_arrayEqualsLoop(testCase)
            % AbsTol 0 is sound because the Krueger series is evaluated elementwise per point,
            % with no reduction across points (obligation O13).
            rng(107);
            llh = [(rand(25, 1) - 0.5)*160, (rand(25, 1) - 0.5)*360];
            [batch, zone] = referenceSystem.geodeticToUtm(llh, ...
                'AngleUnit', "deg");

            for k = 1:size(llh, 1)
                [single, singleZone] = referenceSystem.geodeticToUtm( ...
                    llh(k, :), 'AngleUnit', "deg");
                testCase.verifyEqual(batch(k, :), single, 'AbsTol', 0);
                testCase.verifyEqual(zone(k), singleZone);
            end
        end

    end

    methods (Static, Access = private)

        function grid = regionalGrid()
            %REGIONALGRID A small planar test grid, degrees and metres.
            %   N is exactly linear in latitude and longitude, so bilinear
            %   interpolation reproduces it exactly and any discrepancy is an
            %   indexing error rather than an interpolation error.
            latitude = 48.0:0.25:51.0;
            longitude = 10.0:0.25:16.0;
            [longitudeGrid, latitudeGrid] = meshgrid(longitude, latitude);
            undulation = 40.0 + 0.5*(latitudeGrid - 48.0) + ...
                0.25*(longitudeGrid - 10.0);

            grid = struct('latitude', latitude, 'longitude', longitude, ...
                'undulation', undulation);
        end

    end


    methods (Test, TestTags = {'contract'})

        function sphericalToCartesian_contract_shapeAndRefusal(testCase)
            % P17: sphericalToCartesian reached session S6 with no test that
            % called it directly - it was exercised only as the return leg of a
            % round trip named for its partner, and a wrong column order there
            % cancels out. Driven forwards on its own it cannot.
            point = [0.5 1.0 6800000; -0.2 -2.0 6700000];

            cartesian = referenceSystem.sphericalToCartesian(point);

            testCase.verifySize(cartesian, [2 3], 'One row of output per row in.');
            testCase.verifyError(@() referenceSystem.sphericalToCartesian( ...
                [0.5 1.0]), ...
                'referenceSystem:sphericalToCartesian:wrongPointSize');
        end

        function cartesianToSpherical_contract_shapeAndRefusal(testCase)
            cartesian = [4075532.4772346476 931770.21864193969 4801623.4209741941];

            spherical = referenceSystem.cartesianToSpherical(cartesian);

            testCase.verifySize(spherical, [1 3], 'One row of output per row in.');
            testCase.verifyError(@() referenceSystem.cartesianToSpherical( ...
                [1 2 3 4]), ...
                'referenceSystem:cartesianToSpherical:wrongPointSize');
        end

        function nedToEnu_contract_shapeAndRefusal(testCase)
            enu = referenceSystem.nedToEnu([1 2 3; 4 5 6]);

            testCase.verifySize(enu, [2 3], 'One row of output per row in.');
            testCase.verifyError(@() referenceSystem.nedToEnu([1 2]), ...
                'referenceSystem:nedToEnu:wrongPointSize');
        end

        function enuToCartesian_contract_refusesABadOriginCount(testCase)
            % The origin is given ONCE or once per point, and nothing else. A
            % two-row origin against three points is the shape that would
            % otherwise be broadcast by implicit expansion into a plausible and
            % wrong answer.
            enu = [1000 2000 300; 0 0 0; -500 250 10];
            origin = [48.5 11.25 550; 49.0 11.5 600];

            testCase.verifyError(@() referenceSystem.enuToCartesian(enu, origin, ...
                'AngleUnit', "deg"), ...
                'referenceSystem:enuToCartesian:originCountMismatch');
            testCase.verifyError(@() referenceSystem.enuToCartesian([1 2], ...
                [48.5 11.25 550], 'AngleUnit', "deg"), ...
                'referenceSystem:enuToCartesian:wrongPointSize');
        end

        function azimuthElevationToEnu_contract_shapeAndRefusal(testCase)
            enu = referenceSystem.azimuthElevationToEnu( ...
                [135 30 1000; 0 90 500], 'AngleUnit', "deg");

            testCase.verifySize(enu, [2 3], 'One row of output per row in.');
            testCase.verifyError(@() referenceSystem.azimuthElevationToEnu( ...
                [1.1 0.4]), ...
                'referenceSystem:azimuthElevationToEnu:wrongPointSize');
        end

        function enuToAzimuthElevation_contract_shapeAndRefusal(testCase)
            azimuthElevation = referenceSystem.enuToAzimuthElevation( ...
                [1000 2000 300; -500 -500 100]);

            testCase.verifySize(azimuthElevation, [2 3], 'One row per row in.');
            testCase.verifyError(@() referenceSystem.enuToAzimuthElevation( ...
                [1 2 3 4]), ...
                'referenceSystem:enuToAzimuthElevation:wrongPointSize');
        end

        function orthometricToEllipsoidal_contract_refusesAMismatchedUndulation(testCase)
            testCase.verifyError(@() referenceSystem.orthometricToEllipsoidal( ...
                [100; 200; 300], [45; 46]), ...
                'referenceSystem:orthometricToEllipsoidal:sizeMismatch');
        end

    end

    methods (Test, TestTags = {'reference'})

        function sphericalToCartesian_reference_matchesTheClosedForm(testCase)
            % Hand-checkable geometry: geocentric latitude 45 degrees, longitude
            % 30 degrees, radius 6 800 000 m, so
            % X = r cos(phi) cos(lambda), Y = r cos(phi) sin(lambda),
            % Z = r sin(phi). Evaluated independently in Python; the point is
            % chosen away from every axis so that a swapped column shows.
            expected = [4.16413256273140339e+06, 2.40416305603426136e+06, ...
                4.80832611206852272e+06];

            cartesian = referenceSystem.sphericalToCartesian([45 30 6800000], ...
                'AngleUnit', "deg");

            % 1e-8 m bounds the difference between two evaluations of the same
            % three products of trigonometric functions in different languages:
            % about 1e-16 relative on a 6.8e6 m radius, that is 1e-9 m, doubled
            % for the degree-to-radian conversion. It is not a model bound.
            testCase.verifyEqual(cartesian, expected, 'AbsTol', 1e-8, ...
                'The spherical to Cartesian map differs from the closed form.');
        end

        function nedToEnu_reference_isThePublishedAxisChange(testCase)
            % NED to ENU is [N E D] -> [E N -D], exactly. The literal is the
            % definition and the assertion is exact: the function permutes and
            % negates, so no arithmetic stands between input and output and
            % AbsTol 0 is a claim about the function rather than about BLAS
            % blocking (obligation O13).
            ned = [10 20 30; -1 -2 -3];

            enu = referenceSystem.nedToEnu(ned);

            testCase.verifyEqual(enu, [20 10 -30; -2 -1 3], 'AbsTol', 0, ...
                'The NED to ENU axis change is not the published permutation.');
        end

        function enuToNed_reference_isThePublishedAxisChange(testCase)
            % The partner of the case above, and the reason both exist rather
            % than one with a flag (decision D36).
            enu = [20 10 -30; -2 -1 3];

            ned = referenceSystem.enuToNed(enu);

            testCase.verifyEqual(ned, [10 20 30; -1 -2 -3], 'AbsTol', 0, ...
                'The ENU to NED axis change is not the published permutation.');
        end

        function enuToCartesian_reference_matchesTheIndependentAssembly(testCase)
            % Origin 48.5 N, 11.25 E, 550 m on GRS80; local offset 1000 m east,
            % 2000 m north, 300 m up. Computed in Python from the ellipsoidal
            % normal formulae, N = a / sqrt(1 - e^2 sin^2 phi), and the
            % transposed ENU rotation. The offset has three distinct non-zero
            % components so that a swapped or dropped axis cannot cancel.
            expected = [4.15176741104392754e+06, 8.26857475698669674e+05, ...
                4.75585947913605440e+06];

            cartesian = referenceSystem.enuToCartesian([1000 2000 300], ...
                [48.5 11.25 550], 'AngleUnit', "deg");

            % 1e-7 m bounds two evaluations of the same expression in different
            % languages at a radius of 6.4e6 m: 1e-16 relative is 6e-10 m, and
            % the margin covers the degree conversion and the sum of three
            % rotated components. Nothing here is a model error.
            testCase.verifyEqual(cartesian, expected, 'AbsTol', 1e-7, ...
                'The ENU to Cartesian map differs from the independent assembly.');
        end

        function azimuthElevationToEnu_reference_matchesTheClosedForm(testCase)
            % Azimuth 135 degrees CLOCKWISE FROM NORTH, elevation 30 degrees,
            % slant range 1000 m, so E = r cos(el) sin(az), N = r cos(el)
            % cos(az), U = r sin(el). South-east and upward: E positive, N
            % negative. A counter-clockwise or from-east convention would put
            % the signs elsewhere, which is what this literal pins.
            expected = [6.12372435695794593e+02, -6.12372435695794479e+02, ...
                4.99999999999999943e+02];

            enu = referenceSystem.azimuthElevationToEnu([135 30 1000], ...
                'AngleUnit', "deg");

            % 1e-10 m is a few ulp of a 1000 m range through two trigonometric
            % factors; it bounds the arithmetic and no physical quantity.
            testCase.verifyEqual(enu, expected, 'AbsTol', 1e-10, ...
                'The azimuth-elevation convention differs from the closed form.');
        end

        function rotationEcefToNed_reference_matchesTheIndependentAssembly(testCase)
            % At 48.5 N, 11.25 E. Row 1 is the North unit vector in earth-fixed
            % components, row 2 East, row 3 Down. Computed in Python from the
            % standard local-level triad. THE ROW ORDER IS THE CLAIM: the same
            % three vectors in the ENU order would be an equally valid rotation
            % matrix, orthogonal and unit-determinant, and wrong.
            expected = [ ...
                -7.34564746623645015e-01, -1.46114012744547855e-01,  6.62620048215737500e-01; ...
                -1.95090322016128248e-01,  9.80785280403230431e-01,  0.00000000000000000e+00; ...
                -6.49887989790074228e-01, -1.29270758580750655e-01, -7.48955720789002077e-01];

            R = referenceSystem.rotationEcefToNed([48.5 11.25], 'AngleUnit', "deg");

            % 1e-15 is a few ulp of unity: the entries are products of two
            % trigonometric functions of numbers of order unity, so the bound
            % is on the arithmetic, not on any geodetic quantity.
            testCase.verifyEqual(R, expected, 'AbsTol', 1e-15, ...
                'The earth-fixed to NED triad differs from the independent one.');
        end

        function utmToGeodetic_reference_invertsThePublishedProjPoint(testCase)
            % PROJ 9.5.1's OWN easting and northing for the station, driven
            % backwards through this toolbox. The forward direction is already
            % checked against the same PROJ pair; running the published numbers
            % the other way is what covers the inverse Krueger series, which
            % revision 1.53 measured as the DOMINANT term of the round trip -
            % 5.9e-04 m of the 7.4e-04 m total.
            geodetic = referenceSystem.utmToGeodetic( ...
                TestCoordinates.StationUtmProj, 33, 1, 'AngleUnit', "deg");

            % 2e-8 degrees is 2.2e-03 m at this latitude and bounds the n^3
            % Krueger truncation of the inverse series plus PROJ's own forward
            % truncation, measured together at 7.4e-04 m worst case over the
            % zone. It is a TRUNCATION bound, not a rounding one, and it must be
            % re-derived rather than relaxed if the series order changes.
            testCase.verifyEqual(geodetic(1:2), ...
                TestCoordinates.StationGeodetic(1:2), 'AbsTol', 2e-8, ...
                'The inverse projection does not return the published point.');
        end

        function orthometricToEllipsoidal_reference_isTheDefinition(testCase)
            % h = H + N, the definition of the two height systems. The numbers
            % are exact in binary so the assertion is exact; what is being
            % checked is the SIGN of N, which is positive where the geoid lies
            % above the ellipsoid, and a sign error here is 100 m of height.
            h = referenceSystem.orthometricToEllipsoidal(618.5, 46.5);

            testCase.verifyEqual(h, 665.0, 'AbsTol', 0, ...
                'The orthometric to ellipsoidal height is not H + N.');
        end

    end

    methods (Test, TestTags = {'precision'})

        function sphericalToCartesian_precision_roundTripAcrossTheSphere(testCase)
            % Driven over a spread that includes the equator and both hemispheres
            % but stops short of the poles, where longitude is undefined and the
            % round trip cannot be asserted componentwise. The pole itself is a
            % separate edge case with its own test.
            latitude = linspace(-1.4, 1.4, 41)';
            longitude = linspace(-3.0, 3.0, 41)';
            radius = 6.7e6 + 1e5 * sin(latitude);
            spherical = [latitude, longitude, radius];

            back = referenceSystem.cartesianToSpherical( ...
                referenceSystem.sphericalToCartesian(spherical));

            % 1e-15 rad is a few ulp of an angle of order unity, which is what
            % an atan2 of two exactly-rounded products returns; 1e-8 m is 1e-15
            % relative on a 6.7e6 m radius. Both bound floating-point rounding.
            testCase.verifyLessThan(max(abs(back(:, 1:2) - spherical(:, 1:2)), ...
                [], 'all'), 1e-15, 'The angular round trip does not close.');
            testCase.verifyLessThan(max(abs(back(:, 3) - radius)), 1e-8, ...
                'The radial round trip does not close.');
        end

        function cartesianToSpherical_precision_atThePoleAndTheEquator(testCase)
            % The two edge cases the representation actually has: at the pole the
            % latitude is exactly +-pi/2 and longitude is arbitrary, at the
            % equator the latitude is exactly zero and the radius is the
            % Cartesian norm. Both are asserted for what IS defined there.
            point = [0 0 6.4e6; 0 0 -6.4e6; 6.378e6 0 0];

            spherical = referenceSystem.cartesianToSpherical(point);

            % 1e-16 rad is one ulp of pi/2: the latitude at the pole comes from
            % atan2(z, 0), which is exact, so only the representation of pi/2
            % contributes.
            testCase.verifyEqual(spherical(1, 1), pi / 2, 'AbsTol', 1e-16, ...
                'The north pole is not at +pi/2.');
            testCase.verifyEqual(spherical(2, 1), -pi / 2, 'AbsTol', 1e-16, ...
                'The south pole is not at -pi/2.');
            testCase.verifyEqual(spherical(3, 1), 0, 'AbsTol', 1e-16, ...
                'The equator is not at zero latitude.');
            % AbsTol 0: the radius on an axis is the absolute value of one
            % component and involves no summation.
            testCase.verifyEqual(spherical(3, 3), 6.378e6, 'AbsTol', 0, ...
                'The equatorial radius is not the Cartesian norm.');
        end

    end

    methods (Test, TestTags = {'speed'})

        function cartesianToGeodetic_speed_oneMillionPoints(testCase)
            % Section B.7 publishes a target for cartesianToGeodetic and the
            % suite has never measured it - only its partner geodeticToCartesian
            % was benchmarked. The two are not interchangeable: the forward map
            % is closed form and the inverse is iterative, so this is the one
            % that can degrade when a convergence criterion changes.
            %
            % 0.15 s, RE-DERIVED AT REV. 1.250 FROM THE SLOWEST OF THREE
            % MEASURED MEDIANS, 0.074467 s - see the class help of
            % TestPerformance for the runs and the rule. The 0.3 s it replaces
            % came from section B.7 and was never a measurement of this
            % function; it happens to sit at exactly 4x what the function
            % costs, which is a budget rather than a detector.
            targetSeconds = 0.15;
            point = TestPerformance.earthFixedCloud(1000000);

            medianSeconds = TestPerformance.medianDuration(@() ...
                referenceSystem.cartesianToGeodetic(point), 3);

            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("cartesianToGeodetic", 1000000, ...
                medianSeconds, targetSeconds));
            if medianSeconds > targetSeconds
                warning('referenceSystem:test:slowerThanTarget', ...
                    'cartesianToGeodetic took %.3f s against a %.3f s target.', ...
                    medianSeconds, targetSeconds);
            end
            testCase.verifyLessThan(medianSeconds, 5 * targetSeconds);
        end

    end

end
