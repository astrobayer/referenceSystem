classdef TestRotationAlgebra < matlab.unittest.TestCase
%TESTROTATIONALGEBRA Layer L4b test suite — rotation algebra.
%
%   Populated by P25. Risk R20 governs this class: a wrong Euler sense,
%   quaternion order or product still yields an orthogonal matrix that round
%   trips through its own inverse, so round-trip tests prove nothing on their
%   own. Independent reference literals and the D35 convention struct are the
%   defence, and both are exercised here.
%
%   Every literal in the Constant block was computed by an independent Python
%   implementation of the same published formulae, written and self-checked
%   BEFORE the MATLAB was written. That check earned its place twice: it found
%   a sign error in the proper-Euler gimbal-lock branch and a wrong operand
%   order in the quaternion composition rule, neither of which any round-trip
%   test in this file would have caught, because both rebuilt an orthogonal
%   matrix from their own mistake.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% Populated: 2026-07-26 08:10 (CEST, UTC+02:00) by prompt P25
% -------------------------------------------------------------------------

    properties (Constant)
        % Intrinsic ZYX, angles [yaw; pitch; roll] = [30; -20; 145] degrees.
        EulerAngleDegree = [30.0; -20.0; 145.0]
        EulerRotation = [ ...
             0.8137976813493738,   0.46984631039295416,  0.34202014332566871; ...
             0.23968375272166903, -0.80749382740072817,  0.5389855446957561; ...
             0.52941952411262749, -0.35664851509553624, -0.76975113132005735]
        EulerQuaternion = [0.24318343006287879; 0.92073919218068478; ...
            0.1926522920769147; 0.23661414514526441]

        % Proper-Euler ZXZ, intrinsic, angles [100; 35; -75] degrees.
        ProperAngleDegree = [100.0; 35.0; -75.0]
        ProperRotation = [ ...
             0.73427594445135835,  0.39228440635192097,  -0.55403229322232339; ...
            -0.37652246844753245,  0.91443571909139554,   0.1484525055496845; ...
             0.56486252146362337,  0.099600502925051182,  0.8191520442889918]

        % Axis-angle case, unit axis and 2.4 rad.
        AxisUnit = [0.30058671670520054; -0.50097786117533427; ...
            0.81158413510404148]
        AxisAngle = 2.4
        AxisRotation = [ ...
            -0.5804160683183639,   0.28656578914409531,  0.76223174699698382; ...
            -0.80982461322036636, -0.30134469547768616, -0.50336415280584346; ...
             0.08544754800657528, -0.90943467220008856,  0.40697333271355929]

        % Two quaternions and their products under both conventions.
        QuaternionA = [0.95154852464378858; 0.23929833774473031; ...
            0.18930785741199999; 0.038134576474850156]
        QuaternionB = [0.92881941023651882; -0.34412148525980546; ...
            0.1077466822489743; 0.085238248543769657]
        HamiltonProduct = [0.94251662080851295; -0.093155954555319762; ...
            0.24483871071875205; 0.20745696749969242]
        ShusterProduct = [0.94251662080851295; -0.11721074676979511; ...
            0.31187930728890267; 0.025599961452376224]

        AllSequences = ["XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX", ...
            "XYX", "XZX", "YXY", "YZY", "ZXZ", "ZYZ"]
    end

    methods (Test, TestTags = {'contract'})

        function attitudeConvention_contract_defaultIsGeodetic(testCase)
            c = referenceSystem.attitudeConvention();

            testCase.verifyEqual(c.sequence, "ZYX");
            testCase.verifyEqual(c.rotationType, "intrinsic");
            testCase.verifyEqual(c.sense, "frame");
            testCase.verifyEqual(c.quaternion, "scalarFirst");
            testCase.verifyEqual(c.product, "hamilton");
            testCase.verifyEqual(c.localFrame, "ENU");
        end

        function attitudeConvention_contract_aerospacePresetDiffersInThreeFields(testCase)
            geodetic = referenceSystem.attitudeConvention("geodetic");
            aerospace = referenceSystem.attitudeConvention("aerospace");

            testCase.verifyEqual(aerospace.quaternion, "scalarLast");
            testCase.verifyEqual(aerospace.product, "shuster");
            testCase.verifyEqual(aerospace.localFrame, "NED");
            testCase.verifyEqual(aerospace.sequence, geodetic.sequence, ...
                'Both presets are ZYX intrinsic; only three fields differ.');
            testCase.verifyEqual(aerospace.rotationType, geodetic.rotationType);
        end

        function attitudeConvention_contract_refusesAnUnknownPreset(testCase)
            testCase.verifyError(@() referenceSystem.attitudeConvention("jpl"), ...
                'referenceSystem:attitudeConvention:unknownPreset');
        end

        function attitudeConvention_contract_refusesAnUnknownField(testCase)
            c = referenceSystem.attitudeConvention();
            c.handedness = "right";
            testCase.verifyError(@() referenceSystem.attitudeConvention(c), ...
                'referenceSystem:attitudeConvention:unknownField');
        end

        function attitudeConvention_contract_refusesAMissingField(testCase)
            c = referenceSystem.attitudeConvention();
            c = rmfield(c, 'product');
            testCase.verifyError(@() referenceSystem.attitudeConvention(c), ...
                'referenceSystem:attitudeConvention:missingField');
        end

        function attitudeConvention_contract_refusesAnUnknownValue(testCase)
            c = referenceSystem.attitudeConvention();
            c.sense = "passive";     % the right idea under the wrong spelling
            testCase.verifyError(@() referenceSystem.attitudeConvention(c), ...
                'referenceSystem:attitudeConvention:unknownValue');
        end

        function rotationX_contract_returnsOnePagePerAngle(testCase)
            R = referenceSystem.rotationX([0.1 0.2 0.3 0.4]);

            testCase.verifySize(R, [3 3 4]);
            testCase.verifyClass(R, 'double');
        end

        function rotationZ_contract_rejectsAMatrixOfAngles(testCase)
            testCase.verifyError(@() referenceSystem.rotationZ(ones(2, 3)), ...
                'referenceSystem:rotationZ:wrongAngleSize');
        end

        function rotationFromEulerSequence_contract_rejectsWrongAngleShape(testCase)
            testCase.verifyError(@() ...
                referenceSystem.rotationFromEulerSequence(ones(2, 5)), ...
                'referenceSystem:rotationFromEulerSequence:wrongAngleSize');
        end

        function rotationFromEulerSequence_contract_requiresASequence(testCase)
            c = referenceSystem.attitudeConvention();
            c.sequence = "";
            testCase.verifyError(@() referenceSystem.rotationFromEulerSequence( ...
                [0.1; 0.2; 0.3], 'Convention', c), ...
                'referenceSystem:rotationFromEulerSequence:sequenceRequired');
        end

        function rotationFromRollPitchYaw_contract_refusesAForeignSequence(testCase)
            c = referenceSystem.attitudeConvention();
            c.sequence = "XYZ";
            testCase.verifyError(@() referenceSystem.rotationFromRollPitchYaw( ...
                [0.1; 0.2; 0.3], 'Convention', c), ...
                'referenceSystem:rotationFromRollPitchYaw:conventionMismatch');
        end

        function quaternionFromRotation_contract_rejectsWrongMatrixSize(testCase)
            testCase.verifyError(@() ...
                referenceSystem.quaternionFromRotation(eye(4)), ...
                'referenceSystem:quaternionFromRotation:wrongMatrixSize');
        end

        function rotationFromQuaternion_contract_rejectsAZeroQuaternion(testCase)
            testCase.verifyError(@() ...
                referenceSystem.rotationFromQuaternion(zeros(4, 1)), ...
                'referenceSystem:rotationFromQuaternion:zeroQuaternion');
        end

        function multiplyQuaternions_contract_refusesAConventionMismatch(testCase)
            % SEAM ITEM 8, and the whole structural protection of D35: no wrong
            % convention produces a non-orthogonal matrix, so this test is the
            % only thing standing between a caller and a silent error.
            [qa, geodetic] = referenceSystem.quaternionFromRotation( ...
                TestRotationAlgebra.EulerRotation);
            aerospace = referenceSystem.attitudeConvention("aerospace");
            qb = referenceSystem.quaternionFromRotation( ...
                TestRotationAlgebra.ProperRotation, 'Convention', aerospace);

            first = struct('quaternion', qa, 'convention', geodetic);
            second = struct('quaternion', qb, 'convention', aerospace);

            testCase.verifyError(@() ...
                referenceSystem.multiplyQuaternions(first, second), ...
                'referenceSystem:multiplyQuaternions:conventionMismatch');
        end

        function multiplyQuaternions_contract_acceptsMatchingTaggedOperands(testCase)
            [qa, c] = referenceSystem.quaternionFromRotation( ...
                TestRotationAlgebra.EulerRotation);
            qb = referenceSystem.quaternionFromRotation( ...
                TestRotationAlgebra.ProperRotation);
            first = struct('quaternion', qa, 'convention', c);
            second = struct('quaternion', qb, 'convention', c);

            [q, used] = referenceSystem.multiplyQuaternions(first, second);

            testCase.verifySize(q, [4 1]);
            testCase.verifyEqual(used.product, "hamilton");
        end

        function multiplyQuaternions_contract_refusesAMalformedOperand(testCase)
            testCase.verifyError(@() referenceSystem.multiplyQuaternions( ...
                struct('q', [1; 0; 0; 0]), [1; 0; 0; 0]), ...
                'referenceSystem:multiplyQuaternions:malformedOperand');
        end

        function axisAngleFromRotation_contract_zeroRotationReportsTheZAxis(testCase)
            % Documented convention: the axis is undefined at zero rotation and
            % is reported as [0; 0; 1] rather than NaN, so that axis*angle is
            % exactly the zero rotation vector.
            [axis, angle] = referenceSystem.axisAngleFromRotation(eye(3));

            testCase.verifyEqual(axis, [0; 0; 1]);
            testCase.verifyEqual(angle, 0, 'AbsTol', 1e-15);
        end

        function rotationFromAxisAngle_contract_rejectsAZeroAxis(testCase)
            testCase.verifyError(@() ...
                referenceSystem.rotationFromAxisAngle([0; 0; 0], 1.0), ...
                'referenceSystem:rotationFromAxisAngle:zeroAxis');
        end

    end

    methods (Test, TestTags = {'reference'})

        function rotationFromEulerSequence_reference_matchesPython(testCase)
            % 1e-15 is a few ulp of a three-factor product of rotation entries of order unity.
            R = referenceSystem.rotationFromEulerSequence( ...
                TestRotationAlgebra.EulerAngleDegree, 'AngleUnit', "deg");

            testCase.verifyEqual(R, TestRotationAlgebra.EulerRotation, ...
                'AbsTol', 1e-15, ...
                'Intrinsic ZYX against the independent Python literal.');
        end

        function rotationFromEulerSequence_reference_matchesTheProperEulerCase(testCase)
            % 1e-15 is a few ulp of a three-factor product of rotation entries of order unity;
            % the proper Euler sequences accumulate no differently from the Tait-Bryan ones.
            c = referenceSystem.attitudeConvention();
            c.sequence = "ZXZ";
            R = referenceSystem.rotationFromEulerSequence( ...
                TestRotationAlgebra.ProperAngleDegree, 'AngleUnit', "deg", ...
                'Convention', c);

            testCase.verifyEqual(R, TestRotationAlgebra.ProperRotation, ...
                'AbsTol', 1e-15);
        end

        function rotationZ_reference_ninetyDegreesByHand(testCase)
            % Verified by hand: a frame rotation of +90 degrees about z sends
            % the x axis of the old frame to [0; -1; 0] in the new one.
            R = referenceSystem.rotationZ(90, 'AngleUnit', "deg");

            testCase.verifyEqual(R, [0 1 0; -1 0 0; 0 0 1], 'AbsTol', 1e-15);
            testCase.verifyEqual(R*[1; 0; 0], [0; -1; 0], 'AbsTol', 1e-15);
        end

        function rotationX_reference_ninetyDegreesByHand(testCase)
            % cos(pi/2) evaluates to 6.1e-17 rather than to zero, so the residual is the binary
            % representation of pi/2 and not the rotation; 1e-15 is a few ulp of unity.
            R = referenceSystem.rotationX(90, 'AngleUnit', "deg");
            testCase.verifyEqual(R, [1 0 0; 0 0 1; 0 -1 0], 'AbsTol', 1e-15);
        end

        function rotationY_reference_ninetyDegreesByHand(testCase)
            % As rotationX: the residual is the representation of pi/2, and 1e-15 is a few ulp
            % of unity.
            R = referenceSystem.rotationY(90, 'AngleUnit', "deg");
            testCase.verifyEqual(R, [0 0 -1; 0 1 0; 1 0 0], 'AbsTol', 1e-15);
        end

        function quaternionFromRotation_reference_matchesPython(testCase)
            % 1e-15 is a few ulp of a unit quaternion component through Shepperd's square root,
            % whose branch selection keeps the divisor away from zero.
            q = referenceSystem.quaternionFromRotation( ...
                TestRotationAlgebra.EulerRotation);

            testCase.verifyEqual(q, TestRotationAlgebra.EulerQuaternion, ...
                'AbsTol', 1e-15);
        end

        function rotationFromAxisAngle_reference_matchesPython(testCase)
            % 1e-15 is a few ulp of unity through the half-angle identity 1 - cos t = 2
            % sin^2(t/2), which is exact at every angle and needs no threshold.
            R = referenceSystem.rotationFromAxisAngle( ...
                TestRotationAlgebra.AxisUnit, TestRotationAlgebra.AxisAngle);

            testCase.verifyEqual(R, TestRotationAlgebra.AxisRotation, ...
                'AbsTol', 1e-15);
        end

        function multiplyQuaternions_reference_bothProductsMatchPython(testCase)
            % 1e-15 is a few ulp of a four-term sum of products of unit components. The two
            % products differ only in the sign of the cross term, so the same bound covers both.
            hamilton = referenceSystem.multiplyQuaternions( ...
                TestRotationAlgebra.QuaternionA, TestRotationAlgebra.QuaternionB);

            c = referenceSystem.attitudeConvention();
            c.product = "shuster";
            shuster = referenceSystem.multiplyQuaternions( ...
                TestRotationAlgebra.QuaternionA, ...
                TestRotationAlgebra.QuaternionB, 'Convention', c);

            testCase.verifyEqual(hamilton, ...
                TestRotationAlgebra.HamiltonProduct, 'AbsTol', 1e-15);
            testCase.verifyEqual(shuster, ...
                TestRotationAlgebra.ShusterProduct, 'AbsTol', 1e-15);
            testCase.verifyGreaterThan(norm(hamilton - shuster), 0.1, ...
                'The two products must be far apart, or this test is vacuous.');
        end

        function rotationFromRollPitchYaw_reference_isIntrinsicZyxReversed(testCase)
            % Roll, pitch, yaw is the same rotation as the ZYX literal with the
            % angle order reversed. If the reversal were dropped the matrix
            % would still be orthogonal, which is why this is asserted against
            % the literal and not against a round trip.
            rpy = flipud(TestRotationAlgebra.EulerAngleDegree);
            R = referenceSystem.rotationFromRollPitchYaw(rpy, ...
                'AngleUnit', "deg");

            testCase.verifyEqual(R, TestRotationAlgebra.EulerRotation, ...
                'AbsTol', 1e-15);
        end

    end

    methods (Test, TestTags = {'precision'})

        function eulerSequenceFromRotation_precision_roundTripAllTwelveSequences(testCase)
            rng(20260726);
            c = referenceSystem.attitudeConvention();
            worst = 0;

            for sequenceName = TestRotationAlgebra.AllSequences
                for rotationType = ["intrinsic", "extrinsic"]
                    c.sequence = sequenceName;
                    c.rotationType = rotationType;
                    angles = TestRotationAlgebra.safeAngles(sequenceName, 200);

                    R = referenceSystem.rotationFromEulerSequence(angles, ...
                        'Convention', c);
                    back = referenceSystem.eulerSequenceFromRotation(R, ...
                        'Convention', c);

                    worst = max(worst, max(abs(back - angles), [], 'all'));
                end
            end

            % A few ulp of an atan2 pair; not an EOP-level or empirical bound.
            testCase.verifyLessThan(worst, 1e-13, ...
                sprintf('Worst Euler round trip over 12 sequences: %.3e', worst));
        end

        function rotationFromEulerSequence_precision_intrinsicEqualsReversedExtrinsic(testCase)
            % The identity the implementation is built on, asserted rather than
            % assumed: intrinsic (i,j,k) with (a1,a2,a3) is extrinsic (k,j,i)
            % with (a3,a2,a1).
            rng(11);
            angles = (rand(3, 50) - 0.5)*2*pi;
            intrinsic = referenceSystem.attitudeConvention();
            extrinsic = intrinsic;
            extrinsic.sequence = "XYZ";
            extrinsic.rotationType = "extrinsic";

            first = referenceSystem.rotationFromEulerSequence(angles, ...
                'Convention', intrinsic);
            second = referenceSystem.rotationFromEulerSequence( ...
                flipud(angles), 'Convention', extrinsic);

            testCase.verifyEqual(second, first, 'AbsTol', 1e-15);
        end

        function rotationFromEulerSequence_precision_isOrthogonal(testCase)
            rng(3);
            R = referenceSystem.rotationFromEulerSequence( ...
                (rand(3, 200) - 0.5)*2*pi);
            residual = max(abs(pagemtimes(R, 'transpose', R, 'none') - ...
                eye(3)), [], 'all');

            % A few ulp of a three-term dot product of numbers of order unity.
            testCase.verifyLessThan(residual, 1e-14, ...
                sprintf('max |R''R - I| = %.3e', residual));
        end

        function quaternionFromRotation_precision_roundTripNearOneHundredEighty(testCase)
            % Shepperd's branch exists for exactly this: the naive
            % q0 = sqrt(1 + trace)/2 loses half its digits here.
            axis = [1; 2; 3]/norm([1; 2; 3]);
            angle = pi - 1e-8;
            R = referenceSystem.rotationFromAxisAngle(axis, angle);

            q = referenceSystem.quaternionFromRotation(R);
            back = referenceSystem.rotationFromQuaternion(q);

            testCase.verifyEqual(back, R, 'AbsTol', 1e-14);
            testCase.verifyEqual(norm(q), 1, 'AbsTol', 1e-15);
        end

        function quaternionFromRotation_precision_doubleCoverGivesOneMatrix(testCase)
            q = TestRotationAlgebra.EulerQuaternion;
            first = referenceSystem.rotationFromQuaternion(q);
            second = referenceSystem.rotationFromQuaternion(-q);

            % Every term is quadratic in q, so this is bit identical and an
            % isequal is the right assertion, not a tolerance.
            testCase.verifyTrue(isequal(first, second), ...
                'q and -q must give the same matrix bit for bit.');
        end

        function quaternionFromEulerSequence_precision_agreesWithTheMatrixRoute(testCase)
            rng(5);
            c = referenceSystem.attitudeConvention();
            worst = 0;

            for sequenceName = TestRotationAlgebra.AllSequences
                c.sequence = sequenceName;
                angles = (rand(3, 40) - 0.5)*2*pi;

                direct = referenceSystem.quaternionFromEulerSequence(angles, ...
                    'Convention', c);
                viaMatrix = referenceSystem.quaternionFromRotation( ...
                    referenceSystem.rotationFromEulerSequence(angles, ...
                    'Convention', c), 'Convention', c);

                worst = max(worst, max(abs(direct - viaMatrix), [], 'all'));
            end

            testCase.verifyLessThan(worst, 1e-14, sprintf( ...
                'Direct quaternion route against the matrix route: %.3e', worst));
        end

        function multiplyQuaternions_precision_compositionOrderIsAsDocumented(testCase)
            % All four rows of the table in the METHOD block. Each is a valid
            % rotation, so only an explicit assertion distinguishes them.
            rng(9);
            a = referenceSystem.quaternionFromRotation( ...
                referenceSystem.rotationFromEulerSequence(rand(3, 1)));
            b = referenceSystem.quaternionFromRotation( ...
                referenceSystem.rotationFromEulerSequence(rand(3, 1)));

            for sense = ["frame", "vector"]
                for product = ["hamilton", "shuster"]
                    c = referenceSystem.attitudeConvention();
                    c.sense = sense;
                    c.product = product;

                    q = referenceSystem.multiplyQuaternions(a, b, ...
                        'Convention', c);
                    Rproduct = referenceSystem.rotationFromQuaternion(q, ...
                        'Convention', c);
                    Ra = referenceSystem.rotationFromQuaternion(a, ...
                        'Convention', c);
                    Rb = referenceSystem.rotationFromQuaternion(b, ...
                        'Convention', c);

                    reversed = strcmp(sense, "frame") == ...
                        strcmp(product, "hamilton");
                    if reversed
                        expected = Rb*Ra;
                    else
                        expected = Ra*Rb;
                    end
                    testCase.verifyEqual(Rproduct, expected, 'AbsTol', 1e-14, ...
                        sprintf('%s / %s composition order.', sense, product));
                end
            end
        end

        function invertQuaternion_precision_productIsTheIdentity(testCase)
            % 1e-15 is a few ulp of a four-term sum of products of unit components, which is
            % what q times its conjugate accumulates.
            q = TestRotationAlgebra.EulerQuaternion;
            identity = referenceSystem.multiplyQuaternions(q, ...
                referenceSystem.invertQuaternion(q));

            testCase.verifyEqual(identity, [1; 0; 0; 0], 'AbsTol', 1e-15);
        end

        function normalizeQuaternion_precision_fixesNormAndSign(testCase)
            % 1e-15 is a few ulp of unity through a square root of four squares.
            q = referenceSystem.normalizeQuaternion(-3*[0.5; 0.5; 0.5; 0.5]);

            testCase.verifyEqual(norm(q), 1, 'AbsTol', 1e-15);
            testCase.verifyGreaterThanOrEqual(q(1), 0, ...
                'The documented sign rule is q0 >= 0.');
        end

        function axisAngleFromRotation_precision_roundTripOverTheWholeRange(testCase)
            % 1e-14 is a few ulp of unity AMPLIFIED BY THE 1/(2 sin t) OF THE AXIS RECOVERY,
            % which grows without bound as t approaches 0 or pi. The sweep stops clear of both;
            % the identity rotation has its own test, because it is where this once raised.
            rng(13);
            axis = rand(3, 60) - 0.5;
            axis = axis./vecnorm(axis);
            angle = [1e-9, linspace(1e-3, pi - 1e-3, 58), pi - 1e-9];

            R = referenceSystem.rotationFromAxisAngle(axis, angle);
            [backAxis, backAngle] = referenceSystem.axisAngleFromRotation(R);
            rebuilt = referenceSystem.rotationFromAxisAngle(backAxis, backAngle);

            testCase.verifyEqual(rebuilt, R, 'AbsTol', 1e-14);
            testCase.verifyEqual(backAngle, angle, 'AbsTol', 1e-14);
        end

        function rollPitchYawFromRotation_precision_roundTrip(testCase)
            % 1e-13 rad allows for the conditioning of the asin near the ends of the pitch
            % range, where its derivative grows; away from there the residual is a few ulp of
            % an angle of order unity.
            rng(21);
            rpy = [(rand(1, 50) - 0.5)*2*pi; ...
                (rand(1, 50) - 0.5)*(pi - 0.2); ...
                (rand(1, 50) - 0.5)*2*pi];

            R = referenceSystem.rotationFromRollPitchYaw(rpy);
            back = referenceSystem.rollPitchYawFromRotation(R);

            testCase.verifyEqual(back, rpy, 'AbsTol', 1e-13);
        end

        function eulerSequenceFromQuaternion_precision_agreesWithTheMatrixRoute(testCase)
            % The two routes differ by one quaternion-to-matrix step, so 1e-13 bounds a few ulp
            % of unity carried through that step and then through an atan2 and an asin.
            rng(17);
            angles = [(rand(1, 40) - 0.5)*2*pi; ...
                (rand(1, 40) - 0.5)*(pi - 0.4); ...
                (rand(1, 40) - 0.5)*2*pi];

            q = referenceSystem.quaternionFromEulerSequence(angles);
            fromQuaternion = referenceSystem.eulerSequenceFromQuaternion(q);
            fromRotation = referenceSystem.eulerSequenceFromRotation( ...
                referenceSystem.rotationFromEulerSequence(angles));

            testCase.verifyEqual(fromQuaternion, fromRotation, 'AbsTol', 1e-13);
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function eulerSequenceFromRotation_diagnostics_gimbalLockWarnsOncePerCall(testCase)
            % THIS TEST ASSERTS A WARNING, SO IT CONSUMES IT. The report lists
            % warnings nobody claimed, and an asserted warning is claimed.
            % Registered as a cleanup so it fires on pass, on failure and on a
            % filtered assumption alike. See WarningRecordingPlugin.
            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>
            % Section C.6 rule 2 and seam item 9: one warning for the call,
            % never one per epoch, however many pages are singular.
            rng(61);
            angles = [(rand(1, 1000) - 0.5)*2*pi; ...
                repmat(pi/2, 1, 1000); (rand(1, 1000) - 0.5)*2*pi];
            R = referenceSystem.rotationFromEulerSequence(angles);

            state = warning('off', 'all');
            cleanup = onCleanup(@() warning(state));
            lastwarn('', '');
            [~, info] = referenceSystem.eulerSequenceFromRotation(R);
            [~, lastIdentifier] = lastwarn();

            testCase.verifyEqual(lastIdentifier, ...
                'referenceSystem:eulerSequenceFromRotation:gimbalLock');
            testCase.verifyEqual(info.lockCount, 1000);
            testCase.verifyTrue(all(info.gimbalLock));
        end

        function eulerSequenceFromRotation_diagnostics_lockedAnglesStillRebuildTheMatrix(testCase)
            % THIS TEST ASSERTS A WARNING, SO IT CONSUMES IT. The report lists
            % warnings nobody claimed, and an asserted warning is claimed.
            % Registered as a cleanup so it fires on pass, on failure and on a
            % filtered assumption alike. See WarningRecordingPlugin.
            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>
            % What is lost at gimbal lock is the SPLIT of the two coincident
            % rotations, not the rotation. The rebuilt matrix must be exact,
            % for every sequence and both singular values of the second angle.
            % This is the test that caught the inverted parity factor in the
            % Python cross-check, where the rebuild was wrong by 2.0.
            c = referenceSystem.attitudeConvention();
            worst = 0;
            rng(31);

            for sequenceName = TestRotationAlgebra.AllSequences
                c.sequence = sequenceName;
                letters = char(sequenceName);
                if letters(1) == letters(3)
                    singular = [0, pi];
                else
                    singular = [pi/2, -pi/2];
                end
                for second = singular
                    angles = [(rand(1, 20) - 0.5)*2*pi; ...
                        repmat(second, 1, 20); (rand(1, 20) - 0.5)*2*pi];
                    R = referenceSystem.rotationFromEulerSequence(angles, ...
                        'Convention', c);

                    warningState = warning('off', ...
                        'referenceSystem:eulerSequenceFromRotation:gimbalLock');
                    back = referenceSystem.eulerSequenceFromRotation(R, ...
                        'Convention', c);
                    warning(warningState);

                    rebuilt = referenceSystem.rotationFromEulerSequence(back, ...
                        'Convention', c);
                    worst = max(worst, max(abs(rebuilt - R), [], 'all'));
                end
            end

            testCase.verifyLessThan(worst, 1e-14, sprintf( ...
                'Gimbal-lock resolution must rebuild R exactly: %.3e', worst));
        end

        function eulerSequenceFromRotation_diagnostics_reportsTheConventionUsed(testCase)
            % NOT eye(3). THE IDENTITY IS AT GIMBAL LOCK FOR EVERY SYMMETRIC
            % SEQUENCE: the six proper-Euler sequences are singular where the
            % second angle is 0 or pi, and the identity has it at 0. It is only
            % safe for the six asymmetric ones, which are singular at +-pi/2.
            % So the most natural neutral test input in the whole family is
            % exactly the wrong one for half of it, and using it here made a
            % test that is about reporting emit a real gimbal-lock warning into
            % the suite output - noise that hides the warnings worth reading.
            c = referenceSystem.attitudeConvention();
            c.sequence = "XYX";
            R = referenceSystem.rotationFromEulerSequence([0.3; 0.9; -0.4], ...
                'Convention', c);

            [~, info] = referenceSystem.eulerSequenceFromRotation(R, ...
                'Convention', c);

            testCase.verifyEqual(info.convention.sequence, "XYX");
            testCase.verifyEqual(info.lockTolerance, 1e-7);
            testCase.verifyFalse(any(info.gimbalLock), ...
                'The chosen rotation must be clear of the singularity.');
        end

        function quaternionFromRotation_diagnostics_returnsItsConvention(testCase)
            [~, c] = referenceSystem.quaternionFromRotation(eye(3), ...
                'Convention', referenceSystem.attitudeConvention("aerospace"));

            testCase.verifyEqual(c.quaternion, "scalarLast");
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function rotationFromEulerSequence_vectorization_arrayEqualsLoop(testCase)
            rng(41);
            angles = (rand(3, 25) - 0.5)*2*pi;
            batch = referenceSystem.rotationFromEulerSequence(angles);

            for k = 1:size(angles, 2)
                single = referenceSystem.rotationFromEulerSequence(angles(:, k));
                % pagemtimes over 25 pages need not sum in the same order
                % as over one, so this is one ulp of an entry of order 1
                % rather than bit-identity. It passed as AbsTol 0 in the
                % S4 run; that was the blocking of the day, not a property.
                testCase.verifyEqual(batch(:, :, k), single, 'AbsTol', 1e-15, ...
                    sprintf('Page %d must agree with the scalar call.', k));
            end
        end

        function quaternionFromRotation_vectorization_arrayEqualsLoop(testCase)
            % AbsTol 0 is sound because Shepperd's method is elementwise per page, with no
            % reduction across pages (obligation O13).
            rng(43);
            R = referenceSystem.rotationFromEulerSequence((rand(3, 25) - 0.5)*2*pi);
            batch = referenceSystem.quaternionFromRotation(R);

            for k = 1:size(R, 3)
                single = referenceSystem.quaternionFromRotation(R(:, :, k));
                testCase.verifyEqual(batch(:, k), single, 'AbsTol', 0);
            end
        end

        function multiplyQuaternions_vectorization_singleOperandExpands(testCase)
            % 1e-15 rather than zero: one ulp of a unit component. The expanded operand is
            % broadcast rather than indexed, so bit identity is not claimed (obligation O13).
            rng(47);
            q = referenceSystem.quaternionFromRotation( ...
                referenceSystem.rotationFromEulerSequence((rand(3, 10) - 0.5)*2));
            single = TestRotationAlgebra.QuaternionA;

            expanded = referenceSystem.multiplyQuaternions(single, q);
            testCase.verifySize(expanded, [4 10]);

            for k = 1:10
                one = referenceSystem.multiplyQuaternions(single, q(:, k));
                testCase.verifyEqual(expanded(:, k), one, 'AbsTol', 1e-15);
            end
        end

        function rotationFromAxisAngle_vectorization_arrayEqualsLoop(testCase)
            % AbsTol 0 is sound because Rodrigues' formula is evaluated elementwise per page,
            % with no reduction across pages (obligation O13).
            rng(53);
            axis = rand(3, 20) - 0.5;
            angle = (rand(1, 20) - 0.5)*2*pi;
            batch = referenceSystem.rotationFromAxisAngle(axis, angle);

            for k = 1:20
                single = referenceSystem.rotationFromAxisAngle(axis(:, k), ...
                    angle(k));
                testCase.verifyEqual(batch(:, :, k), single, 'AbsTol', 0);
            end
        end

    end

    methods (Static, Access = private)

        function angles = safeAngles(sequenceName, nSample)
            %SAFEANGLES Random angle sets away from the sequence's singularity.
            %   The second angle is kept clear of gimbal lock, because the round
            %   trip of the first and third is undefined there by construction
            %   and is tested separately in the diagnostics block.
            first = (rand(1, nSample) - 0.5)*2*pi;
            third = (rand(1, nSample) - 0.5)*2*pi;
            letters = char(sequenceName);
            if letters(1) == letters(3)
                second = 0.05 + rand(1, nSample)*(pi - 0.1);
            else
                second = (rand(1, nSample) - 0.5)*(pi - 0.1);
            end
            angles = [first; second; third];
        end

    end

    methods (Test, TestTags = {'reference'})

        function rotationAlgebra_reference_matchesSpice(testCase)
            % R20's VENDOR CRITERION. Every other independent check in this
            % project runs in Python against a transcription of the MATLAB
            % source, so a misreading during transcription would agree with
            % itself. NAIF SPICE removes that link: JPL maintains it, it
            % documents its conventions explicitly, and it never saw this code.
            %
            % Filtered rather than failed where MICE is absent (risk R18).
            testCase.assumeTrue(exist('cspice_q2m', 'file') == 2 && ...
                exist('cspice_qxq', 'file') == 2 && ...
                exist('cspice_eul2m', 'file') == 2, ...
                'MICE is not on the path, so the vendor comparison is skipped.');

            rng(20260726);
            n = 500;
            q = randn(4, n);
            q = q./sqrt(sum(q.^2, 1));

            % (1) QUATERNION TO MATRIX. cspice_q2m returns the matrix that
            % ROTATES a vector; this toolbox returns the frame rotation, its
            % transpose. That transpose is the claim: get the sense backwards
            % and this fails by 2*sin(theta) off the diagonal. Vectorised -
            % MICE documents q as [4,n] and r as [3,3,n].
            testCase.verifyEqual(referenceSystem.rotationFromQuaternion(q), ...
                pagetranspose(cspice_q2m(q)), 'AbsTol', 1e-14, ...
                'Frame sense must be the transpose of the SPICE matrix.');

            % (2) BOTH PRODUCTS. NAIF states its formula in cspice_qxq as
            % s1*s2 - <v1,v2> + s1*v2 + s2*v1 + v1 x v2, which is Hamilton
            % scalar first. The Shuster product negates only the cross term,
            % and that is exactly Hamilton with the operands swapped:
            %     shuster(a, b) == hamilton(b, a)
            % verified algebraically and to 0.0 numerically before this test
            % was written. So ONE vendor routine covers BOTH conventions, and
            % the Shuster branch is no longer taken on trust.
            shuster = referenceSystem.attitudeConvention();
            shuster.product = "shuster";
            for k = 1:200
                a = q(:, k);
                b = q(:, k + 200);

                actual = referenceSystem.multiplyQuaternions(a, b);
                expected = cspice_qxq(a, b);
                if actual.'*expected < 0
                    expected = -expected;
                end
                testCase.verifyEqual(actual, expected, 'AbsTol', 1e-14, ...
                    'Hamilton product must match the SPICE product.');

                actual = referenceSystem.multiplyQuaternions(a, b, ...
                    'Convention', shuster);
                expected = cspice_qxq(b, a);
                if actual.'*expected < 0
                    expected = -expected;
                end
                testCase.verifyEqual(actual, expected, 'AbsTol', 1e-14, ...
                    'Shuster product is the SPICE product, operands swapped.');
            end

            % (3) ALL TWELVE SEQUENCES, BOTH ROTATION TYPES, BOTH SENSES.
            % cspice_eul2m(a3, a2, a1, x3, x2, x1) is documented as
            % [a3]_x3 [a2]_x2 [a1]_x1 with COORDINATE-system rotations, the
            % same elementary matrices rotationX, rotationY and rotationZ
            % produce. The toolbox's extrinsic form is A_i(a1) A_j(a2) A_k(a3),
            % and its intrinsic form is the reversal of both the sequence and
            % the angles, so the two bridges are
            %     extrinsic (i,j,k),(a1,a2,a3) -> eul2m(a1, a2, a3, i, j, k)
            %     intrinsic (i,j,k),(a1,a2,a3) -> eul2m(a3, a2, a1, k, j, i)
            % Both were checked to 0.0 against the elementary matrices before
            % this test existed. The vector sense is the transpose.
            % Uppercase: attitudeConvention permits "XYZ" and refuses "xyz",
            % which run 8 established by rejecting the lowercase form and
            % naming the twelve it accepts.
            sequenceList = ["XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX", ...
                "XYX", "XZX", "YXY", "YZY", "ZXZ", "ZYZ"];
            m = 200;
            angle = (rand(3, m) - 0.5)*3;

            for sequence = sequenceList
                % 'X'-'W' = 1, 'Y'-'W' = 2, 'Z'-'W' = 3.
                axis = int32(double(char(sequence)) - double('W'));
                for rotationType = ["extrinsic", "intrinsic"]
                    if strcmp(rotationType, "extrinsic")
                        expected = cspice_eul2m(angle(1, :), angle(2, :), ...
                            angle(3, :), axis(1), axis(2), axis(3));
                    else
                        expected = cspice_eul2m(angle(3, :), angle(2, :), ...
                            angle(1, :), axis(3), axis(2), axis(1));
                    end
                    for sense = ["frame", "vector"]
                        convention = referenceSystem.attitudeConvention();
                        convention.sequence = sequence;
                        convention.rotationType = rotationType;
                        convention.sense = sense;

                        actual = referenceSystem.rotationFromEulerSequence( ...
                            angle, 'Convention', convention);
                        target = expected;
                        if strcmp(sense, "vector")
                            target = pagetranspose(expected);
                        end

                        testCase.verifyEqual(actual, target, ...
                            'AbsTol', 1e-14, sprintf( ...
                            'Sequence %s, %s, %s sense.', sequence, ...
                            rotationType, sense));
                    end
                end
            end
        end

    end


    properties (Constant)
        % P17 reference literals for the rotation algebra, computed in Python
        % from the conventions the functions themselves document: extrinsic
        % (i,j,k) is A_i(a1) A_j(a2) A_k(a3) with A the FRAME rotations, and
        % intrinsic reverses both the sequence and the angles, so the toolbox
        % default of intrinsic ZYX with angles [yaw; pitch; roll] gives
        % R = rotationX(roll) rotationY(pitch) rotationZ(yaw).
        %
        % RISK R20 IS WHY THESE ARE LITERALS AND NOT COMPUTED IN THE TEST. Every
        % wrong sequence, sense or product yields a matrix that is orthogonal,
        % unit-determinant and round-trips through its own inverse, so a test
        % that builds its own expectation from the same misunderstanding passes.
        AttitudeYawPitchRoll = [0.4, -0.25, 0.8]

        AttitudeRotation = [ ...
             8.92427438242548998e-01,  3.77312269104819409e-01,  2.47403959254522937e-01; ...
            -4.34777271700163781e-01,  5.72596677486222894e-01,  6.95055227262338038e-01; ...
             1.20590179885442003e-01, -7.27851974315321115e-01,  6.75047784975616350e-01]

        % The quaternion of that rotation under the documented frame-sense map
        % R = (q0^2 - v'v) I + 2 v v' - 2 q0 [v]x, scalar first, q0 >= 0. It
        % reconstructs AttitudeRotation to 1.1e-16.
        AttitudeQuaternion = [ ...
             8.86012401254122950e-01; 4.01491897732914993e-01; ...
            -3.57821682827407367e-02; 2.29141697016739199e-01]

        AttitudeAxis = [ ...
             8.65915893434362594e-01; -7.71730348545661554e-02; ...
             4.94200352275375787e-01]
        AttitudeAngle = 9.642467167834398e-01
    end

    methods (Test, TestTags = {'contract'})

        function rotationY_contract_shapeAndRefusal(testCase)
            % rotationX and rotationZ had contract tests and rotationY did not,
            % which is the shape of gap a per-layer count cannot see.
            R = referenceSystem.rotationY([0.1; 0.2; 0.3]);

            testCase.verifySize(R, [3 3 3], 'One page per angle.');
            testCase.verifySize(referenceSystem.rotationY(0.1), [3 3], ...
                'A scalar angle returns a plain 3x3.');
            testCase.verifyError(@() referenceSystem.rotationY(ones(2, 2)), ...
                'referenceSystem:rotationY:wrongAngleSize');
        end

        function invertQuaternion_contract_shapeAndRefusals(testCase)
            q = referenceSystem.invertQuaternion( ...
                TestRotationAlgebra.AttitudeQuaternion);

            testCase.verifySize(q, [4 1], 'One inverse per quaternion.');
            testCase.verifyError(@() referenceSystem.invertQuaternion([1; 0; 0]), ...
                'referenceSystem:invertQuaternion:wrongQuaternionSize');
            testCase.verifyError(@() referenceSystem.invertQuaternion(zeros(4, 1)), ...
                'referenceSystem:invertQuaternion:zeroQuaternion');
        end

        function normalizeQuaternion_contract_shapeAndRefusals(testCase)
            q = referenceSystem.normalizeQuaternion([1; 1; 1; 1]);

            testCase.verifySize(q, [4 1], 'One normalised quaternion per input.');
            testCase.verifyError(@() referenceSystem.normalizeQuaternion([1; 0; 0]), ...
                'referenceSystem:normalizeQuaternion:wrongQuaternionSize');
            testCase.verifyError(@() referenceSystem.normalizeQuaternion(zeros(4, 2)), ...
                'referenceSystem:normalizeQuaternion:zeroQuaternion');
        end

        function quaternionFromEulerSequence_contract_shapeAndRefusals(testCase)
            angles = TestRotationAlgebra.AttitudeYawPitchRoll';

            q = referenceSystem.quaternionFromEulerSequence([angles, angles]);

            testCase.verifySize(q, [4 2], 'One quaternion per angle triple.');
            testCase.verifyError(@() referenceSystem.quaternionFromEulerSequence( ...
                [0.1; 0.2]), ...
                'referenceSystem:quaternionFromEulerSequence:wrongAngleSize');
        end

        function eulerSequenceFromQuaternion_contract_shapeAndRefusal(testCase)
            angles = referenceSystem.eulerSequenceFromQuaternion( ...
                TestRotationAlgebra.AttitudeQuaternion);

            testCase.verifySize(angles, [3 1], 'One angle triple per quaternion.');
            testCase.verifyError(@() referenceSystem.eulerSequenceFromQuaternion( ...
                [1; 0; 0]), ...
                'referenceSystem:eulerSequenceFromQuaternion:wrongQuaternionSize');
        end

        function eulerSequenceFromRotation_contract_shapeAndRefusal(testCase)
            [angles, info] = referenceSystem.eulerSequenceFromRotation( ...
                TestRotationAlgebra.AttitudeRotation);

            testCase.verifySize(angles, [3 1], 'One angle triple per page.');
            testCase.verifyFalse(any(info.gimbalLock), ...
                'A generic rotation was reported as singular.');
            testCase.verifyError(@() referenceSystem.eulerSequenceFromRotation( ...
                eye(2)), ...
                'referenceSystem:eulerSequenceFromRotation:wrongMatrixSize');
        end

        function rollPitchYawFromRotation_contract_shapeAndRefusal(testCase)
            rollPitchYaw = referenceSystem.rollPitchYawFromRotation( ...
                TestRotationAlgebra.AttitudeRotation);

            testCase.verifySize(rollPitchYaw, [3 1], 'One triple per page.');
            testCase.verifyError(@() referenceSystem.rollPitchYawFromRotation( ...
                eye(2)), ...
                'referenceSystem:rollPitchYawFromRotation:wrongMatrixSize');
        end

    end

    methods (Test, TestTags = {'reference'})

        function quaternionFromEulerSequence_reference_matchesTheIndependentMap(testCase)
            % The angle triple is intrinsic ZYX [yaw; pitch; roll]; the expected
            % quaternion was obtained in Python by building the matrix from the
            % elementary FRAME rotations and reading the quaternion out of it,
            % then checked by reconstructing the matrix to 1.1e-16.
            q = referenceSystem.quaternionFromEulerSequence( ...
                TestRotationAlgebra.AttitudeYawPitchRoll');

            % 1e-15 is a few ulp of a unit quaternion: the components are
            % products of half-angle sines and cosines of order unity, so this
            % bounds floating-point rounding through three factors.
            testCase.verifyEqual(q, TestRotationAlgebra.AttitudeQuaternion, ...
                'AbsTol', 1e-15, ...
                'The Euler-to-quaternion map differs from the independent one.');
        end

        function eulerSequenceFromQuaternion_reference_recoversTheAngles(testCase)
            % The other direction, from the same independently built pair. A
            % round trip through the toolbox alone would pass with a consistently
            % wrong sequence; starting from a quaternion computed outside it
            % cannot (risk R20).
            angles = referenceSystem.eulerSequenceFromQuaternion( ...
                TestRotationAlgebra.AttitudeQuaternion);

            % 1e-14 rad bounds an atan2 and an asin of quantities of order
            % unity accumulated through the quaternion, that is a few ulp of an
            % angle near 1 rad. Nothing physical enters.
            testCase.verifyEqual(angles, ...
                TestRotationAlgebra.AttitudeYawPitchRoll', 'AbsTol', 1e-14, ...
                'The quaternion-to-Euler map does not recover the angles.');
        end

        function eulerSequenceFromRotation_reference_recoversTheAngles(testCase)
            angles = referenceSystem.eulerSequenceFromRotation( ...
                TestRotationAlgebra.AttitudeRotation);

            % As above: a few ulp of an angle of order unity through an atan2.
            testCase.verifyEqual(angles, ...
                TestRotationAlgebra.AttitudeYawPitchRoll', 'AbsTol', 1e-14, ...
                'The matrix-to-Euler map does not recover the angles.');
        end

        function rollPitchYawFromRotation_reference_ordersRollFirst(testCase)
            % THE ROW ORDER IS THE CLAIM. rollPitchYawFromRotation returns
            % [roll; pitch; yaw] while eulerSequenceFromRotation returns the
            % angles in the order the sequence names its axes, which for ZYX is
            % [yaw; pitch; roll]. The two are the same three numbers reversed,
            % and a caller who assumes otherwise flies 0.4 rad off heading.
            expected = flipud(TestRotationAlgebra.AttitudeYawPitchRoll');

            rollPitchYaw = referenceSystem.rollPitchYawFromRotation( ...
                TestRotationAlgebra.AttitudeRotation);

            % A few ulp of an angle of order unity through an atan2.
            testCase.verifyEqual(rollPitchYaw, expected, 'AbsTol', 1e-14, ...
                'Roll, pitch and yaw are not in the documented row order.');
        end

        function invertQuaternion_reference_isTheConjugate(testCase)
            % The inverse of a unit quaternion is its conjugate, so the expected
            % value is the input with three signs flipped. The scalar part here
            % is positive, so the documented q0 >= 0 canonicalisation leaves it
            % alone.
            %
            % NOT EXACT, AND THE FIRST RUN SAID SO. invertQuaternion
            % NORMALISES ON ENTRY rather than assuming a unit input, which is
            % right - a quaternion of norm 1+e gives a matrix scaled by
            % (1+e)^2 - and the stored literal has norm 1 - 1.1e-16. So there
            % is a division between input and output and AbsTol 0 was a claim
            % about a computation that does not happen. 1e-15 is a few ulp of a
            % unit component.
            q = TestRotationAlgebra.AttitudeQuaternion;
            expected = [q(1); -q(2); -q(3); -q(4)];

            inverse = referenceSystem.invertQuaternion(q);

            testCase.verifyEqual(inverse, expected, 'AbsTol', 1e-15, ...
                'The quaternion inverse is not the conjugate.');
        end

        function normalizeQuaternion_reference_matchesTheIndependentNormalisation(testCase)
            % A quaternion that is both off the unit sphere and in the wrong
            % half of it, so the test drives BOTH jobs the function does. The
            % expected value was computed in Python: divide by the norm, then
            % negate because the scalar part is negative.
            raw = [-0.822; 0.274; -0.411; 0.685];
            expected = [ ...
                 6.97485832462915734e-01; -2.32495277487638569e-01; ...
                 3.48742916231457867e-01; -5.81238193719096463e-01];

            q = referenceSystem.normalizeQuaternion(raw);

            % 1e-15, not 1e-16: eps(0.697) is 1.1e-16, so a bound of 1e-16 is
            % BELOW ONE ULP of the largest component and unreachable however
            % correct the function is. That is the trap revision 1.61 recorded
            % and this is its fourth appearance. 1e-15 is a few ulp of a
            % unit-norm component through a division by a square root of a sum
            % of four squares.
            testCase.verifyEqual(q, expected, 'AbsTol', 1e-15, ...
                'The normalisation differs from the independent one.');
        end

        function axisAngleFromRotation_reference_matchesTheIndependentAxis(testCase)
            % Axis and angle of the same independently built rotation, from
            % R = I cos t + (1 - cos t) a a' - sin t [a]x. The axis is checked
            % rather than only the angle: the angle alone is recovered correctly
            % by a transposed matrix as well, and the axis is not.
            [axis, angle] = referenceSystem.axisAngleFromRotation( ...
                TestRotationAlgebra.AttitudeRotation);

            % 1e-15 on a unit vector and 1e-15 rad on an angle near 0.96 rad:
            % both are a few ulp of quantities of order unity, obtained from an
            % arccos and a division by 2 sin(t) well away from the singular
            % t = 0 and t = pi.
            testCase.verifyEqual(axis, TestRotationAlgebra.AttitudeAxis, ...
                'AbsTol', 1e-15, 'The rotation axis differs from the independent one.');
            testCase.verifyEqual(angle, TestRotationAlgebra.AttitudeAngle, ...
                'AbsTol', 1e-15, 'The rotation angle differs from the independent one.');
        end

    end

    methods (Test, TestTags = {'precision'})

        function rotationX_precision_elementaryRotationsAreOrthogonal(testCase)
            % One test for all three elementary rotations, driven over a full
            % turn including the quadrant boundaries where a sign convention
            % that is wrong in one quadrant shows. Named for rotationX because a
            % method has to be named for something; it exercises all three.
            angle = linspace(-pi, pi, 73)';
            R = cat(3, referenceSystem.rotationX(angle), ...
                referenceSystem.rotationY(angle), referenceSystem.rotationZ(angle));

            residual = pagemtimes(R, 'transpose', R, 'none') - eye(3);
            determinant = arrayfun(@(k) det(R(:, :, k)), 1:size(R, 3));

            % 1e-15 is a few ulp of a three-term dot product of sines and
            % cosines of order unity; it bounds floating-point summation.
            testCase.verifyLessThan(max(abs(residual), [], 'all'), 1e-15, ...
                'An elementary rotation is not orthogonal.');
            % Same basis: a determinant is a sum of six triple products of
            % numbers of order unity. A PROPER rotation is the claim - an
            % improper one would be a reflection and would still be orthogonal.
            testCase.verifyEqual(determinant, ones(1, size(R, 3)), 'AbsTol', 1e-15, ...
                'An elementary rotation is not proper.');
        end

        function rotationZ_precision_composesAdditively(testCase)
            % Rotations about ONE axis form a one-parameter group, so
            % A(s) A(t) = A(s + t) exactly in exact arithmetic. This catches a
            % sign error in a way orthogonality cannot: a transposed elementary
            % rotation is still orthogonal and still proper, but composes as
            % A(-s) A(-t) and fails here.
            s = 0.37;
            t = -1.14;

            product = referenceSystem.rotationZ(s) * referenceSystem.rotationZ(t);

            % 1e-15 is a few ulp of a two-term dot product of numbers of order
            % unity, plus the rounding of the angle sum itself.
            testCase.verifyEqual(product, referenceSystem.rotationZ(s + t), ...
                'AbsTol', 1e-15, ...
                'Rotations about z do not compose by adding their angles.');
        end

    end

    methods (Test, TestTags = {'speed'})

        function rotationFromQuaternion_speed_oneMillionPages(testCase)
            % LAYER L4b HAD NO BENCHMARK AT ALL, although it is on the hot path
            % of every attitude workload: a GRACE-like reprocessing turns a
            % 1 Hz star camera series into matrices, which is 86 400 pages a day
            % and a million pages in under a fortnight of data.
            %
            % 0.30 s, TIGHTENED FROM THE 0.5 s PREDICTED IN REV. 1.73 (risk
            % R17). Measured 0.148 s on PCWIN64 and 0.066 s on GLNXA64, so the
            % prediction was pessimistic by 3.4x on the slower of the two.
            % THE RULE, so the next revision does not reinvent it: twice the
            % slowest host measured, rounded up. The hard failure stays at five
            % times the target, which puts it at ten times the slowest
            % measurement - a real regression detector rather than a flaky one.
            targetSeconds = 0.30;
            angle = linspace(0, 2 * pi, 1000000);
            q = referenceSystem.normalizeQuaternion([cos(angle / 2); ...
                sin(angle / 2) * 0.3; sin(angle / 2) * 0.5; sin(angle / 2) * 0.8]);

            medianSeconds = TestPerformance.medianDuration(@() ...
                referenceSystem.rotationFromQuaternion(q), 3);

            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("rotationFromQuaternion", 1000000, ...
                medianSeconds, targetSeconds));
            if medianSeconds > targetSeconds
                warning('referenceSystem:test:slowerThanTarget', ...
                    'rotationFromQuaternion took %.3f s against a %.3f s target.', ...
                    medianSeconds, targetSeconds);
            end
            testCase.verifyLessThan(medianSeconds, 5 * targetSeconds);
        end

    end

end
