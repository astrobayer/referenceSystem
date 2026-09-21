function status = teardownReferenceSystem(options)
%TEARDOWNREFERENCESYSTEM Release the toolbox so its folder can be deleted.
%
%   status = teardownReferenceSystem() unloads the MEX gateway, closes any file
%   the toolbox left open, leaves the folder if it is the current one, and
%   removes the toolbox root from the search path. It then MEASURES whether the
%   folder is still held and reports what is holding it.
%
%   status = teardownReferenceSystem('Save', true) also calls savepath, so the
%   removal survives the MATLAB session.
%
% INPUT ARGUMENTS
%   This function takes no positional arguments. It acts on the toolbox it is
%   itself part of, located from mfilename('fullpath'), so there is no root to
%   pass in and no way to point it at the wrong installation.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name   Size   Type      Default   Description
%   ----   ----   ----      -------   -----------
%   Save   1x1    logical   false     Call savepath after removing the root.
%
% OUTPUT ARGUMENTS
%   Name                 Size   Type      Units  Description
%   ----                 ----   ----      -----  -----------
%   status               1x1    struct    -      What was released and what was
%                                                not.
%   .toolboxRoot         1x1    string    -      The folder this function acted
%                                                on.
%   .mexWasLoaded        1x1    logical   -      Whether the gateway was in
%                                                memory when called.
%   .mexStillLoaded      1x1    logical   -      Whether it is STILL in memory
%                                                after the unload attempt. This
%                                                is the one field to read.
%   .filesOpenInTree     1xN    string    -      Files inside the tree that are
%                                                open. REPORTED, NOT CLOSED; see
%                                                METHOD.
%   .leftCurrentFolder   1x1    logical   -      Whether the current folder had
%                                                to be changed.
%   .removedFromPath     1xN    string    -      Path entries removed.
%   .pathSaved           1x1    logical   -      True if savepath succeeded.
%   .folderIsHeld        1x1    logical   -      Measured, see METHOD. NaN-free:
%                                                false also when the test does
%                                                not apply, and .heldBy says so.
%   .heldBy              1x1    string    -      Plain-language account of what
%                                                still holds the folder, or ""
%                                                when nothing does.
%
% METHOD
%   A folder cannot be deleted on Windows while anything inside it is open, and
%   the usual holder is not a file but a LOADED LIBRARY: mexGateway.mexw64 is a
%   DLL mapped into the MATLAB process, and Windows locks a mapped DLL's folder
%   and every ancestor of it. That is why the whole toolbox tree resists
%   deletion when only one file deep inside it is in use. On Linux and macOS the
%   problem does not arise - a loaded .so may be unlinked - so this function is
%   close to a no-op there and says so rather than pretending to have worked.
%
%   THE STEPS, IN THE ORDER THEY MUST HAPPEN.
%
%   1. REPORT the files open inside the tree, and close none of them. The list
%      comes from openedFiles, not from fopen('all'), which was removed in
%      R2025a and raises on R2026a; see listOpenFiles for the shim. The first
%      version of this function closed them, on the reasoning that a file inside
%      the tree is the toolbox's business. THAT WAS WRONG AND THE SUITE PROVED
%      IT ON THE FIRST RUN: runTestSuite writes testReport.txt into the current
%      folder, which during a run is the toolbox root, so this function closed
%      the report file of the harness that was calling it, out from under a live
%      fprintf. Both of its own contract tests errored.
%
%      The rule that replaces it: A TEARDOWN CLOSES WHAT IT OPENED AND NOTHING
%      ELSE. A file handle belongs to the code that created it, which alone
%      knows whether it is finished with it; this function cannot know that and
%      must not guess. The names are reported in .filesOpenInTree and named in
%      .heldBy so the caller can act, which is the whole of what an outsider is
%      entitled to do. fclose('all') would have been the same error, larger.
%
%   2. Leave the folder. Windows locks a process's current directory, so if pwd
%      is inside the tree nothing else will help. The function moves to the
%      parent of the toolbox root, never to a folder chosen for the caller.
%
%   3. Unload the MEX. `clear mex` is used and NOT `clear all`: they are not
%      synonyms for this purpose, `clear all` additionally destroys the caller's
%      workspace, and this function has no business doing that.
%
%   4. Remove from the path, optionally saving.
%
%   5. MEASURE, and this is the point of the function. Success is not inferred
%      from the four steps having run without error - that is obligation O9's
%      failure mode exactly, and this toolbox has already been bitten by it once
%      in buildMex. Two independent measurements are taken:
%
%        inmem   - the second output of inmem lists the MEX files in memory. If
%                  the gateway is still there after `clear mex`, it did not
%                  unload, and no amount of path tidying will free the folder.
%        fopen   - the gateway file is opened with 'r+', read and write without
%                  truncation. Windows maps a loaded DLL with read sharing only,
%                  so this open FAILS while the library is loaded and succeeds
%                  once it is not. The file is closed immediately and nothing is
%                  written. On Unix the open succeeds either way, so the result
%                  is reported as not applicable rather than as a pass.
%
%   WHAT THIS FUNCTION CANNOT RELEASE, and will name in .heldBy instead:
%
%     - A file from the tree open in the MATLAB Editor. The Editor holds its own
%       handle and nothing in the language can close it. testReport.txt is the
%       usual offender, because it is the file one has just been reading.
%     - Any file another part of the program has open under the tree. These are
%       listed in .filesOpenInTree rather than closed, for the reason in step 1.
%     - The Current Folder browser pointed inside the tree, which is a separate
%       handle from pwd.
%     - MATLAB's folder change notification, which takes a directory handle on
%       Windows for folders it has seen on the path. Setting the "Enable folder
%       change notification" preference off, or restarting MATLAB, releases it.
%     - A MEX that will not unload because its OpenMP runtime keeps a live
%       thread pool. MEASURED ON R2026a WITH MinGW64 AND OpenMP LIVE ON 16
%       THREADS: "clear mex" did NOT release the mapped gateway, and the linker
%       could not overwrite it until MATLAB was restarted. So restarting is not
%       the last resort here, it is the reliable cure, and "clear mex" is the
%       cheap thing worth trying first rather than the fix.
%
%   Restarting MATLAB releases all of them, which is worth saying plainly: this
%   function exists so that a restart is not needed, not to claim it never is.
%
%   WHY THIS LIVES INSIDE THE NAMESPACE AND setupReferenceSystem DOES NOT. Setup
%   has to be callable before the toolbox root is on the path, so it sits at the
%   root as a plain function. Teardown can only be wanted after setup has run,
%   which is exactly when referenceSystem.* resolves, so it belongs with the
%   rest of the package. The asymmetry is deliberate rather than an oversight,
%   and it is the one place in the toolbox where a matched pair of operations
%   does not live in a matched pair of places.
%
%   STEP 3 HAS NOW BEEN MEASURED AND THE ANSWER IS NO. The first version of this
%   help said that whether "clear mex" unloads a MEX-file in every release and
%   state was a MATLAB semantic its author had not measured, and that step 5
%   existed so the function would ask rather than claim. It asked, on R2026a
%   with OpenMP live on 16 threads, and "clear mex" did not release the gateway:
%   a rebuild in the same session still failed to link, and only restarting
%   MATLAB freed it. The function is unchanged by that - it already reported
%   what it found - but the help no longer implies the unload usually works.
%   This is what building the measurement into the function bought, and it is
%   the argument for doing so again elsewhere.
%
% ACCURACY
%   Not a numerical function. The one quantitative claim is the fopen probe, and
%   its meaning is exact on Windows and absent elsewhere: a loaded DLL is mapped
%   with FILE_SHARE_READ, so an open for writing is refused by the operating
%   system rather than by a heuristic.
%
%   The probe cannot distinguish a lock held by MATLAB from one held by another
%   process - a virus scanner or a backup agent reading the same file will fail
%   it too. That is a limitation of the measurement, not a fault in it, and
%   .heldBy says so rather than naming MATLAB with unearned confidence.
%
% ERRORS
%   referenceSystem:teardownReferenceSystem:rootNotFound
%
% EXAMPLE
%   status = referenceSystem.teardownReferenceSystem();
%   if status.folderIsHeld
%       disp(status.heldBy)
%   end
%
% REFERENCES
%   MathWorks, clear - Remove items from workspace, freeing up system memory,
%   MATLAB documentation; note that "clear all" and "clear mex" are not
%   synonyms for unloading a MEX-file.
%   MathWorks, inmem - Names of functions, MEX-files, classes in memory.
%   Microsoft, LoadLibrary and DLL locking: a mapped image is opened with
%   FILE_SHARE_READ, so the file cannot be written or deleted while mapped.
%
% KEYWORDS
%   teardown, uninstall, unload, MEX, DLL, file lock, Windows, path, cleanup
%
% See also SETUPREFERENCESYSTEM, BUILDMEX, MEXINFO.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 12:30 (CEST, UTC+02:00) - session S4, folder-lock report
% -------------------------------------------------------------------------

    arguments
        options.Save (1,1) logical = false
    end

    toolboxRoot = string(fileparts(fileparts(mfilename('fullpath'))));
    if ~isfolder(toolboxRoot)
        error('referenceSystem:teardownReferenceSystem:rootNotFound', ...
            'The toolbox root "%s" is not a folder.', toolboxRoot);
    end
    gatewayFile = fullfile(toolboxRoot, "+referenceSystem", "private", ...
        "mexGateway." + string(mexext()));

    [~, mexInMemory] = inmem();
    mexWasLoaded = any(strcmp(mexInMemory, 'mexGateway'));

    % 1. REPORT the files open inside the tree; do not close them. See METHOD.
    filesOpenInTree = strings(1, 0);
    openId = listOpenFiles();
    for k = 1:numel(openId)
        openName = string(fopen(openId(k)));
        if strlength(openName) > 0 && startsWith(openName, toolboxRoot)
            filesOpenInTree(end+1) = openName; %#ok<AGROW>
        end
    end

    % 2. a process cannot delete its own current directory on Windows
    leftCurrentFolder = false;
    if startsWith(string(pwd), toolboxRoot)
        cd(fileparts(toolboxRoot));
        leftCurrentFolder = true;
    end

    % 3. clear mex, deliberately not clear all: they are not synonyms here, and
    %    destroying the caller's workspace is not this function's business
    % clear mex UNLOADS the gateway. Windows locks a loaded MEX file, so
    clear mex %#ok<CLMEX>

    % 4. leave the search path as it was before setupReferenceSystem
    removedFromPath = strings(1, 0);
    entry = split(string(path()), pathsep);
    onPath = entry(strcmp(entry, toolboxRoot));
    if ~isempty(onPath)
        rmpath(char(toolboxRoot));
        removedFromPath = reshape(onPath, 1, []);
    end
    pathSaved = false;
    if options.Save
        pathSaved = savepath() == 0;
    end

    % 5. measure; do not infer
    [~, mexInMemory] = inmem();
    mexStillLoaded = any(strcmp(mexInMemory, 'mexGateway'));
    [folderIsHeld, heldBy] = probeGateway(gatewayFile, mexStillLoaded);
    if ~isempty(filesOpenInTree)
        folderIsHeld = true;
        heldBy = heldBy + " Files are also open inside the tree and this " + ...
            "function did not close them: " + join(filesOpenInTree, ", ") + ...
            ". Close them in the code that opened them.";
        heldBy = strip(heldBy);
    end

    status = struct( ...
        'toolboxRoot', toolboxRoot, ...
        'mexWasLoaded', mexWasLoaded, ...
        'mexStillLoaded', mexStillLoaded, ...
        'filesOpenInTree', filesOpenInTree, ...
        'leftCurrentFolder', leftCurrentFolder, ...
        'removedFromPath', removedFromPath, ...
        'pathSaved', pathSaved, ...
        'folderIsHeld', folderIsHeld, ...
        'heldBy', heldBy);
