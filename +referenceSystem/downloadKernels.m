function manifest = downloadKernels(options)
%DOWNLOADKERNELS Fetch the SPICE kernels the MICE provider needs, or list them.
%
%   manifest = downloadKernels()
%   manifest = downloadKernels(Set = "orientation", Mode = "download")
%   manifest = downloadKernels(Mode = "verify")
%
%   THE DEFAULT MODE IS "list" AND DOWNLOADS NOTHING. One entry in this
%   catalogue is 650 MB, so the exploratory call has to be the harmless one;
%   asking for bytes is deliberate, in Mode "download".
%
%   This function is the SINGLE AUTHORITY for where these files come from. The
%   table in data/README.md and section H.7.1 of the handover describe them;
%   this catalogue is what a machine acts on, and a prose table that no code
%   reads is exactly how H.7.1 came to carry a wrong row for four sessions
%   (obligation O26).
%
% INPUT ARGUMENTS
%   (none)
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type              Default    Description
%   ----         ----   ----              -------    -----------
%   Set          1x1    string            "minimal"  How much content:
%                                                    "minimal", "orientation",
%                                                    "smallBodies" or "all".
%                                                    These ACCUMULATE.
%   Span         1x1    string            "short"    Which issue of the
%                                                    planetary ephemeris:
%                                                    "short", "full" or
%                                                    "both".
%   Mode         1x1    string            "list"     "list", "verify" or
%                                                    "download".
%   CacheDir     1x1    string            data/      Destination folder.
%   Timeout      1x1    double            900        Seconds per file.
%   Overwrite    1x1    logical           false      Refetch files already there.
%   Announce     1x1    function_handle   no-op      Called as
%                                                    Announce(name, bytes, index,
%                                                    total) before each transfer.
%   Catalogue    Mx7    table             empty      Entries to use INSTEAD of
%                                                    the built-in catalogue, with
%                                                    variables File, Url, Set,
%                                                    Span, ApproximateBytes,
%                                                    Purpose and Note as below.
%                                                    Empty means the built-in
%                                                    one. Set and Span select
%                                                    from it as from the
%                                                    built-in one. See METHOD.
%
% OUTPUT ARGUMENTS
%   Name                 Size   Type      Units  Description
%   ----                 ----   ----      -----  -----------
%   manifest             Nx10   table     -      One row per catalogue entry.
%   .File                Nx1    string    -      Kernel file name.
%   .Url                 Nx1    string    -      Where it comes from.
%   .Set                 Nx1    string    -      Content group it belongs to.
%   .Span                Nx1    string    -      "short", "full" or "any".
%   .ApproximateBytes    Nx1    double    B      Size for planning. Measured
%                                                where a real fetch has
%                                                reported one; estimated
%                                                otherwise, and estimates here
%                                                have been wrong by 3x.
%   .Purpose             Nx1    string    -      What needs it.
%   .Note                Nx1    string    -      Traps and pairing rules.
%   .Status              Nx1    string    -      "listed", "present", "fetched",
%                                                "reachable", "FAILED | reason".
%   .Bytes               Nx1    double    B      Actual size, once on disk.
%   .Digest              Nx1    string    -      SHA-256, once on disk.
%
% METHOD
%   TWO AXES, BECAUSE THERE ARE TWO INDEPENDENT QUESTIONS.
%
%   Set says HOW MUCH CONTENT, and its values accumulate:
%
%     "minimal"      the planetary ephemeris alone. All P22b needs.
%     "orientation"  adds the text PCK, the binary lunar orientation and the
%                    lunar frame kernel. What P23 needs.
%     "all"          adds sb441-n16.bsp, about 650 MB, for work where the
%                    sixteen D15 perturbing asteroids matter. "smallBodies"
%                    is accepted as a synonym.
%
%   "all" MEANS ALL (decision D99). The size is a real concern, and the
%   protection is that Mode defaults to "list", which shows the bill before
%   anything moves.
%
%   Span says WHICH ISSUE of the planetary ephemeris:
%
%     "short"        de440s.bsp, 1849-12-26 to 2150-01-22, about 31 MB.
%                    Ample for anything GRACE-era and the default.
%     "full"         de440.bsp, 1550 to 2650, of order 120 MB. For epochs
%                    outside the short file.
%     "both"         both files. Decision D114.
%
%   THE TWO FILES ARE THE SAME INTEGRATION - de440s.bsp is a time-restricted
%   issue of de440.bsp - so in the overlap they answer identically and SPICE
%   resolves an overlapping body from whichever was furnished last. That is
%   not a reason to refuse both. D110 settles the principle one level up, for
%   whole generations:
%   this toolbox prevents an UNKNOWING mixture, not a deliberate choice.
%   Holding the small file for routine work and the long one for the
%   occasional deep-time epoch is ordinary, and readEphemeris reports the
%   generation of everything furnished either way. "both" is therefore
%   offered and is not the default; "short" remains the default because it is
%   what almost every caller needs.
%
%   THE SIZE THAT ARGUED FOR THE REFUSAL WAS WRONG BY MORE THAN AN ORDER OF
%   MAGNITUDE. This catalogue carried 2.6 GB for de440.bsp - which is the
%   scale of DE441, not DE440 - and the help, the error message and decision
%   D99's reasoning all leaned on it. de440s.bsp measured 31.2 MB for its
%   300-year span; the same integration over DE440's 1100 years (Park et al.
%   2021) scales to roughly 120 MB, which is what the catalogue now carries,
%   MARKED AS DERIVED AND NOT MEASURED. Mode "verify" or a real fetch records
%   the true figure, and until one does this number is an estimate like the
%   others.
%
%   sum(manifest.ApproximateBytes) is the planning figure for any combination.
%
%   MODE "verify" ISSUES A HEAD REQUEST PER ENTRY AND DOWNLOADS NOTHING. It
%   exists because the URLs below were transcribed from section H.7.1 and could
%   not be checked when they were written - the machine that wrote them had no
%   route to either host. THE FIRST CALLER WITH A NETWORK CLOSES O26 IN ONE
%   CALL rather than discovering a bad path part-way through a 650 MB transfer.
%
%   EVERY ENTRY IS ATTEMPTED AND EVERY FAILURE IS RECORDED BEFORE ANYTHING IS
%   RAISED. A failure on the third of five files must not discard the two that
%   succeeded, so the manifest carries "FAILED | reason" rows, for the same
%   reason runTestSuite writes its report before reporting failure.
%
%   NO LEAPSECONDS KERNEL APPEARS IN THIS CATALOGUE AND NONE MAY BE ADDED.
%   Decision D89: a .tls would install a second leap-second authority beside
%   leapSecondTable, silently, because the two agree until a
%   leapSecondTable("load") override is installed and SPICE does not see it.
%   readEphemeris refuses to furnish one, and a static test asserts that no
%   .tls reaches this catalogue - a rule enforced at both ends of the path.
%
%   Identity is recorded and bulk is not: each fetched file gets a SHA-256 in
%   the manifest, which is what a result should carry (data/README.md).
%
%   A CALLER'S CATALOGUE. Catalogue replaces the built-in table,
%   so a user with a private kernel mirror can point every Url at it, and a
%   test can point one at a host that cannot resolve and observe a failed
%   transfer on any machine - which is what made the D98 test deterministic.
%   It is held to the same rules as the built-in one: the seven descriptive
%   variables must be present (badCatalogue), and a leapseconds kernel is
%   refused (D89, leapSecondKernelInCatalogue). Status, Bytes and Digest are
%   added as for the built-in rows.
%
% ACCURACY
%   Not applicable; this function transfers files and computes no quantity.
%   ApproximateBytes is the published size and is for planning only; Bytes is
%   measured from the file on disk.
%
% ERRORS
%   referenceSystem:downloadKernels:unknownSet
%   referenceSystem:downloadKernels:unknownSpan
%   referenceSystem:downloadKernels:unknownMode
%   referenceSystem:downloadKernels:cacheNotWritable
%   referenceSystem:downloadKernels:badCatalogue
%   referenceSystem:downloadKernels:leapSecondKernelInCatalogue
%   referenceSystem:downloadKernels:notReachable
%       Raised for one catalogue entry in Mode "verify" when the server does
%       not answer OK, and caught: that row's Status reads "FAILED | " and the
%       message, and incompleteFetch is warned. It never leaves the function.
%
% WARNINGS
%   referenceSystem:downloadKernels:incompleteFetch
%       At least one entry failed. THIS IS A WARNING AND NOT AN ERROR because
%       the manifest is the artifact: a function that throws returns nothing,
%       so raising here would destroy the record of everything that succeeded.
%       Decision D98, taken after the first real run reported zero kernels
%       while four were on disk. Inspect Status and retry the FAILED rows.
%
% REFERENCES
%   NAIF generic kernels, https://naif.jpl.nasa.gov/pub/naif/generic_kernels/
%   JPL SSD small-body ephemerides, https://ssd.jpl.nasa.gov/ftp/eph/
%   Folkner, W. M. et al., 2014, IPN Progress Report 42-196 (DE430/DE431).
%   Park, R. S. et al., 2021, Astron. J. 161, 105 (DE440 and DE441).
%   Handover sections H.7.1, H.7.5; decisions D13, D15, D26, D89; O26.
%
% EXAMPLE
%   referenceSystem.downloadKernels()                       % see the plan
%   referenceSystem.downloadKernels(Mode = "verify")        % check the URLs
%   referenceSystem.downloadKernels(Set = "orientation", Mode = "download")
%   referenceSystem.downloadKernels(Set = "all", Span = "full")   % the lot
%
% KEYWORDS
%   SPICE, kernel, NAIF, DE440, SPK, PCK, download, catalogue, provenance
%
% See also READEPHEMERIS, DOWNLOADEOP, SETUPREFERENCESYSTEM, EPHEMERISBODIES.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-29 09:15 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.Set (1,1) string = "minimal"
        options.Span (1,1) string = "short"
        options.Mode (1,1) string = "list"
        options.CacheDir (1,1) string = localDefaultCache()
        options.Timeout (1,1) double {mustBePositive} = 900
        options.Overwrite (1,1) logical = false
        options.Announce (1,1) function_handle = @(varargin) []
        options.Catalogue table = table()
    end

    if ~ismember(options.Mode, ["list", "verify", "download"])
        error('referenceSystem:downloadKernels:unknownMode', ...
            'Mode is "%s"; it must be "list", "verify" or "download".', ...
            options.Mode);
    end

    if isempty(options.Catalogue)
        manifest = localCatalogue();
    else
        manifest = localCallerCatalogue(options.Catalogue);
    end
    localRefuseLeapSecondKernel(manifest);
    manifest = manifest(localSelect(manifest, options.Set, options.Span), :);

    if options.Mode == "list"
        return
    end

    if options.Mode == "download"
        localRequireCache(options.CacheDir);
    end

    for k = 1:height(manifest)
        target = fullfile(options.CacheDir, manifest.File(k));

        if options.Mode == "download" && isfile(target) && ~options.Overwrite
            manifest.Status(k) = "present";
            [manifest.Bytes(k), manifest.Digest(k)] = localDescribe(target);
            continue
        end

        options.Announce(manifest.File(k), manifest.ApproximateBytes(k), k, ...
            height(manifest));

        try
            if options.Mode == "verify"
                localHead(manifest.Url(k), options.Timeout);
                manifest.Status(k) = "reachable";
            else
                localFetch(manifest.Url(k), target, options.Timeout);
                manifest.Status(k) = "fetched";
                [manifest.Bytes(k), manifest.Digest(k)] = localDescribe(target);
            end
        catch failure
            % RECORDED, NOT RAISED, AND THE LOOP CONTINUES. See METHOD.
            % A 404 additionally asks the server what the directory DOES
            % hold, because "not found" is a dead end and "not found, but
            % these five files match" is a fix. This is O26 answered by a
            % mechanism rather than by another careful transcription.
            manifest.Status(k) = "FAILED | " + string(failure.message) + ...
                localSuggestAlternatives(manifest.Url(k), options.Timeout);
        end
    end

    failed = startsWith(manifest.Status, "FAILED");
    if any(failed)
        % A WARNING AND NOT AN ERROR, AND REV. 1.134 HAD THIS WRONG. That
        % revision claimed run 44's lesson was "applied before the fact":
        % complete the manifest, then raise. But a MATLAB function that throws
        % RETURNS NOTHING, so raising destroyed the very artifact whose
        % survival was the point - the first real run reported "0 kernels"
        % while four sat on disk. runTestSuite gets away with the same shape
        % only because its artifact is a FILE, which outlives the exception;
        % here the artifact IS the return value. Decision D98.
        warning('referenceSystem:downloadKernels:incompleteFetch', ...
            ['%d of %d kernels could not be %s; the other %d are fine. The ', ...
            'returned manifest carries a FAILED row for each, with any ', ...
            'alternative file names found on the server. First failure: %s'], ...
            sum(failed), height(manifest), ...
            ternary(options.Mode == "verify", "reached", "fetched"), ...
            sum(~failed), manifest.Status(find(failed, 1)));
    end
