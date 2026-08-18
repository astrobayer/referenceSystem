function fixtureFile = fetchHorizonsVectors(options)
%FETCHHORIZONSVECTORS Retrieve JPL HORIZONS state vectors as a P22 test fixture.
%
%   fixtureFile = fetchHorizonsVectors()
%   fixtureFile = fetchHorizonsVectors('Body', "499", 'BodyName', "Mars")
%   fixtureFile = fetchHorizonsVectors('Center', "@399", 'ExpectedSource', "DE441")
%
%   Builds one HORIZONS API query per body, checks the response header against
%   what was asked for, and writes the geometric state vectors into a plain text
%   fixture that a P22 test can read. It is the reference-truth half of D13: the
%   ephemeris reader is validated against HORIZONS, not against itself.
%
%   THIS IS A FIXTURE-GENERATION INSTRUMENT AND LIVES IN test/, NOT IN THE
%   PACKAGE. downloadEop is a package function because the toolbox needs EOP to
%   run; nothing in the toolbox needs HORIZONS to run. What HORIZONS supplies is
%   reference truth for a test, and reference truth belongs to the test tree. It
%   is therefore outside Contents.m, the generated function reference and the
%   provenance scans, and it adds no test method.
%
% INPUT ARGUMENTS
%   (none)
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size  Type     Default                 Description
%   ----        ----  ----     -------                 -----------
%   Body        1xN   string   see METHOD              HORIZONS COMMAND codes,
%                                                      one per body.
%   BodyName    1xN   string   see METHOD              Expected target name, one
%                                                      per body. Checked against
%                                                      the response, not assumed.
%   Center      1x1   string   "@0"                    Coordinate origin. "@0" is
%                                                      the solar system
%                                                      barycentre, "@399" the
%                                                      geocentre.
%   JulianDate  1xM   double   see METHOD              Epochs, TDB Julian dates.
%                                                      Must be exact; see METHOD.
%   ExpectedSource
%               1x1   string   "DE441"                 Ephemeris the response
%                                                      must name in its
%                                                      {source: ...} tag. A
%                                                      mismatch is an error.
%                                                      HORIZONS serves DE441;
%                                                      see METHOD.
%   Output      1x1   string   "horizonsVectors.txt"   Fixture to write.
%   Timeout     1x1   double   60                      Seconds per request.
%
% OUTPUT ARGUMENTS
%   Name         Size  Type    Units  Description
%   ----         ----  ------  -----  -----------
%   fixtureFile  1x1   string  -      Absolute path of the fixture written.
%
% METHOD
%   THE PARAMETERS ARE ALL STATED AND NONE IS LEFT TO A DEFAULT, because four of
%   the HORIZONS defaults silently invalidate the comparison and one of them is
%   large. REF_PLANE defaults to ECLIPTIC, so accepting it compares across the
%   IAU76 obliquity of 84381.448 arcseconds - an error that does not look like
%   an error. VEC_CORR must be NONE, because light-time and stellar aberration
%   are not applied by SPK evaluation and are hundreds of kilometres for the
%   outer planets. REF_SYSTEM is ICRF and TIME_TYPE is TDB. Handover section
%   H.7.3 carries the full table and the reasoning.
%
%   THE RESPONSE IS CHECKED BEFORE IT IS BELIEVED, TWICE. HORIZONS names the
%   ephemeris it used and the target it resolved. If HORIZONS has moved to a
%   release newer than the kernel under test, the comparison measures HORIZONS'
%   upgrade rather than the toolbox - so the named ephemeris must match
%   'Ephemeris' or this function errors. The same applies to the body: a
%   COMMAND code that resolves to a different object than intended produces
%   perfectly clean numbers for the wrong thing, which is this domain's
%   characteristic failure. Both checks refuse rather than warn.
%
%   THE EPOCHS ARE CHOSEN SO THAT THE JULIAN DATE IS EXACT, AND THAT IS NOT
%   FUSSINESS. A Julian date near 2460000 resolves about 21 microseconds in
%   double precision. The Earth moves 30 km/s, so 21 microseconds is 0.6 m -
%   comparable to D13's 1 m accuracy target. An epoch passed as a rounded
%   decimal JD would therefore spend a large part of the error budget on time
%   transfer and the test would be measuring the wrong thing. The default
%   epochs are exact 0h TDB instants, whose Julian dates end in .5 and are
%   exactly representable, so the comparison tests the ephemeris and nothing
%   else. Any epoch supplied through 'JulianDate' is checked for exact
%   representability and refused if it is not.
%
%   HORIZONS IS A DE441 ORACLE AND NOT A DE440 ONE, AND THAT IS NOT A NAMING
%   DETAIL (decision D91, rev. 1.129). Horizons was moved to the DE440/441
%   solution in April 2021 and serves the long-span member; every vector
%   response tags its target and centre {source: DE441}. DE440 and DE441 are
%   fit to the same data, but DE441 assumes no damping between the lunar liquid
%   core and the solid mantle so that a backward integration does not diverge,
%   and it is therefore LESS accurate than DE440 for the current century. They
%   are two integrations, not two names for one, and the difference is
%   concentrated in the lunar solution - which matters here, because the Moon
%   is one of the default bodies.
%
%   The expected source therefore defaults to DE441, which is what the service
%   actually serves, and a response naming anything else is refused. Accepting
%   DE441 silently while validating a DE440 kernel would be exactly the
%   mixed-generation error D15 forbids. What to do about the residual is a
%   question for P22 and is recorded in handover section H.7.6, not decided
%   here: this function's job is to fetch honestly and to say what it fetched.
%
%   WHAT RUN 44 CONFIRMED, SO THAT NOBODY RE-DERIVES IT. Four bodies returned
%   correctly on the first attempt, which establishes the whole query shape:
%   the frame and correction parameters, the TDB time type, and - the one thing
%   rev. 1.128 flagged as documented but untested - MULTI-EPOCH TLIST IN ONE
%   GET QUERY. Three epochs came back in one response. The caveat is withdrawn.
%
%   WHAT IT REFUTED: `COMMAND=1;`, the small-body designator form for Ceres,
%   sent as a name-value pair. webread encoded the spaces of TLIST as "+" and
%   left the semicolon raw, and a raw semicolon is a reserved sub-delimiter
%   that the server answered 400. The URL is now assembled and encoded here.
%   **Whether `1;` then RESOLVES is a separate question this function does not
%   assume**: if it does not, the bodyMismatch guard names what came back
%   instead, and `2000001` and `Ceres` are the alternatives to try.
%
%   THE FIXTURE KEEPS HORIZONS' OWN UNITS. Distances are km and velocities
%   km/s, as returned. A fixture records what the source said; converting to SI
%   on the way in would put a transformation between the authority and the
%   assertion, and the test can divide by a thousand itself.
%
%   DEFAULT BODIES: Sun (10), Moon (301), Mars barycentre (4), Jupiter
%   barycentre (5) and Ceres ("1;", the small-body designator form; "2000001"
%   is the SPK body ID and may or may not resolve here - the bodyMismatch guard
%   reports whatever HORIZONS actually returned, so a wrong code names itself). The first four
%   exercise the planetary kernel across four orders of magnitude in distance;
%   Ceres exercises the small-body kernel and the D15 pairing. DEFAULT EPOCHS:
%   2000-01-01, 2015-01-01 and 2025-01-01, all 0h TDB.
%
% ACCURACY
%   Retrieval only; nothing here computes a state. The numbers are HORIZONS'
%   to the precision it prints, which under CSV_FORMAT is ample for D13's 1 m
%   tier even at Neptune's distance, where 1 m is 2e-10 relative and needs
%   about eleven significant digits. The fixture records the printed digits
%   unchanged so a later reader can check that claim rather than trust it.
%
% ERRORS
%   referenceSystem:fetchHorizonsVectors:requestFailed
%   referenceSystem:fetchHorizonsVectors:inexactEpoch
%   referenceSystem:fetchHorizonsVectors:ephemerisMismatch
%   referenceSystem:fetchHorizonsVectors:bodyMismatch
%   referenceSystem:fetchHorizonsVectors:unparseableResponse
%   referenceSystem:fetchHorizonsVectors:cannotWriteFixture
%   referenceSystem:fetchHorizonsVectors:incompleteFixture
%
% REFERENCES
%   JPL HORIZONS API, https://ssd-api.jpl.nasa.gov/doc/horizons.html
%   JPL HORIZONS manual, https://ssd.jpl.nasa.gov/horizons/manual.html
%   Handover sections H.7.3 and H.7.5, decisions D13 and D15.
%
% EXAMPLE
%   fixtureFile = fetchHorizonsVectors('Output', "fixtures/horizonsDe441.txt");
%
% KEYWORDS
%   HORIZONS, ephemeris, state vector, fixture, DE440, validation, P22
%
% See also DOWNLOADEOP, PROFILEROTATIONCALL.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 17:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.Body (1,:) string = ["10", "301", "4", "5", "1;"]
        options.BodyName (1,:) string = ["Sun", "Moon", "Mars Barycenter", ...
            "Jupiter Barycenter", "Ceres"]
        options.Center (1,1) string = "@0"
        options.JulianDate (1,:) double = [2451544.5, 2457023.5, 2460676.5]
        options.ExpectedSource (1,1) string = "DE441"
        options.Output (1,1) string = "horizonsVectors.txt"
        options.Timeout (1,1) double {mustBePositive} = 60
    end

    if numel(options.Body) ~= numel(options.BodyName)
        error('referenceSystem:fetchHorizonsVectors:bodyMismatch', ...
            ['Body and BodyName must have one entry each; they have %d and ', ...
            '%d.'], numel(options.Body), numel(options.BodyName));
    end
    localRequireExactEpochs(options.JulianDate);

    record = strings(0, 1);
    header = strings(0, 1);
    failure = strings(0, 1);

    % EVERY BODY IS ATTEMPTED AND THE FIXTURE IS WRITTEN FROM WHAT SUCCEEDED.
    % Run 44 lost four good responses because the fifth returned 400 - four
    % HTTP round trips discarded to report one failure that the other four had
    % nothing to do with. runTestSuite already settled this question for the
    % test report: the report is WRITTEN and THEN the error is raised, because
    % the results that did run are still worth reading. The same rule applies
    % to a fixture, and a partial fixture that says so is worth more than no
    % fixture at all.
    for k = 1:numel(options.Body)
        fprintf('Requesting %s (COMMAND=%s) ...\n', options.BodyName(k), ...
            options.Body(k));
        try
            [url, responseText] = localRequest(options.Body(k), options, ...
                options.Timeout);
            localVerifyResponse(responseText, options.Body(k), ...
                options.BodyName(k), options.ExpectedSource);

            header(end+1, 1) = "REQUEST | " + options.BodyName(k) + ...
                " | " + url; %#ok<AGROW>
            header(end+1, 1) = "SOURCE | " + options.BodyName(k) + " | " + ...
                localEphemerisLine(responseText); %#ok<AGROW>
            record = [record; localParseVectors(responseText, ...
                options.BodyName(k), options.Body(k))]; %#ok<AGROW>
        catch cause
            fprintf('  FAILED: %s\n', cause.message);
            failure(end+1, 1) = "FAILED | " + options.BodyName(k) + " | " + ...
                options.Body(k) + " | " + cause.identifier + " | " + ...
                replace(cause.message, newline, " "); %#ok<AGROW>
        end
    end

    if isempty(record)
        error('referenceSystem:fetchHorizonsVectors:requestFailed', ...
            ['Every request failed, so there is nothing to write. First ', ...
            'failure: %s'], failure(1));
    end

    fixtureFile = localWriteFixture(options, header, record, failure);
    fprintf('Fixture written to %s\n', fixtureFile);

    % RAISED AFTER THE FIXTURE IS WRITTEN, NOT INSTEAD OF IT. A caller that
    % only checks for an exception must not treat a partial fixture as a whole
    % one, so this still throws - but the file is on disk first and names both
    % what was retrieved and what was not.
    if ~isempty(failure)
        error('referenceSystem:fetchHorizonsVectors:incompleteFixture', ...
            ['%d of %d bodies failed and are recorded in %s, which holds the ', ...
            '%d that succeeded. First failure: %s'], numel(failure), ...
            numel(options.Body), fixtureFile, ...
            numel(options.Body) - numel(failure), failure(1));
    end
