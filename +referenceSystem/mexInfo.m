function mexState = mexInfo()
%MEXINFO State of the compiled MEX gateway and of the leap-second authority.
%
%   mexState = mexInfo() reports whether the package-private MEX gateway is
%   built, what it was built from, and how it is configured. It is the only
%   public face of +referenceSystem/private/mexGateway, which is not callable
%   from outside the package.
%
% INPUT ARGUMENTS
%   (none)
%
% OUTPUT ARGUMENTS
%   Name                       Size   Type      Units  Description
%   ----                       ----   ----      -----  -----------
%   mexState                   1x1    struct    -      Fields listed below.
%   .built                     1x1    logical   -      True if the gateway exists.
%   .file                      1x1    string    -      Expected gateway path.
%   .buildDate                 1x1    string    -      Build date, ISO 8601, or ''.
%   .sofaRelease               1x1    string    -      SOFA release, or ''.
%   .openMp                    1x1    logical   -      True if built with OpenMP.
%   .threadCount               1x1    double    -      Active OpenMP threads, NaN
%                                                      if unknown.
%   .compiler                1x1    string   -      Name of the SELECTED C
%                                                   compiler, empty if none can
%                                                   be interrogated. A variable
%                                                   on Windows - MinGW and MSVC
%                                                   differ in the math library
%                                                   behind sin and cos and in
%                                                   the OpenMP runtime - so a
%                                                   timing comparison that does
%                                                   not record it is comparing
%                                                   two unknowns.
%   .clampedToSingleThread     1x1    logical   -      True if D31 clamping is in
%                                                      force inside a parfor worker.
%   .leapSecondsValidThrough   1x1    string    -      Last date the table covers,
%                                                      or '' if unknown.
%   .leapSecondsSource         1x1    string    -      Authority of that table.
%   .summary                   1x1    string    -      One line for the report header.
%   .leapSecondsSummary        1x1    string    -      One line for the report header.
%
% METHOD
%   The gateway is a build product, so its absence is a normal state, not an
%   error: this function reports it and returns. Every field has the same class
%   and size whether or not the gateway exists, so a caller never has to test
%   for existence before indexing, and the test report can be written before any
%   C code has been compiled.
%
%   The fields that only the gateway itself can answer for - the SOFA release
%   it was compiled against, the OpenMP thread count and whether the decision
%   D31 clamp is in force - are filled by a mexGateway('info') query. A gateway
%   that is present but does not load is reported as such rather than as
%   absent, because the two have different repairs.
%
%   The leap-second fields are not read from the gateway. They are asked of
%   leapSecondTable, which owns them, so that this header and that function can
%   never disagree; if leapSecondTable cannot answer, the state says so instead of
%   guessing. A stated but unverified SOFA release or leap-second coverage in a
%   test report is exactly the provenance defect this toolbox exists to
%   prevent.
%
% ACCURACY
%   Not applicable; the function reports build state and computes no numerical
%   quantity. threadCount is NaN, and the two date fields are empty strings,
%   whenever the value is genuinely unknown; this is the documented use of an
%   undefined-but-valid value permitted by section C.6 rule 5.
%
% ERRORS
%   (none) The function reports rather than raises: a missing gateway is a
%   state, and every caller of this function needs the state, not an exception.
%
% REFERENCES
%   Handover section C.4 (MEX rules), C.9 and decision D31 (thread clamping),
%   section D.3 (the report header this function feeds).
%
% EXAMPLE
%   state = referenceSystem.mexInfo();
%   if ~state.built
%       % referenceSystem.buildMex has not been run yet
%   end
%
% KEYWORDS
%   MEX, gateway, build, SOFA, OpenMP, threads, leap seconds, provenance
%
% See also RUNTESTSUITE, TOOLBOXVERSION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 12:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    gatewayFile = fullfile(fileparts(mfilename('fullpath')), 'private', ...
        "mexGateway." + string(mexext()));
    isBuilt = isfile(gatewayFile);

    buildDate = "";
    if isBuilt
        fileEntry = dir(gatewayFile);
        buildDate = string(datetime(fileEntry.datenum, 'ConvertFrom', 'datenum', ...
            'Format', 'yyyy-MM-dd HH:mm'));
    end

    mexState = struct( ...
        'built', isBuilt, ...
        'file', string(gatewayFile), ...
        'buildDate', buildDate, ...
        'sofaRelease', "", ...
        'openMp', false, ...
        'threadCount', NaN, ...
        'clampedToSingleThread', false, ...
        'compiler', "", ...
        'leapSecondsValidThrough', "", ...
        'leapSecondsSource', "", ...
        'summary', "", ...
        'leapSecondsSummary', "");

    % WHICH COMPILER BUILT IT, BECAUSE THAT IS A VARIABLE AND NOT A CONSTANT
    % (rev. 1.199). Windows offers MinGW and MSVC and they differ in the two
    % places that matter to this gateway - the math library behind sin and cos,
    % which the IAU 2000A series calls hundreds of times per epoch, and the
    % OpenMP runtime. Comparing two machines, or the same machine before and
    % after `mex -setup`, is only meaningful if each report says which toolchain
    % produced the binary it measured. This reads the SELECTED compiler, which
    % is the one buildMex would use now; if it has been changed since the
    % gateway was built the two disagree, and the build date beside it is what
    % settles which is older.
    try
        configuration = mex.getCompilerConfigurations('C', 'Selected');
        if ~isempty(configuration)
            mexState.compiler = string(configuration(1).Name);
        end
    catch
        % No selected compiler to interrogate. The field stays empty and the
        % report prints it as unknown rather than guessing from the platform.
    end

    if ~isBuilt
        mexState.summary = "not built - run referenceSystem.buildMex";
        mexState.leapSecondsSummary = "unknown (no MEX gateway, no leap-second " + ...
            "authority yet)";
        return
    end

    try
        gatewayState = mexGateway('info');
        mexState.sofaRelease = string(gatewayState.sofaRelease);
        mexState.openMp = logical(gatewayState.openMp);
        mexState.threadCount = double(gatewayState.threadCount);
        mexState.clampedToSingleThread = logical(gatewayState.clampedToSingleThread);
        mexState.summary = mexState.file + " built " + buildDate + ", SOFA " + ...
            mexState.sofaRelease + ", OpenMP: " + ...
            localYesNo(mexState.openMp, mexState.threadCount, ...
            mexState.clampedToSingleThread);
    catch cause
        mexState.summary = "present but not loadable (" + ...
            string(cause.identifier) + ")";
        mexState.leapSecondsSummary = "unknown (the gateway did not answer)";
        return
    end

    % The leap-second fields are asked of the authority that owns them rather
    % than restated here, so the report header and leapSecondTable can never
    % disagree. A failure to answer is a state to report, not an exception to
    % raise: this function is what a caller uses to find out whether the
    % toolbox is usable.
    try
        leapState = referenceSystem.leapSecondTable("state");
        mexState.leapSecondsValidThrough = string(leapState.validThrough, ...
            'yyyy-MM-dd');
        mexState.leapSecondsSource = leapState.source;
        mexState.leapSecondsSummary = "last leap second " + ...
            string(leapState.lastChange, 'yyyy-MM-dd') + " (TAI-UTC = " + ...
            string(leapState.lastDeltaAt) + " s), table valid through " + ...
            mexState.leapSecondsValidThrough + " (source: " + ...
            leapState.source + ")";
    catch cause
        mexState.leapSecondsSummary = "unknown (" + string(cause.identifier) + ")";
    end
end

% =========================== local functions ===========================

function text = localYesNo(hasOpenMp, threadCount, isClamped)
%LOCALYESNO One-line description of the OpenMP state for the report header.
    if ~hasOpenMp
        text = "no";
        return
    end
    text = "yes (" + string(threadCount) + " threads)";
    if isClamped
        text = text + ", clamped to one thread inside a parfor worker";
    end
end
