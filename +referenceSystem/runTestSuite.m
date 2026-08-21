function [results, reportFile, summary] = runTestSuite(options)
%RUNTESTSUITE Run the referenceSystem test suite and write one plain-text report.
%
%   results = runTestSuite() runs every test in the test folder of this toolbox and
%   writes the report described in handover section D.3 to
%   referenceSystem_testReport.txt in the current folder.
%
%   results = runTestSuite(Tags=t) runs only the tests carrying one of the tags in t.
%   results = runTestSuite(Output=f) writes the report to the file f.
%   results = runTestSuite(Verbose=true) additionally prints framework output.
%   [results, reportFile] = runTestSuite(...) also returns the full path written.
%
% INPUT ARGUMENTS
%   Name             Size   Type      Units  Description
%   ----             ----   ----      -----  -----------
%   options.Tags     1xM    string    -      Test tags to select, or 'all'
%                                            (default). Permitted: contract,
%                                            reference, precision, speed,
%                                            vectorization, layering,
%                                            provenance, diagnostics,
%                                            concurrency, convergence.
%   options.Output   1x1    string    -      Report file name or path. Default
%                                            'referenceSystem_testReport.txt'.
%                                            A bare name is written to the
%                                            TOOLBOX ROOT, not to pwd, so the
%                                            report does not move with the
%                                            current folder. The resolved path
%                                            is returned as writtenTo.
%   options.Verbose  1x1    logical   -      Print framework progress to the
%                                            command window. Default false.
%   options.Instruments
%                    1x1    logical   -      Append the PLATFORM INSTRUMENTS
%                                            section: the host probe and the
%                                            hot-path profile, so ONE report
%                                            per machine answers both "is the
%                                            toolbox correct" and "how does
%                                            this machine behave". Costs a few
%                                            seconds. Default true; set false
%                                            for a pure test run, and it is
%                                            false in the nested run inside
%                                            TestDispatch.
%   options.ScratchDir
%                    1x1    string    -      Second location for the probe's
%                                            file measurement. Default tempdir.
%                                            ON WINDOWS THE DEFAULT SITS UNDER
%                                            THE USER PROFILE and cannot
%                                            separate a scanner from the
%                                            platform; name a path outside it.
%
% OUTPUT ARGUMENTS
%   Name         Size   Type              Units  Description
%   ----         ----   ----              -----  -----------
%   results      1xN    matlab.unittest.  -      One TestResult per selected
%                       TestResult               test; empty if none matched.
%   reportFile   1x1    string            -      Absolute path of the report
%                                                that was written.
%
% METHOD
%   The suite is built with TestSuite.fromFolder over the test folder, which
%   lies outside the package: the test classes call referenceSystem.* exactly as
%   a user does, so a function accidentally left out of the namespace fails the
%   suite instead of resolving through an import (section C.5 rule 4).
%
%   Benchmark and convergence rows are not produced by this function. A test
%   that measures something logs one pipe-separated record through
%   testCase.log, the framework records it, and this function parses those
%   A WARNINGS section lists every test that raised a MATLAB warning it did not
%   suppress. Warnings appear in no TestResult, so before revision 1.58 they
%   reached the console and nowhere else: a real gimbal-lock warning survived
%   four S4 runs unreported and was found by a reader watching the console. The
%   count in SUMMARY is of TESTS THAT WARNED, not of warnings - lastwarn keeps
%   only the most recent - and the section says so rather than implying a total
%   it does not have.
%
%   records into the BENCHMARKS, CONVERGENCE and NOTES sections. The measuring test
%   therefore owns its numbers and the runner owns only their layout. The record
%   formats are built by TestPerformance.benchmarkRecord and
%   TestPerformance.convergenceRecord, the single authority for them.
%
%   The report is one UTF-8 file with LF line endings, fixed-width columns and
%   no colour, so it can be uploaded to a later session and parsed again. Test
%   durations are given to three decimals; benchmark medians to six, because a
%   single-epoch call is measured in microseconds.
%
%   A TEST THAT IS MEANT TO FILTER SAYS SO. Two checks in this suite cannot run
%   on a healthy machine - one needs a MATLAB release that still permits a
%   namespace folder on the path, the other needs a transfer slow enough to time
%   out - and until revision 1.204 the report described them in the framework's
%   words, "assumption was not met" and "assumeTrue failed". Read as intended
%   that says nothing is wrong; read at a glance it says two things are, on
%   every run, for the life of the toolbox. The runner therefore carries an
%   allow-list of the tests whose assumption is EXPECTED to fail, with the
%   standing reason for each. They are labelled SKIP, counted separately in the
%   summary, and listed under INTENTIONALLY SKIPPED with the reason instead of
%   the boilerplate. Every OTHER filtered test keeps the INC label and its own
%   section: an absent optional toolkit is a fact about the machine that the
%   reader needs, and a blanket rename would have buried it. Adding a test to
%   the allow-list is a claim that its premise cannot exist anywhere, not that
%   it happens to be filtered today.
%
%   The header states the toolbox version from toolboxVersion, the MATLAB
%   release and platform, and the MEX and leap-second state from mexInfo. Before
%   the gateway is built, mexInfo reports that fact and the report is written
%   anyway: a harness that only works once the toolbox is finished is not a
%   harness.
%
%   Every call to a sibling package function is qualified and is made in this
%   main function, never in a local one: a namespace folder is not on the path,
%   so an unqualified sibling name does not resolve anywhere in a package file,
%   and the local formatting functions receive what they need as arguments
%   rather than fetching it.
%
%   The second output exists because no library function in this toolbox prints
%   (design principle 10), so the location of the report would otherwise be
%   undiscoverable whenever the default is used.
%
% ACCURACY
%   Not applicable to the runner itself; it computes no physical quantity.
%   Durations are wall-clock values reported by the test framework and inherit
%   its resolution, typically a few microseconds, which is why the speed tests
%   of section D.1 take a median over repetitions rather than a single timing.
%
% ERRORS
%   referenceSystem:runTestSuite:testFolderMissing
%
% WARNINGS
%   None raised by this function. It RECORDS the warnings raised by the tests
%   it runs, in the WARNINGS section of the report; see WarningRecordingPlugin.
%       The test folder is not where the package expects it, next to the
%       package folder. Reinstall the toolbox as one distribution folder.
%   referenceSystem:runTestSuite:cannotWriteReport
%       The report file could not be opened for writing.
%
% REFERENCES
%   Handover section D.1 (test categories), D.2 (structure), D.3 (this report).
%
% EXAMPLE
%   results = referenceSystem.runTestSuite();
%   contractOnly = referenceSystem.runTestSuite(Tags="contract", Verbose=true);
%
% KEYWORDS
%   test, suite, report, unittest, benchmark, convergence, harness
%
% See also MEXINFO, TOOLBOXVERSION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.Tags (1,:) string {mustBeMember(options.Tags, ["all", "contract", ...
            "reference", "precision", "speed", "vectorization", "layering", ...
            "provenance", "diagnostics", "concurrency", "convergence"])} = "all"
        options.Output (1,1) string {mustBeNonzeroLengthText} = ...
            "referenceSystem_testReport.txt"
        options.Verbose (1,1) logical = false
        options.Instruments (1,1) logical = true
        options.ScratchDir (1,1) string = ""
    end

    import matlab.unittest.TestSuite
    import matlab.unittest.TestRunner
    import matlab.unittest.Verbosity
    import matlab.unittest.plugins.DiagnosticsRecordingPlugin
    import matlab.unittest.selectors.HasTag

    toolboxRoot = fileparts(fileparts(mfilename('fullpath')));
    testFolder = fullfile(toolboxRoot, 'test');
    if ~isfolder(testFolder)
        error('referenceSystem:runTestSuite:testFolderMissing', ...
            ['The test folder %s does not exist. The test classes must sit next ', ...
            'to the +referenceSystem package inside one distribution folder.'], ...
            testFolder);
    end

    localRequireResolvablePackage(toolboxRoot);

    suite = TestSuite.fromFolder(testFolder);

    % A TEST CLASS THAT FAILS TO PARSE IS EXCLUDED FROM THE SUITE AND THE RUN
    % REPORTS GREEN. TestSuite.fromFolder warns to the console and carries on,
    % so a duplicate method name or a stray keyword removes forty-five tests
    % and every remaining one passes. That happened: 391 of 436 ran, nothing
    % failed, and the report said so.
    %
    % THIS IS THE WORST FAILURE MODE THE HARNESS HAS, because it is the only
    % one that looks like success. It is caught by asking the question the
    % framework does not: every Test*.m file on disk must contribute at least
    % one test. The check runs BEFORE the tests, so the report can name the
    % file rather than leaving the reader to compare counts against memory.
    excludedClass = localExcludedClasses(testFolder, suite);

    if ~any(options.Tags == "all")
        selector = HasTag(options.Tags(1));
        for k = 2:numel(options.Tags)
            selector = selector | HasTag(options.Tags(k));
        end
        suite = suite.selectIf(selector);
    end

    if options.Verbose
        runner = TestRunner.withTextOutput('OutputDetail', Verbosity.Detailed);
    else
        runner = TestRunner.withNoPlugins();
    end
    runner.addPlugin(DiagnosticsRecordingPlugin( ...
        'IncludingPassingDiagnostics', true, 'LoggingLevel', Verbosity.Verbose));

    % A warning raised inside a test appears in no TestResult and reached no
    % previous report; it went to the console and was seen only if somebody was
    % watching. In S4 a genuine gimbal-lock warning survived four runs that way.
    %
    % The framework puts the test folder on the path for the DURATION OF THE
    % RUN, which is why TestPerformance resolves inside a test although nothing
    % here adds it. The plugin is constructed before the run and so falls
    % outside that scope; it needs the folder on the path itself, and must put
    % the path back, because a test harness that leaves the path changed is a
    % harness that changes what it measures.
    previousPath = path();
    restorePath = onCleanup(@() path(previousPath)); %#ok<NASGU>
    addpath(testFolder);

    warningPlugin = WarningRecordingPlugin();
    runner.addPlugin(warningPlugin);

    % THE RUN IS WRAPPED SO THAT A REPORT EXISTS WHATEVER HAPPENS, AND THIS
    % IS DECISION D98 FOR THE THIRD TIME IN THIS PROJECT. Rev. 1.135:
    % downloadKernels raised and annihilated the manifest it existed to
    % produce. Rev. 1.164: one <missing> element made fprintf refuse an entire
    % report of 577 results. Both were repaired where they happened, and the
    % same shape was left standing ONE LEVEL UP - if anything between here and
    % writeReport throws, or the run itself throws, there is no file at all and
    % the user is left with a report from three revisions ago and no way to
    % tell why. Which is exactly what happened after rev. 1.169.
    %
    % A run that dies still knows a great deal worth writing down: which
    % results completed, what the environment was, and what killed it. All of
    % that is now written, the report says plainly that it is INCOMPLETE, and
    % the exception is re-raised afterwards so a caller checking for one still
    % sees it.
    runFailure = MException.empty;
    if isempty(suite)
        results = matlab.unittest.TestResult.empty(1, 0);
    else
        try
            results = runner.run(suite);
        catch runFailure
            results = matlab.unittest.TestResult.empty(1, 0);
        end
    end

    % Sibling calls are qualified, and their results are passed down to the
    % local functions: a namespace folder is never on the path, so an
    % unqualified name inside a package function resolves against the path and
    % this file only (§C.5 rule 2, measured rev. 1.31).
    environment = struct( ...
        'versionInfo', referenceSystem.toolboxVersion(), ...
        'mexState', referenceSystem.mexInfo(), ...
        'requestedTags', options.Tags, ...
        'excludedClass', excludedClass);

    % THE INSTRUMENTS RUN AFTER THE SUITE AND CANNOT SPOIL IT (rev. 1.198).
    % `probePlatformCost` and `profileRotationCall` used to be three separate
    % commands producing three files, which is three chances to run the wrong
    % one and two files to remember; one report is one upload. They are
    % gathered here, AFTER the results exist, and every failure is caught and
    % written into the report as text rather than raised - the D98 rule that
    % the artefact outlives the exception, applied to the artefact this
    % function exists to produce.
    instrument = struct('requested', options.Instruments, 'probe', [], ...
        'probeFailure', "", 'profileText', strings(0, 1), ...
        'profileFailure', "", 'scratchDir', options.ScratchDir);
    if options.Instruments
        instrument = gatherInstruments(instrument);
    end

    reportFile = absoluteReportPath(options.Output);
    writeReport(reportFile, results, suite, environment, ...
        warningPlugin.WarningRecord, runFailure, instrument);

    % THE CLASSIFICATION THE REPORT PRINTS, RETURNED RATHER THAN REPRINTED.
    % ciGate has to distinguish a skip that D116 foresaw from one that nobody
    % did, and the allow-list that makes the distinction lives in this file.
    % A copy in the caller is the defect auditPackage.py's own header names -
    % two instruments disagreeing after one of them is edited - so the counts
    % are computed HERE, from intendedFilterMask, and handed out.
    summary = localRunSummary(results);

    % THE ARTEFACT FIRST, THE EXCEPTION SECOND - the same order as the
    % excluded-class error below, and for the same reason.
    if ~isempty(runFailure)
        rethrow(runFailure)
    end

    % RAISED AFTER THE REPORT IS WRITTEN, not instead of it. The results that
    % did run are still worth reading, and a reader who has the file in front
    % of them can see which class is missing. But the run cannot be allowed to
    % END quietly: a caller that only checks for an exception would otherwise
    % treat a suite missing a tenth of itself as a pass.
    if ~isempty(excludedClass)
        error('referenceSystem:runTestSuite:testClassExcluded', ...
            ['%d test class(es) contributed no tests and were excluded from ', ...
            'the run: %s. The report at %s covers only what ran. Load the ', ...
            'class directly to see the parse error, for example ', ...
            'matlab.unittest.TestSuite.fromFile.'], numel(excludedClass), ...
            join(excludedClass, ", "), reportFile);
    end
