function buildReport = buildMex(options)
%BUILDMEX Compile the package-private MEX gateway against the bundled SOFA source.
%
%   buildReport = buildMex()
%   buildReport = buildMex(Name, Value)
%
%   Compiles every .c file at the top of mex/ together with every .c file in
%   mex/sofa/ into one MEX file in +referenceSystem/private/, where it is
%   callable from inside the package and from nowhere else. Run it once after
%   unpacking the toolbox, and again whenever the C sources change.
%
% INPUT ARGUMENTS
%   (none) The sources, the output folder and the SOFA release are all fixed by
%   the layout of the distribution; nothing about the build is a caller's
%   choice except the two switches below.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name       Size   Type      Default  Description
%   ----       ----   ----      -------  -----------
%   OpenMp     1x1    logical   true     Attempt an OpenMP build. On failure
%                                        the serial build is used instead and
%                                        the fallback is reported.
%   Debug      1x1    logical   false    Build with -g and without -DNDEBUG.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type      Units  Description
%   ----                ----   ----      -----  -----------
%   buildReport         1x1    struct    -      Fields below.
%   .file               1x1    string    -      The MEX file written.
%   .openMp             1x1    logical   -      Whether the BUILT BINARY has
%                                                OpenMP, read back from the
%                                                gateway, not inferred from the
%                                                build command succeeding.
%   .openMpFlags        1x1    string    -      Which flag spelling the
%                                                platform actually honoured,
%                                                or "" where OpenMP is absent.
%   .openMpFallback     1x1    string    -      Why OpenMP is absent, or "".
%   .sourceCount        1x1    double    -      Translation units compiled.
%   .sofaRelease        1x1    string    -      Release reported by the gateway.
%   .leapSecondsSummary 1x1    string    -      Coverage of the leap-second
%                                               table the new build exposes.
%   .duration           1x1    double    s      Wall-clock build time.
%
% METHOD
%   The build is a plain mex call with three deliberate properties.
%
%   The output goes to +referenceSystem/private/. A private folder is not on
%   the MATLAB path and is visible only to the functions of its parent, so the
%   gateway cannot be called by a user or by a test, and everything a caller
%   legitimately needs from it is re-exported by mexInfo (handover section C.4).
%
%   The misconfiguration of section C.5 rule 1 is rejected before anything is
%   compiled. With +referenceSystem itself on the path every function becomes
%   visible both qualified and unqualified, which reintroduces every shadowing
%   problem the namespace was adopted to remove; building on top of that would
%   produce a working binary in a broken installation.
%
%   OpenMP is attempted and its absence is not an error. Apple clang ships
%   without it, so on macOS the serial build is used directly rather than after
%   a failed attempt, and the reason is reported rather than printed. Nothing
%   in this function prints; section B.1 principle 10 has one exception in this
%   toolbox and it is setupReferenceSystem, not this function.
%
%   The result is verified by asking mexInfo, which queries the gateway itself,
%   so a build that produced a file the process cannot load is a failure here
%   rather than a puzzle later.
%
% ACCURACY
%   Not applicable; the function compiles code and computes no numerical
%   quantity. The numerical accuracy of what it produces is that of the
%   unmodified SOFA release named in .sofaRelease.
%
% ERRORS
%   referenceSystem:buildMex:packageFolderOnPath
%   referenceSystem:buildMex:missingSource
%   referenceSystem:buildMex:noCompiler
%   referenceSystem:buildMex:outputFileLocked
%       The gateway from an earlier build is still mapped into this process and
%       the linker cannot overwrite it. Raised BEFORE mex is invoked where the
%       preflight can see it, and also from either build attempt, so that a
%       locked output is never reported as an OpenMP flag failure.
%   referenceSystem:buildMex:buildFailed
%   referenceSystem:buildMex:gatewayNotLoadable
%
% REFERENCES
%   Handover sections C.4 (MEX rules), C.5 rule 1, C.9 and C.10.
%   IAU SOFA release 20231011, bundled unmodified in mex/sofa/.
%
% EXAMPLE
%   report = referenceSystem.buildMex();
%   assert(report.openMp || strlength(report.openMpFallback) > 0);
%
% KEYWORDS
%   MEX, build, compile, SOFA, OpenMP, gateway, installation
%
% See also MEXINFO, LEAPSECONDS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 20:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.OpenMp (1,1) logical = true
        options.Debug (1,1) logical = false
    end

    startTime = tic;
    packageFolder = fileparts(mfilename('fullpath'));
    toolboxRoot = fileparts(packageFolder);
    mexFolder = fullfile(toolboxRoot, 'mex');
    sofaFolder = fullfile(mexFolder, 'sofa');
    iersFolder = fullfile(mexFolder, 'iers');
    outputFolder = fullfile(packageFolder, 'private');

    pathEntry = split(string(path()), pathsep);
    if any(strcmpi(pathEntry, string(packageFolder)))
        error('referenceSystem:buildMex:packageFolderOnPath', ...
            ['The +referenceSystem folder is on the MATLAB path, which is ', ...
            'the section C.5 rule 1 misconfiguration. Remove it and add ', ...
            '"%s" instead, or run setupReferenceSystem, before building.'], ...
            toolboxRoot);
    end

    % EVERY .c AT THE TOP OF mex/ IS COMPILED, not a named pair (rev. 1.85).
    % Until now this listed mexGateway.c and rsCore.c by name, so mex/rsCheb.c
    % could be added at rev. 1.83, tested by gcc in the standalone harness, and
    % be absent from the binary MATLAB actually calls - with nothing anywhere
    % to notice. The vendored sofa/ and iers/ trees are already globbed; the top
    % level now is too, and a contract test asserts the folder and the build
    % agree so a future core file cannot go missing the same way.
    coreEntry = dir(fullfile(mexFolder, '*.c'));
    gatewaySource = fullfile(mexFolder, 'mexGateway.c');
    sofaEntry = dir(fullfile(sofaFolder, '*.c'));
    iersEntry = dir(fullfile(iersFolder, '*.c'));
    if ~isfile(gatewaySource) || ~isfile(fullfile(mexFolder, 'rsCore.c')) || ...
            isempty(sofaEntry) || isempty(iersEntry)
        error('referenceSystem:buildMex:missingSource', ...
            ['The C sources are incomplete: expected mexGateway.c and ', ...
            'rsCore.c in "%s", the SOFA .c files in "%s" and the ported ', ...
            'IERS Conventions .c files in "%s".'], ...
            mexFolder, sofaFolder, iersFolder);
    end

    if isempty(mex.getCompilerConfigurations('C', 'Selected'))
        error('referenceSystem:buildMex:noCompiler', ...
            ['No C compiler is selected. Run "mex -setup C" once and choose ', ...
            'a supported compiler, then build again.']);
    end

    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    % THE GATEWAY IS FORCED FIRST. MATLAB names the compiled artefact after the
    % FIRST source file, so with a bare dir() listing the output name depends on
    % alphabetical order - it happens to work today because 'm' sorts before
    % 'r', and it would stop working the day someone adds mex/aSomething.c. The
    % order is made explicit rather than inherited from the file system.
    otherCore = coreEntry(~strcmp({coreEntry.name}, 'mexGateway.c'));
    sourceFile = [{gatewaySource}, fullfile({otherCore.folder}, {otherCore.name}), ...
        fullfile({sofaEntry.folder}, {sofaEntry.name}), ...
        fullfile({iersEntry.folder}, {iersEntry.name})];
    baseArgument = [{'-outdir', outputFolder}, ...
        {['-I' mexFolder]}, {['-I' sofaFolder]}, {['-I' iersFolder]}, ...
        {'-output', 'mexGateway'}];
    if options.Debug
        baseArgument = [baseArgument, {'-g'}];
    else
        baseArgument = [baseArgument, {'-DNDEBUG'}];
    end
    baseArgument = [baseArgument, sourceFile];

    % A gateway built earlier in this session is a DLL mapped into this
    % process, and Windows refuses to let the linker overwrite a mapped image.
    % Unload it first, then MEASURE that the output file is writable rather
    % than discovering it from ld's message three attempts later.
    localReleaseAndCheckOutput(fullfile(outputFolder, ...
        ['mexGateway.' mexext()]));

    [fallbackReason, openMpFlagName] = localBuild(baseArgument, options.OpenMp);

    % The previously loaded binary must be released before the new one can be
    % queried; a private MEX function cannot be cleared by name from here.
    % clear mex UNLOADS the gateway so the next build can overwrite it.
    clear mex %#ok<CLMEX>
    mexState = referenceSystem.mexInfo();
    if ~mexState.built || mexState.sofaRelease == ""
        error('referenceSystem:buildMex:gatewayNotLoadable', ...
            ['The build produced no loadable gateway at "%s". Check the ', ...
            'compiler output above.'], mexState.file);
    end

    % openMp comes from the BINARY, never from whether mex() threw. Until
    % revision 1.44 this field was set true simply because the build command
    % had not raised an error, which is not the same claim at all: a mex
    % variable assignment the platform's options file does not use is accepted
    % and ignored, so the build succeeds and _OPENMP is never defined. That is
    % exactly what happened on MinGW64, where buildMex reported openMp true
    % while the gateway reported false and the report header said "OpenMP: no".
    % Two sources of truth for one fact, with nothing comparing them. There is
    % now one source, and it is the compiled artefact.
    if ~mexState.openMp && fallbackReason == ""
        fallbackReason = "the compiler accepted the OpenMP flags but the " + ...
            "binary reports _OPENMP undefined";
    end

    buildReport = struct( ...
        'file', mexState.file, ...
        'openMp', mexState.openMp, ...
        'openMpFlags', openMpFlagName, ...
        'openMpFallback', fallbackReason, ...
        'sourceCount', numel(sourceFile), ...
        'sofaRelease', mexState.sofaRelease, ...
        'leapSecondsSummary', mexState.leapSecondsSummary, ...
        'duration', toc(startTime));

    % THE MANIFEST IS WRITTEN LAST, AFTER THE BUILD SUCCEEDED. If the compile
    % fails, no manifest exists and the next setup rebuilds - which is the
    % right default. Written first, a failed build would leave a manifest
    % claiming sources that were never compiled.
    manifestFile = fullfile(packageFolder, 'private', 'mexGateway.sources');
    fileId = fopen(manifestFile, 'w');
    if fileId >= 0
        fprintf(fileId, '%d\n', referenceSystem.mexSourceDigest(toolboxRoot));
        fclose(fileId);
    end
