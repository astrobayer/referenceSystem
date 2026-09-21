function ephemeris = readEphemeris(kernelFile, options)
%READEPHEMERIS Furnish NAIF kernels and record what was furnished.
%
%   ephemeris = readEphemeris(kernelFile)
%   ephemeris = readEphemeris(kernelFile, Name, Value)
%
%   The only cspice_furnsh wrapper the toolbox permits (decision D26). It reads
%   each kernel's comment area, records identity rather than content, refuses
%   combinations that would be wrong in ways nothing downstream could notice,
%   and only then loads the set - in place of the set it loaded before.
%
% INPUT ARGUMENTS
%   Name         Size   Type              Units  Description
%   ----         ----   ----              -----  -----------
%   kernelFile   1xK    string | char     -      Kernel paths, in load order.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name              Size   Type      Default  Description
%   ----              ----   ----      -------  -----------
%   ExpectedEphemeris 1x1    string    ""       Planetary ephemeris the kernels
%                                               must name, e.g. "DE440". Empty
%                                               takes the name from the first
%                                               SPK and requires the rest to
%                                               agree with it.
%   AllowGenerations  1xG    string    []       Generations the caller has
%                                               DECIDED belong together, e.g.
%                                               ["DE440" "DE441"]. A mixed set
%                                               is always accepted; naming it
%                                               here stops the warning, for
%                                               exactly that set and nothing
%                                               wider. Empty warns on any
%                                               mixture, which is the default.
%   Digest            1x1    logical   true     Compute a SHA-256 of each file.
%
% OUTPUT ARGUMENTS
%   Name              Size   Type      Units  Description
%   ----              ----   ----      -----  -----------
%   ephemeris         1x1    struct    -      Handle for the body-state functions.
%   .meta             1x1    struct    -      Provenance, fields below.
%   .meta.file        Kx1    string    -      Absolute paths as furnished.
%   .meta.digest      Kx1    string    -      SHA-256, or "" when Digest false.
%   .meta.ephemeris   1x1    string    -      Planetary ephemeris named by the
%                                             SPK comment areas, or the value of
%                                             ExpectedEphemeris when none names
%                                             one. Read generationVerified
%                                             before believing it.
%   .meta.generations 1xG    string    -      Every distinct planetary ephemeris
%                                             named across the comment areas.
%                                             Normally one entry; more only
%                                             when AllowGenerations lifted the
%                                             D15 refusal.
%   .meta.generationVerified
%                     1x1    logical   -      True when the name was READ from a
%                                             comment area; false when nothing
%                                             could be read and the field is the
%                                             caller's own declaration (D15).
%   .meta.toolkit     1x1    string    -      cspice_tkvrsn('TOOLKIT').
%   .meta.bodies      Nx6    table     -      Bodies the set covers, in the
%                                             ephemerisBodies layout.
%
% METHOD
%   IDENTITY TRAVELS AND BULK DOES NOT. de440.bsp is about 2.6 GB and
%   sb441-n16.bsp about 650 MB against a whole toolbox of roughly two megabytes.
%   Nothing here copies, caches or bundles a kernel; meta records the filename
%   and a digest, which is what a result must carry to be reproducible and what
%   an archive can afford to carry. This is the rule data/README.md states and
%   the same rule mexSourceDigest applies to the C sources.
%
%   THE KERNEL PAIRING IS MEASURED, NOT DECLARED (decision D15, and D110 for
%   what happens when it disagrees: a warning, never a refusal). SB441-N16
%   pairs with DE440/441 and SB431-N16 with DE430; mixing
%   generations shifts the barycentre by of order 100 km, and nothing downstream
%   would report it. Each SPK names the planetary ephemeris it expects in its
%   own comment area, which cspice_dafec reads, so the pairing is checked
%   against what the files say rather than against what the caller believes.
%
%   A LEAPSECONDS KERNEL IS REFUSED (decision D89), AND THAT IS A SEAM DECISION
%   RATHER THAN AN INCONVENIENCE. cspice_spkezr takes TDB seconds past J2000
%   directly and convertTimeScale already reaches TDB, so a .tls would install a
%   second leap-second authority beside leapSecondTable - finding M-2 in a new
%   place, and a silent one, because the two agree until the day a
%   leapSecondTable("load") override is installed and SPICE does not see it.
%   Seam contract S1 item 2 exists to make that impossible by construction.
%
%   ONE FURNISHED SET IS LIVE AT A TIME. SPICE keeps one kernel pool per
%   process and answers from whatever is loaded, whatever struct a caller
%   passes. So every check runs before anything is loaded - a refused set
%   leaves the pool as it was - and loading unloads the set this function
%   loaded last. The MICE consumers (barycentricBodyState, geocentricBodyState,
%   bodyRotationElements, rotationIcrfToBodyFixed) refuse a struct whose
%   kernels are not exactly the loaded SPK and binary PCK files with
%   staleEphemeris, so an older result cannot quietly read a newer set. To
%   compare two generations, furnish them together in one call. Inside a
%   parfor worker the pool is the worker's own: call this function there.
%
%   THE TOOLKIT VERSION IS A CHECKED PRECONDITION AND NOT AN ASSUMPTION, because
%   pck00011.tpc's Mars system data used with Toolkit N0066 or earlier may cause
%   fatal run-time memory corruption in the calling process rather than a wrong
%   number. NAIF ships pck00011_n0066.tpc for that case. The check costs one
%   call to cspice_tkvrsn and this function refuses rather than proceeds.
%
% ACCURACY
%   Not applicable; this function computes nothing. The accuracy of a state
%   obtained through the furnished kernels is the kernel's own - about 1 m for
%   DE440 in the current century, the tier decision D13 adopts as the target -
%   and it is reported by ephemerisBodies for the resulting set, not here.
%
% ERRORS
%   referenceSystem:readEphemeris:miceUnavailable
%   referenceSystem:readEphemeris:fileNotFound
%   referenceSystem:readEphemeris:leapSecondKernelRefused
%   referenceSystem:readEphemeris:mismatchedGeneration
%   referenceSystem:readEphemeris:toolkitTooOld
%
% WARNINGS
%   referenceSystem:readEphemeris:mixedGenerations
%       The furnished kernels name more than one planetary ephemeris. A
%       WARNING and not an error since decision D110: the choice of models and
%       of their combination belongs to the caller, and comparing two
%       generations is ordinary work. Silenced for a set named in
%       AllowGenerations.
%   referenceSystem:readEphemeris:generationNotVerified
%       ExpectedEphemeris was given and no comment area names a generation, so
%       the pairing could not be measured. A warning and not an error: a kernel
%       without that metadata is unusual, not wrong, and refusing it would make
%       a good file unusable over a comment.
%
% REFERENCES
%   NAIF SPICE Toolkit, MICE for MATLAB, https://naif.jpl.nasa.gov/naif/toolkit_MATLAB.html
%   NAIF generic kernels, https://naif.jpl.nasa.gov/pub/naif/generic_kernels/
%   JPL SSD small-body SPKs, https://ssd.jpl.nasa.gov/ftp/eph/small_bodies/asteroids_de441/
%   Folkner, W.M. et al., 2014, IPN Progress Report 42-196 (DE430/DE431).
%   Handover decisions D13, D15, D26, D89 and section H.7.1.
%
% EXAMPLE
%   eph = referenceSystem.readEphemeris("data/de440s.bsp");
%   r = referenceSystem.geocentricBodyState("moon", t, Source = "mice", ...
%       Ephemeris = eph);
%
% KEYWORDS
%   SPK, kernel, NAIF, MICE, DE440, ephemeris, provenance, digest, furnsh
%
% See also BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, EPHEMERISBODIES.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 11:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        kernelFile (1,:) string {mustBeNonempty}
        options.ExpectedEphemeris (1,1) string = ""
        options.AllowGenerations (1,:) string = string.empty
        options.Digest (1,1) logical = true
    end

    % THE REFUSALS COME FIRST, BEFORE MICE IS EVEN LOOKED FOR. A .tls must be
    % refused on a machine without MICE too, or the guard would only hold where
    % it is least likely to be tested.
    localRefuseLeapSecondKernel(kernelFile);

    missing = ~isfile(kernelFile);
    if any(missing)
        error('referenceSystem:readEphemeris:fileNotFound', ...
            ['%d of %d kernels were not found; the first is "%s". Kernels ', ...
            'are not bundled: see section H.7.1 of the handover for the ', ...
            'download locations, and note that sb441-n16.bsp is a JPL SSD ', ...
            'file and is NOT on the NAIF generic tree.'], ...
            sum(missing), numel(kernelFile), kernelFile(find(missing, 1)));
    end

    toolkit = localRequireMice();
    localRequireToolkitVersion(kernelFile, toolkit);

    absolutePath = strings(numel(kernelFile), 1);
    for k = 1:numel(kernelFile)
        info = dir(kernelFile(k));
        absolutePath(k) = string(fullfile(info.folder, info.name));
    end

    digest = strings(numel(kernelFile), 1);
    if options.Digest
        for k = 1:numel(kernelFile)
            digest(k) = localDigest(absolutePath(k));
        end
    end

    [namedEphemeris, generationVerified, generations] = localCheckPairing( ...
        absolutePath, options.ExpectedEphemeris, options.AllowGenerations);

    % Loaded last, after every refusal above, in place of the previous set.
    localFurnish(absolutePath);

    ephemeris = struct('meta', struct( ...
        'file', absolutePath, ...
        'digest', digest, ...
        'ephemeris', namedEphemeris, ...
        'generations', generations, ...
        'generationVerified', generationVerified, ...
        'toolkit', toolkit, ...
        'bodies', localCoveredBodies(absolutePath)));
