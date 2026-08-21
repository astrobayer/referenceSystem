classdef TestEop < matlab.unittest.TestCase
%TESTEOP Layer L1 test suite — Earth orientation parameters.
%
%   Covers P5 (readEop, downloadEop), P6 (interpolateEop) and P7 (the two tidal
%   corrections). The D30 correction-sense contract spans all three, so both
%   directions of it — acceptance of an additive correction and rejection of a
%   regularization one — are asserted here.
%
%   Fixtures are genuine IERS excerpts of about 200 rows, cut from the four
%   supplied series and deliberately spanning MJD 57654 to 57854, which
%   straddles the 2017-01-01 leap second. That span is not a convenience: the
%   leap-second interpolation test needs a real boundary in real data, and a
%   fixture that avoided one would make the most likely defect in this layer
%   untestable.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 13:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    properties (Constant)
        % The 2017-01-01 leap second: MJD 57753 is 86401 s long, 57754 is the
        % first day of TAI - UTC = 37 s.
        LeapDayMjd = 57753
    end

    properties (TestParameter)
        % Every format the registry claims to support, so that a format added
        % without a fixture fails here rather than in a user's session.
        fixtureName = {'eop14c04.txt', 'eop20c04.txt', ...
            'eop20c04DPsiDEpsilon.txt', 'finals2000A.txt'}
    end

    methods (Test, TestTags = {'contract'})

        function downloadEop_contract_rejectsAnUnknownSeriesWithoutTheNetwork(testCase)
            % OPEN ITEM B3, THE SECOND EXEMPTION THAT WAS WRONG WHEN WRITTEN.
            % downloadEop was exempted from contract coverage because "every
            % code path reaches the network, which section D.2 forbids". The
            % rejection paths do not: series carries a mustBeMember and the
            % arguments block runs before any transfer, so an unknown series
            % is refused offline, deterministically, in microseconds.
            %
            % This is the one downloadEop error a test can reach without a
            % network, and it is worth reaching: mustBeMember is also what
            % keeps the offered series in step with what readEop can read,
            % which TestEop asserts statically elsewhere.
            testCase.verifyError(@() referenceSystem.downloadEop("EOP 21 C04"), ...
                'MATLAB:validators:mustBeMember');
        end


        function readEop_contract_returnsDocumentedFields(testCase, fixtureName)
            eop = referenceSystem.readEop(testCase.fixture(fixtureName));

            testCase.verifyClass(eop, 'struct');
            testCase.verifySize(eop, [1 1]);
            testCase.verifyEqual(sort(string(fieldnames(eop))), ...
                sort(["mjd"; "xp"; "yp"; "dut1"; "lod"; "dX"; "dY"; ...
                "sigma"; "meta"]));
            testCase.verifyEqual(sort(string(fieldnames(eop.sigma))), ...
                sort(["xp"; "yp"; "dut1"; "lod"; "dX"; "dY"]));
            testCase.verifyEqual(sort(string(fieldnames(eop.meta))), ...
                sort(["series"; "cipModel"; "cipModelSource"; ...
                "cipModelStatement"; "poleOffsetType"; "itrf"; "file"; ...
                "readTime"; "nRows"; "mjdRange"; "samplingHour"; "bulletin"]));

            rowCount = numel(eop.mjd);
            testCase.verifyGreaterThan(rowCount, 150);
            for name = ["xp", "yp", "dut1", "lod", "dX", "dY"]
                testCase.verifySize(eop.(name), [rowCount 1], ...
                    "Field " + name + " is not a column of one value per row.");
            end
            testCase.verifyEqual(eop.meta.nRows, rowCount);
        end

        function readEop_contract_identifiesEveryFixtureFormat(testCase)
            % Auto-detection is the part of P5 most likely to rot when a new
            % series appears, so the mapping is asserted explicitly rather than
            % through a round trip.
            expected = ["eop14c04.txt",             "EOP 14 C04"
                        "eop20c04.txt",             "EOP 20 C04"
                        "eop20c04DPsiDEpsilon.txt", "EOP 20 C04 dPsiDEpsilon"
                        "finals2000A.txt",          "finals2000A"];

            for k = 1:size(expected, 1)
                eop = referenceSystem.readEop(testCase.fixture(expected(k,1)));
                testCase.verifyEqual(eop.meta.series, expected(k,2), ...
                    "Fixture " + expected(k,1) + " was identified wrongly.");
            end
        end

        function readEop_contract_rejectsUnidentifiableFile(testCase)
            % Handover P5: if the format cannot be identified, error. Never
            % default, because a wrong column map produces a plausible series.
            scratch = fullfile(tempdir, "referenceSystem_notAnEopFile.txt");
            cleanup = onCleanup(@() TestEop.deleteIfPresent(scratch));
            writelines(["this is not an EOP series"; "1 2 3"], scratch);

            testCase.verifyError(@() referenceSystem.readEop(scratch), ...
                'referenceSystem:readEop:unknownFormat');
        end

        function readEop_contract_reportsThroughInfoNeverByPrinting(testCase)
            % Finding M-6: v1 printed unconditionally on every call. Library
            % code must not print, so the diagnostics leave through info and
            % the absence of output is asserted rather than assumed.
            % The captured names must not collide with a MATLAB function.
            % Written as "[eop, info] = ..." this test failed, not because
            % readEop printed anything, but because evalc warned that the
            % identifier "info" no longer referred to the built-in function of
            % that name -- a warning about the TEST, captured by the test, and
            % reported as though the function under test had printed it. The
            % names below are chosen to shadow nothing.
            fixtureFile = char(testCase.fixture('eop20c04.txt'));
            printed = evalc(['[eopSeries, readInfo] = ' ...
                'referenceSystem.readEop("' fixtureFile '");']);

            testCase.verifyEmpty(strtrim(printed), ...
                "readEop printed to the command window: " + printed);
            testCase.verifyEqual(sort(string(fieldnames(readInfo))), ...
                sort(["rowsRead"; "rowsKept"; "rowsIncomplete"; "gapCount"; ...
                "largestGap"; "duration"]));
            testCase.verifyEqual(readInfo.rowsKept, eopSeries.meta.nRows);
            testCase.verifyEqual(readInfo.gapCount, 0, ...
                'The C04 fixtures are contiguous and must report no gap.');
        end

        function readEop_contract_bulletinBIsFinalsOnly(testCase)
            testCase.verifyError(@() referenceSystem.readEop( ...
                testCase.fixture('eop20c04.txt'), 'Bulletin', "B"), ...
                'referenceSystem:readEop:unsupportedBulletin');

            % finals2000A does carry both, and they differ: Bulletin A is the
            % rapid solution, Bulletin B the final one.
            bulletinA = referenceSystem.readEop( ...
                testCase.fixture('finals2000A.txt'), 'Bulletin', "A");
            bulletinB = referenceSystem.readEop( ...
                testCase.fixture('finals2000A.txt'), 'Bulletin', "B");
            testCase.verifyEqual(bulletinA.meta.bulletin, "A");
            testCase.verifyEqual(bulletinB.meta.bulletin, "B");
            testCase.verifyNotEqual(bulletinA.xp, bulletinB.xp);
        end

        function interpolateEop_contract_rejectsNonUtcEpoch(testCase)
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            tt = referenceSystem.daySecondToEpoch([57700 0], "TT");

            testCase.verifyError( ...
                @() referenceSystem.interpolateEop(eop, tt), ...
                'referenceSystem:interpolateEop:wrongScale');
        end

        function interpolateEop_contract_rejectsSeriesWithoutMeta(testCase)
            % Seam contract S2 item 2: meta travels with the data, unbroken.
            % A series that has lost it cannot reach S3, so it is refused here
            % rather than silently interpolated into something unusable.
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            stripped = rmfield(eop, 'meta');
            utc = referenceSystem.daySecondToEpoch([57700 0], "UTC");

            testCase.verifyError( ...
                @() referenceSystem.interpolateEop(stripped, utc), ...
                'referenceSystem:interpolateEop:missingMeta');
        end

        function interpolateEop_contract_extrapolationPolicies(testCase)
            % THIS TEST ASSERTS A WARNING, SO IT CONSUMES IT. The report lists
            % warnings nobody claimed, and an asserted warning is claimed.
            % Registered as a cleanup so it fires on pass, on failure and on a
            % filtered assumption alike. See WarningRecordingPlugin.
            consumeWarning = onCleanup(@() lastwarn('', ''));
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            outside = referenceSystem.daySecondToEpoch( ...
                [eop.mjd(end) + 5, 0], "UTC");

            testCase.verifyError( ...
                @() referenceSystem.interpolateEop(eop, outside), ...
                'referenceSystem:interpolateEop:outOfRange');

            held = testCase.verifyWarning( ...
                @() referenceSystem.interpolateEop(eop, outside, ...
                'ExtrapolationPolicy', "hold"), ...
                'referenceSystem:interpolateEop:extrapolatedEop');
            testCase.verifyEqual(held.xp, eop.xp(end), 'AbsTol', 0, ...
                'The hold policy must clamp to the edge value exactly.');
            testCase.verifyEqual(held.meta.nExtrapolated, 1);

            marked = referenceSystem.interpolateEop(eop, outside, ...
                'ExtrapolationPolicy', "nan");
            testCase.verifyTrue(isnan(marked.xp));
        end

        function interpolateEop_contract_sigmaIsOptional(testCase)
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            utc = referenceSystem.daySecondToEpoch([57700 3600], "UTC");

            withoutSigma = referenceSystem.interpolateEop(eop, utc);
            withSigma = referenceSystem.interpolateEop(eop, utc, 'Sigma', true);

            testCase.verifyFalse(isfield(withoutSigma, 'sigma'));
            testCase.verifyTrue(isfield(withSigma, 'sigma'));
            testCase.verifyGreaterThan(withSigma.sigma.xp, 0);
        end

        function tidalCorrections_contract_carryTheirSense(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            utc = referenceSystem.daySecondToEpoch([57700 0; 57700 3600], "UTC");
            tt = referenceSystem.convertTimeScale(utc, "TT");

            subdaily = referenceSystem.subdailyEopCorrection(utc);
            zonal = referenceSystem.zonalTideEopCorrection(tt);

            testCase.verifyEqual(subdaily.sense, "additive");
            testCase.verifyEqual(zonal.sense, "regularization");
            testCase.verifyEqual(sort(string(fieldnames(subdaily))), ...
                sort(["dxp"; "dyp"; "dut1"; "sense"; "source"; "model"]));
            testCase.verifyEqual(sort(string(fieldnames(zonal))), ...
                sort(["dut1"; "dlod"; "domega"; "sense"; "source"; "model"]));
            % Decision D55: no dlod on the sub-daily struct, because it would
            % be the libration part only and would look like the whole.
            testCase.verifyFalse(isfield(subdaily, 'dlod'));
        end

        function tidalCorrections_contract_refuseTheWrongScale(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            utc = referenceSystem.daySecondToEpoch([57700 0], "UTC");
            tt = referenceSystem.convertTimeScale(utc, "TT");

            testCase.verifyError( ...
                @() referenceSystem.subdailyEopCorrection(tt), ...
                'referenceSystem:subdailyEopCorrection:wrongScale');
            testCase.verifyError( ...
                @() referenceSystem.zonalTideEopCorrection(utc), ...
                'referenceSystem:zonalTideEopCorrection:wrongScale');
        end

    end

    methods (Test, TestTags = {'reference'})

        function readEop_reference_matchesThePublishedRow(testCase)
            % Independently derived literals: the values are read off the
            % fixture files by eye and converted by hand, so this test checks
            % the column map and the unit conversion together. A shifted map
            % passes every structural test and fails here.
            as2r = referenceSystem.iersConstants().arcsecondsToRadians;

            % eopc04_20, first fixture row, MJD 57654.00:
            %   x = 0.236326"  y = 0.348944"  UT1-UTC = -0.2691148 s
            %   dX = 0.000052" dY = -0.000042"
            eop20 = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            testCase.verifyEqual(eop20.mjd(1), 57654);
            testCase.verifyEqual(eop20.xp(1), 0.236326*as2r, 'RelTol', 1e-14);
            testCase.verifyEqual(eop20.yp(1), 0.348944*as2r, 'RelTol', 1e-14);
            testCase.verifyEqual(eop20.dut1(1), -0.2691148, 'RelTol', 1e-14);
            testCase.verifyEqual(eop20.dX(1), 0.000052*as2r, 'RelTol', 1e-12);
            testCase.verifyEqual(eop20.dY(1), -0.000042*as2r, 'RelTol', 1e-12);

            % finals2000A, MJD 57654: Bulletin A dX and dY are in
            % MILLIarcseconds, and LOD is in MILLIseconds. Getting either unit
            % wrong is a factor of 1000 that no round trip would notice.
            finals = referenceSystem.readEop(testCase.fixture('finals2000A.txt'));
            row = find(finals.mjd == 57654, 1);
            testCase.assertNotEmpty(row, 'MJD 57654 is missing from the fixture.');
            testCase.verifyLessThan(abs(finals.dX(row)), 1e-3*as2r, ...
                'dX looks like arcseconds, not milliarcseconds.');
            testCase.verifyLessThan(abs(finals.lod(row)), 0.01, ...
                'LOD looks like milliseconds, not seconds.');
        end

        function readEop_reference_agreesAcrossSeries(testCase)
            % The four fixtures describe the same days of the same Earth, so
            % they must agree to the level analysis centres differ. This is a
            % genuinely independent check of the two column maps at once: it
            % cannot be satisfied by any self-consistent misreading.
            as2r = referenceSystem.iersConstants().arcsecondsToRadians;
            c04 = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            finals = referenceSystem.readEop(testCase.fixture('finals2000A.txt'));

            [common, inC04, inFinals] = intersect(c04.mjd, finals.mjd);
            testCase.assertGreaterThan(numel(common), 100);

            testCase.verifyLessThan( ...
                max(abs(c04.xp(inC04) - finals.xp(inFinals))), 0.001*as2r, ...
                'C04 and finals2000A disagree in xp beyond 1 mas.');
            testCase.verifyLessThan( ...
                max(abs(c04.dut1(inC04) - finals.dut1(inFinals))), 1e-3, ...
                'C04 and finals2000A disagree in UT1-UTC beyond 1 ms.');
        end

        function readEop_reference_recordsWhatTheFileSaysAboutTheCipModel(testCase)
            % Finding C-2. No IERS file examined states IAU2006/2000A; both
            % 20 C04 products carry the identical line "IAU 2000", on the
            % CIO-based and on the equinox-based product of one solution, which
            % is why that line is recorded verbatim and is not read as a model
            % reference. The registry value is a stated decision and says so.
            eop20 = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            eopPsi = referenceSystem.readEop( ...
                testCase.fixture('eop20c04DPsiDEpsilon.txt'));
            eop14 = referenceSystem.readEop(testCase.fixture('eop14c04.txt'));

            testCase.verifyEqual(eop20.meta.cipModelStatement, "IAU 2000");
            testCase.verifyEqual(eopPsi.meta.cipModelStatement, "IAU 2000", ...
                ['The equinox-based product carries the same statement as ', ...
                'the CIO-based one; if that ever stops being true the line ', ...
                'may be readable as a model reference after all.']);
            testCase.verifyEqual(eop14.meta.cipModelStatement, "");

            for eop = [eop20, eopPsi, eop14]
                testCase.verifyEqual(eop.meta.cipModel, "IAU2006/2000A");
                testCase.verifyEqual(eop.meta.cipModelSource, "format registry");
            end

            overridden = referenceSystem.readEop( ...
                testCase.fixture('eop20c04.txt'), 'CipModel', "IAU2000A");
            testCase.verifyEqual(overridden.meta.cipModel, "IAU2000A");
            testCase.verifyEqual(overridden.meta.cipModelSource, "caller");
        end

        function zonalTideEopCorrection_reference_publishedTestCase(testCase)
            % RG_ZONT2.F published test case: T = 0.07995893223819302 centuries
            % of TT since J2000.0, which is TT MJD 54465.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            tt = referenceSystem.daySecondToEpoch([54465 0], "TT");

            correction = referenceSystem.zonalTideEopCorrection(tt);

            testCase.verifyEqual(correction.dut1, 7.983287678576557467e-2, ...
                'AbsTol', 1e-15);
            testCase.verifyEqual(correction.dlod, 5.035331113978199288e-5, ...
                'AbsTol', 1e-18);
            testCase.verifyEqual(correction.domega, -4.249711616463017e-14, ...
                'AbsTol', 1e-27);
        end

        function subdailyEopCorrection_reference_matchesTheModelSum(testCase)
            % The three model outputs are published individually and are summed
            % here, so the sum is bracketed against the published literal of
            % the dominant component. ORTHO_EOP's own test case is at MJD
            % 47100; PMSDNUT2 and UTLIBR add at most about 30 uas and 3 us at
            % any epoch, so the total must sit inside those windows.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            as2r = referenceSystem.iersConstants().arcsecondsToRadians;
            utc = referenceSystem.daySecondToEpoch([47100 0], "UTC");

            correction = referenceSystem.subdailyEopCorrection(utc);

            testCase.verifyEqual(correction.dxp, -162.8386e-6*as2r, ...
                'AbsTol', 40e-6*as2r);
            testCase.verifyEqual(correction.dyp, 117.7908e-6*as2r, ...
                'AbsTol', 40e-6*as2r);
            testCase.verifyEqual(correction.dut1, -23.3909e-6, 'AbsTol', 4e-6);
        end

    end

    methods (Test, TestTags = {'precision'})

        function interpolateEop_precision_leapSecondBoundary(testCase)
            % Seam contract S2 item 4, and the single most likely defect in
            % this session. UT1 - UTC steps by one second at 2017-01-01.
            % Interpolating it directly smears a fraction of that second into
            % UT1; interpolating UT1 - TAI does not. The tolerance bounds the
            % curvature of UT1 - TAI over one day, which is the algorithmic
            % quantity at stake, and is nowhere near one second.
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            leapDay = TestEop.LeapDayMjd;

            second = (0:600:86400-600)';
            utc = referenceSystem.daySecondToEpoch( ...
                [[leapDay*ones(numel(second),1); (leapDay+1)*ones(numel(second),1)], ...
                 [second; second]], "UTC");

            interpolated = referenceSystem.interpolateEop(eop, utc);

            % UT1 - TAI is what must be smooth. Reconstruct it and check that
            % its second difference stays at the curvature level rather than
            % showing a one-second step.
            deltaAt = referenceSystem.leapSecondTable("deltaAT", utc);
            ut1MinusTai = interpolated.dut1 - deltaAt;
            step = diff(ut1MinusTai);

            testCase.verifyLessThan(max(abs(diff(step))), 1e-6, ...
                ['UT1 - TAI is not smooth across the leap second: the ', ...
                'interpolation is being done on UT1 - UTC somewhere.']);
            testCase.verifyGreaterThan(max(abs(diff(interpolated.dut1))), 0.5, ...
                ['UT1 - UTC shows no step across the leap second, which ', ...
                'means the leap second was not applied at all.']);
        end

        function interpolateEop_precision_reproducesTableAtNodes(testCase, fixtureName)
            % At a tabulated epoch, interpolation must return the tabulated
            % value exactly. The tolerance bounds the interpolation arithmetic,
            % not the EOP: linear interpolation at a node is an exact identity
            % up to the rounding of the abscissa.
            eop = referenceSystem.readEop(testCase.fixture(fixtureName));
            node = (20:20:100)';
            mjd = eop.mjd(node);
            utc = referenceSystem.daySecondToEpoch( ...
                [floor(mjd), (mjd - floor(mjd))*86400], "UTC");

            interpolated = referenceSystem.interpolateEop(eop, utc);

            for name = ["xp", "yp", "lod", "dX", "dY"]
                testCase.verifyEqual(interpolated.(name), eop.(name)(node), ...
                    'AbsTol', 1e-18, ...
                    "Interpolation at a node changed " + name + ".");
            end
            testCase.verifyEqual(interpolated.dut1, eop.dut1(node), 'AbsTol', 1e-12);
        end

        function readEop_precision_dPsiDEpsilonConversionRoundTrips(testCase)
            % Risk R13c and seam contract S2 item 3. The equinox-based product
            % and the CIO-based product describe the same pole, so converting
            % the first must reproduce the second.
            %
            % WHAT THIS TEST MEASURES, and what it deliberately does not. The
            % two IERS products are sampled twelve hours apart, so any
            % comparison has to interpolate a daily series across half a day,
            % and that interpolation error is far larger than the conversion
            % error being tested. Written as a straight residual bound this
            % test failed at 64 uas -- and the conversion was correct all
            % along. Measured decomposition:
            %
            %   mean residual                        0.3 uas   (no bias)
            %   neglected second-order term          1.2 uas
            %   residual scatter, linear interp     10.4 uas rms, 64 uas peak
            %   residual scatter, spline interp      5.4 uas rms, 31 uas peak
            %
            % So the scatter is interpolation and the conversion is sound. The
            % assertion is therefore on the regression of converted against
            % published, where a conversion error appears as a slope or an
            % offset and interpolation noise does not. The failure modes this
            % separates are large and unmistakable:
            %
            %   correct                    slope  1.000
            %   sin(eps0) omitted          slope  2.514
            %   cos(eps0) used instead     slope  2.307
            %   sign error                 slope -1.000
            %
            % The scatter is still bounded, generously, so that a gross
            % regression cannot hide behind a fitted slope.
            as2r = referenceSystem.iersConstants().arcsecondsToRadians;
            fromPsi = referenceSystem.readEop( ...
                testCase.fixture('eop20c04DPsiDEpsilon.txt'));
            direct = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));

            testCase.verifyEqual(fromPsi.meta.poleOffsetType, ...
                "converted from dPsiDEpsilon");
            testCase.verifyEqual(direct.meta.poleOffsetType, "observed dXdY");

            inside = fromPsi.mjd > direct.mjd(1) & fromPsi.mjd < direct.mjd(end);
            mjd = fromPsi.mjd(inside);
            utc = referenceSystem.daySecondToEpoch( ...
                [floor(mjd), (mjd - floor(mjd))*86400], "UTC");
            reference = referenceSystem.interpolateEop(direct, utc, ...
                'Method', "spline");

            for name = ["dX", "dY"]
                converted = fromPsi.(name)(inside);
                published = reference.(name);
                fit = [published, ones(size(published))] \ converted;

                testCase.verifyEqual(fit(1), 1, 'AbsTol', 0.02, ...
                    "The " + name + " conversion has the wrong scale; " + ...
                    "check the obliquity and which trigonometric function " + ...
                    "is applied.");
                testCase.verifyLessThan(abs(fit(2)), 5e-6*as2r, ...
                    "The " + name + " conversion carries a constant offset.");
                testCase.verifyLessThan(max(abs(converted - published)), ...
                    100e-6*as2r, ...
                    "The " + name + " residual exceeds what half a day of " + ...
                    "interpolation can explain.");
            end
        end

        function subdailyEopCorrection_precision_isPeriodicNotSecular(testCase)
            % These are tidal terms with periods of a day or less, so over a
            % long arc their mean must be near zero and their amplitude
            % bounded. A secular drift would mean an argument is being formed
            % from the wrong epoch. Bounds the model output, not the EOP.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            as2r = referenceSystem.iersConstants().arcsecondsToRadians;
            day = 57700 + floor((0:2879)'/24);
            second = mod((0:2879)', 24) * 3600;
            utc = referenceSystem.daySecondToEpoch([day second], "UTC");

            correction = referenceSystem.subdailyEopCorrection(utc);

            testCase.verifyLessThan(abs(mean(correction.dxp)), 0.05e-3*as2r);
            testCase.verifyLessThan(abs(mean(correction.dut1)), 5e-6);
            testCase.verifyLessThan(max(abs(correction.dxp)), 1e-3*as2r, ...
                'Sub-daily polar motion exceeds 1 mas, which it cannot.');
            testCase.verifyLessThan(max(abs(correction.dut1)), 1e-4, ...
                'Sub-daily UT1 exceeds 100 us, which it cannot.');
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function interpolateEop_vectorization_arcEqualsLoop(testCase)
            % AbsTol 0 is sound because interpolation is elementwise in the query epoch: each
            % result is one multiply and one add on its own bracketing pair, with no reduction
            % across queries (obligation O13).
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            mjd = 57700 + (0:9)'/10;
            utc = referenceSystem.daySecondToEpoch( ...
                [floor(mjd), (mjd - floor(mjd))*86400], "UTC");

            wholeArc = referenceSystem.interpolateEop(eop, utc);

            for k = 1:numel(mjd)
                single = referenceSystem.interpolateEop(eop, ...
                    referenceSystem.daySecondToEpoch( ...
                    [floor(mjd(k)), (mjd(k) - floor(mjd(k)))*86400], "UTC"));
                for name = ["xp", "yp", "dut1", "lod", "dX", "dY"]
                    testCase.verifyEqual(wholeArc.(name)(k), single.(name), ...
                        'AbsTol', 0, ...
                        "Arc and single-epoch results differ in " + name + ".");
                end
            end
        end

        function subdailyEopCorrection_vectorization_arcEqualsLoop(testCase)
            % AbsTol 0 is sound because the tidal series is summed per epoch in C, in the same
            % order whatever the arc length, with no reduction across epochs (obligation O13).
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            second = (0:3600:82800)';
            utc = referenceSystem.daySecondToEpoch( ...
                [57700*ones(numel(second),1) second], "UTC");

            wholeArc = referenceSystem.subdailyEopCorrection(utc);

            for k = 1:numel(second)
                single = referenceSystem.subdailyEopCorrection( ...
                    referenceSystem.daySecondToEpoch([57700 second(k)], "UTC"));
                testCase.verifyEqual(wholeArc.dxp(k), single.dxp, 'AbsTol', 0);
                testCase.verifyEqual(wholeArc.dut1(k), single.dut1, 'AbsTol', 0);
            end
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function interpolateEop_diagnostics_acceptsAdditiveCorrection(testCase)
            % Seam contract S2 item 1, acceptance direction. An additive
            % correction is applied without ceremony and moves the values.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            utc = referenceSystem.daySecondToEpoch( ...
                [57700*ones(4,1) (0:6*3600:18*3600)'], "UTC");
            subdaily = referenceSystem.subdailyEopCorrection(utc);

            plain = referenceSystem.interpolateEop(eop, utc);
            corrected = referenceSystem.interpolateEop(eop, utc, ...
                'Correction', subdaily);

            testCase.verifyEqual(corrected.xp, plain.xp + subdaily.dxp, ...
                'AbsTol', 0, ...
                'The additive correction was not added, or was scaled.');
            testCase.verifyEqual(corrected.dut1, plain.dut1 + subdaily.dut1, ...
                'AbsTol', 0);
            testCase.verifyEqual(corrected.meta.corrections, ...
                "subdailyEopCorrection");
            testCase.verifyFalse(corrected.meta.regularized);
        end

        function interpolateEop_diagnostics_refusesRegularizationByDefault(testCase)
            % Seam contract S2 item 1, rejection direction, and the reason
            % decision D30 exists. Getting this backwards costs up to 168 ms of
            % UT1 and has no symptom.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            utc = referenceSystem.daySecondToEpoch([57700 0], "UTC");
            tt = referenceSystem.convertTimeScale(utc, "TT");
            zonal = referenceSystem.zonalTideEopCorrection(tt);

            testCase.verifyError(@() referenceSystem.interpolateEop(eop, utc, ...
                'Correction', zonal), ...
                'referenceSystem:interpolateEop:wrongCorrectionSense');

            % With the flag it is accepted, and SUBTRACTED. The sign is the
            % whole hazard, so it is asserted rather than described.
            plain = referenceSystem.interpolateEop(eop, utc);
            regularized = referenceSystem.interpolateEop(eop, utc, ...
                'Correction', zonal, 'Regularize', true);

            testCase.verifyEqual(regularized.dut1, plain.dut1 - zonal.dut1, ...
                'AbsTol', 0, ...
                'The regularization correction must be subtracted, not added.');
            testCase.verifyTrue(regularized.meta.regularized);
        end

        function interpolateEop_diagnostics_refusesUntaggedCorrection(testCase)
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            utc = referenceSystem.daySecondToEpoch([57700 0], "UTC");
            untagged = struct('dut1', 1e-6, 'source', "handmade");

            testCase.verifyError(@() referenceSystem.interpolateEop(eop, utc, ...
                'Correction', untagged), ...
                'referenceSystem:interpolateEop:wrongCorrectionSense');
        end

        function readEop_diagnostics_metaSurvivesInterpolation(testCase)
            % Seam contract S2 item 2. If meta is dropped anywhere in this
            % pipeline, S3 cannot work, so the survival of every field is
            % asserted rather than spot-checked.
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            utc = referenceSystem.daySecondToEpoch([57700 0], "UTC");

            interpolated = referenceSystem.interpolateEop(eop, utc);

            for name = string(fieldnames(eop.meta))'
                testCase.verifyTrue(isfield(interpolated.meta, name), ...
                    "meta." + name + " was lost by interpolateEop.");
                testCase.verifyEqual(interpolated.meta.(name), eop.meta.(name), ...
                    "meta." + name + " was altered by interpolateEop.");
            end
            testCase.verifyEqual(interpolated.meta.method, "linear");
        end

        function readEop_diagnostics_wrongFormatIsRefused(testCase)
            % Forcing a real file to be read as the wrong series must be
            % refused by layout, before any value is interpreted. finals2000A
            % carries an I/P flag character where the C04 layout expects a
            % number, so the field count check fires first and names the
            % mismatch.
            %
            % The identifier is asserted rather than accepting any MException.
            % Written as ?MException this test PASSED in the S2 run while
            % readEop was broken in a completely unrelated way: it threw, the
            % assertion was satisfied, and the green result meant nothing. A
            % test that cannot tell why it passed is not a test.
            testCase.verifyError(@() referenceSystem.readEop( ...
                testCase.fixture('finals2000A.txt'), 'Format', "EOP 20 C04"), ...
                'referenceSystem:readEop:unknownFormat');
        end

        function readEop_diagnostics_implausibleValuesAreRefused(testCase)
            % The range gate proper, which is the last thing standing between a
            % column map that happens to fit and a plausible wrong answer. It
            % is exercised directly, with a file of the right shape and absurd
            % content, because relying on a real mis-read to reach it only
            % tests whichever check fires first.
            scratch = fullfile(tempdir, "referenceSystem_absurdEop.txt");
            cleanup = onCleanup(@() TestEop.deleteIfPresent(scratch));

            % A well-formed EOP 20 C04 row whose polar motion is 5 arcseconds:
            % correct layout, correct field count, physically impossible value.
            header = ["# EOP (IERS) 20 C04 TIME SERIES consistent with ITRF 2020"
                      "# Reference Precession-Nutation Model: IAU 2000"];
            row = "2016   9  23   0  57654.00    5.000000    0.348944  " + ...
                  "-0.2691148    0.000052   -0.000042   -0.000296    0.000920  " + ...
                  " 0.0011021    0.000030    0.000030   0.0000059    0.000064  " + ...
                  " 0.000064    0.000043    0.000043   0.0000101";
            writelines([header; row], scratch);

            testCase.verifyError(@() referenceSystem.readEop(scratch), ...
                'referenceSystem:readEop:implausibleValue');
        end

    end

    methods (Access = private)

        function path = fixture(testCase, name)
            %FIXTURE Absolute path of a named fixture file.
            path = string(fullfile(testCase.toolboxRoot(), 'test', 'fixtures', name));
        end

        function root = toolboxRoot(~)
            %TOOLBOXROOT Absolute path of the distribution folder.
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function folder = packageFolder(testCase)
            %PACKAGEFOLDER Absolute path of the +referenceSystem folder.
            folder = fullfile(testCase.toolboxRoot(), '+referenceSystem');
        end

    end

    methods (Static, Access = private)

        function deleteIfPresent(file)
            %DELETEIFPRESENT Remove a scratch file, tolerating its absence.
            if isfile(file)
                delete(file);
            end
        end

    end


    methods (Test, TestTags = {'contract'})

        function subdailyEopCorrection_contract_refusesANonUtcEpoch(testCase)
            % Decision D57: the sub-daily models are driven with UTC and the
            % zonal model with TT, each refusing the other, because each
            % routine's own header says so. Supplying TT here would be wrong by
            % TT - UTC, about 69 s, which at a 12-hour tidal period is 0.6
            % degrees of tidal phase.
            tt = referenceSystem.daySecondToEpoch([57660 43200], "TT");

            testCase.verifyError(@() referenceSystem.subdailyEopCorrection(tt), ...
                'referenceSystem:subdailyEopCorrection:wrongScale');
        end

        function downloadEop_contract_offersExactlyTheSeriesReadEopCanRead(testCase)
            % A SEAM, NOT A FORMALITY, and it is checked statically because
            % section D.2 forbids a test that needs the network. downloadEop
            % fetches a series and readEop must be able to read it; if the two
            % name sets ever diverge, the toolbox will happily download a file
            % it cannot open, and the user finds out after the transfer.
            %
            % Both lists are read from the source rather than restated here, so
            % this test cannot be satisfied by editing the test.
            downloadSource = fileread(fullfile(testCase.packageFolder(), ...
                'downloadEop.m'));
            readSource = fileread(fullfile(testCase.packageFolder(), 'readEop.m'));

            offered = TestEop.quotedSeriesNames(downloadSource);
            readable = TestEop.quotedSeriesNames(readSource);

            testCase.assertNotEmpty(offered, 'No series names found in downloadEop.');
            unreadable = setdiff(offered, readable);

            % THE DIAGNOSTIC IS BUILT FROM A GUARDED LIST. join of an empty
            % string array returns <missing>, and verifyEmpty evaluates its
            % message eagerly - so the passing case ERRORED on its own
            % diagnostic in the first S6 run. The empty branch is the one that
            % runs every time the test succeeds, which is exactly the branch a
            % message is least likely to be exercised in.
            if isempty(unreadable)
                offence = "none";
            else
                offence = join(unreadable, ", ");
            end
            testCase.verifyEmpty(unreadable, ...
                "downloadEop offers a series readEop cannot read: " + offence);
        end

    end

    methods (Test, TestTags = {'reference'})

        function interpolateEop_reference_matchesAnIndependentLinearInterpolation(testCase)
            % The expected values were computed in Python directly from the
            % fixture rows for MJD 57660 and 57661, as a + 0.25 (b - a), with the
            % published arcsecond-to-radian factor applied afterwards. Nothing
            % from this toolbox took part.
            %
            % The epoch is a QUARTER of the way between two nodes, not a half:
            % at a half, a linear interpolation and any symmetric alternative
            % agree, so the test would not distinguish them.
            eop = referenceSystem.readEop(testCase.fixture('eop20c04.txt'));
            epoch = referenceSystem.daySecondToEpoch([57660 21600], "UTC");

            atEpoch = referenceSystem.interpolateEop(eop, epoch);

            % 1e-20 rad on polar motion and 1e-16 s on UT1 are a few ulp of the
            % interpolated quantities themselves - 1.1e-06 rad and 0.28 s - so
            % they bound the arithmetic of one multiply and one add. THEY ARE
            % NOT EOP-LEVEL BOUNDS: the formal error of the series is 3e-4
            % arcseconds, eleven orders larger, and asserting at that level
            % would pass any interpolation whatsoever.
            testCase.verifyEqual(atEpoch.xp, 1.13432705393140089e-06, ...
                'AbsTol', 1e-20, 'The interpolated xp differs from the independent one.');
            testCase.verifyEqual(atEpoch.yp, 1.61958918769596311e-06, ...
                'AbsTol', 1e-20, 'The interpolated yp differs from the independent one.');
            % 1e-14 s, NOT the 1e-16 the value's own magnitude would suggest.
            % interpolateEop is leap-second safe: it converts UT1-UTC to
            % UT1-TAI, interpolates that, and converts back, so the arithmetic
            % passes through a quantity of order 37 s whose eps is 7.1e-15.
            % The bound is a few ulp OF THE INTERMEDIATE, which is what
            % dominates - the first attempt bounded the ulp of the answer and
            % was measuring a quantity the computation never held (O8).
            testCase.verifyEqual(atEpoch.dut1, -2.76550424999999989e-01, ...
                'AbsTol', 1e-14, 'The interpolated UT1-UTC differs from the independent one.');
            testCase.verifyEqual(atEpoch.dX, 8.44787839333366386e-10, ...
                'AbsTol', 1e-24, 'The interpolated dX differs from the independent one.');
            testCase.verifyEqual(atEpoch.lod, 1.37752500000000010e-03, ...
                'AbsTol', 1e-18, 'The interpolated LOD differs from the independent one.');
        end

    end

    methods (Test, TestTags = {'precision'})

        function zonalTideEopCorrection_precision_lodIsTheRateOfTheUt1Term(testCase)
            % AN INTERNAL RELATION OF THE MODEL, NOT A ROUND TRIP. RG_ZONT2
            % returns the zonal tide effect on UT1 and on the excess length of
            % day, and the second is minus the time derivative of the first:
            % a day that is dLOD longer is a day in which UT1 falls behind by
            % that much. The two come from separately summed series, so the
            % relation is a real check on both.
            %
            % THE STEP IS A TENTH OF A DAY, NOT A DAY, and the difference is
            % rescaled to per-day afterwards. At h = 1 day, which is the unit
            % dLOD is expressed in and therefore the obvious choice, the
            % truncation is about one per cent: the series carries terms with
            % periods down to about five days, and (h^2/6) f''' for an
            % amplitude of 1e-4 s at that period is 3e-5 s/day. Measured
            % against the compiled Fortran port: the ratio -rate/dlod is 0.99
            % at h = 1 day and 1.0000 +- 4e-4 at h = 0.1 day, so the relation
            % is exact and the first attempt was measuring its own step.
            day = (55000:20:56000)';
            centre = referenceSystem.daySecondToEpoch([day, ...
                zeros(size(day)) + 43200], "TT");
            before = referenceSystem.daySecondToEpoch([day, ...
                zeros(size(day)) + 43200 - 4320], "TT");
            after = referenceSystem.daySecondToEpoch([day, ...
                zeros(size(day)) + 43200 + 4320], "TT");

            atCentre = referenceSystem.zonalTideEopCorrection(centre);
            rate = (referenceSystem.zonalTideEopCorrection(after).dut1 - ...
                referenceSystem.zonalTideEopCorrection(before).dut1) / 0.1;

            % 1e-7 s/day bounds the SECOND-ORDER TRUNCATION at h = 0.1 day,
            % measured at 2.4e-08 s/day against the compiled Fortran over this
            % span. It is a truncation bound, proportional to h^2, and must be
            % re-derived rather than relaxed if the step or the model changes.
            testCase.verifyLessThan(max(abs(-rate - atCentre.dlod)), 1e-7, ...
                'The zonal LOD term is not the rate of the zonal UT1 term.');
        end

    end

    methods (Static, Access = private)

        function name = quotedSeriesNames(sourceText)
            %QUOTEDSERIESNAMES The IERS product names a source file mentions.
            %   Matched on the published product names themselves rather than on
            %   the shape of an arguments block, so the check survives a
            %   refactoring of either file.
            candidate = ["EOP 14 C04", "EOP 20 C04", ...
                "EOP 20 C04 dPsiDEpsilon", "finals2000A"];
            name = candidate(arrayfun(@(c) contains(string(sourceText), c), ...
                candidate));
            name = name(:);
        end

    end

end
