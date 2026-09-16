function requireFurnished(ephemeris, functionName)
%REQUIREFURNISHED Refuse an ephemeris whose kernels are not the loaded ones.
%
%   requireFurnished(ephemeris, functionName)
%
%   PACKAGE-PRIVATE. SPICE holds one kernel pool per process, and a state or a
%   frame read through it comes from whichever kernels are loaded, not from the
%   struct a caller passes. The MICE consumers call this first, so that the two
%   are the same thing or the call is refused.
%
% INPUT ARGUMENTS
%   Name           Size   Type     Units  Description
%   ----           ----   ----     -----  -----------
%   ephemeris      1x1    struct   -      A readEphemeris result.
%   functionName   1x1    string   -      The public caller, for the identifier.
%
% OUTPUT ARGUMENTS
%   (none)
%
% METHOD
%   The SPK and binary PCK files loaded must be exactly the ones the struct
%   names, and every text kernel it names must be loaded. The comparison is by
%   path, case-insensitive, because readEphemeris furnishes absolute paths. It
%   refuses a struct whose set a later readEphemeris replaced, a struct from
%   before a "clear all" that dropped readEphemeris's record of what it loaded,
%   and an SPK loaded beside the set by other code - each of which would
%   otherwise give states from kernels the struct does not name. Text kernels
%   loaded beside the set are allowed: they carry no ephemeris data.
%
% ACCURACY
%   Not applicable; this function computes nothing.
%
% ERRORS
%   referenceSystem:<caller>:staleEphemeris
%
% REFERENCES
%   NAIF SPICE Toolkit, MICE: cspice_ktotal, cspice_kdata.
%
% EXAMPLE
%   % Not called directly; see barycentricBodyState and rotationIcrfToBodyFixed.
%
% KEYWORDS
%   SPICE, kernel pool, provenance, private
%
% See also READEPHEMERIS, BARYCENTRICBODYSTATE, ROTATIONICRFTOBODYFIXED.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-09-15 22:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    named = lower(string(ephemeris.meta.file(:)));
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