end

% =========================== local functions ===========================

function localFurnish(absolutePath)
%LOCALFURNISH Unload the set loaded last, then load this one.
%   The record is this function's own: only readEphemeris furnishes kernels
%   (decision D26), so only it can know what it loaded. Kernels loaded outside
%   this toolbox are left alone.
    persistent furnished
    if isempty(furnished)
        furnished = strings(0, 1);
    end
    for k = 1:numel(furnished)
        cspice_unload(char(furnished(k)));
    end
    furnished = strings(0, 1);
    for k = 1:numel(absolutePath)
        cspice_furnsh(char(absolutePath(k)));
        furnished(end + 1, 1) = absolutePath(k); %#ok<AGROW> a handful of kernels
    end
end

function localRefuseLeapSecondKernel(kernelFile)
%LOCALREFUSELEAPSECONDKERNEL Decision D89, enforced rather than documented.

    isLeapSecondKernel = endsWith(lower(kernelFile), ".tls");
    if any(isLeapSecondKernel)
        error('referenceSystem:readEphemeris:leapSecondKernelRefused', ...
            ['"%s" is a leapseconds kernel and this toolbox will not ', ...
            'furnish one. Loading it would install a second leap-second ', ...
            'authority beside leapSecondTable, silently, because the two ', ...
            'agree until a leapSecondTable("load") override is installed ', ...
            'and SPICE does not see it. None is needed: cspice_spkezr takes ', ...
            'TDB seconds past J2000 and convertTimeScale already produces ', ...
            'them (decision D89).'], kernelFile(find(isLeapSecondKernel, 1)));
    end