end

% =========================== local functions ===========================

function catalogue = localCatalogue()
%LOCALCATALOGUE The files, their homes and their traps.
%
%   Transcribed from handover section H.7.1. NOT VERIFIED AGAINST THE HOSTS at
%   the time of writing - see Mode "verify", which exists for exactly that.

    naif = "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/";
    ssd = "https://ssd.jpl.nasa.gov/ftp/eph/";

    file = [ ...
        "de440s.bsp"; ...
        "pck00011.tpc"; ...
        "pck00011_n0066.tpc"; ...
        "moon_pa_de440_200625.bpc"; ...
        "moon_de440_250416.tf"; ...
        "sb441-n16.bsp"; ...
        "de440.bsp"];

    url = [ ...
        naif + "spk/planets/de440s.bsp"; ...
        naif + "pck/pck00011.tpc"; ...
        naif + "pck/pck00011_n0066.tpc"; ...
        naif + "pck/moon_pa_de440_200625.bpc"; ...
        naif + "fk/satellites/moon_de440_250416.tf"; ...
        ssd + "small_bodies/asteroids_de441/sb441-n16.bsp"; ...
        naif + "spk/planets/de440.bsp"];

    % TWO AXES, BECAUSE THERE ARE TWO INDEPENDENT CHOICES. Set is how much
    % CONTENT is wanted and its values accumulate. Span is which issue of the
    % planetary ephemeris to take: "short", "full" or, since D114, "both".
    % de440s.bsp is the same integration as de440.bsp restricted to
    % 1849-2150, so the two agree in the overlap and SPICE resolves an
    % overlapping body from whichever was furnished last - a reason to say
    % which was taken, not a reason to refuse the pair (D110's principle,
    % applied to one generation instead of two). Collapsing the two axes
    % into one is what forced "all" to mean "all except the biggest file"
    % at rev. 1.134 (decision D99).
    set = [ ...
        "minimal"; "orientation"; "orientation"; "orientation"; ...
        "orientation"; "smallBodies"; "minimal"];

    span = [ ...
        "short"; "any"; "any"; "any"; "any"; "any"; "full"];

    approximateBytes = [ ...
        % MEASURED where a real fetch has reported one, estimated otherwise.
        % de440s.bsp came back at 31.2 MB against an estimate of 32 MB;
        % moon_pa_de440_200625.bpc at 12.3 MB against an estimate of 40, which
        % is why the estimated ones are marked as such rather than trusted.
        %
        % de440.bsp CARRIED 2.6e9 UNTIL REV. 1.191 AND THAT WAS DE441's SCALE,
        % NOT DE440's. Derived instead: de440s.bsp measures 31.2 MB for
        % 1849-2150, and de440.bsp is the same integration at the same
        % Chebyshev degree over 1550-2650 (Park et al. 2021), so 1100/300 of
        % 31.2 MB is about 115 MB. 120e6 is carried as a planning figure that
        % errs high. STILL AN ESTIMATE: only a verify or a fetch makes it a
        % measurement, and this catalogue's estimates have been wrong by 3x
        % before and by 23x here.
        32.7e6; 130e3; 130e3; 12.9e6; 5e3; 650e6; 120e6];

    purpose = [ ...
        "Planetary and lunar ephemeris DE440, 1849-12-26 to 2150-01-22."; ...
        "Generic text PCK: the machine-readable WGCCRE encoding (P23)."; ...
        "The same data for SPICE toolkits older than N0067."; ...
        "Binary lunar orientation, the DE440 libration (D14)."; ...
        "Frame kernel defining the lunar PA and ME frames (D14)."; ...
        "The sixteen perturbing asteroids DE440/441 was integrated with."; ...
        "Full DE440, 1550 to 2650. Only for epochs outside the short file."];

    % URL STATUS AS OF THE 2026-07-29 VERIFY RUN ON A REAL NETWORK: the four
    % entries in the "orientation" set returned 200 and are CONFIRMED, and
    % moon_de440_250416.tf comes from that run's directory listing.
    % sb441-n16.bsp and de440.bsp were not in that set and remain UNCHECKED.
    note = [ ...
        "URL confirmed 2026-07-29. Ample for anything GRACE-era; the " + ...
            "default. The same integration as de440.bsp over a shorter " + ...
            "span, so the two agree where they overlap."; ...
        "URL confirmed 2026-07-29. " + ...
        "REQUIRES SPICE Toolkit N0067 or newer, or Mars system orientation " + ...
            "may cause fatal memory corruption rather than a wrong number."; ...
        "URL confirmed 2026-07-29. Identical to pck00011.tpc but for one " + ...
            "Phobos phase angle."; ...
        "URL confirmed 2026-07-29, 12.3 MB measured. Pairs with the lunar " + ...
            "frame kernel. The PAIRING with moon_de440_250416.tf is NOT " + ...
            "yet verified: read the frame kernel comments once furnished."; ...
        "URL confirmed 2026-07-29. Supersedes moon_de440_220930.tf, which " + ...
            "was catalogued here in error and returns 404. Defines the " + ...
            "lunar PA and ME frames; pairs with moon_pa_de440_200625.bpc."; ...
        "JPL SSD, NOT a NAIF generic kernel. Do NOT substitute " + ...
            "codes_300ast_20100725.bsp: it is a DE405-era set and pairing " + ...
            "it with DE440 is the D15 generation error."; ...
        "UNCHECKED URL. Of order 120 MB - DERIVED by scaling de440s.bsp's " + ...
            "measured 31.2 MB from 300 to 1100 years, NOT measured; the " + ...
            "2.6 GB this row carried until rev. 1.191 was DE441's scale. " + ...
            "The same integration as de440s.bsp over a longer span; take " + ...
            "either, or both on request (D114). Mirrored at " + ...
            ssd + "planets/bsp/de440.bsp."];

    count = numel(file);
    catalogue = table(file, url, set, span, approximateBytes, purpose, note, ...
        repmat("listed", count, 1), nan(count, 1), strings(count, 1), ...
        'VariableNames', ["File", "Url", "Set", "Span", "ApproximateBytes", ...
        "Purpose", "Note", "Status", "Bytes", "Digest"]);
