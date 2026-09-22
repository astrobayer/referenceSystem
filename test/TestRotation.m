classdef TestRotation < matlab.unittest.TestCase
%TESTROTATION Layer L2 test suite — Earth rotation, ITRS to GCRS.
%
%   Populated by P8 (cipCoordinates) and P9 (rotationItrsToGcrs and its
%   derivatives). Carries the R13b equinox-versus-CIO cross-check and the D28
%   finite-difference convergence sweep, which is why it also uses the
%   convergence tag.
%
%   Every reference literal here comes from the SOFA cookbook "SOFA Tools for
%   Earth Attitude" (sofa_pn_c.pdf, release 20231011), worked example of
%   2007-04-05 12:00:00 UTC. Its sections 5.3 and 5.5 give the SAME physical
%   pole expressed against two different precession-nutation models, which is
%   what makes it the right document to test finding C-2 against: a fixture
%   carrying one set of offsets could not show that both routes agree.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% Populated: 2026-07-25 23:05 (CEST, UTC+02:00) by prompts P8 and P9
% -------------------------------------------------------------------------

    properties (Constant)
        % D28's velocity budget, as rotationItrsToGcrs's help states it, and the
        % orbit radius the handover evaluates it at. A rotation-rate error e
        % moves a velocity by about e*r, so the rate these tests may miss by is
        % VelocityBudget / OrbitRadius = 1.43e-16 1/s (rev. 1.223, H.11 item 5).
        VelocityBudget = 1e-9       % m/s
        OrbitRadius = 7e6           % m

        % SOFA cookbook example, 2007-04-05 12:00:00 UTC.
        % TT  = UTC + 32.184 s + 33 s of TAI - UTC.
        % UT1 = UTC - 0.072073685 s.
        CookbookTtSecond = 43265.184
        CookbookUt1Second = 43199.927926315
        CookbookDay = 54195

        % Offsets in milliarcseconds, as the cookbook prints them.
        CookbookDeltaX2006 = 0.1750
        CookbookDeltaY2006 = -0.2259
        CookbookDeltaX2000 = 0.1725
        CookbookDeltaY2000 = -0.2650

        % Section 5.5 results, IAU 2006/2000A.
        CookbookX = 0.000712264729599
        CookbookY = 0.000044385250426

        % Section 5.3 results, the IAU 2000A route to the same physical pole.
        CookbookX2000 = 0.000712264729708
        CookbookY2000 = 0.000044385250265

        % Section 5.5 celestial-to-terrestrial matrix, which is the transpose
        % of what rotationItrsToGcrs returns.
        CookbookGcrsToItrs = [ ...
             0.973104317697535,  0.230363826239128, -0.000703163482198; ...
            -0.230363800456037,  0.973104570632801,  0.000118545366625; ...
             0.000711560162668,  0.000046626403995,  0.999999745754024]

        CookbookPolarX = 0.0349282
        CookbookPolarY = 0.4833163
        CookbookDeltaUt1 = -0.072073685

        % P17 reference literals, assembled in Python from the IERS Conventions
        % (2010) formulae and NOT taken from SOFA, so they check the assembly
        % and the marshalling rather than repeating the library under test.
        %
        % PolarMotionAtCookbook is equation 5.3, W = R3(-s') R2(xp) R1(yp),
        % TRANSPOSED, because equation 5.1 uses that W as the ITRS to TIRS
        % rotation while rotationTirsToItrs is named for the other direction.
        % Transposed it agrees with iauPom00 to 0.0; untransposed it differs by
        % 4.7e-06, which is the defect this literal exists to pin.
        PolarMotionAtCookbook = [ ...
             9.99999999999985678e-01, -1.65383565821104614e-11,  1.69336692165300118e-07; ...
             1.69351435327846182e-11,  9.99999999997254752e-01, -2.34318354543023026e-06; ...
            -1.69336692126082837e-07,  2.34318354543306443e-06,  9.99999999997240430e-01]

        % CelestialToIntermediateAtCookbook is equation 5.10,
        % Q = R3(-(E+s)) R2(d) R3(E), at the cookbook CIP with s from iauS06.
        % Agrees with iauC2ixys to 1.1e-16.
        CelestialToIntermediateAtCookbook = [ ...
             9.99999746339444995e-01, -5.13919366518466063e-09, -7.12264730072494317e-04; ...
            -2.64748560595797359e-08,  9.99999999014974716e-01, -4.43852428276791234e-05; ...
             7.12264729599000027e-04,  4.43852504260000013e-05,  9.99999745354419822e-01]
    end

    methods (Test, TestTags = {'contract'})

        function rotationItrsToGcrs_contract_infoReportsTheModelUsed(testCase)
            % info.cipModel is the model the offsets were referred to IN THIS
            % CALL. An override is what was used, and reporting the series'
            % metadata instead would be a diagnostic contradicting the
            % computation.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 3600], "UTC");
            [~, ~, ~, info] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop, ...
                'CipModel', "IAU2000A", 'Derivatives', 0);
            testCase.verifyEqual(info.cipModel, "IAU2000A");
            [~, ~, ~, info] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop, ...
                'Derivatives', 0);
            testCase.verifyEqual(info.cipModel, string(eop.meta.cipModel));
        end

        function rotationItrsToGcrs_contract_refusesAMissingEopValue(testCase)
            % D129, end to end. A series that leaves dX blank where the epoch's
            % stencil reads it gave an all-NaN rotation with no error; it is
            % refused by name.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            eop.dX(eop.mjd >= 57760) = NaN;
            utc = referenceSystem.daySecondToEpoch([57761 3600], "UTC");
            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs(utc, ...
                'Eop', eop), 'referenceSystem:interpolateEop:missingValue');
        end

        function rotationItrsToGcrs_contract_refusesAMismatchedCipModel(testCase)
            % P19c DELIVERABLE 3. With the series no longer read on the
            % interpolated path, the CIP model can only come from the
            % interpolant - and a caller who overrides it is asking for the
            % fitted X and Y to be reinterpreted against a different
            % precession-nutation model. THEY CANNOT BE: the observed pole
            % offsets are already inside them, referred to the model the fit
            % used. Getting this wrong is 121 and 135 uas at 2025, 4.2 mm at
            % the surface, and it was the most serious defect inherited from
            % v1 - invisible in the resulting rotation, which is why it is
            % refused rather than warned about.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);
            query = referenceSystem.daySecondToEpoch([57754 3600], "UTC");

            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs( ...
                query, 'Interpolant', interpolant, 'CipModel', "IAU2000A"), ...
                'referenceSystem:rotationItrsToGcrs:cipModelMismatch');

            % AND THE AGREEING OVERRIDE MUST BE ACCEPTED, or the refusal above
            % would pass on a function that refuses every override.
            testCase.verifyNotEmpty(referenceSystem.rotationItrsToGcrs( ...
                query, 'Interpolant', interpolant, ...
                'CipModel', string(interpolant.meta.cipModel)));
        end

        function rotationItrsToGcrs_contract_formatOneInterpolantStillWorks(testCase)
            % BACKWARD COMPATIBILITY, ASSERTED AGAINST A FILE THAT PREDATES
            % THE CHANGE. test/fixtures/arc.eopi was written by an earlier
            % revision with six channels, and it is the only end-to-end
            % evidence that the C API reads what MATLAB wrote. P19c adds a
            % seventh; if that had invalidated the fixture the format change
            % would have destroyed the check while claiming to extend it.
            %
            % The old interpolant keeps working on its own: it carries the six
            % channels the rotation reads, so no series is passed.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            file = fullfile(testCase.toolboxRoot(), 'test', 'fixtures', 'arc.eopi');
            testCase.assumeTrue(isfile(file), 'arc.eopi is not present.');

            old = referenceSystem.readInterpolant(string(file));
            testCase.verifyEqual(numel(old.quantity), 6, ...
                'The committed fixture is a six-channel format 1 file.');

            query = referenceSystem.daySecondToEpoch([57754 3600], "UTC");
            [R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(query, ...
                'Interpolant', old);
            testCase.verifyEqual(info.path, "interpolated");
            testCase.verifyTrue(all(isfinite([R(:); Rdot(:)])), ...
                'A format-1 interpolant must still give a finite rotation and rate.');
        end

        function rotationItrsToGcrs_contract_refusesASampleInsideALeapSecond(testCase)
            % 23:59:60 HAS NO MJD, AND THE PANELS ARE INDEXED BY MJD (rev.
            % 1.226). Read from the next panel, a sample inside the leap second
            % is one second late: measured at 23:59:60.5 on 2017-01-01 that is
            % 4.5e-12 on R but 3.3e-16 1/s on Rdot, over the 1 nm/s budget. So
            % the interpolated path refuses it - as the epoch itself, and as a
            % difference shoulder - while the direct path, which takes the epoch
            % struct rather than an MJD, is asserted to accept the same instant.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            interpolant = referenceSystem.earthOrientationInterpolant( ...
                referenceSystem.daySecondToEpoch([57752 0; 57756 0], "UTC"), 'Eop', eop);
            inside = referenceSystem.daySecondToEpoch([57753 86400.5], "UTC");
            shoulderInside = referenceSystem.daySecondToEpoch([57753 86200.5], "UTC");
            clearOfIt = referenceSystem.daySecondToEpoch([57753 86199.5], "UTC");

            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs(inside, ...
                'Interpolant', interpolant), ...
                'referenceSystem:rotationItrsToGcrs:insideLeapSecond');
            % The shoulders exist only when Rdot is requested; hence the helper.
            testCase.verifyError(@() localInterpolatedRate(shoulderInside, ...
                interpolant, 200), ...
                'referenceSystem:rotationItrsToGcrs:insideLeapSecond');
            [~, rateClearOfIt] = localInterpolatedRate(clearOfIt, interpolant, 200);
            testCase.verifySize(rateClearOfIt, [3 3], ...
                'One second earlier the shoulder is clear of the leap second.');
            % Accepted here; directPathTurnsOnceThroughALeapSecond holds the
            % value to SI time, which this size check could not (rev. 1.235).
            testCase.verifySize(referenceSystem.rotationItrsToGcrs(inside, 'Eop', eop), ...
                [3 3], 'The direct path takes the leap second like any other epoch.');
        end

        function rotationItrsToGcrs_contract_cApiRateFixtureIsCurrent(testCase)
            % THE C API'S RATE TRUTH MUST STILL BE WHAT MATLAB COMPUTES (rev.
            % 1.222). test/c/testApi.c holds rsApiRotationRate to
            % test/fixtures/arcFormat2Rate.csv, because the C-only truths share
            % the rate construction of rsCore and cannot see it differ from
            % MATLAB's. That file is a truth only while this function still
            % produces it, so this test recomputes it from the committed
            % arcFormat2.eopi. A failure here
            % means the interpolated rotation or rate changed: decide which
            % side is right and regenerate the CSV as its header says, rather
            % than widening these bounds (obligation O8).
            %
            % Bounds as in the C test: P19c's 5e-12 on R, and on Rdot D28's
            % 1 nm/s at 7000 km, 1.43e-16 1/s (rev. 1.223, H.11 item 5), with h
            % read from the fixture (O33).
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            folder = fullfile(testCase.toolboxRoot(), 'test', 'fixtures');
            text = string(fileread(fullfile(folder, 'arcFormat2Rate.csv')));
            lines = splitlines(strtrim(text));
            stepLine = lines(startsWith(lines, "step "));
            testCase.assertNumElements(stepLine, 1, 'The rate fixture names no step.');
            step = str2double(extractAfter(stepLine, "step "));
            rows = str2double(split(lines(~startsWith(lines, ["#", "step"])), ","));
            % 32 rows since rev. 1.226: eight about the 2017-01-01 leap second,
            % then the 24 of the P19c arc.
            testCase.assertSize(rows, [32, 19], 'The rate fixture lost rows or columns.');

            interpolant = referenceSystem.readInterpolant( ...
                string(fullfile(folder, 'arcFormat2.eopi')));
            mjd = rows(:, 1);
            epoch = referenceSystem.daySecondToEpoch( ...
                [floor(mjd), (mjd - floor(mjd)) * 86400], "UTC");
            [R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(epoch, ...
                'Interpolant', interpolant, 'DifferenceStep', step);

            testCase.verifyEqual(info.path, "interpolated");
            expectedR = reshape(rows(:, 2:10)', 3, 3, []);
            expectedRdot = reshape(rows(:, 11:19)', 3, 3, []);
            testCase.log(1, sprintf(['C API rate fixture: max|dR| %.3g, ', ...
                'max|dRdot| %.3g 1/s at h = %g s'], max(abs(R - expectedR), [], 'all'), ...
                max(abs(Rdot - expectedRdot), [], 'all'), info.differenceStep));
            testCase.verifyEqual(R, expectedR, 'AbsTol', 5e-12);
            testCase.verifyEqual(Rdot, expectedRdot, 'AbsTol', ...
                TestRotation.VelocityBudget / TestRotation.OrbitRadius);
        end

        function rotationItrsToGcrs_contract_cApiDaySecondFixtureIsCurrent(testCase)
            % THE SAME CONTRACT FOR THE C API'S DAY-AND-SECOND FORM (rev. 1.236).
            % test/c/testApi.c holds rsApiRotationRateDaySecond to
            % test/fixtures/arcFormat2DaySecond.csv, which is this function at
            % a day and a second: seconds an MJD double cannot name, and six
            % epochs about the 2017-01-01 leap second, one of them 0.2 us before
            % 23:59:60. Recomputed here from the committed arcFormat2.eopi, so a
            % change on either side fails a test on that side. Regenerate the
            % CSV as its header says, rather than widening these bounds (O8).
            %
            % Bounds as in cApiRateFixtureIsCurrent. Measured when written: 0
            % and 0 in MATLAB, and in C.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            folder = fullfile(testCase.toolboxRoot(), 'test', 'fixtures');
            text = string(fileread(fullfile(folder, 'arcFormat2DaySecond.csv')));
            lines = splitlines(strtrim(text));
            stepLine = lines(startsWith(lines, "step "));
            testCase.assertNumElements(stepLine, 1, 'The fixture names no step.');
            step = str2double(extractAfter(stepLine, "step "));
            rows = str2double(split(lines(~startsWith(lines, ["#", "step"])), ","));
            testCase.assertSize(rows, [21, 20], 'The fixture lost rows or columns.');

            interpolant = referenceSystem.readInterpolant( ...
                string(fullfile(folder, 'arcFormat2.eopi')));
            epoch = referenceSystem.daySecondToEpoch(rows(:, 1:2), "UTC");
            [R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(epoch, ...
                'Interpolant', interpolant, 'DifferenceStep', step);

            testCase.verifyEqual(info.path, "interpolated");
            expectedR = reshape(rows(:, 3:11)', 3, 3, []);
            expectedRdot = reshape(rows(:, 12:20)', 3, 3, []);
            testCase.log(1, sprintf(['C API day-and-second fixture: max|dR| %.3g, ', ...
                'max|dRdot| %.3g 1/s at h = %g s'], max(abs(R - expectedR), [], 'all'), ...
                max(abs(Rdot - expectedRdot), [], 'all'), info.differenceStep));
            testCase.verifyEqual(R, expectedR, 'AbsTol', 5e-12);
            testCase.verifyEqual(Rdot, expectedRdot, 'AbsTol', ...
                TestRotation.VelocityBudget / TestRotation.OrbitRadius);
        end

        function rotationItrsToGcrsPartials_contract_eopIsRequired(testCase)
            % The same refusal rotationItrsToGcrs makes, for the same reason:
            % a Jacobian built from zero EOP is as plausible and as wrong as a
            % rotation built from zero EOP.
            testCase.verifyError( ...
                @() referenceSystem.rotationItrsToGcrsPartials( ...
                testCase.cookbookUtc()), ...
                'referenceSystem:rotationItrsToGcrsPartials:eopRequired');
        end

        function rotationItrsToGcrsPartials_contract_shapeAndInfoFields(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            epoch = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 4, 1), (0:3)'*3600], "UTC");

            [dXp, dYp, dUt1, info] = ...
                referenceSystem.rotationItrsToGcrsPartials(epoch, 'Eop', eop);

            testCase.verifySize(dXp, [3 3 4]);
            testCase.verifySize(dYp, [3 3 4]);
            testCase.verifySize(dUt1, [3 3 4]);
            testCase.verifyEqual(sort(string(fieldnames(info))), ...
                sort(["cipModel"; "differenceStep"; "rateConstruction"; ...
                "polarMotionUnits"]));
            testCase.verifyEqual(info.polarMotionUnits, "radian", ...
                'A factor of 206265 in a Jacobian is invisible in the answer.');
            testCase.verifyTrue(isnan(info.differenceStep), ...
                'No rate partials were asked for, so no step was used.');
        end

        function rotationItrsToGcrsPartials_contract_ratePartialsAreGatedByNargout(testCase)
            % Design principle 15: the three analytic partials are nearly free
            % and the three rate partials each cost two more evaluations, so
            % asking for four outputs must be the thing that pays for them.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            epoch = testCase.cookbookUtc();

            [~, ~, ~, info, dRdotdXp, dRdotdYp, dRdotdUt1] = ...
                referenceSystem.rotationItrsToGcrsPartials(epoch, 'Eop', eop);

            testCase.verifySize(dRdotdXp, [3 3 1]);
            testCase.verifySize(dRdotdYp, [3 3 1]);
            testCase.verifySize(dRdotdUt1, [3 3 1]);
            testCase.verifyEqual(info.differenceStep, 200, ...
                ['D112: the default half-offset is the D28 optimum ', ...
                'rotationItrsToGcrs itself uses, not a third number.']);
            testCase.verifySubstring(char(info.rateConstruction), ...
                'difference of two analytic partials', ...
                'D102 chose an order and info must record which.');
        end


        function readInterpolant_contract_refusesWhatItCannotTrust(testCase)
            % Three ways a file can be wrong, and all three are refused rather
            % than read hopefully. The truncation case is the one that matters:
            % a reader that padded or reshaped whatever it found would produce
            % coefficients that are plausible and wrong.
            folder = tempname();
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's'));

            testCase.verifyError(@() referenceSystem.readInterpolant( ...
                fullfile(folder, "absent.eopi")), ...
                'referenceSystem:readInterpolant:cannotOpen');

            % VERSION 2 IS NOW A FORMAT THIS READER KNOWS (P19c), so the
            % unknown-version case must name a version that does not exist.
            % Leaving it at 2 would have turned a guard into a test that
            % asserts the reader cannot read its own current output.
            wrongVersion = fullfile(folder, "v9.eopi");
            fileId = fopen(wrongVersion, 'w');
            fprintf(fileId, 'referenceSystemInterpolant 9\ndegree 20\n');
            fclose(fileId);
            testCase.verifyError(@() referenceSystem.readInterpolant( ...
                wrongVersion), 'referenceSystem:readInterpolant:badFormat');

            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
            good = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
            full = fullfile(folder, "full.eopi");
            referenceSystem.writeInterpolant(good, full);

            truncated = fullfile(folder, "short.eopi");
            line = splitlines(strtrim(fileread(full)));
            fileId = fopen(truncated, 'w');
            fprintf(fileId, '%s\n', line{1:end-3});
            fclose(fileId);
            testCase.verifyError(@() referenceSystem.readInterpolant( ...
                truncated), 'referenceSystem:readInterpolant:badFormat');

            testCase.verifyError(@() referenceSystem.writeInterpolant( ...
                struct('degree', 20), fullfile(folder, "x.eopi")), ...
                'referenceSystem:writeInterpolant:badInterpolant');
        end

        function earthOrientationPartials_contract_refusesAMismatchedRotation(testCase)
            % A rotation from a different arc gives partials that are each
            % well-formed and collectively meaningless, and nothing downstream
            % would notice. The size is the only handle available, so it is
            % checked rather than trusted.
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 0; 57754 3600], "UTC");
            testCase.verifyError(@() referenceSystem.earthOrientationPartials( ...
                utc, 'Eop', eop, 'Rotation', zeros(3, 3, 5)), ...
                'referenceSystem:earthOrientationPartials:sizeMismatch');
        end

        function cipCoordinates_contract_refusesANonTtEpoch(testCase)
            utc = referenceSystem.daySecondToEpoch([54195 43200], "UTC");
            testCase.verifyError(@() referenceSystem.cipCoordinates(utc), ...
                'referenceSystem:cipCoordinates:wrongScale');
        end

        function cipCoordinates_contract_refusesOffsetsWithoutAModel(testCase)
            % The C-2 failure mode made unreachable: offsets whose frame is
            % unknown are refused rather than assumed.
            tt = testCase.cookbookTt();
            testCase.verifyError(@() referenceSystem.cipCoordinates(tt, ...
                'DeltaX', 1e-9), ...
                'referenceSystem:cipCoordinates:cipModelRequired');
        end

        function cipCoordinates_contract_refusesAnUnknownModel(testCase)
            tt = testCase.cookbookTt();
            testCase.verifyError(@() referenceSystem.cipCoordinates(tt, ...
                'DeltaX', 1e-9, 'CipModel', "IAU1980"), ...
                'referenceSystem:cipCoordinates:unknownCipModel');
        end

        function cipCoordinates_contract_refusesTwoOffsetSources(testCase)
            tt = testCase.cookbookTt();
            eop = struct('dX', 1e-9, 'dY', 0, ...
                'meta', struct('cipModel', "IAU2006/2000A"));
            testCase.verifyError(@() referenceSystem.cipCoordinates(tt, ...
                'Eop', eop, 'DeltaX', 2e-9), ...
                'referenceSystem:cipCoordinates:conflictingOffsets');
        end

        function rotationItrsToGcrs_contract_twoOutputsBindAMatrix(testCase)
            % SEAM ITEM 3, and the exact regression decision D25 exists to
            % prevent: revisions 1.18 to 1.22 put the fundamental arguments in
            % output slot 2, so [R, Rdot] silently bound a struct to Rdot and
            % failed three functions later inside pagemtimes.
            [R, Rdot] = testCase.cookbookRotation(2);

            testCase.verifyClass(Rdot, 'double', ...
                'Output 2 must be the first derivative, never a struct.');
            testCase.verifySize(Rdot, size(R));
            testCase.verifyEqual(size(Rdot, 1), 3);
            testCase.verifyEqual(size(Rdot, 2), 3);
        end

        function rotationItrsToGcrs_contract_reportsTheDirectPath(testCase)
            % Seam item 2.
            [~, ~, ~, info] = testCase.cookbookRotation(4);

            testCase.verifyEqual(info.path, "direct");
            testCase.verifyEqual(info.derivativeMethod, "centralDifference");
            testCase.verifyEqual(info.differenceStep, 200);
            testCase.verifyEqual(info.cipModel, "IAU2006/2000A");
            testCase.verifyEqual(info.epochCount, 1);
            testCase.verifyTrue(isnan(info.interpolantResidual));
        end

        function rotationItrsToGcrs_contract_infoTellsTheTruthAboutNargout(testCase)
            % A TILDE IS A REQUEST. [R, ~, ~, info] reports nargout = 4, so the
            % derivatives ARE computed and info correctly says
            % centralDifference. The first version of this test asserted
            % "none" for that call and failed - the function was honest and the
            % test was asserting a fiction about MATLAB.
            % Four outputs, because the helper returns four. Asking for two
            % here bound Rdot to a variable named info and the test errored
            % rather than failed - the same shape as the D25 regression this
            % file exists to guard, committed in the test itself.
            [R, ~, ~, info] = testCase.cookbookRotationWithInfo(-1);

            testCase.verifySize(R, [3 3]);
            testCase.verifyEqual(info.derivativeMethod, "centralDifference", ...
                'A discarded output is still a requested output.');
        end

        function rotationItrsToGcrs_contract_derivativesOverridesNargout(testCase)
            % What the failure above exposed is a real cost, not just a wrong
            % expectation: without an override, asking for the diagnostics
            % always pays for two derivatives. 'Derivatives' makes the cheap
            % call expressible, and the outputs it suppresses come back EMPTY
            % rather than as a plausible array of the right size.
            [R, Rdot, Rddot, info] = testCase.cookbookRotationWithInfo(0);

            testCase.verifySize(R, [3 3]);
            testCase.verifyEmpty(Rdot, ...
                'A derivative that was not computed must be empty.');
            testCase.verifyEmpty(Rddot);
            testCase.verifyEqual(info.derivativeMethod, "none");
            testCase.verifyTrue(isnan(info.differenceStep));
        end

        function rotationItrsToGcrs_contract_rejectsANonInterpolantStruct(testCase)
            % THIS TEST GUARDED THE RESERVED SEAM UNTIL REV. 1.97, asserting
            % notImplemented. The seam is now live, so what it has to guard
            % instead is the case it always really covered: a struct that is
            % not an interpolant. The identifier changes from notImplemented to
            % badInterpolant and the call it makes is unchanged, which is the
            % point of having reserved the name-value pair two sessions early.
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");
            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs(utc, ...
                'Eop', eop, 'Interpolant', struct('dummy', 1)), ...
                'referenceSystem:rotationItrsToGcrs:badInterpolant');
        end

        function rotationItrsToGcrs_contract_requiresAnEopSource(testCase)
            % No zero fallback: a rotation built from zero EOP is wrong by
            % metres at the surface and looks entirely healthy.
            utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");
            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs(utc), ...
                'referenceSystem:rotationItrsToGcrs:eopRequired');
        end

        function rotationItrsToGcrs_contract_refusesAZeroStep(testCase)
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");
            testCase.verifyError(@() localTwoOutputs(utc, eop, 0), ...
                'referenceSystem:rotationItrsToGcrs:badDifferenceStep');
        end

        function rotationItrsToGcrs_contract_rowsLayoutIsNineColumns(testCase)
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch( ...
                [57754 0; 57754 3600; 57755 0], "UTC");
            R = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop, ...
                'Layout', "rows");

            testCase.verifySize(R, [3 9]);
        end

        function applyRotation_contract_refusesAnOddArgumentCount(testCase)
            testCase.verifyError(@() localThreeArgumentCall(eye(3)), ...
                'referenceSystem:applyRotation:wrongArgumentCount');
        end

        function applyRotation_contract_refusesAnNbyThreeState(testCase)
            % The columns are the vectors. An Nx3 array is the transpose of
            % what pagemtimes multiplies.
            testCase.verifyError(@() referenceSystem.applyRotation(eye(3), ...
                zeros(4, 3)), 'referenceSystem:applyRotation:wrongVectorSize');
        end

        function applyRotation_contract_acceptsTheInverseNameValue(testCase)
            % This is the one place in the toolbox where MATLAB must separate
            % optional positional arguments from a name-value pair. Asserting
            % it means the platform behaviour is measured rather than assumed
            % (handover obligation O9).
            R = referenceSystem.rotationGcrsToCirs(1e-3, 2e-5, -1e-8);
            r = [4.2e6; -3.1e6; 5.7e6];

            forward = referenceSystem.applyRotation(R, r);
            back = referenceSystem.applyRotation(R, forward, 'Inverse', true);

            % Asserted on the NORM of the residual, not element by element. A
            % relative tolerance is undefined where the expected value is
            % exactly zero, and the first two runs of this test used
            % r = [7e6; 0; 0], which has two such components: the rotation put
            % about 1e-10 m into each, verifyEqual read that as an infinite
            % relative error, and the test failed while the function was
            % correct. The state vector now has no zero component either, so
            % all three axes are exercised.
            testCase.verifyLessThan(norm(back - r) / norm(r), 1e-14, ...
                'A round trip through Inverse must return the input.');
        end

        function invertRotation_contract_verifyIsOffByDefault(testCase)
            % The orthogonality check costs a page product per call and the
            % toolbox's own rotations are orthogonal by construction, so it
            % must not run unless asked.
            notARotation = 2 * eye(3);

            testCase.verifyWarningFree( ...
                @() referenceSystem.invertRotation(notARotation));
            testCase.verifyError(@() referenceSystem.invertRotation( ...
                notARotation, 'Verify', true), ...
                'referenceSystem:invertRotation:notOrthogonal');
        end

    end

    methods (Test, TestTags = {'reference'})

        function rotationItrsToGcrsPartials_reference_matchDifferencedRotations(testCase)
            % THE ORACLE P20's PROMPT ASKS FOR, AND THE ONLY ONE WORTH HAVING.
            % Each partial is compared against a central difference of
            % rotationItrsToGcrs with THE EOP SERIES ITSELF PERTURBED - not
            % against a second analytic expression, which would only confirm
            % that two copies of my algebra agree.
            %
            % Perturbing the series rather than the sampled value matters: it
            % drives the same interpolation the rotation uses, so anything the
            % sampling does to xp - tidal corrections, unit handling - is
            % inside the comparison rather than bypassed by it.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            epoch = testCase.cookbookUtc();

            [dXp, dYp, dUt1] = referenceSystem.rotationItrsToGcrsPartials( ...
                epoch, 'Eop', eop);

            % Steps chosen so the perturbation is far above roundoff on the
            % quantity and far below any nonlinearity: 1e-8 rad is about 2 mas
            % of polar motion, 1e-3 s is a millisecond of Delta UT1.
            poleStep = 1e-8;
            timeStep = 1e-3;

            differenced = @(field, step) ...
                (testCase.rotationWithPerturbedEop(epoch, eop, field, step) - ...
                testCase.rotationWithPerturbedEop(epoch, eop, field, -step)) / ...
                (2*step);

            % RelTol 1e-6 against the LARGEST element of each partial, because
            % some elements are near zero and a relative test on those measures
            % cancellation. The bound is the central difference's own
            % truncation at these steps, not a property of the algebra.
            testCase.verifyEqual(differenced("xp", poleStep), dXp, ...
                'AbsTol', 1e-6*max(abs(dXp), [], 'all'), ...
                'd R / d xp disagrees with a differenced rotation.');
            testCase.verifyEqual(differenced("yp", poleStep), dYp, ...
                'AbsTol', 1e-6*max(abs(dYp), [], 'all'), ...
                'd R / d yp disagrees with a differenced rotation.');
            testCase.verifyEqual(differenced("dut1", timeStep), dUt1, ...
                'AbsTol', 1e-6*max(abs(dUt1), [], 'all'), ...
                'd R / d Delta UT1 disagrees with a differenced rotation.');

            % THE PROMPT ASKS FOR THE ACHIEVED FIGURE AND A PASSING TEST HIDES
            % IT. P20 says "agreement to ~1e-8 relative; state the achieved
            % figure", and a verifyEqual that succeeds leaves no trace of the
            % number it checked - the same defect as the P19 arc ratio at
            % rev. 1.155. The three agreements are logged into the D28 block so
            % the report carries them.
            %
            % STATUS IS "roundoff-limited" AND NOT "asserted", BECAUSE THAT IS
            % WHAT THIS IS. The oracle's own floor is eps/delta: at a 1e-8 rad
            % perturbation that is 2.2e-8 relative, so THE PROMPT'S ~1e-8
            % FIGURE IS THE LIMIT OF ITS OWN ORACLE and not an accuracy of the
            % partials. Sweeping the perturbation would show order -1, not +2.
            % Labelling it "asserted" would repeat the Rdot mislabel rev. 1.151
            % had to correct.
            achieved = [ ...
                max(abs(differenced("xp", poleStep) - dXp), [], 'all')/ ...
                    max(abs(dXp), [], 'all'), ...
                max(abs(differenced("yp", poleStep) - dYp), [], 'all')/ ...
                    max(abs(dYp), [], 'all'), ...
                max(abs(differenced("dut1", timeStep) - dUt1), [], 'all')/ ...
                    max(abs(dUt1), [], 'all')];
            name = ["dR/dxp", "dR/dyp", "dR/dDeltaUT1"];
            perturbation = [poleStep, poleStep, timeStep];
            for k = 1:3
                testCase.log(1, TestPerformance.convergenceRecord( ...
                    name(k), perturbation(k), achieved(k), NaN, ...
                    "roundoff-limited"));
            end
        end


        function cipCoordinates_reference_reproducesTheCookbookIau2006(testCase)
            % 5e-15 rad is 1.0 microarcsecond and bounds this evaluation of the IAU 2006/2000A
            % series against the cookbook's printed value, which stops at 15 digits. Measured
            % 9.0e-17 in X and 2.9e-16 in Y, so the bound is the PRINTING and not the model.
            [X, Y] = testCase.cookbookCip("IAU2006/2000A");

            testCase.verifyEqual(X, TestRotation.CookbookX, 'AbsTol', 5e-15);
            testCase.verifyEqual(Y, TestRotation.CookbookY, 'AbsTol', 5e-15);
        end

        function cipCoordinates_reference_reproducesTheCookbookIau2000(testCase)
            % The IAU 2000A branch against the cookbook's OWN section 5.3
            % literals, not against section 5.5. Using one literal for both
            % branches would make the C-2 statement untestable.
            [X, Y] = testCase.cookbookCip("IAU2000A");

            testCase.verifyEqual(X, TestRotation.CookbookX2000, 'AbsTol', 5e-15);
            testCase.verifyEqual(Y, TestRotation.CookbookY2000, 'AbsTol', 5e-15);
        end

        function rotationItrsToGcrs_reference_reproducesTheCookbookMatrix(testCase)
            % 5e-15 bounds the accumulation of the three-factor product against the cookbook's
            % printed matrix, whose own digits stop near 1e-15. Measured 2.6e-15, which is
            % 5e-04 microarcseconds.
            R = testCase.cookbookRotation(1);

            testCase.verifyEqual(R', TestRotation.CookbookGcrsToItrs, ...
                'AbsTol', 5e-15, ...
                'The assembled rotation must reproduce cookbook section 5.5.');
        end

        function earthRotationAngle_reference_reproducesTheCookbookEra(testCase)
            % 1e-11 degrees is 3.6e-08 arcseconds and bounds the printed precision of the
            % cookbook's ERA rather than any model error; measured 5.9e-13 degrees.
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second], "UT1");
            era = referenceSystem.earthRotationAngle(ut1);

            testCase.verifyEqual(rad2deg(era), 13.318492966097, 'AbsTol', 1e-11);
        end

        function earthRotationAngleRate_reference_isNotTheMeanRotationRate(testCase)
            % Decision D63. The two constants differ by a relative 2.0e-8,
            % which is 10.3 micrometres per second of co-rotation velocity at
            % 7000 km, above the length-of-day term this toolbox insists on
            % including. A test asserting only "about 7.29e-5" passes with
            % either and is therefore no test at all.
            rate = referenceSystem.earthRotationAngleRate();
            constants = referenceSystem.iersConstants();

            % THE VALUE IS LOGGED, BECAUSE THE HELP QUOTES IT (rev. 1.227, H.11
            % item 11). Until then both help blocks quoted 7.292115146705669e-5,
            % which is 1.31e-17 from the exact value and would fail the 1e-17
            % below - so it was a transcription, not a reading from any host
            % this suite passes on. The log is how each runner's reading reaches
            % the record.
            testCase.log(1, sprintf(['earthRotationAngleRate = %.16e rad/s, ', ...
                '%.3g from the defining 7.292115146706979e-5'], rate, ...
                rate - constants.eraRatePerUt1Second));
            testCase.verifyEqual(rate, 7.292115146706979e-5, 'AbsTol', 1e-17, ...
                'The rate must be the defining rate of advance of ERA.');
            testCase.verifyGreaterThan( ...
                abs(rate - constants.earthRotationRate) * 7e6, 1e-5, ...
                'The two constants must stay distinguishable by this test.');
        end

        function equinoxNutationMatrix_reference_isOrthogonal(testCase)
            npb = referenceSystem.equinoxNutationMatrix(testCase.cookbookTt());

            testCase.verifyLessThan( ...
                max(abs(npb' * npb - eye(3)), [], 'all'), 1e-15);
        end

    end

    methods (Test, TestTags = {'precision'})

        function rotationItrsToGcrsPartials_precision_deltaUt1OracleSweep(testCase)
            % OPEN ITEM A1, AND THE INSTRUMENT THAT SETTLES IT RATHER THAN AN
            % ASSERTION THAT HIDES IT. Run 67 reported dR/dDeltaUT1 agreeing
            % with its central-difference oracle to 1.66e-7, against 4.8e-9 and
            % 1.9e-9 for the two polar-motion partials, and it passed only
            % because the bound (1e-6) is looser than P20's stated ~1e-8. One
            % number at one perturbation cannot say which of two things it is.
            %
            % THE DISCRIMINANT IS THE SLOPE, NOT THE VALUE. A central
            % difference carries a truncation error of (delta^2/6)*|f'''| and a
            % cancellation error of about eps*|f|/delta. Here f is a rotation
            % matrix and f''' = omega^3*G^3*R, so at delta = 0.1 s the
            % truncation is (delta^2/6)*omega^2 = 8.9e-12 RELATIVE - eleven
            % orders below the reported figure and negligible at every step
            % swept. Whatever is being measured is therefore either
            %
            %   a roundoff floor       error proportional to 1/delta, slope -1
            %   a model inconsistency  error independent of delta, slope  0
            %
            % and four decades of sweep separate them with a factor of 1e4.
            %
            % THE ASSERTION IS THE HYPOTHESIS, WHICH IS THE POINT. If the slope
            % comes out near -1 this closes A1 as an artefact of the oracle and
            % identifies the floor constant, which is NOT the eps(R)/DeltaR
            % estimate of 3.0e-9 the register worked from - that estimate
            % predicts 1.66e-10*(1e-3/delta) and the sweep will say so. If the
            % slope comes out near 0 the test fails and the failure IS the
            % finding: a delta-independent inconsistency in the analytic
            % partial at the 1.66e-7 level. A test that could only pass would
            % not have been worth writing.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            epoch = testCase.cookbookUtc();

            [~, ~, dUt1] = referenceSystem.rotationItrsToGcrsPartials( ...
                epoch, 'Eop', eop);
            scale = max(abs(dUt1), [], 'all');

            timeStep = [1e-1; 1e-2; 1e-3; 1e-4; 1e-5];
            achieved = zeros(size(timeStep));
            for k = 1:numel(timeStep)
                differenced = (testCase.rotationWithPerturbedEop(epoch, eop, ...
                    "dut1", timeStep(k)) - ...
                    testCase.rotationWithPerturbedEop(epoch, eop, ...
                    "dut1", -timeStep(k))) / (2*timeStep(k));
                achieved(k) = max(abs(differenced - dUt1), [], 'all')/scale;
            end

            % EVERY POINT IS REPORTED, PASS OR FAIL. The row at 1e-3 is the one
            % run 67 logged, so the report carries the sweep and the number it
            % is explaining side by side, and the "floor" column - achieved
            % times delta - is CONSTANT if and only if the 1/delta law holds.
            % That column is the useful one: it is the floor constant itself,
            % which is what a later revision needs and what no single point
            % could give.
            for k = 1:numel(timeStep)
                testCase.log(1, TestPerformance.convergenceRecord( ...
                    "dR/dDeltaUT1 sweep", timeStep(k), achieved(k), NaN, ...
                    sprintf("floor %.3e", achieved(k)*timeStep(k))));
            end

            % Least squares slope of log10(achieved) on log10(delta). Fitted
            % over the whole sweep rather than taken from the endpoints,
            % because a single anomalous point at either end would otherwise
            % set the verdict on its own.
            logStep = log10(timeStep);
            logError = log10(achieved);
            slope = (logStep - mean(logStep))'*(logError - mean(logError))/ ...
                sum((logStep - mean(logStep)).^2);

            testCase.verifyLessThan(slope, -0.5, sprintf( ...
                ['dR/dDeltaUT1 sweep slope %.3f over delta = 1e-1 ... 1e-5 s. ', ...
                'A slope near -1 is the oracle''s own roundoff floor and ', ...
                'closes open item A1; a slope near 0 is a delta-INDEPENDENT ', ...
                'inconsistency in the analytic partial and A1 becomes a ', ...
                'defect. Truncation is 8.9e-12 relative at the largest step ', ...
                'and cannot be the cause either way. Achieved: %s'], slope, ...
                sprintf('%.3e ', achieved)));

            % The largest step is the one a model error cannot survive: it is
            % where the floor is smallest, so a residual that is still at the
            % 1.66e-7 level there is not roundoff. Asserted separately from the
            % slope because the two fail for different reasons and a reader
            % should not have to work out which.
            testCase.verifyLessThan(achieved(1), 1e-8, sprintf( ...
                ['At delta = 0.1 s the oracle floor is a hundredth of its ', ...
                'value at 1e-3 s, so %.3e here means the disagreement does ', ...
                'not scale away and is in the partial, not the oracle.'], ...
                achieved(1)));
        end

        function rotationItrsToGcrsPartials_precision_ratePartialFollowsD102(testCase)
            % D102 SAYS WHICH ORDER, AND THIS ASSERTS THAT ORDER WAS TAKEN.
            % dRdot/dp is the DIFFERENCE OF TWO ANALYTIC PARTIALS, so it must
            % reproduce exactly what differencing the partials by hand gives -
            % to roundoff, not to the differencing error, because it IS that
            % difference. The other order would agree only to O(h^2), so this
            % test distinguishes the two constructions rather than merely
            % checking a number is small.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            epoch = testCase.cookbookUtc();
            step = 600;

            [~, ~, ~, ~, dRdotdXp] = ...
                referenceSystem.rotationItrsToGcrsPartials(epoch, 'Eop', eop, ...
                'DifferenceStep', step);

            % D112: DifferenceStep is the HALF-OFFSET h everywhere - samples
            % at t-h and t+h, divisor 2h - the same meaning it has in
            % rotationItrsToGcrs. Until rev. 1.184 both the function and this
            % mirror used t-h/2 with divisor h, so the pair agreed while the
            % option meant something different in the sibling function.
            before = referenceSystem.daySecondToEpoch( ...
                [epoch.day, epoch.sec - step], "UTC");
            after = referenceSystem.daySecondToEpoch( ...
                [epoch.day, epoch.sec + step], "UTC");
            dXpBefore = referenceSystem.rotationItrsToGcrsPartials(before, ...
                'Eop', eop);
            dXpAfter = referenceSystem.rotationItrsToGcrsPartials(after, ...
                'Eop', eop);
            expected = (dXpAfter - dXpBefore)/(2*step);

            % AbsTol 0 is legitimate: this is the same arithmetic, so anything
            % but bit equality means a different construction was used.
            testCase.verifyEqual(dRdotdXp, expected, 'AbsTol', 0, ...
                'The rate partial is not the difference of two analytic partials.');
        end


        function writeInterpolant_precision_roundTripIsBitIdentical(testCase)
            % PROMPT P19 SERIALISER. The claim is EXACTNESS, not closeness, so
            % the tolerance is AbsTol 0 - and that is legitimate here in a way
            % it rarely is: %.17g round-trips an IEEE-754 double exactly, no
            % arithmetic happens between writing and reading, and obligation
            % O13 does not apply because nothing goes through BLAS.
            %
            % A tolerance would have hidden the defect this test exists for. A
            % text format that lost one bit per coefficient would pass any
            % sensible RelTol and would surface, days later, as an integrator
            % whose orbit disagreed with the one that built the panels.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57756 0], "UTC");
            original = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);

            file = fullfile(tempname(), "arc.eopi");
            mkdir(fileparts(file));
            cleanup = onCleanup(@() rmdir(fileparts(file), 's'));
            referenceSystem.writeInterpolant(original, file);
            recovered = referenceSystem.readInterpolant(file);

            testCase.verifyEqual(recovered.coefficient, original.coefficient, ...
                'AbsTol', 0, 'A coefficient did not survive the round trip.');
            testCase.verifyEqual(recovered.panelStartMjd, ...
                original.panelStartMjd, 'AbsTol', 0);
            testCase.verifyEqual(recovered.taiMinusUtc, ...
                original.taiMinusUtc, 'AbsTol', 0);
            testCase.verifyEqual(recovered.degree, original.degree);
            testCase.verifyEqual(recovered.quantity, original.quantity);
            testCase.verifyEqual(recovered.meta.tidalCorrections, ...
                original.meta.tidalCorrections);

            % And the recovered panels must still evaluate. Comparing the
            % structs alone would pass if both were equally corrupt.
            mjd = original.panelStartMjd(1) + 0.31831;
            testCase.verifyEqual( ...
                referenceSystem.evaluateInterpolant(recovered, mjd, 1), ...
                referenceSystem.evaluateInterpolant(original, mjd, 1), ...
                'AbsTol', 0);
        end

        function earthOrientationPartials_precision_generatorsAreSkew(testCase)
            % The generator of a rotation is skew-symmetric, so dR/dp * R' must
            % be. This is a property the arithmetic cannot satisfy by accident
            % and it needs no external truth - which is what makes it worth
            % asserting alongside the finite-difference check, since the two
            % fail for different reasons.
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 12345], "UTC");
            rotation = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop);
            [dXp, dYp, dUt1, info] = referenceSystem.earthOrientationPartials( ...
                utc, 'Eop', eop, 'Rotation', rotation);

            testCase.verifyTrue(info.rotationSupplied);
            for partial = {dXp, dYp, dUt1}
                generator = partial{1} * rotation';
                % AbsTol 1e-15 is roundoff on a product of orthogonal matrices
                % whose elements are order one; obligation O13 applies because
                % this is a BLAS product, so exact zero is not claimed.
                testCase.verifyEqual(generator + generator', zeros(3), ...
                    'AbsTol', 1e-15);
            end
        end

        function cipCoordinates_precision_bothModelsReachTheSamePole(testCase)
            % SEAM ITEM 1, AND THE WHOLE OF FINDING C-2. The cookbook computed
            % its two offset pairs by differencing iauXys00a and iauXys06a at
            % this epoch, so they describe one physical pole in two frames. An
            % implementation that applies the model bias unconditionally, or
            % never, fails here by the size of that bias.
            [x2006, y2006] = testCase.cookbookCip("IAU2006/2000A");
            [x2000, y2000] = testCase.cookbookCip("IAU2000A");

            % 1.1e-13 rad is 0.023 microarcseconds and is the rounding of the
            % published offsets to four decimals of a milliarcsecond.
            testCase.verifyEqual(x2006, x2000, 'AbsTol', 3e-13);
            testCase.verifyEqual(y2006, y2000, 'AbsTol', 3e-13);
        end

        function cipCoordinates_precision_theBiasIsLargeEnoughToMatter(testCase)
            % The other half of C-2. If the two models agreed to within the
            % tolerance above, the test above would pass for a broken
            % implementation too, so the bias is measured and required to be
            % large. Measured at 2025: 121 uas in X and 135 uas in Y, which is
            % 4.2 mm at the Earth's surface.
            tt = referenceSystem.daySecondToEpoch([60676 0], "TT");
            scale = referenceSystem.iersConstants().arcsecondsToRadians;

            [x2006, y2006] = referenceSystem.cipCoordinates(tt, ...
                'DeltaX', 1e-9, 'DeltaY', 1e-9, 'CipModel', "IAU2006/2000A");
            [x2000, y2000] = referenceSystem.cipCoordinates(tt, ...
                'DeltaX', 1e-9, 'DeltaY', 1e-9, 'CipModel', "IAU2000A");

            biasX = abs(x2000 - x2006) / scale * 1e6;
            biasY = abs(y2000 - y2006) / scale * 1e6;

            testCase.log(1, "C-2 model bias at 2025: " + biasX + " uas in X, " ...
                + biasY + " uas in Y");
            testCase.verifyGreaterThan(biasX, 100, ...
                "X bias measured " + biasX + " uas, expected about 121.");
            testCase.verifyGreaterThan(biasY, 100, ...
                "Y bias measured " + biasY + " uas, expected about 135.");
        end

        function rotationItrsToGcrs_precision_isOrthogonal(testCase)
            % Seam item 6, first half. Holds independently of the step.
            [R, Rdot] = testCase.arcRotation();
            residual = pagemtimes(R, 'transpose', R, 'none') - eye(3);

            testCase.verifyLessThan(max(abs(residual), [], 'all'), 1e-15);
            testCase.verifyTrue(all(isfinite(Rdot), 'all'));
        end

        function rotationItrsToGcrs_precision_derivativeIsSkewConsistent(testCase)
            % SEAM ITEM 6, second half, and the sharpest test in this file.
            % d(R'R)/dt = Rdot'R + R'Rdot = 0 catches a sign error or a
            % transposition in Rdot that no magnitude comparison would, and it
            % holds for any step, so it separates a wrong derivative from a
            % merely imprecise one.
            [R, Rdot] = testCase.arcRotation();
            rate = TestPerformance.rotationRateSkewResidual(R, Rdot);

            testCase.verifyLessThan(max(abs(rate), [], 'all'), 1e-17);
        end

        function rotationItrsToGcrs_precision_matchesTheAnalyticEraTerm(testCase)
            % The dominant term of Rdot pinned against truth rather than
            % against another approximation. Rdot' R is the skew matrix of the
            % rotation vector, and for a rotation about the CIP its (2,1)
            % element is the Earth rotation rate, which is exact in closed
            % form. The finite-difference terms enter only as the small
            % deviations quoted in the tolerance below.
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");

            [R, Rdot] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop, ...
                'ApplyTidalCorrections', false);

            skew = Rdot' * R;
            recovered = abs(skew(2, 1));
            expected = referenceSystem.earthRotationAngleRate();

            testCase.verifyEqual(recovered, expected, 'RelTol', 1e-6, ...
                ['The dominant term of Rdot must be the analytic ERA rate. ', ...
                'The deviations are the length-of-day correction at 2.5e-8 ', ...
                'and the precession-nutation term at 9.3e-8 of it, so 1e-6 ', ...
                'leaves a factor ten of margin while a wrong formula would ', ...
                'be out by orders.']);
        end

        function rotationItrsToGcrs_precision_equinoxRouteAgrees(testCase)
            % SEAM ITEM 5, risk R13b. The classical equinox route and the CIO
            % route describe the same rotation and must agree. A test asset
            % only: there is no user-facing 'Formulation' option.
            %
            % Observed pole offsets are excluded deliberately. Converting them
            % between the dX/dY and dPsi/dEpsilon parameterisations is a
            % separate approximation already measured by readEop under
            % decision D56, and including it here would confuse a conversion
            % residual with a model inconsistency.
            day = (47892:1826:47892 + 11 * 1826)';
            second = repmat(43200, numel(day), 1);
            tt = referenceSystem.daySecondToEpoch([day second], "TT");
            ut1 = referenceSystem.daySecondToEpoch([day second], "UT1");

            [X, Y, s] = referenceSystem.cipCoordinates(tt);
            cioMatrix = referenceSystem.rotationGcrsToCirs(X, Y, s);
            npb = referenceSystem.equinoxNutationMatrix(tt);
            era = referenceSystem.earthRotationAngle(ut1);
            gast = referenceSystem.greenwichSiderealTime(ut1, tt, ...
                'Type', "apparent");

            worst = 0;
            for k = 1:numel(day)
                angle = -(era(k) - gast(k));
                rotation = [cos(angle) sin(angle) 0; ...
                    -sin(angle) cos(angle) 0; 0 0 1];
                worst = max(worst, max(abs( ...
                    rotation * npb(:,:,k) - cioMatrix(:,:,k)), [], 'all'));
            end

            testCase.log(1, "equinox versus CIO worst element " + worst + " rad");
            testCase.verifyLessThan(worst, 1e-14, ...
                'The equinox and CIO routes must agree at the arithmetic level.');
        end

        function applyRotation_precision_coriolisFactorIsTwo(testCase)
            % The classic error in this formula. A rotation about z at a
            % constant rate has a closed-form state transformation, so the
            % factor is checked against truth. With the factor wrong the
            % acceleration is out by roughly the Coriolis acceleration itself,
            % and every orthogonality check in this toolbox stays happy.
            omega = 7.292115e-5;
            theta = 0.7;
            R = [cos(theta) -sin(theta) 0; sin(theta) cos(theta) 0; 0 0 1];
            Rdot = omega * [-sin(theta) -cos(theta) 0; ...
                cos(theta) -sin(theta) 0; 0 0 0];
            Rddot = -omega^2 * [cos(theta) -sin(theta) 0; ...
                sin(theta) cos(theta) 0; 0 0 0];
            r = [7e6; 1e5; 3e5];
            v = [10; -7500; 200];
            a = [-8.0; 0.3; 0.1];

            [~, ~, a2] = referenceSystem.applyRotation(R, Rdot, Rddot, r, v, a);
            expected = R * a + 2 * Rdot * v + Rddot * r;
            wrongFactor = R * a + Rdot * v + Rddot * r;

            testCase.verifyEqual(a2, expected, 'RelTol', 1e-14);
            testCase.verifyGreaterThan(norm(a2 - wrongFactor), 0.5, ...
                'The two candidate formulas must be distinguishable here.');
        end

        function applyRotation_precision_roundTripReturnsTheState(testCase)
            [R, Rdot] = testCase.arcRotation();
            pageCount = size(R, 3);
            r = repmat([4.2e6; -3.1e6; 5.7e6], 1, pageCount);
            v = repmat([1.9e3; 6.8e3; -3.4e3], 1, pageCount);

            [r2, v2] = referenceSystem.applyRotation(R, Rdot, r, v);
            [r1, v1] = referenceSystem.applyRotation(R, Rdot, r2, v2, ...
                'Inverse', true);

            % Norms again, and for the same reason as
            % applyRotation_contract_acceptsTheInverseNameValue: the state
            % below is no longer axis-aligned, and the residual is judged as a
            % length rather than component by component.
            testCase.verifyLessThan(norm(r1 - r) / norm(r), 1e-14);
            testCase.verifyLessThan(norm(v1 - v) / norm(v), 1e-12);
        end

        function invertRotation_precision_transposeIsTheInverse(testCase)
            [R, Rdot] = testCase.arcRotation();
            [Rinv, RdotInv] = referenceSystem.invertRotation(R, Rdot);

            % 1e-15 is a few units in the last place of a three-term dot
            % product, which is what bounds this. The first run asserted
            % 1.2e-16, a figure measured for R'R at one epoch in C - a
            % different product over a different number of pages - and it
            % failed at the true value of 4.4e-16, that is 2 ulp. Obligation
            % O8: the bound must name the error that dominates it.
            product = pagemtimes(R, Rinv);
            testCase.verifyLessThan( ...
                max(abs(product - eye(3)), [], 'all'), 1e-15);
            testCase.verifyEqual(RdotInv, pagetranspose(Rdot), ...
                'A transposition must be exact, not merely close.');
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function rotationItrsToGcrsPartials_vectorization_arcMatchesSingleEpochs(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            arc = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 5, 1), (0:4)'*7200], "UTC");

            [arcXp, arcYp, arcUt1] = ...
                referenceSystem.rotationItrsToGcrsPartials(arc, 'Eop', eop);

            for k = 1:numel(arc.day)
                single = referenceSystem.daySecondToEpoch( ...
                    [arc.day(k) arc.sec(k)], "UTC");
                [oneXp, oneYp, oneUt1] = ...
                    referenceSystem.rotationItrsToGcrsPartials(single, ...
                    'Eop', eop);
                % AbsTol 0: no cross-epoch state exists, so an arc must be
                % bit-identical or the page assembly is indexing wrongly.
                testCase.verifyEqual(arcXp(:, :, k), oneXp, 'AbsTol', 0);
                testCase.verifyEqual(arcYp(:, :, k), oneYp, 'AbsTol', 0);
                testCase.verifyEqual(arcUt1(:, :, k), oneUt1, 'AbsTol', 0);
            end
        end


        function rotationItrsToGcrs_vectorization_arcMatchesEpochByEpoch(testCase)
            % 1e-15 is a few ulp of a rotation entry of order unity. THE 1e-20 IS BELOW ONE ULP
            % of an Rdot entry of order 7e-05, whose eps is 1.4e-20, so it is in effect a
            % bit-identity claim. It is sound because the arc and the single epoch run the
            % identical per-epoch C code with no reduction across epochs, and OpenMP is
            % asserted bit-reproducible by decision D31; it would not be sound across a
            % MATLAB-side pagemtimes (obligation O13).
            eop = testCase.cookbookEop();
            day = repmat(57754, 5, 1);
            second = (0:3600:4 * 3600)';
            arc = referenceSystem.daySecondToEpoch([day second], "UTC");

            [Rarc, RdotArc] = referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);

            for k = 1:5
                single = referenceSystem.daySecondToEpoch( ...
                    [day(k) second(k)], "UTC");
                [R, Rdot] = referenceSystem.rotationItrsToGcrs(single, ...
                    'Eop', eop);
                testCase.verifyEqual(Rarc(:,:,k), R, 'AbsTol', 1e-15, ...
                    "Epoch " + k + " of the arc differs from the same epoch " ...
                    + "computed alone.");
                testCase.verifyEqual(RdotArc(:,:,k), Rdot, 'AbsTol', 1e-20);
            end
        end

        function rotationItrsToGcrs_vectorization_singleEpochIsThreeByThree(testCase)
            % Section B.9: the N = 1 call pays no vectorised setup, and the
            % natural consequence is that MATLAB drops the trailing singleton
            % so the output is 3x3 and not 3x3x1.
            R = testCase.cookbookRotation(1);
            testCase.verifySize(R, [3 3]);
        end

        function applyRotation_vectorization_oneMatrixManyPoints(testCase)
            % 1e-14 relative bounds a three-term dot product of numbers of order unity against
            % the same product formed one column at a time. Not zero, because the batch goes
            % through pagemtimes and BLAS may block the larger operand differently (O13).
            R = referenceSystem.rotationGcrsToCirs(1e-3, 2e-5, -1e-8);
            r = [7e6 * ones(1, 100); linspace(0, 1e5, 100); zeros(1, 100)];

            rotated = referenceSystem.applyRotation(R, r);

            testCase.verifySize(rotated, [3 100]);
            testCase.verifyEqual(rotated(:, 7), R * r(:, 7), 'RelTol', 1e-14);
        end

        function applyRotation_vectorization_refusesAMismatchedCount(testCase)
            R = repmat(eye(3), 1, 1, 4);
            testCase.verifyError(@() referenceSystem.applyRotation(R, ...
                zeros(3, 7)), 'referenceSystem:applyRotation:sizeMismatch');
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function rotationItrsToGcrs_diagnostics_warnsOnceBeyondTheTable(testCase)
            % THIS TEST ASSERTS A WARNING, SO IT CONSUMES IT. The report lists
            % warnings nobody claimed, and an asserted warning is claimed.
            % Registered as a cleanup so it fires on pass, on failure and on a
            % filtered assumption alike. See WarningRecordingPlugin.
            consumeWarning = onCleanup(@() lastwarn('', ''));
            % Decision D62: one warning per call, naming this function rather
            % than leapSecondTable, which is not the function the user called.
            beyond = referenceSystem.leapSecondTable("validThroughDay") + 400;
            eop = testCase.syntheticEop(beyond);
            utc = referenceSystem.daySecondToEpoch( ...
                [beyond 0; beyond 3600], "UTC");

            testCase.verifyWarning(@() referenceSystem.rotationItrsToGcrs( ...
                utc, 'Eop', eop, 'ApplyTidalCorrections', false), ...
                'referenceSystem:rotationItrsToGcrs:dubiousYear');
        end

        function rotationItrsToGcrs_diagnostics_refusesAnUnknownCipModel(testCase)
            % Seam item 1: an EOP struct whose model is not recognised must
            % error, never silently produce a plausible-looking rotation.
            eop = testCase.cookbookEop();
            eop.meta.cipModel = "IAU1976";
            utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");

            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs(utc, ...
                'Eop', eop), ...
                'referenceSystem:rotationItrsToGcrs:unknownCipModel');
        end

        function rotationItrsToGcrs_diagnostics_neverPrints(testCase)
            % Library code does not print. The captured variables shadow
            % nothing, which is the revision 1.43 lesson: a test that captures
            % output must not itself generate any.
            % Used inside the evalc string below; the analyser cannot see through it.
            eopSeries = testCase.cookbookEop(); %#ok<NASGU>
            % Used inside the evalc string below; the analyser cannot see through it.
            utcEpoch = referenceSystem.daySecondToEpoch([57754 0], "UTC"); %#ok<NASGU>
            printed = evalc(['rotationValue = referenceSystem.' ...
                'rotationItrsToGcrs(utcEpoch, ''Eop'', eopSeries);']);

            testCase.verifyEmpty(strtrim(printed), ...
                "rotationItrsToGcrs printed: " + printed);
        end

        function applyRotation_diagnostics_recordsTheNameValueBinding(testCase)
            % The first run showed both 'Inverse' round trips returning the
            % FORWARD rotation, silently. The cause was the dispatch reading
            % nargin, which counts a name-value pair as two arguments; the
            % dispatch now reads which optional slots were filled instead and
            % is true under either counting rule.
            %
            % This test exists so that the next report answers the question
            % directly rather than by inference: it records both the option as
            % the function received it and the resulting rotation sense.
            R = referenceSystem.rotationGcrsToCirs(1e-3, 2e-5, -1e-8);
            r = [4.2e6; -3.1e6; 5.7e6];

            forward = referenceSystem.applyRotation(R, r);
            inverse = referenceSystem.applyRotation(R, r, 'Inverse', true);

            testCase.log(1, "applyRotation forward-inverse separation " + ...
                norm(forward - inverse) + " m");
            testCase.verifyGreaterThan(norm(forward - inverse), 1.0, ...
                ['The forward and inverse rotations of the same vector must ', ...
                'differ. Equal results mean the Inverse name-value never ', ...
                'reached the function.']);
            % Norm, per O12. This assertion passed with an axis-aligned state
            % only because R has nonzero off-diagonal elements, which is a
            % property of this particular rotation and not of the contract.
            testCase.verifyLessThan(norm(inverse - R' * r) / norm(r), 1e-14, ...
                'Inverse must apply the transpose.');
        end

        function rotationGcrsToCirs_diagnostics_refusesAMismatchedLength(testCase)
            testCase.verifyError(@() referenceSystem.rotationGcrsToCirs( ...
                [1e-3; 2e-3], [1e-5; 2e-5; 3e-5], 0), ...
                'referenceSystem:rotationGcrsToCirs:sizeMismatch');
        end

    end

    methods (Test, TestTags = {'convergence'})

        function rotationItrsToGcrs_convergence_stepRefinement(testCase)
            % SEAM ITEM 4, decision D28. The obvious test - comparing Rdot
            % against a central difference of R - is circular, because in
            % direct mode Rdot IS a central difference, so it passes for any
            % step including a badly chosen one. This sweep refines the step
            % against a Richardson-extrapolated reference instead and asserts
            % the O(h^2) region, which a circular test cannot do.
            %
            % Below about 300 s the comparison becomes reference-limited: the
            % session study measured the plain difference at 60 s as more
            % accurate than a two-point Richardson estimate, so the lower rows
            % are logged as observations and only the 600-to-300 ratio is
            % asserted as convergence.
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch([57754 43200], "UTC");
            stepList = [600, 300, 60, 10];

            reference = testCase.richardsonDerivative(utc, eop);
            errorList = zeros(size(stepList));

            for k = 1:numel(stepList)
                [~, Rdot] = referenceSystem.rotationItrsToGcrs(utc, ...
                    'Eop', eop, 'DifferenceStep', stepList(k), ...
                    'ApplyTidalCorrections', false);
                errorList(k) = max(abs(Rdot - reference), [], 'all');
            end

            for k = 1:numel(stepList)
                % THE STATUS MUST SAY WHICH ROWS ARE CLAIMS AND WHICH ARE
                % OBSERVATIONS. Every row below the first was logged as "ok",
                % including the 60 s and 10 s rows this test's own comment
                % calls reference-limited - so the report printed
                % "order -1.40 ... ok", which reads as a convergence result
                % and is not one. Their relative errors are around 1e-18,
                % below machine epsilon, so the order there is noise about a
                % floor rather than a rate. Only the 600-to-300 ratio is
                % asserted, and now only that row says so.
                if k == 1
                    order = NaN;
                    status = "baseline";
                elseif k == 2
                    order = log(errorList(k - 1) / errorList(k)) / ...
                        log(stepList(k - 1) / stepList(k));
                    status = "asserted";
                else
                    order = log(errorList(k - 1) / errorList(k)) / ...
                        log(stepList(k - 1) / stepList(k));
                    status = "reference-limited";
                end
                testCase.log(1, TestPerformance.convergenceRecord( ...
                    "Rdot", stepList(k), errorList(k), order, status));
            end

            ratio = errorList(1) / errorList(2);
            testCase.verifyGreaterThan(ratio, 3.0, ...
                "Refining 600 s to 300 s reduced the error by " + ratio + ...
                ", not the factor four that second-order convergence requires.");
            testCase.verifyLessThan(ratio, 5.0);
        end

    end

    methods (Test, TestTags = {'reference'})

        function earthOrientationPartials_reference_matchCentralDifferences(testCase)
            % PROMPT P20. The partials are compared against central differences
            % of rotationItrsToGcrs with the EOP SERIES PERTURBED - not against
            % a second analytic derivation, which would only assert that two
            % pieces of algebra agree. A sign error survives any check that
            % differentiates the same expression twice; it does not survive
            % this one.
            eop = testCase.cookbookEop();
            utc = referenceSystem.daySecondToEpoch( ...
                [57754 0; 57754 21600; 57754 43200], "UTC");

            [dXp, dYp, dUt1] = referenceSystem.earthOrientationPartials(utc, ...
                'Eop', eop);

            step = [1e-9, 1e-9, 1e-4];       % rad, rad, s
            field = ["xp", "yp", "dut1"];
            analytic = {dXp, dYp, dUt1};
            for k = 1:3
                ahead = eop;
                behind = eop;
                ahead.(field(k)) = ahead.(field(k)) + step(k);
                behind.(field(k)) = behind.(field(k)) - step(k);
                numerical = (referenceSystem.rotationItrsToGcrs(utc, 'Eop', ahead) ...
                    - referenceSystem.rotationItrsToGcrs(utc, 'Eop', behind)) ...
                    / (2 * step(k));

                % 1e-6 RELATIVE is the accuracy the constant-axis form claims
                % in ACCURACY, and the central difference contributes its own
                % truncation on top. Asserting relative rather than absolute
                % matters because dUt1 carries a factor of omega and is four
                % orders smaller than the other two.
                scale = max(abs(analytic{k}(:)));
                testCase.verifyLessThan( ...
                    max(abs(numerical(:) - analytic{k}(:))) / scale, 1e-5, ...
                    "Partial in " + field(k) + " disagrees with a central difference.");
            end
        end

        function rotationItrsToGcrs_reference_interpolatedMatchesDirect(testCase)
            % PROMPT P19b, AND THE FIRST CHECK THAT EXERCISES THE WHOLE CHAIN.
            % Everything before it tested a piece: the fit against the models,
            % the injected CIP against the model CIP, the gateway marshalling.
            % This one asks the question a user asks - does 'Interpolant' give
            % the same rotation as not passing it - across an arc that CROSSES
            % PANEL BOUNDARIES, because a per-epoch panel lookup that is off by
            % one is invisible inside a single panel. No series is passed
            % beside the panels: the interpolated path reads none.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57757 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);

            mjd = 57754.05 + (0:23)' * 0.125;      % three days, 24 epochs
            query = referenceSystem.daySecondToEpoch( ...
                [floor(mjd), (mjd - floor(mjd)) * 86400], "UTC");

            [direct, directDot, ~, directInfo] = ...
                referenceSystem.rotationItrsToGcrs(query, 'Eop', eop);
            [fitted, fittedDot, ~, fittedInfo] = ...
                referenceSystem.rotationItrsToGcrs(query, ...
                'Interpolant', interpolant);

            testCase.verifyEqual(directInfo.path, "direct");
            testCase.verifyEqual(fittedInfo.path, "interpolated");
            testCase.verifyLessThan(fittedInfo.interpolantResidual, 0.5);

            % R: 5e-12 on a direction cosine is 1.03 uas of angle (5e-12 x
            % 2.063e11 uas/rad; rev. 1.217 corrects "1e-3 uas", a factor of
            % 1000 out). It is P19c's accuracy requirement, and the term it
            % bounds is the error the panels add to the chain, which the
            % builder caps at 0.5 uas per fitted angle (Tolerance default).
            % Measured on this arc: 2.2e-16, ONE ULP - the roundoff of the
            % assembly dominates, not the fit (worst channel Y, 4.0e-5 uas,
            % is 2e-16 rad). Loose enough to survive a compiler; a panel chosen
            % one index wrong measured 3.9e-7, 7.7e4 times over.
            %
            % Rdot: NOT THE SAME NUMBER, BECAUSE A RATE IS NOT AN ANGLE, AND
            % SINCE REV. 1.223 NOT DERIVED FROM R AT ALL. Both paths difference
            % the samples at t-h and t+h, so a sample disagreement e reaches
            % Rdot as e/h: measured 5.5e-19 1/s against |dR(t+h) - dR(t-h)|/2h
            % = 5.6e-19, while omega*dR is 1.6e-20. D123 stated the R claim in
            % rate units, 5e-12/h (0.18 um/s at 7000 km at h = 200 s), and
            % that was 175 times D28's 1 nm/s budget and moved with h. The
            % bound is now the budget itself, 1.43e-16 1/s, whatever the step:
            % 260 times the measured floor (H.11 item 5).
            testCase.verifyEqual(fitted, direct, 'AbsTol', 5e-12);
            testCase.verifyEqual(fittedDot, directDot, 'AbsTol', ...
                TestRotation.VelocityBudget / TestRotation.OrbitRadius);
        end

        function rotationItrsToGcrs_reference_rateIsTheDerivativeOfTheRotation(testCase)
            % D128: Rdot IS THE TIME DERIVATIVE OF THE R RETURNED. The oracle is
            % the motion of R itself: the angular velocity
            % logm(R(t-h)' R(t+h)) / 2h, with R at t-h and t+h from this
            % function, is compared with R(t)' Rdot(t), at hourly epochs of one
            % day with the sub-daily tides on and off. A matrix logarithm is
            % exact for a constant rotation rate, so, unlike a central
            % difference of the matrix elements, it carries no (omega h)^2 / 6
            % truncation - 2.6e-13 1/s at h = 2 s, which is larger than what is
            % under test.
            %
            % Until the Earth rotation rate was formed from the interpolated UT1
            % it came from the series' LOD column, and this oracle measured the
            % difference at 2.0e-13 1/s with the tides (1.37 um/s at 7000 km)
            % and 5.8e-14 without, the same at h = 50, 100, 200 and 400 s.
            %
            % BOUND 3e-16 1/s (2 nm/s at 7000 km), NOT D28's 1.43e-16: the
            % oracle's own floor at h = 200 s measured 1.1e-16 with the tides
            % and 1.05e-16 without - the ERA resolution of 1.6e-14 rad over
            % 400 s and the logarithm's roundoff - so the budget itself would
            % leave a margin of 1.3. The bound is 2.7 times that floor and 190
            % times below the smaller of the two defects. The epochs are 1000 s
            % past each hour, so no shoulder reaches midnight, where the
            % interpolated rows change slope.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            second = (0:3600:82800)' + 1000;
            dayNumber = repmat(57700, numel(second), 1);
            h = 200;
            worst = zeros(1, 2);
            tides = [true, false];
            for tide = 1:2
                at = @(shift, order) referenceSystem.rotationItrsToGcrs( ...
                    referenceSystem.daySecondToEpoch([dayNumber, second + shift], "UTC"), ...
                    'Eop', eop, 'ApplyTidalCorrections', tides(tide), ...
                    'Derivatives', order);
                [R, Rdot] = at(0, 1);
                before = at(-h, 0);
                after = at(h, 0);
                for k = 1:size(R, 3)
                    motion = real(logm(before(:, :, k)' * after(:, :, k))) / (2 * h);
                    worst(tide) = max(worst(tide), ...
                        max(abs(Rdot(:, :, k) - R(:, :, k) * motion), [], 'all'));
                end
            end
            testCase.log(1, sprintf(['Rdot against the motion of R: %.3g 1/s with ', ...
                'the sub-daily tides, %.3g without (%.3g and %.3g m/s at 7000 km)'], ...
                worst(1), worst(2), worst(1) * TestRotation.OrbitRadius, ...
                worst(2) * TestRotation.OrbitRadius));
            testCase.verifyLessThan(worst, [3e-16, 3e-16], ...
                'Rdot is not the derivative of R: a UT1 rate is missing.');
        end

        function rotationItrsToGcrs_reference_interpolantAcrossALeapSecondMatchesDirect(testCase)
            % AN INTERPOLANT MAY SPAN A LEAP SECOND (rev. 1.226, H.11 item 9).
            % Until then building one across 2017-01-01 failed toleranceNotMet
            % at 3.58e5: the panel ending in the leap second took its last node
            % at 0h of the next day, where UT1-UTC had already stepped by a
            % second, and fitted the step. Five GRACE-era leap seconds made
            % that a real limit for reprocessing.
            %
            % THE EPOCHS STRADDLE THE BOUNDARY, two of them 86.4 s from it, so
            % that one difference shoulder at the default h = 200 s lies on
            % each side. Bounds as in interpolatedMatchesDirect: P19c's 5e-12
            % on R and D28's 1 nm/s at 7000 km on Rdot. Measured: R 2.2e-16,
            % Rdot 5.5e-19 1/s - the same floors as a span with no leap second.
            %
            % THE THIRTEENTH EPOCH IS 0.2 us BEFORE 23:59:60 (rev. 1.235), where
            % day + sec/86400 rounds up to the next whole MJD. The panel is
            % chosen by that MJD, and until the rounding was held below the
            % next day it read the next panel's dut1, a second higher, and the
            % rotation was 7.2e-5 rad out. The direct path was out by the same
            % amount there, so this comparison could not see it until
            % directPathTurnsOnceThroughALeapSecond held the direct path to SI
            % time.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57752 0; 57756 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
            testCase.verifyEqual(interpolant.taiMinusUtc', [36 36 37 37 37], ...
                'The span must hold the leap second at a panel boundary.');

            before = [0.9; 0.5; 0.1; 0.01; 0.003; 0.001];
            after = [0.001; 0.003; 0.01; 0.1; 0.5; 0.9];
            query = referenceSystem.daySecondToEpoch( ...
                [[repmat(57753, 6, 1); repmat(57754, 6, 1); 57753], ...
                [86400 * (1 - before); 86400 * after; 86400 - 2e-7]], "UTC");

            [direct, directDot] = referenceSystem.rotationItrsToGcrs(query, 'Eop', eop);
            [fitted, fittedDot, ~, info] = referenceSystem.rotationItrsToGcrs(query, ...
                'Interpolant', interpolant);
            testCase.verifyEqual(info.path, "interpolated");
            testCase.verifyEqual(fitted, direct, 'AbsTol', 5e-12);
            testCase.verifyEqual(fittedDot, directDot, 'AbsTol', ...
                TestRotation.VelocityBudget / TestRotation.OrbitRadius);
        end

        function rotationItrsToGcrs_reference_directPathTurnsOnceThroughALeapSecond(testCase)
            % THE DIRECT PATH IS HELD TO SI TIME, NOT TO THE INTERPOLATED PATH
            % (rev. 1.235). Until then interpolateEop gave UT1 - UTC in the next
            % day's convention through 23:59:60, and in the last 0.3 us before
            % it. UT1 ran a second ahead there and the rotation was 7.2e-5 rad
            % out. The interpolated path inherited the same error through its
            % fitted dut1, so every comparison between the two agreed. Measured
            % on 2017-01-01, over labels one SI second apart: the Earth turned
            % 2 s, then 0 s.
            %
            % THE REFERENCE IS THE ROTATION'S OWN NEIGHBOURS. Rotations at
            % 23:59:59.5 and 00:00:00.5, two SI seconds apart and each clear of
            % the defect, are joined along the geodesic, and the rotation at an
            % instant between them must lie on it at the fraction of SI time
            % elapsed. Bound: P19c's 5e-12. It separates the 3.6e-5 that a
            % second-early step leaves at the midpoint from everything that
            % bends the path in two seconds - the moving pole and CIP, and the
            % series read a second late at 23:59:60.5 - which together measured
            % 4.6e-13 and are logged. The angle's own advance is not a term: the
            % geodesic is exact for a constant axis.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            label = [57753, 86399.5; 57753, 86400 - 2e-7; 57753, 86400.5; 57754, 0.5];
            utc = referenceSystem.daySecondToEpoch(label, "UTC");
            R = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop);

            tai = referenceSystem.convertTimeScale(utc, "TAI");
            elapsed = (tai.day - tai.day(1)) * 86400 + (tai.sec - tai.sec(1));
            testCase.assertEqual(elapsed(end), 2, 'AbsTol', 1e-9, ...
                'The outer labels must lie two SI seconds apart.');
            chord = logm(R(:, :, 1)' * R(:, :, end));
            worst = 0;
            for k = 2:3
                onGeodesic = real(R(:, :, 1) * expm(elapsed(k) / 2 * chord));
                worst = max(worst, max(abs(R(:, :, k) - onGeodesic), [], 'all'));
                testCase.verifyEqual(R(:, :, k), onGeodesic, 'AbsTol', 5e-12, ...
                    sprintf(['The direct rotation at %d %.7f s is off the SI-time ', ...
                    'geodesic: UT1 is stepping inside the leap second.'], label(k, 1), label(k, 2)));
            end
            testCase.log(1, sprintf('direct path off the SI-time geodesic by %.3g', worst));
        end

        function earthOrientationInterpolant_reference_matchesTheDirectChain(testCase)
            % PROMPT P19. The claim the whole prompt rests on: an epoch the fit
            % has never seen is reproduced to the accuracy section B.9.2
            % measured. The epochs are deliberately irrational fractions of a
            % day so that none of them can land on a fit node by accident -
            % a test that only queried node positions would pass for any
            % degree whatever.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57757 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);

            % THE COMPARISON IS AGAINST THE CHAIN, NOT AGAINST
            % rotationItrsToGcrs('Interpolant', ...). THAT SENTENCE WAS STALE
            % FROM THE REVISION THAT WIRED THE OPTION: it no longer raises
            % notImplemented, and the precision test above drives it directly.
            % The comparison here is still against the chain on purpose,
            % because it is the builder's claim that is being tested. What P19's
            % builder claims is exactly what is asserted here - that the panels
            % reproduce cipCoordinates and interpolateEop at epochs the fit
            % never saw. Wiring the option consumes this; it does not change
            % the claim.
            offset = [0.13579; 0.31831; 0.57721; 1.41421; 2.71828];
            queryMjd = 57754 + offset;
            query = referenceSystem.daySecondToEpoch( ...
                [floor(queryMjd), (queryMjd - floor(queryMjd)) * 86400], "UTC");

            % THE SUB-DAILY CORRECTIONS ARE APPLIED HERE TOO, and at rev. 1.90
            % they were not - in either place. The builder omitted them and so
            % did this test, so the two agreed and the test passed while the
            % interpolant was missing tens of microarcseconds of physics. It
            % was the two DEGREE tests that caught it, because they compared
            % the fit against itself at two degrees rather than against a
            % second evaluation of the same wrong chain. A reference test that
            % rebuilds the reference the same way as the thing under test is
            % only asserting that the code is deterministic.
            correction = referenceSystem.subdailyEopCorrection(query);
            eopAt = referenceSystem.interpolateEop(eop, query, ...
                'Correction', correction);
            [X, Y, s] = referenceSystem.cipCoordinates( ...
                referenceSystem.convertTimeScale(query, "TT"), 'Eop', eopAt);
            direct = [X, Y, s, eopAt.xp, eopAt.yp, eopAt.dut1];
            testCase.assertSize(direct, [numel(queryMjd), ...
                numel(interpolant.quantity)], ...
                'The hand-built chain and the interpolant disagree on width.');

            fitted = zeros(size(direct));
            for k = 1:numel(queryMjd)
                panel = find(interpolant.panelStartMjd <= queryMjd(k), 1, 'last');
                fitted(k, :) = referenceSystem.evaluateInterpolant( ...
                    interpolant, queryMjd(k), panel);
            end

            % 1e-3 uas ON ALL FIVE ANGLES, 4.85e-15 rad, SINCE REV. 1.224 (H.11
            % item 6). It bounds the error the panels add to each angle at an
            % epoch the fit never saw, and the number is the builder's own
            % ACCURACY claim for the pole, applied to the CIP as well.
            %
            % WHY NOT THE 5e-12 IT REPLACES. That was P19c's bound on R, asserted
            % per input: 1.03 uas, TWICE the 0.5 uas gate the builder applies
            % at its midpoints. It passed a degree-12 fit (xp 9.1e-13 rad, 0.19
            % uas) and a panel mapping about a second late (X moves 4.1e-12 rad
            % per second). It was not a claim about which error dominates.
            %
            % WHAT DOMINATES, MEASURED ON THESE FIVE EPOCHS: worst column Y,
            % 8.4e-17 rad (1.7e-5 uas), the CIP series' own evaluation noise
            % rather than the fit - Y reads 8.4e-17 to 1.4e-16 at every degree
            % from 8 to 20. The truncation the degree controls shows in xp and
            % yp at 8.8e-19 rad (1.8e-7 uas, B.9.2's order). The bound is 58
            % times the noise floor, 5500 times the truncation.
            %
            % WHAT IT NOW SEES, MEASURED: degree 12 fails (xp 9.1e-13, 190 times
            % over), as do degree 10 and a fit without the sub-daily tides; a
            % mapping error of more than about 1.2 ms fails. Degree 16 (xp
            % 1.05e-15 rad, 2.2e-4 uas) still passes, which is right: it meets
            % the accuracy the builder documents. WHY NOT THE CIP's 1e-4 uas:
            % Y's noise would leave a margin of six on one host, and noise
            % that close to a bound fails on a compiler rather than on a fit
            % (obligation O8).
            microarcsecond = referenceSystem.iersConstants().arcsecondsToRadians * 1e-6;
            testCase.verifyEqual(fitted(:, 1:5), direct(:, 1:5), 'AbsTol', ...
                1e-3 * microarcsecond);
            testCase.verifyEqual(fitted(:, 6), direct(:, 6), 'AbsTol', 1e-10);
        end

    end

    methods (Test, TestTags = {'precision'})

        function evaluateInterpolant_precision_reproducesTheFitNodes(testCase)
            % At a fit node the expansion must return the value it was built
            % from, to roundoff, for any degree. That property says nothing
            % about accuracy - which is why the BUILDER measures its residual
            % at midpoints instead - but it is exactly the right check for the
            % EVALUATOR, because it isolates Clenshaw and the panel mapping
            % from the quality of the fit.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);

            node = referenceSystem.evaluateInterpolant(interpolant, ...
                interpolant.panelStartMjd(1), 1);
            % SIZED FROM THE INTERPOLANT, NOT FROM A LITERAL. This test held
            % a 6 that P19c made a 7, which is obligation O33 in the tests
            % rather than in the library. What matters is that the evaluator
            % returns one value per fitted quantity, whatever that number is.
            testCase.verifySize(node, [1, numel(interpolant.quantity)]);

            % The panel start is a node, so the CIP X there must match the
            % direct chain to the same roundoff, not merely to the fit
            % tolerance. 1e-14 rad IS 2.1e-3 uas (1e-14 x 2.063e11 uas/rad),
            % not the "about 2e-6 uas" this comment said until rev. 1.218
            % (D124). The term it bounds is the arithmetic of the fit and of
            % Clenshaw at u = -1, where the expansion interpolates its node
            % exactly and no truncation enters. Measured here: 6.5e-18 rad,
            % 30 ulp of X (1.3e-6 uas). The bound is 1.5e3 above that floor
            % and 240 times below the 0.5 uas fit tolerance it has to be told
            % apart from. In time it is 2.4 ms of X's motion (4.1e-12 rad/s):
            % the same node read 1 s late measured 4.1e-12, 411 times over.
            utc = referenceSystem.daySecondToEpoch( ...
                [interpolant.panelStartMjd(1), 0], "UTC");
            eopAt = referenceSystem.interpolateEop(eop, utc, ...
                'Correction', referenceSystem.subdailyEopCorrection(utc));
            [X, ~, ~] = referenceSystem.cipCoordinates( ...
                referenceSystem.convertTimeScale(utc, "TT"), 'Eop', eopAt);
            testCase.verifyEqual(node(1), X, 'AbsTol', 1e-14);
        end

        function earthOrientationInterpolant_precision_residualIsRecordedAndSmall(testCase)
            % The builder measures itself at points it did not fit and refuses
            % to return if it missed. This asserts the number it reports is
            % real: degree 12 must be visibly worse than degree 20, or the
            % residual is not measuring the fit at all. Section B.9.2 puts
            % degree 12 at 0.2 uas and degree 20 at 2.6e-7 uas.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57756 0], "UTC");

            fine = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
            coarse = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop, 'Degree', 12);

            % Section B.9.2 puts degree 12 at 0.2 uas and degree 20 at
            % 2.6e-7 uas over a one-day panel, so the gap is about six orders.
            % Asserting a FACTOR rather than a difference is what makes this
            % test able to fail: at rev. 1.90 the two degrees measured
            % 3.566e-05 and 3.640e-05, indistinguishable, because the fitted
            % chain had no sub-daily terms in it and there was nothing for
            % degree to resolve.
            testCase.verifyLessThan(max(fine.meta.residual), 1e-2);
            testCase.verifyGreaterThan(max(coarse.meta.residual), ...
                100 * max(fine.meta.residual), ...
                'Degree 12 must fit far worse than degree 20, or the residual is not measured.');
        end

    end

    methods (Test, TestTags = {'contract'})

        function evaluateInterpolant_contract_refusesWhatItCannotEvaluate(testCase)
            % The panel is NAMED by the caller rather than searched for, so
            % both ways of naming it wrongly have to be refused: an index past
            % the end, and an epoch that is inside the interpolant but outside
            % the panel that was named. The second is the dangerous one - a
            % Chebyshev expansion diverges outside its interval, so evaluating
            % it there returns a plausible number that is wrong by an
            % unbounded amount.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57756 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);

            testCase.verifyError(@() referenceSystem.evaluateInterpolant( ...
                interpolant, interpolant.panelStartMjd(1), ...
                numel(interpolant.panelStartMjd) + 1), ...
                'referenceSystem:evaluateInterpolant:badPanel');

            testCase.verifyError(@() referenceSystem.evaluateInterpolant( ...
                interpolant, interpolant.panelStartMjd(1) + 1.5, 1), ...
                'referenceSystem:mex:outOfPanel');
        end

        function rotationItrsToGcrs_contract_refusesAMismatchedInterpolant(testCase)
            % The tidal mismatch is refused rather than reconciled because a
            % caller who mixes them gets NO signal from the numbers: the
            % rotation stays smooth, orthogonal and plausible while being wrong
            % by tens of microarcseconds. Revision 1.91 is the evidence - the
            % builder omitted those terms and a reference test that omitted
            % them too agreed with it to 1e-14 for two revisions.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57756 0], "UTC");
            bare = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop, 'ApplyTidalCorrections', false);
            query = referenceSystem.daySecondToEpoch([57755 3600], "UTC");

            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs( ...
                query, 'Interpolant', bare), ...
                'referenceSystem:rotationItrsToGcrs:tidalMismatch');

            % And an epoch past the end of the panels: a Chebyshev expansion
            % diverges outside its interval, so extrapolation is refused rather
            % than returned as a plausible number.
            full = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
            outside = referenceSystem.daySecondToEpoch([57760 0], "UTC");
            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs( ...
                outside, 'Interpolant', full), ...
                'referenceSystem:rotationItrsToGcrs:outsideInterpolant');

            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs( ...
                query, 'Interpolant', struct('degree', 20)), ...
                'referenceSystem:rotationItrsToGcrs:badInterpolant');

            % A series or a method beside the panels would be silently unused,
            % because the panels fixed both when they were built.
            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs( ...
                query, 'Eop', eop, 'Interpolant', full), ...
                'referenceSystem:rotationItrsToGcrs:conflictingEopSource');
            testCase.verifyError(@() referenceSystem.rotationItrsToGcrs( ...
                query, 'Interpolant', full, 'InterpolationMethod', "linear"), ...
                'referenceSystem:rotationItrsToGcrs:conflictingEopSource');
        end

        function earthOrientationInterpolant_contract_refusesWhatItCannotUse(testCase)
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57756 0], "UTC");
            ttSpan = referenceSystem.convertTimeScale(span, "TT");
            single = referenceSystem.daySecondToEpoch([57754 0], "UTC");

            testCase.verifyError(@() ...
                referenceSystem.earthOrientationInterpolant(ttSpan, 'Eop', eop), ...
                'referenceSystem:earthOrientationInterpolant:wrongScale');
            testCase.verifyError(@() ...
                referenceSystem.earthOrientationInterpolant(single, 'Eop', eop), ...
                'referenceSystem:earthOrientationInterpolant:singleEpoch');
            testCase.verifyError(@() ...
                referenceSystem.earthOrientationInterpolant(span), ...
                'referenceSystem:earthOrientationInterpolant:missingEop');
            testCase.verifyError(@() ...
                referenceSystem.earthOrientationInterpolant(span, 'Eop', eop, ...
                'Degree', 4), ...
                'referenceSystem:earthOrientationInterpolant:toleranceNotMet');
            % Degree 4 over a day cannot resolve a semi-diurnal tide at all -
            % section B.9.2 measures degree 8 at 30 uas - so this must breach
            % the 0.5 uas default. At rev. 1.90 it did not, and that was the
            % first sign that the sub-daily terms were missing from the fit.
        end

        function earthOrientationInterpolant_contract_refusesALeapSecondInsideAPanel(testCase)
            % A PANEL CARRIES ONE TAI-UTC (rev. 1.226). Three-day panels align
            % to MJD 57753, so the 2017-01-01 leap second at 57754 falls inside
            % the second panel; that is refused by name before anything is
            % fitted, where it used to surface as toleranceNotMet. One-day
            % panels over the same span build: see
            % interpolantAcrossALeapSecondMatchesDirect.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57752 0; 57756 0], "UTC");
            testCase.verifyError(@() referenceSystem.earthOrientationInterpolant( ...
                span, 'Eop', eop, 'PanelSpan', 3), ...
                'referenceSystem:earthOrientationInterpolant:leapSecondInsidePanel');
        end

        function earthOrientationInterpolant_contract_toleranceGatesDut1AsAnAngle(testCase)
            % TOLERANCE IS MICROARCSECONDS OF ROTATION FOR EVERY CHANNEL, dut1
            % INCLUDED: a UT1 residual in microseconds turns the Earth by
            % 15.04 uas per us, and comparing the raw microseconds with the
            % tolerance would hold dut1 fifteen times more loosely than the
            % angles it becomes.
            %
            % A CONFIGURATION IN WHICH THE READINGS DISAGREE, MEASURED: four-day
            % panels over MJD 57700-57708 without the sub-daily terms put three
            % daily-row kinks inside each panel. The angles reach 2.96 uas and
            % dut1 0.372 us, which is 5.59 uas of rotation. A tolerance of
            % 4.2 uas lies between the angles and dut1-as-angle with a margin
            % of 1.3 on each side and far above dut1 in microseconds: a gate
            % reading microseconds builds this interpolant, the angle gate must
            % refuse it. The second call admits the same fit at 6 uas, so the
            % refusal is about dut1 and not blanket.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57700 0; 57708 0], "UTC");

            testCase.verifyError(@() referenceSystem.earthOrientationInterpolant( ...
                span, 'Eop', eop, 'PanelSpan', 4, 'ApplyTidalCorrections', false, ...
                'Tolerance', 4.2), ...
                'referenceSystem:earthOrientationInterpolant:toleranceNotMet');

            admitted = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop, 'PanelSpan', 4, 'ApplyTidalCorrections', false, ...
                'Tolerance', 6);
            name = string(admitted.quantity);
            dut1 = admitted.meta.residual(name == "dut1");
            angles = max(admitted.meta.residual(name ~= "dut1"));
            testCase.log(1, sprintf('dut1 gate: angles %.3g uas, dut1 %.3g us', ...
                angles, dut1));
            % Both below 4.2 in their own units, so only the conversion can
            % have refused the first call.
            testCase.verifyLessThan([angles, dut1], [4.2, 4.2], ...
                'The configuration no longer separates the two gates.');
        end

        function earthOrientationInterpolant_contract_refusesANonIntegerPanelSpan(testCase)
            % A FRACTION OF A DAY IS REFUSED UNDER THIS FUNCTION'S OWN NAME (rev.
            % 1.237, H.11 item 12, Matthias's decision). Until then PanelSpan
            % 0.5 and 1.5 both failed with normalizeEpoch:nonIntegerDay from
            % inside the leap-second lookup, which names neither the function
            % nor the option. Both are asserted, below and above one day, and
            % the refusal must come before any EOP is evaluated - so the Eop
            % here is a real series and the span a valid one. PanelSpan 2 is
            % the whole-day case that must still build; two-day panels miss
            % the default 0.5 uas, so the tolerance is a generous 40.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57756 0], "UTC");
            for fraction = [0.5, 1.5]
                testCase.verifyError(@() referenceSystem.earthOrientationInterpolant( ...
                    span, 'Eop', eop, 'PanelSpan', fraction), ...
                    'referenceSystem:earthOrientationInterpolant:nonIntegerPanelSpan', ...
                    sprintf('PanelSpan %g was not refused by name.', fraction));
            end
            whole = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop, ...
                'PanelSpan', 2, 'Tolerance', 40);
            testCase.verifyEqual(whole.panelSpan, 2);
        end

        function earthOrientationInterpolant_contract_panelsAlignToWholeDays(testCase)
            % TWO CALLERS ASKING FOR OVERLAPPING SPANS MUST GET THE SAME PANELS.
            % If the grid started at the requested epoch instead, two arcs that
            % overlap would be interpolated on grids offset by an arbitrary
            % fraction of a day, and the same instant would evaluate to two
            % different rotations depending on which arc asked. That is the
            % kind of difference that surfaces as an unexplained jump in a
            % residual weeks later.
            eop = testCase.cookbookEop();
            early = referenceSystem.earthOrientationInterpolant( ...
                referenceSystem.daySecondToEpoch([57754 3600; 57756 0], "UTC"), ...
                'Eop', eop);
            late = referenceSystem.earthOrientationInterpolant( ...
                referenceSystem.daySecondToEpoch([57755 7200; 57757 0], "UTC"), ...
                'Eop', eop);

            shared = intersect(early.panelStartMjd, late.panelStartMjd);
            testCase.assertNotEmpty(shared, 'The two spans should share panels.');
            testCase.verifyEqual(shared, [57755; 57756], 'AbsTol', 0);

            earlyIndex = early.panelStartMjd == shared(1);
            lateIndex = late.panelStartMjd == shared(1);
            testCase.verifyEqual(late.coefficient(:, :, lateIndex), ...
                early.coefficient(:, :, earlyIndex), 'AbsTol', 0, ...
                'A shared panel must hold bit-identical coefficients.');
        end

        function earthOrientationInterpolant_contract_quantityOrderIsTheAuthority(testCase)
            % The column order is published in .quantity and nothing may assume
            % it. This asserts the field exists, names all six, and matches the
            % width of the coefficient array - so a seventh quantity added
            % later cannot be silently unnamed.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);

            % The order is the authority the C API strides by and the file
            % format names, so it is asserted here in full rather than by
            % count: a reordering that kept the length would be silent
            % everywhere else. The length of day is not a channel: the
            % rotation takes its rate from the UT1 panels.
            testCase.verifyEqual(interpolant.quantity, ...
                ["X", "Y", "s", "xp", "yp", "dut1"]);
            testCase.verifyEqual([interpolant.meta.method, ...
                interpolant.meta.zonalTides], ["lagrange", "restore"], ...
                'The builder must record the interpolation it fitted through.');
            testCase.verifySize(interpolant.coefficient, ...
                [interpolant.degree + 1, numel(interpolant.quantity), ...
                numel(interpolant.panelStartMjd)]);
        end

    end

    methods (Test, TestTags = {'speed'})

        function rotationItrsToGcrs_speed_interpolatedArcBeatsTheExactPath(testCase)
            % MEASURED ON AN ARC, NOT ON ONE EPOCH, AND THE FIRST VERSION OF
            % THIS TEST GOT THAT WRONG. It asserted P19's "< 15 us per
            % single-epoch call" and measured 469 us against an exact path of
            % 491 us: a speedup of 0.99. That is the correct answer to the
            % wrong question, and the prompt contains its own refutation two
            % paragraphs later - "MATLAB's own call overhead is ~5-15 us and
            % cannot be optimised away, so an integrator needing better must
            % live in C". A single MATLAB call cannot be under 15 us when
            % 5-15 us is the FLOOR, and on this host the floor is far higher:
            % the exact path costs 491 us at N = 1, which is overhead and not
            % series evaluation. AT N = 1 THE INTERPOLANT HAS NOTHING TO
            % REMOVE.
            %
            % Where it must win is an arc. At N = 5000 the exact path spends
            % about 8 us per epoch and roughly 0.1 us of that is amortised
            % overhead, so ~98 per cent is the per-epoch work the panels
            % replace. That is the claim section B.9 actually supports and it
            % is what is asserted here. The single-epoch target is retired as
            % internally inconsistent with the prompt that set it, and the C
            % API - measured at 0.564 us per call in test/c/testApi.c - is
            % where P19's sub-microsecond promise is kept.
            eop = testCase.cookbookEop();
            span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
            interpolant = referenceSystem.earthOrientationInterpolant(span, ...
                'Eop', eop);
            arc = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 5000, 1), (0:4999)' * 10], "UTC");

            % Warm up both paths: the first call of each pays for JIT.
            referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);
            referenceSystem.rotationItrsToGcrs(arc, 'Interpolant', interpolant);

            exactTime = zeros(5, 1);
            fastTime = zeros(5, 1);
            for k = 1:5
                start = tic;
                referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);
                exactTime(k) = toc(start);
                start = tic;
                referenceSystem.rotationItrsToGcrs(arc, 'Interpolant', interpolant);
                fastTime(k) = toc(start);
            end

            % BOTH ROWS ARE LOGGED, BECAUSE ONE OF THEM ALONE IS MISLEADING.
            % Run 60 logged only the interpolated arc, at 5.698 ms. The nearest
            % exact row in the table is (N=5000,R+Rdot) at 47.814 ms - a
            % DIFFERENT test computing TWO outputs - so a reader comparing them
            % would infer a speedup from two rows that do not measure the same
            % thing. The ratio this test asserts was invisible in the report
            % precisely because the test passed: a quiet pass leaves no trace
            % of the number it checked.
            %
            % BOTH TARGETS RE-DERIVED AT REV. 1.250 FROM THE SLOWEST OF THREE
            % MEASURED MEDIANS, 0.050161 s and 0.007782 s, giving 0.11 s and
            % 0.016 s - see the class help of TestPerformance for the runs and
            % the rule. Neither row carries a hard assertion and neither
            % acquires one here: what this test refuses is the RATIO below,
            % and an absolute bound on either path would be a second claim
            % nobody has argued.
            testCase.log(1, TestPerformance.benchmarkRecord( ...
                "rotationItrsToGcrs (exact,N=5000,R)", 5000, ...
                median(exactTime), 0.11, min(exactTime)));
            testCase.log(1, TestPerformance.benchmarkRecord( ...
                "rotationItrsToGcrs (Interpolant,N=5000)", 5000, ...
                median(fastTime), 0.016, min(fastTime)));

            % THE RATIO IS THE CLAIM AND IT SURVIVES A LOADED HOST, because
            % both paths are timed back to back on the same machine in the
            % same second. The bound is deliberately modest: section B.9 is
            % being asked whether the interpolant helps AT ALL on an arc, and
            % the honest first answer to that is a number, not a target.
            speedup = min(exactTime)/min(fastTime);
            testCase.verifyGreaterThan(speedup, 1.5, ...
                sprintf(['The interpolated arc is %.2fx the exact one. If ', ...
                'this is at or below 1, the panels are buying nothing even ', ...
                'where per-epoch cost dominates, and the remaining ', ...
                'interpolateEop call is the reason - see the comment in ', ...
                'rotationItrsToGcrs.m beginning THE SERIES IS STILL ', ...
                'INTERPOLATED.'], speedup));
        end

        function rotationItrsToGcrsPartials_speed_marginalCostOverTheRotation(testCase)
            % OPEN ITEM B1. P20's prompt states that "the marginal cost over
            % rotationItrsToGcrs is small" and NOTHING HAS EVER MEASURED IT.
            % That is the same unmeasured-claim shape P19 carried, and P19's
            % turned out to be wrong by a factor of thirty - which is the whole
            % reason this test exists rather than the sentence being believed.
            %
            % THE QUANTITY IS A RATIO ON ONE MACHINE IN ONE SECOND, NOT AN
            % ABSOLUTE MICROSECOND FIGURE (obligation O21). An absolute target
            % for a function nobody has profiled would be invented, and a
            % ratio against the function it extends is the claim actually being
            % made. Both rows are logged, because one alone invites a reader to
            % pair it with some other row measuring something else - which is
            % exactly how rev. 1.155 produced an 8.4x that was really 3.41x.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            arc = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 500, 1), (0:499)' * 100], "UTC");

            % Warm up both paths: the first call of each pays for JIT.
            referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);
            referenceSystem.rotationItrsToGcrsPartials(arc, 'Eop', eop);

            rotationTime = zeros(5, 1);
            partialTime = zeros(5, 1);
            partialRateTime = zeros(5, 1);
            for k = 1:5
                start = tic;
                referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);
                rotationTime(k) = toc(start);
                start = tic;
                referenceSystem.rotationItrsToGcrsPartials(arc, 'Eop', eop);
                partialTime(k) = toc(start);
                start = tic;
                localPartialsWithRates(arc, eop);
                partialRateTime(k) = toc(start);
            end

            % Targets are the section B.7 shape - a number the report can be
            % read against - and not a claim. The three-output call does three
            % constant-axis generator products on top of one rotation, so
            % twice the rotation is the honest expectation; the six-output call
            % adds D102's two extra rotations for the rate partials and is
            % therefore expected near four times.
            %
            % ALL THREE RE-DERIVED AT REV. 1.250 FROM THE SLOWEST OF THREE
            % MEASURED MEDIANS, 0.010542, 0.011193 and 0.035995 s, giving
            % 0.022, 0.023 and 0.072 s - see the class help of TestPerformance
            % for the runs and the rule. The measured shape is 1.0 : 1.06 :
            % 3.4 against the 1 : 2 : 4 the paragraph above expects, so the
            % three rotation partials are very nearly free and only the rate
            % partials cost what was predicted.
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "rotationItrsToGcrs (N=500,R)", 500, median(rotationTime), ...
                0.022, min(rotationTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "rotationItrsToGcrsPartials (N=500,dR)", 500, ...
                median(partialTime), 0.023, min(partialTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "rotationItrsToGcrsPartials (N=500,dR+dRdot)", 500, ...
                median(partialRateTime), 0.072, min(partialRateTime)));

            % THE MARGINAL COST IS THE ASSERTION. Ten times the rotation would
            % not be "small" by any reading of P20's sentence, and would mean
            % the partials are re-deriving the chain rather than reusing its
            % factors. The bound is deliberately generous: this is a first
            % measurement, and its job is to produce a number and to refuse
            % only an answer that contradicts the prompt outright.
            marginal = min(partialTime)/min(rotationTime);
            marginalWithRate = min(partialRateTime)/min(rotationTime);
            testCase.verifyLessThan(marginal, 10, sprintf( ...
                ['The three rotation partials cost %.2fx the rotation ', ...
                'itself. P20 claims the marginal cost is small; above ten ', ...
                'the factors are being recomputed, not reused.'], marginal));
            testCase.verifyLessThan(marginalWithRate, 25, sprintf( ...
                ['With the rate partials the cost is %.2fx the rotation. ', ...
                'D102 buys them with two further evaluations of the ', ...
                'partials, so about four is expected and 25 is the bound ', ...
                'that refuses a different construction.'], marginalWithRate));
        end

        function earthOrientationPartials_speed_generatorsAreNegligible(testCase)
            % OPEN ITEM B1, THE OTHER HALF. earthOrientationPartials is the
            % constant-axis generator layer the rotation partials sit on, and
            % it does no astronomy at all - three fixed skew products per
            % epoch. If it is not far cheaper than the rotation it decorates,
            % something is being rebuilt per call, which is the defect section
            % B.9 found everywhere else in this toolbox.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = testCase.cookbookEop();
            arc = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 500, 1), (0:499)' * 100], "UTC");
            R = referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);

            % TWENTY REPETITIONS, NOT FIVE, AND THE REASON IS IN THE REPORTS.
            % At five this row measured 0.000664, 0.000097 and 0.000658 s on
            % runs 68, 71 and 72 - a 6.8x swing on a function NOTHING TOUCHED
            % between them. A few hundred microseconds is where timer
            % granularity and JIT live, not where this code lives, and a row
            % that swings sevenfold on its own invites the next reader to
            % diagnose a regression that never happened (rev. 1.124 recorded
            % exactly that trap about this table).
            %
            % THE ROTATION IS SUPPLIED, WHICH IS THE WHOLE POINT OF THE
            % MEASUREMENT. Passing 'Rotation' is the call shape an estimator
            % uses - it already holds R - so this times the generator layer
            % alone and not a second evaluation of the chain.
            referenceSystem.earthOrientationPartials(arc, 'Eop', eop, ...
                'Rotation', R);
            referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);

            partialTime = zeros(20, 1);
            rotationTime = zeros(20, 1);
            for k = 1:20
                start = tic;
                referenceSystem.earthOrientationPartials(arc, 'Eop', eop, ...
                    'Rotation', R);
                partialTime(k) = toc(start);
                start = tic;
                referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);
                rotationTime(k) = toc(start);
            end

            % 0.00033 s, RE-DERIVED AT REV. 1.250 FROM THE SLOWEST OF THREE
            % MEASURED MEDIANS, 0.000162 s - see the class help of
            % TestPerformance for the runs and the rule. The 0.05 s it replaces
            % was 309x the cost, which is not a target but a placeholder.
            % THIS IS THE ROW WHERE THE RULE IS MOST LIKELY TO BITE, and the
            % paragraph above says why: at five repetitions this figure swung
            % 6.8x between runs that changed nothing. At twenty it is steady to
            % eight per cent across the three runs behind this number. If it
            % starts reporting SLOW while the ratio below still passes, that is
            % the timer and the machine, not the generator layer.
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "earthOrientationPartials (N=500)", 500, median(partialTime), ...
                0.00033, min(partialTime)));

            % AND THE CLAIM IS THE RATIO, BECAUSE THE ABSOLUTE ROW CANNOT
            % CARRY IT (obligation O21). What is being asserted is that the
            % generator layer does no astronomy - three fixed skew products
            % per epoch against a full SOFA evaluation - so it must be
            % SUBSTANTIALLY cheaper than the rotation it decorates. Measured
            % between 3x and 38x across runs 68 to 72; three is the bound,
            % and a value near one would mean something is being rebuilt per
            % call, which is the defect section B.9 found everywhere else.
            cheaper = min(rotationTime)/min(partialTime);
            testCase.verifyGreaterThan(cheaper, 3, sprintf( ...
                ['earthOrientationPartials is only %.2fx cheaper than the ', ...
                'rotation it decorates. Given a rotation it does three skew ', ...
                'products per epoch and no astronomy; near one means the ', ...
                'chain is being re-derived.'], cheaper));
        end

        function rotationItrsToGcrs_speed_singleEpochAndArc(testCase)
            eop = testCase.cookbookEop();
            single = referenceSystem.daySecondToEpoch([57754 0], "UTC");
            arc = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 5000, 1), (0:4999)' * 10], "UTC");

            singleTime = zeros(20, 1);
            for k = 1:20
                start = tic;
                referenceSystem.rotationItrsToGcrs(single, 'Eop', eop);
                singleTime(k) = toc(start);
            end

            arcTime = zeros(5, 1);
            for k = 1:5
                start = tic;
                localTwoOutputs(arc, eop, 200);
                arcTime(k) = toc(start);
            end

            % The N = 1 target is call overhead and not arithmetic: one MEX
            % round trip, the arguments block, the EOP interpolation and the
            % struct assembly. Section B.9 documents that cost and names the
            % P19 C API, not a faster MATLAB call, as the fix for an
            % integrator hot loop.
            % THE HARD ASSERTION IS ON THE FASTEST REPETITION (rev. 1.86). Run
            % 17 measured these two rows at 6.9x and 5.4x their usual values on
            % the same host and the same MEX binary, and run 18 put them back
            % where they belong while doing the same thing to
            % convertCoordinates. External load can only add time, so the
            % fastest repetition estimates the code and the median reports the
            % machine. See TestDispatch/convertCoordinates_speed_manySinglePointCalls
            % for the full argument; it is not repeated here.
            % BOTH ROWS FAILED AT ONE TIMES THEIR TARGET UNTIL REV. 1.250,
            % WHICH IS NOT THE RULE THIS SUITE PUBLISHES. Section B.7, section
            % D.1 and the class help of TestPerformance all say a benchmark
            % warns at its target and fails at five times it, because the
            % target is a property of the machine and a fivefold miss is a
            % property of the code. These two called benchmarkRecord and then
            % asserted the bare target, so the number was doing both jobs at
            % once. It never showed, because the targets sat at 3.0x and 15.2x
            % what the code costs - the looseness was hiding the defect, and
            % re-deriving the targets would have turned both rows into hard
            % failures on any busy minute. Routed through verifiedBenchmark,
            % which carries the five-times rule and the fastest-repetition
            % rule in the one place they are tested.
            %
            % TARGETS FROM THE SLOWEST OF THREE MEASURED MEDIANS, 0.001657 s
            % and 0.131979 s, giving 0.0034 s and 0.27 s - see the class help
            % of TestPerformance for the runs and the rule.
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "rotationItrsToGcrs (N=1,call)", 1, median(singleTime), ...
                0.0034, min(singleTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "rotationItrsToGcrs (N=5000,R+Rdot)", 5000, median(arcTime), ...
                0.27, min(arcTime)));
        end

    end

    methods (Static, Access = private)

        function rate = rateOf(epochUt1, lengthOfDay)
            %RATEOF The ERA rate, in a form a function handle can request.
            %   An anonymous function cannot make a multiple-output call, so a
            %   test that needs the nargout >= 2 path needs a named one.
            [~, rate] = referenceSystem.earthRotationAngle(epochUt1, ...
                'LengthOfDay', lengthOfDay);
        end

    end

    methods (Access = private)

        function utc = cookbookUtc(~)
            %COOKBOOKUTC The cookbook epoch as a UTC epoch struct.
            utc = referenceSystem.daySecondToEpoch([57754 43200], "UTC");
        end

        function R = rotationWithPerturbedEop(~, epoch, eop, field, step)
            %ROTATIONWITHPERTURBEDEOP The rotation with one EOP column shifted.
            %   THE SERIES IS PERTURBED, NOT THE SAMPLED VALUE, so the shift
            %   passes through the same interpolation and the same sub-daily
            %   corrections the rotation itself applies. Perturbing after the
            %   sampling would bypass exactly the code the partial has to agree
            %   with.
            perturbed = eop;
            perturbed.(field) = perturbed.(field) + step;
            R = referenceSystem.rotationItrsToGcrs(epoch, 'Eop', perturbed);
        end


        function tt = cookbookTt(~)
            tt = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookTtSecond], "TT");
        end

        function [X, Y] = cookbookCip(testCase, modelName)
            %COOKBOOKCIP The cookbook CIP through the branch named.
            scale = referenceSystem.iersConstants().arcsecondsToRadians * 1e-3;
            if modelName == "IAU2000A"
                deltaX = TestRotation.CookbookDeltaX2000;
                deltaY = TestRotation.CookbookDeltaY2000;
            else
                deltaX = TestRotation.CookbookDeltaX2006;
                deltaY = TestRotation.CookbookDeltaY2006;
            end
            [X, Y] = referenceSystem.cipCoordinates(testCase.cookbookTt(), ...
                'DeltaX', deltaX * scale, 'DeltaY', deltaY * scale, ...
                'CipModel', modelName);
        end

        function eop = cookbookEop(testCase)
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
        end

        function varargout = cookbookRotation(testCase, outputCount)
            %COOKBOOKROTATION The cookbook epoch driven through the full chain.
            %
            %   The EOP are a synthetic five-row series carrying the
            %   cookbook's own polar motion, Delta UT1 and pole offsets, so
            %   that the reference tests exercise the whole pipeline and not
            %   only the C core. No published IERS series in this repository
            %   covers 2007, and inventing a fixture file would put the
            %   literals two files away from the assertion.
            eop = testCase.syntheticEop(TestRotation.CookbookDay);
            utc = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay 43200], "UTC");

            [varargout{1:outputCount}] = referenceSystem.rotationItrsToGcrs( ...
                utc, 'Eop', eop, 'ApplyTidalCorrections', false, ...
                'DifferenceStep', 200);
        end

        function [R, Rdot, Rddot, info] = cookbookRotationWithInfo(testCase, ...
                derivatives)
            %COOKBOOKROTATIONWITHINFO Four outputs, with the override chosen.
            %
            %   derivatives = -1 leaves the order to nargout, which is the
            %   default behaviour; 0, 1 or 2 override it.
            eop = testCase.syntheticEop(TestRotation.CookbookDay);
            utc = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay 43200], "UTC");

            [R, Rdot, Rddot, info] = referenceSystem.rotationItrsToGcrs(utc, ...
                'Eop', eop, 'ApplyTidalCorrections', false, ...
                'Derivatives', derivatives);
        end

        function eop = syntheticEop(~, centreDay)
            %SYNTHETICEOP A five-day series holding the cookbook values.
            %   interpolateEop restores the zonal tides at the epoch, so the
            %   rows carry the cookbook UT1 - UTC less the tide at noon of the
            %   centre day plus the tide at their own epoch: the regularised
            %   series is then constant, and at noon of the centre day dut1 is
            %   the cookbook value to roundoff under any stencil. Five rows,
            %   because 4-point Lagrange needs four.
            scale = referenceSystem.iersConstants().arcsecondsToRadians;
            mjd = (centreDay - 2:centreDay + 2)';
            rowCount = numel(mjd);
            tide = @(epoch) referenceSystem.zonalTideEopCorrection( ...
                referenceSystem.convertTimeScale(epoch, "TT")).dut1;
            noon = tide(referenceSystem.daySecondToEpoch([centreDay 43200], "UTC"));
            rowTide = tide(referenceSystem.daySecondToEpoch( ...
                [mjd, zeros(rowCount, 1)], "UTC"));
            eop = struct( ...
                'mjd', mjd, ...
                'xp', repmat(TestRotation.CookbookPolarX * scale, rowCount, 1), ...
                'yp', repmat(TestRotation.CookbookPolarY * scale, rowCount, 1), ...
                'dut1', TestRotation.CookbookDeltaUt1 - noon + rowTide, ...
                'lod', zeros(rowCount, 1), ...
                'dX', repmat(TestRotation.CookbookDeltaX2006 * scale * 1e-3, rowCount, 1), ...
                'dY', repmat(TestRotation.CookbookDeltaY2006 * scale * 1e-3, rowCount, 1), ...
                'sigma', struct(), ...
                'meta', struct('series', "synthetic", ...
                    'cipModel', "IAU2006/2000A", ...
                    'cipModelSource', "test fixture", ...
                    'poleOffsetType', "dXdY", ...
                    'samplingHour', 0, ...
                    'nRows', rowCount, ...
                    'mjdRange', [mjd(1) mjd(end)]));
        end

        function [R, Rdot] = arcRotation(testCase)
            %ARCROTATION A real EOP series over one day, for the invariants.
            eop = testCase.cookbookEop();
            arc = referenceSystem.daySecondToEpoch( ...
                [repmat(57754, 24, 1), (0:23)' * 3600], "UTC");
            [R, Rdot] = referenceSystem.rotationItrsToGcrs(arc, 'Eop', eop);
        end

        function reference = richardsonDerivative(~, utc, eop)
            %RICHARDSONDERIVATIVE Reference Rdot, better than any single step.
            %
            %   Two central differences whose steps differ by a factor two
            %   combine to cancel the leading h^2 error term, giving an O(h^4)
            %   estimate. The reference has to be better than what it measures,
            %   which is why the sweep cannot simply compare one step against
            %   another.
            [~, coarse] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop, ...
                'DifferenceStep', 2400, 'ApplyTidalCorrections', false);
            [~, fine] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop, ...
                'DifferenceStep', 1200, 'ApplyTidalCorrections', false);
            reference = (4 * fine - coarse) / 3;
        end

        function path = fixture(testCase, name)
            %FIXTURE Absolute path of a named fixture file.
            path = string(fullfile(testCase.toolboxRoot(), 'test', ...
                'fixtures', name));
        end

        function root = toolboxRoot(~)
            %TOOLBOXROOT Absolute path of the distribution folder.
            root = fileparts(fileparts(mfilename('fullpath')));
        end

    end


    methods (Test, TestTags = {'contract'})

        function rotationTirsToItrs_contract_shapeAndScalarBroadcast(testCase)
            % P17: rotationTirsToItrs reached session S6 with NO tests at all.
            % It is the one L2 function nothing exercised, which is how the
            % METHOD-block defect corrected in this session survived nine runs.
            xp = [1e-7; 2e-7; 3e-7];

            single = referenceSystem.rotationTirsToItrs(1e-7, 2e-7, 0);
            arc = referenceSystem.rotationTirsToItrs(xp, 2e-7, 0);

            testCase.verifySize(single, [3 3], 'N = 1 returns a plain 3x3.');
            testCase.verifySize(arc, [3 3 3], 'An arc returns one page per epoch.');
            testCase.verifyEqual(arc(:, :, 1), ...
                referenceSystem.rotationTirsToItrs(xp(1), 2e-7, 0), 'AbsTol', 0, ...
                'A scalar yp and sp must broadcast to every epoch unchanged.');
        end

        function rotationTirsToItrs_contract_refusesAMismatchedLength(testCase)
            testCase.verifyError(@() referenceSystem.rotationTirsToItrs( ...
                [1e-7; 2e-7; 3e-7], [1e-7; 2e-7], 0), ...
                'referenceSystem:rotationTirsToItrs:sizeMismatch');
        end

        function greenwichSiderealTime_contract_refusesTheWrongScales(testCase)
            % Both slots are checked, and separately: sidereal time needs UT1
            % for the rotation and TT for the precession and nutation, and
            % supplying one where the other belongs is the mistake worth
            % catching. Two verifyError calls rather than one, per obligation O6.
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second], "UT1");
            tt = testCase.cookbookTt();

            testCase.verifyError(@() referenceSystem.greenwichSiderealTime(tt, tt), ...
                'referenceSystem:greenwichSiderealTime:wrongScale');
            testCase.verifyError(@() referenceSystem.greenwichSiderealTime(ut1, ut1), ...
                'referenceSystem:greenwichSiderealTime:wrongScale');
        end

        function greenwichSiderealTime_contract_refusesMismatchedLengths(testCase)
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second; ...
                TestRotation.CookbookDay + 1 TestRotation.CookbookUt1Second], "UT1");
            tt = testCase.cookbookTt();

            testCase.verifyError(@() referenceSystem.greenwichSiderealTime(ut1, tt), ...
                'referenceSystem:greenwichSiderealTime:sizeMismatch');
        end

        function earthRotationAngle_contract_refusesANonUt1Epoch(testCase)
            % The ERA is an angle of the Earth about its axis, so it is defined
            % on UT1 and on nothing else. A TT epoch would be wrong by the whole
            % of TT - UT1, about 69 s in 2026, which is 5e-4 rad of rotation.
            testCase.verifyError(@() referenceSystem.earthRotationAngle( ...
                testCase.cookbookTt()), ...
                'referenceSystem:earthRotationAngle:wrongScale');
        end

        function earthRotationAngle_contract_refusesAMismatchedLengthOfDay(testCase)
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second], "UT1");

            % TWO OUTPUTS ARE REQUESTED DELIBERATELY. Until this session the
            % LengthOfDay check sat below an "if nargout < 2, return", because
            % the option affects only the rate - so a one-output call accepted
            % a wrongly sized option in silence and the documented error was
            % unreachable on the default call shape. The library now validates
            % what it was given before deciding what it was asked for, and this
            % test drives the rate path so that both halves are covered.
            testCase.verifyError(@() TestRotation.rateOf(ut1, [1e-3; 2e-3]), ...
                'referenceSystem:earthRotationAngle:sizeMismatch');
            testCase.verifyError(@() referenceSystem.earthRotationAngle(ut1, ...
                'LengthOfDay', [1e-3; 2e-3]), ...
                'referenceSystem:earthRotationAngle:sizeMismatch');
        end

        function earthRotationAngleRate_contract_isAScalarPositiveRate(testCase)
            % Decision D63 made the rate its own function so that it could not
            % be confused with iersConstants().earthRotationRate, which is the
            % MEAN angular velocity and differs by 2.0e-8 relative - 10.3 um/s
            % at low Earth orbit. The contract is only that this returns one
            % positive number; that it is the RIGHT one is asserted in the
            % reference test that keeps the two constants distinguishable.
            rate = referenceSystem.earthRotationAngleRate();

            testCase.verifySize(rate, [1 1], 'The rate is one scalar per session.');
            testCase.verifyGreaterThan(rate, 0, 'The Earth turns eastward.');
            testCase.verifyEqual(referenceSystem.earthRotationAngleRate(), rate, ...
                'AbsTol', 0, ...
                'The cached second call must return the identical bits.');
        end

        function equinoxNutationMatrix_contract_shapeAndScale(testCase)
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second], "UT1");
            npb = referenceSystem.equinoxNutationMatrix(testCase.cookbookTt());

            testCase.verifySize(npb, [3 3], 'N = 1 returns a plain 3x3.');
            testCase.verifyError(@() referenceSystem.equinoxNutationMatrix(ut1), ...
                'referenceSystem:equinoxNutationMatrix:wrongScale');
        end

    end

    methods (Test, TestTags = {'reference'})

        function rotationTirsToItrs_reference_matchesTheIersAssembly(testCase)
            % INDEPENDENTLY ASSEMBLED, NOT TAKEN FROM SOFA. The matrix below was
            % built in Python from IERS Conventions (2010) equation 5.3,
            % W(IERS) = R3(-s') R2(xp) R1(yp), and then TRANSPOSED, because
            % equation 5.1 uses W(IERS) as the ITRS to TIRS rotation while this
            % function is named for the other direction. It agrees with SOFA
            % iauPom00 to 0.0 once transposed and differs from it by 4.7e-06
            % without the transpose.
            %
            % THAT TRANSPOSE IS THE WHOLE POINT OF THE TEST. The METHOD block of
            % rotationTirsToItrs printed equation 5.3 unchanged from revision
            % 1.0 to 1.72 while the code returned iauPom00, so the help
            % described the inverse of what the function did. Nine green runs
            % did not catch it: a transpose is still orthogonal, still
            % unit-determinant and still round-trips through invertRotation.
            % Only a literal from outside the toolbox can see it.
            %
            % Inputs are the SOFA cookbook pole for 2007-04-05 in radians, with
            % s' from iauSp00 at the same epoch.
            arcsecond = referenceSystem.iersConstants().arcsecondsToRadians;
            xp = TestRotation.CookbookPolarX * arcsecond;
            yp = TestRotation.CookbookPolarY * arcsecond;
            sp = -1.65383565821106972e-11;

            W = referenceSystem.rotationTirsToItrs(xp, yp, sp);

            % 1e-15 bounds the accumulated rounding of a three-factor product of
            % elementary rotations, which is a few ulp of unity. It is NOT an
            % EOP-level bound: the pole coordinates here are exact inputs.
            testCase.verifyEqual(W, TestRotation.PolarMotionAtCookbook, ...
                'AbsTol', 1e-15, ...
                'The polar motion matrix differs from the IERS 5.3 assembly.');
        end

        function rotationGcrsToCirs_reference_matchesTheIersAssembly(testCase)
            % Built in Python from IERS Conventions (2010) equation 5.10,
            % Q = R3(-(E+s)) R2(d) R3(E) with X = sin d cos E and Y = sin d sin
            % E, at the cookbook CIP and the CIO locator s from SOFA iauS06.
            % Agrees with iauC2ixys to 1.1e-16, so the literal pins the whole
            % marshalling path: page order, column-major storage and the
            % argument order of the three angles.
            s = -1.06678325529432728e-08;

            Q = referenceSystem.rotationGcrsToCirs(TestRotation.CookbookX, ...
                TestRotation.CookbookY, s);

            % 1e-15 is a few ulp of a three-factor rotation product of numbers
            % of order unity; it bounds floating-point summation, nothing else.
            testCase.verifyEqual(Q, TestRotation.CelestialToIntermediateAtCookbook, ...
                'AbsTol', 1e-15, ...
                'The celestial-to-intermediate matrix differs from IERS 5.10.');
        end

        function greenwichSiderealTime_reference_matchesTheIers2006Series(testCase)
            % GMST(2006) from IERS Conventions (2010) equation 5.32, evaluated
            % independently in Python as theta(UT1) plus the arcsecond
            % polynomial, with theta from equation 5.15 in SPLIT-ARGUMENT form.
            % Agrees with SOFA iauGmst06 to 2.8e-17 rad.
            %
            % THE SPLIT ARGUMENT IS NOT AN IMPLEMENTATION DETAIL HERE. The same
            % series evaluated on a single-part Julian Date disagrees by
            % 1.19e-09 rad, because eps at JD 2454196 is 4.7e-10 days, that is
            % 4.0e-05 s of rotation. That is decision D9's two-part epoch
            % arguing for itself in the test that checks the function using it.
            %
            % AND THE SPLIT IS NOT UNIQUE, WHICH THE FIRST RUN OF THIS TEST
            % FOUND. The literal below is the series evaluated with the pairing
            % the gateway itself uses, (2400000.5 + day, sec/86400). The
            % equally valid pairing (2400000.5, MJD) gives 2.3407458482043833e-01,
            % which is 1.5e-11 rad = 3 microarcseconds = 0.1 mm at the surface
            % lower. Neither is wrong; the difference is the conditioning of
            % the two-part representation, not the model, and a test asserting
            % at 1e-14 has to say which pairing it means.
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second], "UT1");

            gmst = referenceSystem.greenwichSiderealTime(ut1, testCase.cookbookTt());

            % 1e-14 rad = 2.1 nanoarcseconds bounds the difference between two
            % evaluations of the same polynomial series in different languages;
            % it is set by the ulp of an angle of order 0.234 rad, not by any
            % model error.
            testCase.verifyEqual(gmst, 2.34074584835381072e-01, 'AbsTol', 1e-14, ...
                'GMST differs from the IERS 5.32 series.');
        end

        function greenwichSiderealTime_reference_apparentExceedsMeanByTheEquation(testCase)
            % GAST needs the whole nutation series and cannot be reproduced
            % independently at reasonable cost, so what is asserted here is the
            % quantity that CAN be checked against a published bound: the
            % equation of the equinoxes, whose range is about +-1.2 arcseconds
            % and which is dominated by the 18.6-year nutation term. GAST's
            % ACCURACY is asserted where it belongs, in the continuous
            % equinox-versus-CIO cross-check of risk R13b; what this test adds
            % is that the apparent branch is reached at all and lands in the
            % physically possible interval.
            arcsecond = referenceSystem.iersConstants().arcsecondsToRadians;
            ut1 = referenceSystem.daySecondToEpoch( ...
                [TestRotation.CookbookDay TestRotation.CookbookUt1Second], "UT1");
            tt = testCase.cookbookTt();

            meanTime = referenceSystem.greenwichSiderealTime(ut1, tt, 'Type', "mean");
            apparentTime = referenceSystem.greenwichSiderealTime(ut1, tt, 'Type', "apparent");

            % 20 ARCSECONDS bounds the equation of the equinoxes, which is
            % nutation in longitude times the cosine of the obliquity and
            % therefore reaches about +-17 arcseconds. The first draft of this
            % test wrote 1.2, confusing arcseconds with the seconds of TIME the
            % quantity is usually tabulated in - it is about 1.1 s of time,
            % which is 16 arcseconds. Measured at this epoch: 3.35 arcseconds.
            testCase.verifyLessThan(abs(apparentTime - meanTime), 20 * arcsecond, ...
                'The equation of the equinoxes exceeds its published amplitude.');
            testCase.verifyGreaterThan(abs(apparentTime - meanTime), 1e-9, ...
                'GAST equals GMST, so the apparent branch did nothing.');
        end

        function applyRotation_reference_matchesTheHandComputedRotation(testCase)
            % A quarter turn about z, by hand. The toolbox default sense is
            % FRAME, so R3(pi/2) = [0 1 0; -1 0 0; 0 0 1] and the earth-fixed
            % x axis acquires the components [0; -1; 0]. Every value here is
            % exact in binary, so the assertion is exact.
            R = referenceSystem.rotationZ(pi / 2);

            rotated = referenceSystem.applyRotation(R, [1; 0; 0]);
            back = referenceSystem.applyRotation(R, [1; 0; 0], 'Inverse', true);

            % 1e-16 is one ulp of unity: cos(pi/2) is 6.1e-17 rather than zero,
            % so the residual is the representation of pi/2 and not the product.
            testCase.verifyEqual(rotated, [0; -1; 0], 'AbsTol', 1e-16, ...
                'The forward frame rotation is not the hand-computed one.');
            testCase.verifyEqual(back, [0; 1; 0], 'AbsTol', 1e-16, ...
                'The inverse did not apply the transpose.');
        end

        function invertRotation_reference_isTheTransposeOfEveryPage(testCase)
            % invertRotation moves values and does not compute, so the reference
            % is the transpose itself and the assertion is EXACT. AbsTol 0 is
            % sound here and only here: no arithmetic stands between input and
            % output, so there is no summation whose blocking could differ
            % (obligation O13).
            R = cat(3, referenceSystem.rotationZ(0.3), ...
                referenceSystem.rotationX(-1.1), referenceSystem.rotationY(2.7));
            Rdot = 1e-4 * cat(3, referenceSystem.rotationY(0.2), ...
                referenceSystem.rotationZ(0.9), referenceSystem.rotationX(0.5));

            [Rinv, RdotInv] = referenceSystem.invertRotation(R, Rdot);

            testCase.verifyEqual(Rinv, pagetranspose(R), 'AbsTol', 0, ...
                'The inverse rotation is not the page-wise transpose.');
            testCase.verifyEqual(RdotInv, pagetranspose(Rdot), 'AbsTol', 0, ...
                'The inverse rate is not the page-wise transpose.');
        end

    end

    methods (Test, TestTags = {'precision'})

        function rotationTirsToItrs_precision_isOrthogonalAtRealisticPoles(testCase)
            % The pole wanders by well under an arcsecond, so W is a rotation
            % through a very small angle and the interesting question is whether
            % it stays orthogonal there rather than degenerating to the
            % identity. Both are asserted: orthogonal, and NOT the identity.
            arcsecond = referenceSystem.iersConstants().arcsecondsToRadians;
            xp = linspace(-0.3, 0.3, 40)' * arcsecond;
            yp = linspace(0.1, 0.6, 40)' * arcsecond;

            W = referenceSystem.rotationTirsToItrs(xp, yp, -1.6e-11);
            residual = pagemtimes(W, 'transpose', W, 'none') - eye(3);

            % 1e-15 is a few ulp of a three-term dot product of numbers of order
            % unity, which is what W'W accumulates; it bounds summation error.
            testCase.verifyLessThan(max(abs(residual), [], 'all'), 1e-15, ...
                'The polar motion matrix is not orthogonal.');
            % 1e-7 rad is 0.02 arcseconds, well below the 0.3 arcsecond pole
            % offsets driven above: the matrix must differ from the identity by
            % the pole motion it carries, or it is carrying nothing.
            testCase.verifyGreaterThan(max(abs(W - eye(3)), [], 'all'), 1e-7, ...
                'The polar motion matrix collapsed to the identity.');
        end

    end