end

function toolkit = localRequireMice()
%LOCALREQUIREMICE Resolve MICE or say exactly where to get it.

    if exist('cspice_tkvrsn', 'file') ~= 2 && exist('cspice_tkvrsn', 'file') ~= 3
        error('referenceSystem:readEphemeris:miceUnavailable', ...
            ['The NAIF MICE toolkit is not on the MATLAB path. It is free ', ...
            'and is at https://naif.jpl.nasa.gov/naif/toolkit_MATLAB.html . ', ...
            'Nothing else in this toolbox needs it: the bundled SOFA ', ...
            'provider works out of the box at the accuracy ', ...
            'ephemerisBodies tabulates.']);
    end
    toolkit = string(cspice_tkvrsn('TOOLKIT'));
end

function localRequireToolkitVersion(kernelFile, toolkit)
%LOCALREQUIRETOOLKITVERSION The pck00011 crash, refused rather than risked.

    needsN0067 = any(endsWith(lower(kernelFile), "pck00011.tpc"));
    if ~needsN0067
        return
    end

    token = regexp(toolkit, 'N(\d+)', 'tokens', 'once');
    if isempty(token) || str2double(token{1}) < 67
        error('referenceSystem:readEphemeris:toolkitTooOld', ...
            ['pck00011.tpc carries Mars system rotation data that requires ', ...
            'SPICE Toolkit N0067 or newer; this toolkit reports "%s". With ', ...
            'an older toolkit the Mars, Phobos or Deimos orientation may ', ...
            'cause fatal run-time memory corruption in this process rather ', ...
            'than return a wrong number, which is why this is refused and ', ...
            'not warned about. NAIF ships pck00011_n0066.tpc for older ', ...
            'toolkits.'], toolkit);
    end