end

function catalogue = localCallerCatalogue(given)
%LOCALCALLERCATALOGUE A caller's catalogue, in the built-in layout (rev. 1.233).
%
%   The seven descriptive variables are required and taken by name, so their
%   order in the caller's table does not matter; the three the transfer fills
%   are added exactly as localCatalogue adds them.

    required = ["File", "Url", "Set", "Span", "ApproximateBytes", "Purpose", "Note"];
    missing = required(~ismember(required, string(given.Properties.VariableNames)));
    if ~isempty(missing)
        error('referenceSystem:downloadKernels:badCatalogue', ...
            ['A Catalogue must carry the variables %s; it is missing %s. The ', ...
            'names are those of the manifest this function returns.'], ...
            strjoin(required, ", "), strjoin(missing, ", "));
    end
    count = height(given);
    catalogue = table(string(given.File), string(given.Url), string(given.Set), ...
        string(given.Span), double(given.ApproximateBytes), string(given.Purpose), ...
        string(given.Note), repmat("listed", count, 1), nan(count, 1), ...
        strings(count, 1), 'VariableNames', ["File", "Url", "Set", "Span", ...
        "ApproximateBytes", "Purpose", "Note", "Status", "Bytes", "Digest"]);
end

function localRefuseLeapSecondKernel(catalogue)
%LOCALREFUSELEAPSECONDKERNEL D89, for the built-in catalogue and a caller's.
%
%   ASSERTED IN CODE AND NOT ONLY IN THE HELP. A leapseconds kernel in the
%   catalogue would be furnished by a caller who trusted it, so no catalogue
%   this function acts on may describe one - since rev. 1.233 that includes one
%   the caller supplied.

    if any(endsWith(lower(catalogue.File), ".tls"))
        error('referenceSystem:downloadKernels:leapSecondKernelInCatalogue', ...
            ['A leapseconds kernel is present in the catalogue. Decision ', ...
            'D89 forbids it: leapSecondTable is the single leap-second ', ...
            'authority and SPICE does not see its overrides.']);
    end
