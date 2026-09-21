function [reportFile, reportLine] = profileRotationCall(options)
%PROFILEROTATIONCALL Measure the single-epoch hot path and compare it to a baseline.
%
%   reportFile = profileRotationCall()
%   reportFile = profileRotationCall('Baseline', previousReport)
%   reportFile = profileRotationCall('Output', file, 'Baseline', file)
%
%   Profiles one single-epoch referenceSystem.rotationItrsToGcrs call, times the
%   functions prompt P28b is allowed to change and the functions it is not, and
%   writes both as machine-readable rows into a plain text report. Given a
%   previous report through 'Baseline' it re-reads those rows and prints the
%   before/after ratio for every key that appears in both.
%
%   THIS IS AN INSTRUMENT, NOT A TOOLBOX FUNCTION. It lives in test/ rather than
%   in +referenceSystem/ because it prints, because it is run by hand, and
%   because nothing in the shipped API may depend on it. It is therefore outside
%   Contents.m, outside the generated function reference and outside the
%   auditPackage.py and provenance scans, all of which exist to protect the
%   published interface. It adds no test method and does not change the suite
%   count.
%
%   WHY IT CARRIES ITS OWN BASELINE. Revision 1.84 (iii) records a performance
%   regression that shipped because the benchmark reported an absolute number
%   with nothing to compare it against, and revision 1.82 (i) records a
%   measurement that could not be read because the host and the code changed in
%   the same step. Both failures are structural, so the answer is structural:
%   the report this function writes is exactly the file it later reads as a
%   baseline, and the environment block is compared before any ratio is
%   believed.
%
% INPUT ARGUMENTS
%   (none)
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name           Size  Type     Default                    Description
%   ----           ----  ----     -------                    -----------
%   Output         1x1   string   "profileRotationCall.txt"  Report to write. A
%                                                            bare name resolves
%                                                            against pwd.
%   Baseline       1x1   string   ""                         Earlier report of
%                                                            this same format to
%                                                            compare against.
%                                                            Empty means none.
%   ProfileRepeat  1x1   double   20                         Rotation calls made
%                                                            inside the profiled
%                                                            region.
%   BenchRepeat    1x1   double   2000                       Calls per trial for
%                                                            the cheap rows.
%   TrialCount     1x1   double   7                          Trials per cheap
%                                                            row; the median
%                                                            reports the machine
%                                                            and the fastest
%                                                            estimates the code.
%   ArcLength      1x1   double   5000                       Epochs in the
%                                                            vectorised control
%                                                            row.
%
% OUTPUT ARGUMENTS
%   Name        Size  Type    Units  Description
%   ----        ----  ----    -----  -----------
%   reportFile  1x1   string  -      Absolute path of the report written.
%
% METHOD
%   THREE BLOCKS, AND THEY ANSWER DIFFERENT QUESTIONS.
%
%   (1) PROFILE. referenceSystem.rotationItrsToGcrs is called ProfileRepeat
%   times under the MATLAB profiler with the same epoch, the same EOP fixture
%   and the same options as the TestRotation speed row, so the headline number
%   is comparable to the benchmark the handover quotes. For each watched
%   function the report carries CALLS PER ROTATION and PER CENT OF THE PROFILED
%   CALL as well as absolute seconds. The first two do not depend on the host
%   and the third does, which is the distinction revision 1.83 (i) relies on
%   when a comparison has to survive a platform change.
%
%   A watched function that is not reached is printed as an explicit
%   "not reached" row rather than omitted. Dropping out of the profile is the
%   signal P28b is looking for, and a missing line cannot be distinguished from
%   a renamed one.
%
%   (2) BENCHMARK. Every row is timed by the same local harness, with the
%   function handle and its arguments passed in and never captured in a closure.
%   Revision 1.82 (iii) records two rows that were compared after only one of
%   them had paid for an anonymous wrapper, so uniform entry is a correctness
%   property of this function and not a matter of taste.
%
%   Rows are labelled candidate or control. CANDIDATES are the functions P28b
%   may change: normalizeEpoch, timeScale, iersConstants, leapSecondTable and
%   convertTimeScale. CONTROLS are functions it may not: ellipsoidParameters and
%   attitudeConvention have the same shape as timeScale - an arguments block, a
%   string dispatch and a struct assembly - and are untouched, so they separate
%   "this function got faster" from "this host is faster". rotationZ,
%   cartesianToGeodetic and the vectorised arc complete the band.
%
%   (3) COMPARISON. With a baseline, each key present in both reports is printed
%   with its ratio, old over new, so a number above one is an improvement. If
%   computer() or version() differ the whole table is marked UNSAFE and printed
%   anyway, with the control rows first: a cross-host comparison is not
%   worthless, but it may only be read through its control band, which is how
%   revision 1.84 recovered a usable answer after the host was lost.
%
%   WARM-UP IS NOT OPTIONAL. The first leapSecondTable call sweeps eighty
%   thousand days through the MEX gateway to discover the SOFA table, and every
%   function is JIT-compiled on first entry. All rows are therefore exercised
%   once before anything is timed, or the first measurement of the session
%   reports the session start-up instead of the code.
%
% ACCURACY
%   Timing only; nothing here is used by the toolbox and no result of it enters
%   a computation. Absolute times depend on the host, the MATLAB release, the
%   thread count and the load on the machine, and are meaningful only against a
%   baseline recorded with the same environment block. Call counts and per-cent
%   shares are exact and host-independent. The profiler inflates every absolute
%   time it reports, so profile seconds and benchmark seconds must not be
%   compared with each other; only like with like across two reports.
%
% ERRORS
%   referenceSystem:profileRotationCall:packageNotResolvable
%   referenceSystem:profileRotationCall:gatewayMissing
%   referenceSystem:profileRotationCall:fixtureMissing
%   referenceSystem:profileRotationCall:unreadableBaseline
%   referenceSystem:profileRotationCall:unparseableBaseline   The baseline file
%       exists and can be read but holds no ENV, BENCH or PROFILE rows. Refused
%       rather than compared, because the alternative is a report of empty
%       tables that looks like a comparison and is not one.
%   referenceSystem:profileRotationCall:cannotWriteReport
%
%   Warnings raised, both of which report on the instrument itself rather than
%   on the toolbox, and neither of which stops the measurement:
%   referenceSystem:profileRotationCall:profilerUnavailable
%   referenceSystem:profileRotationCall:reportDoesNotRoundTrip
%
% REFERENCES
%   Handover revisions 1.81, 1.82, 1.83, 1.84 and 1.113; obligation O21.
%   Handover Part H, the P28b entry of the status board and section B.7.
%
% EXAMPLE
%   before = profileRotationCall('Output', "profileBeforeP28b.txt");
%   % ... apply P28b, then:
%   after = profileRotationCall('Output', "profileAfterP28b.txt", ...
%       'Baseline', before);
%
% KEYWORDS
%   profile, benchmark, baseline, hot path, P28b, regression, call count
%
% See also RUNTESTSUITE, TESTPERFORMANCE, MEXINFO, TOOLBOXVERSION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 02:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.Output (1,1) string = "profileRotationCall.txt"
        options.Baseline (1,1) string = ""
        options.ProfileRepeat (1,1) double {mustBeInteger, mustBePositive} = 20
        options.BenchRepeat (1,1) double {mustBeInteger, mustBePositive} = 2000
        options.TrialCount (1,1) double {mustBeInteger, mustBePositive} = 7
        options.ArcLength (1,1) double {mustBeInteger, mustBePositive} = 5000
    end

    localRequireResolvablePackage();
    fixtureFile = localFixtureFile("eop20c04.txt");

    mexState = referenceSystem.mexInfo();
    if ~mexState.built
        error('referenceSystem:profileRotationCall:gatewayMissing', ...
            ['The MEX gateway is not built, so the hot path cannot be ', ...
            'measured. Run referenceSystem.buildMex once.']);
    end

    fprintf('Building inputs from %s ...\n', fixtureFile);
    eop = referenceSystem.readEop(fixtureFile);
    singleEpoch = referenceSystem.daySecondToEpoch([57754 0], "UTC");
    arcEpoch = referenceSystem.daySecondToEpoch( ...
        [repmat(57754, options.ArcLength, 1), (0:options.ArcLength-1)'*10], "UTC");

    row = localBenchmarkRows(eop, singleEpoch, arcEpoch, options);

    fprintf('Warming up %d rows ...\n', numel(row));
    localWarmUp(row);

    fprintf('Profiling %d rotation calls ...\n', options.ProfileRepeat);
    profileRow = localProfileBlock(singleEpoch, eop, options.ProfileRepeat);

    fprintf('Timing %d benchmark rows ...\n', numel(row));
    benchRow = localBenchmarkBlock(row);

    environment = localEnvironment(mexState, fixtureFile, options);

    baseline = struct('present', false, 'file', "", 'environment', struct(), ...
        'bench', struct('key', strings(0,1), 'median', [], 'fastest', []), ...
        'profile', struct('key', strings(0,1), 'calls', [], 'share', []));
    if strlength(options.Baseline) > 0
        baseline = localReadBaseline(options.Baseline);
    end

    reportFile = localAbsolutePath(options.Output);
    % The composed text is returned as well as written, so runTestSuite can
    % splice this block into the single report a caller is asked to upload
    % (rev. 1.198). The file is still written and still read back, because
    % localVerifyRoundTrip is the check that the format survived.
    reportLine = localWriteReport(reportFile, environment, profileRow, ...
        benchRow, baseline);
    localVerifyRoundTrip(reportFile, profileRow, benchRow);

    fprintf('Report written to %s\n', reportFile);
end

% =========================== local functions ===========================

function localRequireResolvablePackage()
%LOCALREQUIRERESOLVABLEPACKAGE Stop before producing a meaningless report.
%   The same guard runTestSuite carries and for the same reason: a profile of a
%   namespace that does not resolve is evidence about the MATLAB path, not about
%   the toolbox. The bias is toward running, so only a positive determination
%   that the name cannot be resolved stops the measurement.
    try
        referenceSystem.toolboxVersion();
        return
    catch cause
        if ~any(strcmp(cause.identifier, ...
                {'MATLAB:undefinedVarOrClass', 'MATLAB:UndefinedFunction'}))
            return
        end
    end

    error('referenceSystem:profileRotationCall:packageNotResolvable', ...
        ['The +referenceSystem namespace cannot be resolved. Add the folder ', ...
        'that CONTAINS +referenceSystem to the path, or run ', ...
        'setupReferenceSystem, and try again.']);
end

function fixtureFile = localFixtureFile(name)
%LOCALFIXTUREFILE Resolve a test fixture against this file, not against pwd.
    testFolder = fileparts(mfilename('fullpath'));
    fixtureFile = string(fullfile(testFolder, 'fixtures', name));
    if ~isfile(fixtureFile)
        error('referenceSystem:profileRotationCall:fixtureMissing', ...
            ['The EOP fixture "%s" is missing. The profile must use the ', ...
            'same series as the TestRotation speed row or its headline ', ...
            'number is not comparable to the benchmark.'], fixtureFile);
    end
end

function row = localBenchmarkRows(eop, singleEpoch, arcEpoch, options)
%LOCALBENCHMARKROWS The rows to time, their arguments and their role.
%   The role field is what makes a cross-host comparison readable later: a
%   candidate row that moves while every control row stands still is a real
%   change, and a candidate row that moves with them is the host.
    utcEpoch = referenceSystem.daySecondToEpoch([57754 43200], "UTC");
    ttEpoch = referenceSystem.daySecondToEpoch([57754 43200], "TT");
    % cartesianToGeodetic takes ONE POINT PER ROW, so this is 1x3 and not 3x1.
    cartesian = [4027893.0, 307045.0, 4919475.0];

    row = struct('key', {}, 'role', {}, 'fcn', {}, 'args', {}, ...
        'callCount', {}, 'trialCount', {});

    row = localAddRow(row, "rotationItrsToGcrs (N=1,call)", "headline", ...
        @referenceSystem.rotationItrsToGcrs, {singleEpoch, 'Eop', eop}, 1, 20);
    row = localAddRow(row, "rotationItrsToGcrs (N=" + options.ArcLength + ",R+Rdot)", ...
        "control", @localRotationTwoOutputs, {arcEpoch, eop}, 1, 5);

    row = localAddRow(row, "normalizeEpoch(TT)", "candidate", ...
        @referenceSystem.normalizeEpoch, {ttEpoch}, options.BenchRepeat, ...
        options.TrialCount);
    row = localAddRow(row, "normalizeEpoch(UTC)", "candidate", ...
        @referenceSystem.normalizeEpoch, {utcEpoch}, options.BenchRepeat, ...
        options.TrialCount);
    row = localAddRow(row, "timeScale(TT)", "candidate", ...
        @referenceSystem.timeScale, {"TT"}, options.BenchRepeat, options.TrialCount);
    row = localAddRow(row, "iersConstants()", "candidate", ...
        @referenceSystem.iersConstants, {}, options.BenchRepeat, options.TrialCount);
    row = localAddRow(row, "leapSecondTable(deltaAT)", "candidate", ...
        @referenceSystem.leapSecondTable, {"deltaAT", utcEpoch}, ...
        options.BenchRepeat, options.TrialCount);
    row = localAddRow(row, "leapSecondTable(list)", "candidate", ...
        @referenceSystem.leapSecondTable, {"list"}, options.BenchRepeat, ...
        options.TrialCount);
    row = localAddRow(row, "convertTimeScale(UTC->TT)", "candidate", ...
        @referenceSystem.convertTimeScale, {utcEpoch, "TT"}, ...
        options.BenchRepeat, options.TrialCount);
    % ALL THREE CONVERSIONS THE ROTATION PERFORMS, NOT ONLY THE CHEAPEST.
    % Run 43's headline gain exceeded what three times the UTC->TT row predicts,
    % and the leading explanation is that UTC->TT is the cheapest of the three:
    % UT1 routes UTC -> TAI -> UTC -> UT1 and therefore carries more shifts. That
    % was a hypothesis with nothing to test it against, which is the situation
    % this instrument exists to prevent, so the other two are measured now.
    % 'DeltaUt1', 0 is EXPLICIT since rev. 1.184 (D113): an omitted value on a
    % UT1 conversion now warns once per call, and a warning inside a timed
    % repetition loop measures the warning machinery, not the conversion.
    % Zero keeps the measured work identical to every earlier run of this row.
    row = localAddRow(row, "convertTimeScale(UTC->UT1)", "candidate", ...
        @referenceSystem.convertTimeScale, {utcEpoch, "UT1", 'DeltaUt1', 0}, ...
        options.BenchRepeat, options.TrialCount);
    row = localAddRow(row, "convertTimeScale(UTC->TAI)", "candidate", ...
        @referenceSystem.convertTimeScale, {utcEpoch, "TAI"}, ...
        options.BenchRepeat, options.TrialCount);
    row = localAddRow(row, "daySecondToEpoch(TT)", "candidate", ...
        @referenceSystem.daySecondToEpoch, {[57754 43200], "TT"}, ...
        options.BenchRepeat, options.TrialCount);

    % CONTROLS. ellipsoidParameters and attitudeConvention have the same shape
    % as timeScale - arguments block, string dispatch, struct assembly - and
    % P28b may not touch them, so they say what that shape costs on this host.
    row = localAddRow(row, "ellipsoidParameters(WGS84)", "control", ...
        @referenceSystem.ellipsoidParameters, {"WGS84"}, options.BenchRepeat, ...
        options.TrialCount);
    row = localAddRow(row, "attitudeConvention()", "control", ...
        @referenceSystem.attitudeConvention, {}, options.BenchRepeat, ...
        options.TrialCount);
    row = localAddRow(row, "rotationZ(scalar)", "control", ...
        @referenceSystem.rotationZ, {0.5}, options.BenchRepeat, options.TrialCount);
    row = localAddRow(row, "cartesianToGeodetic(N=1)", "control", ...
        @referenceSystem.cartesianToGeodetic, {cartesian}, options.BenchRepeat, ...
        options.TrialCount);
end

function row = localAddRow(row, key, role, fcn, args, callCount, trialCount)
%LOCALADDROW Append one benchmark row.
    row(end+1) = struct('key', key, 'role', role, 'fcn', fcn, 'args', {args}, ...
        'callCount', callCount, 'trialCount', trialCount);
end

function localRotationTwoOutputs(epoch, eop)
%LOCALROTATIONTWOOUTPUTS The arc row, with the derivative actually requested.
%   nargout reaches the arithmetic in rotationItrsToGcrs, so an arc timed with
%   one output would not measure the derivative path at all.
    [~, ~] = referenceSystem.rotationItrsToGcrs(epoch, 'Eop', eop, ...
        'DifferenceStep', 200);
end

function localWarmUp(row)
%LOCALWARMUP Exercise every row once so no measurement pays for session start-up.
%   The first leapSecondTable call sweeps the whole SOFA table through the MEX
%   gateway; the first call of anything is JIT-compiled. Neither belongs in a
%   number that is going to be compared against another machine.
    for k = 1:numel(row)
        row(k).fcn(row(k).args{:});
    end
end

function profileRow = localProfileBlock(epoch, eop, repeatCount)
%LOCALPROFILEBLOCK Call counts, self time and share of the profiled call.
%   Shares are taken against the TotalTime of the rotation entry itself, which
%   is what "per cent of a profiled call" means in handover revision 1.84 (v).
%   The profiler inflates all of these uniformly, so they may be compared with
%   each other and with another profile, but never with the benchmark block.

    profileRow = struct('name', strings(0,1), 'calls', [], 'selfSeconds', [], ...
        'totalSeconds', [], 'sharePercent', [], 'watched', logical([]));

    try
        profile('off');
        profile('clear');
        profile('on');
    catch cause
        warning('referenceSystem:profileRotationCall:profilerUnavailable', ...
            ['The MATLAB profiler could not be started (%s), so the report ', ...
            'carries benchmark rows only.'], cause.message);
        return
    end
    restoreProfiler = onCleanup(@() localStopProfiler());

    for k = 1:repeatCount
        referenceSystem.rotationItrsToGcrs(epoch, 'Eop', eop);
    end
    profile('off');
    profileData = profile('info');

    functionTable = profileData.FunctionTable;
    if isempty(functionTable)
        return
    end

    name = string({functionTable.FunctionName})';
    totalTime = [functionTable.TotalTime]';
    numCalls = [functionTable.NumCalls]';
    selfTime = totalTime;
    for k = 1:numel(functionTable)
        child = functionTable(k).Children;
        if ~isempty(child)
            selfTime(k) = selfTime(k) - sum([child.TotalTime]);
        end
    end

    rotationIndex = find(name == "rotationItrsToGcrs" | ...
        name == "referenceSystem.rotationItrsToGcrs", 1);
    if isempty(rotationIndex)
        callTotal = max(totalTime);
    else
        callTotal = totalTime(rotationIndex);
    end
    if ~(callTotal > 0)
        callTotal = NaN;
    end

    watchList = localWatchList();
    reportedIndex = localReportedIndex(name, totalTime, watchList);

    for k = reportedIndex'
        profileRow.name(end+1, 1) = name(k);
        profileRow.calls(end+1, 1) = numCalls(k)/repeatCount;
        profileRow.selfSeconds(end+1, 1) = selfTime(k)/repeatCount;
        profileRow.totalSeconds(end+1, 1) = totalTime(k)/repeatCount;
        profileRow.sharePercent(end+1, 1) = 100*selfTime(k)/callTotal;
        profileRow.watched(end+1, 1) = localMatchesWatch(name(k), watchList);
    end

    % A watched function that was never entered is reported as an explicit
    % zero-call row. Omitting it would make "dropped out of the profile" -
    % which is the outcome P28b is trying to produce - indistinguishable from
    % "renamed" or "misspelled in the watch list".
    for k = 1:numel(watchList)
        if any(arrayfun(@(n) localMatchesWatch(n, watchList(k)), profileRow.name))
            continue
        end
        % NaN AND NOT ZERO. A zero reads as a measurement - "this function cost
        % nothing" - and the first run printed fourteen of them for functions
        % that had in fact been called seventeen and twenty times, because the
        % watch list held the wrong spelling. NaN cannot be misread as a result,
        % and the printed row says "not reached" in words.
        profileRow.name(end+1, 1) = watchList(k);
        profileRow.calls(end+1, 1) = NaN;
        profileRow.selfSeconds(end+1, 1) = NaN;
        profileRow.totalSeconds(end+1, 1) = NaN;
        profileRow.sharePercent(end+1, 1) = NaN;
        profileRow.watched(end+1, 1) = true;
    end
end

function localStopProfiler()
%LOCALSTOPPROFILER Leave no profiler state behind, whatever happened.
    profile('off');
    profile('clear');
end

function watchList = localWatchList()
%LOCALWATCHLIST The functions whose call count and share P28b is judged on.
%   THESE ARE THE NAMES THE PROFILER ACTUALLY REPORTS, AND THE FIRST RUN PROVED
%   THEY ARE NOT WHAT THIS LIST FIRST HELD. R2026a lists a namespace function by
%   its BARE name - normalizeEpoch, not referenceSystem.normalizeEpoch - so a
%   watch list written with the qualified names matched nothing at all. Every
%   watched row printed as an unreached zero while the real rows sat unmarked in
%   the top-cost listing, and the CALLS PER ROTATION comparison, which is the
%   one number no host change can spoil, would have compared zero against zero
%   and reported no change from any P28b whatsoever.
%
%   The instrument did not lose the data, because the top-cost listing catches
%   everything expensive and the machine-readable rows carry it - which is why
%   the run 40 report is still a usable baseline. But an instrument that reports
%   a clean nothing is the failure mode this project has recorded three times.
%   localMatchesWatch therefore accepts BOTH spellings rather than the one this
%   release happens to use.
%
%   THREE WATCHED ROWS READ "not reached" AND THAT IS CORRECT, NOT A DEFECT.
%   cipCoordinates, earthRotationAngle and fundamentalArguments are absent from
%   a direct-path profile because rsCoreDcm calls iauXys06a and iauEra00 inside
%   C; the CIP and the Earth rotation angle never cross the gateway boundary
%   into MATLAB. They stay on the list because on the interpolated path they
%   WILL appear, and a row that changes from "not reached" to a count is the
%   signal. The gateway itself is listed under the name the profiler prints for
%   it - the path-qualified +referenceSystem/private/mexGateway - which run 41
%   established and which closes the question rev. 1.122 (vii) left open.
%
%   Local functions are watched by their full parent>local name and are NOT
%   folded into their parent: convertTimeScale>localShift at 4 calls is the
%   single most direct evidence for candidate C1, and it is invisible in the
%   parent's count.
    watchList = [ ...
        "rotationItrsToGcrs"
        "normalizeEpoch"
        "timeScale"
        "iersConstants"
        "leapSecondTable"
        "leapSecondTable>localDeltaAt"
        "leapSecondTable>localMjdOfDatetime"
        "convertTimeScale"
        "convertTimeScale>localShift"
        "convertTimeScale>localToTai"
        "convertTimeScale>localFromTai"
        "convertTimeScale>localUtcToTai"
        "convertTimeScale>localTaiToUtc"
        "interpolateEop"
        "cipCoordinates"
        "earthRotationAngle"
        "subdailyEopCorrection"
        "fundamentalArguments"
        "daySecondToEpoch"
        "+referenceSystem/private/mexGateway"
        "+referenceSystem/private/carryEpoch"
        "+referenceSystem/private/carryEpoch>localCarryUtc"
        "datetime.datetime>datetime.datetime"
        "datetime.minus"
        "discretize"
        "interp1"
        "ismember"
        "mustBeMember"
        "tabular.dotReference"
        "tabular.dotParenReference"];
end

function isWatched = localMatchesWatch(name, watchList)
%LOCALMATCHESWATCH Whether a profiled entry is on the watch list.
%   Accepts the bare name and the referenceSystem-qualified name for the same
%   function, so the report does not depend on which spelling the release uses.
%   A local function never matches its parent: convertTimeScale>localShift and
%   convertTimeScale are different rows and are meant to stay that way.
%
%   PATH SEPARATORS ARE NORMALISED, AND REV. 1.194 IS WHY. Three watch entries
%   are PATH-QUALIFIED - the gateway and the two carryEpoch rows - and the
%   profiler prints a path in the separator of its host: forward slash on
%   GLNXA64, BACKSLASH on PCWIN64. The comparison matched the two spellings as
%   plain strings, so on Windows all three failed to match, were recorded as
%   "not reached", and vanished from the profile. **The gateway itself, at two
%   calls per rotation, was silently absent from every Windows profile**, and
%   the cross-host comparison then reported the Linux run as ADDING seventeen
%   carryEpoch calls that had been there all along. That is the clean-nothing
%   failure this file's own help says the project has recorded three times,
%   recurring on the only rows whose name is shaped like a path. Both sides are
%   folded to forward slashes before comparison; nothing else about the name is
%   touched, because a local function must still not match its parent.
    isWatched = any(localFoldSeparators(name) == localFoldSeparators(watchList)) || ...
        any("referenceSystem." + localFoldSeparators(watchList) == ...
            localFoldSeparators(name));
end

function folded = localFoldSeparators(name)
%LOCALFOLDSEPARATORS Backslash to forward slash, so a name is host-independent.

    % Single quotes deliberately: a lone backslash is unambiguous in a char
    % array, and the separator to fold is the PRODUCING host's, not this
    % one's - a Windows baseline read on Linux still carries backslashes,
    % so filesep would be the wrong thing to ask.
    folded = replace(name, '\', '/');
end

function reportedIndex = localReportedIndex(name, totalTime, watchList)
%LOCALREPORTEDINDEX The 30 costliest entries, plus every watched entry.
%   The top listing is what finds a cost nobody predicted - which is how
%   revision 1.81 discovered that two thirds of the call was bookkeeping the
%   design document never mentioned.
    [~, order] = sort(totalTime, 'descend');
    topIndex = order(1:min(30, numel(order)));
    watchIndex = find(arrayfun(@(n) localMatchesWatch(n, watchList), name));
    reportedIndex = unique([topIndex(:); watchIndex(:)], 'stable');
end

function benchRow = localBenchmarkBlock(row)
%LOCALBENCHMARKBLOCK Time every row through one harness, identically.
    benchRow = struct('key', strings(numel(row), 1), ...
        'role', strings(numel(row), 1), 'callCount', zeros(numel(row), 1), ...
        'median', zeros(numel(row), 1), 'fastest', zeros(numel(row), 1));

    for k = 1:numel(row)
        [medianSeconds, fastestSeconds] = localRepeat(row(k).fcn, row(k).args, ...
            row(k).callCount, row(k).trialCount);
        benchRow.key(k) = row(k).key;
        benchRow.role(k) = row(k).role;
        benchRow.callCount(k) = row(k).callCount;
        benchRow.median(k) = medianSeconds;
        benchRow.fastest(k) = fastestSeconds;
    end
end

function [medianSeconds, fastestSeconds] = localRepeat(fcn, args, callCount, trialCount)
%LOCALREPEAT Seconds per call, as a median over trials and as the fastest trial.
%   THE HANDLE AND ITS ARGUMENTS ARE PASSED IN AND NEVER CAPTURED. Revision
%   1.82 (iii) compared two rows after only one of them had been called through
%   an anonymous wrapper, and the resulting factor of seventeen was partly the
%   closure. Every row here enters through this line and pays the same overhead,
%   so the rows are comparable with each other even though none of them is an
%   absolute cost.
%
%   The median reports the machine and the fastest estimates the code: external
%   load can only ADD time, which is the argument already recorded at revision
%   1.86 for the speed rows.
    trialTime = zeros(trialCount, 1);
    for trial = 1:trialCount
        start = tic;
        for k = 1:callCount
            fcn(args{:});
        end
        trialTime(trial) = toc(start);
    end
    medianSeconds = median(trialTime)/callCount;
    fastestSeconds = min(trialTime)/callCount;
end

function environment = localEnvironment(mexState, fixtureFile, options)
%LOCALENVIRONMENT Everything a later reader needs to decide whether to compare.
    versionInfo = referenceSystem.toolboxVersion();
    timestamp = datetime('now', 'TimeZone', 'local');
    timestamp.Format = 'yyyy-MM-dd HH:mm:ss';

    digest = "unavailable";
    try
        toolboxRoot = fileparts(fileparts(mfilename('fullpath')));
        digest = string(referenceSystem.mexSourceDigest(toolboxRoot));
    catch
        % A missing digest weakens the comparison but must not stop the
        % measurement; it is recorded as unavailable rather than invented.
    end

    environment = struct( ...
        'generated', string(timestamp), ...
        'computer', string(computer()), ...
        'release', string(version()), ...
        'threads', string(maxNumCompThreads()), ...
        'toolbox', versionInfo.version, ...
        'mexBuildDate', mexState.buildDate, ...
        'mexSourceDigest', digest, ...
        'fixture', string(fixtureFile), ...
        'profileRepeat', string(options.ProfileRepeat), ...
        'benchRepeat', string(options.BenchRepeat), ...
        'trialCount', string(options.TrialCount));
end

function baseline = localReadBaseline(baselineFile)
%LOCALREADBASELINE Parse the machine-readable rows out of an earlier report.
    if ~isfile(baselineFile)
        error('referenceSystem:profileRotationCall:unreadableBaseline', ...
            'Cannot read the baseline report "%s".', baselineFile);
    end
    text = string(fileread(baselineFile));

    % EVERY CHARACTER CLASS HERE EXCLUDES THE LINE BREAK EXPLICITLY, AND THAT
    % IS NOT DEFENSIVE PADDING. MATLAB's regexp defaults to 'dotall', so `.`
    % MATCHES A NEWLINE, and a negated class such as [^|] matches one too. Run
    % 41 is the evidence: '^ENV \| (\w+) \| (.*)$' with 'lineanchors' matched
    % ONCE, greedily swallowing the whole remainder of the file into the value
    % of the first field, so ten of the eleven ENV fields vanished, computer and
    % release read as "(absent)", and the report declared the host CHANGED and
    % the ratios UNSAFE - on the same machine, in the same session, twenty-five
    % minutes after the baseline. The same defect truncated nothing but the LAST
    % BENCH row, whose fastest value over-ran into the closing rule and parsed
    % as NaN. Both are one root cause and both are fixed the same way.
    envToken = regexp(text, '^ENV \| (\w+) \| ([^\r\n]*)$', 'tokens', ...
        'lineanchors');
    environment = struct();
    for k = 1:numel(envToken)
        environment.(char(envToken{k}(1))) = strtrim(envToken{k}(2));
    end

    % The numeric fields are captured as "anything but a bar or a line break"
    % rather than as a digit class, because a NaN share or a NaN time is a
    % legitimate row and a digit class would drop it silently on read-back.
    benchToken = regexp(text, ...
        ['^BENCH \| ([^|\r\n]+?) \| (\w+) \| (\d+) \| ([^|\r\n]+) \| ', ...
        '([^|\r\n]+)$'], 'tokens', 'lineanchors');
    bench = struct('key', strings(numel(benchToken), 1), ...
        'median', zeros(numel(benchToken), 1), ...
        'fastest', zeros(numel(benchToken), 1));
    for k = 1:numel(benchToken)
        bench.key(k) = benchToken{k}(1);
        bench.median(k) = str2double(strtrim(benchToken{k}(4)));
        bench.fastest(k) = str2double(strtrim(benchToken{k}(5)));
    end

    profileToken = regexp(text, ...
        ['^PROFILE \| ([^|\r\n]+?) \| ([^|\r\n]+) \| ([^|\r\n]+) \| ', ...
        '([^|\r\n]+) \| ([^|\r\n]+)$'], 'tokens', 'lineanchors');
    profileRows = struct('key', strings(numel(profileToken), 1), ...
        'calls', zeros(numel(profileToken), 1), ...
        'share', zeros(numel(profileToken), 1));
    for k = 1:numel(profileToken)
        profileRows.key(k) = profileToken{k}(1);
        profileRows.calls(k) = str2double(strtrim(profileToken{k}(2)));
        profileRows.share(k) = str2double(strtrim(profileToken{k}(5)));
    end

    % A BASELINE THAT PARSED TO NOTHING IS NOT A BASELINE, AND SAYING SO IS
    % THE WHOLE OF THIS CHECK (rev. 1.196). Given a Linux report on Windows,
    % this function returned empty collections and the report then printed
    % "(absent)" for the host, an EMPTY ratio table and an EMPTY call-count
    % table, under a heading announcing that ratios were unsafe: a page of
    % confident-looking nothing. Run 41 produced the SAME SYMPTOM from a
    % different cause and the comment above records that fix - but neither
    % time was a guard added, so the second cause found the same silence
    % waiting for it. The file exists and is readable, so the failure is in
    % the FORMAT, and the opening is quoted because a transferred report can
    % lose its machine-readable section, arrive re-wrapped, or turn out to be
    % a console transcript rather than the file.
    if isempty(fieldnames(environment)) && isempty(bench.key) && ...
            isempty(profileRows.key)
        opening = extractBefore(text + newline, min(400, strlength(text) + 1));
        error('referenceSystem:profileRotationCall:unparseableBaseline', ...
            ['"%s" is readable but contains no ENV, BENCH or PROFILE rows, ', ...
            'so it cannot serve as a baseline and no comparison is ', ...
            'possible. Those rows live in the MACHINE-READABLE section at ', ...
            'the end of a report written by this function; check that the ', ...
            'file is that report in full and was not truncated, re-wrapped ', ...
            'or pasted from a console. It begins:\n%s'], ...
            baselineFile, opening);
    end

    baseline = struct('present', true, 'file', string(baselineFile), ...
        'environment', environment, 'bench', bench, 'profile', profileRows);
end

function reportLine = localWriteReport(reportFile, environment, profileRow, benchRow, baseline)
%LOCALWRITEREPORT Compose the report and write it as UTF-8 with LF endings.
    reportLine = [localHeaderBlock(environment); ...
        localSectionRule(); ...
        localProfileText(profileRow, benchRow); ...
        localSectionRule(); ...
        localBenchText(benchRow); ...
        localSectionRule(); ...
        localComparisonText(environment, profileRow, benchRow, baseline); ...
        localSectionRule(); ...
        localMachineBlock(environment, profileRow, benchRow); ...
        localHeavyRule()];

    [fileId, message] = fopen(reportFile, 'w', 'n', 'UTF-8');
    if fileId < 0
        error('referenceSystem:profileRotationCall:cannotWriteReport', ...
            'Cannot open %s for writing: %s', reportFile, message);
    end
    closeFile = onCleanup(@() fclose(fileId));
    fprintf(fileId, '%s\n', reportLine);
end

function reportLine = localHeaderBlock(environment)
%LOCALHEADERBLOCK Identification, and the fields that gate a comparison.
    reportLine = [localHeavyRule(); ...
        "referenceSystem — HOT-PATH PROFILE (prompt P28b)"; ...
        localHeavyRule(); ...
        localPair("Generated", environment.generated); ...
        localPair("MATLAB", environment.release + "  on " + environment.computer); ...
        localPair("Threads", environment.threads); ...
        localPair("Toolbox", environment.toolbox); ...
        localPair("MEX built", environment.mexBuildDate); ...
        localPair("MEX digest", environment.mexSourceDigest); ...
        localPair("EOP fixture", environment.fixture); ...
        localPair("Repeats", "profile " + environment.profileRepeat + ...
            ", bench " + environment.benchRepeat + " x " + environment.trialCount); ...
        localHeavyRule()];
end

function line = localPair(label, value)
%LOCALPAIR One aligned "label : value" line.
    line = pad(string(label), 14) + ": " + string(value);
end

function reportLine = localProfileText(profileRow, benchRow)
%LOCALPROFILETEXT The profile table, watched rows marked with an asterisk.
%   THE TABLE STATES ITS OWN DISTORTION. The profiler adds a fixed cost to every
%   function ENTRY, so a function called twenty times per rotation is inflated
%   about twenty times as much as one called once, and the self-per-cent column
%   is therefore biased toward the call-count-heavy functions - which are
%   exactly the ones P28b is about. Run 40 measured the whole call at 4463 us
%   profiled against 691 us on the bench, a factor of 6.5, across roughly two
%   hundred function entries. A share read off this table is an upper bound on
%   a call-count-heavy function's true share, not an estimate of it, and the
%   BENCHMARK block is where cost is attributed.
    reportLine = "PROFILE OF ONE rotationItrsToGcrs CALL (N = 1)";
    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = localInflationLine(profileRow, benchRow);
    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = "  " + pad("function", 52) + pad("calls/call", 12) + ...
        pad("self [s]", 14) + pad("total [s]", 14) + "self %";
    reportLine(end+1, 1) = "  " + string(repmat('-', 1, 102));

    if isempty(profileRow.name)
        reportLine(end+1, 1) = "  (no profile data - the profiler did not run)";
        return
    end

    for k = 1:numel(profileRow.name)
        marker = "  ";
        if profileRow.watched(k)
            marker = "* ";
        end
        if isnan(profileRow.calls(k))
            reportLine(end+1, 1) = marker + pad(profileRow.name(k), 52) + ...
                "not reached in this profile"; %#ok<AGROW>
            continue
        end
        reportLine(end+1, 1) = marker + pad(profileRow.name(k), 52) + ...
            pad(sprintf('%.2f', profileRow.calls(k)), 12) + ...
            pad(sprintf('%.6f', profileRow.selfSeconds(k)), 14) + ...
            pad(sprintf('%.6f', profileRow.totalSeconds(k)), 14) + ...
            sprintf('%.2f', profileRow.sharePercent(k)); %#ok<AGROW>
    end
    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = "  * watched by P28b. calls/call and self % are " + ...
        "host-independent; the seconds are not,";
    reportLine(end+1, 1) = "    and they are inflated by the profiler. Never " + ...
        "compare them with the BENCHMARK block.";
end

function line = localInflationLine(profileRow, benchRow)
%LOCALINFLATIONLINE How much the profiler inflated the call it measured.
%   Printed rather than assumed, because it is the factor by which every second
%   in the table above is wrong and the reader has no other way to know it.
    profiled = localValueOf(profileRow.name, profileRow.totalSeconds, ...
        "rotationItrsToGcrs");
    measured = localValueOf(benchRow.key, benchRow.median, ...
        "rotationItrsToGcrs (N=1,call)");
    if isnan(profiled) || isnan(measured) || ~(measured > 0)
        line = "  Profiler inflation: not determined.";
        return
    end
    line = "  Profiler inflation: " + sprintf('%.2f', profiled/measured) + ...
        "x (" + sprintf('%.0f', 1e6*profiled) + " us profiled against " + ...
        sprintf('%.0f', 1e6*measured) + " us on the bench). Entry cost is per " + ...
        "CALL, so" + newline + "  a function called twenty times is inflated " + ...
        "twenty times as much as one called once.";
end

function value = localValueOf(keyList, valueList, wanted)
%LOCALVALUEOF One value looked up by key, or NaN if the key is absent.
    index = find(keyList == wanted, 1);
    if isempty(index)
        value = NaN;
    else
        value = valueList(index);
    end
end

function reportLine = localBenchText(benchRow)
%LOCALBENCHTEXT The benchmark table, candidates and controls kept apart.
    reportLine = "BENCHMARK, SECONDS PER CALL";
    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = "  " + pad("key", 40) + pad("role", 11) + ...
        pad("calls", 8) + pad("median [s]", 15) + "fastest [s]";
    reportLine(end+1, 1) = "  " + string(repmat('-', 1, 90));

    for k = 1:numel(benchRow.key)
        reportLine(end+1, 1) = "  " + pad(benchRow.key(k), 40) + ...
            pad(benchRow.role(k), 11) + pad(string(benchRow.callCount(k)), 8) + ...
            pad(sprintf('%.6e', benchRow.median(k)), 15) + ...
            sprintf('%.6e', benchRow.fastest(k)); %#ok<AGROW>
    end
end

function reportLine = localComparisonText(environment, profileRow, benchRow, baseline)
%LOCALCOMPARISONTEXT Before/after against a baseline, gated on the environment.
    reportLine = "COMPARISON AGAINST BASELINE";
    reportLine(end+1, 1) = "";

    if ~baseline.present
        reportLine(end+1, 1) = "  No baseline given. Pass an earlier report of " + ...
            "this format through 'Baseline'";
        reportLine(end+1, 1) = "  to obtain before/after ratios. A row without a " + ...
            "baseline cannot detect a change.";
        return
    end

    reportLine(end+1, 1) = "  Baseline: " + baseline.file;

    sameHost = localBaselineField(baseline, 'computer') == environment.computer;
    sameRelease = localBaselineField(baseline, 'release') == environment.release;
    if sameHost && sameRelease
        reportLine(end+1, 1) = "  Environment: SAME host and SAME release. " + ...
            "Ratios may be read directly.";
        unsafe = false;
    else
        reportLine(end+1, 1) = "  Environment: CHANGED — baseline ran on " + ...
            localBaselineField(baseline, 'computer') + " / " + ...
            localBaselineField(baseline, 'release') + ".";
        reportLine(end+1, 1) = "  RATIOS ARE UNSAFE. Read them only through the " + ...
            "control rows: a candidate that";
        reportLine(end+1, 1) = "  moves with the controls is the host, one that " + ...
            "moves against them is the code.";
        unsafe = true;
    end

    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = "  BENCHMARK, ratio = baseline / now. Above 1.00 is " + ...
        "faster than the baseline.";
    reportLine(end+1, 1) = "  " + pad("key", 40) + pad("role", 11) + ...
        pad("median x", 12) + "fastest x";
    reportLine(end+1, 1) = "  " + string(repmat('-', 1, 75));

    for role = ["control", "headline", "candidate"]
        for k = 1:numel(benchRow.key)
            if benchRow.role(k) ~= role
                continue
            end
            index = find(baseline.bench.key == benchRow.key(k), 1);
            if isempty(index)
                continue
            end
            reportLine(end+1, 1) = "  " + pad(benchRow.key(k), 40) + ...
                pad(benchRow.role(k), 11) + ...
                pad(sprintf('%.3f', baseline.bench.median(index)/benchRow.median(k)), 12) + ...
                sprintf('%.3f', baseline.bench.fastest(index)/benchRow.fastest(k)); %#ok<AGROW>
        end
    end

    if unsafe
        reportLine = [reportLine; localBandNote(benchRow, baseline)];
    end

    reportLine = [reportLine; localCallCountComparison(profileRow, baseline)];
end

function reportLine = localBandNote(benchRow, baseline)
%LOCALBANDNOTE The control band, split by regime, and the rows below the floor.
%
%   ONE BAND WAS NOT ENOUGH, AND THE FIRST CROSS-HOST COMPARISON SHOWED WHY
%   (rev. 1.194). The controls came back spanning 1.31x to 3.64x - a range so
%   wide that no candidate could possibly move against it, which makes the
%   rule "read the candidates through the controls" vacuous. The spread is not
%   noise: the SCALAR controls sat at 1.31 to 1.70 while the VECTORISED one,
%   the N=5000 arc, sat at 3.64. Those are two different regimes - interpreter
%   and dispatch on one side, threaded compiled arithmetic on the other - and
%   a scalar candidate belongs against the scalar controls only.
%
%   AND THE CHEAPEST ROWS CANNOT BE READ AT ALL. A ratio at 150 ns per call
%   measures the loop and timer around the function, not the function; the two
%   rows that appeared to move hardest against the controls in that comparison
%   were the two fastest rows in the table. They are named here rather than
%   left to be over-read.

    reportLine = "";
    reportLine(end+1, 1) = "";

    ratio = nan(numel(benchRow.key), 1);
    for k = 1:numel(benchRow.key)
        index = find(baseline.bench.key == benchRow.key(k), 1);
        if ~isempty(index)
            ratio(k) = baseline.bench.median(index)/benchRow.median(k);
        end
    end

    isControl = benchRow.role == "control";
    % The bulk controls are the ones timed as a SINGLE call over a large N -
    % callCount 1 - against the per-call controls timed over 2000 repeats.
    isBulk = benchRow.callCount == 1 & isControl;
    scalarBand = ratio(isControl & ~isBulk);
    bulkBand = ratio(isBulk);

    if any(~isnan(scalarBand))
        reportLine(end+1, 1) = sprintf( ...
            '  Control band, SCALAR regime: %.2f to %.2f. Read a per-call candidate here.', ...
            min(scalarBand, [], 'omitnan'), max(scalarBand, [], 'omitnan'));
    end
    if any(~isnan(bulkBand))
        reportLine(end+1, 1) = sprintf( ...
            ['  Control band, VECTORISED regime: %.2f to %.2f. ', ...
            'A different regime, not an outlier.'], ...
            min(bulkBand, [], 'omitnan'), max(bulkBand, [], 'omitnan'));
    end
    reportLine(end+1, 1) = "  A candidate ratio inside its OWN band says nothing about the code.";

    % WHAT THE CHEAPEST ROWS MEASURE, WHICH IS NOT WHAT THEIR NAMES SAY.
    % Rev. 1.194 called these rows UNREADABLE and that was wrong; rev. 1.195
    % measured it. Two consecutive runs of this bench on one host, with the
    % benchmarked code untouched, reproduce every 2000-repeat row to within
    % 4.8 per cent and most to within 2 - and the two cheapest rows, at 0.15
    % and 1.02 us, reproduce to 1.7 and 1.3 per cent. They are among the most
    % PRECISE rows in the table, not the least.
    %
    % What is true is different and more useful: at a tenth of a microsecond
    % the measured time is mostly the fixed cost of entering a function, so
    % the row is a precise measurement OF PER-CALL OVERHEAD rather than of the
    % function's body. Cross-host that is a real and readable number - it says
    % what the other host charges to make a call - and it must simply not be
    % read as a statement about the function named on the row.
    atFloor = benchRow.median < 2e-6 & ~isnan(ratio);
    if any(atFloor)
        reportLine(end+1, 1) = "  DOMINATED BY PER-CALL OVERHEAD (under 2 us, " + ...
            "so the ratio measures what a call";
        reportLine(end+1, 1) = "  COSTS on each host, not the body of the " + ...
            "function named): " + ...
            strjoin(benchRow.key(atFloor), ", ") + ".";
    end

    % AND THE ROWS TO ACTUALLY DISTRUST ARE THE SINGLE-SHOT ONES. A row timed
    % as ONE call over seven trials carries the run-to-run scatter of a single
    % measurement: the same two runs that gave 1.3 per cent on the cheap rows
    % gave 11.8 per cent on the headline and 3.4 on the vectorised control.
    % Both of those are single-shot, and the vectorised control is what the
    % VECTORISED band above rests on, so its width is not to be over-read.
    singleShot = benchRow.callCount == 1 & ~isnan(ratio);
    if any(singleShot)
        reportLine(end+1, 1) = "  SINGLE-SHOT ROWS, widest run-to-run scatter " + ...
            "(one call per trial; 3 to 12 per cent";
        reportLine(end+1, 1) = "  on repeat, against under 5 for the 2000-repeat " + ...
            "rows): " + strjoin(benchRow.key(singleShot), ", ") + ".";
    end
end

function reportLine = localCallCountComparison(profileRow, baseline)
%LOCALCALLCOUNTCOMPARISON Calls per rotation, before and after.
%   THIS IS THE ONE COMPARISON NO HOST CHANGE CAN SPOIL. A call count is an
%   integer property of the code, so it answers "is this function reached less
%   often" exactly, on any machine, and that is the question P28b was set.
    reportLine = "";
    reportLine(end+1, 1) = "  CALLS PER ROTATION, baseline -> now. Host-independent.";
    reportLine(end+1, 1) = "  " + pad("function", 52) + pad("was", 12) + ...
        pad("now", 12) + "delta";
    reportLine(end+1, 1) = "  " + string(repmat('-', 1, 88));

    for k = 1:numel(profileRow.name)
        if ~profileRow.watched(k)
            continue
        end
        % FOLDED ON BOTH SIDES (rev. 1.194). The baseline key and the current
        % name are path-shaped for the gateway and carryEpoch, and the two
        % hosts spell a path differently; matching them raw is what made a
        % Windows baseline report seventeen carryEpoch calls as newly added.
        index = find(localFoldSeparators(baseline.profile.key) == ...
            localFoldSeparators(profileRow.name(k)), 1);
        if isempty(index)
            continue
        end
        was = baseline.profile.calls(index);
        current = profileRow.calls(k);
        % A FUNCTION THAT HAS DISAPPEARED IS THE RESULT, NOT A GAP. NaN means
        % the profile never reached it, which after a change is exactly the
        % outcome the change was made for - leapSecondTable>localMjdOfDatetime
        % going from four calls to none is what P28b's first half is FOR. It is
        % counted as zero and labelled, rather than printed as NaN and read as
        % a measurement that failed.
        note = "";
        if isnan(current)
            current = 0;
            note = "   (gone)";
        end
        if isnan(was)
            was = 0;
            note = note + "   (absent in baseline)";
        end
        reportLine(end+1, 1) = "  " + pad(profileRow.name(k), 52) + ...
            pad(sprintf('%.2f', was), 12) + pad(sprintf('%.2f', current), 12) + ...
            sprintf('%+.2f', current - was) + note; %#ok<AGROW>
    end
end

function value = localBaselineField(baseline, fieldName)
%LOCALBASELINEFIELD A baseline environment field, or a marker if it is absent.
    if isfield(baseline.environment, fieldName)
        value = string(baseline.environment.(fieldName));
    else
        value = "(absent)";
    end
end

function reportLine = localMachineBlock(environment, profileRow, benchRow)
%LOCALMACHINEBLOCK The rows this function reads back as a baseline.
%   The report and the baseline are the SAME artefact. A separate baseline file
%   is a second thing to keep in step, and this project has recorded three
%   occasions on which a second copy of something eventually disagreed with the
%   first (obligation O20).
    reportLine = "MACHINE-READABLE ROWS — this section is what 'Baseline' parses";
    reportLine(end+1, 1) = "";

    fieldName = string(fieldnames(environment));
    for k = 1:numel(fieldName)
        reportLine(end+1, 1) = "ENV | " + fieldName(k) + " | " + ...
            string(environment.(char(fieldName(k)))); %#ok<AGROW>
    end

    for k = 1:numel(profileRow.name)
        reportLine(end+1, 1) = "PROFILE | " + profileRow.name(k) + " | " + ...
            sprintf('%.4f', profileRow.calls(k)) + " | " + ...
            sprintf('%.9f', profileRow.selfSeconds(k)) + " | " + ...
            sprintf('%.9f', profileRow.totalSeconds(k)) + " | " + ...
            sprintf('%.4f', profileRow.sharePercent(k)); %#ok<AGROW>
    end

    for k = 1:numel(benchRow.key)
        reportLine(end+1, 1) = "BENCH | " + benchRow.key(k) + " | " + ...
            benchRow.role(k) + " | " + string(benchRow.callCount(k)) + " | " + ...
            sprintf('%.9e', benchRow.median(k)) + " | " + ...
            sprintf('%.9e', benchRow.fastest(k)); %#ok<AGROW>
    end
end

function localVerifyRoundTrip(reportFile, profileRow, benchRow)
%LOCALVERIFYROUNDTRIP Read the report back and check every row survived.
%   The writer and the reader are two implementations of one format, and this
%   project has recorded three occasions on which a second copy of something
%   eventually disagreed with the first (obligation O20). The check is made here
%   rather than in a unit test because a report that does not parse is useless
%   at the moment it is written, not at the next suite run - and because the
%   defect it guards against, a benchmark format the parser silently drops, is
%   exactly what cost nine speed rows at run 20.
    readBack = localReadBaseline(reportFile);
    offence = strings(0, 1);

    for k = 1:numel(benchRow.key)
        index = find(readBack.bench.key == benchRow.key(k), 1);
        if isempty(index)
            offence(end+1, 1) = "BENCH row lost: " + benchRow.key(k); %#ok<AGROW>
        elseif ~localSameNumber(readBack.bench.median(index), benchRow.median(k), 1e-8)
            offence(end+1, 1) = "BENCH median changed: " + benchRow.key(k); %#ok<AGROW>
        end
    end

    for k = 1:numel(profileRow.name)
        index = find(readBack.profile.key == profileRow.name(k), 1);
        if isempty(index)
            offence(end+1, 1) = "PROFILE row lost: " + profileRow.name(k); %#ok<AGROW>
        elseif ~localSameNumber(readBack.profile.calls(index), profileRow.calls(k), 1e-4)
            offence(end+1, 1) = "PROFILE call count changed: " + ...
                profileRow.name(k); %#ok<AGROW>
        end
    end

    if ~isempty(offence)
        warning('referenceSystem:profileRotationCall:reportDoesNotRoundTrip', ...
            ['The report was written but does not parse back into the same ', ...
            'rows, so it cannot serve as a baseline. %d offence(s):\n%s'], ...
            numel(offence), join(offence, newline));
    end
end

function same = localSameNumber(a, b, tolerance)
%LOCALSAMENUMBER Equality at the precision the report was written with.
%   THE TOLERANCE IS THE FORMAT, NOT A GUESS. Call counts are written with
%   %.4f and times with %.9e, so a check tighter than the printed precision
%   would report every rounded row as lost. NaN is a legitimate value here - an
%   unreached function and an undetermined share both produce one - so it is
%   treated as equal to itself rather than as a difference.
    same = (isnan(a) && isnan(b)) || abs(a - b) <= tolerance*max(1, abs(b));
end

function reportFile = localAbsolutePath(requested)
%LOCALABSOLUTEPATH Resolve a bare file name against the current folder.
    if strlength(fileparts(requested)) == 0
        reportFile = string(fullfile(pwd, requested));
    else
        reportFile = requested;
    end
end

function rule = localHeavyRule()
%LOCALHEAVYRULE The 80-column rule that opens and closes the report.
    rule = string(repmat('=', 1, 80));
end

function rule = localSectionRule()
%LOCALSECTIONRULE The 80-column rule between report sections.
    rule = string(repmat('-', 1, 80));
end