end

function excluded = localExcludedClasses(testFolder, suite)
%LOCALEXCLUDEDCLASSES Test class files that contributed nothing to the suite.
%   Compared by class name rather than by counting, so the answer names the
%   file to open instead of reporting a shortfall the reader has to locate.

    onDisk = dir(fullfile(testFolder, 'Test*.m'));
    onDisk = string(erase({onDisk.name}, ".m"));
    if isempty(suite)
        inSuite = strings(1, 0);
    else
        % A test name is Class/method, and a CLASS-LEVEL parameterisation puts
        % its parameter in brackets after the class - TestEop[fixture=x]/method.
        % Both are stripped, so a parameterised class is not reported missing
        % on the strength of its own parameters.
        className = extractBefore(string({suite.Name}) + "/", "/");
        inSuite = unique(extractBefore(className + "[", "["));
    end
    excluded = setdiff(onDisk, inSuite);
    excluded = reshape(excluded, 1, []);
end

% -------------------------------------------------------------------------
% Report assembly
% -------------------------------------------------------------------------

function instrument = gatherInstruments(instrument)
%GATHERINSTRUMENTS Run the two platform instruments, surviving either failing.
%   Neither is a test and neither can change the counts: they are measurements
%   of the HOST, gathered so that one report answers "how does this machine
%   behave" without a second command. A machine without the EOP fixture, or
%   without a built gateway, simply records why instead of stopping the run.

    try
        if instrument.scratchDir == ""
            % The default scratch warns on Windows because tempdir sits under
            % the user profile there. The report carries that caveat in the
            % block itself, so the warning is suppressed rather than printed
            % twice - and it is consumed, per the plugin rule.
            previousState = warning('off', ...
                'referenceSystem:probePlatformCost:scratchIsAlsoScanned');
            restoreWarning = onCleanup(@() warning(previousState)); %#ok<NASGU>
            lastwarnCleanup = onCleanup(@() lastwarn('', ''));      %#ok<NASGU>
            instrument.probe = probePlatformCost();
        else
            instrument.probe = probePlatformCost( ...
                ScratchDir = instrument.scratchDir);
        end
    catch probeFailure
        instrument.probeFailure = string(probeFailure.message);
    end

    try
        % Written to a temporary file and deleted: profileRotationCall reads
        % its own report back to verify the format survived, so the file has
        % to exist, but a caller who asked for ONE report should not find a
        % second one beside it.
        temporaryReport = fullfile(tempdir, "rsHotPathProfile.txt");
        removeTemporary = onCleanup(@() deleteIfPresent(temporaryReport)); %#ok<NASGU>
        [~, instrument.profileText] = profileRotationCall( ...
            Output = temporaryReport);
    catch profileFailure
        instrument.profileFailure = string(profileFailure.message);
    end
