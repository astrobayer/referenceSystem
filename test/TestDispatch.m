classdef TestDispatch < matlab.unittest.TestCase
%TESTDISPATCH Layer L6 test suite — namespace integrity, layering, provenance.
%
%   At S0 this class holds the toolbox-wide static checks: the two namespace
%   contract tests of handover section C.5, the path-misconfiguration guard of
%   rule 1, the layering scan of section D.1 and the provenance scan of the same
%   section. The dispatcher convertCoordinates is added by P15.
%
%   These tests are the reason the class lives outside +referenceSystem and never
%   imports it: they must see the package exactly as a user does. An import would
%   make a function that was accidentally left out of the namespace resolve
%   anyway, which is precisely the defect being tested for.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    properties (Access = private)
        % THE SUITE, READ ONCE. matlab.unittest builds a fresh TestCase for
        % every test method, so an instrument that reads the suite has nowhere
        % to put the result - and four of them do. Before session S7 the ten
        % test classes, 9136 lines, were read five times and fully parsed
        % twice, at 0.552 s and 0.595 s for the two coverage instruments alone.
        % A TestClassSetup property is the framework's own answer: assigned
        % once for the class and visible to every test in it.
        SuiteSource
        CategoryCoverageMap
    end

    methods (TestClassSetup)

        function readTheSuiteOnce(testCase)
            %READTHESUITEONCE Parse the test classes for every instrument that needs them.
            %   THIS RUNS BEFORE EVERY TEST IN THE CLASS, INCLUDING THE ONES
            %   THAT DO NOT NEED IT, and a failure here fails all of
            %   TestDispatch rather than the four provenance tests. That is the
            %   price of the property and it is worth paying: it is the same
            %   code that ran twice before, so the failure surface is unchanged
            %   in kind, and if the parse is broken then every provenance
            %   verdict is meaningless anyway.
            file = testCase.testFiles();
            testCase.assertNotEmpty(file, 'No test classes found beside this one.');

            source = struct('className', {}, 'fileName', {}, 'line', {});
            for k = 1:numel(file)
                source(k).fileName = string(file(k).name); %#ok<AGROW>
                source(k).className = erase(string(file(k).name), ".m"); %#ok<AGROW>
                source(k).line = split(string(fileread(fullfile( ...
                    file(k).folder, file(k).name))), newline); %#ok<AGROW>
            end
            testCase.SuiteSource = source;
            testCase.CategoryCoverageMap = testCase.categoryCoverage();
        end

    end

    methods (Test, TestTags = {'contract'})

        function setupReferenceSystem_contract_staleCheckSeesTheTopOfMex(testCase)
            % REV. 1.95. The staleness check read only 'mex/**/*.c', and the
            % files that ever change - mexGateway.c, rsCore.c, rsCheb.c - live
            % at the TOP of mex/. sofa/ and iers/ are vendored and frozen, so
            % if ** skips the top level the maximum timestamp is pinned to
            % files that never move and the check can never fire. Three
            % consecutive sessions changed a top-level source and got no
            % rebuild; each time the symptom was read as an installation
            % problem.
            %
            % The test reads the SOURCE TEXT rather than calling setup,
            % because calling setup would compile the gateway - minutes, and a
            % compiler this machine may not have. What has to hold is that the
            % top level is globbed explicitly and does not depend on how **
            % is interpreted.
            setupText = string(fileread(fullfile(testCase.toolboxRoot(), ...
                'setupReferenceSystem.m')));
            testCase.verifyTrue( ...
                contains(setupText, "referenceSystem.mexSourceDigest(toolboxRoot)"), ...
                ['The rebuild check must glob the top of mex/ explicitly. ', ...
                'Relying on ** to span zero folder levels is what hid three ', ...
                'changes to mexGateway.c and rsCore.c.']);
            testCase.verifyTrue(contains(setupText, "mexGateway.sources"), ...
                'The manifest written by buildMex is what the digest is compared against.');
        end

        function buildMex_contract_compilesEveryCoreSource(testCase)
            % REV. 1.85. mex/rsCheb.c was added at rev. 1.83, was covered by the
            % gcc harness, and was NOT in buildMex's source list - which named
            % mexGateway.c and rsCore.c one at a time. It would have compiled
            % under gcc forever and been absent from the .mexw64 the toolbox
            % actually calls, and the first symptom would have been an
            % undefined symbol at P19 integration, a long way from the cause.
            %
            % The test reads the FOLDER and the SOURCE TEXT, not the build
            % report, so it holds on a machine with no compiler and it fails
            % if someone reverts the glob to a list of names.
            mexFolder = fullfile(testCase.toolboxRoot(), 'mex');
            coreEntry = dir(fullfile(mexFolder, '*.c'));
            testCase.assertNotEmpty(coreEntry, 'mex/ contains no .c files.');

            buildText = string(fileread(fullfile(testCase.packageFolder(), ...
                'buildMex.m')));
            testCase.verifyTrue(contains(buildText, "dir(fullfile(mexFolder, '*.c'))"), ...
                ['buildMex must glob the top of mex/ rather than name its ', ...
                'sources, or a new core file will be built by gcc and left ', ...
                'out of the MEX binary.']);

            % And every file that glob will pick up has to be a real core
            % source, not a stray: a test .c or a scratch .c dropped in mex/
            % would be compiled into the gateway without anyone deciding to.
            expected = ["mexGateway.c"; "rsCore.c"; "rsCheb.c"; "rsApi.c"];
            found = sort(string({coreEntry.name})');
            testCase.verifyEqual(found, sort(expected), ...
                ['The top of mex/ holds a file the build will compile that ', ...
                'this test does not know about. Add it here deliberately or ', ...
                'move it out of mex/.']);
        end

        function mexSourceDigest_contract_changesWithContentNotWithTime(testCase)
            % REV. 1.100. THE PROPERTY THE TIMESTAMP CHECK DID NOT HAVE.
            % Three revisions shipped a changed C source and none rebuilt,
            % because a ZIP stores naive local time and the archive was built
            % on a UTC machine and unpacked on a UTC+2 one. Touching a file
            % must NOT change the digest; editing one byte MUST.
            root = testCase.toolboxRoot();
            first = referenceSystem.mexSourceDigest(root);
            testCase.verifyGreaterThanOrEqual(first, 0);
            testCase.verifyEqual(referenceSystem.mexSourceDigest(root), first, ...
                'The digest must be a function of content alone.');

            scratch = fullfile(tempname(), 'mex');
            cleanup = onCleanup(@() rmdir(fileparts(scratch), 's'));
            mkdir(scratch);
            source = fullfile(scratch, 'aFile.c');
            fileId = fopen(source, 'w');
            fprintf(fileId, 'int a = 1;\n');
            fclose(fileId);
            base = referenceSystem.mexSourceDigest(fileparts(scratch));

            % Touch: same bytes, new modification time. The old check would
            % have fired on this and it must not.
            pause(0.01);
            fileId = fopen(source, 'w');
            fprintf(fileId, 'int a = 1;\n');
            fclose(fileId);
            testCase.verifyEqual(referenceSystem.mexSourceDigest( ...
                fileparts(scratch)), base, ...
                'Rewriting identical bytes must not change the digest.');

            % One byte different.
            fileId = fopen(source, 'w');
            fprintf(fileId, 'int a = 2;\n');
            fclose(fileId);
            testCase.verifyNotEqual(referenceSystem.mexSourceDigest( ...
                fileparts(scratch)), base, ...
                'A one-byte edit must change the digest.');

            % A new file, which is how rev. 1.99 shipped rsApi.c.
            fileId = fopen(fullfile(scratch, 'bFile.h'), 'w');
            fprintf(fileId, '#define B 1\n');
            fclose(fileId);
            testCase.verifyNotEqual(referenceSystem.mexSourceDigest( ...
                fileparts(scratch)), base, ...
                'Adding a source must change the digest.');
        end

        function namespace_contract_packageResolvesUniquely(testCase)
            % Section C.5 rule 0: nothing else on the path may answer to the name
            % referenceSystem. The package must also actually be reachable, which
            % is asserted through the function every later test needs first.
            toolboxRoot = testCase.toolboxRoot();
            matches = TestDispatch.whichAll('referenceSystem');
            foreign = matches(~contains(matches, toolboxRoot));

            testCase.verifyEmpty(foreign, ...
                "The name referenceSystem also resolves outside this toolbox: " + ...
                TestDispatch.describeList(string(foreign)));
            % which, not exist: a package function is invisible to exist because
            % the package folder is not on the path (section C.5 rule 9).
            testCase.verifyNotEmpty(which('referenceSystem.toolboxVersion'), ...
                'The +referenceSystem package is not reachable from the MATLAB path.');
        end

        function namespace_contract_noBaseMatlabCollision(testCase)
            % Section C.5 rule 3: an exported name that also names a base MATLAB
            % function is a hazard for the documented import referenceSystem.*
            % workflow, and on a case-insensitive filesystem two names differing
            % only in case are one name. Every exported name is checked against
            % which(name, '-all').
            %
            % Only *path-reachable* matches count. which also reports methods and
            % functions that live inside +namespace or @class folders; those are
            % not on the path, cannot be called unqualified and therefore cannot
            % collide with anything (measured rev. 1.33: runTestSuite is reported
            % against a private method of matlab.unittest.TestRunner).
            toolboxRoot = testCase.toolboxRoot();
            exportedName = [testCase.exportedNames(); testCase.globalNames()];

            testCase.assertNotEmpty(exportedName, 'The package exports no functions.');

            isColliding = false(numel(exportedName), 1);
            collidingWith = strings(numel(exportedName), 1);
            for k = 1:numel(exportedName)
                matches = string(TestDispatch.whichAll(char(exportedName(k))));
                foreign = matches(~contains(matches, toolboxRoot));
                foreign = foreign(TestDispatch.isPathReachable(foreign));
                isColliding(k) = ~isempty(foreign);
                if isColliding(k)
                    collidingWith(k) = foreign(1);
                end
            end

            testCase.verifyFalse(any(isColliding), ...
                "Exported names collide with base MATLAB: " + ...
                TestDispatch.describeList( ...
                    exportedName(isColliding)+" <- "+collidingWith(isColliding)));
        end

        function namespace_contract_packageFolderNotOnPath(testCase)
            % Section C.5 rule 1: only the distribution folder goes on the path.
            % Adding +referenceSystem itself makes every function visible both
            % qualified and unqualified and reintroduces every shadowing problem
            % the namespace was adopted to remove.
            packageFolder = fullfile(testCase.toolboxRoot(), '+referenceSystem');
            pathEntry = split(string(path()), pathsep);

            testCase.verifyFalse(any(pathEntry == string(packageFolder)), ...
                ['The +referenceSystem folder is on the MATLAB path. ', ...
                'Remove it and add the parent folder instead.']);
        end

        function runTestSuite_contract_reportIsWrittenAndWellFormed(testCase)
            % Seam contract S0 item 1: the harness must produce a valid section
            % D.3 report before the toolbox is populated. Running the 'layering'
            % tag alone keeps this test cheap and free of recursion into itself.
            reportFile = fullfile(tempdir, "referenceSystem_seamCheck.txt");
            removeFile = onCleanup(@() TestDispatch.deleteIfPresent(reportFile));

            % Instruments = false, and rev. 1.198 is why: the platform
            % instruments were added to runTestSuite so one report answers
            % everything, and this NESTED run would then profile the hot path
            % a second time inside a suite that is already profiling it -
            % seconds spent measuring the measurement. The section they write
            % is asserted below from the OUTER run's own report, not this one.
            [results, writtenTo] = referenceSystem.runTestSuite(Tags="layering", ...
                Output=reportFile, Instruments=false);

            testCase.verifyEqual(string(writtenTo), reportFile);
            testCase.verifyTrue(isfile(reportFile));
            testCase.verifyClass(results, 'matlab.unittest.TestResult');

            reportLine = split(string(fileread(reportFile)), newline);
            % NOTES ADDED AT REV. 1.167, AND ITS ABSENCE IS WHY IT IS HERE.
            % Two revisions logged records into a section that did not exist
            % and recorded the gap as closed; this list is the one instrument
            % that could have said otherwise, and it did not name the section
            % because the section had never been written down anywhere.
            for section = ["SUMMARY", "BENCHMARKS", "CONVERGENCE", "NOTES", ...
                    "FAILURES", "INTENTIONALLY SKIPPED", ...
                    "FILTERED - AN ASSUMPTION DID NOT HOLD", ...
                    "WARNINGS", "FULL RESULTS", "PLATFORM INSTRUMENTS"]
                testCase.verifyTrue(any(startsWith(reportLine, section)), ...
                    "The report has no " + section + " section.");
            end
            % Rev. 1.203: a filtered test must never sit under the FAILURES
            % banner - the report made its own author read a green run as two
            % failures. Rev. 1.204 splits the filtered section again, into the
            % skips the allow-list foresaw and the ones this machine caused,
            % because "assumption was not met" still reads as a defect when it
            % is printed on every run for the life of the toolbox.
            %
            % This nested run has none of the three, so ALL THREE sections must
            % exist and all three must read "(none)": the headings are
            % structure, present whatever the run contained.
            for section = ["FAILURES", "INTENTIONALLY SKIPPED", ...
                    "FILTERED - AN ASSUMPTION DID NOT HOLD"]
                headingAt = find(startsWith(reportLine, section), 1);
                testCase.verifyEqual(strtrim(reportLine(headingAt + 1)), "(none)", ...
                    "An empty " + section + " section must say so.");
            end
            % The summary must account for the two kinds separately, or the
            % counts cannot distinguish a designed skip from a new one.
            summaryAt = find(startsWith(reportLine, "SUMMARY"), 1);
            testCase.verifyTrue(contains(reportLine(summaryAt + 1), "Skipped"), ...
                'The summary must count the intentional skips separately.');
            testCase.verifyTrue(any(startsWith(reportLine, "Version")), ...
                'The header must state the version, and so the D107 revision.');
            testCase.verifyTrue(any(startsWith(reportLine, "Generated")));
            testCase.verifyTrue(any(startsWith(reportLine, "MEX")));
            % Rev. 1.199: the toolchain is a build variable, and a timing
            % comparison that does not record it compares two unknowns.
            testCase.verifyTrue(any(startsWith(reportLine, "Compiler")), ...
                'The header must name the compiler the gateway was built with.');
            testCase.verifyTrue(any(startsWith(reportLine, "Leap sec")));
        end

        function runTestSuite_contract_theIntentionalSkipListIsNotStale(testCase)
            % AN ALLOW-LIST IS A CLAIM ABOUT NAMES, AND NAMES GET RENAMED.
            % Every entry in intendedFilterCatalogue suppresses one test's INC
            % label for the life of the toolbox. Rename that test and the entry
            % stops matching - silently, because a name that matches nothing
            % looks exactly like a name that matches something not filtered
            % today. The report would then show an unexplained filtered test
            % again, which is precisely the defect rev. 1.204 exists to remove,
            % reintroduced by an edit nobody would connect to it.
            %
            % Checked statically and deliberately so: building the whole suite
            % here would re-run every constructor, and what is asserted is a
            % spelling rather than a behaviour.
            runnerText = string(fileread(which('referenceSystem.runTestSuite')));
            catalogueText = extractBetween(runnerText, ...
                "function catalogue = intendedFilterCatalogue()", "reason = [");
            testCase.assertNotEmpty(catalogueText, ...
                ['The intentional-skip catalogue was not found in ', ...
                'runTestSuite; this test is stale, not the list.']);

            listed = TestDispatch.capturedNames(catalogueText(1), '"(Test\w+/\w+)"');
            testCase.verifyNotEmpty(listed, ...
                ['The catalogue names no test at all. An empty allow-list is ', ...
                'not wrong, but it is never what an edit intended.']);

            for k = 1:numel(listed)
                part = split(listed(k), "/");
                classFile = fullfile(testCase.toolboxRoot(), 'test', part(1) + ".m");
                testCase.assertTrue(isfile(classFile), ...
                    "The allow-list names class " + part(1) + ...
                    ", which is not in the test folder.");
                testCase.verifyTrue(contains(string(fileread(classFile)), ...
                    "function " + part(2) + "("), ...
                    "The allow-list names " + listed(k) + ", which no longer " + ...
                    "exists. Update intendedFilterCatalogue in runTestSuite.");
            end
        end

        function runTestSuite_contract_aNamedCapabilityIsOneTheTestProbes(testCase)
            % D117 PUT A SECOND STATEMENT OF THE SAME FACT IN TWO FILES, AND
            % THIS IS THE CHECK THAT KEEPS THEM EQUAL. A conditional row in
            % intendedFilterCatalogue excuses a skip only while the symbol it
            % names is absent, and the symbol is the one the test's own
            % assumeTrue probes. Change the entry point a test probes - swap
            % cspice_spkezr for cspice_spkgeo, say - and the catalogue would
            % go on answering about a symbol nobody asks for: absent on every
            % machine, so the row would excuse the skip FOREVER, including on
            % the one machine where the test could have run. That is the exact
            % failure D117 was written to prevent, arriving through the back
            % door of an unrelated edit.
            %
            % Static for the same reason as the staleness check beside it:
            % what is asserted is a spelling, and building the suite here
            % would re-run every constructor to learn it.
            runnerText = string(fileread(which('referenceSystem.runTestSuite')));
            catalogueText = extractBetween(runnerText, ...
                "function catalogue = intendedFilterCatalogue()", "reason = [");
            testCase.assertNotEmpty(catalogueText, ...
                ['The intentional-skip catalogue was not found in ', ...
                'runTestSuite; this test is stale, not the list.']);

            listed = TestDispatch.capturedNames(catalogueText(1), '"(Test\w+/\w+)"');
            symbol = TestDispatch.capturedNames(catalogueText(1), '"(cspice_\w+)"');
            if isempty(symbol)
                return    % no conditional row; nothing to hold to anything.
            end

            % Every symbol the catalogue names must be probed by at least one
            % of the classes it lists. The pairing is deliberately NOT checked
            % row by row: the catalogue's own comment records which helper
            % serves which test, and asserting the mapping here would be a
            % third copy of it.
            probed = strings(0, 1);
            for k = 1:numel(listed)
                part = split(listed(k), "/");
                classFile = fullfile(testCase.toolboxRoot(), 'test', part(1) + ".m");
                if isfile(classFile)
                    found = regexp(string(fileread(classFile)), ...
                        'cspice_\w+', 'match');
                    probed = [probed; unique(string(found(:)))]; %#ok<AGROW>
                end
            end
            probed = unique(probed);

            for k = 1:numel(symbol)
                testCase.verifyTrue(any(probed == symbol(k)), ...
                    "The allow-list makes a skip conditional on " + ...
                    symbol(k) + ", which no listed test class probes. A " + ...
                    "symbol nobody asks for is absent everywhere, so the " + ...
                    "row would excuse its test on every machine.");
            end
        end

        function setupReferenceSystem_contract_configuresAndReportsThePath(testCase)
            % Section C.10: setup is the documented way in, so it is tested like
            % any other entry point. The path is restored afterwards, because a
            % test that leaves the session changed is a defect of its own.
            originalPath = path();
            restorePath = onCleanup(@() path(originalPath));

            status = setupReferenceSystem(TestDispatch.setupOptionsForTesting{:});

            testCase.verifyClass(status, 'struct');
            testCase.verifySize(status, [1 1]);
            testCase.verifyEqual(sort(string(fieldnames(status))), ...
                sort(["toolboxRoot"; "version"; "matlabRelease"; "pathAdded"; ...
                "pathSaved"; "removedFromPath"; "unlistedFiles"; "dataFolder"; ...
                "eopSources"; "kernels"; "toolkit"; "fetch"; "mex"; ...
                "leapSecondTable"; "documentation"; "build"; "ready"]));
            testCase.verifyEmpty(status.unlistedFiles, ...
                "Files left in the package by an older version: " + ...
                TestDispatch.describeList(status.unlistedFiles));
            testCase.verifyTrue(status.ready);
            testCase.verifyFalse(status.pathSaved, ...
                ['Setup saved the path although Save=false was passed. Since ', ...
                'rev. 1.204 saving is the DEFAULT, so this assertion now ', ...
                'guards the opt-out rather than the default.']);
            testCase.verifyEqual(status.toolboxRoot, string(testCase.toolboxRoot()));
            testCase.verifyEqual(status.version, ...
                referenceSystem.toolboxVersion().version);
        end

        function dataFolder_contract_queryDefaultsBesideThePackageAndCreatesIt(testCase)
            % D119: WITHOUT A STORED PREFERENCE THE ANSWER IS data/ BESIDE THE
            % PACKAGE, which is what ships and what every install before this
            % revision hardcoded. The folder is created on query deliberately:
            % every caller is about to read or write in it, and returning a
            % path that does not exist moves the mkdir into each of them.
            restorePreference = TestDispatch.preferenceRestorer();  %#ok<NASGU>
            if ispref('referenceSystem', 'dataFolder')
                rmpref('referenceSystem', 'dataFolder');
            end

            folder = referenceSystem.dataFolder();

            expected = what(char(fullfile(testCase.toolboxRoot(), 'data')));
            testCase.assertNotEmpty(expected, ...
                'The default data folder did not resolve after the query.');
            testCase.verifyEqual(folder, string(expected(1).path), ...
                'A query without a preference must answer data/ beside the package.');
            testCase.verifyTrue(isfolder(folder), ...
                'dataFolder returned a path it did not create.');
        end

        function dataFolder_contract_setPersistsAndResetRestoresTheDefault(testCase)
            % THE THREE SHAPES ARE ONE CONTRACT AND ARE TESTED AS ONE, because
            % a setter without a reset is a trap rather than a setting: the
            % shipped behaviour would be unreachable once a preference existed.
            % shLowLevel.dataFolder in shAnalysis has the same three, and the
            % two toolboxes are meant to feel identical here.
            restorePreference = TestDispatch.preferenceRestorer();  %#ok<NASGU>

            wanted = fullfile(tempname(), "rsPreferredData");
            cleanupFolder = onCleanup(@() TestDispatch.removeIfPresent(wanted)); %#ok<NASGU>

            stored = referenceSystem.dataFolder(wanted);
            resolved = what(char(wanted));
            testCase.assertNotEmpty(resolved, ...
                "dataFolder did not create the folder it was given: " + wanted);
            testCase.verifyEqual(stored, string(resolved(1).path), ...
                'A set must return the resolved folder it stored.');
            testCase.verifyEqual(referenceSystem.dataFolder(), stored, ...
                'A set did not persist: the next query gave a different answer.');

            afterReset = referenceSystem.dataFolder("reset");
            testCase.verifyFalse(ispref('referenceSystem', 'dataFolder'), ...
                '"reset" left the preference in place.');
            testCase.verifyNotEqual(afterReset, stored, ...
                '"reset" returned the folder it was supposed to discard.');
        end

        function dataFolder_contract_isTheOneAuthorityBothDownloadersResolve(testCase)
            % D119's WHOLE POINT. downloadEop and downloadKernels each carried
            % a private localDefaultCache composing data/ from their own
            % mfilename, so the toolbox held two answers to one question and a
            % caller who moved one was surprised by the other.
            %
            % CHECKED STATICALLY, AND THE REASON IS WORTH WRITING DOWN. No
            % public surface reveals the resolved default without a network
            % call: "list" returns before CacheDir is read, "verify" issues a
            % HEAD per row, and "download" is 660 MB. A test that provoked a
            % transfer to observe a path would be network-dependent and would
            % pass vacuously on any machine that could not reach NAIF - the
            % defect D116's second allow-list row exists to record. What is
            % asserted here is a spelling, so it is read as one.
            for name = ["downloadKernels", "downloadEop"]
                source = string(fileread(which("referenceSystem." + name)));
                testCase.verifyTrue(contains(source, ...
                    "referenceSystem.dataFolder()"), ...
                    name + " no longer resolves through referenceSystem." + ...
                    "dataFolder; the second copy of the location is back.");
                testCase.verifyFalse(contains(source, ...
                    "fileparts(mfilename('fullpath'))), 'data')"), ...
                    name + " composes data/ from its own mfilename again. " + ...
                    "D119 deleted that copy; it must not return.");
            end
        end

        function dataFolder_contract_refusesAPathThatIsAnExistingFile(testCase)
            % A PATH THAT IS ALREADY A FILE IS REFUSED RATHER THAN WORKED
            % AROUND. mkdir would otherwise fail later, inside a transfer, and
            % report a kernel when the defect is in the argument.
            restorePreference = TestDispatch.preferenceRestorer();  %#ok<NASGU>

            occupied = [tempname() '.txt'];
            fileId = fopen(occupied, 'w');
            testCase.assertNotEqual(fileId, -1, 'Could not create the probe file.');
            fclose(fileId);
            cleanupFile = onCleanup(@() delete(occupied)); %#ok<NASGU>

            testCase.verifyError(@() referenceSystem.dataFolder(occupied), ...
                'referenceSystem:dataFolder:pathIsAFile', ...
                'A file was accepted as a data folder.');
        end

        function setupReferenceSystem_contract_dataFolderIsResolvedBeforeTheFetch(testCase)
            % D118: THE OPTION IS ONLY WORTH ANYTHING IF IT IS RESOLVED BEFORE
            % ANYTHING IS DOWNLOADED. Resolving it afterwards, or reporting it
            % without using it, would look identical in the status struct and
            % would put 660 MB in the wrong place. Fetch is "none" here, so
            % what is asserted is the RESOLUTION and the folder creation; the
            % ordering is guarded structurally by the fact that both downloads
            % receive the folder as an argument and cannot pick another.
            originalPath = path();
            restorePath = onCleanup(@() path(originalPath));

            wanted = fullfile(tempname(), "rsData");
            cleanupFolder = onCleanup(@() TestDispatch.removeIfPresent(wanted));

            status = setupReferenceSystem(TestDispatch.setupOptionsForTesting{:}, ...
                'DataFolder', wanted);

            testCase.verifyTrue(isfolder(wanted), ...
                "Setup did not create the DataFolder it was given: " + wanted);

            % ABSOLUTE, AND COMPARED AFTER what() HAS SEEN BOTH SIDES. A
            % verbatim string comparison would fail on macOS, where tempname
            % returns /var/... and the resolved path is /private/var/...; the
            % assertion is about the folder, not about its spelling.
            resolved = what(char(wanted));
            testCase.assertNotEmpty(resolved, ...
                "The created folder did not resolve: " + wanted);
            testCase.verifyEqual(status.dataFolder, string(resolved(1).path), ...
                ['status.dataFolder must be the resolved DataFolder, not the ', ...
                'default and not the string as it was passed in.']);

            testCase.verifyNotEqual(status.dataFolder, ...
                string(fullfile(testCase.toolboxRoot(), 'data')), ...
                'DataFolder was accepted and then ignored in favour of data/.');
        end

        function setupReferenceSystem_contract_dataFolderDefaultsToTheToolboxData(testCase)
            % D113's idiom, asserted on the branch that keeps the old
            % behaviour: an OMITTED DataFolder is not the same argument as one
            % naming the default, and the omission must still land on
            % <toolboxRoot>/data. Without this the previous test would pass
            % against an implementation that had quietly moved the default.
            %
            % D119 GAVE "THE DEFAULT" TWO MEANINGS AND THIS TEST NOW PINS BOTH.
            % With a stored preference the omission lands on the PREFERENCE -
            % otherwise a user who moved their data and then ran setup with no
            % arguments would fetch 700 MB back into the toolbox tree. Without
            % one it still lands on <toolboxRoot>/data. Run 95 failed here
            % against a real preference, which is the collision worth pinning
            % rather than the accident it looked like.
            originalPath = path();
            restorePath = onCleanup(@() path(originalPath));
            restorePreference = TestDispatch.preferenceRestorer(); %#ok<NASGU>

            wanted = fullfile(tempname(), "rsPreferredDefault");
            cleanupFolder = onCleanup(@() TestDispatch.removeIfPresent(wanted)); %#ok<NASGU>
            preferred = referenceSystem.dataFolder(wanted);
            status = setupReferenceSystem(TestDispatch.setupOptionsForTesting{:});
            testCase.verifyEqual(status.dataFolder, preferred, ...
                ['An omitted DataFolder must follow a stored preference, ', ...
                'or setup fetches into the toolbox tree behind the user.']);

            referenceSystem.dataFolder("reset");
            status = setupReferenceSystem(TestDispatch.setupOptionsForTesting{:});
            expected = what(char(fullfile(testCase.toolboxRoot(), 'data')));
            if isempty(expected)
                testCase.verifyEqual(status.dataFolder, ...
                    string(fullfile(testCase.toolboxRoot(), 'data')));
            else
                testCase.verifyEqual(status.dataFolder, string(expected(1).path));
            end
        end

        function setupReferenceSystem_contract_dataFolderRefusesAnExistingFile(testCase)
            % A PATH THAT IS ALREADY A FILE FAILS EARLY OR IT FAILS LATE. Late
            % means inside a transfer, reported as whichever download happened
            % to go first, and the caller reads about a kernel when the defect
            % is in their argument. Asserted on the identifier, not the text.
            originalPath = path();
            restorePath = onCleanup(@() path(originalPath));

            wanted = string(tempname()) + ".txt";
            fileId = fopen(wanted, 'w');
            testCase.assertNotEqual(fileId, -1, "Could not create " + wanted);
            fclose(fileId);
            cleanupFile = onCleanup(@() delete(wanted));

            testCase.verifyError(@() setupReferenceSystem( ...
                TestDispatch.setupOptionsForTesting{:}, 'DataFolder', wanted), ...
                'referenceSystem:setupReferenceSystem:dataFolderIsAFile');
        end

        function setupReferenceSystem_contract_removesThePackageFolderFromPath(testCase)
            % THIS TEST ASSERTS A WARNING, SO IT CONSUMES IT. The report lists
            % warnings nobody claimed, and an asserted warning is claimed.
            % Registered as a cleanup so it fires on pass, on failure and on a
            % filtered assumption alike. See WarningRecordingPlugin.
            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>
            % Section C.5 rule 1 is the misconfiguration setup exists to undo,
            % so the repair is asserted rather than assumed.
            originalPath = path();
            restorePath = onCleanup(@() path(originalPath));
            previousWarning = warning('off', 'all');
            restoreWarning = onCleanup(@() warning(previousWarning));
            packageFolder = fullfile(testCase.toolboxRoot(), '+referenceSystem');
            addpath(packageFolder);

            % Releases from R2024b on refuse a namespace folder on the path and
            % only warn, so the misconfiguration cannot be created and the repair
            % cannot be exercised. That is a filtered test, not a passing one.
            isOnPath = any(TestDispatch.normalizePath(split(string(path()), pathsep)) == ...
                TestDispatch.normalizePath(packageFolder));
            testCase.assumeTrue(isOnPath, ...
                ['This MATLAB release refuses namespace folders on the path, so ', ...
                'the section C.5 rule 1 misconfiguration cannot be created here.']);

            status = testCase.verifyWarning(@() setupReferenceSystem( ...
                TestDispatch.setupOptionsForTesting{:}), ...
                'referenceSystem:setupReferenceSystem:packageFolderRemoved');

            testCase.verifyTrue(any(TestDispatch.normalizePath( ...
                status.removedFromPath) == TestDispatch.normalizePath(packageFolder)));
            testCase.verifyFalse(any(TestDispatch.normalizePath( ...
                split(string(path()), pathsep)) == TestDispatch.normalizePath(packageFolder)));
        end

        function buildMex_contract_aLockedOutputIsNotBlamedOnOpenMp(testCase)
            % The S4 rebuild failed with ld's "cannot open output file ...
            % Permission denied" because the previous gateway was still mapped.
            % buildMex then RETRIED WITHOUT THE OPENMP FLAGS and, had that
            % retry succeeded, would have shipped a serial binary with a file
            % lock recorded in buildReport.openMpFallback - a wrong answer
            % blamed on a compiler flag, which is revision 1.44's defect in a
            % new costume.
            %
            % A static check, and deliberately so: the classifier is a local
            % function of buildMex and there is no honest way to reach it from
            % here, while creating a genuinely locked file to drive the real
            % path would need a mapped DLL and would be flaky. What can be
            % checked exactly is the ORDER, which is the whole property: the
            % catch must classify before it attributes.
            source = string(fileread(which('referenceSystem.buildMex')));

            testCase.verifyTrue(contains(source, ...
                "referenceSystem:buildMex:outputFileLocked"), ...
                'The locked-output identifier must exist.');

            catchBlock = extractBetween(source, "catch cause", ...
                "fallbackReason = ""the probe accepted");
            testCase.verifyNotEmpty(catchBlock, ...
                'The OpenMP catch block was not found; this test is stale.');
            testCase.verifyTrue(contains(catchBlock(1), "localIsLockedOutput"), ...
                ['The OpenMP catch must classify a locked output BEFORE it ', ...
                'records an OpenMP fallback reason.']);
        end

        function teardownReferenceSystem_contract_reportsWhatStillHoldsTheFolder(testCase)
            % The point of the function is step 5, not steps 1 to 4: it must
            % MEASURE whether the folder is still held rather than infer it
            % from having run without error. Obligation O9. This test asserts
            % that the measurement is reported, not what it says, because what
            % it says is a property of the machine and not of the code.
            previousFolder = pwd;
            previousPath = path();
            restore = onCleanup(@() TestDispatch.restoreEnvironment( ...
                previousFolder, previousPath));

            status = referenceSystem.teardownReferenceSystem();

            % The report file of this very run lives under the toolbox root, so
            % this call reliably exercises the case that broke run 2: a file
            % open inside the tree must be REPORTED and must still be open.
            testCase.verifyClass(status.filesOpenInTree, 'string');
            for name = status.filesOpenInTree
                stillOpen = TestDispatch.openFileIds();
                testCase.verifyNotEmpty(stillOpen, ...
                    'A reported file must not have been closed.');
                testCase.verifyTrue(any(arrayfun(@(id) ...
                    strcmp(fopen(id), name), stillOpen)), ...
                    "teardownReferenceSystem closed a file it did not open: " ...
                    + name);
            end

            testCase.verifyClass(status.mexStillLoaded, 'logical');
            testCase.verifyClass(status.folderIsHeld, 'logical');
            testCase.verifyClass(status.heldBy, 'string');
            testCase.verifyTrue(status.folderIsHeld == ...
                (strlength(status.heldBy) > 0 && status.folderIsHeld), ...
                'A held folder must always be explained.');
            if status.folderIsHeld
                testCase.verifyGreaterThan(strlength(status.heldBy), 0, ...
                    'folderIsHeld true with no explanation is useless.');
            end
        end

        function teardownReferenceSystem_contract_removesTheRootFromThePath(testCase)
            root = string(fileparts(fileparts(which( ...
                'referenceSystem.teardownReferenceSystem'))));
            previousFolder = pwd;
            previousPath = path();
            restore = onCleanup(@() TestDispatch.restoreEnvironment( ...
                previousFolder, previousPath));

            status = referenceSystem.teardownReferenceSystem();

            onPath = any(strcmp(split(string(path()), pathsep), root));
            testCase.verifyFalse(onPath, ...
                'The toolbox root must not remain on the path.');
            testCase.verifyFalse(status.pathSaved, ...
                'savepath must not be called unless Save was asked for.');
        end

        function namespace_contract_siblingCallsAreQualified(testCase)
            % Measured MATLAB behaviour, revision 1.31: a namespace folder is
            % never on the MATLAB path, so an unqualified name inside a package
            % function resolves against the path and against its own file only.
            % A sibling must therefore be called as referenceSystem.<name>, from
            % the main function and from local functions alike. The symptom is a
            % runtime "Unrecognized function" on whichever path first reaches the
            % call, which a green suite need not reach — hence a static scan.
            exportedName = testCase.exportedNames();
            offence = strings(0, 1);

            for k = 1:numel(exportedName)
                offence = [offence; testCase.unqualifiedSiblingNames( ...
                    exportedName(k), exportedName)]; %#ok<AGROW>
            end

            testCase.verifyEmpty(offence, ...
                "Unqualified sibling references inside the package: " + ...
                TestDispatch.describeList(offence));
        end

        function leapSecondTable_contract_isTheOnlyTableInTheToolbox(testCase)
            % Finding M-2. v1 carried three independent hardcoded leap-second
            % tables, all frozen at 2017-01-01 and free to diverge. After P3
            % there is one, in mex/sofa/dat.c, and leapSecondTable is the only file
            % that reads it. The scan covers the package and the distribution
            % root - that is, every file a user's call can reach - and not the
            % test folder, because a test that installs a fictitious override
            % has to contain a table-shaped literal to do its job.
            leapPattern = '4[0-9]{4}\s*,?\s*(1[0-9]|2[0-9]|3[0-9])\s*;';
            candidateFile = [dir(fullfile(testCase.packageFolder(), '*.m')); ...
                dir(fullfile(testCase.toolboxRoot(), '*.m'))];
            offence = strings(0, 1);

            for k = 1:numel(candidateFile)
                fileName = string(candidateFile(k).name);
                if fileName == "leapSecondTable.m"
                    continue
                end
                code = TestDispatch.codeOnly(fileread(fullfile( ...
                    candidateFile(k).folder, fileName)));
                if ~isempty(regexp(code, leapPattern, 'once'))
                    offence(end+1, 1) = fileName; %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(offence, ...
                "Files outside leapSecondTable.m hold a leap-second table: " + ...
                TestDispatch.describeList(offence));
        end

        function leapSecondTable_contract_ownsTheGatewayDatCommand(testCase)
            % Seam contract S1 item 2. leapSecondTable is the single authority only
            % if it is the single caller: any other file reaching the gateway's
            % 'dat' command would bypass a session override and observe a
            % different table, which is finding M-2 in a new place.
            packageFile = dir(fullfile(testCase.packageFolder(), '*.m'));
            offence = strings(0, 1);

            for k = 1:numel(packageFile)
                fileName = string(packageFile(k).name);
                if fileName == "leapSecondTable.m"
                    continue
                end
                code = TestDispatch.codeOnly(fileread(fullfile( ...
                    packageFile(k).folder, fileName)));
                if contains(code, "mexGateway('dat'") || ...
                        contains(code, 'mexGateway("dat"')
                    offence(end+1, 1) = fileName; %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(offence, ...
                "Files other than leapSecondTable.m call the gateway 'dat' command: " + ...
                TestDispatch.describeList(offence));
        end

        function normalizeEpoch_contract_hasNoLeapSecondStubLeft(testCase)
            % Seam contract S1 item 4. P1 was allowed to stub the leap-second
            % query behind a TODO while P3 did not exist yet; P3 had to remove
            % it. A stub that survived the session would be a leap-second-blind
            % normaliser, which is defect C-3 reintroduced, and it would not
            % show up as a failure anywhere else - hence a grep.
            %
            % THE GUARD MOVED WITH THE CODE IT GUARDS, AND IT CAUGHT THE MOVE
            % (run 42, rev. 1.124). D88 put the carry in the package-private
            % carryEpoch so that normalizeEpoch and convertTimeScale reach ONE
            % implementation, and the leap-second consultation went with it -
            % so this grep, which read normalizeEpoch.m alone, stopped seeing
            % the authority and failed. The property it protects was never
            % broken: the behavioural evidence is independent and was green in
            % the same run.
            %
            % IT IS WIDENED RATHER THAN RELOCATED. Reading carryEpoch.m instead
            % of normalizeEpoch.m would restore the letter of the check and
            % lose half of it: normalizeEpoch could then stop delegating
            % altogether and nothing would notice. Both files are read, and the
            % DELEGATION ITSELF is asserted, so the guard now fails on three
            % distinct regressions instead of one - a stub in either file, and
            % a normaliser that no longer reaches the carry at all.
            normalizeCode = TestDispatch.codeOnly(fileread(fullfile( ...
                testCase.packageFolder(), 'normalizeEpoch.m')));
            carryFile = fullfile(testCase.packageFolder(), 'private', ...
                'carryEpoch.m');

            testCase.verifyFalse(contains(upper(normalizeCode), "TODO"), ...
                'normalizeEpoch still carries a TODO stub after P3.');

            testCase.assertTrue(isfile(carryFile), ...
                'The package-private carryEpoch is missing; D88 expects it.');
            carryCode = TestDispatch.codeOnly(fileread(carryFile));

            testCase.verifyFalse(contains(upper(carryCode), "TODO"), ...
                'carryEpoch carries a TODO stub in the leap-second carry.');
            testCase.verifyTrue(contains(carryCode, "referenceSystem.leapSecondTable"), ...
                'carryEpoch does not consult the leap-second authority.');
            testCase.verifyTrue(contains(normalizeCode, "carryEpoch(") || ...
                contains(normalizeCode, "referenceSystem.leapSecondTable"), ...
                ['normalizeEpoch neither consults the leap-second authority ', ...
                'nor delegates to carryEpoch, so it is leap-second blind.']);
        end

        function mexInfo_contract_reportsNotBuiltWithoutError(testCase)
            % Seam contract S0 item 2: mexInfo must answer before P2 builds the
            % gateway. Every field keeps its class and size in both states.
            mexState = referenceSystem.mexInfo();

            testCase.verifyClass(mexState, 'struct');
            testCase.verifySize(mexState, [1 1]);
            testCase.verifyClass(mexState.built, 'logical');
            testCase.verifyClass(mexState.summary, 'string');
            testCase.verifyClass(mexState.leapSecondsSummary, 'string');
            % Rev. 1.199. The field exists in BOTH states and is a string in
            % both, empty when no compiler can be interrogated - the same
            % contract every other field here keeps, and the reason this test
            % exists at the seam rather than after the gateway is built.
            testCase.verifyClass(mexState.compiler, 'string');
            testCase.verifySize(mexState.compiler, [1 1]);
            testCase.verifyGreaterThan(strlength(mexState.summary), 0);
            testCase.verifyGreaterThan(strlength(mexState.leapSecondsSummary), 0);
            testCase.verifyTrue(endsWith(mexState.file, string(mexext())));
        end

    end

    methods (Test, TestTags = {'layering'})

        function toolbox_layering_noFunctionCallsUpward(testCase)
            % Section B.2: a function may call downward only. The layer of each
            % function is read from Contents.m, which is the documented grouping
            % and therefore the single authority; a function missing from it
            % fails here rather than drifting silently.
            layerOfFunction = testCase.layerMap();
            exportedName = testCase.exportedNames();

            if isempty(exportedName)
                testCase.verifyTrue(true, 'No package functions to scan.');
                return
            end

            unlisted = setdiff(exportedName, string(layerOfFunction.keys()));
            testCase.verifyEmpty(unlisted, ...
                "Not grouped by layer in Contents.m: " + ...
                TestDispatch.describeList(unlisted));

            for k = 1:numel(exportedName)
                caller = exportedName(k);
                if ~isKey(layerOfFunction, char(caller))
                    continue
                end
                callerLayer = layerOfFunction(char(caller));
                called = testCase.calledFunctions(caller, exportedName);
                for m = 1:numel(called)
                    if ~isKey(layerOfFunction, char(called(m)))
                        continue
                    end
                    calleeLayer = layerOfFunction(char(called(m)));
                    testCase.verifyLessThanOrEqual(calleeLayer, callerLayer, ...
                        sprintf('%s (L%g) calls %s (L%g), which is upward.', ...
                        caller, callerLayer, called(m), calleeLayer));
                end
            end
        end

    end

    methods (Test, TestTags = {'provenance'})

        function toolbox_provenance_helpTemplateIsFollowed(testCase)
            % Section D.1: every function carries the version tag and the
            % mandatory section C.3 blocks. The generated function reference
            % (D33) parses exactly these headings, so this test is also the
            % guarantee that the generator has a valid input.
            versionInfo = referenceSystem.toolboxVersion();
            helpTag = versionInfo.helpTag;
            versionTag = versionInfo.versionTag;
            mandatorySection = ["INPUT ARGUMENTS", "OUTPUT ARGUMENTS", "METHOD", ...
                "ACCURACY", "ERRORS", "REFERENCES", "EXAMPLE", "KEYWORDS"];
            packageFile = testCase.documentedFiles();

            testCase.assertNotEmpty(packageFile, 'The package contains no .m files.');

            % ONE QUALIFICATION, NOT ONE PER CHECK. Eighty-two files times ten
            % checks is 820 qualifications, each building its own diagnostic
            % string, and run 9 measured this test at 24.6 s - the second
            % slowest in the suite, for a scan that reads 82 files. The
            % offences are accumulated and reported together, which also reads
            % better: a template that has drifted has usually drifted in
            % several files at once, and 820 separate failures bury that.
            offence = strings(0, 1);

            for k = 1:numel(packageFile)
                fileName = string(packageFile(k).name);
                fileText = string(fileread(fullfile(packageFile(k).folder, fileName)));

                % TWO LINES SINCE D103, AND THEY ARE ASSERTED SEPARATELY.
                % Naming the author in full beside the toolbox, the version and
                % the model is 103 columns and section C.1 allows 100, so the
                % footer was split rather than the standard amended. Checking
                % them as one concatenated string would reintroduce the
                % coupling: a file that carried the authorship and had its
                % version line edited would then report as having neither.
                if ~contains(fileText, versionTag)
                    offence(end+1, 1) = fileName + ...
                        " does not carry the toolboxVersion version tag"; %#ok<AGROW>
                end
                if ~contains(fileText, helpTag)
                    offence(end+1, 1) = fileName + ...
                        " does not carry the toolboxVersion authorship tag"; %#ok<AGROW>
                end
                if fileName == "Contents.m"
                    continue
                end

                functionName = erase(fileName, ".m");
                if ~contains(fileText, "%" + upper(functionName) + " ")
                    offence(end+1, 1) = fileName + " has no H1 line of the form %" + ...
                        upper(functionName); %#ok<AGROW>
                end
                % contains(text, patternArray) is an ANY match, not elementwise,
                % so the presence of each section is asked for one at a time.
                present = arrayfun(@(section) contains(fileText, "% " + section), ...
                    mandatorySection);
                absent = mandatorySection(~present);
                if ~isempty(absent)
                    offence(end+1, 1) = fileName + " has no " + ...
                        join(absent, ", ") + " block"; %#ok<AGROW>
                end
            end

            % THE DIAGNOSTIC NAMES THE USUAL CAUSE (rev. 1.85). Twice now a
            % scratch .m file has been left in the distribution root - it is a
            % natural place to put one - and the failure then reads as though a
            % toolbox function had lost its help block. Any file in the root is
            % a global name a user can call, so the rule is right; it is the
            % message that was unhelpful, and obligation O17 applies to a
            % diagnostic that is true but sends the reader to the wrong file.
            testCase.verifyEmpty(offence, "Help template offences: " + ...
                TestDispatch.describeList(offence) + ...
                " | If a file named here is a scratch or measurement script " + ...
                "rather than part of the toolbox, it does not belong in the " + ...
                "package or the distribution root: every .m file in either is " + ...
                "a name the user can call and must follow the section C.3 " + ...
                "template. Move it out of the toolbox tree.");
        end

        function toolbox_provenance_ecefAndEciNameTheRigorousFrame(testCase)
            % Section C.7 discoverability obligation: a function whose name
            % carries the engineering shorthand must state the rigorous frame in
            % its METHOD block, so nobody has to guess which realization is meant.
            packageFile = dir(fullfile(testCase.packageFolder(), '*.m'));

            for k = 1:numel(packageFile)
                fileName = string(packageFile(k).name);
                if ~contains(fileName, "Ecef") && ~contains(fileName, "Eci")
                    continue
                end
                fileText = string(fileread(fullfile(packageFile(k).folder, fileName)));
                testCase.verifyTrue(contains(fileText, "ITRS") && ...
                    contains(fileText, "GCRS"), ...
                    fileName + " names Ecef or Eci but not the rigorous frames.");
            end
        end

    end

    methods (Test, TestTags = {'contract'})

        function buildMex_contract_rejectsAnInvalidOptionWithoutCompiling(testCase)
            % OPEN ITEM B3, AND ONE OF THE TWO EXEMPTIONS THAT WAS WRONG WHEN
            % IT WAS WRITTEN. buildMex was exempted from contract coverage on
            % the grounds that "calling it recompiles 255 sources and takes a
            % minute, so no test may". That is true of a VALID call. An
            % arguments block runs BEFORE the body, so an invalid call costs
            % nothing at all and is exactly a contract test - the exemption
            % confused an expensive success with an expensive rejection.
            %
            % noCategoryExemptionIsStale catches an exemption that HAS BECOME
            % false; nothing caught one that was false the day it was written,
            % which is what this open item was about. The mechanism added
            % alongside this test is noContractExemptionSurvivesAnArgumentsBlock.
            %
            % THE IDENTIFIER IS NOT NAMED AND THE REASON IS DELIBERATE.
            % MATLAB's own validation identifiers are release detail, and this
            % test would then fail on a release change for a reason that has
            % nothing to do with the toolbox. What is asserted is the property
            % the exemption denied: the rejection came from the ARGUMENTS
            % BLOCK, and nothing was compiled.
            caught = false;
            identifier = "";
            started = tic;
            try
                referenceSystem.buildMex('OpenMp', "yes");
            catch exception
                caught = true;
                identifier = string(exception.identifier);
            end
            elapsed = toc(started);

            testCase.verifyTrue(caught, ...
                'buildMex accepted a non-logical OpenMp option.');
            testCase.verifyTrue(contains(identifier, "validation") || ...
                contains(identifier, "validators"), ...
                "The rejection came from " + identifier + ...
                ", not from the arguments block; the body was entered.");
            % A COMPILE OF 255 SOURCES TAKES ABOUT A MINUTE ON EVERY HOST THIS
            % HAS RUN ON. One second is three orders inside that, so this
            % cannot fail on a slow machine and cannot pass on one that built.
            testCase.verifyLessThan(elapsed, 1, sprintf( ...
                'The rejected call took %.3f s; something was compiled.', ...
                elapsed));
        end


        function convertCoordinates_contract_graphDeclaresEveryEdgeTimeKind(testCase)
            % Seam item 2: every edge declares timeKind, and the published
            % graph is what documentation and tests read. An edge with any
            % other value would be routed but never validated.
            adjacency = referenceSystem.convertCoordinates('graph');

            testCase.assertTrue(isstruct(adjacency), 'graph returns a struct.');
            testCase.verifyTrue(all(isfield(adjacency, ...
                {'node', 'edge', 'aliasName', 'aliasTarget', 'realization'})), ...
                'The adjacency is missing a documented field.');

            declared = string({adjacency.edge.timeKind});
            testCase.verifyTrue(all(ismember(declared, ["none", "decimalYear"])), ...
                "An edge declares a timeKind outside {none, decimalYear}: " + ...
                TestDispatch.describeList(unique(declared)));

            called = string({adjacency.edge.functionName});
            isRealization = strcmp(called, "convertItrf");
            testCase.verifyTrue(all(strcmp(declared(isRealization), "decimalYear")), ...
                'A realization edge does not declare decimalYear.');
            testCase.verifyTrue(all(strcmp(declared(~isRealization), "none")), ...
                'A geometry edge declares a time kind it cannot use.');
        end

        function convertCoordinates_contract_everyPublishedEdgeExecutes(testCase)
            % THE SEAM BETWEEN THE TWO AUTHORITIES. buildGraph says which edges
            % exist; applyEdge says how each is called. Nothing but this test
            % keeps them in agreement, and an edge with no execution branch
            % would sit in the published graph raising :unroutableEdge on the
            % first user who routed through it. Every edge is therefore
            % executed once, from the graph rather than from a second list.
            adjacency = referenceSystem.convertCoordinates('graph');
            edgeCount = numel(adjacency.edge);
            testCase.assertGreaterThan(edgeCount, 12, 'The graph lost its edges.');

            for k = 1:edgeCount
                edge = adjacency.edge(k);
                sample = TestDispatch.sampleFor(edge.from);
                argument = TestDispatch.optionsFor(edge);
                try
                    referenceSystem.convertCoordinates(sample, edge.from, ...
                        edge.to, argument{:});
                catch failure
                    testCase.verifyFail(sprintf( ...
                        'Edge %s -> %s (%s) raised %s: %s', edge.from, ...
                        edge.to, edge.functionName, failure.identifier, ...
                        failure.message));
                end
            end
        end

        function convertCoordinates_contract_unknownFrameIsRefused(testCase)
            testCase.verifyError(@() referenceSystem.convertCoordinates( ...
                [1 2 3], "ITRS", "MERCATOR"), ...
                'referenceSystem:convertCoordinates:unknownFrame');
        end

        function convertCoordinates_contract_enuWithoutAnOriginIsRefused(testCase)
            % The option is required by the EDGE, so it is checked before any
            % leg runs rather than by the leg that would have needed it.
            testCase.verifyError(@() referenceSystem.convertCoordinates( ...
                TestDispatch.Station, "ITRS", "ENU"), ...
                'referenceSystem:convertCoordinates:missingOption');
        end

        function convertCoordinates_contract_utmWithoutAZoneIsRefused(testCase)
            testCase.verifyError(@() referenceSystem.convertCoordinates( ...
                [400000 5000000], "UTM", "GEODETIC"), ...
                'referenceSystem:convertCoordinates:missingOption');
        end

        function convertCoordinates_contract_theTwoComponentsAreNotJoined(testCase)
            % The deliberate disconnection. If this test ever starts passing a
            % path, the ITRF2014 -> GEODETIC -> ITRF2020 reinterpretation is
            % reachable again and D29 is defeated from inside the graph.
            testCase.verifyError(@() referenceSystem.convertCoordinates( ...
                TestDispatch.Station, "ITRF2014", "GEODETIC", 'Epoch', 2020.0), ...
                'referenceSystem:convertCoordinates:noPath');
        end

        function convertCoordinates_contract_reportsThePathItTook(testCase)
            [~, info] = referenceSystem.convertCoordinates( ...
                TestDispatch.Station, "ITRS", "AZIMUTHELEVATION", ...
                'Origin', [0.9075712110370513 0.22689280275926285 100]);

            testCase.verifyEqual(info.path, ...
                ["ITRS", "ENU", "AZIMUTHELEVATION"], 'Chosen path.');
            testCase.verifyEqual(info.edgeFunction, ...
                ["cartesianToEnu", "enuToAzimuthElevation"], 'Legs called.');
            testCase.verifyEqual(info.timeKind, ["none", "none"], ...
                'Both legs are pure geometry.');
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function setupReferenceSystem_diagnostics_warnsWhenTheMexBuildFails(testCase)
            % REV. 1.101. Setup is quiet by default, does not stop on a build
            % failure, and returns ready = 1 because ready means the path is
            % right. So a failed compile produced a struct that looked healthy
            % and the only trace was build.mexReason - a field nobody had a
            % reason to open. Four consecutive test reports were read as
            % evidence about C that was not in the binary.
            %
            % The documentation build already warned; the MEX build, which
            % matters far more, did not. The test reads the source text because
            % provoking a real link failure needs a locked DLL, which cannot be
            % arranged portably - what has to hold is that the branch warns.
            setupText = string(fileread(fullfile(testCase.toolboxRoot(), ...
                'setupReferenceSystem.m')));
            failureBlock = extractAfter(setupText, 'build.mexAction = "failed";');
            failureBlock = extractBefore(failureBlock, 'documentationAction');

            testCase.verifyTrue(contains(failureBlock, ...
                "referenceSystem:setupReferenceSystem:mexBuildFailed"), ...
                ['A failed MEX build must warn. Silence here means the ', ...
                'gateway does not match the sources and nothing says so.']);
            testCase.verifyTrue(contains(failureBlock, "build.mexReason"), ...
                'The warning must carry the reason, not just announce failure.');
        end

        function convertCoordinates_diagnostics_realizationPathNeedsAnEpoch(testCase)
            testCase.verifyError(@() referenceSystem.convertCoordinates( ...
                TestDispatch.Station, "ITRF2014", "ITRF2020"), ...
                'referenceSystem:convertCoordinates:timeKindMismatch');
        end

        function convertCoordinates_diagnostics_geometryPathRefusesAnEpoch(testCase)
            % Never silently ignore a supplied epoch (seam item 2). A caller
            % who passes one on a geometry path has misunderstood something,
            % and accepting it would leave them believing otherwise.
            testCase.verifyError(@() referenceSystem.convertCoordinates( ...
                TestDispatch.Station, "ITRS", "GEODETIC", 'Epoch', 2020.0), ...
                'referenceSystem:convertCoordinates:timeKindMismatch');
        end

        function convertCoordinates_diagnostics_celestialEndpointNamesTheCure(testCase)
            % SEAM ITEM 3 ASKS FOR THE TEXT TO BE TESTED, NOT ONLY THE
            % IDENTIFIER. That message is the entire user-facing cost of
            % excluding ITRS<->GCRS from the graph: a user who is told only
            % "unknown frame" has been given the decision without the remedy.
            % verifyError's captured-exception output is `missing` in this
            % release, so the MException is taken from a try/catch instead:
            % the message text is the point of this test (seam item 3) and
            % must be read directly rather than through a qualification.
            failure = MException.empty;
            try
                referenceSystem.convertCoordinates(TestDispatch.Station, ...
                    "ITRS", "GCRS");
            catch caught
                failure = caught;
            end
            testCase.assertNotEmpty(failure, 'No error was raised at all.');
            testCase.verifyEqual(failure.identifier, ...
                'referenceSystem:convertCoordinates:useRotationFunction');

            testCase.verifyTrue(contains(failure.message, "rotationItrsToGcrs"), ...
                "The message must name rotationItrsToGcrs: " + failure.message);
            testCase.verifyTrue(contains(failure.message, "applyRotation"), ...
                "The message must name applyRotation: " + failure.message);
        end

        function convertCoordinates_diagnostics_orbitFrameNamesTheCure(testCase)
            % RSW is refused with the same identifier and its own cure, rather
            % than sitting in the graph as a node nothing can reach.
            % verifyError's captured-exception output is `missing` in this
            % release, so the MException is taken from a try/catch instead:
            % the message text is the point of this test (seam item 3) and
            % must be read directly rather than through a qualification.
            failure = MException.empty;
            try
                referenceSystem.convertCoordinates(TestDispatch.Station, ...
                    "ITRS", "RSW");
            catch caught
                failure = caught;
            end
            testCase.assertNotEmpty(failure, 'No error was raised at all.');
            testCase.verifyEqual(failure.identifier, ...
                'referenceSystem:convertCoordinates:useRotationFunction');

            testCase.verifyTrue(contains(failure.message, "rotationGcrsToRsw"), ...
                "The message must name rotationGcrsToRsw: " + failure.message);
        end

    end

    methods (Test, TestTags = {'reference'})

        function convertCoordinates_reference_geodeticToCartesianLiteral(testCase)
            % Independent literal: the closed-form ellipsoidal formula
            % evaluated in Python on GRS80 for 52 N, 13 E, 100 m.
            %   N = a/sqrt(1 - e2 sin^2 phi)
            %   X = (N+h) cos phi cos lambda, Y = (N+h) cos phi sin lambda,
            %   Z = (N(1-e2)+h) sin phi
            expected = [3834167.6730921804, 885187.35515890107, 5002882.1464441];

            actual = referenceSystem.convertCoordinates([52 13 100], ...
                "GEODETIC", "ITRS", 'AngleUnit', "deg");

            % A metre at the surface is 1.6e-7 relative, so this bound is far
            % inside the quantity under test and bounds the formula, not the
            % ellipsoid choice.
            testCase.verifyEqual(actual, expected, 'RelTol', 1e-12);
        end

        function convertCoordinates_reference_sphericalLiteral(testCase)
            % Same point, geocentric spherical, computed from the same Python
            % Cartesian triple: latitude asin(Z/r), longitude atan2(Y,X).
            expected = [51.813143651627236, 13.0, 6365000.2490437841];

            actual = referenceSystem.convertCoordinates([52 13 100], ...
                "GEODETIC", "SPHERICAL", 'AngleUnit', "deg");

            testCase.verifyEqual(actual, expected, 'RelTol', 1e-12);
        end

    end

    methods (Test, TestTags = {'precision'})

        function convertCoordinates_precision_geometryRoundTrip(testCase)
            % The origin is NOT axis aligned and the target is offset in all
            % three components, so no expected value is exactly zero
            % (obligation O12) and every axis is exercised.
            origin = [0.9075712110370513 0.22689280275926285 100];
            expected = TestDispatch.Station + [1234.5 -2345.6 3456.7];

            enu = referenceSystem.convertCoordinates(expected, "ITRS", "ENU", ...
                'Origin', origin);
            ned = referenceSystem.convertCoordinates(enu, "ENU", "NED");
            actual = referenceSystem.convertCoordinates(ned, "NED", "ITRS", ...
                'Origin', origin);

            % Bound: the residual of two orthogonal rotations and one
            % translation of a 6.4e6 m vector, a few ulp of that magnitude.
            testCase.verifyLessThan(norm(actual - expected), 1e-8);
        end

        function convertCoordinates_precision_realizationRoundTrip(testCase)
            % D68: the inverse is solved, never obtained by negating the
            % parameters, so the round trip closes far below the 1e-3 m the
            % negated form would leave.
            expected = TestDispatch.Station;

            there = referenceSystem.convertCoordinates(expected, "ITRF2020", ...
                "ITRF93", 'Epoch', 2015.5);
            actual = referenceSystem.convertCoordinates(there, "ITRF93", ...
                "ITRF2020", 'Epoch', 2015.5);

            testCase.verifyLessThan(norm(actual - expected), 1e-8);
            testCase.verifyGreaterThan(norm(there - expected), 1e-3, ...
                'ITRF93 carries rotations; a null result means no transform ran.');
        end

    end

    methods (Test, TestTags = {'layering'})

        function convertCoordinates_layering_holdsNoTransformationMathematics(testCase)
            % SEAM ITEM 1, ENFORCED RATHER THAN REVIEWED. A router indexes,
            % compares and searches; it never evaluates a trigonometric
            % function, a root or a power. Those are the operations every
            % transformation in L3 and L4 is built from, so their absence is a
            % narrow but genuine check that the mathematics lives downstairs.
            %
            % What this CANNOT catch is stated so the check is not mistaken
            % for more than it is: a transformation written with + - * / only
            % would pass. The edge-execution test above is what covers that,
            % by proving every leg is a named library call.
            forbidden = ["sin", "cos", "tan", "asin", "acos", "atan", ...
                "atan2", "sqrt", "hypot", "norm", "cross", "dot", "expm", ...
                "deg2rad", "rad2deg"];
            code = TestDispatch.codeOnly(fileread(fullfile( ...
                testCase.packageFolder(), 'convertCoordinates.m')));

            for name = forbidden
                pattern = "(?<![\w.])" + name + "\s*\(";
                testCase.verifyEmpty(regexp(code, pattern, 'once'), ...
                    "convertCoordinates calls " + name + ...
                    ", which is transformation mathematics in a dispatcher.");
            end
            testCase.verifyEmpty(regexp(code, '\.\^|(?<![\w.\)\]])\^', 'once'), ...
                'convertCoordinates raises a power; a router has nothing to raise.');
        end

        function layerFive_layering_quaternionAlgebraIsNotReimplemented(testCase)
            % SEAM ITEM 5: L5 consumes L4b, it does not duplicate it. The
            % signature of an inline Hamilton product is a cross product and a
            % summed inner product in ONE statement - the two halves of
            %   [a0 b0 - av.bv ; a0 bv + b0 av +- av x bv]
            % and they occur together in no other operation in this toolbox.
            % Continuations are joined first, because the product is normally
            % written across two lines.
            %
            % The layer map is read from Contents.m, which is the same single
            % authority the upward-call scan uses (D41).
            layerOfFunction = testCase.layerMap();
            offender = strings(1, 0);

            for name = testCase.exportedNames()'
                if ~isKey(layerOfFunction, char(name)) || ...
                        layerOfFunction(char(name)) ~= 5
                    continue
                end
                code = TestDispatch.codeOnly(fileread(fullfile( ...
                    testCase.packageFolder(), name+".m")));
                statement = split(replace(code, "..." + newline, " "), newline);
                for k = 1:numel(statement)
                    line = statement(k);
                    if ~isempty(regexp(line, '(?<![\w.])cross\s*\(', 'once')) && ...
                            (~isempty(regexp(line, '(?<![\w.])(sum|dot)\s*\(', 'once')) || ...
                            ~isempty(regexp(line, '\.?''\s*\*', 'once')))
                        offender(end+1) = name; %#ok<AGROW>
                        break
                    end
                end
            end

            % A local product is permitted ONLY where a test measures it
            % against the L4b authority, which is what makes it a documented
            % optimisation rather than a second implementation drifting free.
            % integrateAttitude carries exactly that justification in its help
            % and the test it named did not exist until this scan asked for it.
            suiteText = string(fileread(fullfile(fileparts(mfilename('fullpath')), ...
                'TestNavigation.m')));
            uncovered = strings(1, 0);
            for k = 1:numel(offender)
                covered = contains(suiteText, "referenceSystem.multiplyQuaternions") && ...
                    contains(suiteText, offender(k));
                if ~covered
                    uncovered(end+1) = offender(k); %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(uncovered, ...
                "L5 source reimplements the quaternion product with no test " + ...
                "measuring it against referenceSystem.multiplyQuaternions: " + ...
                TestDispatch.describeList(uncovered));
        end

    end

    properties (Constant, Access = private)
        % 52 N, 13 E, 100 m on GRS80, from the closed-form ellipsoidal formula
        % evaluated in Python. One authority: the reference test asserts this
        % same triple, so a change to the ellipsoid moves both together.
        Station = [3834167.6730921804, 885187.35515890107, 5002882.1464441]
        StationGeodetic = [0.9075712110370513, 0.22689280275926285, 100]
    end

    methods (Static, Access = private)

        function sample = sampleFor(node)
            %SAMPLEFOR One valid row of data in the representation of a node.
            %   Used only to drive every published edge once, so the values
            %   need to be plausible rather than meaningful.
            if startsWith(node, "ITRF") || node == "ITRS"
                sample = TestDispatch.Station;
            elseif node == "GEODETIC"
                sample = TestDispatch.StationGeodetic;
            elseif node == "SPHERICAL"
                sample = [0.90418 0.22689 6365000.249];
            elseif node == "ENU"
                sample = [1234.5 -2345.6 3456.7];
            elseif node == "NED"
                sample = [-2345.6 1234.5 -3456.7];
            elseif node == "AZIMUTHELEVATION"
                sample = [1.1 0.4 5000];
            elseif node == "UTM"
                sample = [400000 5762610];
            else
                sample = TestDispatch.Station;
            end
        end

        function argument = optionsFor(edge)
            %OPTIONSFOR The name-value arguments one edge declares it needs.
            %   Read from the edge record rather than from a second table, so
            %   a new requirement is supplied here the moment it is declared.
            argument = {};
            if any(strcmp(edge.requires, "Origin"))
                argument = [argument, {'Origin', TestDispatch.StationGeodetic}];
            end
            if any(strcmp(edge.requires, "Zone"))
                argument = [argument, {'Zone', 33, 'Hemisphere', 1}];
            end
            if strcmp(edge.timeKind, "decimalYear")
                argument = [argument, {'Epoch', 2015.5}];
            end
        end

    end

    methods (Access = private)

        function root = toolboxRoot(~)
            %TOOLBOXROOT Absolute path of the distribution folder.
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function folder = packageFolder(testCase)
            %PACKAGEFOLDER Absolute path of the +referenceSystem folder.
            folder = fullfile(testCase.toolboxRoot(), '+referenceSystem');
        end

        function name = exportedNames(testCase)
            %EXPORTEDNAMES Public function names of the package, without Contents.
            packageFile = dir(fullfile(testCase.packageFolder(), '*.m'));
            fileName = string({packageFile.name});
            name = erase(fileName(fileName ~= "Contents.m"), ".m");
            name = name(:);
        end

        function name = globalNames(testCase)
            %GLOBALNAMES Unqualified names the toolbox installs on the path.
            %   Everything else lives in the package; these are the only names a
            %   user sees without the referenceSystem prefix, so they carry the
            %   whole collision risk (section C.10).
            rootFile = dir(fullfile(testCase.toolboxRoot(), '*.m'));
            name = erase(string({rootFile.name}), ".m");
            name = name(:);
        end

        function fileEntry = documentedFiles(testCase)
            %DOCUMENTEDFILES Every .m file that must follow the section C.3 template.
            fileEntry = [dir(fullfile(testCase.packageFolder(), '*.m')); ...
                dir(fullfile(testCase.toolboxRoot(), '*.m'))];
        end

        function layerOfFunction = layerMap(testCase)
            %LAYERMAP Function name to layer index, parsed from Contents.m.
            %   L4b maps to 3.5: rotation algebra sits below L4, so L4 may call
            %   it while it may call nothing above L0 (decision D34).
            contentsLine = split(string(fileread(fullfile(testCase.packageFolder(), ...
                'Contents.m'))), newline);
            layerOfFunction = containers.Map('KeyType', 'char', 'ValueType', 'double');
            currentLayer = NaN;

            for k = 1:numel(contentsLine)
                layerToken = regexp(contentsLine(k), '^%\s*L(\d+)(b?)\s', 'tokens', 'once');
                if ~isempty(layerToken)
                    currentLayer = str2double(layerToken(1));
                    if layerToken(2) == "b"
                        currentLayer = currentLayer-0.5;
                    end
                    continue
                end
                nameToken = regexp(contentsLine(k), '^%\s{3,}(\w+)\s+-\s', 'tokens', 'once');
                if ~isempty(nameToken) && ~isnan(currentLayer)
                    layerOfFunction(char(nameToken(1))) = currentLayer;
                end
            end
        end

        function offence = unqualifiedSiblingNames(testCase, fileName, candidateName)
            %UNQUALIFIEDSIBLINGNAMES Sibling names used without the namespace prefix.
            %   The file's own name is exempt: within one file every function is
            %   visible to every other, so recursion and local dispatch are fine.
            code = TestDispatch.codeOnly(fileread(fullfile(testCase.packageFolder(), ...
                fileName+".m")));
            isOffending = false(numel(candidateName), 1);

            for k = 1:numel(candidateName)
                if candidateName(k) == fileName
                    continue
                end
                pattern = "(?<![\w.])" + candidateName(k) + "(?![\w])";
                isOffending(k) = ~isempty(regexp(code, pattern, 'once'));
            end

            offence = fileName + ".m uses " + candidateName(isOffending) + ...
                " unqualified";
            offence = offence(:);
        end

        function called = calledFunctions(testCase, callerName, candidateName)
            %CALLEDFUNCTIONS Package functions called from the code of one file.
            %   Sibling calls are qualified (section C.5 rule 2), so that is the
            %   form searched for.
            code = TestDispatch.codeOnly(fileread(fullfile(testCase.packageFolder(), ...
                callerName+".m")));

            isCalled = false(numel(candidateName), 1);
            for k = 1:numel(candidateName)
                if candidateName(k) == callerName
                    continue
                end
                pattern = "(?<![\w.])referenceSystem\." + candidateName(k) + "(?![\w])";
                isCalled(k) = ~isempty(regexp(code, pattern, 'once'));
            end
            called = candidateName(isCalled);
        end

    end

    methods (Static, Access = private)

        function option = setupOptionsForTesting()
            %SETUPOPTIONSFORTESTING The arguments every test must pass to setup.
            %   REVISION 1.204 TURNED THE INSTALLING DEFAULTS ON: setup now
            %   saves the path, fetches both EOP series and the full kernel set
            %   - some 700 MB - and prints a summary. That is right for the
            %   person who runs the one documented command on a fresh clone and
            %   wrong for every test in this suite, which would then modify the
            %   user's pathdef.m and pull hundreds of megabytes over the network
            %   as a side effect of checking a struct field.
            %
            %   A HARNESS MUST NOT CHANGE THE MACHINE IT MEASURES. The three
            %   arguments live here, in one place, so a later change to the
            %   defaults cannot leave one call site behind - which is exactly
            %   how this trap would be sprung a second time.
            option = {'Save', false, 'Fetch', "none", 'Verbose', false};
        end

        function restorer = preferenceRestorer()
            %PREFERENCERESTORER Put the user's dataFolder preference back.
            %   A TEST THAT SETS A PREFERENCE AND DIES LEAVES THE MACHINE
            %   RECONFIGURED, and unlike a path change that survives a restart.
            %   Every dataFolder test goes through this, so the suite cannot
            %   move where a person's data lives as a side effect of checking
            %   that it can be moved. The same shape as shAnalysis's
            %   testContract, which saves ispref before it touches anything.
            group = 'referenceSystem';
            name = 'dataFolder';
            if ispref(group, name)
                previous = getpref(group, name);
                restorer = onCleanup(@() setpref(group, name, previous));
            else
                restorer = onCleanup(@() TestDispatch.removePreferenceIfPresent( ...
                    group, name));
            end
        end

        function removePreferenceIfPresent(group, name)
            %REMOVEPREFERENCEIFPRESENT Discard a preference without failing.
            %   A teardown that throws turns a passing test red for a reason
            %   that has nothing to do with what it asserted.
            if ispref(group, name)
                rmpref(group, name);
            end
        end

        function removeIfPresent(folder)
            %REMOVEIFPRESENT Delete a scratch folder without failing the test.
            %   A teardown that throws turns a passing test red for a reason
            %   that has nothing to do with what it asserted.
            if isfolder(folder)
                [~, ~] = rmdir(folder, 's');
            end
        end

        function openId = openFileIds()
            %OPENFILEIDS Identifiers of all open files, across releases.
            %   Mirrors the shim in teardownReferenceSystem: fopen('all') was
            %   removed in R2025a and raises on R2026a; openedFiles replaced it
            %   in R2024a. Duplicated here rather than exported, because a
            %   release shim is not part of the toolbox's interface and a test
            %   helper is the right place for the second copy.
            if isempty(which('openedFiles'))
                openId = reshape(fopen('all'), 1, []);
            else
                openId = reshape(openedFiles(), 1, []);
            end
        end

        function restoreEnvironment(previousFolder, previousPath)
            %RESTOREENVIRONMENT Undo everything teardownReferenceSystem changes.
            %   It changes the current folder, the search path and the loaded
            %   MEX. The first two must come back or every later test in the
            %   suite runs somewhere else; the third reloads itself on demand.
            path(previousPath);
            cd(previousFolder);
        end


        function matches = whichAll(name)
            %WHICHALL which(name, '-all') normalised to a cell array of char.
            matches = which(name, '-all');
            if ischar(matches)
                matches = {matches};
            end
            matches = matches(:);
        end

        function repeatConversion(point, callCount)
            %REPEATCONVERSION One point through the dispatcher, many times over.
            %   A loop rather than one vectorised call: the quantity being
            %   measured is the PER-CALL overhead, which vectorising is exactly
            %   what hides.
            for k = 1:callCount
                referenceSystem.convertCoordinates(point, "ITRS", "GEODETIC");
            end
        end

        function deleteIfPresent(fileName)
            %DELETEIFPRESENT Delete a file only if it exists, to keep cleanup quiet.
            if isfile(fileName)
                delete(fileName);
            end
        end

        function isReachable = isPathReachable(entries)
            %ISPATHREACHABLE True for which-entries that are callable unqualified.
            %   A file inside a +namespace or @class folder is not on the MATLAB
            %   path, so it neither shadows nor is shadowed by an exported name.
            if isempty(entries)
                isReachable = false(size(entries));
                return
            end
            isReachable = ~contains(entries, string(filesep)+"+") & ...
                ~contains(entries, string(filesep)+"@");
        end

        function description = describeList(items)
            %DESCRIBELIST Join a string list into one scalar, empty list included.
            if isempty(items)
                description = "none";
            else
                description = join(items(:), "; ");
            end
        end

        function code = codeOnly(sourceText)
            %CODEONLY Executable text of a file: comments removed, literals blanked.
            %   Character and string literals keep their quotes but lose their
            %   contents, so a function name mentioned in an error message is not
            %   mistaken for a call. Block comments are not used anywhere in this
            %   toolbox and are not handled.
            sourceLine = split(string(sourceText), newline);
            sourceLine(startsWith(strip(sourceLine), "%")) = "";
            for k = 1:numel(sourceLine)
                sourceLine(k) = TestDispatch.codeOnlyLine(sourceLine(k));
            end
            code = join(sourceLine, newline);
        end

        function codeLine = codeOnlyLine(oneLine)
            %CODEONLYLINE Cut one line at its comment and blank out its literals.
            character = char(oneLine);
            inCharLiteral = false;
            inStringLiteral = false;
            cutAt = 0;

            for k = 1:numel(character)
                if inCharLiteral
                    inCharLiteral = character(k) ~= '''';
                    if inCharLiteral
                        character(k) = ' ';
                    end
                elseif inStringLiteral
                    inStringLiteral = character(k) ~= '"';
                    if inStringLiteral
                        character(k) = ' ';
                    end
                elseif character(k) == '"'
                    inStringLiteral = true;
                elseif character(k) == ''''
                    inCharLiteral = ~TestDispatch.isTransposeContext(character, k);
                elseif character(k) == '%'
                    cutAt = k;
                    break
                end
            end

            if cutAt > 0
                codeLine = string(character(1:cutAt-1));
            else
                codeLine = string(character);
            end
        end

        function normalized = normalizePath(rawPath)
            %NORMALIZEPATH Comparable form of a folder name, as setup uses.
            normalized = regexprep(string(rawPath), '[\\/]+$', '');
            if ispc()
                normalized = lower(normalized);
            end
        end

        function isTranspose = isTransposeContext(character, k)
            %ISTRANSPOSECONTEXT True if a quote directly follows a value.
            if k == 1
                isTranspose = false;
                return
            end
            previous = character(k-1);
            isTranspose = isstrprop(previous, 'alphanum') || ...
                any(previous == '_)]}.''');
        end

    end


    methods (Test, TestTags = {'provenance'})

        function toolbox_provenance_everyFunctionHasTheMandatoryCategories(testCase)
            % PROMPT P17 ASKS FOR THE SECTION D.1 CATEGORIES PER FUNCTION, AND
            % UNTIL THIS TEST EXISTED NOTHING COUNTED THEM. Each layer suite is
            % green on its own, and a function with no reference literal is
            % invisible in a per-layer count: the shortfall appears only when
            % the package and the whole suite are read together. The audit that
            % produced this test found 46 of 81 functions short of at least one
            % category and two with no coverage at all, after nine green runs.
            %
            % A function counts as exercised by a category when a test method
            % carrying that tag CALLS it, directly or through one static helper.
            % Counting calls rather than method names is deliberate:
            % sphericalToCartesian is exercised by a round trip named for
            % cartesianToSpherical, and that is real coverage.
            %
            % THE INSTRUMENT MEASURES EXERCISE, NOT INTENT, and therefore
            % reports a FLOOR on the gap rather than a ceiling. A reference test
            % that builds its epoch with mjdToEpoch credits mjdToEpoch with
            % reference coverage it did not earn. Tightening that would need the
            % test to declare its subject, which is a second authority beside
            % the method name; the weaker measure is kept because it cannot
            % produce a false alarm, only a missed one.
            required = ["contract", "reference", "precision"];
            coverage = testCase.CategoryCoverageMap;
            exemption = TestDispatch.categoryExemptions();
            exported = testCase.exportedNames();

            offence = strings(0, 1);
            for k = 1:numel(exported)
                name = exported(k);
                seen = TestDispatch.lookupCoverage(coverage, name);
                excused = TestDispatch.exemptCategories(exemption, name);
                missing = setdiff(setdiff(required, seen), excused);
                if ~isempty(missing)
                    offence(end+1, 1) = name + " lacks " + ...
                        join(missing, ", "); %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(offence, "Functions short of a mandatory " + ...
                "section D.1 category: " + TestDispatch.describeList(offence));
        end

        function toolbox_provenance_noCategoryExemptionIsStale(testCase)
            % AN EXEMPTION LIST ROTS INTO A DUMPING GROUND UNLESS SOMETHING
            % OBJECTS WHEN AN ENTRY STOPS BEING NEEDED. Every entry claims that
            % the category cannot be written for that function; the moment a
            % test proves otherwise the claim is false and the entry must go,
            % or the list starts licensing the gaps it was meant to bound.
            %
            % It also refuses an exemption for a function that does not exist,
            % which is what a rename leaves behind.
            coverage = testCase.CategoryCoverageMap;
            exemption = TestDispatch.categoryExemptions();
            exported = testCase.exportedNames();
            offence = strings(0, 1);

            for k = 1:numel(exemption)
                name = string(exemption(k).name);
                if ~any(exported == name)
                    offence(end+1, 1) = name + " is exempted and does not exist"; %#ok<AGROW>
                    continue
                end
                seen = TestDispatch.lookupCoverage(coverage, name);
                overtaken = intersect(string(exemption(k).exempt), seen);
                if ~isempty(overtaken)
                    offence(end+1, 1) = name + " is exempted from " + ...
                        join(overtaken, ", ") + " and now has it"; %#ok<AGROW>
                end
                testCase.verifyNotEmpty(char(exemption(k).why), ...
                    name + " is exempted without a stated reason.");
            end

            testCase.verifyEmpty(offence, "Stale category exemptions: " + ...
                TestDispatch.describeList(offence));
        end

        function toolbox_provenance_disabledWarningsAndLastwarn(testCase)
            % THE MEASUREMENT RUN 69 ASKED FOR, TAKEN DELIBERATELY INSTEAD OF
            % THEORISED ABOUT. WarningRecordingPlugin clears lastwarn before
            % each method and reads it after, and its help states that a test
            % which deliberately exercises a warning path suppresses it with
            % warning('off', id) and "correctly never appears" in the report.
            % Run 69 contradicted that: a test with the identifier switched
            % off appeared in WARNINGS anyway.
            %
            % THE ANSWER WAS ALREADY WRITTEN DOWN, SIXTY LINES AWAY, IN
            % CAPITALS. WarningRecordingPlugin's help has said since session
            % S4: "SUPPRESSING A WARNING DOES NOT HIDE IT FROM lastwarn, and
            % the first run of this plugin is what established that", together
            % with the rule that replaces it - a test which raises a warning
            % deliberately CONSUMES it by registering
            % onCleanup(@() lastwarn('', '')). I read run 69's WARNINGS
            % section, formed a hypothesis, called it an open question across
            % two revisions and never opened the file. **Obligation O28, with
            % the source in the same folder.**
            %
            % THE PROBE STAYS, BECAUSE THE MEASUREMENT IS WORTH HAVING EVEN
            % THOUGH THE QUESTION WAS NOT OPEN. What it now asserts is the
            % measured behaviour rather than the plugin's retracted claim: a
            % disabled warning DOES update lastwarn on this release, and if a
            % future release changes that, the rule above stops being
            % necessary and this test is what will say so. Run 73 measured
            % "updates when off: true, when on: true".
            probeId = 'referenceSystem:testDispatch:lastwarnProbe';
            previousState = warning('off', probeId);
            restoreState = onCleanup(@() warning(previousState)); %#ok<NASGU>
            % THE DOCUMENTED CONSUMING FORM, AND A CLEANUP RATHER THAN A
            % TRAILING STATEMENT so that it fires on pass, on failure and on a
            % filtered assumption alike - which a trailing lastwarn('') does
            % not, and that is the whole reason the plugin's help specifies a
            % cleanup.
            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>

            lastwarn('');
            warning(probeId, 'Probe for the disabled-warning question.');
            [~, disabledId] = lastwarn;
            updatesWhenOff = string(disabledId) == string(probeId);

            warning('on', probeId);
            lastwarn('');
            warningState = warning('off', 'all');       % keep the console clean
            warning(probeId, 'Probe for the disabled-warning question.');
            warning(warningState);
            [~, enabledId] = lastwarn;
            updatesWhenOn = string(enabledId) == string(probeId);

            testCase.log(1, TestPerformance.noteRecord("lastwarn probe", ...
                "updates when off: " + string(updatesWhenOff) + ...
                ", when on: " + string(updatesWhenOn), ...
                "WarningRecordingPlugin assumes off means invisible"));

            % THE ASSERTION IS THE PLUGIN'S CONTRACT, NOT THE LANGUAGE'S
            % BEHAVIOUR. If a disabled warning does update lastwarn, the
            % help of WarningRecordingPlugin is wrong and the tests that rely
            % on suppression need the lastwarn('') that TestEphemeris already
            % carries. Failing here says exactly that, which is more useful
            % than a green run and an unexplained row in WARNINGS.
            % THE MEASURED FACT IS THE ASSERTION, AND IT IS A REGRESSION
            % GUARD ON A LANGUAGE BEHAVIOUR THIS SUITE DEPENDS ON. Seven test
            % methods suppress a warning; every one of them relies on the
            % consuming cleanup because suppression alone does not hide the
            % warning from the plugin. If a release ever makes 'off' also
            % clear lastwarn, this fails, and the cleanups become optional
            % rather than load-bearing - which is worth being told.
            testCase.verifyTrue(updatesWhenOff, ...
                ['A disabled warning no longer updates lastwarn. That is a ', ...
                'change in MATLAB, not a defect here: the consuming ', ...
                'cleanups in seven test methods are then no longer ', ...
                'required, and WarningRecordingPlugin''s help should be ', ...
                'revised back.']);
            testCase.verifyTrue(updatesWhenOn, ...
                'An ENABLED warning did not update lastwarn at all.');
        end

        function toolbox_provenance_noFileReSplitsTheVersionAuthority(testCase)
            % THE GUARD REV. 1.164 PAID FOR. runTestSuite composed its report
            % title as extractBefore(helpTag, " | "), which was correct only
            % while the toolbox name, the version and the model shared one
            % string with a separator in it. D103 split that string in two, the
            % separator went with it, extractBefore returned <missing>, and
            % fprintf refused the ENTIRE report array - a green run of 577
            % tests wrote no report at all.
            %
            % D38 makes toolboxVersion the single authority for these values.
            % A caller that takes a SUBSTRING of one of them has silently made
            % itself a second authority, and it will keep agreeing with the
            % first until the day the composition changes - which is precisely
            % when nobody is looking for it. The fields are already separate;
            % ask for the one you want.
            %
            % Scanned on code only, so the sentence in this comment and the one
            % in runTestSuite.m explaining the defect are not findings.
            forbidden = "(extractBefore|extractAfter|strtok|split|erase|" + ...
                "regexp|regexprep)\s*\(\s*[A-Za-z0-9_.]*\.(helpTag|versionTag)\b";
            packageFile = dir(fullfile(testCase.packageFolder(), '*.m'));
            offence = strings(0, 1);

            for k = 1:numel(packageFile)
                fileName = string(packageFile(k).name);
                code = TestDispatch.codeOnly(string(fileread( ...
                    fullfile(packageFile(k).folder, fileName))));
                if ~isempty(regexp(code, forbidden, 'once'))
                    offence(end+1, 1) = fileName + ...
                        " takes a substring of a toolboxVersion tag instead " + ...
                        "of reading the field it wants"; %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(offence, "Files re-splitting the version " + ...
                "authority: " + TestDispatch.describeList(offence));
        end

        function toolbox_provenance_noContractExemptionSurvivesAnArgumentsBlock(testCase)
            % OPEN ITEM B3'S MECHANISM. noCategoryExemptionIsStale catches an
            % exemption that HAS BECOME false. Nothing caught one that was
            % false the day it was written, and the whole-list re-read at
            % rev. 1.163 found two of sixteen in that state - buildMex and
            % downloadEop, both exempted from contract, both refusing an
            % invalid argument in microseconds without entering their bodies.
            %
            % THE RULE IS MECHANICAL AND HAS NO JUDGEMENT IN IT: a function
            % with an arguments block has a rejection path, a rejection path
            % runs before the body, and a test that drives it costs nothing
            % whatever the body would have cost. So contract may not be
            % exempted for such a function, and every function in this package
            % has an arguments block by section C.1.
            %
            % It does not attempt the same rule for reference or precision,
            % because those genuinely can be impossible - a function that
            % computes nothing has nothing to check against anything. The
            % narrow rule is the one that can be enforced without argument.
            exemption = TestDispatch.categoryExemptions();
            offence = strings(0, 1);

            for k = 1:numel(exemption)
                if ~any(string(exemption(k).exempt) == "contract")
                    continue
                end
                name = string(exemption(k).name);
                file = fullfile(testCase.packageFolder(), name + ".m");
                if ~isfile(file)
                    continue          % the staleness test reports this one
                end
                code = TestDispatch.codeOnly(string(fileread(file)));
                if ~isempty(regexp(code, '^\s*arguments\s*$', 'lineanchors', 'once'))
                    offence(end+1, 1) = name + ...
                        " is exempted from contract and has an arguments " + ...
                        "block, so an invalid call is refused before its " + ...
                        "body runs and a contract test costs nothing"; %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(offence, "Contract exemptions that an " + ...
                "arguments block refutes: " + TestDispatch.describeList(offence));
        end

        function toolbox_provenance_onlyReadEphemerisFurnishesKernels(testCase)
            % DECISION D89, AS A STATIC GUARD, AND IT LIVES HERE BECAUSE OF
            % WHERE IT FAILED. Written in TestEphemeris it used a plain
            % contains() and matched the words "cspice_furnsh" in a COMMENT in
            % downloadKernels.m - one sentence explaining why a partial
            % transfer is dangerous - and reported a D26 violation that did not
            % exist. A guard that cannot tell a call from a mention will be
            % switched off the first time it is wrong about something
            % important. TestDispatch owns codeOnly, which blanks comments and
            % string literals, and owns the other package-wide static checks,
            % so the guard belongs beside them rather than beside the functions
            % it polices.
            %
            % Furnishing a leapseconds kernel would install a second
            % leap-second authority beside leapSecondTable, silently: the two
            % agree until a leapSecondTable("load") override is installed and
            % SPICE does not see it. D26 permits exactly one wrapper.
            packageFolder = fullfile(testCase.toolboxRoot(), '+referenceSystem');
            candidateFile = dir(fullfile(packageFolder, '**', '*.m'));

            offence = strings(0, 1);
            for k = 1:numel(candidateFile)
                fileName = string(candidateFile(k).name);
                code = TestDispatch.codeOnly(fileread(fullfile( ...
                    candidateFile(k).folder, fileName)));
                if contains(code, "cspice_furnsh")
                    offence(end+1, 1) = fileName; %#ok<AGROW>
                end
            end

            testCase.verifyEqual(sort(offence), "readEphemeris.m", ...
                "cspice_furnsh belongs in readEphemeris and nowhere else " + ...
                "(decision D26). Found in: " + ...
                TestDispatch.describeList(offence));
        end

        function toolbox_provenance_everyToleranceCarriesAJustification(testCase)
            % SESSION S6 SEAM ITEM 2, AND DESIGN PRINCIPLE 15. A tolerance is a
            % claim about which error dominates, so every one of them carries a
            % comment naming the algorithmic quantity it bounds. This is the
            % last point at which a bare number can be caught cheaply.
            %
            % WHAT THIS CAN AND CANNOT CHECK, stated plainly rather than
            % implied: it asserts that a method containing a numeric tolerance
            % also contains a comment. It cannot judge whether the comment is
            % true, or whether it names the right quantity. That remains a
            % review obligation and obligation O8 remains the rule for changing
            % a bound. What the check does buy is the floor: a tolerance with no
            % sentence beside it is a number nobody has had to justify, and 45
            % methods were in that state when the check was written.
            offence = testCase.methodsWithAnUnjustifiedTolerance();

            testCase.verifyEmpty(offence, "Test methods asserting a tolerance " + ...
                "with no comment in the method: " + ...
                TestDispatch.describeList(offence));
        end

        function toolbox_provenance_noToleranceIsJustifiedByEopMagnitude(testCase)
            % SECTION D.1, IN THE ONE FORM THAT IS MECHANICALLY CHECKABLE.
            % "A tolerance justified by EOP magnitudes is a defect" - it passes
            % a broken algorithm and must be re-argued every time the EOP series
            % improves. The phrasing that does this is recognisable: a comment
            % that mentions the EOP error and then concedes the point instead of
            % naming an algorithmic quantity.
            %
            % THE PHRASES ARE LISTED IN THE ARRAY BELOW AND NOWHERE ELSE, not
            % even as an example in this comment. A scanner that quotes its own
            % targets matches itself, and the first draft of this test did.
            %
            % The scan is deliberately narrow. A comment may mention EOP for
            % perfectly good reasons - interpolateEop's own tests must - so only
            % the concessive forms are refused, and the test names the line it
            % objects to rather than the method, because that is what has to be
            % rewritten.
            concession = ["about the eop error anyway", "eop error anyway", ...
                "dominated by the eop", "eop dominates anyway", ...
                "within the eop error", "no better than the eop"];
            offence = testCase.commentsMatching(concession);

            testCase.verifyEmpty(offence, "Tolerances justified by EOP " + ...
                "magnitude rather than by an algorithmic quantity: " + ...
                TestDispatch.describeList(offence));
        end

    end

    methods (Test, TestTags = {'speed'})

        function convertCoordinates_speed_manySinglePointCalls(testCase)
            % THE WORKLOAD THE N = 1e6 BENCHMARK CANNOT SEE. Graph construction
            % is a FIXED cost per call, so at a million points it hides under
            % two per cent of the leg and at one point it is the entire call.
            % Before session S7 the graph was rebuilt every time, at 2 to 3 ms
            % on GLNXA64 and 20 to 39 ms on PCWIN64, so a loop over ten
            % thousand single-point conversions - a per-station or per-epoch
            % pipeline, which is an ordinary thing to write - spent between
            % twenty seconds and six minutes assembling the same 194 edges.
            %
            % A THOUSAND CALLS ARE TIMED TOGETHER because one is too fast to
            % measure and it is the PER-CALL cost that regressed. The first
            % call of the session still pays the build; at a thousand calls
            % that is under four per cent of the budget below.
            %
            % 1.0 s for a thousand calls is a NEW TARGET AND A PREDICTION (risk
            % R17): after caching, a call is a struct lookup, a path search
            % over 194 edges and one Vermeille evaluation on one point, so a
            % millisecond each is generous. It is also 2 to 39 times under what
            % the uncached graph cost, which is what makes it a detector for
            % this defect returning rather than a decoration.
            targetSeconds = 1.0;
            callCount = 1000;
            point = [4075532.4772, 931770.2186, 4801623.4210];

            % FIVE REPETITIONS, AND THE HARD ASSERTION IS ON THE FASTEST
            % (rev. 1.86). Run 18 measured this row at 5.27 s against 0.74 s in
            % the two runs either side of it, on the same host and the same MEX
            % binary, while every other benchmark stayed inside 0.7x to 1.5x.
            % Run 17 did the same thing to rotationItrsToGcrs and left this row
            % alone. A regression does not move between tests between runs.
            %
            % External load can only ADD time, so the fastest repetition is the
            % honest estimate of what the code costs and the median is the
            % honest report of what the machine did. The failure is asserted on
            % the first and the warning is raised on the second, so a spike
            % informs without stopping the suite and a real regression - which
            % moves both - still fails.
            [medianSeconds, fastestSeconds] = TestPerformance.medianDuration(@() ...
                TestDispatch.repeatConversion(point, callCount), 5);

            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("convertCoordinates(N=1, 1000 calls)", ...
                callCount, medianSeconds, targetSeconds, fastestSeconds));
            if medianSeconds > targetSeconds
                warning('referenceSystem:test:slowerThanTarget', ...
                    ['%d single-point conversions took %.3f s against %.3f s ', ...
                    '(fastest of five %.3f s; a normal fastest with a slow ', ...
                    'median is the machine, not the toolbox).'], ...
                    callCount, medianSeconds, targetSeconds, fastestSeconds);
            end
            testCase.verifyLessThan(fastestSeconds, 5 * targetSeconds);
        end

        function convertCoordinates_speed_oneMillionPoints(testCase)
            % THE DISPATCHER HAD NO BENCHMARK UNTIL P17, so the cost of routing
            % has never appeared in a report. The target is stated in section
            % B.7 as 1.0 s for the ITRS to GEODETIC edge at N = 1e6: the leg
            % itself is cartesianToGeodetic at 0.3 s, and the remaining 0.7 s is
            % the allowance for graph construction, path search and option
            % validation. If the measured figure sits near the leg's own target
            % the routing is free; if it sits near the whole budget, the graph
            % is being rebuilt per call, which is what run 9 suggested when
            % convertCoordinates_contract_everyPublishedEdgeExecutes took 7.6 s
            % for about twenty calls.
            % 0.30 s, TIGHTENED FROM THE 1.0 s PREDICTED IN REV. 1.73 (risk
            % R17). Measured 0.124 s on PCWIN64 and 0.032 s on GLNXA64, against
            % 0.103 s and 0.030 s for the bare cartesianToGeodetic leg on the
            % same runs. THE ROUTING IS ESSENTIALLY FREE AT THIS SIZE: the
            % 194-edge graph is rebuilt per call, but at N = 1e6 that cost
            % amortises to under 2 per cent. It is NOT free at small N, which
            % is why everyPublishedEdgeExecutes remains among the slower tests.
            targetSeconds = 0.30;
            point = TestPerformance.earthFixedCloud(1000000);

            medianSeconds = TestPerformance.medianDuration(@() ...
                referenceSystem.convertCoordinates(point, "ITRS", "GEODETIC"), 3);

            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("convertCoordinates(ITRS>GEODETIC)", ...
                1000000, medianSeconds, targetSeconds));
            if medianSeconds > targetSeconds
                warning('referenceSystem:test:slowerThanTarget', ...
                    'convertCoordinates took %.3f s against a %.3f s target.', ...
                    medianSeconds, targetSeconds);
            end
            % Section D.1: a benchmark warns at the target and fails at five
            % times it, because the target is a property of the machine while a
            % fivefold miss is a property of the code.
            testCase.verifyLessThan(medianSeconds, 5 * targetSeconds);
        end

    end

    methods (Test, TestTags = {'contract'})

        function buildDocumentation_contract_writesAPageAndReportsWhatItDid(testCase)
            % THIS IS THE FIRST TEST THAT ACTUALLY RUNS THE GENERATOR. Until
            % session S7 the shipped reference page was produced by an
            % equivalent parse outside MATLAB, and the MATLAB generator had
            % never executed - which is the state obligation O2 exists to
            % forbid. It survived two green runs because nothing called it.
            % Setup now calls it on every fresh clone, so a defect here would
            % greet every new user.
            %
            % The page goes to a temporary file and the search step is not
            % requested, so the test neither touches the shipped documentation
            % nor pays for builddocsearchdb.
            outputFile = string(tempname) + ".html";
            cleaner = onCleanup(@() TestDispatch.deleteIfPresent(outputFile)); %#ok<NASGU>

            report = referenceSystem.buildDocumentation('Output', outputFile, ...
                'Steps', "reference", 'Force', true);

            testCase.verifyEqual(report.referenceAction, "written");
            testCase.verifyEqual(report.searchAction, "skipped", ...
                'A step that was not requested must not report as done.');
            testCase.assertTrue(isfile(outputFile), 'No page was written.');

            pageText = lower(string(fileread(outputFile)));
            exported = testCase.exportedNames();
            quote = char(34);
            present = arrayfun(@(name) contains(pageText, ...
                "id=" + quote + lower(name) + quote), exported);
            testCase.verifyEmpty(exported(~present), ...
                "The generator omitted: " + ...
                TestDispatch.describeList(exported(~present)));
        end

        function buildDocumentation_contract_isCurrentOnASecondCall(testCase)
            % Idempotence is what makes it safe for setup to call this on every
            % session start. The second call must find the page current and do
            % nothing, or a startup.m that runs setup would reparse eighty help
            % blocks every morning.
            outputFile = string(tempname) + ".html";
            cleaner = onCleanup(@() TestDispatch.deleteIfPresent(outputFile)); %#ok<NASGU>
            referenceSystem.buildDocumentation('Output', outputFile, ...
                'Steps', "reference", 'Force', true);

            second = referenceSystem.buildDocumentation('Output', outputFile, ...
                'Steps', "reference");

            testCase.verifyEqual(second.referenceAction, "current", ...
                'The generator rewrote a page that was already newer.');
        end

        function buildDocumentation_contract_refusesAnAbsentToolboxRoot(testCase)
            testCase.verifyError(@() referenceSystem.buildDocumentation( ...
                'ToolboxRoot', string(tempname)), ...
                'referenceSystem:buildDocumentation:packageNotFound');
        end

    end

    methods (Access = private)

        function file = testFiles(testCase)
            %TESTFILES Every test class of the suite, as dir entries.
            file = dir(fullfile(testCase.toolboxRoot(), 'test', 'Test*.m'));
        end

        function coverage = categoryCoverage(testCase)
            %CATEGORYCOVERAGE Package function name to the section D.1 tags exercising it.
            %   One pass over every test class records, per method, its tags,
            %   the referenceSystem.* names it calls and the sibling test
            %   methods it calls. A second pass resolves ONE level of helper
            %   indirection, which is what cookbookRotationWithInfo and
            %   TestOrbit.epochAt need and is as deep as the suite goes.
            source = testCase.SuiteSource;
            methodKey = strings(0, 1);
            methodTag = {};
            methodPackageCall = {};
            methodHelperCall = {};

            for f = 1:numel(source)
                className = source(f).className;
                sourceLine = source(f).line;
                activeTag = strings(0, 1);
                inMethod = false;

                for k = 1:numel(sourceLine)
                    oneLine = char(sourceLine(k));

                    header = regexp(oneLine, '^\s*methods\s*\((.*)\)', ...
                        'tokens', 'once');
                    if ~isempty(header)
                        inMethod = false;
                        activeTag = TestDispatch.tagsOfHeader(header{1});
                        continue
                    end

                    signature = regexp(oneLine, ...
                        '^\s*function\s+(?:[^=]*=\s*)?(\w+)\s*\(', 'tokens', 'once');
                    if ~isempty(signature)
                        methodKey(end+1, 1) = className + "/" + ...
                            string(signature{1}); %#ok<AGROW>
                        methodTag{end+1, 1} = activeTag; %#ok<AGROW>
                        methodPackageCall{end+1, 1} = strings(0, 1); %#ok<AGROW>
                        methodHelperCall{end+1, 1} = strings(0, 1); %#ok<AGROW>
                        inMethod = true;
                        continue
                    end

                    if ~inMethod
                        continue
                    end
                    code = char(TestDispatch.codeOnlyLine(string(oneLine)));
                    index = numel(methodKey);
                    methodPackageCall{index} = union( ...
                        methodPackageCall{index}(:), ...
                        TestDispatch.capturedNames(code, 'referenceSystem\.(\w+)'));
                    methodHelperCall{index} = union( ...
                        methodHelperCall{index}(:), ...
                        TestDispatch.capturedNames(code, '(\w+)\s*\('));
                end
            end

            % Bare method name to the indices carrying it. Built once: resolving
            % by a linear search per helper call is quadratic in the suite size,
            % and the suite is the thing that grows.
            indexOfName = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for index = 1:numel(methodKey)
                bare = char(extractAfter(methodKey(index), "/"));
                if isKey(indexOfName, bare)
                    indexOfName(bare) = [indexOfName(bare), index];
                else
                    indexOfName(bare) = index;
                end
            end

            coverage = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for index = 1:numel(methodKey)
                tag = methodTag{index};
                if isempty(tag)
                    continue
                end
                called = methodPackageCall{index}(:);
                helper = methodHelperCall{index};
                for h = 1:numel(helper)
                    bare = char(helper(h));
                    if ~isKey(indexOfName, bare)
                        continue
                    end
                    for sibling = indexOfName(bare)
                        called = union(called, methodPackageCall{sibling}(:));
                    end
                end
                for c = 1:numel(called)
                    key = char(called(c));
                    if isKey(coverage, key)
                        coverage(key) = union(coverage(key), tag(:));
                    else
                        coverage(key) = tag(:);
                    end
                end
            end
        end

        function offence = methodsWithAnUnjustifiedTolerance(testCase)
            %METHODSWITHANUNJUSTIFIEDTOLERANCE Methods asserting a bound with no comment.
            source = testCase.SuiteSource;
            offence = strings(0, 1);

            for f = 1:numel(source)
                className = source(f).className;
                sourceLine = source(f).line;
                current = "";
                hasComment = false;
                hasTolerance = false;

                for k = 1:numel(sourceLine)
                    oneLine = char(sourceLine(k));
                    signature = regexp(oneLine, ...
                        '^\s*function\s+(?:[^=]*=\s*)?(\w+)\s*\(', 'tokens', 'once');
                    if ~isempty(signature)
                        if hasTolerance && ~hasComment
                            offence(end+1, 1) = current; %#ok<AGROW>
                        end
                        current = className + "/" + string(signature{1});
                        hasComment = false;
                        hasTolerance = false;
                        continue
                    end
                    if current == ""
                        continue
                    end
                    if ~isempty(regexp(oneLine, '^\s*%', 'once'))
                        hasComment = true;
                    end
                    if contains(string(oneLine), "'AbsTol'") || ...
                            contains(string(oneLine), "'RelTol'")
                        hasTolerance = true;
                    end
                end

                if hasTolerance && ~hasComment
                    offence(end+1, 1) = current; %#ok<AGROW>
                end
            end
        end

        function offence = commentsMatching(testCase, phrase)
            %COMMENTSMATCHING Comment lines of the suite containing any phrase given.
            source = testCase.SuiteSource;
            offence = strings(0, 1);

            for f = 1:numel(source)
                fileName = source(f).fileName;
                sourceLine = source(f).line;
                for k = 1:numel(sourceLine)
                    if isempty(regexp(char(sourceLine(k)), '^\s*%', 'once'))
                        continue
                    end
                    if any(contains(lower(sourceLine(k)), phrase))
                        offence(end+1, 1) = fileName + " line " + k + ...
                            ": " + strip(sourceLine(k)); %#ok<AGROW>
                    end
                end
            end
        end

    end

    methods (Static, Access = private)

        function tag = tagsOfHeader(headerText)
            %TAGSOFHEADER The TestTags of one methods block header, empty if not a test.
            if ~contains(string(headerText), "Test")
                tag = strings(0, 1);
                return
            end
            tag = TestDispatch.capturedNames(headerText, '''([a-z]+)''');
        end

        function name = capturedNames(text, pattern)
            %CAPTUREDNAMES Every first capture of a pattern, as a string column.
            token = regexp(text, pattern, 'tokens');
            if isempty(token)
                name = strings(0, 1);
                return
            end
            name = string(cellfun(@(c) c{1}, token, 'UniformOutput', false));
            name = name(:);
        end

        function seen = lookupCoverage(coverage, name)
            %LOOKUPCOVERAGE The tags recorded for a function, empty where none are.
            if isKey(coverage, char(name))
                seen = coverage(char(name));
                seen = seen(:);
            else
                seen = strings(0, 1);
            end
        end

        function excused = exemptCategories(exemption, name)
            %EXEMPTCATEGORIES The categories one function is excused from.
            excused = strings(0, 1);
            for k = 1:numel(exemption)
                if string(exemption(k).name) == name
                    excused = string(exemption(k).exempt);
                    excused = excused(:);
                    return
                end
            end
        end

        function exemption = categoryExemptions()
            %CATEGORYEXEMPTIONS Functions for which a category cannot be written.
            %   EVERY ENTRY IS A CLAIM THAT THE TEST IS IMPOSSIBLE, NOT THAT IT
            %   IS INCONVENIENT, and the companion test refuses an entry whose
            %   category has since been covered. Two shapes recur. A function
            %   that reports the state of this machine or of this toolbox has no
            %   external authority to be checked against and no computed
            %   quantity whose precision could be asserted. A function that
            %   returns published constants verbatim has a reference test and
            %   nothing for a precision test to round-trip.
            %   THREE PROPOSED ENTRIES WERE WITHDRAWN BEFORE DELIVERY because
            %   the companion staleness test found coverage that already
            %   existed: mexInfo, attitudeConvention and leapSecondTable. One of
            %   those three, mexInfo, is credited through calls that appear only
            %   inside assume guards, which is the instrument's documented floor
            %   property showing itself. The entry was removed anyway: a stale
            %   exemption is worse than an over-generous count, because it
            %   licenses a gap permanently while the count merely misses one.
            exemption = struct('name', {}, 'exempt', {}, 'why', {});

            exemption(end+1) = TestDispatch.exemption("writeInterpolant", ...
                "reference", ...
                "Writes this toolbox's own file format. There is no " + ...
                "published file to check the output against; what has to " + ...
                "hold is that the round trip is exact, which the precision " + ...
                "test asserts with AbsTol 0.");
            exemption(end+1) = TestDispatch.exemption("readInterpolant", ...
                "reference", ...
                "Reads this toolbox's own file format; same argument as " + ...
                "writeInterpolant, and the two are only meaningful as a pair.");
            exemption(end+1) = TestDispatch.exemption("mexSourceDigest", ...
                ["reference", "precision"], ...
                "Answers 'did these files change' about this machine's own " + ...
                "sources. There is no published digest of them to check " + ...
                "against, and the value is an arbitrary label whose " + ...
                "numerical precision means nothing - only its equality does, " + ...
                "which is what the contract test asserts.");
            exemption(end+1) = TestDispatch.exemption("dataFolder", ...
                "precision", ...
                "Resolves a path on THIS MACHINE. A path is not a computed " + ...
                "quantity whose precision could be round-tripped - only its " + ...
                "equality matters, which the contract tests assert across " + ...
                "set, query and reset. REFERENCE IS NOT EXEMPTED AND WAS " + ...
                "BRIEFLY CLAIMED TO BE: the kernel-backed tests call this " + ...
                "function to find their kernels, so it earns reference " + ...
                "coverage through them, and the staleness companion refused " + ...
                "the wider claim at run 95.");
            exemption(end+1) = TestDispatch.exemption("toolboxVersion", ...
                ["reference", "precision"], ...
                "Reports the toolbox's own version and provenance.");
            exemption(end+1) = TestDispatch.exemption("buildDocumentation", ...
                ["reference", "precision"], ...
                "Transforms text and computes nothing, so there is no " + ...
                "published quantity to check against and no precision to " + ...
                "assert. That the page it writes covers the package IS " + ...
                "asserted, by functionReferenceCoversThePackage.");
            % CONTRACT REMOVED AT REV. 1.163, AND IT WAS WRONG WHEN WRITTEN,
            % not overtaken. The entry reasoned from an expensive SUCCESS to an
            % impossible test and never asked what a rejected call costs: an
            % arguments block runs before the body, so buildMex('OpenMp', "yes")
            % is refused in microseconds and compiles nothing. Open item B3.
            exemption(end+1) = TestDispatch.exemption("buildMex", ...
                ["reference", "precision"], ...
                "A valid call recompiles 255 sources and takes a minute, so " + ...
                "no test may make one, and there is no published quantity a " + ...
                "compiler invocation could be checked against. Its testable " + ...
                "contract - argument rejection, and that a locked output is " + ...
                "not misreported as an OpenMP failure - is asserted in " + ...
                "TestDispatch, and mexInfo covers the product.");
            exemption(end+1) = TestDispatch.exemption("runTestSuite", ...
                ["reference", "precision"], ...
                "The harness itself; its report format is a contract.");
            exemption(end+1) = TestDispatch.exemption("teardownReferenceSystem", ...
                ["reference", "precision"], ...
                "Reports what holds the folder on this machine.");
            exemption(end+1) = TestDispatch.exemption("downloadKernels", ...
                ["reference", "precision"], ...
                "Transfers files and computes nothing, so there is no " + ...
                "quantity whose precision could be asserted. A reference " + ...
                "test would have to check the catalogue's URLs against the " + ...
                "servers, which needs a live network and would make the " + ...
                "suite non-deterministic and offline-hostile; that check " + ...
                "exists as Mode = ""verify"", run deliberately by a human, " + ...
                "and it has already found two wrong rows (O26).");
            % REFERENCE COVERAGE REMOVED FROM THIS EXEMPTION AT REV. 1.146.
            % Section H.7.7 wrote it with "REVISIT AT P22b: if the suite ever
            % gains an optional kernel-backed tier, a reference test becomes
            % possible and the staleness test will object - which is the
            % intended outcome." P23b added that tier, the test objected, and
            % this is the exemption retiring on schedule rather than being
            % patched around. Precision stays: readEphemeris still computes
            % nothing whose precision could be asserted.
            exemption(end+1) = TestDispatch.exemption("readEphemeris", ...
                "precision", ...
                "Furnishes kernels and computes nothing, so there is no " + ...
                "quantity whose precision could be asserted. Its reference " + ...
                "coverage arrived with the kernel-backed tier at P23b and " + ...
                "this entry was cut back rather than kept.");
            exemption(end+1) = TestDispatch.exemption("ephemerisBodies", ...
                "precision", ...
                "Returns a registry of published constants verbatim - the " + ...
                "SOFA header accuracy figures and the NAIF identifiers - so " + ...
                "there is nothing for a precision test to round-trip. This " + ...
                "is the second recurring shape named at the head of this " + ...
                "list. Its reference coverage is real: the heliocentric " + ...
                "band test drives every row of the registry.");
            % CONTRACT REMOVED AT REV. 1.163 FOR THE SAME REASON AS buildMex.
            % "Every code path reaches the network" was false of the rejection
            % paths, which is where a contract test lives. Open item B3.
            exemption(end+1) = TestDispatch.exemption("downloadEop", ...
                ["reference", "precision"], ...
                "Every SUCCEEDING code path reaches the network, which " + ...
                "section D.2 forbids, so no reference or precision test can " + ...
                "be written offline. The properties testable without it - " + ...
                "that an unknown series is refused by the arguments block, " + ...
                "and that the series it offers are exactly the set readEop " + ...
                "can read - are asserted in TestEop.");
            exemption(end+1) = TestDispatch.exemption("timeScale", ...
                ["reference", "precision"], ...
                "A registry of scale names and boolean properties.");
            exemption(end+1) = TestDispatch.exemption("normalizeEpoch", ...
                "reference", ...
                "The canonical form is a section B.3 convention, not a published quantity.");
            exemption(end+1) = TestDispatch.exemption("itrfParameters", ...
                "precision", ...
                "Returns published constants verbatim; convertItrf carries the precision tests.");
            exemption(end+1) = TestDispatch.exemption("geoidUndulation", ...
                "reference", ...
                "No geoid grid is bundled (risk R8), so no published undulation can be asserted.");
        end

        function record = exemption(name, exempt, why)
            %EXEMPTION One row of the exemption table.
            record = struct('name', name, 'exempt', exempt, 'why', why);
        end


    end


    methods (Test, TestTags = {'provenance'})

        function toolbox_provenance_functionReferenceCoversThePackage(testCase)
            % DECISION D33: the function reference is GENERATED, never
            % hand-written, so the risk is not that it is wrong but that it is
            % STALE - a page generated before the last three functions were
            % added looks exactly like a current one.
            %
            % The test asserts coverage, not bytes. Comparing against a freshly
            % generated file would be the stronger check and the wrong one: it
            % would fail on any whitespace difference between the generator's
            % output and the shipped copy, which is not a defect anybody needs
            % told about, and it would make the suite depend on the doc folder
            % being writable.
            referencePage = fullfile(testCase.toolboxRoot(), 'doc', ...
                'referenceSystem_functionReference.html');
            testCase.assumeTrue(isfile(referencePage), ...
                'The generated function reference is not present.');
            pageText = string(fileread(referencePage));
            exported = testCase.exportedNames();
            missing = strings(0, 1);

            for k = 1:numel(exported)
                anchor = "id=""" + lower(exported(k)) + """";
                if ~contains(lower(pageText), lower(anchor))
                    missing(end+1, 1) = exported(k); %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(missing, "The function reference has no " + ...
                "section for: " + TestDispatch.describeList(missing) + ...
                ". Run referenceSystem.buildDocumentation.");
        end

    end

    methods (Test, TestTags = {'contract'})

        function setupReferenceSystem_contract_reportsTheDocumentationState(testCase)
            % Section C.10 makes setup a maintenance obligation rather than a
            % convenience: a prompt that adds a prerequisite extends setup in
            % the same session, because a setup function that silently stops
            % covering the toolbox is worse than none. P18 adds the Help
            % browser registration.
            %
            % WHAT IS ASSERTED IS THAT THE STATE IS REPORTED, not what it says:
            % whether the pages are searchable is a property of this machine and
            % of whether builddocsearchdb has been run, which is a deliberate
            % and slow user action.
            previousFolder = pwd;
            previousPath = path;
            restorer = onCleanup(@() TestDispatch.restoreEnvironment( ...
                previousFolder, previousPath));

            % Save, Fetch and Verbose are named because rev. 1.204 turned all
            % three on by default. See TestDispatch.setupOptionsForTesting.
            status = setupReferenceSystem(TestDispatch.setupOptionsForTesting{:});

            testCase.assertTrue(isfield(status, 'documentation'), ...
                'setup does not report the documentation state.');
            testCase.verifyTrue(all(isfield(status.documentation, ...
                {'registered', 'reason', 'infoFile', 'helpFolder', 'searchable'})), ...
                'The documentation state is missing a documented field.');
            testCase.verifyClass(status.documentation.registered, 'logical', ...
                'registered must be a plain logical, not a status code.');
            if ~status.documentation.registered
                testCase.verifyNotEmpty(char(status.documentation.reason), ...
                    'An unregistered doc set must say which file is absent.');
            end
        end

    end

end
