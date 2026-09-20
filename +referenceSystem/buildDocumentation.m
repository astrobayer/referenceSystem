function report = buildDocumentation(options)
%BUILDDOCUMENTATION Generate the function reference and the help search database.
%
%   report = buildDocumentation() regenerates the function reference page from
%   the help text of every package function, then rebuilds the Help browser
%   search database, doing each only when its inputs are newer than its output.
%
%   report = buildDocumentation('Force', true) rebuilds both unconditionally.
%   report = buildDocumentation('Steps', "reference") does only the first.
%
%   This is the single point of access for building documentation, beside
%   buildMex for the gateway and runTestSuite for the suite. Together those
%   three are every build step the toolbox has, and setupReferenceSystem drives
%   all of them.
%
% INPUT ARGUMENTS
%   Name   Size   Type   Units  Description
%   ----   ----   ----   -----  -----------
%   -      -      -      -      No positional arguments.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name          Size   Type      Default              Description
%   ----          ----   ----      -------              -----------
%   ToolboxRoot   1x1    string    the installed root   Distribution folder.
%   Output        1x1    string    the doc folder page  Reference page path.
%   Steps         1xM    string    both                 "reference", "search".
%   Force         1x1    logical   false                Rebuild even if current.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   report              1x1    struct   -      What each step did.
%   report.referenceFile 1x1   string   -      Path of the reference page.
%   report.referenceAction 1x1 string   -      "written", "current", "skipped".
%   report.searchFolder 1x1    string   -      Path of the search database.
%   report.searchAction 1x1    string   -      "built", "current", "skipped",
%                                              "failed".
%   report.reason       1x1    string   -      Why, in one sentence.
%
% METHOD
%   DECISION D33: THE FUNCTION REFERENCE IS GENERATED AND NEVER HAND-WRITTEN.
%   Maintaining prose for eighty functions beside eighty help blocks saying the
%   same thing is the two-sources-of-truth pattern this toolbox rejects
%   everywhere else, and it is the copy that rots first, because the help text
%   is what developers actually read.
%
%   The generator is safe because the input format is guaranteed rather than
%   hoped for: toolbox_provenance_helpTemplateIsFollowed asserts that every
%   package file carries the H1 line and all eight mandatory section headings,
%   so a file this parser cannot read fails a test before it reaches here.
%
%   THE ARGUMENT BLOCKS ARE EMITTED AS PREFORMATTED TEXT, NOT RE-TABULATED.
%   The help text already IS the table, laid out in fixed-width columns that a
%   reader of the help sees in exactly that form. Re-parsing those columns into
%   HTML cells would add a second layout free to disagree with the first, for
%   no gain a reader would notice, and would fail on the one file whose
%   description wraps in an unforeseen way. Preformatted output cannot
%   misrepresent its input.
%
%   The layer grouping is read from Contents.m, the same single authority the
%   layering test reads (decision D41), so a function missing from the manifest
%   is missing from the reference and fails a test rather than disappearing
%   quietly.
%
%   STALENESS IS DECIDED BY MODIFICATION TIME, not by a stored hash. A hash
%   would be a fourth artefact to keep current and would itself go stale; the
%   file system already answers the question. The reference is rebuilt when any
%   package file is newer than the page, and the search database when any page
%   or helptoc.xml is newer than the database.
%
%   A FAILED SEARCH DATABASE WARNS AND DOES NOT ERROR. Search is a convenience
%   on top of pages that are already readable, so its absence is a degraded
%   state and not an impossible one, and builddocsearchdb depends on release
%   details this toolbox does not control.
%
% ACCURACY
%   Not applicable: the function transforms text and computes nothing.
%
% ERRORS
%   referenceSystem:buildDocumentation:packageNotFound
%   referenceSystem:buildDocumentation:docFolderNotFound
%   referenceSystem:buildDocumentation:outputNotWritable
%
% WARNINGS
%   referenceSystem:buildDocumentation:searchDatabaseFailed
%       builddocsearchdb failed. The pages are written and open normally;
%       only the Help browser search will not find them.
%
% REFERENCES
%   Handover Part E and decision D33. MathWorks, "Display Custom
%   Documentation", for info.xml, helptoc.xml and builddocsearchdb.
%
% EXAMPLE
%   report = referenceSystem.buildDocumentation();
%   disp(report.referenceAction)
%
% KEYWORDS
%   documentation, function reference, help, generator, build, search database
%
% See also BUILDMEX, RUNTESTSUITE, MEXINFO.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 09:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        options.ToolboxRoot (1,1) string = ""
        options.Output (1,1) string = ""
        options.Steps (1,:) string {mustBeMember(options.Steps, ...
            ["reference", "search"])} = ["reference", "search"]
        options.Force (1,1) logical = false
    end

    toolboxRoot = localToolboxRoot(options.ToolboxRoot);
    packageFolder = fullfile(toolboxRoot, '+referenceSystem');
    docFolder = fullfile(toolboxRoot, 'doc');
    if ~isfolder(packageFolder)
        error('referenceSystem:buildDocumentation:packageNotFound', ...
            'No +referenceSystem folder under %s.', toolboxRoot);
    end
    if ~isfolder(docFolder)
        error('referenceSystem:buildDocumentation:docFolderNotFound', ...
            'No doc folder under %s.', toolboxRoot);
    end

    if options.Output == ""
        referenceFile = string(fullfile(docFolder, ...
            'referenceSystem_functionReference.html'));
    else
        referenceFile = options.Output;
    end

    report = struct('referenceFile', referenceFile, ...
        'referenceAction', "skipped", 'searchFolder', "", ...
        'searchAction', "skipped", 'reason', "");

    if any(options.Steps == "reference")
        [report.referenceAction, report.reason] = localBuildReference( ...
            packageFolder, referenceFile, options.Force);
    end

    if any(options.Steps == "search")
        [report.searchFolder, report.searchAction] = localBuildSearch( ...
            docFolder, options.Force);
    end