end

function deleteIfPresent(fileName)
%DELETEIFPRESENT Remove a file if it is there, and say nothing if it is not.

    if isfile(fileName)
        delete(fileName);
    end
end

function writeReport(reportFile, results, suite, environment, warningRecord, ...
        runFailure, instrument)
%WRITEREPORT Compose the section D.3 report and write it as UTF-8 with LF.

    reportLine = [headerBlock(environment); ...
        interruptedBlock(runFailure); ...
        summaryBlock(results, suite, environment.requestedTags, warningRecord); ...
        excludedBlock(environment.excludedClass); ...
        sectionRule(); ...
        benchmarkBlock(results); ...
        sectionRule(); ...
        convergenceBlock(results); ...
        sectionRule(); ...
        noteBlock(results); ...
        sectionRule(); ...
        failureBlock(results); ...
        sectionRule(); ...
        warningBlock(warningRecord); ...
        sectionRule(); ...
        fullResultBlock(results); ...
        sectionRule(); ...
        instrumentBlock(instrument); ...
        heavyRule()];

    [fileId, message] = fopen(reportFile, 'w', 'n', 'UTF-8');
    if fileId < 0
        error('referenceSystem:runTestSuite:cannotWriteReport', ...
            'Cannot open %s for writing: %s', reportFile, message);
    end
    closeFile = onCleanup(@() fclose(fileId));

    % THE REPORT MUST SURVIVE A BAD ELEMENT (obligation O30). fprintf refuses a
    % string array containing <missing> and refuses ALL of it, so one faulty
    % line in a header costs every benchmark, every convergence row and every
    % one of 577 results - the run is over and there is nothing to read. That
    % is the D98 defect in a new place: a mechanism that exists to preserve an
    % artefact destroying it instead. The offending line is marked in the
    % report and named in a warning, and everything else is written.
    faulty = ismissing(reportLine);
    if any(faulty)
        reportLine(faulty) = "<<< a report block returned a missing string; " + ...
            "this line is lost, the rest of the report is complete >>>";
        warning('referenceSystem:runTestSuite:missingReportLine', ...
            ['%d report line(s) were missing and have been marked in %s. ', ...
            'A block composed a line from a value that does not exist - ', ...
            'usually a substring taken of a toolboxVersion field rather ', ...
            'than the field itself.'], sum(faulty), reportFile);
    end

    % AND NO LINE MAY CARRY A CONTROL CHARACTER (rev. 1.168). THIS RUNS
    % AFTER the missing repair above, because regexp has nothing to say about
    % <missing> and would raise where it is meant to be tidying up. Run 70's report
    % contained a single NUL, out of the NUL padding of a SPICE comment area,
    % and one such byte is enough for every tool that reads the file to call it
    % binary - the report was intact and unreadable at the same time. The
    % formatter that let it through has been tightened, but this is the layer
    % that writes the file and it is where the property must actually hold: a
    % section can only produce text, whatever it was given.
    control = regexp(reportLine, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', 'once');
    tainted = ~cellfun(@isempty, control);
    if any(tainted)
        reportLine(tainted) = regexprep(reportLine(tainted), ...
            '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]+', " ");
        warning('referenceSystem:runTestSuite:controlCharacterInReport', ...
            ['%d report line(s) carried a control character and it has been ', ...
            'replaced with a space in %s. A block put raw file content into ', ...
            'a report field; the field formatter is where that belongs.'], ...
            sum(tainted), reportFile);
    end

    fprintf(fileId, '%s\n', reportLine);
end

function reportLine = headerBlock(environment)
%HEADERBLOCK The six identification lines and their rules.
%
%   THE VERSION LINE EXISTS BECAUSE OF D107. The footer tag carries the release
%   and never the patch, so without this line a report could not be tied to the
%   handover revision that produced it - and dates cannot do that job, since two
%   revisions on one day are ordinary in this project. Every field is read, none
%   is parsed (obligation O30).
%   versionInfo and mexState are supplied by the main function, which keeps this
%   function pure and keeps every qualified sibling call in one place.
%
%   THE TITLE READS versionTag DIRECTLY AND MUST NEVER PARSE IT OUT OF helpTag.
%   Until rev. 1.164 this line was extractBefore(helpTag, " | "), which worked
%   only because the two facts happened to share one string with a separator
%   between them. D103 split them into two lines, the separator went with it,
%   extractBefore returned <missing>, and fprintf refused the whole array - so
%   a green run of 577 tests produced NO REPORT AT ALL. Decision D38 makes
%   toolboxVersion the single authority for these strings; a caller that
%   re-splits a composed value has made itself a second one.

    versionInfo = environment.versionInfo;
    mexState = environment.mexState;
    timestamp = datetime('now', 'TimeZone', 'local');
    timestamp.Format = 'yyyy-MM-dd HH:mm:ss';

    reportLine = [heavyRule(); ...
        versionInfo.versionTag + " — TEST REPORT"; ...
        pad("Version", 10) + ": " + versionInfo.version + ...
            " (handover rev. 1." + versionInfo.patch + ", built " + ...
            versionInfo.buildDate + ")"; ...
        pad("Generated", 10) + ": " + string(timestamp) + " (" + ...
            zoneLabel(timestamp) + ")"; ...
        pad("MATLAB", 10) + ": " + string(version()) + "  on " + string(computer()); ...
        pad("MEX", 10) + ": " + mexState.summary; ...
        pad("Compiler", 10) + ": " + localCompilerLine(mexState); ...
        pad("Leap sec", 10) + ": " + mexState.leapSecondsSummary; ...
        heavyRule()];
end

function localRequireResolvablePackage(toolboxRoot)
%LOCALREQUIRERESOLVABLEPACKAGE Stop before producing a meaningless report.
%   A test suite whose every assertion fails with "Unable to resolve the name
%   referenceSystem.<anything>" is not evidence about the toolbox; it is
%   evidence about the MATLAB path. Session S2 produced exactly that report --
%   113 tests, 102 failures, three and a half seconds -- and it cost a full
%   round trip to establish that nothing was wrong with the code at all.
%
%   This function can run while the namespace is unresolvable, because
%   runTestSuite can be reached without it: calling the file directly, or from
%   inside the +referenceSystem folder, executes the function while leaving
%   referenceSystem.* unresolvable, since a namespace resolves through the
%   PARENT folder being on the path and never through the namespace folder
%   itself (section C.5 rule 1).
%
%   HOW THE CHECK IS MADE, and how it was made wrongly. Revision 1.42 asked
%   exist('referenceSystem.toolboxVersion', 'file') == 2. exist does not
%   reliably resolve a namespace-qualified function name, so that test could
%   return false while the namespace was perfectly resolvable -- and it did,
%   blocking the suite outright on a correctly configured installation. A guard
%   written to prevent a misdiagnosis, itself built on an unmeasured assumption
%   about a MATLAB builtin. Obligation O9 in its purest form.
%
%   The property is now measured directly by attempting the call, which is the
%   only statement that means exactly what is being asked. The identifier
%   distinguishes "the name does not resolve" from "the name resolves and the
%   function threw", which are different diagnoses and must not be merged.
%
%   The bias is deliberately toward running. A false negative here blocks all
%   work; a false positive merely fails to warn. Anything other than a positive
%   determination that the name cannot be resolved lets the suite proceed.

    try
        referenceSystem.toolboxVersion();
        return
    catch cause
        if ~any(strcmp(cause.identifier, ...
                {'MATLAB:undefinedVarOrClass', 'MATLAB:UndefinedFunction'}))
            % It resolved and failed for some other reason. That is a real
            % defect and belongs to the suite, not to this guard.
            return
        end
    end

    error('referenceSystem:runTestSuite:packageNotResolvable', ...
        ['The +referenceSystem namespace cannot be resolved, so every test ', ...
        'that calls a toolbox function would fail with "Unable to resolve ', ...
        'the name". The suite was not run, because that report would say ', ...
        'nothing about the toolbox.\n\n', ...
        'A namespace resolves through its PARENT folder being on the path, ', ...
        'never through the +referenceSystem folder itself. Fix it with:\n\n', ...
        '    cd(''%s'')\n', ...
        '    setupReferenceSystem\n', ...
        '    referenceSystem.runTestSuite\n\n', ...
        'If runTestSuite was started from inside the +referenceSystem folder ', ...
        'or by running the file directly, that alone is the cause: the ', ...
        'function runs, the namespace does not.'], toolboxRoot);
end

function reportLine = summaryBlock(results, suite, requestedTags, warningRecord)
%SUMMARYBLOCK Totals and the per-tag breakdown.

    if isempty(results)
        reportLine = ["SUMMARY"; ...
            "  Total 0 | Passed 0 | Failed 0 | Skipped 0 (by design) | " + ...
            "Filtered 0 | Warned 0 | Duration 0.000 s"; ...
            "  By tag: (no test matched " + join(requestedTags, ",") + ")"];
        return
    end

    % MATLAB's TestResult.Incomplete is true for a FAILED test as well as for a
    % filtered one -- the three properties are not mutually exclusive. Summing
    % it raw made the S2 report read "Passed 86 | Failed 25 | Incomplete 26" on
    % 112 tests, which does not add up and invites the reader to treat 25 real
    % failures as 26 benign filtered ones. The residual is what belongs here.
    filtered = [results.Incomplete] & ~[results.Failed];
    % AND THE RESIDUAL IS ITSELF TWO THINGS (rev. 1.204). A skip the allow-list
    % foresaw and a skip this machine caused are different facts about the run,
    % and one count for both meant the standing two could never be distinguished
    % from a new one. See intendedFilterCatalogue.
    intended = filtered & intendedFilterMask(results);

    reportLine = ["SUMMARY"; ...
        sprintf(['  Total %d | Passed %d | Failed %d | Skipped %d (by design) ', ...
        '| Filtered %d | Warned %d | Duration %.3f s'], ...
            numel(results), sum([results.Passed]), sum([results.Failed]), ...
            sum(intended), sum(filtered & ~intended), numel(warningRecord), ...
            sum([results.Duration])); ...
        "  By tag: " + tagBreakdown(suite, results)];
end

function text = tagBreakdown(suite, results)
%TAGBREAKDOWN passed/total per tag, in the order the categories are defined.

    knownTag = ["contract", "reference", "precision", "speed", "vectorization", ...
        "layering", "provenance", "diagnostics", "concurrency", "convergence"];
    passed = [results.Passed];
    failed = [results.Failed];
    % Filtered, not Incomplete: see the note in summaryBlock.
    filtered = [results.Incomplete] & ~failed;
    intended = filtered & intendedFilterMask(results);

    field = strings(numel(knownTag), 1);
    isUsed = false(numel(knownTag), 1);
    for k = 1:numel(knownTag)
        hasTag = arrayfun(@(oneTest) any(string(oneTest.Tags) == knownTag(k)), suite);
        isUsed(k) = any(hasTag);
        if ~isUsed(k)
            continue
        end
        field(k) = sprintf('%s %d/%d', knownTag(k), sum(passed & hasTag), sum(hasTag));
        % A test filtered by an unmet assumption is neither a pass nor a
        % failure. Saying so keeps a permanently filtered test, such as the
        % release-dependent path repair of section C.5 rule 1, from reading as
        % an unfixed defect for the life of the toolbox - and rev. 1.204 says
        % WHICH of the two it is, so the shortfall against the total is
        % accounted for rather than merely acknowledged.
        if any(failed & hasTag)
            field(k) = field(k) + sprintf(' (%d failed)', sum(failed & hasTag));
        end
        if any(intended & hasTag)
            field(k) = field(k) + sprintf(' (%d skipped by design)', ...
                sum(intended & hasTag));
        end
        if any(filtered & ~intended & hasTag)
            field(k) = field(k) + sprintf(' (%d filtered)', ...
                sum(filtered & ~intended & hasTag));
        end
    end

    if any(isUsed)
        text = join(field(isUsed), "  ");
    else
        text = "(none tagged)";
    end
end

function reportLine = excludedBlock(excludedClass)
%EXCLUDEDBLOCK Test classes that produced no tests, or nothing at all.
%   Placed directly under the summary rather than at the end, because it
%   invalidates the summary. A reader who stops after the counts must not be
%   able to stop before this.

    if isempty(excludedClass)
        reportLine = strings(0, 1);
        return
    end
    reportLine = [sectionRule(); ...
        "EXCLUDED TEST CLASSES - THE COUNTS ABOVE ARE INCOMPLETE"; ...
        "  " + excludedClass(:) + " contributed no tests and did not run."; ...
        "  A class that fails to parse is dropped from the suite and every"; ...
        "  remaining test still passes, so this report would otherwise read"; ...
        "  as a clean run. Load the class directly to see the parse error."];
end

function reportLine = benchmarkBlock(results)
%BENCHMARKBLOCK Measured throughput against the section B.7 targets.

    record = loggedRecords(results, "BENCHMARK", 5);
    label = ["Function", "N", "Median [s]", "Fastest [s]", "Target [s]", ...
        "Ratio", "Status"];

    field = strings(size(record, 1), 7);
    for k = 1:size(record, 1)
        medianSeconds = str2double(record(k, 3));
        targetSeconds = str2double(record(k, 4));
        fastestSeconds = str2double(record(k, 5));
        ratio = medianSeconds/targetSeconds;
        % A dash, not a zero and not a NaN: the row simply does not carry the
        % figure, which is different from having measured it as nothing.
        if isnan(fastestSeconds)
            fastestText = "--";
        else
            fastestText = string(sprintf('%.6f', fastestSeconds));
        end
        field(k, :) = [record(k, 1), record(k, 2), ...
            string(sprintf('%.6f', medianSeconds)), fastestText, ...
            string(sprintf('%.6f', targetSeconds)), ...
            string(sprintf('%.2f', ratio)), benchmarkStatus(ratio)];
    end
    reportLine = tableBlock("BENCHMARKS", label, field);
end

function status = benchmarkStatus(ratio)
%BENCHMARKSTATUS Section D.1: warn above the target, fail above five times it.

    if ratio <= 1.0
        status = "OK";
    elseif ratio <= 5.0
        status = "WARN";
    else
        status = "FAIL";
    end
end

function reportLine = convergenceBlock(results)
%CONVERGENCEBLOCK Finite-difference step refinement, decision D28.

    record = loggedRecords(results, "CONVERGENCE", 5);
    reportLine = tableBlock("CONVERGENCE (finite-difference steps, D28)", ...
        ["Quantity", "h [s]", "rel. error", "order", "Status"], record);
end

function reportLine = interruptedBlock(runFailure)
%INTERRUPTEDBLOCK What killed the run, placed where it cannot be read past.
%   Directly under the header and above the summary, because it invalidates
%   everything below it - the same placement and the same argument as
%   excludedBlock. A reader who stops after the counts must not be able to stop
%   before this.

    if isempty(runFailure)
        reportLine = strings(0, 1);
        return
    end
    reportLine = [sectionRule(); ...
        "RUN INTERRUPTED - THIS REPORT IS INCOMPLETE"; ...
        "  The test run raised and did not finish. Everything below is what"; ...
        "  had been collected when it stopped, which may be nothing at all."; ...
        "  Identifier : " + string(runFailure.identifier); ...
        "  Message    : " + regexprep(string(runFailure.message), '\s+', ' '); ...
        localStackLines(runFailure)];
end

function reportLine = localStackLines(runFailure)
%LOCALSTACKLINES The first few stack frames, which is where the cause is.

    reportLine = strings(0, 1);
    if isempty(runFailure.stack)
        return
    end
    depth = min(numel(runFailure.stack), 5);
    reportLine = "  Stack      : " + ...
        string({runFailure.stack(1:depth).name})' + " (line " + ...
        string([runFailure.stack(1:depth).line])' + ")";
end

function reportLine = noteBlock(results)
%NOTEBLOCK Facts a test measured or declined to check, decision D108.
%   THE SECTION THAT SHOULD HAVE EXISTED BEFORE ANYTHING WAS LOGGED INTO IT.
%   Rev. 1.163 made a skipped Ceres comparison log a record instead of stepping
%   over it silently, and rev. 1.165 added a record naming what a kernel's
%   comment area contains. This function parsed BENCHMARK and CONVERGENCE and
%   nothing else, so BOTH went nowhere - in revisions that cited obligation O17,
%   "a diagnostic channel that reaches only the console reaches nobody", as
%   their justification. Run 69's report contains neither string, which is how
%   it was found.
%
%   A test that skips something is not a test that passed, and the report must
%   be able to say which. "(none recorded)" is printed rather than the section
%   being omitted, because an absent section reads as an absent instrument.

    record = loggedRecords(results, "NOTE", 3);
    reportLine = tableBlock("NOTES (measured facts and declined checks)", ...
        ["Subject", "Detail", "Reason"], record);
end

function reportLine = tableBlock(title, label, field)
%TABLEBLOCK A titled table whose columns are sized to what is in them.
%   THE ONE PLACE THE THREE REPORT TABLES ARE LAID OUT, AND THEY USED TO BE
%   THREE. pad() EXTENDS AND NEVER TRUNCATES, so a guessed column width does
%   not bound anything - it only decides how often two columns run together.
%   All three guesses were wrong on real content: "rotationIcrfToBodyFixed
%   (N=1000)1000" and "convertCoordinates(N=1, 1000 calls)1000" in BENCHMARKS,
%   "dR/dDeltaUT1 sweep0.1" in CONVERGENCE, "verified 0first line:" in NOTES.
%   Rev. 1.168 repaired the third by hand, which left the same defect standing
%   in the two older tables - the repair that fixes one instance of a shared
%   mistake is the one to distrust.
%
%   The width is MEASURED from the contents and the header, so a table cannot
%   collide whatever a test decides to call itself, and no label is truncated
%   to fit a layout. The last column is never padded, because trailing spaces
%   are invisible and only make the file bigger.
%
%   title   1x1    string   heading printed above the table
%   label   1xM    string   column headings
%   field   NxM    string   already-formatted cell contents

    header = title;
    if isempty(field)
        reportLine = [header; "  (none recorded)"];
        return
    end

    width = max([strlength(label); strlength(field)], [], 1) + 2;

    row = strings(size(field, 1) + 1, 1);
    row(1) = paddedRow(label, width);
    for k = 1:size(field, 1)
        row(k + 1) = paddedRow(field(k, :), width);
    end
    reportLine = [header; row];
end

function line = paddedRow(cellText, width)
%PADDEDROW One table row: every column padded to its width but the last.
%   pad is called with a SCALAR width per cell rather than a vector for the
%   whole row. Whether pad accepts a vector of widths is a question about the
%   language that I would be answering from memory, and obligation O16 says a
%   base-MATLAB call is not exempt from the check-the-source rule. A loop over
%   scalars needs no such check.

    line = "  ";
    for j = 1:numel(cellText)
        if j == numel(cellText)
            line = line + cellText(j);          % never pad the last column
        else
            line = line + pad(cellText(j), width(j));
        end
    end
end

function reportLine = failureBlock(results)
%FAILUREBLOCK Failures, intentional skips and unexpected filters, kept apart.
%   Until rev. 1.203 a test filtered by an unmet assumption was listed UNDER
%   THE HEADING "FAILURES" with an INC label - and on 2026-08-05 that report
%   made its own author read a green run as two failures. The heading is the
%   first word a reader takes in and the label is the last; a section must not
%   say one thing in its banner and another in its rows. Failures and filtered
%   tests were separated there, each section saying "(none)" when empty.
%
%   REV. 1.204 SPLITS THE FILTERED SECTION IN TWO, because separating it from
%   FAILURES was necessary and not sufficient. The two tests that filter on
%   every run of this toolbox are DESIGNED to filter - one needs a MATLAB
%   release that still permits a namespace folder on the path, the other needs
%   a network slow enough to time out - and the report described them in the
%   framework's words: "assumption was not met", "assumeTrue failed", "Actual
%   Value: logical 0". That is the mechanism, not the meaning, and it reads
%   like two defects that nobody has got round to fixing. It will read that way
%   to every user of this toolbox, on every run, for as long as it stands.
%
%   So the runner now carries an ALLOW-LIST (intendedFilterCatalogue) naming
%   the tests whose assumption is expected to fail, with the standing reason
%   why. Those are reported as SKIP under a heading that says by design, with
%   the boilerplate dropped. An allow-list rather than a blanket rename,
%   because the OTHER kind of filtered test - the optional toolkit that is
%   absent, the fixture that was not installed - is information the reader
%   wants and must not be normalised away by a word that says "expected".

    if isempty(results)
        reportLine = [detailBlock("FAILURES", results, []); sectionRule(); ...
            intendedBlock(results, []); sectionRule(); ...
            detailBlock(unexpectedFilterHeading(), results, [])];
        return
    end

    failed = [results.Failed];
    reportLine = detailBlock("FAILURES", results, failed);

    % Filtered, not Incomplete: see the note in summaryBlock. Still listed in
    % full, with the assumption diagnostic, because a filtered test is not a
    % pass and the REASON it filtered is the content - the reader decides
    % whether the assumption is the designed one or a machine problem.
    filtered = [results.Incomplete] & ~failed;
    intended = filtered & intendedFilterMask(results);

    reportLine = [reportLine; sectionRule(); ...
        intendedBlock(results, intended); sectionRule(); ...
        detailBlock(unexpectedFilterHeading(), results, filtered & ~intended)];
end

function heading = unexpectedFilterHeading()
%UNEXPECTEDFILTERHEADING Banner of the filtered tests that are NOT on the list.
%   It still says "not a failure" in its own words, because an absent optional
%   toolkit is not a defect either - but it does not say "expected", because
%   the whole point of keeping this section separate is that its contents
%   describe THIS MACHINE and deserve a reader's attention.

    heading = "FILTERED - AN ASSUMPTION DID NOT HOLD ON THIS MACHINE " + ...
        "(NOT A FAILURE)";
end

function summary = localRunSummary(results)
%LOCALRUNSUMMARY Counts of the run, with skips split by whether they were foreseen.
%
%   The fields exist so a gate does not have to re-derive them, and so that a
%   NEW permanently filtered test cannot enter the tree behind a word that
%   says it was foreseen: anything filtered and not on the allow-list is
%   counted as unexpected and named.

    failed = [results.Failed];
    filtered = [results.Incomplete] & ~failed;
    intended = intendedFilterMask(results) & filtered;
    unexpected = filtered & ~intended;

    summary = struct( ...
        'total', numel(results), ...
        'passed', sum([results.Passed]), ...
        'failed', sum(failed), ...
        'intendedSkip', sum(intended), ...
        'unexpectedFilter', sum(unexpected), ...
        'unexpectedFilterName', string({results(unexpected).Name}), ...
        'duration', sum([results.Duration]));
end

function catalogue = intendedFilterCatalogue()
%INTENDEDFILTERCATALOGUE Tests whose assumption is EXPECTED not to hold.
%
%   THE SINGLE AUTHORITY FOR "THIS SKIP IS INTENTIONAL". A test may only be
%   listed here when its premise cannot be created on a healthy, fully equipped
%   machine - not when it merely happens to be filtered today. The distinction
%   is the whole value of the list: anything not named here is reported as an
%   unexpected filter, so a NEW permanently filtered test cannot hide behind a
%   word that says it was foreseen.
%
%   Name is the full matlab.unittest test name, Class/method. Parameterisation
%   brackets are stripped before the comparison, so a parameterised test is
%   named once and not once per parameter.

    name = [ ...
        "TestDispatch/setupReferenceSystem_contract_removesThePackageFolderFromPath"; ...
        "TestEphemeris/downloadKernels_contract_partialFetchWarnsAndReturnsTheManifest"];

    reason = [ ...
        "Release-dependent, and expected to filter on every current MATLAB. " + ...
            "The test must first CREATE the section C.5 rule 1 " + ...
            "misconfiguration - a +referenceSystem namespace folder on the " + ...
            "path - before it can check that setup undoes it. R2024b and " + ...
            "later refuse to put a namespace folder on the path at all, so " + ...
            "the defect cannot be built here and there is nothing to repair. " + ...
            "The check still runs on R2024a and earlier."; ...
        "Network-dependent, and expected to filter on any fast connection. " + ...
            "The test observes what downloadKernels does when a transfer " + ...
            "FAILS, and provokes one with a one-second timeout. A NAIF host " + ...
            "that answers inside that second leaves no failed transfer to " + ...
            "observe, and the remaining assertions would then hold without " + ...
            "testing anything - a vacuous pass, which is worse than a skip. " + ...
            "See handover section H.11 for the catalogue seam that would " + ...
            "make it deterministic."];

    catalogue = table(name, reason, 'VariableNames', ["Name", "Reason"]);
end

function [isIntended, reason] = intendedFilter(testName)
%INTENDEDFILTER Whether a test is on the allow-list, and the standing reason.

    catalogue = intendedFilterCatalogue();
    % A class-level parameterisation writes TestEop[fixture=x]/method and a
    % method-level one writes method(param=y); the allow-list names the test,
    % never the parameter, so both bracket forms are removed before matching.
    bareName = regexprep(string(testName), '[\[\(][^\]\)]*[\]\)]', '');
    row = find(catalogue.Name == bareName, 1);
    isIntended = ~isempty(row);
    if isIntended
        reason = catalogue.Reason(row);
    else
        reason = "";
    end
end

function mask = intendedFilterMask(results)
%INTENDEDFILTERMASK Row mask of the results named in the allow-list.

    mask = false(1, numel(results));
    for k = 1:numel(results)
        mask(k) = intendedFilter(results(k).Name);
    end
end

function reportLine = intendedBlock(results, selected)
%INTENDEDBLOCK Filtered tests that are MEANT to filter, with the standing reason.
%   Its own block and not a detailBlock with a different heading, because the
%   CONTENT differs and not only the banner. A test on the allow-list did not
%   "fail an assumption"; it declined to run a check whose premise this machine
%   cannot supply, and that was foreseen when the test was written. The
%   framework boilerplate - "assumeTrue failed", "The value must evaluate to
%   true", "Actual Value: logical 0" - is therefore dropped: the assumed value
%   is false by construction, so printing it adds nothing but the appearance of
%   a defect. What is printed instead is the standing reason from the catalogue
%   and the sentence the test itself supplied.

    heading = "INTENTIONALLY SKIPPED - BY DESIGN, NOT A FAILURE";
    if isempty(results) || ~any(selected)
        reportLine = [heading; "  (none)"];
        return
    end

    index = find(selected);
    reportLine = heading;
    for k = 1:numel(index)
        oneResult = results(index(k));
        [~, reason] = intendedFilter(oneResult.Name);
        reportLine = [reportLine; ...
            sprintf('  [%d] SKIP %s', k, oneResult.Name); ...
            wrappedField("By design", reason); ...
            wrappedField("The test", spokenDiagnostic(oneResult)); ...
            wrappedField("Location", qualificationLocation(oneResult))]; %#ok<AGROW>
    end
end

function text = spokenDiagnostic(oneResult)
%SPOKENDIAGNOSTIC The sentence the TEST supplied, without the framework's.
%   qualificationDiagnostic deliberately appends the framework diagnostic,
%   because a failure needs the actual and the expected value. A designed skip
%   needs neither, for the reason given in intendedBlock.

    text = "(the test supplied no reason of its own)";
    record = failureRecords(oneResult);
    for k = 1:numel(record)
        spoken = firstNonEmptyDiagnostic(record(k), 'TestDiagnosticResult');
        if strlength(spoken) > 0
            text = spoken;
            return
        end
    end
end

function reportLine = wrappedField(label, text)
%WRAPPEDFIELD One "      Label      : value" entry, wrapped to the report width.
%   The report is a fixed-width document read in a terminal and uploaded to a
%   later session, so a three-hundred-character reason on one line is a reason
%   nobody reads. Continuations are indented to the value column, which leaves
%   the label the only thing in the left margin and keeps the block scannable.

    lead = "      " + pad(string(label), 11) + ": ";
    continuation = string(blanks(strlength(lead)));
    word = split(strip(regexprep(string(text), '\s+', ' ')), " ");
    word = word(strlength(word) > 0);
    if isempty(word)
        reportLine = lead + "(none)";
        return
    end

    reportLine = strings(0, 1);
    line = lead + word(1);
    for k = 2:numel(word)
        if strlength(line) + 1 + strlength(word(k)) <= ruleWidth()
            line = line + " " + word(k);
        else
            reportLine(end+1, 1) = line; %#ok<AGROW>
            line = continuation + word(k);
        end
    end
    reportLine(end+1, 1) = line;
end

function reportLine = detailBlock(heading, results, selected)
%DETAILBLOCK One indented entry per selected test, under the given heading.

    if isempty(results) || ~any(selected)
        reportLine = [heading; "  (none)"];
        return
    end

    badIndex = find(selected);
    entry = strings(4*numel(badIndex), 1);
    for k = 1:numel(badIndex)
        oneResult = results(badIndex(k));
        entry(4*k-3) = sprintf('  [%d] %-4s %s', k, resultStatus(oneResult), ...
            oneResult.Name);
        entry(4*k-2) = "      Assertion  : " + qualificationSummary(oneResult);
        entry(4*k-1) = "      Location   : " + qualificationLocation(oneResult);
        entry(4*k) = "      Diagnostic : " + qualificationDiagnostic(oneResult);
    end
    reportLine = [heading; entry];
end

function reportLine = fullResultBlock(results)
%FULLRESULTBLOCK Every test in suite order, with status, duration and name.

    if isempty(results)
        reportLine = ["FULL RESULTS"; "  (empty suite)"];
        return
    end

    row = strings(numel(results), 1);
    for k = 1:numel(results)
        row(k) = sprintf('  %-5s %9.3f s  %s', resultStatus(results(k)), ...
            results(k).Duration, results(k).Name);
    end
    reportLine = ["FULL RESULTS"; row];
end

function status = resultStatus(oneResult)
%RESULTSTATUS Fixed-width status label of one test result.
%   FOUR LABELS, NOT THREE (rev. 1.204). A reader scanning FULL RESULTS for
%   something that is not PASS finds INC and has to go and look up why; SKIP
%   answers that question in the four characters it already occupies, for the
%   tests the allow-list says were meant to filter. Anything else still reads
%   INC, which is the point of having two labels rather than one.

    if oneResult.Passed
        status = "PASS";
    elseif oneResult.Failed
        status = "FAIL";
    elseif intendedFilter(oneResult.Name)
        status = "SKIP";
    else
        status = "INC";
    end
end

% -------------------------------------------------------------------------
% Diagnostic record access
% -------------------------------------------------------------------------

function field = loggedRecords(results, keyword, nField)
%LOGGEDRECORDS Parse pipe-separated log records into an nRecord-by-nField array.

    field = strings(0, nField);
    if isempty(results)
        return
    end

    pattern = keyword + join(repmat("\|([^|\n\r]*)", 1, nField), "");
    collected = cell(numel(results), 1);
    for k = 1:numel(results)
        text = recordReports(results(k), "DiagnosticLogged");
        if isempty(text)
            collected{k} = strings(0, nField);
            continue
        end
        token = regexp(join(text, newline), pattern, 'tokens');
        row = strings(numel(token), nField);
        for t = 1:numel(token)
            row(t, :) = strip(string(token{t}));
        end
        collected{k} = row;
    end
    field = vertcat(field, collected{:});
end

function text = recordReports(oneResult, event)
%RECORDREPORTS Reports of the diagnostic records of one result for given events.

    text = strings(0, 1);
    details = oneResult.Details;
    if ~isstruct(details) || ~isfield(details, 'DiagnosticRecord')
        return
    end

    record = details.DiagnosticRecord;
    isWanted = false(numel(record), 1);
    report = strings(numel(record), 1);
    for k = 1:numel(record)
        isWanted(k) = any(string(record(k).Event) == event);
        if isWanted(k)
            report(k) = string(record(k).Report);
        end
    end
    text = report(isWanted);
end

function summary = qualificationSummary(oneResult)
%QUALIFICATIONSUMMARY First informative line of the framework diagnostic.

    text = recordReports(oneResult, failureEvents());
    if isempty(text)
        summary = "no qualification record (see the FULL RESULTS entry)";
        return
    end

    candidate = strip(split(text(1), newline));
    candidate = candidate(strlength(candidate) > 0);
    if isempty(candidate)
        summary = "empty qualification report";
    else
        summary = candidate(1);
    end
end

function location = qualificationLocation(oneResult)
%QUALIFICATIONLOCATION File and line of the innermost frame of the failure.

    location = "unknown";
    record = failureRecords(oneResult);
    for k = 1:numel(record)
        stack = record(k).Stack;
        if ~isempty(stack)
            [~, name, extension] = fileparts(stack(1).file);
            location = string(name) + string(extension) + " line " + string(stack(1).line);
            return
        end
    end
end

function diagnostic = qualificationDiagnostic(oneResult)
%QUALIFICATIONDIAGNOSTIC What the test said, or failing that what the framework said.
%   The framework diagnostic carries the actual and expected values, which is
%   what a reader needs when the test supplied no message of its own.

    diagnostic = "(none supplied by the test or the framework)";
    record = failureRecords(oneResult);
    for k = 1:numel(record)
        % An ERRORED test - an uncaught exception rather than a failed
        % qualification - carries no test or framework diagnostic at all. Its
        % record has an Exception property instead, and until this branch
        % existed the report said "(none supplied)" and the reader had to
        % reproduce the error to learn what it was. That cost three separate
        % guessing rounds across the S4 runs, which is two more than the five
        % lines it takes to read the property.
        diagnostic = exceptionDiagnostic(record(k));
        if strlength(diagnostic) > 0
            return
        end
        % BOTH, NOT THE FIRST OF THE TWO. Until this run the test's own
        % message SUPPRESSED the framework's, which is the one carrying the
        % actual and expected values - so a reference test that failed with a
        % careful sentence and no number could not be diagnosed from the
        % report at all. Six of the thirteen failures in the first S6 run were
        % in exactly that state. A diagnostic that replaces the measurement is
        % worse than one that omits the prose.
        spoken = firstNonEmptyDiagnostic(record(k), 'TestDiagnosticResult');
        measured = firstNonEmptyDiagnostic(record(k), 'FrameworkDiagnosticResult');
        if strlength(spoken) > 0 && strlength(measured) > 0
            diagnostic = spoken + newline + "                   " + measured;
            return
        end
        if strlength(spoken) > 0
            diagnostic = spoken;
            return
        end
        if strlength(measured) > 0
            diagnostic = measured;
            return
        end
    end
    if strlength(diagnostic) == 0
        diagnostic = "(none supplied by the test or the framework)";
    end
end

function text = exceptionDiagnostic(oneRecord)
%EXCEPTIONDIAGNOSTIC The message and origin of an uncaught error, if there is one.
%   matlab.unittest records an errored test through a record carrying an
%   MException rather than a diagnostic. The identifier is included because it
%   is what a caller catches on, and the innermost stack frame because "which
%   line" is the first question asked of any error.

    text = "";
    if ~isprop(oneRecord, 'Exception')
        return
    end

    thrown = oneRecord.Exception;
    if isempty(thrown) || ~isa(thrown, 'MException')
        return
    end

    text = string(thrown.message);
    if strlength(string(thrown.identifier)) > 0
        text = string(thrown.identifier) + ": " + text;
    end
    if ~isempty(thrown.stack)
        [~, name, extension] = fileparts(thrown.stack(1).file);
        text = text + " [at " + string(name) + string(extension) + ...
            " line " + string(thrown.stack(1).line) + "]";
    end
    text = strip(join(strip(split(text, newline)), " | "));
end

function text = firstNonEmptyDiagnostic(oneRecord, propertyName)
%FIRSTNONEMPTYDIAGNOSTIC One diagnostic property flattened to a single line.
%   Long framework diagnostics are truncated, because the report is a fixed-width
%   document meant to be read and re-parsed, not a transcript.

    maximumLength = 300;
    text = "";
    if ~isprop(oneRecord, propertyName)
        return
    end

    candidate = string(oneRecord.(propertyName));
    candidate = strip(candidate(:));
    candidate = candidate(strlength(candidate) > 0);
    if isempty(candidate)
        return
    end

    text = strip(join(candidate, " | "));
    if strlength(text) > maximumLength
        text = extractBefore(text, maximumLength) + " ...";
    end
end

function record = failureRecords(oneResult)
%FAILURERECORDS The diagnostic records of one result that report a failure.

    record = [];
    details = oneResult.Details;
    if ~isstruct(details) || ~isfield(details, 'DiagnosticRecord')
        return
    end

    allRecords = details.DiagnosticRecord;
    isWanted = false(numel(allRecords), 1);
    for k = 1:numel(allRecords)
        isWanted(k) = any(string(allRecords(k).Event) == failureEvents());
    end
    record = allRecords(isWanted);
end

function event = failureEvents()
%FAILUREEVENTS The framework events that mark a test as failed or incomplete.
    event = ["VerificationFailed", "AssertionFailed", "AssumptionFailed", ...
        "FatalAssertionFailed", "ExceptionThrown"];
end

% -------------------------------------------------------------------------
% Small formatting helpers
% -------------------------------------------------------------------------

function reportFile = absoluteReportPath(requested)
%ABSOLUTEREPORTPATH Resolve a bare file name against the TOOLBOX ROOT.
%
%   IT RESOLVED AGAINST pwd UNTIL REV. 1.174, AND THAT IS WHY THE USER SPENT
%   THREE REVISIONS LOOKING AT A REPORT FROM v2.1.169. The file was written on
%   every run; it was written wherever the current folder happened to be, while
%   the copy in the toolbox root - the folder anyone looks in - sat there
%   unchanged, current-looking and three revisions old. **A stale artefact is
%   indistinguishable from a fresh one, which is what makes a moving output
%   path worse than a missing one.**
%
%   The toolbox root is the one folder that does not move between sessions, and
%   teardownReferenceSystem has assumed the report lives there since rev. 1.135.
%   An explicit path is still honoured exactly as before, and the resolved path
%   is returned as the second output so a caller never has to infer it.

    if strlength(fileparts(requested)) == 0
        reportFile = string(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            requested));
    else
        reportFile = requested;
    end