end

% =========================== local functions ===========================

function localRequireExactEpochs(julianDate)
%LOCALREQUIREEXACTEPOCHS Refuse an epoch the double cannot hold exactly.
%   A Julian date near 2460000 resolves about 21 us, which is 0.6 m of Earth
%   motion and a large part of D13's 1 m budget. An epoch at 0h TDB has a
%   Julian date ending in .5 and is exact; anything else spends the budget on
%   time transfer. The test is refused rather than run at a silently degraded
%   tolerance.
    isExact = mod(julianDate, 0.5) == 0;
    if ~all(isExact)
        offending = find(~isExact, 1);
        error('referenceSystem:fetchHorizonsVectors:inexactEpoch', ...
            ['Julian date %d, %.9f, is not an exact half day. A JD near ', ...
            '2460000 resolves about 21 us in double precision, which is ', ...
            '0.6 m of Earth motion and comparable to the 1 m accuracy this ', ...
            'fixture exists to demonstrate. Use instants at 0h or 12h TDB, ', ...
            'whose Julian dates are exactly representable.'], ...
            offending, julianDate(offending));
    end
end

function [url, responseText] = localRequest(body, options, timeout)
%LOCALREQUEST One HORIZONS query, with every parameter stated and encoded.
%   NOTHING IS LEFT TO A DEFAULT. REF_PLANE in particular defaults to ECLIPTIC
%   and would rotate the whole comparison by the IAU76 obliquity; see the
%   METHOD block and handover section H.7.3.
%
%   THE URL IS ASSEMBLED AND PERCENT-ENCODED HERE RATHER THAN LEFT TO webread,
%   AND RUN 44 IS THE REASON. Passed as name-value pairs, webread encoded the
%   spaces in TLIST as "+" and left the semicolon of the small-body designator
%   COMMAND=1; untouched. A bare semicolon is a reserved sub-delimiter in a
%   query string - historically an alternative parameter separator - and the
%   server answered 400. Encoding a defined unsafe set here makes the outgoing
%   URL exactly what this function decided it should be.
%
%   THE UNSAFE SET IS DELIBERATELY SMALL. "@" is NOT encoded, because CENTER=@0
%   is proven to work unencoded by the four bodies that succeeded in run 44,
%   and there is no reason to change a character with positive evidence behind
%   it while fixing one that has evidence against it.
    endpoint = "https://ssd.jpl.nasa.gov/api/horizons.api";
    timeList = join(compose("%.1f", options.JulianDate(:)'), " ");

    query = [ ...
        "format",      "text"; ...
        "MAKE_EPHEM",  "YES"; ...
        "EPHEM_TYPE",  "VECTORS"; ...
        "COMMAND",     body; ...
        "CENTER",      options.Center; ...
        "REF_PLANE",   "FRAME"; ...
        "REF_SYSTEM",  "ICRF"; ...
        "VEC_CORR",    "NONE"; ...
        "OUT_UNITS",   "KM-S"; ...
        "TIME_TYPE",   "TDB"; ...
        "TLIST_TYPE",  "JD"; ...
        "TLIST",       timeList; ...
        "VEC_TABLE",   "2"; ...
        "VEC_LABELS",  "NO"; ...
        "CSV_FORMAT",  "YES"; ...
        "OBJ_DATA",    "YES"];

    % OBJ_DATA stays YES although it costs a page of text: the object data
    % sheet is where HORIZONS names what it resolved, and that name is checked
    % rather than assumed.

    url = endpoint + "?" + join(query(:,1)' + "=" + ...
        arrayfun(@localEncode, query(:,2)'), "&");

    requestOptions = weboptions('ContentType', 'text', 'Timeout', timeout);
    try
        responseText = string(webread(url, requestOptions));
    catch cause
        error('referenceSystem:fetchHorizonsVectors:requestFailed', ...
            'The HORIZONS request for COMMAND=%s failed: %s', body, cause.message);
    end
end

function encoded = localEncode(value)
%LOCALENCODE Percent-encode the characters a query string may not carry raw.
%   Only the characters that have caused a failure or are unambiguously
%   reserved are touched. Everything else, "@" included, is passed through, so
%   this function cannot silently change a request that already worked.
    % The percent sign is replaced FIRST, or the escapes introduced below would
    % themselves be escaped.
    encoded = replace(value, "%", "%25");
    encoded = replace(encoded, " ", "%20");
    encoded = replace(encoded, ";", "%3B");
    encoded = replace(encoded, "'", "%27");
    encoded = replace(encoded, "&", "%26");
    encoded = replace(encoded, "#", "%23");
    encoded = replace(encoded, "+", "%2B");
end

function localVerifyResponse(responseText, body, bodyName, expectedSource)
%LOCALVERIFYRESPONSE Refuse a response that is not what was asked for.
%   TWO CHECKS, BOTH REFUSING RATHER THAN WARNING. The ephemeris check is the
%   D15-shaped one: if HORIZONS has moved past the kernel under test, the
%   comparison measures HORIZONS' upgrade. The body check guards this domain's
%   characteristic failure - a wrong object returns numbers that are smooth,
%   plausible and about something else.
    if ~contains(responseText, "$$SOE")
        error('referenceSystem:fetchHorizonsVectors:unparseableResponse', ...
            ['The response for COMMAND=%s carries no $$SOE marker, so no ', ...
            'ephemeris block was produced. First 300 characters:\n%s'], ...
            body, extractBefore(responseText, min(300, strlength(responseText))));
    end

    reportedSource = localEphemerisLine(responseText);
    if ~strcmpi(reportedSource, expectedSource)
        error('referenceSystem:fetchHorizonsVectors:ephemerisMismatch', ...
            ['The response for %s names ephemeris "%s", not "%s". HORIZONS ', ...
            'reports its source in a {source: ...} tag on the target and ', ...
            'centre lines; if it has moved past the kernel under test then ', ...
            'the comparison measures that move rather than the toolbox. ', ...
            'Note that HORIZONS serves DE441, NOT DE440 - the two are ', ...
            'different integrations, not two names for one, and D91 records ', ...
            'what follows from that.'], bodyName, reportedSource, expectedSource);
    end

    targetLine = localMatchLine(responseText, 'Target body name:\s*([^\r\n]*)');
    if strlength(targetLine) > 0 && ~contains(upper(targetLine), upper(bodyName))
        error('referenceSystem:fetchHorizonsVectors:bodyMismatch', ...
            ['COMMAND=%s resolved to "%s", which does not contain the ', ...
            'expected name "%s". A COMMAND code that resolves to the wrong ', ...
            'object returns clean numbers about something else.'], ...
            body, strtrim(targetLine), bodyName);
    end
end

function source = localEphemerisLine(responseText)
%LOCALEPHEMERISLINE The ephemeris HORIZONS names, out of its {source: } tag.
%   THE FIRST VERSION OF THIS MATCHED THE WRONG LINE AND THE FIRST RUN FOUND IT.
%   It searched for "Ephemeris" and hit the banner - "Ephemeris / API_USER Tue
%   Jul 28 01:05:42 2026 Pasadena, USA / Horizons" - which names a user and a
%   timestamp and no ephemeris at all. HORIZONS states its source in a
%   {source: XXXX} tag appended to the "Target body name:" and "Center body
%   name:" lines, and nowhere else in a vector response.
%
%   The tag is parsed rather than the line, so the check compares an ephemeris
%   NAME against an ephemeris name instead of asking whether one string occurs
%   somewhere in a page of text - which is what let the banner defeat it.
    source = localMatchLine(responseText, '\{source:\s*([A-Za-z0-9\-]+)\s*\}');
    if strlength(source) == 0
        source = "unreported";
    end
    source = strtrim(source);
end

function line = localMatchLine(responseText, pattern)
%LOCALMATCHLINE First match of a pattern, or an empty string.
%   The patterns exclude the line break explicitly. MATLAB's regexp defaults to
%   'dotall', so a bare . or a negated class crosses newlines and a greedy
%   match swallows the file; obligation O24 records what that cost.
    token = regexp(responseText, pattern, 'tokens', 'once');
    if isempty(token)
        token = regexp(responseText, pattern, 'match', 'once');
    end
    if isempty(token)
        line = "";
    else
        line = string(token(1));
    end
end

function record = localParseVectors(responseText, bodyName, body)
%LOCALPARSEVECTORS The CSV rows between the $$SOE and $$EOE markers.
%   VEC_TABLE=2 with VEC_LABELS=NO gives JDTDB, calendar date, X, Y, Z, VX, VY,
%   VZ. The calendar field is kept as HORIZONS wrote it: it is the only
%   human-readable check that the epoch requested is the epoch returned.
    block = extractBetween(responseText, "$$SOE", "$$EOE");
    if isempty(block)
        error('referenceSystem:fetchHorizonsVectors:unparseableResponse', ...
            'No $$SOE/$$EOE block in the response for %s.', bodyName);
    end

    line = strtrim(split(block(1), newline));
    line = line(strlength(line) > 0);
    record = strings(numel(line), 1);
    for k = 1:numel(line)
        record(k) = "VECTOR | " + bodyName + " | " + body + " | " + line(k);
    end
end

function fixtureFile = localWriteFixture(options, header, record, failure)
%LOCALWRITEFIXTURE Provenance first, then the numbers, as UTF-8 with LF.
%   The full request URL and the ephemeris HORIZONS named are written ABOVE the
%   data, so the fixture answers "where did this come from and against what"
%   without a second file to keep in step.
    timestamp = datetime('now', 'TimeZone', 'local');
    timestamp.Format = 'yyyy-MM-dd HH:mm:ss';

    reportLine = [string(repmat('=', 1, 80)); ...
        "JPL HORIZONS state vectors — P22 reference fixture"; ...
        string(repmat('=', 1, 80)); ...
        "Retrieved   : " + string(timestamp); ...
        "Center      : " + options.Center; ...
        "Frame       : ICRF, REF_PLANE=FRAME, VEC_CORR=NONE"; ...
        "Units       : km and km/s, as returned"; ...
        "Epochs      : " + join(compose("%.1f", options.JulianDate(:)'), ", ") + ...
            " (TDB Julian date, exact half days)"; ...
        "Expected src: " + options.ExpectedSource + " (HORIZONS serves DE441; D91)"; ...
        string(repmat('-', 1, 80)); ...
        header; ...
        failure; ...
        string(repmat('-', 1, 80)); ...
        "VECTOR | body | command | JDTDB, date, X, Y, Z, VX, VY, VZ"; ...
        record; ...
        string(repmat('=', 1, 80))];

    fixtureFile = options.Output;
    if strlength(fileparts(fixtureFile)) == 0
        fixtureFile = string(fullfile(pwd, fixtureFile));
    end

    [fileId, message] = fopen(fixtureFile, 'w', 'n', 'UTF-8');
    if fileId < 0
        error('referenceSystem:fetchHorizonsVectors:cannotWriteFixture', ...
            'Cannot open %s for writing: %s', fixtureFile, message);
    end
    closeFile = onCleanup(@() fclose(fileId));
    fprintf(fileId, '%s\n', reportLine);
end