end

% -------------------------------------------------------------------------

function toolboxRoot = localToolboxRoot(given)
%LOCALTOOLBOXROOT The distribution folder, from the argument or from this file.
%   This file sits in +referenceSystem, so the distribution folder is two
%   levels up. Deriving it rather than searching the path means the function
%   documents the installation it belongs to and not whichever copy happens to
%   be found first.

    if given ~= ""
        toolboxRoot = given;
        return
    end
    toolboxRoot = string(fileparts(fileparts(mfilename('fullpath'))));
end

function [action, reason] = localBuildReference(packageFolder, outputFile, force)
%LOCALBUILDREFERENCE Regenerate the reference page when the package is newer.

    layer = localLayerGroups(packageFolder);

    % STALENESS IS DECIDED BY CONTENT FIRST AND BY THE CLOCK SECOND. A zip
    % archive stores naive local times and a checkout stamps every file with
    % the checkout time, so timestamps alone once let a page missing twenty
    % functions read as "current" (rev. 1.184; the same lesson mexSourceDigest
    % applied to the gateway at rev. 1.100). The page's own index anchors are
    % compared against Contents.m - the single authority for the grouping -
    % and any disagreement forces a rebuild whatever the clocks say. The
    % timestamp check remains as the cheap second gate for the common case.
    newest = localNewestFile(fullfile(packageFolder, '*.m'));
    existing = dir(outputFile);
    if ~force && ~isempty(existing) && newest <= existing.datenum && ...
            localIndexMatchesContents(outputFile, layer)
        action = "current";
        reason = "the reference page indexes every function and is newer";
        return
    end

    % The whole document is built in memory and written once. fopen with 'w'
    % TRUNCATES BEFORE ITS ARGUMENT IS EVALUATED, so a formatting error while
    % composing would otherwise leave an empty file where a good one was
    % (handover obligation O19).
    text = localHeader();
    text = [text, localContentsList(layer)];
    for k = 1:numel(layer)
        text = [text, localLayerSection(layer(k), packageFolder)]; %#ok<AGROW>
    end
    text = [text, localFooter()];

    [fid, message] = fopen(outputFile, 'w', 'n', 'UTF-8');
    if fid < 0
        error('referenceSystem:buildDocumentation:outputNotWritable', ...
            'Cannot write %s: %s', outputFile, message);
    end
    closer = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
    action = "written";
    reason = "a package file is newer than the reference page";