end

function digest = localDigest(fileName)
%LOCALDIGEST SHA-256 of a file, streamed so a 2.6 GB kernel does not load.

    digester = java.security.MessageDigest.getInstance('SHA-256');
    stream = java.io.FileInputStream(java.io.File(char(fileName)));
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

function [namedEphemeris, generationVerified, generations] = localCheckPairing( ...
        absolutePath, expected, allowed)
%LOCALCHECKPAIRING D15's rule, answered from the comment areas.
%
%   The comment area is the kernel's own statement of which planetary ephemeris
%   it belongs to; commnt -r prints it and cspice_dafec reads it. Asking the
%   file is the difference between a measured pairing and a declared one.
%
%   IT NEVER REFUSES A COMBINATION (decision D110). Two labels can differ for
%   a reason that is not a different fit - DE440 and DE441 are one solution
%   over two spans - and a user comparing two generations deliberately is
%   doing ordinary work. The disagreement is reported, in meta.generations and
%   in a warning; the judgement is the caller's. The one thing still refused
%   is a stated ExpectedEphemeris that none of the files supports, because
%   that is a check the caller explicitly asked to have made.
%
%   AND IT REPORTS WHEN IT COULD NOT ASK (rev. 1.165). Until run 68 this
%   function returned the caller's own ExpectedEphemeris whenever no comment
%   area named a generation, and meta.ephemeris then carried a DECLARED value
%   that was indistinguishable from a measured one - which is the exact
%   distinction D15 exists to draw. Run 68 found it the only way it could be
%   found: a test asked for a mismatch to be refused, and nothing was refused.
%   generationVerified is now returned beside the name, false means nothing was
%   read from any file, and a caller who stated an expectation is warned rather
%   than quietly agreed with.

    isSpk = endsWith(lower(absolutePath), ".bsp");
    named = strings(0, 1);
    source = strings(0, 1);

    for k = find(isSpk).'
        % cspice_dafec TAKES A DAF HANDLE, NOT A FILE NAME, and three
        % arguments. This was wrong from rev. 1.134 until the first real SPK
        % reached it: every kernel-backed test until now furnished only
        % pck00011.tpc, which is a TEXT kernel and not a DAF, so isSpk was
        % false and this branch never ran. A green suite proved only that
        % nothing had tried it.
        handle = cspice_dafopr(char(absolutePath(k)));
        closeHandle = onCleanup(@() cspice_dafcls(handle));
        comment = strings(0, 1);
        done = false;
        while ~done
            % string(chunk) AND NOT string(chunk(:)). REV. 1.168, AND THIS ONE
            % LINE IS WHY D15's PAIRING CHECK NEVER ONCE FIRED. cspice_dafec
            % returns a CHAR MATRIX of bufsiz rows by lenout columns, and
            % string() of a char matrix gives one string PER ROW - which is
            % what a comment line is. chunk(:) flattens it column-major into
            % 100 000 single characters first, so string() then produced
            % 100 000 one-character strings and the strjoin below put a space
            % between every letter: "D E 4 4 0". No pattern could ever match,
            % on any kernel, and the check has been silently inert since it
            % was written at rev. 1.127.
            %
            % Found by a NOTES row reporting "43077 lines" for one comment
            % area (rev. 1.167). That is a CHARACTER count wearing a line
            % count's label, and no assertion caught it - the test that was
            % supposed to read the comment area independently had copied this
            % same loop, so the two agreed (obligation O23).
            [chunk, done] = cspice_dafec(handle, 100, 1000);
            comment = [comment; string(chunk)];   %#ok<AGROW>
        end
        clear closeHandle

        % THE PADDING IS NUL, NOT BLANK. The unused tail of each fixed-width
        % row comes back as char(0), which strtrim does not remove and which
        % turns a text file into a binary one the moment it is written out.
        comment = strip(erase(comment, char(0)));
        comment = comment(strlength(comment) > 0);
        token = regexp(strjoin(comment, " "), 'DE-?(\d{3})', 'tokens', 'once');
        if ~isempty(token)
            named(end + 1, 1) = "DE" + string(token{1}); %#ok<AGROW>
            source(end + 1, 1) = absolutePath(k); %#ok<AGROW>
        end
    end

    generations = reshape(unique(named), 1, []);

    if isempty(named)
        namedEphemeris = expected;
        generationVerified = false;
        if expected ~= ""
            % ONE WARNING, NOT AN ERROR. A kernel whose comment area names no
            % generation is unusual but not wrong, and refusing it would make
            % a legitimate file unusable over a piece of METADATA. What may
            % not happen is silence: the caller asserted a pairing, nothing
            % confirmed it, and meta.generationVerified now says so on every
            % call rather than only in this message.
            warning('referenceSystem:readEphemeris:generationNotVerified', ...
                ['ExpectedEphemeris is "%s" and NO furnished kernel names ', ...
                'a planetary ephemeris in its comment area, so the ', ...
                'expectation could not be checked against anything. ', ...
                'meta.ephemeris carries your declaration, not a measured ', ...
                'value, and meta.generationVerified is false. Decision D15 ', ...
                'requires the pairing to be measured; this is the case ', ...
                'where it cannot be.'], expected);
        end
        return
    end
    generationVerified = true;

    distinct = unique(named);
    if numel(distinct) > 1
        % IT WARNS. IT DOES NOT REFUSE (decision D110, rev. 1.176, and this
        % REPLACES D15's refusal clause).
        %
        % D15 refused a mixed set because mixing generations is not harmless
        % and "nothing downstream would report it". The first half is still
        % true; THE SECOND HALF STOPPED BEING TRUE. When D15 was written this
        % function had no way to tell anyone: there was no meta field carrying
        % the finding, no WARNINGS section in the report and no NOTES section.
        % All three exist now, so the choice is no longer between refusing and
        % silence - which is the only pair of options that justified refusing.
        %
        % AND THE REFUSAL WAS WRONG ABOUT WHAT IT WAS SEEING. It compares
        % LABELS. DE440 and DE441 were fit to the SAME DATA SET and differ
        % only in the lunar core damping assumption - below 1 m in the planets
        % over DE440's span and below 2 m in the Moon across 1970-2020 (Park
        % et al. 2021, AJ 161:105) - so a legitimate pairing was refused;
        % meanwhile a user who wants to
        % compare two generations deliberately - which is ordinary work - was
        % refused the comparison outright and had to go around the toolbox to
        % do it. **A library that will not let you do the thing you came to do
        % is not protecting you.** The judgement is the user's; this function's
        % duty is to make sure they cannot make it unknowingly.
        namedEphemeris = strjoin(sort(distinct), "+");
        generationVerified = true;
        if isempty(allowed) || ~all(ismember(distinct, allowed))
            warning('referenceSystem:readEphemeris:mixedGenerations', ...
                ['The furnished SPKs name more than one planetary ', ...
                'ephemeris in their comment areas: %s. This may be exactly ', ...
                'what you intend - DE440 and DE441 were fit to the same ', ...
                'data set and differ by under 1 m in the planets and under ', ...
                '2 m in the Moon over 1970-2020 (Park et al. 2021), and ', ...
                'comparing two generations deliberately is ordinary work. ', ...
                'It is NOT harmless if unintended: the barycentre moved ', ...
                'about 100 km between DE430 and DE440, and SPICE resolves ', ...
                'an overlapping body from whichever kernel was furnished ', ...
                'last. meta.generations lists what was found; name the set ', ...
                'in AllowGenerations once you have decided, and this ', ...
                'warning stops.'], strjoin(distinct, ", "));
        end
        if expected ~= "" && ~ismember(expected, distinct)
            error('referenceSystem:readEphemeris:mismatchedGeneration', ...
                ['ExpectedEphemeris is "%s" and the furnished kernels name ', ...
                '%s. A mixed set is allowed; a stated expectation that none ', ...
                'of the files supports is not, because you asked for it to ', ...
                'be checked.'], expected, strjoin(distinct, ", "));
        end
        return
    end

    namedEphemeris = distinct;
    if expected ~= "" && expected ~= namedEphemeris
        error('referenceSystem:readEphemeris:mismatchedGeneration', ...
            ['ExpectedEphemeris is "%s" but the kernels name "%s" in their ', ...
            'comment areas. The files are the authority here; correct the ', ...
            'expectation or furnish the kernels you meant.'], ...
            expected, namedEphemeris);
    end
