classdef TestPerformance < matlab.unittest.TestCase
%TESTPERFORMANCE Cross-cutting speed suite and the report record formats.
%
%   Benchmarks are added by P17 as each layer completes, against the targets of
%   handover section B.7. A benchmark warns when it is slower than its target
%   and fails only beyond five times it, because the target is machine
%   dependent while a fivefold miss is a defect.
%
%   This class also owns the two record formats that referenceSystem.runTestSuite
%   parses into the BENCHMARKS and CONVERGENCE sections of the report. A test
%   that measures something builds the record here and logs it itself:
%
%       testCase.log(matlab.unittest.Verbosity.Concise, ...
%           TestPerformance.benchmarkRecord("convertItrf", 1e6, 0.412, 0.5));
%
%   The measuring test therefore owns its numbers, this class owns their format
%   and the runner owns only their layout — one authority each.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly; it must never import the package (handover section C.5 rule 4).
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    methods (Test, TestTags = {'contract'})

        function benchmarkRecord_contract_matchesRunnerPattern(testCase)
            % The runner parses these records with a fixed pipe-separated
            % pattern. If the two ever disagree the report silently loses every
            % benchmark row, which is why the format is asserted here.
            % FIVE FIELDS SINCE REV. 1.86, and the FOUR-ARGUMENT CALL IS
            % TESTED FIRST because that is the one that broke. Nine speed tests
            % failed in run 20 for a defect in the optional argument's default,
            % and this test - which exists to guard exactly this format - did
            % not see it, because it always passed all the arguments. A test
            % for an optional argument that never omits it is testing the other
            % case. Both are exercised now.
            record = TestPerformance.benchmarkRecord("convertItrf", 1000000, 0.412, 0.5);
            token = regexp(record, TestPerformance.recordPattern("BENCHMARK", 5), ...
                'tokens', 'once');

            testCase.assertNumElements(token, 5, ...
                "The record did not split into five fields: " + record);
            testCase.verifyEqual(token(1), "convertItrf", 'Function name field.');
            testCase.verifyEqual(str2double(token(2)), 1000000, 'Problem size field.');
            testCase.verifyEqual(str2double(token(3)), 0.412, 'RelTol', 1e-12, ...
                'Measured median field.');
            testCase.verifyEqual(str2double(token(4)), 0.5, 'RelTol', 1e-12, ...
                'Target field.');
            testCase.verifyTrue(isnan(str2double(token(5))), ...
                'An omitted fastest time is carried as NaN, not as zero.');

            withFastest = TestPerformance.benchmarkRecord("convertItrf", 1000000, ...
                0.412, 0.5, 0.401);
            token = regexp(withFastest, TestPerformance.recordPattern("BENCHMARK", 5), ...
                'tokens', 'once');
            testCase.assertNumElements(token, 5, ...
                "The five-argument record did not split into five fields: " + withFastest);
            testCase.verifyEqual(str2double(token(5)), 0.401, 'RelTol', 1e-12, ...
                'Fastest field.');
        end

        function convergenceRecord_contract_matchesRunnerPattern(testCase)
            % Same contract for the D28 convergence rows, including the case of
            % an undetermined order, which is printed as a dash rather than NaN.
            record = TestPerformance.convergenceRecord("Qdot", 600, 3.1e-5, NaN, "--");
            token = regexp(record, TestPerformance.recordPattern("CONVERGENCE", 5), ...
                'tokens', 'once');

            testCase.assertNumElements(token, 5, ...
                "The record did not split into five fields: " + record);
            testCase.verifyEqual(token(1), "Qdot", 'Quantity field.');
            testCase.verifyEqual(str2double(token(2)), 600, 'Step field.');
            testCase.verifyEqual(str2double(token(3)), 3.1e-5, 'RelTol', 1e-12, ...
                'Relative error field.');
            testCase.verifyEqual(token(4), "--", 'Undetermined order prints as a dash.');
            testCase.verifyEqual(token(5), "--", 'Status field.');
        end

        function noteRecord_contract_matchesRunnerPatternAndStripsSeparators(testCase)
            % Same contract as the other two formats, plus the property the
            % other two do not need: these fields carry text read from files,
            % so a pipe or a newline inside one must not become a column
            % boundary. The subject below contains both.
            record = TestPerformance.noteRecord("readEphemeris" + newline + ...
                "comment area", "ephemeris=|" + string(char(0)) + ...
                ",verified=false", "D15 pairing, read from de440s.bsp");
            token = regexp(record, TestPerformance.recordPattern("NOTE", 3), ...
                'tokens', 'once');

            testCase.assertNumElements(token, 3, ...
                "The record did not split into three fields: " + record);
            testCase.verifyEqual(token(1), "readEphemeris comment area", ...
                'A newline inside a field is folded to a space.');
            testCase.verifyEqual(token(2), "ephemeris= ,verified=false", ...
                'A pipe and a NUL inside a field fold to one space.');
            testCase.verifyFalse(any(char(record) < 32 & char(record) ~= 10), ...
                'The record carries a control character.');
            testCase.verifyEqual(token(3), "D15 pairing, read from de440s.bsp");
        end

        function verifiedConvergence_contract_returnsTheRowItAsserted(testCase)
            % OPEN ITEM D1. The property that matters is not that the helper
            % verifies - verifyLessThan already did that - but that it CANNOT
            % verify without handing back something to log. So the test checks
            % the return value, in the passing case, which is precisely the
            % case that used to leave no trace.
            record = TestPerformance.verifiedConvergence(testCase, "dR/dTest", ...
                1e-3, 1.66e-7, 1e-6, NaN, "roundoff-limited");
            token = regexp(record, TestPerformance.recordPattern("CONVERGENCE", 5), ...
                'tokens', 'once');

            testCase.assertNumElements(token, 5, ...
                "The returned record is not a CONVERGENCE row: " + record);
            testCase.verifyEqual(token(1), "dR/dTest");
            testCase.verifyEqual(str2double(token(3)), 1.66e-7, 'RelTol', 1e-2);
            testCase.verifyEqual(token(5), "roundoff-limited");
        end

        function verifiedBenchmark_contract_judgesTheFastestRepetition(testCase)
            % THE FIVE-TIMES RULE AND THE FASTEST-REPETITION RULE ARE BOTH IN
            % THE HELPER NOW, so they are tested here once instead of being
            % restated at each speed call site. The median is deliberately over
            % target and the fastest under it: this must PASS, because that is
            % the loaded-host case the rule exists for.
            record = TestPerformance.verifiedBenchmark(testCase, "unitTest", ...
                1000, 0.9, 0.2, 0.15);
            token = regexp(record, TestPerformance.recordPattern("BENCHMARK", 5), ...
                'tokens', 'once');

            testCase.assertNumElements(token, 5, ...
                "The returned record is not a BENCHMARK row: " + record);
            testCase.verifyEqual(str2double(token(3)), 0.9, 'RelTol', 1e-12, ...
                'The report carries the median.');
            testCase.verifyEqual(str2double(token(5)), 0.15, 'RelTol', 1e-12, ...
                'The assertion used the fastest.');
        end

    end

    methods (Test, TestTags = {'speed'})
        % Benchmarks are added by P17 against the section B.7 targets.
    end

    methods (Test, TestTags = {'concurrency'})
        % Section C.9 and decision D31. Added by P2 and P3: the leapSecondTable
        % override must be shown not to reach parfor workers, and an identical
        % arc at one, two and N threads must satisfy isequal on the raw bits.
    end

    methods (Static)

        function state = graceFoOrbitArc()
            %GRACEFOORBITARC The GNI1B orbit for the same eleven seconds.
            %   GRACE C, 2025-01-01, GNI1B version 04, inertial position and
            %   velocity in metres and metres per second, at the same GPS
            %   seconds as graceFoArc so the two pair up row by row.
            %
            %   Rows 1 to 3 are x, y, z; rows 4 to 6 are vx, vy, vz.
            %   Together with graceFoArc this is what pins ALL THREE
            %   spacecraft axes rather than only the rotation axis.
            state = [ ...
                140225.2950093752, 140049.5177350202, 139873.5664215875, ...
                139697.4412881411, 139521.142553957, 139344.6704385229, ...
                139168.0251615373, 138991.2069429096, 138814.2160027604, ...
                138637.0525614203, 138459.7168394303; ...
                -71382.78398833182, -63747.72075436251, -56112.57824254977, ...
                -48477.36593688457, -40842.09332137539, -33206.76988003657, ...
                -25571.40509687677, -17936.00845588586, -10300.58944102821, ...
                -2665.157536226103, 4970.277774650367; ...
                6831597.447842967, 6831685.03146452, 6831764.105078746, ...
                6831834.668619358, 6831896.7220306, 6831950.265267261, ...
                6831995.298294672, 6832031.821088698, 6832059.833635753, ...
                6832079.335932786, 6832090.327987284; ...
                -175.6901818459877, -175.8643303854926, -176.0382599666093, ...
                -176.2119703775179, -176.3854614066499, -176.5587328426878, ...
                -176.7317844745647, -176.9046160914849, -177.077227482857, ...
                -177.2496184383606, -177.4217887479236; ...
                7635.020433721092, 7635.104453551603, 7635.178989403918, ...
                7635.24404125466, 7635.299609092036, 7635.345692915856, ...
                7635.382292737533, 7635.409408579837, 7635.427040477705, ...
                7635.43518847744, 7635.433852636986; ...
                91.8386004795335, 83.32862981439598, 74.81858758695445, ...
                66.30848433750208, 57.79833060636669, 49.28813693389931, ...
                40.77791386046115, 32.26767192605785, 23.75742167141333, ...
                15.2471736368666, 6.73693836270805; ...
                ];
        end


        function residual = rotationRateSkewResidual(R, Rdot)
            %ROTATIONRATESKEWRESIDUAL The seam item 6 invariant, in one place.
            %   Differentiating R'R = I gives Rdot'R + R'Rdot = 0 for any
            %   proper rotation and its true derivative, at any step. It
            %   catches a sign error or a transposition that no magnitude
            %   comparison would.
            %
            %   S5 seam item 6 asks for one invariant, one helper and two call
            %   sites: rotationItrsToGcrs in TestRotation and
            %   angularVelocityToRotationRate in TestNavigation. Until this
            %   existed both carried their own copy of the expression, which is
            %   the duplicate-authority pattern this toolbox rejects elsewhere.
            %
            %   THE TOLERANCE IS DELIBERATELY NOT FIXED HERE. The residual
            %   cancels terms of order |Rdot|, so its floor is a few ulp of
            %   that: 1e-17 is right where |Rdot| ~ 7e-05, the Earth rotation
            %   case, and unreachable where |Rdot| ~ 0.1, a spacecraft rate.
            %   Run 1 of S5 failed on exactly that difference. The invariant is
            %   shared; the bound is a claim about the quantity under test and
            %   is stated at each call site.
            residual = pagemtimes(Rdot, 'transpose', R, 'none') + ...
                pagemtimes(R, 'transpose', Rdot, 'none');
        end

        function q = graceFoArc()
            %GRACEFOARC Eleven seconds of real GRACE-FO star camera attitude.
            %   GRACE C, 2025-01-01, SCA1B version 04, GPS seconds 788963364
            %   to 788963374 at 1 Hz, columns 4 to 7 verbatim. Scalar first,
            %   inertial frame to SRF - the frame sense and quaternion layout
            %   attitudeConvention("geodetic") declares.
            %
            %   RISK R20 IS WHY THIS DATA IS HERE. A wrong quaternion order,
            %   sense or product still yields an orthogonal, unit-determinant
            %   matrix that round-trips through its own inverse, so no
            %   self-test can catch a consistently wrong toolbox. The register
            %   names one defence and this is it.
            %
            %   THIS ARC WAS CHOSEN, not taken from the head of the file: q0
            %   crosses zero inside it, a rotation passing through 180 degrees,
            %   which is where the canonical q0 >= 0 form is least stable.
            q = [ ...
                0.002325113886327394, 0.00193351783004252, 0.001541972582721839, ...
                0.001150145763363516, 0.0007580255395939865, 0.000366139375462138, ...
                -2.564814725591076e-05, -0.0004176266601672051, -0.0008094728648309795, ...
                -0.001201244315590975, -0.00159311805134395; ...
                -0.7212971142436002, -0.7213166091757841, -0.7213358901757874, ...
                -0.7213549580370936, -0.7213736745930137, -0.7213919831476528, ...
                -0.7214100948566413, -0.7214279360822393, -0.7214456708254627, ...
                -0.7214631294687117, -0.7214803824481284; ...
                0.6925983140145425, 0.692582383874365, 0.6925662258641861, ...
                0.6925498389679203, 0.6925333656334512, 0.6925168652152808, ...
                0.6925001193260003, 0.6924832038386264, 0.6924659481854999, ...
                0.6924485291362164, 0.6924308724604974; ...
                0.005713351821283484, 0.005315299640362047, 0.004917189634060588, ...
                0.004519080739893087, 0.004121224791104677, 0.003723455307070475, ...
                0.003325525464914778, 0.002927631171502131, 0.002529718247188133, ...
                0.002131750740951003, 0.001733985873834988; ...
                ];
        end


        function point = earthFixedCloud(pointCount)
            %EARTHFIXEDCLOUD Earth-fixed Cartesian points for a million-point benchmark.
            %   A spread over latitude and longitude rather than one point
            %   repeated, so a benchmark meets the branch mix the iterative
            %   inverse really sees. The poles are excluded deliberately: they
            %   are an edge case with their own precision test, and they are not
            %   what a million-point workload looks like.
            %
            %   One authority, two callers - TestCoordinates for
            %   cartesianToGeodetic and TestDispatch for convertCoordinates -
            %   so that the two benchmarks are comparable by construction. Two
            %   copies would be free to drift into measuring different work
            %   while both stayed green, which is the S5 seam item 6 lesson.
            arguments
                pointCount (1,1) double {mustBePositive, mustBeInteger}
            end

            latitude = linspace(-1.4, 1.4, pointCount)';
            longitude = mod(linspace(0, 200 * pi, pointCount)', 2 * pi) - pi;
            radius = 6378137 + 8000 * sin(5 * latitude);
            point = [radius .* cos(latitude) .* cos(longitude), ...
                radius .* cos(latitude) .* sin(longitude), ...
                radius .* sin(latitude)];
        end

        function pattern = recordPattern(keyword, nField)
            %RECORDPATTERN The regular expression referenceSystem.runTestSuite uses.
            %   join is essential: keyword + repmat(...) concatenates element by
            %   element and yields nField separate patterns rather than one, which
            %   is the defect the first test report caught here.
            arguments
                keyword (1,1) string
                nField (1,1) double {mustBePositive, mustBeInteger}
            end

            pattern = keyword + join(repmat("\|([^|\n\r]*)", 1, nField), "");
        end

        function [medianSeconds, fastestSeconds] = medianDuration(operation, ...
                repetitionCount)
            %MEDIANDURATION Median and fastest wall-clock duration of a repeated
            %   operation.
            %
            %   THE SECOND OUTPUT EXISTS BECAUSE THE MEDIAN CANNOT TELL A
            %   REGRESSION FROM A LOAD SPIKE (rev. 1.86). Runs 17 and 18 each
            %   carried exactly one benchmark row about seven times its usual
            %   value while every other row stayed inside 0.7x to 1.5x - and it
            %   was a DIFFERENT row each time, so nothing in the toolbox had
            %   changed. Both victims were the two tests built as a tight loop
            %   of many small MATLAB calls. A median over repetitions that all
            %   run inside one short window defends against nothing, because a
            %   spike lasting a second covers every sample.
            %
            %   Contamination by external load is ONE-SIDED: it can only make a
            %   measurement slower. The minimum is therefore the better
            %   estimator of the true cost, and the two together separate the
            %   cases - a slow median with a normal minimum is the machine, a
            %   slow minimum is the code.
            %   Section D.1 requires at least three repetitions and the median
            %   rather than the mean, because a single run on a shared machine
            %   is dominated by whatever else that machine was doing. The
            %   operation is run once first and that run is discarded, so that
            %   just-in-time compilation and first-call MEX loading are not
            %   charged to the measurement.
            arguments
                operation (1,1) function_handle
                repetitionCount (1,1) double {mustBeGreaterThanOrEqual(repetitionCount, 3)}
            end

            operation();
            duration = zeros(repetitionCount, 1);
            for k = 1:repetitionCount
                startTime = tic;
                operation();
                duration(k) = toc(startTime);
            end
            medianSeconds = median(duration);
            fastestSeconds = min(duration);
        end

        function record = benchmarkRecord(functionName, nEpoch, medianSeconds, ...
                targetSeconds, fastestSeconds)
            %BENCHMARKRECORD Format one BENCHMARKS row for the section D.3 report.
            %
            %   functionName    1x1 string   label shown in the report
            %   nEpoch          1x1 double   problem size the median refers to
            %   medianSeconds   1x1 double   measured median over the repetitions
            %   targetSeconds   1x1 double   section B.7 target for that size
            %   record          1x1 string   the formatted log record
            arguments
                functionName (1,1) string
                nEpoch (1,1) double {mustBeNonnegative}
                medianSeconds (1,1) double {mustBeNonnegative, mustBeFinite}
                targetSeconds (1,1) double {mustBePositive, mustBeFinite}
                % NO VALIDATOR, AND THAT IS THE POINT (rev. 1.88). MATLAB
                % validates the DEFAULT value of an arguments block, not only
                % what a caller passes, so {mustBeNonnegative} on a NaN default
                % made every call site that omitted this argument throw -
                % nine speed tests in run 20, all with the same message, none
                % of them about speed. A validator that rejects its own default
                % is a contradiction the language is right to refuse.
                fastestSeconds (1,1) double = NaN
            end

            % The fifth field is optional and defaults to NaN, so the six call
            % sites that do not yet pass it are unchanged and the report prints
            % a dash for them. Only the two rows that external load has actually
            % hit need it; adding it elsewhere is one argument per call site.
            record = string(sprintf('BENCHMARK|%s|%d|%.9g|%.9g|%.9g', ...
                functionName, round(nEpoch), medianSeconds, targetSeconds, ...
                fastestSeconds));
        end

        function record = noteRecord(subject, detail, reason)
            %NOTERECORD Format one NOTES row for the report.
            %
            %   THE SECTION THAT SHOULD HAVE EXISTED BEFORE ANYTHING WAS
            %   LOGGED INTO IT. Twice - the Ceres skip at rev. 1.163 and the
            %   comment-area diagnostic at rev. 1.165 - a test logged a
            %   hand-written "SKIPPED|..." string and the handover recorded
            %   the gap as closed. The runner parses BENCHMARK and CONVERGENCE
            %   records and nothing else, so BOTH records went nowhere, in
            %   revisions that cited obligation O17 as their justification.
            %   Run 69's report is the evidence: neither string appears in it.
            %
            %   A record type without a section is a diagnostic that reaches
            %   nobody. This is that section's format, owned here as the other
            %   two are, so a third call site cannot invent a fourth spelling.
            %
            %   subject   1x1 string   what the note is about, e.g. a function
            %   detail    1x1 string   the fact being reported
            %   reason    1x1 string   why it is worth a line in the report
            %   record    1x1 string   the formatted log record
            arguments
                subject (1,1) string
                detail (1,1) string
                reason (1,1) string
            end

            % THE SEPARATOR AND EVERY CONTROL CHARACTER ARE STRIPPED, NOT
            % TRUSTED ABSENT. These fields carry text read from files - a
            % kernel comment area, a body name - so a stray pipe would split
            % one field into two and shift every column after it, and a stray
            % control character is worse: run 70's report carried ONE NUL out
            % of a kernel's fixed-width padding and the whole file stopped
            % being a text file. Rev. 1.167 stripped only pipe and newline,
            % which is the half of the problem I had thought of.
            clean = @(text) strtrim(regexprep(text, '[|\x00-\x1F\x7F]+', " "));
            record = string(sprintf('NOTE|%s|%s|%s', clean(subject), ...
                clean(detail), clean(reason)));
        end

        function record = convergenceRecord(quantity, stepSeconds, relativeError, ...
                order, status)
            %CONVERGENCERECORD Format one CONVERGENCE row for the report (D28).
            %
            %   quantity        1x1 string   differentiated quantity, e.g. "Qdot"
            %   stepSeconds     1x1 double   finite-difference step h
            %   relativeError   1x1 double   relative error at that step
            %   order           1x1 double   observed order, NaN if undetermined
            %   status          1x1 string   verdict, e.g. "OK" or "--"
            %   record          1x1 string   the formatted log record
            arguments
                quantity (1,1) string
                stepSeconds (1,1) double {mustBePositive, mustBeFinite}
                relativeError (1,1) double {mustBeNonnegative}
                order (1,1) double
                status (1,1) string
            end

            if isnan(order)
                orderText = "--";
            else
                orderText = sprintf('%.2f', order);
            end
            record = string(sprintf('CONVERGENCE|%s|%.9g|%.2e|%s|%s', quantity, ...
                stepSeconds, relativeError, orderText, status));
        end

        function record = verifiedConvergence(testCase, quantity, stepSeconds, ...
                achieved, bound, order, status)
            %VERIFIEDCONVERGENCE Verify an achieved figure AND return its report row.
            %
            %   OPEN ITEM D1's MECHANISM. A passing verifyLessThan leaves no
            %   trace of the number it checked, and the report is therefore
            %   silent about exactly the measurements that went well. That was
            %   repaired by hand three times - the P19 arc ratio, the
            %   interpolant row, the P20 achieved figures - each time by
            %   remembering to add a log call beside an assertion. The fourth
            %   instance would have been found the same way.
            %
            %   The repair is to make the two inseparable: this function
            %   qualifies the bound and RETURNS the record, so a caller cannot
            %   have the assertion without also having something to log. It
            %   deliberately does not log for the caller, because
            %   matlab.unittest.TestCase.log is reached from inside the test
            %   class and a static method of this class is not inside it.
            %
            %   testCase        1x1 TestCase the calling test, for qualification
            %   quantity        1x1 string   label shown in the report
            %   stepSeconds     1x1 double   perturbation or step the figure is at
            %   achieved        1x1 double   measured relative disagreement
            %   bound           1x1 double   the bound being asserted
            %   order           1x1 double   observed order, NaN if undetermined
            %   status          1x1 string   verdict, e.g. "roundoff-limited"
            %   record          1x1 string   the formatted log record
            arguments
                testCase (1,1) matlab.unittest.TestCase
                quantity (1,1) string
                stepSeconds (1,1) double {mustBePositive, mustBeFinite}
                achieved (1,1) double {mustBeNonnegative}
                bound (1,1) double {mustBePositive, mustBeFinite}
                order (1,1) double = NaN
                status (1,1) string = "asserted"
            end

            record = TestPerformance.convergenceRecord(quantity, stepSeconds, ...
                achieved, order, status);
            % THE DIAGNOSTIC CARRIES THE RECORD ITSELF, so a failure reports
            % the same row the report would have carried and the two cannot
            % describe the run differently.
            testCase.verifyLessThan(achieved, bound, ...
                "Convergence bound missed: " + record);
        end

        function record = verifiedBenchmark(testCase, functionName, nEpoch, ...
                measuredSeconds, targetSeconds, fastestSeconds)
            %VERIFIEDBENCHMARK Verify a timing against its target AND return its row.
            %   The speed-test counterpart of verifiedConvergence, with the
            %   section B.7 rule built in rather than restated at each call
            %   site: slower than the target WARNS through the diagnostic, and
            %   only beyond five times the target does it fail, because the
            %   target is machine dependent while a fivefold miss is a defect.
            %
            %   THE ASSERTION IS ON THE FASTEST REPETITION AND THE REPORT
            %   CARRIES THE MEDIAN. External load can only add time, so the
            %   fastest repetition estimates the code and the median reports
            %   the machine (rev. 1.86).
            %
            %   testCase         1x1 TestCase the calling test, for qualification
            %   functionName     1x1 string   label shown in the report
            %   nEpoch           1x1 double   problem size the timing refers to
            %   measuredSeconds  1x1 double   median over the repetitions
            %   targetSeconds    1x1 double   section B.7 target for that size
            %   fastestSeconds   1x1 double   fastest repetition, NaN if not kept
            %   record           1x1 string   the formatted log record
            arguments
                testCase (1,1) matlab.unittest.TestCase
                functionName (1,1) string
                nEpoch (1,1) double {mustBeNonnegative}
                measuredSeconds (1,1) double {mustBeNonnegative, mustBeFinite}
                targetSeconds (1,1) double {mustBePositive, mustBeFinite}
                fastestSeconds (1,1) double = NaN
            end

            record = TestPerformance.benchmarkRecord(functionName, nEpoch, ...
                measuredSeconds, targetSeconds, fastestSeconds);
            judged = measuredSeconds;
            if ~isnan(fastestSeconds)
                judged = fastestSeconds;
            end
            testCase.verifyLessThan(judged, 5*targetSeconds, ...
                "Benchmark beyond five times its target: " + record);
        end

    end

end