end

% =========================== local functions ===========================

function [fallbackReason, flagName] = localBuild(baseArgument, tryOpenMp)
%LOCALBUILD Detect the OpenMP flag spelling, then compile once.
%   Returns why OpenMP is not expected, or "", and the name of the spelling
%   that took effect. It does not return whether OpenMP is present: that is a
%   property of the binary and the caller reads it from mexInfo.
%
%   WHY A PROBE RATHER THAN TRIAL BUILDS. Which variable name mex honours is a
%   property of the platform's options file, not of the compiler family, and
%   the two do not line up: Windows with MSVC wants COMPFLAGS and /openmp,
%   Windows with MinGW is a GCC toolchain wanting -fopenmp, Unix wants CFLAGS
%   and LDFLAGS. An assignment mex does not use is accepted and silently
%   ignored, so the spelling has to be established by experiment.
%
%   Revision 1.44 established it by building the whole toolbox with each
%   spelling in turn and asking the binary afterwards. That was correct and
%   cost 203 seconds on MinGW64, because the first spelling tried was wrong and
%   255 sources were compiled twice. The question is settled here instead by a
%   five-line C file that FAILS TO COMPILE unless _OPENMP is defined, run
%   through mex -c: about a second per candidate, no linking, no loading, and
%   the same answer. The full build then happens exactly once.
%
%   The order below is measured rather than assumed. On R2026a with MinGW64 the
%   spelling that takes effect is CFLAGS and LDFLAGS -- the Unix names, on
%   Windows -- which is not what the platform would lead one to guess and is
%   why the ordering is recorded here rather than reasoned about again.
%
%   Optimisation flags are deliberately not bundled with the OpenMP concern.
%   They were, and when the assignment was ignored the -O3 went with it, so the
%   build quietly lost its optimisation as well. One concern per flag.

    fallbackReason = "";
    flagName = "";

    if ~tryOpenMp
        fallbackReason = "OpenMp was set false by the caller";
    elseif ismac
        fallbackReason = "Apple clang ships without OpenMP support";
    else
        [variant, rejected] = localDetectOpenMpFlags();
        if ~isempty(variant)
            try
                mex(variant.flag{:}, baseArgument{:});
                flagName = variant.name;
                return
            catch cause
                % A locked output file is not an OpenMP problem and must not
                % be recorded as one. Falling through to the non-OpenMP build
                % here would fail again for the same reason, and if it ever
                % succeeded it would produce a serial binary blamed on a
                % compiler flag - a silent wrong answer of exactly the kind
                % revision 1.44 recorded. Abort instead.
                if localIsLockedOutput(cause.message)
                    localRaiseLocked(cause.message);
                end
                fallbackReason = "the probe accepted " + variant.name + ...
                    " but the full build failed with it (" + ...
                    string(cause.message) + ")";
            end
        else
            fallbackReason = "no OpenMP flag spelling took effect: " + ...
                join(rejected, "; ");
        end
    end

    try
        mex(baseArgument{:});
    catch cause
        if localIsLockedOutput(cause.message)
            localRaiseLocked(cause.message);
        end
        error('referenceSystem:buildMex:buildFailed', ...
            'The MEX build failed: %s', cause.message);
    end