end

% -------------------------------------------------------------------------

function openId = listOpenFiles()
%LISTOPENFILES The identifiers of every open file, across releases.
%   fopen('all') was announced for removal in R2024a and REMOVED IN R2025a, and
%   on R2026a it raises MATLAB:fopen:FopenAllStagedRemoval rather than warning.
%   openedFiles is the replacement and was introduced in R2024a, so there is no
%   release in which neither works and the shim needs no third branch.
%
%   The two differ in one way worth knowing: openedFiles excludes the standard
%   input, output and error identifiers 0, 1 and 2, which fopen('all') also
%   omitted, so the loop that consumes this needs no filtering either way.
%
%   Checked with which() rather than a release comparison, because the question
%   is whether the function exists here and that is what which() answers;
%   isMATLABReleaseOlderThan would be an inference from a version string.
%
%   D120 PUT THE SUPPORTED FLOOR AT R2026a, WHERE openedFiles ALWAYS EXISTS, so
%   the fopen('all') branch is unreachable on every supported release. It is
%   kept deliberately and not deleted: which() asks whether the function is
%   here, which stays the right question if the floor ever moves, and the
%   branch costs one comparison. Recorded so the next reader knows it is dead
%   by decision rather than by oversight.

    if isempty(which('openedFiles'))
        openId = reshape(fopen('all'), 1, []);
    else
        openId = reshape(openedFiles(), 1, []);
    end