end

function bodies = localCoveredBodies(absolutePath)
%LOCALCOVEREDBODIES What the kernels contain, asked of the kernels.
%
%   The registry the MICE provider reports is the union of the SPK body tables,
%   not a hard-coded list: de440s.bsp and de440.bsp cover different intervals
%   and sb441-n16.bsp adds sixteen asteroids, so a fixed table would report a
%   body that cannot be evaluated the first time a different kernel was used.

    naifId = [];
    for k = 1:numel(absolutePath)
        if ~endsWith(lower(absolutePath(k)), ".bsp")
            continue
        end
        naifId = union(naifId, double(cspice_spkobj(char(absolutePath(k)), 100)));
    end
    naifId = naifId(:);

    % CANONICAL NAMES WHERE THEY EXIST, SYNTHETIC ONES ONLY WHERE THEY DO NOT.
    % This table first answered to "naif10" and never to "sun", which meant the
    % MICE provider could not be reached by any name a caller would use and the
    % whole point of the provider split - the SAME name working with either
    % source - was lost. The mapping is taken from ephemerisBodies rather than
    % restated, so there is still exactly one place that knows a body's NAIF
    % identifier. Asteroids and anything else the bundled registry does not
    % name keep the naif<id> form, which is addressable and honest.
    known = referenceSystem.ephemerisBodies();
    name = "naif" + string(naifId);
    for k = 1:numel(naifId)
        match = known.NaifId == naifId(k);
        if any(match)
            name(k) = known.Body(find(match, 1));
        end
    end

    count = numel(naifId);
    bodies = table( ...
        name, ...
        naifId, ...
        repmat("cspice_spkezr", count, 1), ...
        nan(count, 1), ...
        nan(count, 1), ...
        nan(count, 1), ...
        'VariableNames', ["Body", "NaifId", "Model", "PositionError", ...
        "VelocityError", "BodyIndex"]);

    % THE ACCURACY COLUMNS ARE NaN AND THAT IS DELIBERATE. A kernel does not
    % state its own accuracy, and inventing one here would be exactly the
    % "far below" this project refuses everywhere else. They are filled when a
    % measured comparison exists - see section H.7.6, which requires the
    % DE440 minus DE441 residual to be measured rather than assumed negligible.
end