end

function localReleaseAndCheckOutput(outputFile)
%LOCALRELEASEANDCHECKOUTPUT Unload any mapped gateway and prove it is writable.
%   clear mex first, because the common case is a gateway this very session
%   loaded and the unload usually succeeds. Then ask the operating system
%   whether the file can be opened for writing, which is the property the
%   linker is about to need: Windows maps a loaded image with FILE_SHARE_READ,
%   so an open for writing is refused while it is mapped. Nothing is written
%   and the handle is closed immediately.
%
%   The check is here rather than left to the linker because ld's message
%   names a path and a permission and not a cause, and because the OpenMP
%   search would otherwise run first and attribute the failure to a flag.

    % clear mex UNLOADS the gateway so the next build can overwrite it.
    clear mex %#ok<CLMEX>

    if ~isfile(outputFile)
        return
    end

    fileId = fopen(outputFile, 'r+');
    if fileId >= 0
        fclose(fileId);
        return
    end

    localRaiseLocked("the existing gateway could not be opened for writing");
end

function tf = localIsLockedOutput(message)
%LOCALISLOCKEDOUTPUT Recognise a locked output file across linkers.
%   GNU ld says "cannot open output file ... Permission denied"; MSVC link
%   says "LNK1104: cannot open file" or "Access is denied". Matching several
%   spellings is not defensive padding: the point of the classification is to
%   stop this failure being reported as an OpenMP one, and a missed spelling
%   restores exactly that confusion.

    message = string(message);
    tf = contains(message, "cannot open output file", 'IgnoreCase', true) || ...
        contains(message, "Permission denied", 'IgnoreCase', true) || ...
        contains(message, "LNK1104", 'IgnoreCase', true) || ...
        contains(message, "Access is denied", 'IgnoreCase', true);