end

function label = zoneLabel(timestamp)
%ZONELABEL Time zone name and UTC offset, e.g. "Europe/Berlin, UTC+02:00".
%   The IANA name is used rather than the seasonal abbreviation of the section
%   D.3 example, because the abbreviation depends on the locale database while
%   the name and the offset do not.

    offset = tzoffset(timestamp);
    offset.Format = 'hh:mm';
    if seconds(offset) < 0
        offsetSign = "-";
    else
        offsetSign = "+";
    end
    label = string(timestamp.TimeZone) + ", UTC" + offsetSign + string(abs(offset));
end

function rule = heavyRule()
%HEAVYRULE The 80-column section D.3 rule that opens and closes the report.
    rule = string(repmat('=', 1, ruleWidth()));
end

function reportLine = warningBlock(warningRecord)
%WARNINGBLOCK Which tests raised a MATLAB warning, and what it said.
%   The count is of TESTS THAT WARNED and not of warnings: lastwarn holds only
%   the most recent one, so a test warning three times is listed once, with the
%   third. See WarningRecordingPlugin for why no supported alternative exists.
%
%   A test that asserts a warning consumes it, by registering
%   onCleanup(@() lastwarn('', '')). Suppressing a warning does NOT hide it from
%   lastwarn - verifyWarning and warning('off', ...) both still set it - so
%   consuming is the only thing that distinguishes a claimed warning from an
%   unclaimed one. A name in this list is therefore a test raising a warning
%   nobody asked for, which is either a defect in the code or carelessness in
%   the test, and both are worth reading.

    if isempty(warningRecord)
        reportLine = ["WARNINGS"; "  (none)"];
        return
    end

    entry = strings(2*numel(warningRecord), 1);
    for k = 1:numel(warningRecord)
        label = warningRecord(k).identifier;
        if strlength(label) == 0
            label = "(no identifier)";
        end
        entry(2*k-1) = "  [" + string(k) + "] " + warningRecord(k).name;
        entry(2*k) = "      " + label + " : " + ...
            oneLine(warningRecord(k).message, 240);
    end

    reportLine = ["WARNINGS (" + string(numel(warningRecord)) + ...
        " test(s) raised at least one; the last of each is shown)"; entry];