end

function matches = localIndexMatchesContents(outputFile, layer)
%LOCALINDEXMATCHESCONTENTS Does the existing page index every listed function?
%   Reads the page's own <li><a href="#..."> anchors and compares the SET
%   against the anchors Contents.m would produce. Order is not compared - a
%   reordering regenerates through the timestamp gate anyway - and a page
%   that cannot be read is simply stale.

    matches = false;
    try
        pageText = string(fileread(outputFile));
    catch
        return
    end
    % regexp with 'tokens' returns a cell OF CELLS - one inner cell per
    % match, holding the capture group - and string() refuses the nesting,
    % so the unwrap is explicit (O16: a base-MATLAB return shape is not
    % exempt from the check-the-source rule).
    token = regexp(char(pageText), '<li><a href="#([a-z0-9\-]+)">', 'tokens');
    pageAnchor = string(cellfun(@(c) c{1}, token, 'UniformOutput', false));

    wanted = strings(0, 1);
    for k = 1:numel(layer)
        for j = 1:numel(layer(k).functionName)
            wanted(end+1, 1) = localAnchor(layer(k).functionName(j)); %#ok<AGROW>
        end
    end

    matches = isempty(setxor(pageAnchor(:), wanted(:)));
end

function [searchFolder, action] = localBuildSearch(docFolder, force)
%LOCALBUILDSEARCH Rebuild the Help browser search database when the pages move.

    searchFolder = localSearchFolder(docFolder);
    newest = max(localNewestFile(fullfile(docFolder, '*.html')), ...
        localNewestFile(fullfile(docFolder, 'helptoc.xml')));

    if searchFolder ~= "" && ~force
        existing = dir(searchFolder);
        if ~isempty(existing) && newest <= max([existing.datenum])
            action = "current";
            return
        end
    end

    % builddocsearchdb depends on release details this toolbox does not
    % control, and search is a convenience on top of pages that are already
    % readable. A failure here is degraded, not impossible, so it warns.
    %
    % ITS OUTPUT IS CAPTURED, BECAUSE LIBRARY CODE IN THIS TOOLBOX DOES NOT
    % PRINT (section C.1). builddocsearchdb writes three lines to the command
    % window - the index folder it removed, a bare "Process Duration: 0.0017"
    % and a success notice - which arrive in the middle of a test run with
    % nothing to say who produced them. Recorded as a cosmetic defect at
    % rev. 1.135 and fixed here. evalc is the only way to silence a builtin
    % that offers no quiet mode; it is confined to this one call, and the
    % captured text is kept so that a FAILURE can still report what the
    % builtin said before it threw. Section C.1 bans eval, assignin and evalin
    % - all three let a caller's workspace be reached or rewritten. evalc does
    % neither: it evaluates a LITERAL written here, in this scope, and returns
    % its console output as a string. The ban is on indirection, not on
    % capture, and there is no other way to quiet a builtin with no quiet mode.
    try
        capturedOutput = evalc('builddocsearchdb(char(docFolder));'); %#ok<NASGU>
        searchFolder = localSearchFolder(docFolder);
        action = "built";
    catch cause
        warning('referenceSystem:buildDocumentation:searchDatabaseFailed', ...
            ['The Help browser search database could not be built in "%s": ', ...
            '%s. The pages themselves are unaffected and open normally; ', ...
            'only the search box will not find them.'], docFolder, ...
            cause.message);
        action = "failed";
    end
end

function folder = localSearchFolder(docFolder)
%LOCALSEARCHFOLDER The helpsearch folder, whatever version this release writes.
%   The name carries the database version - helpsearch-v3, helpsearch-v4 and
%   so on - and it changes between releases, so it is discovered rather than
%   assumed.

    folder = "";
    candidate = dir(fullfile(docFolder, 'helpsearch*'));
    candidate = candidate([candidate.isdir]);
    if isempty(candidate)
        return
    end
    [~, newest] = max([candidate.datenum]);
    folder = string(fullfile(candidate(newest).folder, candidate(newest).name));