end

function localRaiseLocked(detail)
%LOCALRAISELOCKED One diagnosis and one cure, in place of the linker's message.

    error('referenceSystem:buildMex:outputFileLocked', ...
        ['The existing mexGateway is still mapped into this MATLAB ', ...
        'process, so the linker cannot overwrite it (%s).\n\n', ...
        'Windows locks a mapped DLL and every ancestor folder of it, which ', ...
        'is the same handle that prevents the toolbox folder being ', ...
        'deleted.\n\nRESTART MATLAB and build before calling anything else. ', ...
        'That is the reliable cure, not the last resort: on R2026a with ', ...
        'MinGW64 and OpenMP live, "clear mex" was MEASURED not to release ', ...
        'the mapped gateway, and the relink failed again until MATLAB was ', ...
        'shut down.\n\n"clear mex" then referenceSystem.buildMex is still ', ...
        'worth one attempt, since it costs a second and does work when no ', ...
        'OpenMP thread pool is holding the library. ', ...
        'referenceSystem.teardownReferenceSystem reports which case you are ', ...
        'in.'], detail);
end

function [variant, rejected] = localDetectOpenMpFlags()
%LOCALDETECTOPENMPFLAGS Which flag spelling actually defines _OPENMP here.
%   The probe compiles only when _OPENMP is defined, so mex -c succeeding is
%   itself the answer; nothing has to be linked, loaded or called. Compiler
%   output is captured rather than shown, because a rejected candidate prints
%   an alarming error that is an expected part of the search.

    variant = [];
    rejected = strings(0, 1);

    probeFolder = tempname;
    if ~mkdir(probeFolder)
        rejected(end+1, 1) = "could not create a probe folder";
        return
    end
    removeProbe = onCleanup(@() rmdir(probeFolder, 's'));

    probeFile = fullfile(probeFolder, 'rsOpenMpProbe.c');
    writelines([ ...
        "/* buildMex probe: compiles only when _OPENMP is defined. */"
        "#ifndef _OPENMP"
        "#error OpenMP is not enabled"
        "#endif"
        "int rsOpenMpProbe(void) { return 1; }"], probeFile);

    candidate = localOpenMpFlagVariants();
    for k = 1:numel(candidate)
        % Called through evalc below, which the analyser cannot read.
        compileProbe = @() mex('-c', candidate(k).flag{:}, ... %#ok<NASGU>
            '-outdir', probeFolder, probeFile);
        try
            evalc('compileProbe()');
            variant = candidate(k);
            return
        catch cause
            firstLine = strtrim(extractBefore(string(cause.message) + newline, ...
                newline));
            rejected(end+1, 1) = candidate(k).name + " (" + firstLine + ")"; %#ok<AGROW>
        end
    end