end

function selected = localSelect(catalogue, setName, spanName)
%LOCALSELECT Rows matching a cumulative Set and an exclusive Span.
%
%   "all" MEANS ALL. It did not until decision D99: rev. 1.134 gave it the
%   meaning "everything except the biggest file", wrote that into the help, and
%   added a test asserting it - documenting and enforcing a name that lied.
%   The size was a real concern and the answer was a bad one; the real
%   protection is that Mode defaults to "list", so asking for everything shows
%   the bill before anything is transferred.

    switch setName
        case "minimal"
            wanted = "minimal";
        case "orientation"
            wanted = ["minimal", "orientation"];
        case {"smallBodies", "all"}
            wanted = ["minimal", "orientation", "smallBodies"];
        otherwise
            error('referenceSystem:downloadKernels:unknownSet', ...
                ['Set is "%s"; it must be "minimal", "orientation", ', ...
                '"smallBodies" or "all", which accumulate in that order. ', ...
                'The length of the planetary ephemeris is the SEPARATE ', ...
                'option Span, because de440s.bsp and de440.bsp are the same ', ...
                'integration and not two steps of one.'], setName);
    end

    if ~ismember(spanName, ["short", "full", "both"])
        error('referenceSystem:downloadKernels:unknownSpan', ...
            ['Span is "%s"; it must be "short" (de440s.bsp, 1849-2150, ', ...
            '31 MB), "full" (de440.bsp, 1550-2650, of order 120 MB) or ', ...
            '"both". The two files are one integration over different ', ...
            'intervals, so in the overlap they agree and SPICE takes ', ...
            'whichever was furnished last; holding both is a deliberate ', ...
            'choice this function offers rather than refuses (D114).'], ...
            spanName);
    end

    if spanName == "both"
        wantedSpan = ["any", "short", "full"];
    else
        wantedSpan = ["any", spanName];
    end

    selected = ismember(catalogue.Set, wanted) & ...
        ismember(catalogue.Span, wantedSpan);
