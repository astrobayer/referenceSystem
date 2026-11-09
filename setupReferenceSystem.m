function status = setupReferenceSystem(options)
%SETUPREFERENCESYSTEM Put the referenceSystem toolbox on the MATLAB path.
%
%   status = setupReferenceSystem() adds the folder containing this file to the
%   MATLAB path, SAVES that path, removes any misconfigured or stale entry
%   belonging to this toolbox, verifies that the package is reachable, reports
%   the external data present in the data pool, prints a summary, and returns
%   what it did. It downloads NOTHING unless Fetch asks for it.
%
%   It is also the INSTALLER: it compiles the MEX gateway and builds the
%   documentation whenever either is missing or out of date, so a fresh zip or
%   git clone takes one command and not three. Every step is idempotent, so
%   calling setup from startup.m costs milliseconds once all is in place.
%
%   THE DEFAULTS INSTALL THE TOOLBOX, NOT THE DATA. Calling this function with
%   no arguments saves the path, builds what is missing and prints the
%   summary, offline, in seconds. The external data - both Earth orientation
%   series and the full kernel set, roughly 700 MB on a first fetch,
%   dominated by the 650 MB small-body kernel - is one named argument away,
%   Fetch="all", and is then skipped file by file on every later run. It goes
%   to the DATA POOL, <pool>/EOP and <pool>/SPICE, and never into the toolbox
%   folder; see referenceSystem.dataFolder for how the pool is found. A failed
%   download does not stop setup; it is recorded and reported.
%
%   status = setupReferenceSystem(Save=false) sets the path for this session only.
%   status = setupReferenceSystem(Fetch="all") fetches EOP and kernels.
%   status = setupReferenceSystem(Fetch="none") downloads nothing (the default).
%   status = setupReferenceSystem(KernelSet="minimal") takes de440s.bsp alone.
%   status = setupReferenceSystem(Verbose=false) prints nothing.
%   status = setupReferenceSystem(Build="always") rebuilds everything.
%   status = setupReferenceSystem(Build="never") only reports, building nothing.
%
%   The quiet, offline, session-only call - what a test or a read-only
%   installation wants - is therefore:
%
%       status = setupReferenceSystem(Save=false, Fetch="none", Verbose=false);
%
%   Run it once, from anywhere:
%
%       run('<path>/referenceSystem/setupReferenceSystem.m')
%
%   This file lives in the distribution folder and not in the package, because
%   the package cannot be addressed before the path is set. It is therefore the
%   one global, unqualified name the toolbox installs, and it carries the
%   product name for exactly that reason (section C.10).
%
% INPUT ARGUMENTS
%   Name              Size   Type      Units  Description
%   ----              ----   ----      -----  -----------
%   options.Save      1x1    logical   -      Call savepath so the entry
%                                             survives a restart. Default true.
%   options.Fetch     1x1    string    -      Data to download before the
%                                            summary: "none" (default),
%                                            "eop", "kernels" or "all".
%                                            NOTHING IS FETCHED BY DEFAULT;
%                                            pass "all" to install the data.
%                                            Anything but "none" needs a
%                                            data pool and refuses without
%                                            one (dataFolder:noDataPool).
%   options.KernelSet 1x1    string    -      How much kernel content, when
%                                            Fetch asks for them: "minimal"
%                                            (~31 MB), "orientation" or "all"
%                                            (default, ~660 MB MEASURED, of
%                                            which the small-body kernel is
%                                            615.8 MB). These accumulate.
%                                            downloadKernels holds the
%                                            catalogue and is the authority
%                                            for every size here.
%   options.KernelSpan 1x1   string    -      Which issue of the planetary
%                                            ephemeris: "short" (default,
%                                            de440s.bsp) or "full"
%                                            (de440.bsp, ~120 MB planning
%                                            figure, still an estimate). These
%                                            are alternatives. The 2.6 GB this
%                                            row carried until now was DE441's
%                                            scale and the catalogue retracted
%                                            it at rev. 1.191; the repair
%                                            stopped one file short of here.
%                                            See downloadKernels.
%                                            NOTE: setup DETECTS the NAIF MICE
%                                            toolkit and reports it, but never
%                                            installs it. See toolkitState.
%   options.Verbose   1x1    logical   -      Print a summary to the command
%                                             window. Default true. It also
%                                             announces each transfer, which a
%                                             615 MB download needs: websave
%                                             shows nothing, and silence is
%                                             indistinguishable from a hang.
%   options.Build     1x1    string    -      Whether to build the MEX gateway
%                                             and the documentation: "auto"
%                                             (default, build when the sources
%                                             are newer than the product),
%                                             "always" or "never".
%   options.DataFolder 1x1   string    -      ROOT OF THE DATA POOL for
%                                             this call, RESOLVED BEFORE
%                                             ANYTHING IS FETCHED: EOP series
%                                             go to <DataFolder>/EOP, kernels
%                                             to <DataFolder>/SPICE. Default ""
%                                             means the pool dataFolder
%                                             resolves (preference, then
%                                             DATAPOOL, then
%                                             READING_DATA_POOL); never the
%                                             toolbox folder. A named folder
%                                             is created when it does not
%                                             exist, reported absolute in
%                                             status.dataFolder, and stored
%                                             nowhere.
%
% OUTPUT ARGUMENTS
%   Name                  Size   Type      Units  Description
%   ----                  ----   ----      -----  -----------
%   status                1x1    struct    -      Fields listed below.
%   .toolboxRoot          1x1    string    -      Folder added to the path.
%   .version              1x1    string    -      Toolbox version now reachable.
%   .matlabRelease        1x1    string    -      Release that ran the setup.
%   .pathAdded            1x1    logical   -      False if it was already there.
%   .pathSaved            1x1    logical   -      True if savepath succeeded.
%   .removedFromPath      Nx1    string    -      Entries removed, possibly empty.
%   .build                1x1    struct    -      What each build step did:
%                                                  .mode, .mexAction,
%                                                  .mexReason,
%                                                  .documentationAction,
%                                                  .searchAction. Actions are
%                                                  "built" or "written",
%                                                  "current", "skipped" or
%                                                  "failed".
%   .documentation        1x1    struct    -      Help browser registration:
%                                                  .registered, .reason,
%                                                  .infoFile, .helpFolder,
%                                                  .searchable.
%   .unlistedFiles        Nx1    string    -      Package files absent from
%                                                 Contents.m, possibly empty.
%   .mex                  1x1    struct    -      The mexInfo report, see there.
%   .dataFolder           1x1    string    -      ABSOLUTE path of the data
%                                                 pool root: the DataFolder
%                                                 option resolved, or the pool
%                                                 dataFolder resolves. "" when
%                                                 no pool is configured, which
%                                                 only Fetch="none" accepts.
%   .dataPool             1x1    struct    -      The location struct of
%                                                 referenceSystem.dataFolder:
%                                                 .root, .source, .SPICE and
%                                                 .EOP; all "" without a pool.
%   .eopSources           Nx1    string    -      EOP series in <pool>/EOP and
%                                                 the tables committed to the
%                                                 toolbox's data/, labelled.
%   .kernels              Nx1    string    -      Kernels in <pool>/SPICE.
%   .leapSecondTable      1x1    string    -      The leap-second source and
%                                                 coverage actually in use.
%   .ready                1x1    logical   -      True when the package resolves.
%
% METHOD
%   DOWNLOADED DATA GOES TO THE DATA POOL AND NEVER INTO THE TOOLBOX (D133,
%   the organisation's DATA_POOL.md). The pool root is resolved by
%   referenceSystem.dataFolder - DataFolder here, else the stored preference,
%   else DATAPOOL, else READING_DATA_POOL - and the products sit under it as
%   SPICE/ and EOP/, spelled by dataFolder alone. Without a pool, Fetch="none"
%   still installs the toolbox and reports that no pool is configured; any
%   other Fetch refuses before a byte moves. The two EOP tables committed to
%   the repository's data/ folder are part of the toolbox, not downloads: they
%   stay, nothing writes there, and the summary lists them beside the pool's.
%
%   DataFolder GOVERNS THIS CALL AND NOT THE TOOLBOX. It is stored nowhere, so
%   a later bare downloadKernels(Mode="download") writes to the pool
%   dataFolder resolves, not to the folder named here. Nothing reads the wrong
%   data as a result - readEop and readEphemeris take explicit paths and
%   discover nothing - but a caller who installs elsewhere has to carry the
%   path onward, which is what status.dataFolder is for; a persistent choice
%   is referenceSystem.dataFolder(path).
%
%   Three things are checked, in the order in which they break a session.
%
%   The MATLAB release comes first, and the floor is R2026a (D120). It is not
%   the oldest release the sources might run on - it is the only one they have
%   ever been RUN on. R2020b stood here from the first revision as an inference
%   from two language features, string scalars in arguments blocks and
%   pagemtimes, and no run on any release below the current one has ever
%   existed. A support claim nobody has tested is worse than a narrower one
%   that has been, because it is believed. The comparison stays numeric on the
%   version string rather than verLessThan or isMATLABReleaseOlderThan, so it
%   works on every release either of those two is missing from - including the
%   ones now refused, which must still reach the error rather than fail to
%   parse it.
%
%   Then the path is cleaned. Two states are wrong and both are removed with a
%   warning: a +referenceSystem folder on the path, which makes every function
%   visible qualified and unqualified at once and reintroduces every shadowing
%   problem the namespace exists to prevent (section C.5 rule 1); and a second
%   distribution folder of this toolbox, which would leave it undefined which
%   copy answers a call.
%
%   Resolution is checked with which and never with exist: a package function is
%   not visible to exist, because the package folder is deliberately not on the
%   path (§C.5 rule 9). Path comparisons fold case on Windows and ignore a
%   trailing separator, so one folder spelled two ways is not read as two
%   installations.
%
%   Only then is this folder added and the package asked to resolve. Setup fails
%   loudly rather than leaving a half-configured path behind, because a path
%   that resolves the wrong copy is the hardest defect in this project to
%   diagnose from a test report.
%
%   Contents.m is the manifest of the package, so a .m file in the package that
%   is not listed there is either undocumented or a leftover from an earlier
%   version that was unpacked over this one. Both are reported. The layering test
%   reads the same manifest for the same reason (D41); one authority, two readers.
%
%   Printing is confined to this function and to the Verbose flag. It is the one
%   place in the toolbox where printing is permitted, because it runs before
%   there is a toolbox to return anything through (section C.10).
%
%   THE DEFAULTS FOLLOW WHO CALLS THIS. The caller is almost always a person
%   running the one documented command on a fresh clone, so the path is saved,
%   the kernel set asked for by a later Fetch is the full one, and the summary
%   is printed. Installing 700 MB is a separate act with a separate cost, so
%   Fetch defaults to "none" - and the summary prints the call that fetches
%   the data whenever none is present, so an empty pool is reported rather
%   than merely left. The test suite passes Save=false, Fetch="none" and
%   Verbose=false, since a suite that saved the path and pulled 700 MB would
%   be changing the machine it is measuring.
%
% ACCURACY
%   Not applicable; the function configures the session and computes no
%   numerical quantity.
%
% ERRORS
%   referenceSystem:setupReferenceSystem:packageMissing
%       The +referenceSystem folder is not next to this file. The distribution
%       folder has been split; unpack it again as one folder.
%   referenceSystem:setupReferenceSystem:unsupportedRelease
%       The MATLAB release is older than R2026a (D120).
%   referenceSystem:setupReferenceSystem:packageNotReachable
%       The folder was added but referenceSystem.toolboxVersion still does not
%       resolve, which means the package folder is unreadable or damaged. The
%       message reports the file it expected and whether that file is on disk.
%   referenceSystem:setupReferenceSystem:otherInstallationResolved
%       The name resolves to a copy of the toolbox outside this folder.
%   referenceSystem:setupReferenceSystem:dataFolderIsAFile
%       DataFolder names an existing file.
%   referenceSystem:setupReferenceSystem:dataFolderNotCreated
%       DataFolder does not exist and could not be created.
%   referenceSystem:dataFolder:noDataPool
%       Fetch is not "none", DataFolder is omitted and no data pool is
%       configured. Raised by dataFolder before anything is downloaded.
%
%   Warnings, all suppressible by identifier:
%   referenceSystem:setupReferenceSystem:packageFolderRemoved
%   referenceSystem:setupReferenceSystem:otherInstallationRemoved
%   referenceSystem:setupReferenceSystem:pathNotSaved
%   referenceSystem:setupReferenceSystem:unlistedPackageFile
%
% REFERENCES
%   Handover section B.8 (directory layout), C.5 (namespace rules),
%   C.10 (installation and this entry point).
%
% EXAMPLE
%   status = setupReferenceSystem();                  % install and save
%   status = setupReferenceSystem(Fetch="all", ...    % and fetch into the pool
%       DataFolder="E:\DATAPOOL");
%   status = setupReferenceSystem(Fetch="none", ...   % quiet and offline
%       Save=false, Verbose=false);
%   t = referenceSystem.iersConstants();
%
% KEYWORDS
%   setup, install, path, namespace, package, getting started
%
% See also RUNTESTSUITE, MEXINFO, TOOLBOXVERSION, DOWNLOADEOP, DOWNLOADKERNELS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 13:45 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.Save (1,1) logical = true
        % D119: "none", NOT "all". Setup installs the toolbox; it does not
        % install the data. See the METHOD note on why D115's default moved.
        options.Fetch (1,1) string {mustBeMember(options.Fetch, ...
            ["none", "eop", "kernels", "all"])} = "none"
        options.KernelSet (1,1) string = "all"
        options.KernelSpan (1,1) string = "short"
        options.Verbose (1,1) logical = true
        options.Build (1,1) string {mustBeMember(options.Build, ...
            ["auto", "always", "never"])} = "auto"
        options.DataFolder (1,1) string = ""
    end

    toolboxRoot = string(fileparts(mfilename('fullpath')));
    packageFolder = fullfile(toolboxRoot, '+referenceSystem');
    if ~isfolder(packageFolder)
        error('referenceSystem:setupReferenceSystem:packageMissing', ...
            ['The package folder %s does not exist. This file must stay in the ', ...
            'distribution folder next to +referenceSystem.'], packageFolder);
    end

    % D120: R2026a. 26.1 is its version number; see the METHOD block for why
    % the floor is the tested release and not the oldest plausible one.
    minimumRelease = 26.1;
    releaseNumber = str2double(regexp(version(), '^\d+\.\d+', 'match', 'once'));
    if releaseNumber < minimumRelease
        error('referenceSystem:setupReferenceSystem:unsupportedRelease', ...
            ['referenceSystem requires MATLAB R2026a or later; this is %s. ', ...
            'R2026a is the only release the toolbox has been run on (D120).'], ...
            version('-release'));
    end

    removedFromPath = cleanPath(toolboxRoot);

    pathAdded = ~any(normalizePath(splitPath()) == normalizePath(toolboxRoot));
    if pathAdded
        addpath(char(toolboxRoot));
    end

    % which resolves a package-qualified name; exist cannot, because the package
    % folder is deliberately not on the path (§C.5 rule 9, measured rev. 1.30).
    resolvedFile = string(which('referenceSystem.toolboxVersion'));
    expectedFile = fullfile(packageFolder, 'toolboxVersion.m');
    if strlength(resolvedFile) == 0
        error('referenceSystem:setupReferenceSystem:packageNotReachable', ...
            ['%s is on the path but referenceSystem.toolboxVersion does not ', ...
            'resolve.\n  expected file : %s\n  file on disk  : %s\n', ...
            'Try "rehash toolboxcache" and check that the folder is readable.'], ...
            toolboxRoot, expectedFile, string(isfile(expectedFile)));
    end
    if ~startsWith(normalizePath(resolvedFile), normalizePath(toolboxRoot))
        error('referenceSystem:setupReferenceSystem:otherInstallationResolved', ...
            ['referenceSystem.toolboxVersion resolves to %s, which is outside ', ...
            '%s. Remove the other installation from the path.'], ...
            resolvedFile, toolboxRoot);
    end

    pathSaved = false;
    if options.Save
        pathSaved = savepath() == 0;
        if ~pathSaved
            warning('referenceSystem:setupReferenceSystem:pathNotSaved', ...
                ['The path was set for this session but could not be saved. ', ...
                'Check write access to the pathdef.m in use.']);
        end
    end

    unlistedFile = unlistedPackageFiles(packageFolder);
    if ~isempty(unlistedFile)
        warning('referenceSystem:setupReferenceSystem:unlistedPackageFile', ...
            ['%d file(s) in the package are not listed in Contents.m, the first ', ...
            'being %s.m. A file left behind by an earlier version still answers ', ...
            'calls and still shadows nothing you can see. Unpack the toolbox into ', ...
            'an empty folder, or delete the file.'], numel(unlistedFile), ...
            unlistedFile(1));
    end

    % RESOLVED HERE, WHICH IS BEFORE performFetch AND BEFORE ANY REPORT READS
    % IT. Both downloads and both of the state readers below take the folder as
    % an argument, so this line is the single place the location is decided and
    % nothing downstream can pick a different one.
    [dataFolder, dataPool] = resolveDataFolder(options.DataFolder, ...
        options.Fetch);

    % SETUP IS THE INSTALLER. The toolbox ships as a zip or a git clone, so
    % nothing stands between the repository and the user: whatever has to
    % happen before the toolbox works has to happen here. Two things do - the
    % MEX gateway and the documentation - and until this revision setup only
    % told the user to go and do them, which is three commands where one will
    % do.
    %
    % IT IS IDEMPOTENT, AND THAT IS WHAT MAKES IT SAFE TO CALL FROM startup.m.
    % Each step compares its inputs against its output and does nothing when
    % the output is newer, so a warm session costs milliseconds while a fresh
    % clone costs a minute. Build=always forces both; Build=never restores the
    % report-only behaviour, which is what a diagnostic run or a read-only
    % installation wants.
    build = performBuildSteps(toolboxRoot, options.Build);

    mexState = referenceSystem.mexInfo();
    if ~mexState.built
        warning('referenceSystem:setupReferenceSystem:mexNotBuilt', ...
            ['The MEX gateway is not built, so leap seconds, time-scale ', ...
            'conversion and the fundamental arguments are unavailable. ', ...
            'Setup tried and did not succeed: %s. Run ', ...
            'referenceSystem.buildMex() to see the compiler output in full; ', ...
            'it needs a C compiler selected with "mex -setup C".'], ...
            build.mexReason);
    end

    % Section C.10: every prompt that adds a prerequisite extends setup in the
    % same session. A doc set that has silently stopped being reachable is
    % worse than none.
    documentation = documentationState(toolboxRoot);
    if ~documentation.registered
        warning('referenceSystem:setupReferenceSystem:documentationNotRegistered', ...
            ['"doc referenceSystem" will not open the Getting Started page: ', ...
            '%s. MATLAB finds custom documentation through an info.xml on the ', ...
            'path, whose help_location names the folder holding the HTML and ', ...
            'helptoc.xml. Custom documentation does not display in MATLAB ', ...
            'Online at all.'], documentation.reason);
    end

    % SECTION C.10 AGAIN: P22b adds a prerequisite, so setup learns to satisfy
    % it in the same session. The fetch runs AFTER the path is set - it calls
    % package functions - and BEFORE eopSource is read, so a series downloaded
    % in this call is reported by this call rather than by the next one.
    fetch = performFetch(dataPool, options);

    report = struct( ...
        'toolboxRoot', toolboxRoot, ...
        'version', referenceSystem.toolboxVersion().version, ...
        'matlabRelease', string(version('-release')), ...
        'pathAdded', pathAdded, ...
        'pathSaved', pathSaved, ...
        'removedFromPath', removedFromPath, ...
        'unlistedFiles', unlistedFile, ...
        'dataFolder', string(dataFolder), ...
        'dataPool', dataPool, ...
        'eopSources', eopSource(dataPool.EOP, fullfile(toolboxRoot, 'data')), ...
        'kernels', kernelState(dataPool.SPICE), ...
        'toolkit', toolkitState(), ...
        'fetch', fetch, ...
        'mex', mexState, ...
        'leapSecondTable', mexState.leapSecondsSummary, ...
        'documentation', documentation, ...
        'build', build, ...
        'ready', true);

    if options.Verbose
        printSummary(report);
    end

    % ASSIGNED ONLY WHEN ASKED FOR. Called as a statement, this function
    % otherwise set ans to a struct that was then echoed in full immediately
    % after the Verbose summary had already said all of it - twice the output
    % and the second copy the less readable one.
    if nargout > 0
        status = report;
    end
end

function removedFromPath = cleanPath(toolboxRoot)
%CLEANPATH Remove package folders and other installations of this toolbox.

    pathEntry = splitPath();
    normalizedEntry = normalizePath(pathEntry);
    normalizedRoot = normalizePath(toolboxRoot);
    isPackageFolder = endsWith(normalizedEntry, normalizePath("+referenceSystem"));
    isOtherRoot = false(size(pathEntry));
    for k = 1:numel(pathEntry)
        isOtherRoot(k) = ~isPackageFolder(k) && normalizedEntry(k) ~= normalizedRoot && ...
            isfolder(fullfile(pathEntry(k), '+referenceSystem'));
    end

    if any(isPackageFolder)
        warning('referenceSystem:setupReferenceSystem:packageFolderRemoved', ...
            ['Removed %d package folder(s) from the path. Only the distribution ', ...
            'folder belongs there; a +referenceSystem folder on the path makes ', ...
            'every function visible both qualified and unqualified.'], ...
            sum(isPackageFolder));
    end
    if any(isOtherRoot)
        warning('referenceSystem:setupReferenceSystem:otherInstallationRemoved', ...
            ['Removed %d other installation(s) of referenceSystem from the path, ', ...
            'the first being %s. Two copies leave it undefined which one answers ', ...
            'a call.'], sum(isOtherRoot), pathEntry(find(isOtherRoot, 1)));
    end

    removedFromPath = pathEntry(isPackageFolder | isOtherRoot);
    if ~isempty(removedFromPath)
        rmpath(char(join(removedFromPath, pathsep)));
    end
end

function unlisted = unlistedPackageFiles(packageFolder)
%UNLISTEDPACKAGEFILES Package files that Contents.m does not mention.

    unlisted = strings(0, 1);
    contentsFile = fullfile(packageFolder, 'Contents.m');
    if ~isfile(contentsFile)
        return
    end

    packageFile = dir(fullfile(packageFolder, '*.m'));
    presentName = erase(string({packageFile.name}), ".m");
    presentName = presentName(presentName ~= "Contents");

    listedToken = regexp(string(fileread(contentsFile)), '^%\s{3,}(\w+)\s+-\s', ...
        'tokens', 'lineanchors');
    if isempty(listedToken)
        return
    end
    listedName = vertcat(listedToken{:});

    unlisted = setdiff(presentName(:), listedName(:));
end

function build = performBuildSteps(toolboxRoot, mode)
%PERFORMBUILDSTEPS Compile the gateway and build the documentation, as needed.
%   Every step is wrapped, because A BUILD FAILURE MUST NOT STOP SETUP. The
%   path is the one thing setup absolutely has to get right, and a toolbox on
%   the path with no MEX gateway still gives the user a working namespace,
%   readable help, and an error that names the missing piece. A setup that
%   refused to finish because a compiler was absent would give them none of
%   that.

    build = struct('mode', mode, ...
        'mexAction', "skipped", 'mexReason', "building was turned off", ...
        'documentationAction', "skipped", 'searchAction', "skipped");
    if mode == "never"
        return
    end

    [needed, build.mexReason] = mexRebuildNeeded(toolboxRoot, mode);
    if needed
        try
            referenceSystem.buildMex();
            build.mexAction = "built";
        catch cause
            build.mexAction = "failed";
            build.mexReason = string(cause.message);
            % IT WARNS (rev. 1.101). Setup is quiet by default, it deliberately
            % does not stop on a build failure, and it returns ready = 1
            % because the path is what ready means - so before this warning
            % existed a failed compile produced a struct that looked entirely
            % healthy, and the only trace was a field nobody had a reason to
            % open. Four consecutive test reports were then read as evidence
            % about C code that was not in the binary.
            %
            % The documentation build already warned on failure. The MEX build,
            % which matters far more, did not. That asymmetry was the defect.
            warning('referenceSystem:setupReferenceSystem:mexBuildFailed', ...
                ['The MEX gateway could not be built, so the compiled ', ...
                'gateway on this machine does NOT match the C sources. ', ...
                'Anything measured against it describes the old binary.\n\n%s'], ...
                build.mexReason);
        end
    else
        build.mexAction = "current";
    end

    try
        report = referenceSystem.buildDocumentation('ToolboxRoot', toolboxRoot, ...
            'Force', mode == "always");
        build.documentationAction = report.referenceAction;
        build.searchAction = report.searchAction;
    catch cause
        build.documentationAction = "failed";
        warning('referenceSystem:setupReferenceSystem:documentationBuildFailed', ...
            ['The documentation could not be built: %s. The toolbox itself ', ...
            'is unaffected; only the function reference page and the Help ', ...
            'browser entry are out of date.'], cause.message);
    end
end

function [needed, reason] = mexRebuildNeeded(toolboxRoot, mode)
%MEXREBUILDNEEDED Whether the gateway must be compiled, and why.
%   THE STALE-BINARY CASE IS THE ONE WORTH THE CODE. A missing binary announces
%   itself: every call fails with gatewayMissing. A binary compiled from older
%   C sources does not - it runs, it returns numbers, and the user is executing
%   one version of the algorithm from MATLAB and another from C. Under git that
%   is not hypothetical: pulling a branch that touched mex/ leaves exactly this
%   state, the binary is a build artefact and therefore untracked, and nothing
%   else in the toolbox would notice.

    if mode == "always"
        needed = true;
        reason = "a full rebuild was requested";
        return
    end

    if ~referenceSystem.mexInfo().built
        needed = true;
        reason = "the gateway is not compiled on this machine";
        return
    end

    % THE DIGEST DECIDES, NOT THE CLOCK (rev. 1.100). Three consecutive
    % revisions shipped a changed C source and none rebuilt: a ZIP entry
    % stores naive local time, so an archive built on a UTC machine and
    % unpacked on a UTC+2 one produces sources that look two hours OLDER than
    % they are. mex/rsApi.c arrived stamped 15:44 against a gateway built at
    % 17:26. The timestamp comparison below is kept only as a fallback for the
    % case where no manifest exists yet.
    manifestFile = fullfile(toolboxRoot, '+referenceSystem', 'private', ...
        'mexGateway.sources');
    if isfile(manifestFile)
        recorded = str2double(strtrim(fileread(manifestFile)));
        current = referenceSystem.mexSourceDigest(toolboxRoot);
        needed = ~isequal(recorded, current);
        if needed
            reason = "a C source differs from the one the gateway was built from";
        else
            reason = "the gateway matches every C source byte for byte";
        end
        return
    end

    binary = dir(fullfile(toolboxRoot, '+referenceSystem', 'private', ...
        ['mexGateway.' mexext]));
    % THE TOP OF mex/ IS GLOBBED SEPARATELY, AND THAT IS THE WHOLE DEFECT
    % (rev. 1.95). This read only 'mex/**/*.c'. Whether MATLAB's ** spans zero
    % folder levels or one or more is not something to be confident about from
    % memory, and the answer decides whether mexGateway.c, rsCore.c and
    % rsCheb.c are seen at all. They are the ONLY files here that ever change:
    % sofa/ and iers/ are vendored and frozen, so if ** skips the top level
    % then max(datenum) is pinned to timestamps that never move and the
    % staleness check can never fire. That matches every observation - three
    % separate changes to top-level sources produced no rebuild, and both
    % rebuilds that did happen followed a fresh install with no binary present,
    % which takes the earlier branch.
    %
    % The union is correct under either reading of **, and duplicates are
    % harmless because only the maximum is used. Not diagnosing which reading
    % is right is deliberate: the fix should not depend on the answer.
    source = [dir(fullfile(toolboxRoot, 'mex', '*.c')); ...
        dir(fullfile(toolboxRoot, 'mex', '*.h')); ...
        dir(fullfile(toolboxRoot, 'mex', '**', '*.c')); ...
        dir(fullfile(toolboxRoot, 'mex', '**', '*.h'))];
    if isempty(binary) || isempty(source)
        needed = false;
        reason = "the gateway reports built and there is no manifest to compare";
        return
    end

    needed = max([source.datenum]) > binary.datenum;
    if needed
        reason = "a C source is newer than the compiled gateway";
    else
        reason = "the compiled gateway is newer than every C source";
    end
end

function state = documentationState(toolboxRoot)
%DOCUMENTATIONSTATE Whether "doc referenceSystem" can reach the help pages.
%   Three files have to line up and any one of them missing is silent: info.xml
%   on the path, the folder its help_location names, and a helptoc.xml INSIDE
%   that folder. The check reports which one is absent rather than that
%   something is, because the three have three different repairs.
%
%   It reports and never repairs. Building the search database is a separate,
%   slow step the user runs deliberately (builddocsearchdb), and this function
%   runs on every setup.

    infoFile = fullfile(toolboxRoot, 'info.xml');
    state = struct('registered', false, 'reason', "", ...
        'infoFile', string(infoFile), 'helpFolder', "", 'searchable', false);

    if ~isfile(infoFile)
        state.reason = "there is no info.xml in " + string(toolboxRoot);
        return
    end

    location = regexp(fileread(infoFile), ...
        '<help_location>\s*([^<]*?)\s*</help_location>', 'tokens', 'once');
    if isempty(location) || isempty(strip(string(location{1})))
        state.reason = "info.xml names no help_location";
        return
    end

    helpFolder = fullfile(toolboxRoot, strip(string(location{1})));
    state.helpFolder = string(helpFolder);
    if ~isfolder(helpFolder)
        state.reason = "info.xml names a help_location that does not exist, " + ...
            string(helpFolder);
        return
    end
    if ~isfile(fullfile(helpFolder, 'helptoc.xml'))
        state.reason = "there is no helptoc.xml in " + string(helpFolder);
        return
    end

    state.registered = true;
    % The database folder carries its version - helpsearch-v3, helpsearch-v4
    % and onward - and the number changes between releases, so it is
    % discovered rather than enumerated. Naming two versions was already wrong
    % for the third.
    found = dir(fullfile(helpFolder, 'helpsearch*'));
    state.searchable = ~isempty(found) && any([found.isdir]);
end

function [dataFolder, dataPool] = resolveDataFolder(requested, fetchRequest)
%RESOLVEDATAFOLDER Decide which data pool this call uses, before any fetch.
%
%   AN OMISSION AND A CHOICE ARE DISTINGUISHABLE, WHICH IS THE D113 IDIOM.
%   The default is the empty string rather than a path, so this function can
%   tell "the caller said nothing" from "the caller named a folder", and the
%   two get different treatment: a NAMED folder is created when absent,
%   because naming it is a deliberate act; an OMITTED one is whatever
%   referenceSystem.dataFolder resolves, and no folder of setup's own.
%
%   D133: WITHOUT A POOL, ONLY AN OFFLINE CALL PROCEEDS. Fetch="none" writes
%   nothing, so refusing it would make the toolbox uninstallable on a machine
%   that has not chosen a pool yet; it proceeds with an empty location and the
%   summary says no pool is configured. Any other Fetch would have to write
%   somewhere, and the contract leaves no somewhere: dataFolder's noDataPool
%   propagates, before a byte moves. There is no toolbox-folder fallback.
%
%   A PATH THAT IS ALREADY A FILE IS REFUSED RATHER THAN WORKED AROUND. mkdir
%   would fail later, inside a download, with the message of whichever transfer
%   happened to go first; the caller would then be reading about a kernel when
%   the defect is in their argument.

    if strlength(strtrim(requested)) == 0
        try
            [dataFolder, dataPool] = referenceSystem.dataFolder();
        catch failure
            if failure.identifier ~= "referenceSystem:dataFolder:noDataPool" ...
                    || fetchRequest ~= "none"
                rethrow(failure);
            end
            dataFolder = "";
            dataPool = struct('root', "", 'source', "", 'SPICE', "", 'EOP', "");
        end
        return
    end

    dataFolder = string(strtrim(requested));
    if isfile(dataFolder)
        error('referenceSystem:setupReferenceSystem:dataFolderIsAFile', ...
            ['DataFolder "%s" is an existing FILE, so no data pool can be ', ...
            'made there. Name a directory, or a path that does not exist ', ...
            'yet.'], dataFolder);
    end

    if ~isfolder(dataFolder)
        [made, message] = mkdir(char(dataFolder));
        if ~made
            error('referenceSystem:setupReferenceSystem:dataFolderNotCreated', ...
                'DataFolder "%s" could not be created: %s', dataFolder, message);
        end
    end

    % ABSOLUTE, AND THE PRODUCT FOLDERS FROM THEIR ONE AUTHORITY. dataFolder
    % makes the path absolute through what() and spells SPICE/ and EOP/; the
    % DataPool argument uses the folder for this call and stores nothing.
    [dataFolder, dataPool] = referenceSystem.dataFolder(DataPool = dataFolder);
end

function fetch = performFetch(dataPool, options)
%PERFORMFETCH Download the external data the caller asked for, and only that.
%   Nothing is fetched unless Fetch says so. The two sources are handled by the
%   package functions that own them - downloadEop and downloadKernels - rather
%   than by HTTP written here, so there is one place that knows where an EOP
%   series lives and one that knows where a kernel does.
%
%   EVERY REQUESTED ITEM IS ATTEMPTED AND EVERY FAILURE IS RECORDED. Setup must
%   not abort on a network error: a machine behind a proxy still wants its path
%   set, its MEX built and its summary printed. The failures come back in the
%   struct and, when Verbose, in the summary.

    fetch = struct('requested', options.Fetch, 'eop', strings(0, 1), ...
        'kernelManifest', table(), 'failures', strings(0, 1));

    if options.Fetch == "none"
        return
    end

    if ismember(options.Fetch, ["eop", "all"])
        % BOTH SERIES, BECAUSE THEY ANSWER DIFFERENT QUESTIONS. EOP 20 C04 is
        % the final smoothed solution and stops well short of today;
        % finals2000A carries the rapid values and the predictions that cover
        % the gap. A session given only one of them discovers the other was
        % needed when an arc falls off the end of a table.
        for series = ["EOP 20 C04", "finals2000A"]
            try
                file = referenceSystem.downloadEop(series, ...
                    CacheDir = dataPool.EOP);
                fetch.eop(end+1, 1) = string(file);
            catch failure
                fetch.failures(end+1, 1) = series + ": " + ...
                    string(failure.message);
            end
        end
    end

    if ismember(options.Fetch, ["kernels", "all"])
        announce = @(varargin) [];
        if options.Verbose
            announce = @announceTransfer;
        end
        % downloadKernels WARNS on a partial fetch and returns the manifest;
        % it does not throw. Rev. 1.134 had it throwing, and the first real run
        % showed why that was wrong: the four kernels that arrived were on
        % disk but the manifest describing them was destroyed by the
        % exception, so this function reported "0 kernels" (decision D98). The
        % warning is suppressed here only because the FAILED rows are reported
        % individually below, which is strictly more information.
        previousWarning = warning('off', ...
            'referenceSystem:downloadKernels:incompleteFetch');
        restoreWarning = onCleanup(@() warning(previousWarning));
        try
            fetch.kernelManifest = referenceSystem.downloadKernels( ...
                Set = options.KernelSet, Span = options.KernelSpan, ...
                Mode = "download", ...
                CacheDir = dataPool.SPICE, Announce = announce);
            failedRow = startsWith(fetch.kernelManifest.Status, "FAILED");
            for k = find(failedRow).'
                fetch.failures(end+1, 1) = fetch.kernelManifest.File(k) + ...
                    ": " + extractAfter(fetch.kernelManifest.Status(k), ...
                    "FAILED | ");
            end
        catch failure
            % Only reached if downloadKernels fails before it has a manifest,
            % e.g. an unwritable cache folder.
            fetch.failures(end+1, 1) = "kernels: " + string(failure.message);
        end
    end

    if ~isempty(fetch.failures)
        warning('referenceSystem:setupReferenceSystem:fetchIncomplete', ...
            ['%d of the requested downloads did not complete. Setup itself ', ...
            'succeeded; status.fetch.failures carries the reasons. The ', ...
            'bundled SOFA ephemeris provider needs no downloads at all.'], ...
            numel(fetch.failures));
    end
end

function count = kernelsOnDisk(fetch)
%KERNELSONDISK Rows of the manifest whose kernel is now present.
%   The manifest is an EMPTY table when only EOP was requested, and indexing a
%   variable of an empty table is an error rather than an empty answer - so the
%   height is checked first instead of being assumed non-zero.

    count = 0;
    if height(fetch.kernelManifest) == 0
        return
    end
    count = sum(ismember(fetch.kernelManifest.Status, ["fetched", "present"]));
end

function announceTransfer(name, approximateBytes, index, total)
%ANNOUNCETRANSFER Say what is about to move, since websave shows nothing.
%   A 650 MB transfer with no output is indistinguishable from a hang. This
%   printer is passed INTO the package function rather than living in it,
%   because library code in this toolbox does not print (section C.1).

    fprintf('  fetching %d/%d  %-26s ~%.0f MB\n', index, total, name, ...
        approximateBytes/1048576);
end

function state = toolkitState()
%TOOLKITSTATE Report whether the NAIF MICE toolkit is available.
%
%   DETECTION AND AN INSTRUCTION, NEVER AN INSTALLATION. Fetching a data file
%   is one thing; downloading and installing a platform-specific binary toolkit
%   into somebody's MATLAB path is another. MICE ships as compiled MEX, so an
%   installer here would have to choose the right platform package, unpack it,
%   modify the path persistently, and then be unable to verify the one thing
%   that matters - that the binary matches this MATLAB on this machine. A
%   half-installed toolkit fails later, somewhere else, in a way that points
%   nowhere near setup. Many sites also manage MICE centrally and pin its
%   version.
%
%   So this reports, and says where to get it. Nothing in the toolbox requires
%   MICE: the bundled SOFA provider and WGCCRE Table 1 work without it, and the
%   kernel-backed tests report INC rather than failing.

    if exist('cspice_tkvrsn', 'file') == 2 || exist('cspice_tkvrsn', 'file') == 3
        try
            state = "MICE " + string(cspice_tkvrsn('TOOLKIT')) + " on the path";
        catch
            state = "cspice_tkvrsn found but not callable";
        end
        return
    end
    state = "not found (optional; " + ...
        "https://naif.jpl.nasa.gov/naif/toolkit_MATLAB.html)";
end

function found = kernelState(spiceFolder)
%KERNELSTATE SPICE kernels present in <pool>/SPICE, with their size and age.
%   The same C.10 obligation eopSource discharges for the Earth orientation
%   series: a session running against a kernel it forgot it had should say so
%   here, where it is cheap to notice.

    found = strings(0, 1);
    if strlength(spiceFolder) == 0 || ~isfolder(spiceFolder)
        return
    end

    candidate = [dir(fullfile(spiceFolder, '*.bsp')); ...
        dir(fullfile(spiceFolder, '*.bpc')); ...
        dir(fullfile(spiceFolder, '*.tpc')); ...
        dir(fullfile(spiceFolder, '*.tf'))];
    candidate = candidate(~[candidate.isdir]);

    for k = 1:numel(candidate)
        age = days(datetime('now') - ...
            datetime(candidate(k).datenum, 'ConvertFrom', 'datenum'));
        found(end+1, 1) = sprintf('%s (%.1f MB, %.0f day(s) old)', ...
            candidate(k).name, candidate(k).bytes/1048576, age); %#ok<AGROW>
    end
end

function found = eopSource(eopFolder, committedFolder)
%EOPSOURCE Earth orientation series present, with their size and age.
%   The section C.10 obligation attached to prompt P5: setup reports the EOP
%   sources actually in use, so that a session which is quietly running on a
%   two-year-old cached series says so at the point where it is cheap to
%   notice, rather than at the point where an arc falls off the end of the
%   table.
%
%   Only the file name, size and modification time are read. Parsing the series
%   here would duplicate readEop, which owns format identification, and would
%   make setup fail on a file that is merely stale rather than broken.
%
%   TWO PLACES, LABELLED, AND THE LABEL IS THE POINT (D133). Downloads are in
%   <pool>/EOP. The repository also COMMITS two tables to its data/ folder;
%   they are part of the toolbox, not downloads, and stay. Both are listed,
%   each with where it is, so a session reading a committed table of a given
%   age is told so rather than left to assume it is reading a fresh download.

    found = [eopFilesIn(eopFolder, "pool"); ...
        eopFilesIn(committedFolder, "committed")];
end

function found = eopFilesIn(folder, label)
%EOPFILESIN The EOP series in one folder, each line tagged with its place.

    found = strings(0, 1);
    if strlength(string(folder)) == 0 || ~isfolder(folder)
        return
    end

    candidate = [dir(fullfile(folder, 'eopc04*')); ...
        dir(fullfile(folder, 'finals*')); ...
        dir(fullfile(folder, 'EOP*'))];
    candidate = candidate(~[candidate.isdir]);
    % ONE LINE PER FILE. Windows matches 'EOP*' case-insensitively, so it
    % found eopc04_* a second time and the summary listed that file twice.
    [~, first] = unique(string({candidate.name}), 'stable');
    candidate = candidate(first);

    for k = 1:numel(candidate)
        age = days(datetime('now') - ...
            datetime(candidate(k).datenum, 'ConvertFrom', 'datenum'));
        found(end+1, 1) = sprintf('%s (%s, %.1f MB, %.0f day(s) old)', ...
            candidate(k).name, label, candidate(k).bytes/1048576, age); %#ok<AGROW>
    end
end

function normalized = normalizePath(rawPath)
%NORMALIZEPATH Comparable form of a folder name.
%   Trailing separators are dropped and, on Windows, case is folded, so that
%   two spellings of the same folder do not look like two installations.

    normalized = regexprep(string(rawPath), '[\\/]+$', '');
    if ispc()
        normalized = lower(normalized);
    end
end

function pathEntry = splitPath()
%SPLITPATH The MATLAB path as a column of non-empty folder names.

    pathEntry = split(string(path()), pathsep);
    pathEntry = pathEntry(strlength(pathEntry) > 0);
end

function printSummary(status)
%PRINTSUMMARY The Verbose report; the only printing in this toolbox.

    fprintf('referenceSystem %s is ready.\n', status.version);
    fprintf('  root    : %s\n', status.toolboxRoot);
    fprintf('  MATLAB  : %s\n', status.matlabRelease);
    fprintf('  path    : %s%s\n', addedText(status.pathAdded), savedText(status.pathSaved));
    for k = 1:numel(status.removedFromPath)
        fprintf('  removed : %s\n', status.removedFromPath(k));
    end
    for k = 1:numel(status.unlistedFiles)
        fprintf('  unlisted: %s.m is in the package but not in Contents.m\n', ...
            status.unlistedFiles(k));
    end
    if strlength(status.dataFolder) == 0
        fprintf(['  data    : NO DATA POOL CONFIGURED. Set DATAPOOL, or call ', ...
            'referenceSystem.dataFolder(path) once\n']);
    else
        fprintf('  data    : %s (from %s)\n', status.dataFolder, ...
            status.dataPool.source);
    end
    fprintf('  MEX     : %s\n', status.mex.summary);
    fprintf('  leapsec : %s\n', status.leapSecondTable);
    % "mex built (the gateway is not compiled on this machine)" read as a
    % contradiction in the first real install run: the parenthetical is the
    % reason the rebuild was TRIGGERED, rendered in the present tense as
    % though it were the state afterwards. It is now introduced as a cause.
    if status.build.mexAction == "built"
        fprintf('  build   : mex rebuilt, because %s; reference %s, search %s\n', ...
            status.build.mexReason, status.build.documentationAction, ...
            status.build.searchAction);
    else
        fprintf('  build   : mex %s (%s), reference %s, search %s\n', ...
            status.build.mexAction, status.build.mexReason, ...
            status.build.documentationAction, status.build.searchAction);
    end
    if status.documentation.registered
        fprintf('  doc     : registered, %s\n', status.documentation.helpFolder);
    else
        fprintf('  doc     : NOT registered - %s\n', status.documentation.reason);
    end
    fprintf('  toolkit : %s\n', status.toolkit);
    if ~isempty(status.kernels)
        for k = 1:numel(status.kernels)
            fprintf('  kernel  : %s\n', status.kernels(k));
        end
    end
    if status.fetch.requested ~= "none"
        fprintf('  fetched : %d EOP file(s), %d kernel(s), %d failure(s)\n', ...
            numel(status.fetch.eop), kernelsOnDisk(status.fetch), ...
            numel(status.fetch.failures));
        for k = 1:numel(status.fetch.failures)
            fprintf('  FAILED  : %s\n', status.fetch.failures(k));
        end
    elseif isempty(status.kernels) || isempty(status.eopSources)
        % D119 OWES D115 THIS LINE. Decoupling setup from the fetch brings back
        % the state rev. 1.204 was written against - an installed toolbox with
        % an empty data folder - and the fix for that was never the download
        % itself, it was ending the SILENCE about it. The next command is
        % printed rather than left in the documentation.
        fprintf(['  data    : nothing in the pool yet. To fetch it:\n', ...
            '            setupReferenceSystem(Fetch = "all")   %% ~700 MB\n', ...
            '            referenceSystem.dataFolder(path)      %% to name the pool first\n']);
    end
    if isempty(status.eopSources)
        fprintf('  EOP     : none found; supply a series to readEop\n');
    else
        for k = 1:numel(status.eopSources)
            fprintf('  EOP     : %s\n', status.eopSources(k));
        end
    end
    fprintf('  tests   : referenceSystem.runTestSuite()\n');
end

function text = addedText(pathAdded)
%ADDEDTEXT Wording for whether the folder had to be added.

    if pathAdded
        text = "added for this session";
    else
        text = "already present";
    end
end

function text = savedText(pathSaved)
%SAVEDTEXT Wording for whether the path was stored permanently.

    if pathSaved
        text = ", saved permanently";
    else
        text = "";
    end
end