end

function variant = localOpenMpFlagVariants()
%LOCALOPENMPFLAGVARIANTS The spellings worth probing, most likely first.
%   The selected compiler decides the order only. Every candidate is proved by
%   the probe before it is used, so a wrong guess costs about a second.

    isMinGw = false;
    try
        configuration = mex.getCompilerConfigurations('C', 'Selected');
        isMinGw = ~isempty(configuration) && ...
            contains(configuration(1).Name, "MinGW", 'IgnoreCase', true);
    catch
        % No selected compiler to interrogate; the probe still decides.
    end

    gccUnixNames = struct('name', "CFLAGS/LDFLAGS -fopenmp", ...
        'flag', {{'CFLAGS="$CFLAGS -fopenmp"', 'LDFLAGS="$LDFLAGS -fopenmp"'}});
    gccWindowsNames = struct('name', "COMPFLAGS/LINKFLAGS -fopenmp", ...
        'flag', {{'COMPFLAGS="$COMPFLAGS -fopenmp"', ...
                  'LINKFLAGS="$LINKFLAGS -fopenmp"'}});
    msvc = struct('name', "COMPFLAGS /openmp", ...
        'flag', {{'COMPFLAGS="$COMPFLAGS /openmp"'}});

    if ~ispc
        variant = gccUnixNames;
    elseif isMinGw
        % Measured on R2026a with MinGW64: the Unix names are the ones mex
        % honours, despite the platform.
        variant = [gccUnixNames, gccWindowsNames, msvc];
    else
        variant = [msvc, gccWindowsNames, gccUnixNames];
    end
end