end

% -------------------------------------------------------------------------

function varargout = localPartialsWithRates(epoch, eop)
%LOCALPARTIALSWITHRATES Force the seven-output call that gates the rate partials.
%   rotationItrsToGcrsPartials gates the D102 rate partials on nargout >= 5,
%   and an anonymous function cannot make a multiple-output call, so the
%   benchmark that has to pay for them needs a named one.

    [varargout{1:7}] = referenceSystem.rotationItrsToGcrsPartials(epoch, ...
        'Eop', eop);
end


function varargout = localTwoOutputs(epoch, eop, step)
%LOCALTWOOUTPUTS Force a two-output call from inside an anonymous function.

    [varargout{1:2}] = referenceSystem.rotationItrsToGcrs(epoch, 'Eop', eop, ...
        'DifferenceStep', step);
end


function varargout = localInterpolatedRate(epoch, interpolant, step)
%LOCALINTERPOLATEDRATE The interpolated path with Rdot requested.
%   A one-output call computes no difference shoulders, so a refusal that
%   only a shoulder can trigger is invisible to verifyError's plain call.

    [varargout{1:2}] = referenceSystem.rotationItrsToGcrs(epoch, ...
        'Interpolant', interpolant, 'DifferenceStep', step);
end

% -------------------------------------------------------------------------

function localThreeArgumentCall(R)
%LOCALTHREEARGUMENTCALL An odd positional count, which applyRotation refuses.

    referenceSystem.applyRotation(R, zeros(3, 1), zeros(3, 1));
end
