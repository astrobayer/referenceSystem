classdef TestNavigation < matlab.unittest.TestCase
%TESTNAVIGATION Layer L5 test suite — navigation frames and strapdown kinematics.
%
%   Covers P26: rotationNavToBody, angularVelocityToRotationRate,
%   angularVelocityFromRotationRate, integrateAttitude and
%   wanderAzimuthRotation.
%
%   Risk R21 governs integrateAttitude: the closed-form coning case is run over
%   ten thousand steps, because a ten-step test looks perfect for an
%   implementation that drifts. The coning truth is analytic on BOTH sides -
%   the rate and the attitude each have a closed form - so this is a reference
%   test with real truth and not a comparison of the two methods against each
%   other, which could share a convention error (seam item 7).
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 23:20 (CEST, UTC+02:00) - session S5, prompt P26
% -------------------------------------------------------------------------

    properties (Constant)
        % Half-cone angle and cone rate of the closed-form coning case.
        ConeAngle = deg2rad(3)
        ConeRate = 2*pi/4
    end

    methods (Test, TestTags = {'contract'})

        function rotationNavToBody_contract_requiresTheConvention(testCase)
            % Decision D36 and the P26 instruction: ENU and NED give the same
            % three angles two different meanings and both produce a valid
            % rotation, so there is nothing at runtime to catch a wrong
            % default. The option therefore has none.
            testCase.verifyError(@() referenceSystem.rotationNavToBody( ...
                [0.1; 0.2; 0.3]), ...
                'referenceSystem:rotationNavToBody:conventionRequired');
        end

        function rotationNavToBody_contract_refusesAnAbsentLocalFrame(testCase)
            convention = referenceSystem.attitudeConvention();
            convention.localFrame = "none";
            testCase.verifyError(@() referenceSystem.rotationNavToBody( ...
                [0.1; 0.2; 0.3], 'Convention', convention), ...
                'referenceSystem:rotationNavToBody:localFrameRequired');
        end

        function rotationNavToBody_contract_namesTheFramesItJoins(testCase)
            [R, info] = referenceSystem.rotationNavToBody([0.1; 0.2; 0.3], ...
                'Convention', referenceSystem.attitudeConvention("geodetic"));

            testCase.verifySize(R, [3 3 1]);
            testCase.verifyEqual(info.fromFrame, "NAV");
            testCase.verifyEqual(info.toFrame, "BODY");
            testCase.verifyEqual(info.localFrame, "ENU");
            testCase.verifyEqual(info.angleOrder, ["roll", "pitch", "yaw"]);
        end

        function rotationNavToBody_contract_enuAndNedDifferOnceReferred(testCase)
            % RUN 2 CORRECTED THIS TEST, NOT THE CODE. It previously asserted
            % that the two conventions return different MATRICES, and a change
            % made to satisfy it broke the hand-computed ENU literal below -
            % which is the plain ZYX composition and was right all along.
            %
            % The arrays are equal and must be: both are R(nav->body) with nav
            % meaning the caller's own local frame, so the same three angles
            % give the same components about axes 3, 2 and 1. What differs is
            % what those axes ARE, and that is not visible until both are
            % referred to a common frame - which is the real content of the
            % convention and what is asserted here.
            angles = [0.1; 0.2; 0.3];
            origin = [0.9075712110370513 0.22689280275926285 100];

            enu = referenceSystem.rotationNavToBody(angles, 'Convention', ...
                referenceSystem.attitudeConvention("geodetic"));
            ned = referenceSystem.rotationNavToBody(angles, 'Convention', ...
                referenceSystem.attitudeConvention("aerospace"));

            testCase.verifyEqual(enu, ned, 'AbsTol', 0, ...
                'Same angles about the same axis indices are the same array.');

            % Referred to ECEF they are different physical attitudes, and the
            % convention is therefore load-bearing rather than decoration.
            viaEnu = enu*referenceSystem.rotationEcefToEnu(origin);
            viaNed = ned*referenceSystem.rotationEcefToNed(origin);
            testCase.verifyGreaterThan(max(abs(viaEnu - viaNed), [], 'all'), 0.1, ...
                'The local frame must change the ECEF-referred attitude.');
        end

        function angularVelocityToRotationRate_contract_rejectsARowLayout(testCase)
            R = eye(3);
            testCase.verifyError(@() ...
                referenceSystem.angularVelocityToRotationRate(R, [1 2 3]), ...
                'referenceSystem:angularVelocityToRotationRate:wrongVelocitySize');
        end

        function angularVelocityToRotationRate_contract_rejectsMismatch(testCase)
            testCase.verifyError(@() ...
                referenceSystem.angularVelocityToRotationRate( ...
                repmat(eye(3), 1, 1, 3), zeros(3, 2)), ...
                'referenceSystem:angularVelocityToRotationRate:sizeMismatch');
        end

        function integrateAttitude_contract_refusesASingleSample(testCase)
            epoch = referenceSystem.daySecondToEpoch([60000 0], "TAI");
            testCase.verifyError(@() referenceSystem.integrateAttitude( ...
                [1; 0; 0; 0], [0.1; 0; 0], epoch), ...
                'referenceSystem:integrateAttitude:tooFewSamples');
        end

        function integrateAttitude_contract_refusesACountMismatch(testCase)
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(60000, 3, 1), (0:2).'], "TAI");
            testCase.verifyError(@() referenceSystem.integrateAttitude( ...
                [1; 0; 0; 0], zeros(3, 5), epoch), ...
                'referenceSystem:integrateAttitude:sizeMismatch');
        end

        function wanderAzimuthRotation_contract_doesNotDegenerateAtThePole(testCase)
            % THE ONLY REASON TO CHOOSE THIS MECHANISATION. A north-slaved
            % local-level frame needs a vertical transport rate proportional to
            % tan(latitude), which diverges at the pole; the wander frame's is
            % zero by construction, so the rotation and the rates stay finite
            % where the north-slaved ones cannot.
            origin = [90 0 0; 89.999 0 0];
            [R, rates, info] = referenceSystem.wanderAzimuthRotation( ...
                origin, 30, 'Velocity', [100 0; 100 0], 'AngleUnit', "deg");

            testCase.verifyTrue(all(isfinite(R), 'all'), ...
                'The rotation must stay finite at the pole.');
            testCase.verifyTrue(all(isfinite(rates.earth), 'all'));
            testCase.verifyEqual(rates.transport(3, :), [0 0], 'AbsTol', 0, ...
                'The wander frame has NO vertical transport rate, by design.');
            % The quantity it avoids is reported, and at 89.999 degrees it is
            % already enormous - which is the measurement that justifies the
            % mechanisation rather than a claim about it.
            testCase.verifyGreaterThan(abs(info.northSlavedVertical(2)), 0.1, ...
                'The north-slaved term must be shown to be large here.');
        end

        function wanderAzimuthRotation_contract_refusesAnAbsentLocalFrame(testCase)
            convention = referenceSystem.attitudeConvention();
            convention.localFrame = "none";
            testCase.verifyError(@() referenceSystem.wanderAzimuthRotation( ...
                [52 13 0], 0, 'AngleUnit', "deg", 'Convention', convention), ...
                'referenceSystem:wanderAzimuthRotation:localFrameRequired');
        end

        function wanderAzimuthRotation_contract_rejectsAWrongOriginSize(testCase)
            testCase.verifyError(@() referenceSystem.wanderAzimuthRotation( ...
                [52; 13; 0], 0), ...
                'referenceSystem:wanderAzimuthRotation:wrongOriginSize');
        end

    end

    methods (Test, TestTags = {'reference'})

        function rotationNavToBody_reference_matchesTheHandComputedCase(testCase)
            % Roll 10, pitch 20, yaw 30 degrees, intrinsic ZYX, frame sense.
            % Literal computed in Python as Rx(roll)*Ry(pitch)*Rz(yaw) with the
            % elementary matrices written out, never through this toolbox.
            expected = [ ...
                0.8137976813493738, 0.46984631039295416, -0.34202014332566871; ...
                -0.44096961052988237, 0.8825641192593856, 0.16317591116653482; ...
                0.37852230636979245, 0.018028311236297258, 0.92541657839832336];

            R = referenceSystem.rotationNavToBody([10; 20; 30], ...
                'AngleUnit', "deg", 'Convention', ...
                referenceSystem.attitudeConvention("geodetic"));

            testCase.verifyEqual(R, expected, 'AbsTol', 1e-15);
        end

        function angularVelocityToRotationRate_reference_matchesTheLiteral(testCase)
            % q = [1 1 1 1]/2 is the cyclic permutation matrix, so R and Rdot
            % are both exactly representable and the literal is checkable by
            % hand: Rdot = -skew(omega)*R.
            q = [0.5; 0.5; 0.5; 0.5];
            R = referenceSystem.rotationFromQuaternion(q);
            omega = [0.01; -0.02; 0.03];

            expected = [0.02, 0, 0.03; 0.01, -0.03, 0; 0, -0.02, -0.01];

            Rdot = referenceSystem.angularVelocityToRotationRate(R, omega);

            testCase.verifyEqual(R, [0 1 0; 0 0 1; 1 0 0], 'AbsTol', 1e-15, ...
                'The chosen quaternion is the cyclic permutation.');
            testCase.verifyEqual(Rdot, expected, 'AbsTol', 1e-17);
        end

        function wanderAzimuthRotation_reference_earthRateAtEquatorAndPole(testCase)
            % Hand-computable: the Earth rotation vector points along the spin
            % axis, so in ENU it is (0, w cos(lat), w sin(lat)) - due north at
            % the equator and straight up at the pole.
            omegaEarth = referenceSystem.iersConstants().earthRotationRate;

            [~, equator] = referenceSystem.wanderAzimuthRotation( ...
                [0 0 0], 0, 'AngleUnit', "deg");
            [~, pole] = referenceSystem.wanderAzimuthRotation( ...
                [90 0 0], 0, 'AngleUnit', "deg");

            testCase.verifyEqual(equator.earth, [0; omegaEarth; 0], ...
                'AbsTol', 1e-20, 'At the equator the Earth rate is due north.');
            testCase.verifyEqual(pole.earth, [0; 0; omegaEarth], ...
                'AbsTol', 1e-20, 'At the pole it is straight up.');
        end

        function wanderAzimuthRotation_reference_matchesTheIndependentCase(testCase)
            % 52 N, 13 E, 100 m, wander 37 degrees, 200 m/s east and 150 north.
            % Every literal computed in Python from the ellipsoid parameters
            % and the curvature formulae, not from this function.
            [R, rates, info] = referenceSystem.wanderAzimuthRotation( ...
                [52 13 100], 37, 'Velocity', [200 150], 'AngleUnit', "deg");

            testCase.verifyEqual(info.primeVerticalRadius, ...
                6391535.2682765769, 'RelTol', 1e-14);
            testCase.verifyEqual(info.meridianRadius, ...
                6375249.7412608815, 'RelTol', 1e-14);
            testCase.verifyEqual(rates.earth, ...
                [2.7018330672437899e-05; 3.5854535807686603e-05; ...
                5.7462650365368818e-05], 'RelTol', 1e-13);
            testCase.verifyEqual(rates.transport, ...
                [4.0938813782349697e-08; 3.9150211140932262e-05; 0], ...
                'AbsTol', 1e-18);
            testCase.verifyEqual(rates.wanderAngleRate, ...
                -4.0051148228685409e-05, 'RelTol', 1e-13);

            expected = [ ...
                -0.64173595379561754, 0.67148648575817493, 0.37051432502693527; ...
                -0.47782467264651773, -0.72795974824178811, 0.49168911636317592; ...
                0.5998821115988352, 0.13849369799340627, 0.78801075360672201];
            testCase.verifyEqual(R, expected, 'AbsTol', 1e-14);
        end

        function integrateAttitude_reference_closedFormConing(testCase)
            % SEAM ITEM 7 and risk R21. The rotation vector traces a circle of
            % radius beta at rate Omega, so the attitude AND the body rate both
            % have closed forms:
            %   q(t)     = [cos(b/2); sin(b/2)cos(Wt); sin(b/2)sin(Wt); 0]
            %   omega(t) = W[-sin(b)sin(Wt); sin(b)cos(Wt); -(1-cos b)]
            % The constant third component is the classical coning drift, which
            % is exactly what a naive integrator turns into a growing error.
            [omega, epoch, truth, tEnd] = TestNavigation.coningCase(0.01, 10000);

            [q, info] = referenceSystem.integrateAttitude(truth(:, 1), ...
                omega, epoch);
            corrected = TestNavigation.angleBetween(q(:, end), truth(:, end));

            testCase.verifyEqual(info.stepCount, 10000);
            testCase.verifyTrue(info.coningCorrection);
            testCase.verifyLessThan(corrected, 1.2e-5, sprintf( ...
                ['Coning-corrected error after %g s of 3 degree coning: ', ...
                '%.4e rad. The independent Python mirror gives 8.846e-06.'], ...
                tEnd, corrected));
        end

        function integrateAttitude_reference_theConingTermEarnsItsPlace(testCase)
            % Obligation O8 applied before quoting a figure: the residual has
            % TWO sources, the non-commutativity that the coning term removes
            % and the trapezoidal quadrature of omega between samples that it
            % cannot. For this motion the two happen to be equal, so dropping
            % the term doubles the error - not the orders of magnitude the
            % method's reputation suggests. Assert the measured factor.
            [omega, epoch, truth, ~] = TestNavigation.coningCase(0.01, 10000);

            with = referenceSystem.integrateAttitude(truth(:, 1), omega, epoch);
            without = referenceSystem.integrateAttitude(truth(:, 1), omega, ...
                epoch, 'ConingCorrection', false);

            errorWith = TestNavigation.angleBetween(with(:, end), truth(:, end));
            errorWithout = TestNavigation.angleBetween(without(:, end), ...
                truth(:, end));

            testCase.verifyEqual(errorWithout/errorWith, 2.0, 'RelTol', 0.05, ...
                sprintf(['Dropping the coning term must double the error ', ...
                'on this case: with %.4e, without %.4e.'], errorWith, ...
                errorWithout));
        end

    end

    methods (Test, TestTags = {'precision'})

        function angularVelocityToRotationRate_precision_roundTrip(testCase)
            % omega -> Rdot -> omega, over random attitudes and rates, in both
            % resolutions. The recovery goes through a matrix product and a
            % skew extraction, so a few ulp of the rate magnitude is the bound.
            rng(1009);
            n = 200;
            q = randn(4, n);
            R = referenceSystem.rotationFromQuaternion(q);
            omega = (rand(3, n) - 0.5)*0.2;

            for resolution = ["body", "reference"]
                Rdot = referenceSystem.angularVelocityToRotationRate(R, ...
                    omega, 'Resolution', resolution);
                recovered = referenceSystem.angularVelocityFromRotationRate( ...
                    R, Rdot, 'Resolution', resolution);
                % Bound: |omega| ~ 0.1 and eps(0.1) = 1.4e-17, so a round trip
                % through two 3x3 products cannot close below one ulp of the
                % quantity itself. The 1e-17 asserted before run 1 was BELOW
                % one ulp - a tolerance nothing could satisfy.
                testCase.verifyEqual(recovered, omega, 'AbsTol', 1e-15, ...
                    "Round trip in the " + resolution + " resolution");
            end
        end

        function angularVelocityToRotationRate_precision_skewInvariant(testCase)
            % SEAM ITEM 6. The same invariant TestRotation asserts on
            % rotationItrsToGcrs: R is orthogonal at every instant, so
            % differentiating R'R = I gives Rdot'R + R'Rdot = 0 identically.
            % It is the cheapest available check that omega is resolved in the
            % frame the help text claims - a rate built in the wrong frame
            % breaks it immediately.
            rng(1013);
            n = 150;
            R = referenceSystem.rotationFromQuaternion(randn(4, n));
            omega = (rand(3, n) - 0.5)*0.2;

            for resolution = ["body", "reference"]
                Rdot = referenceSystem.angularVelocityToRotationRate(R, ...
                    omega, 'Resolution', resolution);
                residual = TestPerformance.rotationRateSkewResidual(R, Rdot);
                % Same bound, same reason: the residual cancels terms of order
                % |omega| ~ 0.1, so a few ulp of 0.1 is the floor.
                testCase.verifyLessThan(max(abs(residual), [], 'all'), 1e-15, ...
                    "Skew invariant in the " + resolution + " resolution");
            end
        end

        function angularVelocityToRotationRate_precision_quaternionAgrees(testCase)
            % The matrix rate and the quaternion rate must describe the same
            % motion. Differentiating R(q(t)) by the chain rule is awkward, so
            % the check is done the other way: advance q by qdot over a tiny
            % step, advance R by Rdot over the same step, and compare.
            rng(1019);
            q = referenceSystem.normalizeQuaternion(randn(4, 1));
            R = referenceSystem.rotationFromQuaternion(q);
            omega = [0.013; -0.021; 0.007];
            step = 1e-7;

            [Rdot, qdot] = referenceSystem.angularVelocityToRotationRate(R, ...
                omega);
            advancedR = R + step*Rdot;
            advancedQ = referenceSystem.rotationFromQuaternion(q + step*qdot);

            testCase.verifyLessThan(max(abs(advancedR - advancedQ), [], 'all'), ...
                1e-13, ...
                'The matrix rate and the quaternion rate must agree to O(step^2).');
        end

        function integrateAttitude_precision_constantRateOverTenThousand(testCase)
            % A constant rate makes the coning term vanish identically
            % (omega x omega = 0) and the exact answer is a single rotation
            % about omega through |omega|*T. Over 10^4 steps the only error is
            % rounding, so this is the tightest available check on the
            % exponential and the composition.
            rate = [0.011; -0.023; 0.017];
            stepCount = 10000;
            interval = 0.01;
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(60000, stepCount+1, 1), ...
                (0:stepCount).'*interval], "TAI");
            omega = repmat(rate, 1, stepCount+1);

            q = referenceSystem.integrateAttitude([1; 0; 0; 0], omega, epoch);

            total = norm(rate)*interval*stepCount;
            exact = [cos(total/2); rate/norm(rate)*sin(total/2)];
            testCase.verifyEqual(q(:, end), exact, 'AbsTol', 1e-13, ...
                'Constant-rate propagation is exact up to rounding.');
        end

        function integrateAttitude_precision_stepsAreUnitAndContinuous(testCase)
            % The output contract promises unit norm and sign continuity. The
            % canonical q0 >= 0 form is deliberately NOT imposed, so a series
            % passing through 180 degrees must not jump.
            [omega, epoch, truth, ~] = TestNavigation.coningCase(0.05, 400);
            q = referenceSystem.integrateAttitude(truth(:, 1), omega, epoch);

            testCase.verifyEqual(sqrt(sum(q.^2, 1)), ...
                ones(1, size(q, 2)), 'AbsTol', 1e-14);
            testCase.verifyGreaterThan(min(sum(q(:, 2:end).*q(:, 1:end-1), 1)), ...
                0, 'No step may reverse the sign of the series.');
        end

        function integrateAttitude_precision_bothMethodsAreSampleLimited(testCase)
            % Comparing the two methods is a cross-check and NOT a substitute
            % for the closed-form test (seam item 7). What it establishes is
            % the finding recorded in the ACCURACY block: with two rate samples
            % per interval both methods are limited by the reconstruction of
            % omega between them, not by the attitude integrator, so RK4 buys
            % nothing here. If they ever diverge, one of them has changed.
            [omega, epoch, truth, ~] = TestNavigation.coningCase(0.01, 4000);

            rotationVector = referenceSystem.integrateAttitude(truth(:, 1), ...
                omega, epoch, 'Method', "rotationVector");
            rungeKutta = referenceSystem.integrateAttitude(truth(:, 1), ...
                omega, epoch, 'Method', "quaternionRk4");

            separation = TestNavigation.angleBetween(rotationVector(:, end), ...
                rungeKutta(:, end));
            % 1e-11 rad. THE OLD BOUND WAS 1e-9 AND IT COULD NOT FAIL: the
            % acos metric it was asserted against returned exactly 0 for
            % anything under 2e-08. With the metric repaired the two methods
            % are measured 5e-14 apart in the mirror, so this discriminates by
            % three orders instead of by none. The 5e-11 quoted in
            % integrateAttitude's ACCURACY block predates the repair and should
            % be re-measured from a run rather than from here.
            testCase.verifyLessThan(separation, 1e-11, sprintf( ...
                ['The two methods must agree to far better than either ', ...
                'agrees with the truth; they differ by %.3e rad.'], separation));
        end

        function wanderAzimuthRotation_precision_rotationIsOrthonormal(testCase)
            rng(1021);
            n = 60;
            origin = [(rand(n, 1) - 0.5)*178, (rand(n, 1) - 0.5)*360, ...
                rand(n, 1)*1000];
            angle = (rand(n, 1) - 0.5)*360;

            R = referenceSystem.wanderAzimuthRotation(origin, angle, ...
                'AngleUnit', "deg");
            residual = pagemtimes(R, 'transpose', R, 'none') - eye(3);

            testCase.verifyLessThan(max(abs(residual), [], 'all'), 1e-14);
        end

        function wanderAzimuthRotation_precision_zeroAngleIsTheLocalLevel(testCase)
            % A wander angle of zero must reproduce the plain local-level
            % rotation exactly, in both local frames. That pins the sign of
            % the wander rotation against L4, which is the only place it can
            % be checked without repeating the arithmetic.
            origin = [52 13 100; -33 151 0];

            enu = referenceSystem.wanderAzimuthRotation(origin, 0, ...
                'AngleUnit', "deg");
            testCase.verifyEqual(enu, ...
                referenceSystem.rotationEcefToEnu(origin(:, 1:2), ...
                'AngleUnit', "deg"), 'AbsTol', 1e-15);

            ned = referenceSystem.wanderAzimuthRotation(origin, 0, ...
                'AngleUnit', "deg", 'Convention', ...
                referenceSystem.attitudeConvention("aerospace"));
            testCase.verifyEqual(ned, ...
                referenceSystem.rotationEcefToNed(origin(:, 1:2), ...
                'AngleUnit', "deg"), 'AbsTol', 1e-15);
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function angularVelocityToRotationRate_vectorization_batchEqualsLoop(testCase)
            rng(1031);
            n = 30;
            R = referenceSystem.rotationFromQuaternion(randn(4, n));
            omega = (rand(3, n) - 0.5)*0.2;

            batch = referenceSystem.angularVelocityToRotationRate(R, omega);
            for k = 1:n
                single = referenceSystem.angularVelocityToRotationRate( ...
                    R(:, :, k), omega(:, k));
                % Obligation O13: this goes through pagemtimes, so bit
                % identity is a claim about BLAS blocking and not about the
                % function. One ulp of the operand magnitude instead.
                testCase.verifyEqual(batch(:, :, k), single, ...
                    'AbsTol', eps(max(abs(omega(:, k)))), ...
                    sprintf('Page %d differs between batch and single.', k));
            end
        end

        function wanderAzimuthRotation_vectorization_batchEqualsLoop(testCase)
            % 1e-15 is a few ulp of a rotation entry of order unity. THE 1e-20 rad/s IS BELOW
            % ONE ULP of the Earth rate 7.29e-05, whose eps is 1.4e-20, so it is in effect a
            % bit-identity claim. It is sound because the batch and the single call evaluate
            % the same elementwise expressions with no reduction across epochs; it would NOT be
            % sound across a pagemtimes, where BLAS may block differently (obligation O13).
            rng(1033);
            n = 25;
            origin = [(rand(n, 1) - 0.5)*170, (rand(n, 1) - 0.5)*360, ...
                rand(n, 1)*500];
            angle = (rand(n, 1) - 0.5)*300;
            velocity = (rand(n, 2) - 0.5)*300;

            [batchR, batchRates] = referenceSystem.wanderAzimuthRotation( ...
                origin, angle, 'Velocity', velocity, 'AngleUnit', "deg");
            for k = 1:n
                [oneR, oneRates] = referenceSystem.wanderAzimuthRotation( ...
                    origin(k, :), angle(k), 'Velocity', velocity(k, :), ...
                    'AngleUnit', "deg");
                testCase.verifyEqual(batchR(:, :, k), oneR, 'AbsTol', 1e-15, ...
                    sprintf('Rotation %d differs.', k));
                testCase.verifyEqual(batchRates.earth(:, k), oneRates.earth, ...
                    'AbsTol', 1e-20, sprintf('Earth rate %d differs.', k));
                testCase.verifyEqual(batchRates.transport(:, k), ...
                    oneRates.transport, 'AbsTol', 1e-20, ...
                    sprintf('Transport rate %d differs.', k));
            end
        end

    end

    methods (Test, TestTags = {'precision'})

        function integrateAttitude_precision_localProductMatchesTheAuthority(testCase)
            % THE TEST integrateAttitude's HELP SAYS EXISTS. Since P27b the
            % product lives in the package-private composeRotationVectors and
            % is shared with integrateAttitudeIncrements, so this test now
            % guards ONE authority rather than one copy. It is a deliberate
            % optimisation - the L4b product normalises
            % and canonicalises the sign on every call, which a propagation
            % loop must then undo - and the help justifies it by claiming this
            % comparison at 1e-16. The claim was written and the test was not,
            % which is obligation O16 exactly: an unchecked SENTENCE.
            %
            % One step of the loop is reproduced by driving the function over a
            % single interval, and the same step is composed through the L4b
            % authority. They must agree as ROTATIONS; the sibling imposes
            % q0 >= 0 and the integrator deliberately does not, so the sign is
            % removed before comparing rather than asserted equal.
            rateSeries = [0.011 0.011; -0.023 -0.023; 0.017 0.017];
            % D9: the two-part epoch exists so a second survives at MJD 60310.
            % Adding 1/86400 to the day number BEFORE the call throws that
            % away - eps(60310) is 6.3e-07 s - and the step is then wrong by
            % 2.3e-07 s, which is 2e-08 rad against a 1e-15 tolerance. The
            % offset must be added in SECONDS.
            epoch = referenceSystem.addSeconds( ...
                referenceSystem.mjdToEpoch([60310; 60310], 'TAI'), [0; 1]);
            start = [0.5; 0.5; 0.5; 0.5];

            q = referenceSystem.integrateAttitude(start, rateSeries, epoch);

            omega = [0.011; -0.023; 0.017];
            angle = norm(omega);
            increment = [cos(angle/2); omega/angle*sin(angle/2)];
            expected = referenceSystem.multiplyQuaternions( ...
                start/norm(start), increment);

            actual = q(:, end);
            if actual.'*expected < 0
                actual = -actual;
            end

            % Bound: a four-term product of unit operands, a few ulp.
            testCase.verifyEqual(actual, expected, 'AbsTol', 1e-15);
        end

    end

    methods (Test, TestTags = {'reference'})

        function angularVelocityFromRotationRate_reference_graceFoRate(testCase)
            % THE SHARPEST CHECK IN THE TOOLBOX, and the one R20 exists for.
            % Real GRACE-FO attitude goes in and an orbital period comes out,
            % compared against orbital mechanics rather than against anything
            % this toolbox computed.
            %
            % A nadir-pointing spacecraft turns once per orbit about the orbit
            % normal, so the rate recovered from its attitude IS the mean
            % motion. Over the full day this arc comes from, |omega| gives
            % 1.114e-03 rad/s: a 94.0 min period and a 469 km altitude, for a
            % satellite flying at about 470 km after seven years of decay.
            % A wrong sense or a wrong product would not produce an orbit.
            q = TestPerformance.graceFoArc();
            R = referenceSystem.rotationFromQuaternion(q);

            Rdot = (R(:, :, 3:end) - R(:, :, 1:end-2))/2;
            omega = referenceSystem.angularVelocityFromRotationRate( ...
                R(:, :, 2:end-1), Rdot, 'Resolution', "body");

            rate = sqrt(sum(omega.^2, 1));

            % Bound: an 8.8e-07 rad formal error through a 2 s central
            % difference is about 4.4e-07 rad/s of noise on a 1.1e-03 rad/s
            % signal, 0.04 per cent. One per cent sits outside that and well
            % inside what an orbit-versus-not decision needs.
            testCase.verifyEqual(mean(rate), 1.118044e-03, 'RelTol', 1e-2, ...
                'Recovered rate must be the GRACE-FO mean motion.');
            testCase.verifyLessThan(abs(mean(2*pi./rate)/60 - 93.7), 1.0, ...
                'Implied orbital period, in minutes.');

            % The rotation axis is the orbit normal, which for this spacecraft
            % is the second SRF axis. Under the transposed sense the fixed axis
            % comes out as the first, so this line alone separates the two.
            [~, dominant] = max(abs(mean(omega, 2)));
            testCase.verifyEqual(dominant, 2, ...
                'omega lies along the SRF axis fixed in inertial space.');
        end

    end


    methods (Test, TestTags = {'contract'})

        function angularVelocityFromRotationRate_contract_shapeAndRefusals(testCase)
            % Decision D76 split this from angularVelocityToRotationRate rather
            % than adding a direction flag (section C.7 rule 2), and the partner
            % had contract tests while this one had only a reference test.
            convention = referenceSystem.attitudeConvention();
            R = cat(3, referenceSystem.rotationZ(0.1), referenceSystem.rotationZ(0.2));
            Rdot = 1e-3 * cat(3, referenceSystem.rotationX(0.4), ...
                referenceSystem.rotationY(0.5));

            omega = referenceSystem.angularVelocityFromRotationRate(R, Rdot, ...
                'Convention', convention);

            testCase.verifySize(omega, [3 2], 'One angular velocity per page.');
            testCase.verifyError(@() ...
                referenceSystem.angularVelocityFromRotationRate(eye(2), Rdot), ...
                'referenceSystem:angularVelocityFromRotationRate:wrongRotationSize');
            testCase.verifyError(@() ...
                referenceSystem.angularVelocityFromRotationRate(R, eye(2)), ...
                'referenceSystem:angularVelocityFromRotationRate:wrongRateSize');
            % A SINGLE PAGE BROADCASTS and is not a mismatch: one rotation
            % against many rates, or one rate against many rotations, are both
            % meaningful. The mismatch is two page counts that are both greater
            % than one and unequal, which is what is driven here.
            testCase.verifyError(@() ...
                referenceSystem.angularVelocityFromRotationRate( ...
                repmat(R, 1, 1, 2), Rdot), ...
                'referenceSystem:angularVelocityFromRotationRate:sizeMismatch');
        end

    end

    methods (Test, TestTags = {'precision'})

        function rotationNavToBody_precision_roundTripsThroughRollPitchYaw(testCase)
            % The matrix must give its own angles back. Driven over a spread
            % that stays clear of pitch = +-pi/2, where the ZYX sequence is
            % singular and roll and yaw are not separately defined - that is a
            % real property of the parameterisation and has its own gimbal-lock
            % test, not something to be hidden inside a round trip.
            convention = referenceSystem.attitudeConvention();
            roll = linspace(-3.0, 3.0, 25);
            pitch = linspace(-1.4, 1.4, 25);
            yaw = linspace(-3.0, 3.0, 25);
            rollPitchYaw = [roll; pitch; yaw];

            R = referenceSystem.rotationNavToBody(rollPitchYaw, ...
                'Convention', convention);
            back = referenceSystem.rollPitchYawFromRotation(R, ...
                'Convention', convention);

            % 1e-14 rad bounds the recovery of an angle of order unity through
            % an atan2 and an asin of entries built from three trigonometric
            % products: a few ulp, accumulated twice. It is not a bound on any
            % attitude accuracy.
            testCase.verifyLessThan(max(abs(back - rollPitchYaw), [], 'all'), 1e-14, ...
                'The navigation attitude does not return its own angles.');
        end

    end

    % ---------------------------------------------------------------------
    % PROMPT P27 - GRACE-FO IMU1B integrated angle increments.
    %
    % The fixture is 120 s of the real IMU1B_2020-01-01_C_04 product, chosen
    % because it CONTAINS A COUNTER WRAP. Section H.5 asked for a constructed
    % one; a real one is better and both are here, because the constructed case
    % is the only one with analytic truth and the real one is the only one that
    % can disagree with the handbook.
    % ---------------------------------------------------------------------

    methods (Test, TestTags = {'contract'})

        function readImu1b_contract_returnsDocumentedFieldsAndSizes(testCase)
            [imu, info] = referenceSystem.readImu1b(testCase.imuFixture());

            testCase.verifyEqual(sort(fieldnames(imu)), sort({'epoch'; ...
                'gyroId'; 'filteredAngle'; 'qualityFlag'; 'satellite'; ...
                'meta'}), 'readImu1b changed its documented field list.');
            testCase.verifyEqual(imu.satellite, "C");
            testCase.verifyEqual(imu.epoch.scale, "GPS");
            testCase.verifyEqual(numel(imu.gyroId), info.recordCount);
            testCase.verifyEqual(numel(imu.filteredAngle), info.recordCount);
            testCase.verifyEqual(numel(imu.epoch.day), info.recordCount);
            testCase.verifyEqual(info.gyroIdPresent, [1 2 3], ...
                'The shipped product carries three gyros and no fourth.');
            testCase.verifyEqual(info.recordsPerGyro, [961 960 960]);
        end

        function readImu1b_contract_refusesAnUnexpectedLayout(testCase)
            % A renamed column is a different product or a format change. Column
            % six of a different layout is a plausible number that is not an
            % angle, so the read is refused rather than indexed.
            scratch = testCase.scratchCopy(@(text) strrep(text, ...
                "- FiltAng:", "- RawAng:"));
            testCase.verifyError(@() referenceSystem.readImu1b(scratch), ...
                'referenceSystem:readImu1b:unexpectedLayout');
        end

        function readImu1b_contract_refusesATruncatedFile(testCase)
            % A truncated file parses perfectly and yields a short arc, which is
            % a defect that looks like a short day. num_records catches it.
            scratch = testCase.scratchCopy(@TestNavigation.dropLastRecords);
            testCase.verifyError(@() referenceSystem.readImu1b(scratch), ...
                'referenceSystem:readImu1b:recordCountMismatch');
        end

        function readImu1b_contract_refusesAnImu1aTimeReference(testCase)
            % IMU1A shares this format and reads "R"; its time tags need TIM1B
            % and CLK1B to reach GPS time, which this toolbox does not do.
            scratch = testCase.scratchCopy(@(text) strrep(text, " G C ", " R C "));
            testCase.verifyError(@() referenceSystem.readImu1b(scratch), ...
                'referenceSystem:readImu1b:wrongTimeReference');
        end

        function readImu1b_contract_refusesAHeaderWithNoTerminator(testCase)
            scratch = testCase.scratchCopy(@(text) strrep(text, ...
                "# End of YAML header", "# not the terminator"));
            testCase.verifyError(@() referenceSystem.readImu1b(scratch), ...
                'referenceSystem:readImu1b:headerNotTerminated');
        end

        function graceFoImuAlignment_contract_refusesAnUnknownSatellite(testCase)
            testCase.verifyError(@() referenceSystem.graceFoImuAlignment("A"), ...
                'referenceSystem:graceFoImuAlignment:unknownSatellite');
        end

        function graceFoImuAlignment_contract_listNamesBothSatellites(testCase)
            listed = referenceSystem.graceFoImuAlignment("list");
            testCase.verifyEqual(height(listed), 2);
            testCase.verifyEqual(listed.satellite', ["C" "D"]);
            testCase.verifyEqual(listed.airbusSatelliteNumber', [1 2], ...
                'Table 3 maps Airbus FM 1 to GRACE C and FM 2 to GRACE D.');
        end

        function graceFoImuIncrements_contract_refusesAMissingTriadGyro(testCase)
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            keep = imu.gyroId ~= 2;
            imu.gyroId = imu.gyroId(keep);
            imu.filteredAngle = imu.filteredAngle(keep);
            imu.qualityFlag = imu.qualityFlag(keep);
            imu.epoch.day = imu.epoch.day(keep);
            imu.epoch.sec = imu.epoch.sec(keep);

            testCase.verifyError(@() referenceSystem.graceFoImuIncrements(imu), ...
                'referenceSystem:graceFoImuIncrements:missingGyro');
        end

        function graceFoImuIncrements_contract_refusesTheOtherSatellitesAlignment(testCase)
            % The two satellites' tables differ by 214.5 arcsec, which is
            % invisible at one epoch and 10.0 deg of attitude per day.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            wrong = referenceSystem.graceFoImuAlignment("D");
            testCase.verifyError(@() referenceSystem.graceFoImuIncrements(imu, ...
                'Alignment', wrong), ...
                'referenceSystem:graceFoImuIncrements:alignmentMismatch');
        end

        function graceFoImuIncrements_contract_refusesAGapLargerThanMaxGap(testCase)
            % Interpolating across a gap reports the spacecraft's motion over it
            % as a measurement of it, so the default refuses beyond one second.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            testCase.verifyError(@() referenceSystem.graceFoImuIncrements(imu, ...
                'MaxGap', 0.05), ...
                'referenceSystem:graceFoImuIncrements:gapTooLarge');
        end

        function graceFoImuIncrements_contract_oneFewerIncrementThanEpoch(testCase)
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            [deltaTheta, epoch, info] = ...
                referenceSystem.graceFoImuIncrements(imu);

            testCase.verifyEqual(size(deltaTheta, 1), 3);
            testCase.verifyEqual(size(deltaTheta, 2), numel(epoch.day) - 1, ...
                'Increment k spans epoch k to epoch k+1.');
            testCase.verifyEqual(epoch.scale, "GPS");
            testCase.verifyEqual(info.gyroUsed, [1 2 3], ...
                'Decision D83 fixes the triad; it is never chosen per epoch.');
            testCase.verifyFalse(info.gyroFourResidual.available);
        end

    end

    methods (Test, TestTags = {'reference'})

        function readImu1b_reference_reproducesTheFirstRecordOfTheFixture(testCase)
            % The literals are the first two lines of the fixture as shipped.
            % The authority is the file, which the reader did not produce.
            imu = referenceSystem.readImu1b(testCase.imuFixture());

            testCase.verifyEqual(imu.gyroId(1:3)', [1 2 3]);
            testCase.verifyEqual(imu.filteredAngle(1), 5753.97053521817, ...
                'AbsTol', 0, 'The angle must be the file''s decimal verbatim.');
            testCase.verifyEqual(imu.filteredAngle(2), 4099.2075498839, ...
                'AbsTol', 0);
            testCase.verifyEqual(imu.filteredAngle(3), -40.9923373159008, ...
                'AbsTol', 0);
            testCase.verifyEqual(imu.qualityFlag(1), "00000000");
        end

        function graceFoImuAlignment_reference_theFourAxesAreATetrahedron(testCase)
            % HANDBOOK SECTION 3.3.3 STATES A TETRAHEDRAL CONFIGURATION IN PROSE
            % AND TABLE 23 STATES TWELVE NUMBERS. The prose is the independent
            % authority: four axes at acos(-1/3) = 109.4712 deg is a claim the
            % table must satisfy and a mistyped digit would break. Re-typing the
            % table here would only assert that the same transcription was made
            % twice (obligation O23).
            for satellite = ["C", "D"]
                alignment = referenceSystem.graceFoImuAlignment(satellite);
                axes = alignment.gyroAxis;

                testCase.verifyEqual(vecnorm(axes, 2, 1), ones(1, 4), ...
                    'AbsTol', 1e-9, ...
                    'Satellite ' + satellite + ' gyro axes are not unit.');

                % The Gram matrix diagonal can land a few ulp above 1, and
                % acosd of that is COMPLEX, which would fail on class rather
                % than on value and send the reader to the wrong question.
                gram = min(max(axes' * axes, -1), 1);
                separation = acosd(gram);
                offDiagonal = separation(~eye(4));
                testCase.verifyEqual(offDiagonal, ...
                    repmat(acosd(-1/3), numel(offDiagonal), 1), ...
                    'AbsTol', 0.05, ...
                    'Satellite ' + satellite + ' axes are not tetrahedral.');
            end
        end

        function graceFoImuIncrements_reference_matchesAConstantRateExactly(testCase)
            % THE ONLY CASE WITH ANALYTIC TRUTH, AND IT CARRIES A CONSTRUCTED
            % COUNTER WRAP. For a constant body rate the integral of omega over
            % an interval is omega*dt exactly, and the projection of an
            % increment onto a fixed axis is exact, so the whole chain has a
            % closed form. The counter is wrapped modulo the span measured from
            % the real product, so the repair is exercised against truth rather
            % than against a second run of the same code.
            omegaImu = [0.02; 0.03; 0.05]*pi/180;
            imu = TestNavigation.syntheticReading(omegaImu, true, false);

            [deltaTheta, epoch, info] = ...
                referenceSystem.graceFoImuIncrements(imu);

            testCase.verifyEqual(info.wrapCount, 1, ...
                'The constructed wrap was not detected.');
            alignment = referenceSystem.graceFoImuAlignment("C");
            spacing = diff(referenceSystem.secondsBetween( ...
                referenceSystem.daySecondToEpoch( ...
                [epoch.day(1), epoch.sec(1)], "GPS"), epoch))';
            expected = (alignment.imuToSatelliteFrame*omegaImu).*spacing;

            % 1e-13 rad is set by CANCELLATION IN THE DIFFERENCE, not by the
            % solve. The synthetic counter starts near 5757 deg so that it
            % wraps, one ulp there is 9.1e-13 deg = 1.6e-14 rad, and each
            % increment is a difference of two such numbers carried through a
            % 3x3 solve of condition 2. It is not a bound on attitude accuracy.
            testCase.verifyLessThan(max(abs(deltaTheta - expected), [], 'all'), ...
                1e-13, 'The increments do not reproduce a constant rate.');
        end

        function graceFoImuIncrements_reference_recoversTheOrbitAndPointing(testCase)
            % NEITHER THE ORBIT NOR THE POINTING MODE IS AN INPUT TO ANY OF
            % THIS, so both are truth from outside the toolbox: the handbook
            % describes a nadir-pointing yaw axis, which makes the body rate
            % almost pure pitch about the Satellite Frame Y axis, and Table 2
            % gives a 500 km launch altitude decaying over the mission.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            [deltaTheta, epoch] = referenceSystem.graceFoImuIncrements(imu);

            spacing = diff(referenceSystem.secondsBetween( ...
                referenceSystem.daySecondToEpoch( ...
                [epoch.day(1), epoch.sec(1)], "GPS"), epoch))';
            omega = mean(deltaTheta./spacing, 2);

            testCase.verifyGreaterThan(abs(omega(2))/norm(omega), 0.999, ...
                'The recovered rate is not pitch about the SRF Y axis.');
            testCase.verifyGreaterThan(omega(2), 0, ...
                'The pitch sense is reversed, which a magnitude check misses.');

            periodMinutes = 2*pi/norm(omega)/60;
            testCase.verifyGreaterThan(periodMinutes, 93.0, ...
                'The recovered orbital period is not a GRACE-FO period.');
            testCase.verifyLessThan(periodMinutes, 96.0, ...
                'The recovered orbital period is not a GRACE-FO period.');
        end

        function graceFoImuIncrements_reference_repairsTheRealCounterWrap(testCase)
            % The wrap actually in the shipped product, and the two numbers that
            % matter about it. THE OBSERVED JUMP IS NOT TWICE THE DECLARED
            % valid_range: the counter turns at 5757.074 and not at 5758, so the
            % implied span is 11514.156 deg and not 11516. A repair that
            % subtracted the declared range would leave 1.844 deg in one
            % increment, and this test is what refuses that.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            [~, ~, info] = referenceSystem.graceFoImuIncrements(imu);

            testCase.verifyEqual(info.wrapCount, 1);
            testCase.verifyEqual(info.wrap.gyroId, 1);
            testCase.verifyEqual(info.wrap.observedJump, -11514.149406113, ...
                'AbsTol', 1e-6, 'The wrap in the fixture is not the one seen.');
            testCase.verifyEqual(info.wrap.impliedSpan, 11514.1559, ...
                'AbsTol', 1e-3, ...
                'The implied counter span moved; 2*5758 = 11516 is not it.');
            testCase.verifyNotEqual(round(info.wrap.impliedSpan), 11516);
        end

    end

    methods (Test, TestTags = {'precision'})

        function readImu1b_precision_keepsTheMicrosecondStated(testCase)
            % The first record reads 631127294 366082 in GPS seconds and
            % microseconds. The split epoch must return it to the resolution the
            % file states; one ulp of the seconds field near 1e4 s is 1.8e-12 s.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            recovered = referenceSystem.epochTo(imu.epoch, "j2000Seconds");

            % 1e-6 s bounds the COLLAPSED form, not the split epoch: recovered
            % is 6.3e8 s, where one ulp is 1.2e-7 s. The split representation
            % holds the microsecond exactly; asking for it back as one number
            % is what costs this, and the bound says which quantity it bounds.
            testCase.verifyEqual(recovered(1), 631127294 + 366082e-6, ...
                'AbsTol', 1e-6, ...
                'The epoch lost the microsecond the file states.');
        end

        function graceFoImuAlignment_precision_theRotationIsProperOrthogonal(testCase)
            % 1e-15 bounds the orthogonality of a matrix given to fifteen
            % decimal digits: the products are three-term dot products of
            % entries of order unity, so a few ulp. Measured 7.2e-16 for C and
            % 6.3e-16 for D. A larger residual means a mistyped digit.
            for satellite = ["C", "D"]
                alignment = referenceSystem.graceFoImuAlignment(satellite);
                R = alignment.imuToSatelliteFrame;
                testCase.verifyLessThan(max(abs(R'*R - eye(3)), [], 'all'), ...
                    1e-15, 'Table 24 for ' + satellite + ' is not orthogonal.');
                testCase.verifyEqual(det(R), 1, 'AbsTol', 1e-15, ...
                    'Table 24 for ' + satellite + ' is not a proper rotation.');
            end
        end

        function graceFoImuIncrements_precision_incrementsTelescope(testCase)
            % THE PROPERTY THAT DECIDES THE DESIGN. The angle is interpolated
            % and then differenced, never differenced and then interpolated, so
            % the increments sum to the total angle turned exactly. Rebuilding
            % them from an interpolated rate would break this at the 1e-9 level
            % and reintroduce exactly the sampling error P27 removes.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            deltaTheta = referenceSystem.graceFoImuIncrements(imu);

            total = sum(deltaTheta, 2);
            running = cumsum(deltaTheta, 2);

            % 1e-16 rad bounds the difference between two summations of the same
            % 958 terms of order 1e-4 rad: accumulated rounding alone.
            testCase.verifyLessThan(max(abs(total - running(:, end))), 1e-16, ...
                'The increments do not telescope.');
        end

        function graceFoImuIncrements_precision_theMethodDoesNotMatter(testCase)
            % ACCURACY claims the three interpolants are indistinguishable at
            % the native 1.1 ms stagger, and this is that claim as a test rather
            % than a sentence. 5e-8 rad bounds the measured spread of 8.9e-09
            % rad between pchip, spline and linear over the shipped fixture,
            % with margin for a different release's pchip end conditions.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            usingPchip = referenceSystem.graceFoImuIncrements(imu);
            usingSpline = referenceSystem.graceFoImuIncrements(imu, ...
                'Method', "spline");
            usingLinear = referenceSystem.graceFoImuIncrements(imu, ...
                'Method', "linear");

            testCase.verifyLessThan( ...
                max(abs(usingPchip - usingSpline), [], 'all'), 5e-8);
            testCase.verifyLessThan( ...
                max(abs(usingPchip - usingLinear), [], 'all'), 5e-8);
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function graceFoImuIncrements_diagnostics_reportsTheWrapNotHidesIt(testCase)
            % A repair nobody can see is indistinguishable from data that never
            % needed one, and this is the repair most likely to be wrong.
            imu = referenceSystem.readImu1b(testCase.imuFixture());
            [~, ~, info] = referenceSystem.graceFoImuIncrements(imu);

            testCase.verifyEqual(sort(fieldnames(info.wrap)), ...
                sort({'gyroId'; 'sampleIndex'; 'observedJump'; ...
                'substitutedIncrement'; 'impliedSpan'}));
            testCase.verifyNotEmpty(info.wrap);
            testCase.verifyGreaterThan(info.wrap.sampleIndex, 0);
        end

        function graceFoImuIncrements_diagnostics_gyroFourIsReportedNeverUsed(testCase)
            % DECISION D83 IN ONE ASSERTION. No shipped file carries a fourth
            % gyro, so the path is exercised synthetically - which is stated
            % rather than left for a reader to discover. The solution must be
            % BIT-IDENTICAL with and without gyro 4 present: both runs perform
            % the same solve on the same three series, so AbsTol 0 is a claim
            % about this function and not about BLAS blocking (obligation O13).
            omegaImu = [0.02; 0.03; 0.05]*pi/180;
            biasRate = 1e-4;
            sampleInterval = 0.125;
            withoutFour = TestNavigation.syntheticReading(omegaImu, false, false);
            withFour = TestNavigation.syntheticReading(omegaImu, false, true, biasRate);

            [triadOnly, ~, plainInfo] = ...
                referenceSystem.graceFoImuIncrements(withoutFour);
            [withGyroFour, ~, info] = ...
                referenceSystem.graceFoImuIncrements(withFour);

            testCase.verifyFalse(plainInfo.gyroFourResidual.available);
            testCase.verifyTrue(info.gyroFourResidual.available);
            testCase.verifyEqual(info.gyroPresent, [1 2 3 4]);
            testCase.verifyEqual(info.gyroUsed, [1 2 3], ...
                'Gyro 4 must never join the solution.');
            testCase.verifyEqual(withGyroFour, triadOnly, 'AbsTol', 0, ...
                'Gyro 4 changed the solution, which D83 forbids.');
            % The residual lives on an INCREMENT, so an injected rate bias of
            % 1e-4 deg/s appears as deg2rad(1e-4)*0.125 = 2.18e-07 rad. RelTol
            % 1e-5 leaves room for the 1e-13 rad cancellation floor of the
            % triad solve, which is 5e-07 of this quantity.
            testCase.verifyEqual(info.gyroFourResidual.rms, ...
                deg2rad(biasRate)*sampleInterval, 'RelTol', 1e-5, ...
                'The injected gyro-4 disagreement was not reported.');
        end

    end


    % ---------------------------------------------------------------------
    % PROMPT P27b - attitude from integrated angle increments (option C of
    % section H.5a). The closed-form coning case has an analytic rate, an
    % analytic INCREMENT and an analytic attitude, so every reference test
    % below compares against truth on both sides rather than against the rate
    % path, which could share a convention error.
    % ---------------------------------------------------------------------

    methods (Test, TestTags = {'contract'})

        function integrateAttitudeIncrements_contract_refusesAWrongIncrementSize(testCase)
            [~, epoch] = TestNavigation.coningIncrements(0.05, 4);
            testCase.verifyError(@() ...
                referenceSystem.integrateAttitudeIncrements([1; 0; 0; 0], ...
                zeros(2, 4), epoch), ...
                'referenceSystem:integrateAttitudeIncrements:wrongIncrementSize');
        end

        function integrateAttitudeIncrements_contract_refusesAWrongQuaternionSize(testCase)
            [deltaTheta, epoch] = TestNavigation.coningIncrements(0.05, 4);
            testCase.verifyError(@() ...
                referenceSystem.integrateAttitudeIncrements([1; 0; 0], ...
                deltaTheta, epoch), ...
                'referenceSystem:integrateAttitudeIncrements:wrongQuaternionSize');
        end

        function integrateAttitudeIncrements_contract_refusesTheWrongEpochCount(testCase)
            % AN INCREMENT SPANS AN INTERVAL, so there is exactly one more
            % epoch than increment. Accepting N epochs for N increments would
            % silently drop the last interval or run off the end.
            [deltaTheta, epoch] = TestNavigation.coningIncrements(0.05, 4);
            testCase.verifyError(@() ...
                referenceSystem.integrateAttitudeIncrements([1; 0; 0; 0], ...
                deltaTheta(:, 1:end-1), epoch), ...
                'referenceSystem:integrateAttitudeIncrements:sizeMismatch');
        end

        function integrateAttitudeIncrements_contract_refusesANonIncreasingEpoch(testCase)
            [deltaTheta, epoch] = TestNavigation.coningIncrements(0.05, 4);
            epoch.sec(3) = epoch.sec(2);
            testCase.verifyError(@() ...
                referenceSystem.integrateAttitudeIncrements([1; 0; 0; 0], ...
                deltaTheta, epoch), ...
                'referenceSystem:integrateAttitudeIncrements:samplesNotIncreasing');
        end

        function integrateAttitudeIncrements_contract_honoursScalarLastLayout(testCase)
            % The convention decides the ROW ORDER of the argument and of the
            % result, and nothing else; the same rotation must come back.
            [deltaTheta, epoch, truth] = TestNavigation.coningIncrements(0.05, 20);
            scalarFirst = referenceSystem.integrateAttitudeIncrements( ...
                truth(:, 1), deltaTheta, epoch);
            scalarLast = referenceSystem.integrateAttitudeIncrements( ...
                truth([2 3 4 1], 1), deltaTheta, epoch, ...
                'Convention', referenceSystem.attitudeConvention('aerospace'));

            testCase.verifyEqual(scalarLast([4 1 2 3], :), scalarFirst, ...
                'AbsTol', 0, 'The layout changed the rotation, not just rows.');
        end

    end

    methods (Test, TestTags = {'reference'})

        function integrateAttitudeIncrements_reference_closedFormConing(testCase)
            % TRUTH ON BOTH SIDES. The increment over an interval is the exact
            % integral of the closed-form rate, and the attitude is the
            % closed-form quaternion; neither is produced by the function.
            interval = 0.02;
            [deltaTheta, epoch, truth] = ...
                TestNavigation.coningIncrements(interval, 100);

            q = referenceSystem.integrateAttitudeIncrements(truth(:, 1), ...
                deltaTheta, epoch);

            % 2e-08 rad bounds the SECOND-ORDER TRUNCATION of Bortz's equation
            % over 100 steps of 0.02 s, measured at 7.2e-09 in the independent
            % mirror. It is a bound on the coning algorithm, not on rounding
            % and not on any sensor.
            separation = TestNavigation.angleBetween(q(:, end), truth(:, end));
            testCase.verifyLessThan(separation, 2e-08, sprintf( ...
                'Closed-form coning missed by %.3e rad.', separation));
        end

        function integrateAttitudeIncrements_reference_beatsTheRatePath(testCase)
            % THE CLAIM IN THE ACCURACY BLOCK, AS A TEST. The same motion, the
            % same interval, the same truth: one function is handed exact
            % increments and the other the exact rates at the same epochs.
            % Section H.5a exists because the difference is the entire reason
            % P27 was filed, and until now it was asserted and never measured.
            interval = 0.02;
            stepCount = 100;
            [deltaTheta, epoch, truth] = ...
                TestNavigation.coningIncrements(interval, stepCount);
            [omega, rateEpoch, rateTruth] = ...
                TestNavigation.coningCase(interval, stepCount);

            fromIncrements = referenceSystem.integrateAttitudeIncrements( ...
                truth(:, 1), deltaTheta, epoch);
            fromRates = referenceSystem.integrateAttitude(rateTruth(:, 1), ...
                omega, rateEpoch);

            incrementError = TestNavigation.angleBetween( ...
                fromIncrements(:, end), truth(:, end));
            rateError = TestNavigation.angleBetween( ...
                fromRates(:, end), rateTruth(:, end));

            % Measured 1194x at this step in the mirror. 100x is asserted, an
            % order of magnitude of margin, because the ratio depends on the
            % step and the point is that the two are of DIFFERENT ORDER, not
            % that any particular number recurs.
            testCase.verifyGreaterThan(rateError/incrementError, 100, sprintf( ...
                ['Increments must beat sampled rates by orders, not by a ', ...
                'little: %.3e against %.3e rad.'], incrementError, rateError));
        end

    end

    methods (Test, TestTags = {'precision'})

        function integrateAttitudeIncrements_precision_constantRateIsExact(testCase)
            % A constant rate makes cross(dTheta, dTheta) vanish identically,
            % so the coning term is zero and the exact answer is one rotation
            % about the axis. Over 10^4 steps the only error is rounding, which
            % makes this the tightest available check on the shared
            % composition reached through this function.
            rate = [0.011; -0.023; 0.017];
            stepCount = 10000;
            interval = 0.01;
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(60000, stepCount+1, 1), ...
                (0:stepCount).'*interval], "TAI");
            deltaTheta = repmat(rate*interval, 1, stepCount);

            [q, info] = referenceSystem.integrateAttitudeIncrements( ...
                [1; 0; 0; 0], deltaTheta, epoch);

            total = norm(rate)*interval*stepCount;
            exact = [cos(total/2); rate/norm(rate)*sin(total/2)];
            testCase.verifyEqual(q(:, end), exact, 'AbsTol', 1e-13, ...
                'Constant-rate propagation is exact up to rounding.');
            testCase.verifyEqual(info.largestConingAngle, 0, 'AbsTol', 0, ...
                'A constant rate cones by nothing.');
        end

        function integrateAttitudeIncrements_precision_agreesWithTheRatePath(testCase)
            % WHERE THE TWO FUNCTIONS MUST AGREE THEY MUST AGREE CLOSELY. For a
            % constant rate the coning term vanishes in both and the increment
            % is the rate times the interval exactly, so any difference is the
            % two argument paths disagreeing about the same arithmetic.
            rate = [0.011; -0.023; 0.017];
            stepCount = 1000;
            interval = 0.01;
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(60000, stepCount+1, 1), ...
                (0:stepCount).'*interval], "TAI");

            fromRates = referenceSystem.integrateAttitude([1; 0; 0; 0], ...
                repmat(rate, 1, stepCount+1), epoch);
            fromIncrements = referenceSystem.integrateAttitudeIncrements( ...
                [1; 0; 0; 0], repmat(rate*interval, 1, stepCount), epoch);

            % 1e-14 bounds 1000 compositions of unit quaternions whose rotation
            % vectors differ only by the rounding of rate*interval against
            % interval*(rate+rate)/2: a few ulp per step, accumulated.
            testCase.verifyEqual(fromIncrements, fromRates, 'AbsTol', 1e-14, ...
                'The two argument paths disagree on a constant rate.');
        end

        function integrateAttitudeIncrements_precision_theConingWeightIsOneTwelfth(testCase)
            % THE GENERAL WEIGHT MUST REDUCE TO THE CLASSICAL ONE. On a uniform
            % grid Tc^2/(6*Tp*(Tp+Tc)) is exactly 1/12, and getting that wrong
            % would leave a coning term of the right shape and the wrong size -
            % which no orthogonality or norm check could see.
            interval = 0.05;
            [deltaTheta, epoch] = TestNavigation.coningIncrements(interval, 40);

            [~, info] = referenceSystem.integrateAttitudeIncrements( ...
                [1; 0; 0; 0], deltaTheta, epoch);

            expected = max(sqrt(sum(cross(deltaTheta(:, 1:end-1), ...
                deltaTheta(:, 2:end)).^2, 1))/12);
            testCase.verifyEqual(info.largestConingAngle, expected, ...
                'RelTol', 1e-14, ...
                'The uniform-grid coning weight is not 1/12.');
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function integrateAttitudeIncrements_diagnostics_firstIntervalUncorrected(testCase)
            % NO SINGLE-SAMPLE ALGORITHM CAN CORRECT THE FIRST INTERVAL, because
            % nothing precedes it. A caller splitting a long arc pays that once
            % per piece and should be told rather than left to discover it.
            [deltaTheta, epoch] = TestNavigation.coningIncrements(0.05, 20);

            [~, corrected] = referenceSystem.integrateAttitudeIncrements( ...
                [1; 0; 0; 0], deltaTheta, epoch);
            [~, plain] = referenceSystem.integrateAttitudeIncrements( ...
                [1; 0; 0; 0], deltaTheta, epoch, 'ConingCorrection', false);

            testCase.verifyTrue(corrected.firstIntervalUncorrected);
            testCase.verifyFalse(plain.firstIntervalUncorrected, ...
                'With no correction at all there is no uncorrected first one.');
            testCase.verifyEqual(corrected.method, "rotationVector", ...
                'There is no second method here and info must not imply one.');
        end

        function integrateAttitudeIncrements_diagnostics_coningTermEarnsItsPlace(testCase)
            % ON RATES THE CONING TERM BUYS A FACTOR OF TWO, because the
            % trapezoidal reconstruction of omega dominates and masks it
            % (rev. 1.60). On exact increments there is nothing to mask it and
            % it buys two orders. That contrast is the argument for this
            % function, so it is asserted rather than described.
            interval = 0.02;
            [deltaTheta, epoch, truth] = ...
                TestNavigation.coningIncrements(interval, 100);

            with = referenceSystem.integrateAttitudeIncrements(truth(:, 1), ...
                deltaTheta, epoch);
            without = referenceSystem.integrateAttitudeIncrements(truth(:, 1), ...
                deltaTheta, epoch, 'ConingCorrection', false);

            errorWith = TestNavigation.angleBetween(with(:, end), truth(:, end));
            errorWithout = TestNavigation.angleBetween(without(:, end), ...
                truth(:, end));

            % Measured 98x at this step. 30x is asserted, with margin, because
            % the ratio grows as the step shrinks and the claim is the order of
            % magnitude and not the number.
            testCase.verifyGreaterThan(errorWithout/errorWith, 30, sprintf( ...
                ['The coning term must buy orders on exact increments: ', ...
                '%.3e with against %.3e without.'], errorWith, errorWithout));
        end

    end

    methods (Access = private)

        function path = imuFixture(testCase)
            %IMUFIXTURE Absolute path of the shipped IMU1B excerpt.
            path = string(fullfile(testCase.toolboxRoot(), 'test', ...
                'fixtures', 'imu1bGraceC.txt'));
        end

        function root = toolboxRoot(~)
            %TOOLBOXROOT Absolute path of the distribution folder.
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function path = scratchCopy(testCase, editFcn)
            %SCRATCHCOPY A temporary copy of the fixture with one edit applied.
            %   The edit is applied to the text and the whole file is written in
            %   one call, because open-for-write truncates before its argument
            %   is evaluated and a formatting error would leave an empty file
            %   (obligation O19).
            text = string(fileread(testCase.imuFixture()));
            path = string([tempname, '.txt']);
            testCase.addTeardown(@() delete(path));
            fid = fopen(path, 'w');
            testCase.assertGreaterThan(fid, 0, 'Cannot write a scratch file.');
            closer = onCleanup(@() fclose(fid));
            fwrite(fid, char(editFcn(text)));
        end

    end

    methods (Static, Access = private)

        function [omega, epoch, truth, tEnd] = coningCase(interval, stepCount)
            %CONINGCASE The closed-form coning rate and attitude.
            %   Both sides are analytic, so nothing here is produced by the
            %   function under test. Derived by hand as omega = 2 vec(q* (x)
            %   qdot) and verified against a numerical derivative of q in the
            %   independent Python mirror.
            beta = TestNavigation.ConeAngle;
            spin = TestNavigation.ConeRate;
            t = (0:stepCount)*interval;

            omega = spin*[-sin(beta)*sin(spin*t); ...
                sin(beta)*cos(spin*t); ...
                -(1 - cos(beta))*ones(1, numel(t))];
            truth = [cos(beta/2)*ones(1, numel(t)); ...
                sin(beta/2)*cos(spin*t); ...
                sin(beta/2)*sin(spin*t); ...
                zeros(1, numel(t))];
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(60000, numel(t), 1), t.'], "TAI");
            tEnd = t(end);
        end

        function [deltaTheta, epoch, truth] = coningIncrements(interval, stepCount)
            %CONINGINCREMENTS Exact integrated increments of the coning case.
            %   The increment over an interval is the CLOSED-FORM integral of
            %   the closed-form rate, not a quadrature of it, so a test built
            %   on it has analytic truth on both sides and shares nothing with
            %   the function under test. Integrating
            %   omega = W[-sin(b) sin(Wt); sin(b) cos(Wt); -(1 - cos b)]
            %   term by term gives the differences below directly.
            beta = TestNavigation.ConeAngle;
            spin = TestNavigation.ConeRate;
            t = (0:stepCount)*interval;
            before = t(1:end-1);
            after = t(2:end);

            deltaTheta = [sin(beta)*(cos(spin*after) - cos(spin*before)); ...
                sin(beta)*(sin(spin*after) - sin(spin*before)); ...
                -(1 - cos(beta))*spin*(after - before)];
            truth = [cos(beta/2)*ones(1, numel(t)); ...
                sin(beta/2)*cos(spin*t); ...
                sin(beta/2)*sin(spin*t); ...
                zeros(1, numel(t))];
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(60000, numel(t), 1), t.'], "TAI");
        end

        function angle = angleBetween(first, second)
            %ANGLEBETWEEN Rotation angle separating two quaternions, sign free.
            %   2*acos(|q1.q2|) LOSES HALF ITS SIGNIFICANT DIGITS near zero
            %   separation: the dot product of two nearly equal unit
            %   quaternions rounds to 1, and the metric returns exactly 0 for
            %   anything below about 2e-08 rad. A test asserting a bound
            %   tighter than that against it asserts nothing, and one did.
            %   The vector part of the relative quaternion resolves to 1e-16,
            %   and the atan2 form is well conditioned at every angle rather
            %   than only at small ones. This is obligation O12's family: a
            %   bound below the resolution of the INSTRUMENT rather than below
            %   one ulp of the quantity.
            if first.'*second < 0
                second = -second;
            end
            relative = [first(1)*second(1) + first(2:4).'*second(2:4); ...
                first(1)*second(2:4) - second(1)*first(2:4) - ...
                cross(first(2:4), second(2:4))];
            angle = 2*atan2(sqrt(sum(relative(2:4).^2)), abs(relative(1)));
        end

        function imu = syntheticReading(omegaImu, wrapCounter, ...
                includeGyroFour, gyroFourBiasRate)
            %SYNTHETICREADING A reading with a constant body rate and known truth.
            %   NO SHIPPED PRODUCT CARRIES A FOURTH GYRO and no shipped day is
            %   guaranteed to carry a wrap, so both paths are built here. The
            %   rate is constant, which makes the integral of omega over an
            %   interval exactly omega*dt and gives these tests real truth.
            arguments
                omegaImu (3,1) double
                wrapCounter (1,1) logical
                includeGyroFour (1,1) logical
                gyroFourBiasRate (1,1) double = 0
            end
            alignment = referenceSystem.graceFoImuAlignment("C");
            sampleCount = 41;
            sampleInterval = 0.125;
            stagger = 0.0011;
            counterSpan = 11514.155886;

            gyroCount = 3 + double(includeGyroFour);
            gpsSecond = zeros(sampleCount*gyroCount, 1);
            gyroId = zeros(sampleCount*gyroCount, 1);
            angle = zeros(sampleCount*gyroCount, 1);
            for j = 1:gyroCount
                elapsed = (0:sampleCount-1)'*sampleInterval;
                rate = rad2deg(alignment.gyroAxis(:, j)'*omegaImu);
                if j == 4
                    rate = rate + gyroFourBiasRate;
                end
                if j == 1 && wrapCounter
                    % Start just below the turning point so the counter rolls
                    % over inside the arc.
                    start = counterSpan/2 - 0.09;
                else
                    start = 0;
                end
                trueAngle = start + rate*elapsed;
                if j == 1 && wrapCounter
                    trueAngle = mod(trueAngle + counterSpan/2, counterSpan) ...
                        - counterSpan/2;
                end
                rows = (j-1)*sampleCount + (1:sampleCount);
                gpsSecond(rows) = 6.31e8 + elapsed + (j-1)*stagger;
                gyroId(rows) = j;
                angle(rows) = trueAngle;
            end

            imu = struct( ...
                'epoch', referenceSystem.j2000SecondsToEpoch(gpsSecond, "GPS"), ...
                'gyroId', gyroId, ...
                'filteredAngle', angle, ...
                'qualityFlag', repmat("00000000", numel(gyroId), 1), ...
                'satellite', "C", ...
                'meta', struct('file', "synthetic", 'product', "IMU1B", ...
                    'timeReference', "G", 'angleUnit', "degrees", ...
                    'declaredRecordCount', numel(gyroId)));
        end

        function shorter = dropLastRecords(text)
            %DROPLASTRECORDS Remove the final three data records.
            line = split(text, newline);
            shorter = join(line(1:end-4), newline);
        end

    end

end
