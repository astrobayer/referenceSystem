#!/usr/bin/env python3
"""Mechanical audit of the referenceSystem package.

Mirrors, outside MATLAB, the checks the suite performs inside it: the section
C.3 help template, the D38 provenance tag, the section C.5 rule 2 qualified
sibling calls, the section C.2 error identifiers, the section B.2 layering read
from Contents.m, and the section C.1 style limits.  It cannot replace running
the suite - it is here so that the run does not have to find the mechanical
things.
"""
import os
import re
import sys


def _locateRoot():
    """Find the distribution folder whether this script sits beside it or in it.

    The script ships INSIDE referenceSystem/ but resolved ROOT as
    <own folder>/referenceSystem, so it could not run from where it ships.
    Both layouts are now accepted and a wrong one is named rather than
    reported as a missing directory three frames down.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    for candidate in (here, os.path.join(here, 'referenceSystem')):
        if os.path.isdir(os.path.join(candidate, '+referenceSystem')):
            return candidate
    sys.exit('No +referenceSystem folder beside or below %s' % here)


ROOT = _locateRoot()
PACKAGE = os.path.join(ROOT, '+referenceSystem')


def _readHelpTag():
    """Derive BOTH provenance tags from toolboxVersion.m, never from a copy.

    Decision D38 makes toolboxVersion the single authority for this string and
    the MATLAB provenance test reads it from there. This script held its own
    copy, so after a version or model bump the two instruments would have
    disagreed - the cheap audit reporting 82 failures while the expensive one
    passed, or the reverse. That is rev. 1.53's finding in a third costume, and
    the repair is the same one: delete the copy.
    """
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()
    name = re.search(r'toolboxName\s*=\s*"([^"]+)"', source)
    version = re.search(r'majorMinorVersion\s*=\s*"([^"]+)"', source)
    author = re.search(r'toolboxAuthor\s*=\s*"([^"]+)"', source)
    model = re.search(r'generatorModel\s*=\s*"([^"]+)"', source)
    if not (name and version and author and model):
        sys.exit('toolboxVersion.m does not expose the four tag literals.')
    return ('%s v%s' % (name.group(1), version.group(1)),
            'Developed by %s with the assistance of %s' % (
                author.group(1), model.group(1)))


VERSION_TAG, HELP_TAG = _readHelpTag()


def check_patch_is_handover_revision():
    """Decision D107: the patch component IS the handover revision number.

    Mirrors TestTime/toolboxVersion_contract_patchIsTheHandoverRevision, and
    DERIVES both numbers rather than holding either (obligation O20). The
    MATLAB test skips where the handover is absent, because a distribution may
    ship without it; this one runs in the development tree, where it never is,
    so between them the rule is checked exactly once wherever it can be.

    The revision log is written newest first, so the FIRST '| 1.x |' row is the
    current revision. Anchoring on it needs no sort and no maximum, and a row
    inserted in the wrong place is reported here instead of quietly becoming
    the version.
    """
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()
    patch = re.search(r'patchVersion\s*=\s*"([^"]+)"', source)
    if not patch:
        fail('version/patchLiteral', 'toolboxVersion.m exposes no patchVersion')
        return
    handover = os.path.join(ROOT, 'HANDOVER_referenceSystem.md')
    if not os.path.isfile(handover):
        fail('version/handoverMissing', handover)
        return
    text = open(handover, encoding='utf-8').read()
    revision = re.search(r'^\|\s*1\.(\d+)\s*\|', text, re.MULTILINE)
    if not revision:
        fail('version/handoverRevision',
             'no parseable "| 1.x |" row in the revision log')
        return
    if patch.group(1) != revision.group(1):
        fail('version/patchIsNotTheRevision',
             'patchVersion %s against handover revision 1.%s (D107)' % (
                 patch.group(1), revision.group(1)))

    contents = open(os.path.join(PACKAGE, 'Contents.m'), encoding='utf-8').read()
    listed = re.search(r'^%\s*Version\s+(\d+\.\d+\.\d+)', contents,
                       re.MULTILINE)
    release = re.search(r'majorMinorVersion\s*=\s*"([^"]+)"', source)
    if listed and release:
        expected = '%s.%s' % (release.group(1), patch.group(1))
        if listed.group(1) != expected:
            fail('version/contentsDisagrees',
                 'Contents.m says %s, toolboxVersion composes %s' % (
                     listed.group(1), expected))
SECTIONS = ['INPUT ARGUMENTS', 'OUTPUT ARGUMENTS', 'METHOD', 'ACCURACY',
            'ERRORS', 'REFERENCES', 'EXAMPLE', 'KEYWORDS']

failures = []
warnings = []


def fail(what, detail):
    failures.append('%-28s %s' % (what, detail))


def warn(what, detail):
    """Report without failing. O37's ceiling is a WARNING and not a gate.

    Development runs from a phone against CI for days at a time, when the
    MATLAB MCP is by definition unavailable; a check that blocked on that
    would block the normal way of working to police the exceptional one. The
    channel is kept separate from failures so the exit code still means
    exactly one thing: something is WRONG, not something is OWED.
    """
    warnings.append('%-28s %s' % (what, detail))


def code_only(text):
    """Blank out comments and string literals, as the MATLAB scan does.

    BOTH literal kinds are blanked.  Until session S5 this handled 'char'
    only, while TestDispatch.codeOnlyLine handled 'char' AND "string" - so a
    sibling name written as a double-quoted literal was invisible to MATLAB
    and a finding here.  convertCoordinates stores its edge table that way and
    produced 26 false positives on its first audit.  A cheap audit that
    disagrees with the expensive one is worse than no audit (rev. 1.53); this
    is that lesson in the opposite direction, where the cheap one cries wolf
    and so trains the reader to skip it.
    """
    out = []
    for line in text.split('\n'):
        stripped = line
        # drop a trailing comment that is not inside a literal
        result = []
        in_char = False
        in_string = False
        k = 0
        while k < len(stripped):
            ch = stripped[k]
            if ch == '"' and not in_char:
                # a double quote is never a transpose in MATLAB
                in_string = not in_string
                result.append(' ')
            elif ch == "'" and not in_string and not in_char:
                prev = stripped[k - 1] if k else ' '
                if prev.isalnum() or prev in ").}]_'":
                    result.append(ch)      # transpose
                    k += 1
                    continue
                in_char = True
                result.append(' ')
            elif ch == "'" and in_char:
                # AN ESCAPED APOSTROPHE, '', STAYS INSIDE THE LITERAL.
                # Missing this was a defect in this stripper for its whole
                # life and it went unnoticed because the checks that used it
                # were insensitive to the difference. The delimiter check
                # added at rev. 1.181 is not: sprintf('max |R''R - I|') closed
                # the literal on the first quote of the pair, reopened it on
                # the second as a transpose, and leaked the brackets of the
                # following code into the count. Four false positives out of
                # five findings on the first run.
                if k + 1 < len(stripped) and stripped[k + 1] == "'":
                    result.append('  ')
                    k += 2
                    continue
                in_char = False
                result.append(' ')
            elif ch == '%' and not in_char and not in_string:
                break
            else:
                result.append(' ' if (in_char or in_string) else ch)
            k += 1
        out.append(''.join(result))
    return '\n'.join(out)




CATEGORIES = ('contract', 'reference', 'precision', 'vectorization',
              'diagnostics')

BLOCK_OPENER = re.compile(
    r'^(function|if|for|while|switch|try|parfor|arguments|classdef|methods|'
    r'properties|events|enumeration|spmd)\b')


def check_delimiter_balance(path, text):
    """Every ( [ { opened in a file must be closed in it.

    ADDED AT REV. 1.181, AND THE DEFECT THAT PROVOKED IT IS THE ARGUMENT FOR
    IT. A nested sprintf inside a nested call lost ONE closing parenthesis at
    TestEphemeris.m:896. MATLAB refused to parse the file, matlab.unittest
    excluded the whole class, and a run of 587 tests silently became a run of
    533. check_matlab_block_structure counts function/if/for/end and was
    fault-injection tested; it says nothing about brackets.

    THE FIRST VERSION OF THIS CHECK WAS WRONG AND PRODUCED TWELVE FALSE
    POSITIVES ON ITS FIRST RUN, which is exactly the outcome obligation O29
    predicts for an instrument written beside the change it checks. It assumed
    a logical statement ends at a line without a trailing "..." - but MATLAB
    also continues across a bare newline INSIDE an open bracket, which is how
    every multi-row array literal in this package is written. Corrected to the
    only model with no false positives: one stack for the whole file, a closer
    with nothing to close is an error, a mismatched closer is an error, and
    anything still open at end of file is an error reported AT THE LINE THAT
    OPENED IT.

    That is weaker than per-statement balance - a missing closer is caught at
    the end of the file rather than at the statement - but it is exact, and an
    exact check that fires late beats an approximate one that cries wolf and
    trains the reader to skip it (rev. 1.53).
    """
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    for number, line in enumerate(code_only(text).split('\n'), start=1):
        for ch in line:
            if ch in '([{':
                stack.append((ch, number))
            elif ch in pairs:
                if not stack:
                    yield ('syntax/unbalancedDelimiter',
                           '%s line %d: %s closes nothing' % (path, number, ch))
                    return
                opener, opened = stack.pop()
                if opener != pairs[ch]:
                    yield ('syntax/unbalancedDelimiter',
                           '%s line %d: %s closes the %s opened on line %d'
                           % (path, number, ch, opener, opened))
                    return
    for opener, opened in stack:
        yield ('syntax/unbalancedDelimiter',
               '%s line %d: %s is never closed' % (path, opened, opener))


def check_matlab_block_structure(path, text):
    """Balance of block keywords, and where a function is allowed to sit.

    THE CHECK THAT SHOULD HAVE EXISTED BEFORE ANY TEST METHOD WAS INSERTED BY
    STRING SURGERY. Three insertions into TestEphemeris.m added a closing 'end'
    without the opening 'methods (Test, ...)' line to match, which left two
    test methods sitting at classdef level and cascaded into fourteen unbalanced
    ends. Every existing audit category passed the file, and it was declared
    clean five revisions running, because they all read .m files as prose.
    MATLAB refused to parse it and the whole class was silently EXCLUDED from
    the suite - which is worse than a failure, because a failure is counted.

    Two properties, both mechanical:

      1. The block keywords balance, i.e. the file ends at depth zero.
      2. In a classdef, a 'function' sits at depth two - inside a methods
         block - and never at depth one.

    This is not a MATLAB parser and will not catch an expression error. It
    catches the shape of defect that string surgery produces, which is the one
    that has actually happened here.
    """
    findings = []
    depth = 0
    is_classdef = False
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith('%'):
            continue
        if BLOCK_OPENER.match(stripped):
            if stripped.startswith('classdef'):
                is_classdef = True
            if is_classdef and stripped.startswith('function') and depth == 1:
                findings.append((
                    'structure/looseFunction',
                    '%s:%d - function at classdef level; it belongs inside a '
                    'methods block' % (path, number)))
            depth += 1
        elif stripped == 'end':
            depth -= 1
            if depth < 0:
                findings.append((
                    'structure/unbalancedEnd',
                    '%s:%d - more ends than blocks' % (path, number)))
                return findings
    if depth != 0:
        findings.append((
            'structure/unclosedBlock',
            '%s - file ends at depth %d, not 0' % (path, depth)))
    return findings


def check_test_tags(path, text):
    """Every test method's name must agree with the tag of its block.

    The convention is <function>_<tag>_<what>, and a method whose name says
    'reference' inside a contract block is filed under the wrong category in
    every report thereafter. This has now been got wrong three times by hand
    (rev. 1.102, 1.108, 1.133), each time found after a run rather than before.
    """
    findings = []
    tag = None
    for number, line in enumerate(text.splitlines(), 1):
        block = re.search(r"methods\s*\(Test,\s*TestTags\s*=\s*\{'(\w+)'\}\)",
                          line)
        if block:
            tag = block.group(1)
            continue
        method = re.match(r'\s+function\s+(\w+_(\w+)_\w+)\s*\(', line)
        if method and method.group(2) in CATEGORIES and method.group(2) != tag:
            findings.append((
                'structure/tagMismatch',
                '%s:%d - %s sits in a %s block' % (
                    path, number, method.group(1), tag)))
    return findings


def check_matlab_string_syntax(path, text):
    """Syntax hazards a text audit CAN catch without a MATLAB parser.

    Rev. 1.136 shipped a hard syntax error - `\"` inside a double-quoted
    string - and every existing check passed it, because they all read .m
    files as prose. There is no MATLAB on the machine that writes this
    toolbox, so the parser that would have caught it does not exist here;
    what does exist is the knowledge that two constructs are NEVER valid.

      1. A backslash before a double quote. MATLAB escapes a double quote
         inside a double-quoted string by DOUBLING it. `\"` always ends the
         string and leaves the rest of the line as bare syntax.
    An odd-quote-count check was written alongside it and DELETED after it
    produced eight false positives on untouched files - splitting a line on
    '%' mangles any sprintf format, and a continuation carries a quote onto
    the next line. A check that cries wolf gets switched off and takes the
    precise one with it; that is the same argument D95 used to refuse a
    heuristic accuracy warning. What survives is the rule with no exceptions.

    This is not a substitute for a parser. It would have caught the defect
    that reached a user, which is the bar that matters.
    """
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        if '\\"' in line:
            findings.append(("syntax/backslash-quote",
                             f"{path}:{number} - MATLAB escapes a quote by "
                             f'doubling it, not with a backslash'))
    return findings


def check_handover_header_is_current():
    """Every vMAJOR.MINOR.PATCH the handover HEADER quotes must be current.

    Rev. 1.183's header still said "Sources are v2.1.166" seventeen revisions
    after that stopped being true, while the row directly beneath it said
    v2.1.183 - the single point of truth disagreeing with itself in its first
    screenful, which is where a cold reader starts (finding C-1 of the
    rev. 1.184 external panel review).  The header is everything before the
    '### Revision log' heading; the log itself legitimately names old
    versions, so the check stops there.  Only the full three-component form
    is compared - prose like 'v2.0' and 'rev. 1.81' is history, not a claim
    about the shipped sources.
    """
    handover = os.path.join(ROOT, 'HANDOVER_referenceSystem.md')
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()
    patch = re.search(r'patchVersion\s*=\s*"([^"]+)"', source)
    release = re.search(r'majorMinorVersion\s*=\s*"([^"]+)"', source)
    if not (patch and release and os.path.isfile(handover)):
        return
    current = '%s.%s' % (release.group(1), patch.group(1))
    header = open(handover, encoding='utf-8').read().split('### Revision log')[0]
    for quoted in sorted(set(re.findall(r'v(\d+\.\d+\.\d+)', header))):
        if quoted != current:
            fail('version/headerIsStale',
                 'the handover header says v%s against sources v%s' % (
                     quoted, current))


def check_reference_page_indexes_contents():
    """The generated function reference must index every Contents.m entry.

    The shipped page at rev. 1.183 was missing all twenty Part-H functions
    and named a generator that no longer exists: a stale generated artefact
    is indistinguishable from a fresh one (rev. 1.174's lesson, met again in
    the doc chain).  buildDocumentation now performs the same comparison at
    build time and rebuilds on a disagreement whatever the timestamps say;
    this is the second instrument, derived from the same two authorities
    rather than holding a copy of either (O20).  Anchors follow
    buildDocumentation/localAnchor: lowercase, non-alphanumerics collapsed.
    """
    page = os.path.join(ROOT, 'doc', 'referenceSystem_functionReference.html')
    if not os.path.isfile(page):
        fail('doc/referencePageMissing', page)
        return
    html = open(page, encoding='utf-8').read()
    indexed = set(re.findall(r'<li><a href="#([a-z0-9\-]+)">', html))
    contents = open(os.path.join(PACKAGE, 'Contents.m'), encoding='utf-8').read()
    listed = set()
    for line in contents.split('\n'):
        m = re.match(r'^%\s{3}(\w+)\s+-\s', line)
        if m:
            listed.add(re.sub(r'[^A-Za-z0-9]+', '-', m.group(1)).lower())
    for name in sorted(listed - indexed):
        fail('doc/referencePageMissesFunction', name)
    for name in sorted(indexed - listed):
        fail('doc/referencePageIndexesGhost', name)


def check_generated_docs_carry_the_current_version():
    """The two GENERATED doc artefacts must stamp the current version.

    Both derive it - buildDocumentation reads toolboxVersion for the page
    footer (D38), buildReferenceManual.py parses the same file - so a stamp
    that disagrees means the artefact was not rebuilt after the sources moved,
    which is rev. 1.184 finding C-2 recurring one layer out.  Run 79 shipped
    with the page at v2.1.184 and the manual at v2.1.183 against sources at
    v2.1.185: the CONTENT gate added at rev. 1.184 compares index anchors and
    a version bump changes none of them, and a zip's timestamps cannot be
    trusted, so both gates passed a stale stamp.

    ONLY THE GENERATED PAIR IS CHECKED, AND ONLY THEIR OWN STAMP.  The
    hand-written pages mention old versions LEGITIMATELY - cApi.html says the
    six-channel interpolant format was written 'up to v2.1.178' and that zero
    still means six for code predating v2.1.179 - and those are statements of
    history, not claims to be current.  A blanket sweep of doc/ would rewrite
    them and destroy the ABI record: this is the rev. 1.121 rule that a
    substitution which must spare some occurrences names its targets rather
    than protecting its exceptions.
    """
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()
    patch = re.search(r'patchVersion\s*=\s*"([^"]+)"', source)
    release = re.search(r'majorMinorVersion\s*=\s*"([^"]+)"', source)
    if not (patch and release):
        return
    current = '%s.%s' % (release.group(1), patch.group(1))

    page = os.path.join(ROOT, 'doc', 'referenceSystem_functionReference.html')
    if os.path.isfile(page):
        stamp = re.search(r'class="foot">referenceSystem v(\d+\.\d+\.\d+)',
                          open(page, encoding='utf-8').read())
        if not stamp:
            fail('doc/pageStampMissing',
                 'the function reference carries no footer version stamp')
        elif stamp.group(1) != current:
            fail('doc/pageStampIsStale',
                 'the function reference says v%s against sources v%s; '
                 'rebuild it with buildDocumentation' % (stamp.group(1),
                                                         current))

    manual = os.path.join(ROOT, 'doc', 'referenceSystem_manual.pdf')
    if os.path.isfile(manual):
        # The PDF's text is compressed, so the stamp is read from the raw
        # bytes; reportlab writes it uncompressed in the title string.
        raw = open(manual, 'rb').read()
        found = set(m.decode() for m in re.findall(rb'2\.1\.\d+', raw))
        if found and current not in found:
            fail('doc/manualStampIsStale',
                 'the manual says v%s against sources v%s; rebuild it with '
                 'doc/buildReferenceManual.py' % (sorted(found)[0], current))


def check_closed_register_items_are_not_called_open():
    """No item the H.11 register records as CLOSED may be named in the header.

    Revs. 1.184, 1.185 and 1.186 each described B4 and B5 as the two remaining
    open items.  Both had been closed for five runs - B5 at run 73, B4 at run
    74 - and the register table said so plainly.  What those revisions read
    instead was the prose list further down, which had never been updated, and
    the claim was then copied forward from one header into the next.  THE
    DOCUMENT CONTAINED BOTH ANSWERS AND NOBODY COMPARED THEM: exactly the
    failure the header check was written for one revision earlier, one section
    lower down.

    The rule is narrow on purpose.  The header is a CURRENT-STATUS surface, so
    a closed identifier has no business appearing there at all - the same line
    the version stamps settled on at rev. 1.186, where history belongs in the
    log entry and the header carries only what is true now.  The revision log
    is exempt because it is history by definition; §H.11 itself is exempt
    because that is where the closures are recorded.
    """
    handover = os.path.join(ROOT, 'HANDOVER_referenceSystem.md')
    if not os.path.isfile(handover):
        return
    text = open(handover, encoding='utf-8').read()

    # Register rows look like: | **B4** | <item> | <disposition> |
    closed = []
    for row in re.finditer(r'^\|\s*\*\*([AB]\d+)\*\*\s*\|(.*)$', text, re.M):
        if re.search(r'\b(CLOSED|DELIVERED)\b', row.group(2)):
            closed.append(row.group(1))
    if not closed:
        return

    header = text.split('### Revision log')[0]
    for name in sorted(set(closed)):
        if re.search(r'\b%s\b' % name, header):
            fail('handover/closedItemCalledOpen',
                 '%s is CLOSED in the H.11 register but is named in the '
                 'header' % name)


def check_no_handover_date_is_in_the_future():
    """No DATED FIELD may post-date the header's own 'Last revised' date.

    Rev. 1.184 found the log dates of revs. 1.143-1.183 running to 2026-08-19
    against a wall clock of 2026-07-30 and recorded the anomaly rather than
    guessing at a repair; rev. 1.185 found the same wrong date inside
    toolboxVersion.buildDate.  Matthias adjudicated at rev. 1.188: the wall
    clock is the truth, so every impossible field was clamped to it.  A log
    entry cannot post-date the revision that contains it, and that is the
    invariant checked here - self-contained, needing no notion of 'today'.

    FIELDS ONLY, NEVER PROSE.  The document legitimately states dates beyond
    its own: the leap-second table is valid through 2028-12-31 and every
    epoch from 2029-01-01 raises the dubious-year warning, and several log
    entries QUOTE an old report header verbatim, wrong date and all.  Those
    are facts and history; rewriting them would destroy the record, which is
    the trap the doc-stamp check avoided at rev. 1.186 and the same rule
    applies here: name the fields, do not sweep the text.
    """
    handover = os.path.join(ROOT, 'HANDOVER_referenceSystem.md')
    if not os.path.isfile(handover):
        return
    text = open(handover, encoding='utf-8').read()

    revised = re.search(r'^\| Last revised \| (\d{4}-\d{2}-\d{2})', text, re.M)
    if not revised:
        fail('handover/noLastRevisedDate',
             'the header carries no parseable "Last revised" date')
        return
    latest = revised.group(1)

    for row in re.finditer(r'^\| (1\.\d+) \| (\d{4}-\d{2}-\d{2}) \|', text,
                           re.M):
        if row.group(2) > latest:
            fail('handover/futureDate',
                 'revision %s is dated %s, after the document was last '
                 'revised (%s)' % (row.group(1), row.group(2), latest))

    for row in re.finditer(r'^\| (P\d+\w*) \|(.*)$', text, re.M):
        for cell in row.group(2).split('|'):
            if re.fullmatch(r'\s*\d{4}-\d{2}-\d{2}\s*', cell) and \
                    cell.strip() > latest:
                fail('handover/futureDate',
                     'status board row %s is dated %s, after %s' % (
                         row.group(1), cell.strip(), latest))


def check_licence_is_present_and_derives_its_author():
    """LICENSE and THIRD_PARTY_NOTICES.md exist, and the holder is the author.

    A copyright line is a fourth place the author's name could drift from
    `toolboxVersion.toolboxAuthor`, after the two help-block tags and the
    generated documentation - and unlike those it is a legal statement, so it
    is the one worst suited to being retyped.  The name is DERIVED here from
    the same literal every other consumer derives it from (O20).

    The scope sentence is checked too, not only the file's presence: this
    tree ships SOFA and the transcribed IERS Conventions routines under their
    own terms, and an MIT file that did not say so would purport to relicense
    them.  That is the failure this check exists to catch, not a missing file.
    """
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()
    author = re.search(r'toolboxAuthor\s*=\s*"([^"]+)"', source)
    if not author:
        fail('licence/noAuthorAuthority',
             'toolboxVersion.m exposes no toolboxAuthor to derive from')
        return

    licence = os.path.join(ROOT, 'LICENSE')
    if not os.path.isfile(licence):
        fail('licence/missing', 'LICENSE is absent')
        return
    text = open(licence, encoding='utf-8').read()

    if not re.search(r'Copyright \(c\) \d{4} %s' % re.escape(author.group(1)),
                     text):
        fail('licence/holderIsNotTheAuthor',
             'LICENSE does not name %s as the copyright holder' %
             author.group(1))
    if 'Permission is hereby granted, free of charge' not in text:
        fail('licence/notMit', 'LICENSE does not carry the MIT grant')

    notices = os.path.join(ROOT, 'THIRD_PARTY_NOTICES.md')
    if not os.path.isfile(notices):
        fail('licence/noThirdPartyNotices', 'THIRD_PARTY_NOTICES.md is absent')
        return
    if 'THIRD_PARTY_NOTICES.md' not in text:
        fail('licence/scopeNotStated',
             'LICENSE does not point at THIRD_PARTY_NOTICES.md, so its scope '
             'is unbounded and appears to cover mex/sofa and mex/iers')
    for vendored in ('mex/sofa', 'mex/iers'):
        if os.path.isdir(os.path.join(ROOT, vendored)) and \
                vendored not in open(notices, encoding='utf-8').read():
            fail('licence/vendoredNotNoticed',
                 '%s ships but is not listed in THIRD_PARTY_NOTICES.md' %
                 vendored)


def check_build_date_agrees_with_contents():
    """toolboxVersion.buildDate and the Contents.m version line are one date.

    Rev. 1.200 moved the Contents.m line to 31-Jul-2026 and left buildDate at
    2026-07-30, and no test noticed: the version test compares the NUMBER and
    not the date.  Two copies of one fact, drifting - and this exact field had
    already drifted once before, sitting at 2026-08-19 until rev. 1.185 caught
    it in a report header.  A second occurrence in fifteen revisions is what
    makes it worth an instrument rather than a resolution.
    """
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()
    built = re.search(r'buildDate\s*=\s*"(\d{4})-(\d{2})-(\d{2})"', source)
    contents = open(os.path.join(PACKAGE, 'Contents.m'), encoding='utf-8').read()
    listed = re.search(r'^%\s*Version\s+\S+\s+(\d{2})-(\w{3})-(\d{4})',
                       contents, re.M)
    if not (built and listed):
        return
    month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    listedIso = '%s-%02d-%s' % (listed.group(3),
                                month.index(listed.group(2)) + 1,
                                listed.group(1))
    builtIso = '-'.join(built.groups())
    if listedIso != builtIso:
        fail('version/buildDateDisagrees',
             'toolboxVersion.buildDate is %s and Contents.m says %s' % (
                 builtIso, listedIso))


def check_unrun_revisions_against_the_o37_ceiling():
    """Count consecutive NOT RUN revision rows and warn past the ceiling.

    O37 lets a CI-green change merge while the MATLAB MCP is unavailable and
    turns the unrun MATLAB tier into a recorded debt rather than a blocker. A
    debt nobody rereads is the failure mode that exception creates, so the
    document counts its own.

    THE CEILING IS 15 AND IT WARNS RATHER THAN FAILS. Fifteen is not a
    tolerance for sloppiness; it is the length of an ordinary phone-and-CI
    stretch, stated by the person who works that way rather than guessed at
    here. The count runs from the top of the log and stops at the first
    revision that recorded a run, so discharging clears it in one edit.
    """
    ceiling = 15
    handover = os.path.join(ROOT, 'HANDOVER_referenceSystem.md')
    if not os.path.isfile(handover):
        return
    text = open(handover, encoding='utf-8').read()
    rows = re.findall(r'^\| (1\.\d+) \| [^|]*\| (.*)$', text, re.M)
    unrun = 0
    for _revision, body in rows:
        if re.search(r'NOT RUN|O2 is open', body, re.I):
            unrun += 1
        else:
            break
    if unrun > ceiling:
        warn('o37/unrunCeiling',
             '%d consecutive revisions carry an unrun MATLAB tier (ceiling '
             '%d). Run the suite and discharge O2 by naming the revisions it '
             'clears.' % (unrun, ceiling))


def main():
    check_patch_is_handover_revision()
    check_unrun_revisions_against_the_o37_ceiling()
    check_build_date_agrees_with_contents()
    check_handover_header_is_current()
    check_reference_page_indexes_contents()
    check_generated_docs_carry_the_current_version()
    check_closed_register_items_are_not_called_open()
    check_no_handover_date_is_in_the_future()
    check_licence_is_present_and_derives_its_author()
    files = sorted(f for f in os.listdir(PACKAGE) if f.endswith('.m'))
    names = [f[:-2] for f in files if f != 'Contents.m']
    contents = open(os.path.join(PACKAGE, 'Contents.m'), encoding='utf-8').read()

    # ---- layer map, parsed exactly as TestDispatch.layerMap does
    layer_of = {}
    current = None
    for line in contents.split('\n'):
        m = re.match(r'^%\s*L(\d+)(b?)\s', line)
        if m:
            current = float(m.group(1)) - (0.5 if m.group(2) == 'b' else 0.0)
            continue
        m = re.match(r'^%\s{3,}(\w+)\s+-\s', line)
        if m and current is not None:
            layer_of[m.group(1)] = current

    for name in names:
        if name not in layer_of:
            fail('contents/unlisted', name)

    for root, _, tree in os.walk('.'):
        if any(part in root for part in ('/.git', 'test/c', '/doc')):
            continue
        for leaf in sorted(tree):
            if not leaf.endswith('.m'):
                continue
            full = os.path.join(root, leaf)
            body = open(full, encoding='utf-8').read()
            for what, detail in check_matlab_string_syntax(full, body):
                fail(what, detail)
            for what, detail in check_matlab_block_structure(full, body):
                fail(what, detail)
            for what, detail in check_delimiter_balance(full, body):
                fail(what, detail)
            for what, detail in check_test_tags(full, body):
                fail(what, detail)

    for filename in files:
        path = os.path.join(PACKAGE, filename)
        text = open(path, encoding='utf-8').read()
        name = filename[:-2]

        if HELP_TAG not in text:
            fail('provenance/helpTag', filename)
        if VERSION_TAG not in text:
            fail('provenance/versionTag', filename)
        if filename == 'Contents.m':
            continue
        if ('%' + name.upper() + ' ') not in text:
            fail('provenance/h1', filename)
        for section in SECTIONS:
            if ('% ' + section) not in text:
                fail('provenance/section', '%s lacks %s' % (filename, section))
        if 'Ecef' in name or 'Eci' in name:
            if 'ITRS' not in text or 'GCRS' not in text:
                fail('provenance/frameNames', filename)

        for number, line in enumerate(text.split('\n'), 1):
            if len(line) > 100:
                fail('style/lineLength', '%s:%d (%d cols)' % (filename, number,
                                                             len(line)))
            if '\t' in line:
                fail('style/tab', '%s:%d' % (filename, number))

        # only RAISE sites count: warning('off', id) legitimately names another
        # function's identifier, which is how D62 suppresses an inner warning.
        raised = re.findall(r"(?:error|warning)\(\s*'(referenceSystem:[A-Za-z0-9_:]+)'",
                            text)
        documented = re.findall(r"^%\s+(referenceSystem:[A-Za-z0-9_:]+)\s*$",
                                text, re.M)
        for identifier in set(raised) | set(documented):
            if len(identifier.split(':')) != 3:
                fail('errorId/shape', '%s %s' % (filename, identifier))
        # a DOCUMENTED identifier may name a callee: an error raised on this
        # function's behalf still reaches the caller and belongs in the block.
        # a RAISED one may not - that is the binding section C.2 rule.
        for identifier in set(raised):
            owner = identifier.split(':')[1]
            if owner != name and owner != 'mex':
                fail('errorId/function', '%s raises %s' % (filename, identifier))

        body = code_only(text)
        signature = re.search(r'^\s*function\b[^\n]*?\(([^)]*)\)', body, re.M)
        takesArguments = bool(signature) and signature.group(1).strip() != ''
        if takesArguments and 'arguments' not in body:
            fail('style/argumentsBlock', filename)
        if 'inputParser' in body:
            fail('style/inputParser', filename)

        # section C.5 rule 2: sibling calls must be qualified
        for other in names:
            if other == name:
                continue
            # TestDispatch scans for the BARE identifier, not for a call
            # pattern. A local variable sharing a sibling's name is caught by
            # that scan and must be caught by this one too, or the two audits
            # disagree and the cheaper one gives false comfort (S4 run).
            for match in re.finditer(r'(?<![\w.])' + other + r'(?![\w])', body):
                start = match.start()
                if body[max(0, start - 16):start].endswith('referenceSystem.'):
                    continue
                fail('namespace/unqualified',
                     '%s calls %s at offset %d' % (filename, other, start))

        # section B.2: call downward only
        if name in layer_of:
            for other in names:
                if other == name or other not in layer_of:
                    continue
                if ('referenceSystem.' + other) in body:
                    if layer_of[other] > layer_of[name]:
                        fail('layering/upward', '%s (L%g) calls %s (L%g)' % (
                            name, layer_of[name], other, layer_of[other]))

    # A DUPLICATE METHOD NAME REMOVES A WHOLE TEST CLASS FROM THE SUITE.
    # MATLAB refuses to load the class, matlab.unittest warns to the console
    # and carries on, and every remaining test passes - so the run reports
    # green while a tenth of it never executed. That happened once, and it is
    # the only failure this project has met that LOOKS like success. Checked
    # here because it must be caught before the archive is built; the harness
    # now also refuses to end quietly when a class contributed nothing.
    import collections
    testFolder = os.path.join(ROOT, 'test')
    if os.path.isdir(testFolder):
        classFile = sorted(f for f in os.listdir(testFolder)
                           if f.startswith('Test') and f.endswith('.m'))
        for name in classFile:
            with open(os.path.join(testFolder, name), encoding='utf-8') as handle:
                text = handle.read()
            method = re.findall(r'^\s+function\s+(?:[^=\n]*=\s*)?(\w+)\s*\(',
                                text, re.M)
            for method_name, count in collections.Counter(method).items():
                if count > 1:
                    fail('test/duplicateMethod',
                         '%s defines %s %d times; MATLAB will exclude the '
                         'whole class' % (name, method_name, count))

        # A STATIC MEMBER THAT NO LONGER EXISTS IS THE MIRROR IMAGE OF A
        # DUPLICATE ONE, and until rev. 1.116 nothing looked for it. Removing a
        # duplicate method by deleting the block that held it also deleted the
        # two helpers that shared the block, and four tests that had been green
        # for a session failed with classHasNoPropertyOrMethod. The duplicate
        # scan above exists because the failure is invisible until a run; this
        # one exists for the same reason and costs the same four lines.
        defined = {}
        constant = {}
        for name in classFile:
            with open(os.path.join(testFolder, name), encoding='utf-8') as handle:
                text = handle.read()
            stem = name[:-2]
            defined[stem] = set(re.findall(
                r'^\s+function\s+(?:[^=\n]*=\s*)?(\w+)\s*\(', text, re.M))
            # A CLASS MAY CARRY SEVERAL properties BLOCKS - TestRotationAlgebra
            # carries two - so every one of them is read. Reading only the
            # first is how the first draft of this check produced six false
            # positives, which is obligation O20 in its usual costume.
            constant[stem] = set()
            for block in re.finditer(r'^\s+properties\b[^\n]*\n(.*?)^\s+end\s*$',
                                     text, re.M | re.S):
                constant[stem] |= set(re.findall(r'^\s+(\w+)\s*=',
                                                 code_only(block.group(1)), re.M))
        for name in classFile:
            with open(os.path.join(testFolder, name), encoding='utf-8') as handle:
                text = code_only(handle.read())
            for owner, member in re.findall(r'\b(Test\w+)\.(\w+)\b', text):
                if owner not in defined:
                    continue
                if member in defined[owner] or member in constant[owner]:
                    continue
                fail('test/missingStaticMember',
                     '%s references %s.%s and %s defines no such method or '
                     'constant' % (name, owner, member, owner))

    print('audited %d package files, %d listed in Contents.m, %d test classes'
          % (len(files), len(layer_of), len(classFile) if os.path.isdir(testFolder) else 0))
    if warnings:
        print()
        print('%d WARNING(S) - recorded, not blocking' % len(warnings))
        for line in warnings:
            print('  ' + line)
    if failures:
        print('\n%d FINDINGS' % len(failures))
        for line in failures:
            print('  ' + line)
        return 1
    print('clean')
    return 0


if __name__ == '__main__':
    sys.exit(main())
