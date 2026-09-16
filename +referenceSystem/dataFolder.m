function folder = dataFolder(newFolder)
%DATAFOLDER Get or set the persistent data folder of the toolbox.
%
%   folder = dataFolder() returns the folder the toolbox reads and writes
%   installed data in, creating it if it does not exist. Without a stored
%   preference this is data/ beside the package, which is what ships.
%
%   folder = dataFolder(path) stores path as the data folder and returns it.
%   The choice PERSISTS ACROSS SESSIONS as a MATLAB preference, so it is made
%   once and not on every call, and no startup.m is needed.
%
%   folder = dataFolder("reset") discards the stored choice and returns the
%   default. Without it a preference would be one-way and the shipped
%   behaviour unreachable, which is a trap rather than a setting.
%
% INPUT ARGUMENTS
%   Name                     Size   Type     Units  Description
%   ----                     ----   ----     -----  -----------
%   newFolder                1x1    string   -      Folder to store, the
%                                                   literal "reset" to discard
%                                                   a stored choice, or omitted
%                                                   to query. Default "".
%
% OUTPUT ARGUMENTS
%   Name                     Size   Type     Units  Description
%   ----                     ----   ----     -----  -----------
%   folder                   1x1    string   -      ABSOLUTE path of the data
%                                                   folder, which exists on
%                                                   return.
%
% METHOD
%   ONE AUTHORITY FOR THE LOCATION, AND THIS IS IT. downloadEop and
%   downloadKernels each carried a private localDefaultCache that composed
%   data/ from their own mfilename, so the toolbox held two answers to one
%   question and neither could be moved. Both now resolve through this
%   function: where a value has more than one definition, the copies are
%   deleted rather than kept equal.
%
%   THE MECHANISM IS setpref AND IT MATCHES shAnalysis DELIBERATELY. The same
%   author maintains both toolboxes and calls shLowLevel.dataFolder with the
%   same three shapes - query, set, "reset" - so the habit transfers and the
%   two do not disagree about where a session's data lives. The preference
%   group is the toolbox name, so nothing here can collide with another
%   toolbox's settings.
%
%   THE FOLDER IS CREATED ON QUERY, WHICH IS A SIDE EFFECT AND IS INTENDED.
%   Every caller of this function is about to read or write in the folder, and
%   returning a path that does not exist moves the mkdir into each of them,
%   where it would be written more than once and eventually forgotten in one
%   place. The alternative - a query that only reports - was considered and
%   rejected because it makes the common path longer to serve a case the
%   toolbox does not have.
%
%   A STORED PREFERENCE IS INVISIBLE IN A SCRIPT, which is the cost of
%   persistence and is stated here rather than discovered. Two identical
%   scripts on two machines can read different files with nothing in the call
%   to say so. Where that matters - a test, a published result, a CI run -
%   pass the folder explicitly through the CacheDir option of downloadEop or
%   downloadKernels, which is unaffected by any preference.
%
% ACCURACY
%   Not applicable; the function resolves a path and computes no numerical
%   quantity.
%
% ERRORS
%   referenceSystem:dataFolder:pathIsAFile
%       The requested folder is an existing FILE, so no folder can be made
%       there. Raised before anything is written, because mkdir would
%       otherwise fail later inside a transfer and report a kernel when the
%       defect is in the argument.
%   referenceSystem:dataFolder:notCreated
%       The folder does not exist and could not be created; the message
%       carries the reason the file system gave.
%
% REFERENCES
%   Handover decision D119 and section C.10. The sibling
%   implementation is shLowLevel.dataFolder in the shAnalysis toolbox.
%
% EXAMPLE
%   % Where does installed data go, and how do I move it off the system disk?
%   folder = referenceSystem.dataFolder()
%   referenceSystem.dataFolder("E:\DATAPOOL\referenceSystem");
%   referenceSystem.downloadKernels(Mode = "download");   % goes there now
%   referenceSystem.dataFolder("reset");                  % back to the default
%
% KEYWORDS
%   data folder, preference, cache, installation, kernels, EOP
%
% See also DOWNLOADKERNELS, DOWNLOADEOP, SETUPREFERENCESYSTEM
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-08-21 18:05 (CEST, UTC+02:00)
% Revised: 2026-08-21 18:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        newFolder (1,1) string = ""
    end

    group = 'referenceSystem';
    preferenceName = 'dataFolder';

    if newFolder == "reset"
        if ispref(group, preferenceName)
            rmpref(group, preferenceName);
        end
        newFolder = "";
    end

    if strlength(strtrim(newFolder)) > 0
        setpref(group, preferenceName, char(strtrim(newFolder)));
    end

    if ispref(group, preferenceName)
        folder = string(getpref(group, preferenceName));
    else
        folder = string(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            'data'));
    end

    if isfile(folder)
        error('referenceSystem:dataFolder:pathIsAFile', ...
            ['The data folder "%s" is an existing FILE, so no folder can be ', ...
            'made there. Name a directory, or a path that does not exist ', ...
            'yet.'], folder);
    end

    if ~isfolder(folder)
        [made, message] = mkdir(char(folder));
        if ~made
            error('referenceSystem:dataFolder:notCreated', ...
                'The data folder "%s" could not be created: %s', folder, message);
        end
    end

    % ABSOLUTE FROM HERE ON. A relative preference would resolve against
    % whatever the working directory happened to be when each caller ran, and
    % two calls in one session could then name different folders. what()
    % answers for a folder that now exists.
    resolved = what(char(folder));
    if ~isempty(resolved)
        folder = string(resolved(1).path);
    end
end
