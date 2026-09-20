function scaleInfo = timeScale(name)
%TIMESCALE Registry of the time scales this toolbox understands.
%
%   scaleInfo = timeScale(name) validates and canonicalises a time-scale name
%   and returns its properties. scaleTable = timeScale("list") returns every
%   supported scale as a table.
%
%   This is the single authority for the set of scale names and for which of
%   them are uniform (handover principle 2). Without it the same list would be
%   repeated in normalizeEpoch, convertTimeScale, addSeconds, secondsBetween
%   and fundamentalArguments, which is the two-sources-of-truth pattern behind
%   findings M-2 and C-2. It is the time-scale counterpart of the frame
%   registry of handover section B.3.
%
% INPUT ARGUMENTS
%   Name       Size   Type            Units  Description
%   ----       ----   ----            -----  -----------
%   name       1x1    string | char   -      Scale name, any case, or "list".
%
% OUTPUT ARGUMENTS
%   Name             Size   Type      Units  Description
%   ----             ----   ----      -----  -----------
%   scaleInfo        1x1    struct    -      Properties of one scale, below.
%   .name            1x1    string    -      Canonical upper-case name.
%   .isUniform       1x1    logical   -      True if the scale runs without
%                                            steps, so that seconds may be
%                                            added to it directly.
%   .isLeapBearing   1x1    logical   -      True if the scale carries UTC leap
%                                            seconds (UTC and GLONASS).
%   .description     1x1    string    -      One-line description.
%
%   For name == "list" the output is instead an Nx4 table with variables
%   name, isUniform, isLeapBearing and description.
%
% METHOD
%   Eleven scales are supported: the atomic and dynamical scales TAI, TT, TDB,
%   TCG and TCB, the rotation-derived scales UTC and UT1, and the satellite
%   navigation scales GPS, GST, BDT and GLONASS. Names are matched
%   case-insensitively and returned upper case, because the IERS and BIPM
%   symbols are upper-case acronyms and no two of them differ only in case, so
%   folding the case resolves nothing and invents nothing.
%
%   No aliases exist. The v1 converter accepted GAL for GST, BEIDOU for BDT and
%   GLONASST for GLONASS; design principle 12 removes them, so exactly one
%   spelling names each scale and a call site cannot disguise which it means.
%
%   Nothing here is cached, and the comment at the head of the body records the
%   measurement that says caching it made the function slower rather than
%   faster. The function is a pure function of its argument with no state at
%   all, so two callers cannot interfere by any route.
%
%   isUniform is false for UTC and GLONASS only. It is the property that
%   decides whether addSeconds and secondsBetween may work directly on an
%   epoch: a second of UTC is not a second of proper time across a leap second,
%   and GLONASS inherits that because it is UTC advanced by three hours.
%
% ACCURACY
%   Not applicable; the function computes no numerical quantity.
%
% ERRORS
%   referenceSystem:timeScale:unknownScale
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 1 and Table 1.1.
%   BIPM, The International System of Units (SI), 9th edition, 2019, Ch. 2.3.1.
%   IS-GPS-200, Galileo OS SIS ICD, BDS-SIS-ICD-B1I, GLONASS ICD (system times).
%
% EXAMPLE
%   info = referenceSystem.timeScale("tt");
%   assert(info.name == "TT" && info.isUniform);
%   supported = referenceSystem.timeScale("list");
%
% KEYWORDS
%   time scale, TAI, TT, TDB, TCG, TCB, UTC, UT1, GPS, GST, BDT, GLONASS
%
% See also NORMALIZEEPOCH, CONVERTTIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 19:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        name (1,1) string
    end

    % NOT CACHED, AND THAT IS A MEASURED DECISION (prompt P28, rev. 1.84).
    % Rev. 1.81 held these four arrays in persistents on the theory that
    % rebuilding them 20 times per rotation was the cost. Host-normalised
    % against eight functions the change did not touch, the cache made this
    % function 1.30x SLOWER: four persistent lookups and an isempty guard cost
    % more than four small literals. iersConstants, which reads ONE persistent
    % holding one struct, went 6.08x the other way in the same measurement.
    % The literals were never the cost here. What costs is the arguments block
    % validating (1,1) string, the strcmpi sweep and the struct assembly, and
    % none of those is cacheable - so the fix is to be called 20 times less,
    % not to be faster 20 times.
    canonicalName = ["TAI"; "TT"; "TDB"; "TCG"; "TCB"; "UTC"; "UT1"; ...
        "GPS"; "GST"; "BDT"; "GLONASS"];
    isUniform = [true; true; true; true; true; false; true; ...
        true; true; true; false];
    isLeapBearing = ~isUniform;
    description = [ ...
        "International Atomic Time"
        "Terrestrial Time, TAI + 32.184 s"
        "Barycentric Dynamical Time"
        "Geocentric Coordinate Time"
        "Barycentric Coordinate Time"
        "Coordinated Universal Time, TAI minus leap seconds"
        "Universal Time, UTC + Delta UT1"
        "GPS system time, nominally TAI - 19 s"
        "Galileo system time, nominally equal to GPS time"
        "BeiDou system time, nominally TAI - 33 s"
        "GLONASS system time, nominally UTC + 3 h"];

    if strcmpi(name, "list")
        scaleInfo = table(canonicalName, isUniform, isLeapBearing, description, ...
            'VariableNames', {'name', 'isUniform', 'isLeapBearing', 'description'});
        return
    end

    index = find(strcmpi(canonicalName, name), 1);
    if isempty(index)
        error('referenceSystem:timeScale:unknownScale', ...
            ['Unknown time scale "%s". Supported scales are %s. ', ...
            'The v1 aliases GAL, BEIDOU and GLONASST were removed; use ', ...
            'GST, BDT and GLONASS.'], name, strjoin(canonicalName, ', '));
    end

    scaleInfo = struct( ...
        'name', canonicalName(index), ...
        'isUniform', isUniform(index), ...
        'isLeapBearing', isLeapBearing(index), ...
        'description', description(index));
end