end

function text = oneLine(text, maximumLength)
%ONELINE Flatten a multi-line message for a fixed-width report.

    text = strip(join(strip(split(string(text), newline)), " | "));
    if strlength(text) > maximumLength
        text = extractBefore(text, maximumLength) + " ...";
    end
end

function text = localCompilerLine(mexState)
%LOCALCOMPILERLINE Which toolchain built the gateway, as a report line.
%   Named in the header because it is the one build variable a reader cannot
%   recover from the artefact otherwise, and because on Windows it is a real
%   choice: MinGW and MSVC differ in the math library behind sin and cos - the
%   IAU 2000A series calls them hundreds of times per epoch - and in the
%   OpenMP runtime. A before-and-after around `mex -setup` is only readable if
%   both reports say which was selected.

    if mexState.compiler == ""
        text = "unknown - no selected C compiler could be interrogated";
        return
    end
    text = mexState.compiler;
    if mexState.built
        text = text + " (selected now; gateway built " + ...
            mexState.buildDate + ")";
    end
end

function reportLine = instrumentBlock(instrument)
%INSTRUMENTBLOCK The two host measurements, in one place, in one file.
%   ONE REPORT PER MACHINE IS THE WHOLE POINT (rev. 1.198). Comparing two
%   machines meant running three commands on each and keeping the files
%   straight; the fields below are the ones that may be compared ACROSS hosts
%   and the block says which they are, because the mistake this project made
%   at rev. 1.191 was comparing raw seconds from two different computers.

    if ~instrument.requested
        reportLine = ["PLATFORM INSTRUMENTS"; ...
            "  (not requested; call with Instruments = true)"];
        return
    end

    reportLine = "PLATFORM INSTRUMENTS";
    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = "  COMPARE ACROSS MACHINES: fileRatio, fileOpenShare, " + ...
        "vectorPerElementRatio,";
    reportLine(end+1, 1) = "  validationShare, callInCpuSteps, mexInCpuSteps, and " + ...
        "the CALLS PER ROTATION";
    reportLine(end+1, 1) = "  column below. NEVER compare the raw seconds: two " + ...
        "machines differ in";
    reportLine(end+1, 1) = "  processor as well as platform, and this project " + ...
        "made exactly that mistake.";
    reportLine(end+1, 1) = "";

    if instrument.probeFailure ~= ""
        reportLine(end+1, 1) = "  PLATFORM PROBE FAILED: " + instrument.probeFailure;
    else
        reportLine = [reportLine; probeRows(instrument.probe)];
    end

    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = sectionRule();
    if instrument.profileFailure ~= ""
        reportLine(end+1, 1) = "HOT-PATH PROFILE FAILED: " + instrument.profileFailure;
    else
        reportLine = [reportLine; instrument.profileText];
    end