end

function localRequireCache(cacheDir)
%LOCALREQUIRECACHE Make the destination, or say why it cannot be made.

    if isfolder(cacheDir)
        return
    end
    [made, message] = mkdir(cacheDir);
    if ~made
        error('referenceSystem:downloadKernels:cacheNotWritable', ...
            'Cannot create "%s": %s', cacheDir, message);
    end
end

function suggestion = localSuggestAlternatives(url, timeout)
%LOCALSUGGESTALTERNATIVES Ask the parent directory what it actually contains.
%
%   NAIF and JPL SSD both serve directory listings, so a wrong file name can be
%   turned into the right one without a human going to look. Returns "" when
%   the listing cannot be read - a failed suggestion must never mask the
%   failure it was trying to explain.

    suggestion = "";
    try
        parts = split(url, "/");
        parent = join(parts(1:end - 1), "/") + "/";
        wanted = parts(end);
        [~, ~, extension] = fileparts(wanted);

        listing = string(webread(parent, weboptions('Timeout', timeout, ...
            'ContentType', 'text')));
        found = regexp(listing, 'href="([^"?/][^"]*)"', 'tokens');
        found = unique(string(cellfun(@(c) c{1}, found, 'UniformOutput', false)));
        found = found(endsWith(found, extension));

        if isempty(found)
            return
        end
        suggestion = " | " + parent + " holds: " + strjoin(found, ", ");
    catch
        % Deliberately silent: see the note above.
    end