end

function [folderIsHeld, heldBy] = probeGateway(gatewayFile, mexStillLoaded)
%PROBEGATEWAY Ask the operating system whether the library is still mapped.
%   Opening a loaded DLL for writing is refused on Windows, which is a direct
%   measurement of the property in question rather than an inference from the
%   steps above having run.

    folderIsHeld = false;
    heldBy = "";

    if ~isfile(gatewayFile)
        heldBy = "No MEX gateway is built, so no library holds the folder. " + ...
            "If it still resists deletion, the holder is outside this " + ...
            "toolbox: an Editor tab, the Current Folder browser, or another " + ...
            "process.";
        return
    end

    if ~ispc()
        if mexStillLoaded
            heldBy = "The gateway is still in memory, but this platform " + ...
                "allows a loaded library to be deleted, so the folder is " + ...
                "not held by it.";
        end
        return
    end

    fileId = fopen(gatewayFile, 'r+');
    if fileId < 0
        folderIsHeld = true;
        if mexStillLoaded
            heldBy = "mexGateway is still mapped into this MATLAB process " + ...
                "and Windows locks the folder of a mapped DLL and every " + ...
                "ancestor of it. ""clear mex"" did not release it. The " + ...
                "usual cause is an OpenMP thread pool that outlives the " + ...
                "call; restarting MATLAB is then the only reliable cure.";
        else
            heldBy = "The gateway file cannot be opened for writing although " + ...
                "MATLAB reports it unloaded, so the handle belongs to " + ...
                "another process - a virus scanner, a backup agent or a " + ...
                "second MATLAB session are the candidates.";
        end
        return
    end
    fclose(fileId);

    if mexStillLoaded
        heldBy = "MATLAB lists mexGateway as loaded, but the file can be " + ...
            "opened for writing, so it is not mapped and does not hold the " + ...
            "folder.";
    end
end