end

function reportLine = probeRows(probe)
%PROBEROWS The platform probe, formatted, with the readable fields marked.

    reportLine = "  PLATFORM PROBE (" + probe.platform + ", " + ...
        string(probe.computeThreads) + " compute threads)";
    reportLine(end+1, 1) = "  " + pad("field", 26) + pad("value", 16) + "reads as";
    reportLine(end+1, 1) = "  " + string(repmat('-', 1, 82));

    entry = { ...
        'fileReadHome',    probe.fileReadHome,    's',  'host only'
        'fileReadScratch', probe.fileReadScratch, 's',  'host only'
        'fileRatio',       probe.fileRatio,       '-',  'COMPARE - above 1: tree costs more'
        'fileOpenOnly',    probe.fileOpenOnly,    's',  'host only'
        'fileOpenShare',   probe.fileOpenShare,   '-',  'COMPARE - near 1: opening is the cost'
        'vectorOpSmall',   probe.vectorOpSmall,   's',  'host only'
        'vectorOpLarge',   probe.vectorOpLarge,   's',  'host only'
        'vectorPerElement', probe.vectorPerElementRatio, '-', 'COMPARE - above 1: memory limits'
        'cpuScalarStep',   probe.cpuScalarStep,   'us', 'host only - the machine speed unit'
        'callOverhead',    probe.callOverhead,    'us', 'host only'
        'mexOverhead',     probe.mexOverhead,     'us', 'host only'
        'callInCpuSteps',  probe.callInCpuSteps,  '-',  'COMPARE - a call in machine units'
        'mexInCpuSteps',   probe.mexInCpuSteps,   '-',  'COMPARE - gateway call, same units'
        'callBare',        probe.callBare,        'us', 'host only'
        'callValidated',   probe.callValidated,   'us', 'host only'
        'validationShare', probe.validationShare, '-',  'COMPARE - share that is validation'};

    for k = 1:size(entry, 1)
        reportLine(end+1, 1) = "  " + pad(string(entry{k, 1}), 26) + ...
            pad(sprintf('%.6g %s', entry{k, 2}, entry{k, 3}), 16) + ...
            string(entry{k, 4}); %#ok<AGROW>
    end

    reportLine(end+1, 1) = "";
    reportLine(end+1, 1) = "  PROBE | platform | " + probe.platform;
    reportLine(end+1, 1) = "  PROBE | computeThreads | " + ...
        string(probe.computeThreads);
    for k = 1:size(entry, 1)
        reportLine(end+1, 1) = "  PROBE | " + string(entry{k, 1}) + " | " + ...
            sprintf('%.9e', entry{k, 2}); %#ok<AGROW>
    end
end

function rule = sectionRule()
%SECTIONRULE The 80-column rule between report sections.
    rule = string(repmat('-', 1, ruleWidth()));
end

function width = ruleWidth()
%RULEWIDTH The column at which the section D.3 report is ruled and wrapped.
%   One number, so a wrapped field cannot outrun the rule above it.
    width = 80;
end