end

function localHead(url, timeout)
%LOCALHEAD Ask whether a URL resolves, without transferring the body.

    request = matlab.net.http.RequestMessage( ...
        matlab.net.http.RequestMethod.HEAD);
    httpOptions = matlab.net.http.HTTPOptions('ConnectTimeout', timeout);
    response = request.send(matlab.net.URI(url), httpOptions);
    if response.StatusCode ~= matlab.net.http.StatusCode.OK
        error('referenceSystem:downloadKernels:notReachable', ...
            '%s returned %s', url, string(response.StatusCode));
    end
end

function localFetch(url, target, timeout)
%LOCALFETCH Transfer to a temporary name, then move.
%
%   A part-written kernel with the right name is worse than no kernel: it is
%   indistinguishable from a good one until cspice_furnsh fails somewhere deep,
%   and on a 650 MB transfer an interruption is not a remote possibility. The
%   file only takes its real name once it is complete - the rule
%   writeInterpolant already follows.

    temporary = target + ".partial";
    cleanup = onCleanup(@() localDiscard(temporary));
    websave(temporary, url, weboptions('Timeout', timeout, ...
        'ContentType', 'binary'));
    movefile(temporary, target);
end

function localDiscard(temporary)
%LOCALDISCARD Remove a partial transfer if one survived.

    if isfile(temporary)
        delete(temporary);
    end