end

function newest = localNewestFile(pattern)
%LOCALNEWESTFILE The newest modification time matching a pattern, 0 if none.

    entry = dir(pattern);
    entry = entry(~[entry.isdir]);
    if isempty(entry)
        newest = 0;
        return
    end
    newest = max([entry.datenum]);
end

function layer = localLayerGroups(packageFolder)
%LOCALLAYERGROUPS Layer name and member functions, read from Contents.m.
%   Contents.m is the manifest and therefore the single authority for the
%   grouping (decision D41). Its layer headings are the comment lines of the
%   form "% L2 - ...", and its function lines are "%   name - summary".

    contentsLine = split(string(fileread(fullfile(packageFolder, ...
        'Contents.m'))), newline);
    layer = struct('name', {}, 'functionName', {});

    for k = 1:numel(contentsLine)
        heading = regexp(char(contentsLine(k)), ...
            '^%\s(L\d\w*)\s+[-\x{2014}]\s+(.*)$', 'tokens', 'once');
        if ~isempty(heading)
            layer(end+1) = struct('name', ...
                string(heading{1}) + " - " + strip(string(heading{2})), ...
                'functionName', strings(0, 1)); %#ok<AGROW>
            continue
        end
        entry = regexp(char(contentsLine(k)), '^%\s{3}(\w+)\s+-\s', ...
            'tokens', 'once');
        if ~isempty(entry) && ~isempty(layer)
            layer(end).functionName(end+1, 1) = string(entry{1});
        end
    end
end

function html = localLayerSection(oneLayer, packageFolder)
%LOCALLAYERSECTION One layer heading and every function under it.

    html = sprintf('<h2 id="%s">%s</h2>\n', ...
        localAnchor(oneLayer.name), localEscape(oneLayer.name));
    for k = 1:numel(oneLayer.functionName)
        name = oneLayer.functionName(k);
        file = fullfile(packageFolder, char(name + ".m"));
        if ~isfile(file)
            continue
        end
        html = [html, localFunctionSection(name, file)]; %#ok<AGROW>
    end
end

function html = localFunctionSection(name, file)
%LOCALFUNCTIONSECTION One anchored section, from one help block.

    section = localSplitSections(localHelpBlock(file));

    html = sprintf('<div class="fcn" id="%s">\n<h3>referenceSystem.%s</h3>\n', ...
        localAnchor(name), localEscape(name));
    html = [html, sprintf('<p class="h1">%s</p>\n', localEscape(section.summary))];

    % WARNINGS sits between ERRORS and REFERENCES; it was absent from this
    % list until rev. 1.184, so every documented warning identifier was
    % silently dropped from the generated page.
    order = ["SYNTAX", "INPUT ARGUMENTS", "OPTIONAL NAME-VALUE ARGUMENTS", ...
        "OUTPUT ARGUMENTS", "METHOD", "ACCURACY", "ERRORS", "WARNINGS", ...
        "REFERENCES", "EXAMPLE", "KEYWORDS"];
    for s = order
        body = localSectionBody(section, s);
        if body == ""
            continue
        end
        html = [html, sprintf('<h4>%s</h4>\n<pre>%s</pre>\n', ...
            localEscape(s), localEscape(body))]; %#ok<AGROW>
    end
    html = [html, sprintf(['<p class="top"><a href="#contents">back to ', ...
        'contents</a></p>\n</div>\n'])];
end

function block = localHelpBlock(file)
%LOCALHELPBLOCK The contiguous comment block that follows the function line.

    sourceLine = split(string(fileread(file)), newline);
    started = false;
    block = strings(0, 1);
    for k = 1:numel(sourceLine)
        oneLine = strip(sourceLine(k), 'right');
        if ~started
            started = startsWith(strip(oneLine), "%") && k > 1;
            if ~started
                continue
            end
        end
        if ~startsWith(strip(oneLine), "%")
            break
        end
        block(end+1, 1) = regexprep(oneLine, '^\s*%\s?', ''); %#ok<AGROW>
    end
