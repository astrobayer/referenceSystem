function ephemerisPool(command, argument, functionName)
%EPHEMERISPOOL The SPICE kernel pool as this toolbox furnishes and reads it.
%
%   ephemerisPool("furnish", absolutePath)
%   ephemerisPool("require", ephemeris, functionName)
%
%   PACKAGE-PRIVATE. SPICE holds one kernel pool per process, and a state or a
%   frame read through it comes from whichever kernels are loaded, not from the
%   struct a caller passes. This function makes the two the same thing:
%   "furnish" unloads the set it furnished last and loads the new one, and
%   "require" refuses a struct whose kernels are not the ones SPICE would
%   answer from.
%
% INPUT ARGUMENTS
%   Name           Size   Type     Units  Description
%   ----           ----   ----     -----  -----------
%   command        1x1    string   -      "furnish" or "require".
%   argument       Kx1    string   -      "furnish": absolute kernel paths.
%                  1x1    struct   -      "require": a readEphemeris result.
%   functionName   1x1    string   -      "require": the public caller, for
%                                         the identifier.
%
% OUTPUT ARGUMENTS
%   (none)
%
% METHOD
%   ONE FURNISHED SET AT A TIME. "furnish" unloads, by path, every kernel the
%   previous call loaded before it loads the new set, so two readEphemeris
%   results never share the pool. Kernels loaded outside this toolbox are left
%   alone.
%
%   "require" compares the pool with the struct: the SPK and binary PCK files
%   loaded must be exactly the ones the struct names, and every text kernel it
%   names must be loaded. The comparison is by path, case-insensitive, because
%   readEphemeris furnishes absolute paths. It therefore also refuses a struct
%   whose set was unloaded by a later readEphemeris, a struct from before a
%   "clear all" that dropped the record of what was loaded, and an SPK loaded
%   beside the set by other code - each of which would otherwise give states
%   from kernels the struct does not name.
%
% ACCURACY
%   Not applicable; this function computes nothing.
%
% ERRORS
%   referenceSystem:<caller>:staleEphemeris
%
% REFERENCES
%   NAIF SPICE Toolkit, MICE: cspice_furnsh, cspice_unload, cspice_ktotal,
%     cspice_kdata.
%
% EXAMPLE
%   % Not called directly; see readEphemeris and barycentricBodyState.
%
% KEYWORDS
%   SPICE, kernel pool, furnish, unload, provenance, private
%
% See also READEPHEMERIS, BARYCENTRICBODYSTATE, ROTATIONICRFTOBODYFIXED.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-09-15 22:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    persistent furnished
    if isempty(furnished)
        furnished = strings(0, 1);
    end

    switch command
        case "furnish"
            for k = 1:numel(furnished)
                cspice_unload(char(furnished(k)));
            end
            furnished = strings(0, 1);
            for k = 1:numel(argument)
                cspice_furnsh(char(argument(k)));
                furnished(end + 1, 1) = argument(k); %#ok<AGROW> a handful of kernels
            end

        case "require"
            named = lower(string(argument.meta.file(:)));
            binary = endsWith(named, [".bsp", ".bpc"]);
            loadedBinary = lower([localLoaded('SPK'); localLoaded('PCK')]);
            loadedText = lower(localLoaded('TEXT'));
            foreign = setdiff(loadedBinary, named(binary));
            absent = [setdiff(named(binary), loadedBinary); ...
                setdiff(named(~binary), loadedText)];
            if ~isempty(foreign) || ~isempty(absent)
                error(sprintf('referenceSystem:%s:staleEphemeris', functionName), ...
                    ['The SPICE pool does not hold the kernels this ephemeris ', ...
                    'names, so a state read through it would come from other ', ...
                    'files. Not loaded: %s. Loaded but not named: %s. Call ', ...
                    'readEphemeris again and pass its result; one furnished set ', ...
                    'is live at a time.'], localList(absent), localList(foreign));
            end
    end
end

% =========================== local functions ===========================

function file = localLoaded(kind)
%LOCALLOADED Paths of the loaded kernels of one kind.

    count = cspice_ktotal(kind);
    file = strings(count, 1);
    for k = 1:count
        file(k) = string(cspice_kdata(k, kind));
    end
end

function text = localList(file)
%LOCALLIST A readable list, "none" when empty.

    if isempty(file)
        text = "none";
    else
        text = strjoin(file, ", ");
    end
end