end

function [bytes, digest] = localDescribe(target)
%LOCALDESCRIBE Size and SHA-256 of a file on disk.

    info = dir(target);
    bytes = info.bytes;

    digester = java.security.MessageDigest.getInstance('SHA-256');
    stream = java.io.FileInputStream(java.io.File(char(target)));
    cleanup = onCleanup(@() stream.close());
    buffer = zeros(1, 1048576, 'int8');
    count = stream.read(buffer);
    while count > 0
        digester.update(buffer, 0, count);
        count = stream.read(buffer);
    end
    digest = string(lower(reshape(dec2hex(typecast( ...
        digester.digest(), 'uint8')).', 1, [])));
end

function cacheDir = localDefaultCache()
%LOCALDEFAULTCACHE The toolbox data folder, from its one authority.
%
%   D119: this function used to compose data/ from its own mfilename, and so
%   did its twin in the sibling downloader. Two definitions of one location
%   cannot be moved together, and a caller who set one was surprised by the
%   other. Both now ask referenceSystem.dataFolder.

    cacheDir = referenceSystem.dataFolder();
end

function value = ternary(condition, whenTrue, whenFalse)
%TERNARY Select one of two values without an if in the middle of a message.

    if condition
        value = whenTrue;
    else
        value = whenFalse;
    end
end
