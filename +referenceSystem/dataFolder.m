function [folder, location] = dataFolder(newFolder, options)
%DATAFOLDER Get or set the root of the data pool the toolbox downloads into.
%
%   folder = dataFolder() returns the ROOT OF THE DATA POOL: the one folder,
%   shared by every astrobayer toolbox, under which downloaded data is kept by
%   product. SPICE kernels live in <pool>/SPICE and Earth orientation series
%   in <pool>/EOP. Nothing downloaded is ever kept in the toolbox folder, and
%   there is no default inside it: without a configured pool this function
%   REFUSES rather than invent one.
%
%   [folder, location] = dataFolder() also returns where each product of this
%   toolbox lives under that root, and which rule chose the root.
%
%   folder = dataFolder(path) stores path as the pool root and returns it.
%   The choice PERSISTS ACROSS SESSIONS as a MATLAB preference, so it is made
%   once and not on every call, and no startup.m is needed.
%
%   folder = dataFolder("reset") discards the stored choice and returns the
%   root the remaining rules resolve to now, or "" when none does. A reset is
%   a successful act, so it does not raise when the pool is then unset.
%
%   folder = dataFolder(DataPool = path) uses path as the root FOR THIS CALL
%   ONLY and stores nothing. It is the explicit first rule below, and what an
%   installer that was told where the pool is passes on.
%
% INPUT ARGUMENTS
%   Name                     Size   Type     Units  Description
%   ----                     ----   ----     -----  -----------
%   newFolder                1x1    string   -      Pool root to store, the
%                                                   literal "reset" to discard
%                                                   a stored choice, or omitted
%                                                   to query. Default "".
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name                     Size   Type     Default  Description
%   ----                     ----   ----     -------  -----------
%   DataPool                 1x1    string   ""       Pool root for this call,
%                                                     stored nowhere. Wins over
%                                                     every other rule. "" means
%                                                     not given.
%
% OUTPUT ARGUMENTS
%   Name                     Size   Type     Units  Description
%   ----                     ----   ----     -----  -----------
%   folder                   1x1    string   -      ABSOLUTE path of the pool
%                                                   root, which exists on
%                                                   return; "" only after a
%                                                   "reset" that leaves no rule
%                                                   standing.
%   location                 1x1    struct   -      Fields listed below.
%   .root                    1x1    string   -      The same path as folder.
%   .source                  1x1    string   -      The rule that chose it:
%                                                   "argument", "preference",
%                                                   "DATAPOOL",
%                                                   "READING_DATA_POOL", or ""
%                                                   when none did.
%   .SPICE                   1x1    string   -      <root>/SPICE, where
%                                                   downloadKernels writes.
%   .EOP                     1x1    string   -      <root>/EOP, where
%                                                   downloadEop writes.
%
% METHOD
%   THE POOL ROOT IS RESOLVED IN ONE ORDER, THE ORGANISATION'S (DATA_POOL.md,
%   decided by the owner on 2026-11-08: "All data go always to the data pool.
%   Only model code or libraries go to the toolbox."):
%     1. the DataPool argument of this call;
%     2. the stored preference, setpref('referenceSystem', 'dataFolder');
%     3. getenv("DATAPOOL"), which toolboxInstaller writes into startup.m;
%     4. getenv("READING_DATA_POOL"), the older name, honoured, never required;
%     5. otherwise referenceSystem:dataFolder:noDataPool. NOTHING IS WRITTEN
%        INTO THE TOOLBOX FOLDER AS A FALLBACK, because a download that lands
%        in a git checkout makes the checkout dirty and is a second copy of a
%        product another toolbox already holds.
%   An environment variable holding only blanks counts as unset.
%
%   THE LAYOUT IS BY PRODUCT AND SHARED. One copy of each product, whichever
%   toolbox fetched it, so NonGravForces and this toolbox read one de440s.bsp.
%   The two folder names are spelled here and nowhere else in the toolbox, and
%   case-exact, because a Linux runner reads "spice" and "SPICE" as two
%   folders. The product folders are NOT created on query: the downloader
%   that writes into one creates it, and a reader that finds none reports it.
%
%   THE STORED PREFERENCE IS A POOL ROOT. Before version 3.0 it named a
%   per-toolbox folder that held the kernels and EOP files flat. The name of
%   the preference is kept, so a user who stored one is not silently ignored,
%   but it now means the root: point it at the pool (or reset it and let
%   DATAPOOL answer) and move the files into <pool>/SPICE and <pool>/EOP once,
%   by hand. No code looks in the old place.
%
%   ONE AUTHORITY FOR THE LOCATION, AND THIS IS IT. downloadEop,
%   downloadKernels, setupReferenceSystem, the test suite and its report all
%   resolve through this function and read the fields of location; none of
%   them composes a path of its own.
%
%   THE MECHANISM IS setpref AND IT MATCHES shAnalysis DELIBERATELY. The same
%   author maintains both toolboxes and calls shLowLevel.dataFolder with the
%   same three shapes - query, set, "reset" - so the habit transfers. The
%   preference group is the toolbox name, so nothing here can collide with
%   another toolbox's settings.
%
%   THE ROOT IS CREATED ON QUERY, WHICH IS A SIDE EFFECT AND IS INTENDED.
%   Every caller is about to read or write under it, and returning a path that
%   does not exist moves the mkdir into each of them. It is the pool, never
%   the toolbox, that is created.
%
%   A STORED PREFERENCE OR AN ENVIRONMENT VARIABLE IS INVISIBLE IN A SCRIPT,
%   which is the cost of configuration and is stated here rather than
%   discovered. Where that matters - a test, a published result, a CI run -
%   pass the folder explicitly: DataPool here, DataFolder to setup, or CacheDir
%   to downloadEop and downloadKernels, which no rule above touches.
%
% ACCURACY
%   Not applicable; the function resolves a path and computes no numerical
%   quantity.
%
% ERRORS
%   referenceSystem:dataFolder:noDataPool
%       No rule named a pool root: no DataPool argument, no stored preference,
%       and neither DATAPOOL nor READING_DATA_POOL is set. Set DATAPOOL (the
%       installer does), call referenceSystem.dataFolder(path) once, or pass
%       DataPool. Nothing is written anywhere before this is raised.
%   referenceSystem:dataFolder:pathIsAFile
%       The resolved root is an existing FILE, so no folder can be made there.
%       Raised before anything is written, because mkdir would otherwise fail
%       later inside a transfer and report a kernel when the defect is in the
%       configuration.
%   referenceSystem:dataFolder:notCreated
%       The root does not exist and could not be created; the message carries
%       the reason the file system gave.
%
% REFERENCES
%   toolboxInstaller docs/DATA_POOL.md, the organisation's data-pool contract.
%   Handover decisions D119 and D133, section C.10. The sibling implementation
%   is shLowLevel.dataFolder in the shAnalysis toolbox.
%
% EXAMPLE
%   % Where does downloaded data go, and how do I name the pool?
%   [folder, location] = referenceSystem.dataFolder()  % refuses if unset
%   referenceSystem.dataFolder("E:\DATAPOOL");          % store the pool root
%   referenceSystem.downloadKernels(Mode = "download"); % to E:\DATAPOOL\SPICE
%   referenceSystem.dataFolder("reset");                % DATAPOOL answers now
%
% KEYWORDS
%   data pool, DATAPOOL, data folder, preference, cache, installation, kernels
%
% See also DOWNLOADKERNELS, DOWNLOADEOP, SETUPREFERENCESYSTEM
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-08-21 18:05 (CEST, UTC+02:00)
% Revised: 2026-11-08 23:10 (CET, UTC+01:00)
% -------------------------------------------------------------------------

    arguments
        newFolder (1,1) string = ""
        options.DataPool (1,1) string = ""
    end

    group = 'referenceSystem';
    preferenceName = 'dataFolder';

    isReset = newFolder == "reset";
    if isReset
        if ispref(group, preferenceName)
            rmpref(group, preferenceName);
        end
        newFolder = "";
    end

    if strlength(strtrim(newFolder)) > 0
        setpref(group, preferenceName, char(strtrim(newFolder)));
    end

    % D133: THE ORDER OF DATA_POOL.md, EACH RULE TRIED ONLY WHEN THE ONE ABOVE
    % IT IS SILENT.
    folder = strtrim(options.DataPool);
    source = "argument";
    if strlength(folder) == 0 && ispref(group, preferenceName)
        folder = strtrim(string(getpref(group, preferenceName)));
        source = "preference";
    end
    for variable = ["DATAPOOL", "READING_DATA_POOL"]
        if strlength(folder) == 0
            folder = strtrim(string(getenv(variable)));
            source = variable;
        end
    end

    if strlength(folder) == 0
        if isReset
            folder = "";
            location = struct('root', "", 'source', "", 'SPICE', "", 'EOP', "");
            return
        end
        error('referenceSystem:dataFolder:noDataPool', ...
            ['No data pool is configured, and referenceSystem keeps no ', ...
            'downloaded data in the toolbox folder. Set the environment ', ...
            'variable DATAPOOL to the pool root (toolboxInstaller does), or ', ...
            'store it once with referenceSystem.dataFolder(path), or pass ', ...
            'DataPool = path (setupReferenceSystem: DataFolder = path). ', ...
            'READING_DATA_POOL is honoured too. Kernels then go to ', ...
            '<pool>/SPICE and EOP series to <pool>/EOP.']);
    end

    if isfile(folder)
        error('referenceSystem:dataFolder:pathIsAFile', ...
            ['The data pool "%s" (from %s) is an existing FILE, so no folder ', ...
            'can be made there. Name a directory, or a path that does not ', ...
            'exist yet.'], folder, source);
    end

    if ~isfolder(folder)
        [made, message] = mkdir(char(folder));
        if ~made
            error('referenceSystem:dataFolder:notCreated', ...
                'The data pool "%s" (from %s) could not be created: %s', ...
                folder, source, message);
        end
    end

    % ABSOLUTE FROM HERE ON. A relative root would resolve against whatever
    % the working directory happened to be when each caller ran, and two calls
    % in one session could then name different folders. what() answers for a
    % folder that now exists.
    resolved = what(char(folder));
    if ~isempty(resolved)
        folder = string(resolved(1).path);
    end

    % THE ONLY SPELLING OF THE PRODUCT FOLDERS IN THE TOOLBOX (D133).
    % Case-exact, as DATA_POOL.md section 3 requires of readers and writers.
    location = struct('root', folder, 'source', source, ...
        'SPICE', string(fullfile(folder, 'SPICE')), ...
        'EOP', string(fullfile(folder, 'EOP')));
end