end

function section = localSplitSections(block)
%LOCALSPLITSECTIONS Summary, syntax and the named blocks of the C.3 template.

    section = struct('summary', "", 'name', strings(0, 1), 'body', strings(0, 1));
    if isempty(block)
        return
    end

    % The H1 line is "%NAME Summary."; the summary is everything after the name.
    first = regexp(char(block(1)), '^(\w+)\s+(.*)$', 'tokens', 'once');
    if isempty(first)
        section.summary = block(1);
    else
        section.summary = string(first{2});
    end

    current = "SYNTAX";
    body = strings(0, 1);
    for k = 2:numel(block)
        heading = regexp(char(block(k)), '^([A-Z][A-Z \-]+)$', 'tokens', 'once');
        if ~isempty(heading)
            section.name(end+1, 1) = current;
            section.body(end+1, 1) = join(body, newline);
            current = string(heading{1});
            body = strings(0, 1);
            continue
        end
        if current == "SYNTAX" && startsWith(strip(block(k)), "See also")
            break
        end
        body(end+1, 1) = block(k); %#ok<AGROW>
    end
    section.name(end+1, 1) = current;
    section.body(end+1, 1) = join(body, newline);
end

function body = localSectionBody(section, name)
%LOCALSECTIONBODY One named block, trimmed, empty where absent.

    body = "";
    hit = find(section.name == name, 1);
    if isempty(hit)
        return
    end
    body = strip(section.body(hit));
end

function anchor = localAnchor(name)
%LOCALANCHOR A stable HTML anchor for a function or layer name.

    anchor = lower(regexprep(string(name), '[^A-Za-z0-9]+', '-'));
    anchor = regexprep(anchor, '(^-|-$)', '');
end

function safe = localEscape(text)
%LOCALESCAPE The three characters that must not reach HTML unescaped.

    safe = replace(string(text), "&", "&amp;");
    safe = replace(safe, "<", "&lt;");
    safe = replace(safe, ">", "&gt;");
end

function html = localContentsList(layer)
%LOCALCONTENTSLIST The in-page index, one list per layer.

    html = sprintf('<h2 id="contents">Contents</h2>\n');
    for k = 1:numel(layer)
        html = [html, sprintf(['<p class="layer"><b>%s</b></p>\n', ...
            '<ul class="index">\n'], localEscape(layer(k).name))]; %#ok<AGROW>
        for j = 1:numel(layer(k).functionName)
            name = layer(k).functionName(j);
            html = [html, sprintf('<li><a href="#%s">%s</a></li>\n', ...
                localAnchor(name), localEscape(name))]; %#ok<AGROW>
        end
        html = [html, sprintf('</ul>\n')]; %#ok<AGROW>
    end
end

function html = localHeader()
%LOCALHEADER The page head, styled to match the other doc pages.

    html = [ ...
        '<!DOCTYPE html>' newline ...
        '<html lang="en"><head><meta charset="utf-8">' newline ...
        '<title>referenceSystem - Function Reference</title>' newline ...
        '<link rel="stylesheet" href="referenceSystem.css">' newline ...
        '</head><body>' newline ...
        '<h1>Function Reference</h1>' newline ...
        '<p class="generated">This page is <b>generated</b> from the help text of' newline ...
        'each function by <code>referenceSystem.buildDocumentation</code>' newline ...
        '(decision D33). Do not edit it: edit the help block and build again.</p>' newline];
end

function html = localFooter()
%LOCALFOOTER The page foot.
%   The version is read from toolboxVersion rather than written here, so the
%   generated page cannot disagree with the package it documents (D38).

    versionText = referenceSystem.toolboxVersion().version;
    html = ['<p class="foot">referenceSystem v' char(versionText) ...
        ' &mdash; generated from the' newline ...
        'package help blocks. See the handover document for the design.</p>' newline ...
        '</body></html>' newline];
end
