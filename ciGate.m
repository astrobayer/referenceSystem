function ciGate()
%CIGATE The ONE CI entry point: install, run the suite, judge, or error.
%
%   ciGate()
%
%   Called by the CI (`matlab-actions/run-command`: `ciGate`) and usable as a
%   local postflight (`matlab -batch ciGate`). It is the gate that protects
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
%   referenceSystem:ciGate:red
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
%   %   matlab -batch "ciGate"
%   ciGate();
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
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-08-21 15:20 (CEST, UTC+02:00)
% Revised: 2026-08-21 15:20 (CEST, UTC+02:00)
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
    % Build="always": a fresh checkout carries no compiled gateway, and
    %   forcing the build makes the MEX compile itself part of the gate
    %   rather than a side effect of "auto" that a cache could skip.
    setupReferenceSystem('Save', false, 'Fetch', "kernels", ...
        'KernelSet', "all", 'KernelSpan', "short", 'Build', "always", ...
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
    fprintf(['\nciGate: %d tests, %d passed, %d failed, %d skipped by ', ...
        'design, %d unexpected filters\n'], numel(results), ...
        sum([results.Passed]), failedCount, summary.intendedSkip, ...
        summary.unexpectedFilter);
    fprintf('ciGate: report at %s\n', reportFile);

    if ~isempty(reason)
        error('referenceSystem:ciGate:red', 'ciGate RED:\n  %s', ...
            join(reason, sprintf('\n  ')));
    end

    fprintf('ciGate: GREEN\n');
end
