function referenceSystemCiGate()
%REFERENCESYSTEMCIGATE The ONE CI entry point: install, run the suite, judge, or error.
%
%   RENAMED FROM ciGate AT REV. 1.229. Two projects on the development machine
%   both put a file called ciGate.m on the MATLAB path, the other one won, and
%   TestDispatch/namespace_contract_noBaseMatlabCollision was red on every
%   local run from rev. 1.216 to 1.228 - so the local gate could never be
%   green there. A name that carries the toolbox's cannot collide that way.
%
%   referenceSystemCiGate()
%
%   Called by the CI (`matlab-actions/run-command`: `referenceSystemCiGate`) and usable as a
%   local postflight (`matlab -batch referenceSystemCiGate`). It is the gate that protects
%   main, and it is NEVER a bare runTestSuite call: runTestSuite RETURNS its
%   results and raises only on a class that failed to load, so a caller that
%   merely checks for an exception treats a red run as a pass. The judgement
%   is this file's job and is made in one place.
%
% INPUT ARGUMENTS
%   (none)      CI policy is decided HERE and nowhere else. Mechanism lives in
%               setupReferenceSystem and referenceSystem.runTestSuite; the
%               choice of what CI installs and what it tolerates is local.
%
% OUTPUT ARGUMENTS
%   (none)      Side effects: console summary, the test report written by
%               runTestSuite (uploaded as the CI artefact), and an error on
%               red so that `matlab -batch` exits non-zero.
%
% ERRORS
%   referenceSystem:referenceSystemCiGate:red
%       The run is not green. Raised for any of: a failed test; a filtered
%       test that is NOT on the runTestSuite allow-list; a test class on disk
%       that contributed nothing to the run; a report file that was not
%       written. The message lists every reason, not the first one.
%
% METHOD
%   THE ALLOW-LIST IS NOT COPIED HERE. runTestSuite owns the catalogue of
%   tests whose assumption is expected not to hold (D116) and returns the
%   classification in its third output. Keeping a second copy in this file is
%   the defect auditPackage.py's own header calls out - two instruments
%   disagreeing after one of them is edited - so the count is read from the
%   authority and never recomputed.
%
%   COVERAGE IS EVIDENCE, NOT AN ASSUMPTION. Every test/Test*.m on disk must
%   appear in the results. runTestSuite already refuses a class that parsed
%   but contributed no tests; this check also catches a class that the folder
%   scan never reached, which is the failure mode that looks like a smaller
%   green run.
%
%   THE ARTEFACT IS PRODUCED BEFORE THE VERDICT IS RAISED, so a red run still
%   uploads the report a reader needs. That is runTestSuite's own ordering and
%   this function does not undo it.
%
% ACCURACY
%   Not applicable; the function judges a run and computes no numerical
%   quantity. The figures it prints are counts taken from the results.
%
% EXAMPLE
%   % exactly what the CI runs:
%   %   matlab -batch "referenceSystemCiGate"
%   referenceSystemCiGate();
%
% REFERENCES
%   Handover section C.10 (installation and entry points), decision D116
%   (the intended-filter allow-list). The workflow that calls this function
%   is .github/workflows/ci.yml.
%
% KEYWORDS
%   ci, gate, continuous integration, test suite, verdict
%
% See also SETUPREFERENCESYSTEM, REFERENCESYSTEM.RUNTESTSUITE
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-08-21 15:20 (CEST, UTC+02:00)
% Revised: 2026-11-06 21:45 (CET, UTC+01:00)
% -------------------------------------------------------------------------

    toolboxRoot = string(fileparts(mfilename('fullpath')));

    isCi = strcmp(getenv('REFERENCESYSTEM_CI'), '1');
    if isCi
        % Headless runner: MATLAB -batch has no display, so any test that
        % opens a figure must not try to show one.
        set(groot, 'DefaultFigureVisible', 'off');
    end

    % --- install ---------------------------------------------------------
    % Save=false: the runner is ephemeral and savepath would either fail or
    %   write a pathdef nothing reads.
    % Fetch="kernels": the EOP tables are under revision control in data/, so
    %   only the SPICE kernels have to come off the network. KernelSpan
    %   "short" selects de440s.bsp and excludes the full-span de440.bsp,
    %   which no test needs and which is about 115 MB.
    % Build="always" ON CI ONLY: a fresh checkout carries no compiled gateway,
    %   and forcing the build makes the MEX compile itself part of the gate
    %   rather than a side effect of "auto" that a cache could skip.
    % Build="auto" EVERYWHERE ELSE. A local run of this gate is a second
    %   MATLAB next to one that already has the toolbox loaded: the
    %   toolboxInstaller GUI runs setup in its own MATLAB and this gate in a
    %   "-batch" one, and a desktop session runs `matlab -batch
    %   referenceSystemCiGate` the same way. Windows refuses to overwrite a
    %   DLL another process has mapped, so a forced relink fails there
    %   (MEASURED 2026-11-06: the installer's MATLAB held mexGateway.mexw64
    %   and the gate's relink failed with mexBuildFailed). "auto" still
    %   rebuilds when the binary is missing or any C source differs from the
    %   one it was built from (the digest in mexGateway.sources), so a local
    %   run can never test a stale binary; it only skips a relink that would
    %   produce the same gateway.
    if isCi
        buildMode = "always";
    else
        buildMode = "auto";
    end
    setupReferenceSystem('Save', false, 'Fetch', "kernels", ...
        'KernelSet', "all", 'KernelSpan', "short", 'Build', buildMode, ...
        'Verbose', true);

    % --- run -------------------------------------------------------------
    [results, reportFile, summary] = referenceSystem.runTestSuite( ...
        'Verbose', true);

    % --- gather the evidence ---------------------------------------------
    reason = strings(0, 1);

    failedCount = sum([results.Failed]);
    if failedCount > 0
        failedName = string({results([results.Failed]).Name});
        reason(end + 1, 1) = sprintf('%d test(s) FAILED: %s', ...
            failedCount, join(failedName, ', '));
    end

    if summary.unexpectedFilter > 0
        reason(end + 1, 1) = sprintf( ...
            ['%d test(s) were filtered WITHOUT being on the intended-filter ', ...
            'allow-list: %s'], summary.unexpectedFilter, ...
            join(summary.unexpectedFilterName, ', '));
    end

    onDisk = string({dir(fullfile(toolboxRoot, 'test', 'Test*.m')).name});
    onDisk = extractBefore(onDisk, strlength(onDisk) - 1);
    ranClass = unique(extractBefore(string({results.Name}) + "/", "/"));
    ranClass = regexprep(ranClass, '[\[\(][^\]\)]*[\]\)]', '');
    missingClass = setdiff(onDisk, ranClass);
    if ~isempty(missingClass)
        reason(end + 1, 1) = sprintf( ...
            '%d test class(es) on disk contributed nothing to the run: %s', ...
            numel(missingClass), join(missingClass, ', '));
    end

    if ~isfile(reportFile)
        reason(end + 1, 1) = sprintf('No report was written at %s', reportFile);
    end

    % --- verdict ---------------------------------------------------------
    fprintf(['\nreferenceSystemCiGate: %d tests, %d passed, %d failed, %d skipped by ', ...
        'design, %d unexpected filters\n'], numel(results), ...
        sum([results.Passed]), failedCount, summary.intendedSkip, ...
        summary.unexpectedFilter);
    fprintf('referenceSystemCiGate: report at %s\n', reportFile);
    echoBenchmarks(reportFile);

    if ~isempty(reason)
        error('referenceSystem:referenceSystemCiGate:red', 'referenceSystemCiGate RED:\n  %s', ...
            join(reason, sprintf('\n  ')));
    end

    fprintf('referenceSystemCiGate: GREEN\n');
end

% =========================== local functions ===========================

function echoBenchmarks(reportFile)
%ECHOBENCHMARKS Copy the report's BENCHMARKS table to the console.
%
%   WHY THIS EXISTS: A BENCHMARK NOBODY CAN READ IS A BENCHMARK NOBODY
%   REREADS. The numbers are logged by the speed tests at Concise, which
%   puts them in the report and not on the console, and the report leaves
%   the runner only as an uploaded artefact. That is fine for a reader with
%   a browser and useless to a session that has only the job log - and a
%   CI-only session is the normal way this toolbox is developed, not the
%   exceptional one. Rev. 1.247 met this head on: the orbitSunGeometry
%   target had to be derived from the method's WALL TIME, an upper bound,
%   because its median sat in an artefact whose blob host the egress policy
%   refuses with a 403 on CONNECT. A bound that was read beat a median that
%   was assumed, but only because there was no third option. This is it.
%
%   THE LOG LEVEL OF THE TESTS IS DELIBERATELY NOT CHANGED. Raising eleven
%   call sites from Concise to Terse would put every benchmark on every
%   local console for the sake of one consumer, and the tests' choice about
%   their own verbosity is theirs. What changes is CI POLICY, which this
%   file owns and nothing else does - the report is read back after it is
%   written, and the one table a later session needs is echoed.
%
%   IT NEVER FAILS THE RUN. An unreadable or sectionless report is already
%   caught by the gate's own reportFile check; a second verdict raised from
%   a printing helper would be a new way for CI to go red that has nothing
%   to do with the toolbox.
%
%   reportFile   1x1   string   path written by runTestSuite

    if ~isfile(reportFile)
        return
    end

    try
        reportLine = string(splitlines(fileread(reportFile)));
    catch
        return
    end

    % The sections of the section D.3 report are separated by a rule of
    % dashes, so the table runs from its own heading to the next rule. The
    % heading is matched whole: "BENCHMARKS" must not also match a row that
    % happens to mention the word.
    first = find(strcmp(strtrim(reportLine), "BENCHMARKS"), 1);
    if isempty(first)
        return
    end
    isRule = startsWith(strtrim(reportLine), "-----");
    last = first + find(isRule(first + 1:end), 1) - 1;
    if isempty(last)
        last = numel(reportLine);
    end

    fprintf('\nreferenceSystemCiGate: benchmarks as recorded in the report\n');
    fprintf('%s\n', reportLine(first:last));
end
