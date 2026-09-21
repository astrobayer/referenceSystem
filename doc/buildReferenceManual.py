#!/usr/bin/env python3
"""Build the referenceSystem reference manual as a PDF.

The manual is GENERATED, never hand-written, for the same reason the HTML
function reference is (decision D33): a hand-written manual is not wrong when
it ships, it is wrong three revisions later and looks exactly the same. The
version, the build date and the whole API chapter are read from the package -
toolboxVersion.m for the first two, the section C.3 help blocks for the third -
so a manual that disagrees with the toolbox cannot be produced.

    python3 doc/buildReferenceManual.py

Writes doc/referenceSystem_manual.pdf.
"""
import os
import re
import sys
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Frame,
                                KeepTogether, NextPageTemplate, PageBreak,
                                PageTemplate, Paragraph, Preformatted, Spacer,
                                Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACKAGE = os.path.join(ROOT, '+referenceSystem')

INK = colors.HexColor('#1a1a1a')
RULE = colors.HexColor('#b0b6bd')
ACCENT = colors.HexColor('#1f4e79')
PANEL = colors.HexColor('#eef2f6')
WARN = colors.HexColor('#fbf3e4')


# --------------------------------------------------------------------------
# Values read from the package, never restated here
# --------------------------------------------------------------------------

def readVersionInfo():
    """Version, author, model and build date, from toolboxVersion.m.

    Obligation O20: a mirror DERIVES what the instrument derives. This script
    is a third reader of toolboxVersion.m after the MATLAB provenance test and
    auditPackage.py, and it parses the same literals rather than holding a
    copy of the composed strings.
    """
    source = open(os.path.join(PACKAGE, 'toolboxVersion.m'),
                  encoding='utf-8').read()

    def literal(name):
        found = re.search(name + r'\s*=\s*"([^"]+)"', source)
        if not found:
            sys.exit('toolboxVersion.m does not expose %s' % name)
        return found.group(1)

    release = literal('majorMinorVersion')
    patch = literal('patchVersion')
    return {
        'version': '%s.%s' % (release, patch),
        'release': release,
        'patch': patch,
        'handoverRevision': literal('handoverRevision'),
        'buildDate': literal('buildDate'),
        'author': literal('toolboxAuthor'),
        'model': literal('generatorModel'),
        'name': literal('toolboxName'),
    }


def readLayers():
    """Layer name -> [function names], parsed from Contents.m.

    Contents.m is the manifest and the single authority for the layering
    (decision D41); the MATLAB layering test and auditPackage.py read it the
    same way. A function absent from it is absent from this manual, which is
    the intended failure mode.
    """
    text = open(os.path.join(PACKAGE, 'Contents.m'), encoding='utf-8').read()
    layers = []
    current = None
    for line in text.split('\n'):
        header = re.match(r'^%\s*(L\d+b?)\s+(.*?)\s*$', line)
        if header and not re.match(r'^%\s{3,}\w+\s+-\s', line):
            current = (header.group(1), header.group(2).strip())
            layers.append((current, []))
            continue
        entry = re.match(r'^%\s{3,}(\w+)\s+-\s+(.*?)\s*$', line)
        if entry and layers:
            layers[-1][1].append((entry.group(1), entry.group(2).strip()))
    return [(name, items) for name, items in layers if items]


def readHelpBlock(functionName):
    """The H1 line and the section C.3 blocks of one package function."""
    path = os.path.join(PACKAGE, functionName + '.m')
    if not os.path.isfile(path):
        return None
    text = open(path, encoding='utf-8').read()
    comment = []
    for line in text.split('\n'):
        if line.startswith('%'):
            comment.append(line[1:].rstrip())
        elif comment:
            break
    if not comment:
        return None

    summary = comment[0]
    summary = re.sub(r'^' + functionName.upper() + r'\s*', '', summary).strip()

    sections = {}
    label = None
    for line in comment[1:]:
        header = re.match(r'^([A-Z][A-Z /]+[A-Z])\s*$', line.strip())
        if header and line.startswith(' ') is False:
            label = header.group(1).strip()
            sections[label] = []
            continue
        if label is not None:
            sections[label].append(line)
    return {'summary': summary, 'sections': sections}


# --------------------------------------------------------------------------
# Styles
# --------------------------------------------------------------------------

def buildStyles():
    base = getSampleStyleSheet()
    style = {}
    style['title'] = ParagraphStyle(
        'title', parent=base['Title'], fontName='Helvetica-Bold',
        fontSize=26, leading=30, textColor=ACCENT, spaceAfter=4)
    style['subtitle'] = ParagraphStyle(
        'subtitle', parent=base['Normal'], fontName='Helvetica',
        fontSize=13, leading=17, textColor=INK, spaceAfter=2)
    style['chapter'] = ParagraphStyle(
        'chapter', parent=base['Heading1'], fontName='Helvetica-Bold',
        fontSize=17, leading=21, textColor=ACCENT, spaceBefore=2, spaceAfter=8)
    style['section'] = ParagraphStyle(
        'section', parent=base['Heading2'], fontName='Helvetica-Bold',
        fontSize=12.5, leading=16, textColor=INK, spaceBefore=12, spaceAfter=4)
    style['sub'] = ParagraphStyle(
        'sub', parent=base['Heading3'], fontName='Helvetica-Bold',
        fontSize=10.5, leading=14, textColor=ACCENT, spaceBefore=9, spaceAfter=3)
    style['body'] = ParagraphStyle(
        'body', parent=base['Normal'], fontName='Helvetica', fontSize=9.3,
        leading=13.2, textColor=INK, alignment=TA_JUSTIFY, spaceAfter=6)
    style['bullet'] = ParagraphStyle(
        'bullet', parent=style['body'], leftIndent=11, bulletIndent=2,
        spaceAfter=3)
    style['code'] = ParagraphStyle(
        'code', parent=base['Code'], fontName='Courier', fontSize=7.6,
        leading=9.6, textColor=INK, backColor=PANEL,
        borderPadding=(5, 5, 5, 5), spaceBefore=3, spaceAfter=7)
    style['api'] = ParagraphStyle(
        'api', parent=style['code'], fontSize=6.9, leading=8.4,
        backColor=colors.white, borderPadding=(2, 2, 2, 2))
    style['fn'] = ParagraphStyle(
        'fn', parent=base['Normal'], fontName='Courier-Bold', fontSize=9.6,
        leading=12, textColor=ACCENT, spaceBefore=9, spaceAfter=1)
    style['note'] = ParagraphStyle(
        'note', parent=style['body'], backColor=WARN, borderColor=RULE,
        borderWidth=0.5, borderPadding=(6, 6, 6, 6), spaceBefore=4,
        spaceAfter=8)
    style['caption'] = ParagraphStyle(
        'caption', parent=base['Normal'], fontName='Helvetica-Oblique',
        fontSize=8, leading=10.5, textColor=colors.HexColor('#555c63'),
        spaceAfter=8)
    return style


def tableOf(rows, widths, style, header=True):
    data = [[Paragraph(str(cell), style['body']) for cell in row]
            for row in rows]
    table = Table(data, colWidths=widths, hAlign='LEFT')
    commands = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LINEBELOW', (0, 0), (-1, -2), 0.3, RULE),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        ('LEFTPADDING', (0, 0), (-1, -1), 4),
    ]
    if header:
        commands += [
            ('BACKGROUND', (0, 0), (-1, 0), PANEL),
            ('LINEBELOW', (0, 0), (-1, 0), 0.8, ACCENT),
        ]
    table.setStyle(TableStyle(commands))
    return table


# --------------------------------------------------------------------------
# Page furniture
# --------------------------------------------------------------------------

class Manual(BaseDocTemplate):
    def __init__(self, path, info, **kw):
        BaseDocTemplate.__init__(self, path, pagesize=A4,
                                 leftMargin=22 * mm, rightMargin=18 * mm,
                                 topMargin=20 * mm, bottomMargin=18 * mm, **kw)
        self.info = info
        frame = Frame(self.leftMargin, self.bottomMargin,
                      self.width, self.height, id='body')
        self.addPageTemplates([
            PageTemplate(id='cover', frames=[frame]),
            PageTemplate(id='page', frames=[frame], onPage=self.decorate),
        ])

    def decorate(self, canvas, doc):
        canvas.saveState()
        canvas.setFont('Helvetica', 7.2)
        canvas.setFillColor(colors.HexColor('#6b7178'))
        canvas.setStrokeColor(RULE)
        top = self.pagesize[1] - self.topMargin + 6
        canvas.line(self.leftMargin, top, self.leftMargin + self.width, top)
        canvas.drawString(self.leftMargin, top + 3,
                          '%s v%s \u2014 Reference Manual'
                          % (self.info['name'], self.info['version']))
        canvas.drawRightString(self.leftMargin + self.width, top + 3,
                               'built %s' % self.info['buildDate'])
        foot = self.bottomMargin - 8
        canvas.line(self.leftMargin, foot + 10, self.leftMargin + self.width,
                    foot + 10)
        canvas.drawCentredString(self.leftMargin + self.width / 2.0, foot,
                                 '%d' % doc.page)
        canvas.restoreState()


def escape(text):
    return (text.replace('&', '&amp;').replace('<', '&lt;')
                .replace('>', '&gt;'))


# --------------------------------------------------------------------------
# Content
# --------------------------------------------------------------------------

def cover(story, st, info):
    story.append(Spacer(1, 45 * mm))
    story.append(Paragraph('referenceSystem', st['title']))
    story.append(Paragraph(
        'Time systems, Earth orientation and coordinate transformations '
        'for satellite geodesy', st['subtitle']))
    story.append(Spacer(1, 8 * mm))
    story.append(tableOf([
        ['Version', 'v%s' % info['version']],
        ['Handover revision', '1.%s &mdash; provenance, and no part of '
                              'the version (D132)' % info['handoverRevision']],
        ['Build date', info['buildDate']],
        ['Author', info['author']],
        ['Developed with', info['model']],
        ['Standards', 'IERS Conventions (2010); IAU SOFA release 20231011; '
                      'IAU 2006/2000A precession-nutation'],
    ], [42 * mm, 118 * mm], st, header=False))
    story.append(Spacer(1, 12 * mm))
    story.append(Paragraph(
        'This manual is <b>generated</b> from the package itself. The version '
        'and build date are read from <font face="Courier">toolboxVersion.m'
        '</font>, the layer structure from <font face="Courier">Contents.m'
        '</font>, and every entry in the API chapter from the help block of '
        'the function it describes. A manual that disagreed with the toolbox '
        'could not be produced, which is the only kind of manual worth '
        'shipping.', st['caption']))
    story.append(NextPageTemplate('page'))
    story.append(PageBreak())


def chapterTheory(story, st):
    story.append(Paragraph('1 &nbsp; Theory', st['chapter']))
    story.append(Paragraph(
        'The toolbox realises one chain and everything else supports it: the '
        'rotation from the International Terrestrial Reference System to the '
        'Geocentric Celestial Reference System, at an arbitrary epoch, to an '
        'accuracy limited by the Earth orientation parameters rather than by '
        'the software.', st['body']))

    story.append(Paragraph('1.1 &nbsp; The rotation chain', st['section']))
    story.append(Paragraph(
        'Following IERS Conventions (2010) Chapter 5 in the CIO-based '
        'formulation, the transformation factorises into four rotations, each '
        'with a distinct physical origin and a distinct error budget:',
        st['body']))
    story.append(Preformatted(
        '  [GCRS] = Q(t) * R(t) * W(t) * [ITRS]\n\n'
        '  W(t)  polar motion       xp, yp and the TIO locator s\'\n'
        '  R(t)  Earth rotation     ERA, linear in UT1\n'
        '  Q(t)  precession-nutation  CIP X, Y and the CIO locator s\n',
        st['code']))
    story.append(Paragraph(
        'The split matters operationally as well as physically. <b>Q varies on '
        'a scale of hours, W and UT1 are tabulated daily, and only the Earth '
        'rotation angle is fast</b> &mdash; and it is linear in UT1, hence '
        'essentially free. That asymmetry is what makes the interpolated mode '
        'possible at all: everything expensive is either constant over an arc '
        'or smooth in time.', st['body']))

    story.append(Paragraph('1.2 &nbsp; Which error dominates', st['section']))
    story.append(Paragraph(
        'Sub-millimetre accuracy at the Earth&rsquo;s surface corresponds to '
        'about <b>32 microarcseconds</b> of rotation. The toolbox\'s own '
        'contribution is far inside that; the Earth orientation parameters '
        'are not:', st['body']))
    story.append(tableOf([
        ['Limit on the absolute rotation', 'Magnitude', 'At the surface'],
        ['UT1 uncertainty (~5 &micro;s)', '3.6e-10 rad', '~2 mm'],
        ['dX/dY uncertainty (~50 &micro;as)', '2.4e-10 rad', '~1.5 mm'],
        ['xp/yp uncertainty (~30 &micro;as)', '1.5e-10 rad', '~1 mm'],
        ['<b>toolbox, direct path</b>', '~1e-16 rad', '<b>~0.6 nm</b>'],
        ['<b>toolbox, interpolated path</b>', '&le; 2.4e-12 rad',
         '<b>~0.015 mm</b>'],
    ], [66 * mm, 44 * mm, 40 * mm], st))
    story.append(Paragraph(
        'Read that table before choosing a tolerance anywhere. <b>Sub-'
        'millimetre absolute accuracy is not achievable from today&rsquo;s EOP '
        'series</b>, and no amount of care in the software changes it. What '
        'the software must do is stay out of the way &mdash; and remain out of '
        'the way when the EOP improve, which is why every tolerance in the '
        'test suite asserts <i>algorithmic</i> agreement and never EOP-level '
        'agreement.', st['note']))

    story.append(Paragraph('1.3 &nbsp; Time scales', st['section']))
    story.append(Paragraph(
        'Eleven scales are supported and the conversions among them are '
        'rigorous, not nominal, wherever a rigorous definition exists. UTC is '
        'the awkward one: it is not a uniform scale, a leap second makes one '
        'day 86401 seconds long, and an epoch inside that second is '
        'representable only if the day and the second-of-day are carried '
        'separately. That is why the <font face="Courier">epoch</font> type is '
        'a two-field struct and never a serial date number.', st['body']))
    story.append(tableOf([
        ['Relation', 'Nature'],
        ['TAI &minus; UTC', 'Integer leap seconds, from a tabulated authority'],
        ['TT = TAI + 32.184 s', 'Exact by definition'],
        ['TCG, TCB', 'Exact linear rate relations (IAU 2000 B1.9, B1.5)'],
        ['TDB &minus; TT', 'Periodic series; SOFA iauDtdb, better than 1e-5 s '
                           'against the Almanac formula'],
        ['UT1 &minus; UTC', '<b>Measured</b>, from the EOP series. Not a '
                            'conversion but an observation'],
        ['GPS, GST, BDT', 'Nominal integer offsets from TAI. Documented as '
                          'nominal, <b>not realised</b>'],
    ], [50 * mm, 100 * mm], st))

    story.append(Paragraph('1.4 &nbsp; What is deliberately approximate',
                           st['section']))
    story.append(Paragraph(
        'Every approximation the toolbox makes is named and quantified in the '
        'Accuracy chapter and in the browsable <font face="Courier">ACCURACY'
        '</font> block of the function that makes it. Three are worth stating '
        'here because they shape how the toolbox is used:', st['body']))
    for text in [
        '<b>Derivatives are differenced, not differentiated.</b> Rdot and '
        'Rddot come from central differences with a measured optimum step of '
        '200 s. Analytic differentiation would mean duplicating SOFA\'s '
        'nutation tables, and every step from 1 s to 1800 s meets a 1 nm/s '
        'velocity budget, so the choice is not critical.',
        '<b>The interpolated mode fits the exact model, it does not replace '
        'it.</b> Chebyshev panels are built from the same SOFA evaluation the '
        'direct path runs; the fit error is bounded at fractions of a '
        'microarcsecond and asserted against the direct chain.',
        '<b>Sub-daily EOP corrections are on by default.</b> Ocean tide and '
        'libration reach ~0.5 mas in polar motion and ~50 &micro;s in UT1, '
        'which is ~15 mm. They are not optional for GRACE-class work.',
    ]:
        story.append(Paragraph(text, st['bullet'], bulletText='\u2022'))


def chapterPhilosophy(story, st):
    story.append(CondPageBreak(60 * mm))
    story.append(Paragraph('2 &nbsp; Implementation philosophy', st['chapter']))
    story.append(Paragraph(
        'The design rules below are not style preferences. Each was adopted '
        'after a specific defect, and the defect is recorded with it in the '
        'handover document. They are repeated here because a user who knows '
        'why the interfaces look as they do can predict what they will do.',
        st['body']))

    rules = [
        ('Correctness is checked against something outside the toolbox',
         'A self-test cannot catch a consistently wrong convention: a mistaken '
         'Euler sense still produces an orthogonal, unit-determinant matrix '
         'that round-trips through its own inverse. Conventions are therefore '
         'checked against NAIF SPICE, PROJ, JPL HORIZONS, published worked '
         'examples and real GRACE-FO flight data.'),
        ('A tolerance is a claim about which error dominates',
         'When a precision test fails, the residual is decomposed into its '
         'physical contributors before any bound is touched. Loosening a '
         'tolerance to make a test pass usually destroys exactly the '
         'discrimination the test existed for.'),
        ('Metadata travels with the data',
         'The CIP model reference, the attitude convention, the ephemeris '
         'generation and the leap-second source all travel in a meta field '
         'rather than being assumed. The worst defect inherited from v1 was '
         'pole offsets referred to an assumed precession-nutation model: 4.2 mm '
         'at 2025, and invisible in the result.'),
        ('Measured, never declared',
         'Where the toolbox can ask, it asks. Kernel pairing is read from the '
         'SPK comment area, not from the filename. The MEX build reports what '
         'the compiler actually did, not what it was asked to do.'),
        ('One authority per fact',
         'The version lives in one file, the layer manifest in one file, the '
         'leap-second table behind one function. A consumer that re-derives a '
         'fact by parsing another consumer has made itself a second '
         'authority, and the two will disagree on the day nobody is looking.'),
        ('Refuse, or report &mdash; never fall back silently',
         'A guard that cannot determine a fault proceeds. A function that '
         'cannot verify a claim says so in its returned metadata and in a '
         'warning. Nothing degrades quietly to a plausible answer.'),
        ('The artefact must survive the failure of what produces it',
         'A run that dies still writes its report, marked incomplete, with the '
         'exception that killed it. A partial download returns its manifest. '
         'Three separate defects in this project were a preserving mechanism '
         'destroying what it existed to preserve.'),
    ]
    for name, text in rules:
        story.append(Paragraph(name, st['sub']))
        story.append(Paragraph(text, st['body']))

    story.append(Paragraph('2.1 &nbsp; Layer architecture', st['section']))
    story.append(Paragraph(
        'Calls go downward only, and the layering is asserted by a test that '
        'reads the manifest in <font face="Courier">Contents.m</font>. A '
        'function that calls upward is a defect the suite reports by name.',
        st['body']))
    story.append(Preformatted(
        '  L6  dispatch, build, documentation, tests\n'
        '  L5  orbit, attitude, navigation, ephemerides, body frames\n'
        '  L4  coordinate representations and rotation algebra\n'
        '  L3  terrestrial frame realizations (ITRF, datums)\n'
        '  L2  Earth orientation transformation (ITRS <-> GCRS)\n'
        '  L1  Earth orientation parameters\n'
        '  L0  time scales and constants\n'
        '  C   MEX gateway over IAU SOFA and the IERS routines\n',
        st['code']))


def chapterInstall(story, st, info):
    story.append(CondPageBreak(60 * mm))
    story.append(Paragraph('3 &nbsp; Installation', st['chapter']))
    story.append(Paragraph(
        'One command does everything and reports what it did. It never repairs '
        'silently: anything it cannot do is named, with the reason.',
        st['body']))
    story.append(Preformatted(
        '>> cd <folder containing referenceSystem>\n'
        '>> addpath referenceSystem\n'
        '>> status = setupReferenceSystem(\'Verbose\', true)\n\n'
        '   ... path set, MEX built, documentation registered ...\n'
        '   %s %s is ready.\n'
        % (info['name'], info['version']), st['code']))
    story.append(Paragraph(
        'The setup puts the distribution folder on the path (never '
        '<font face="Courier">+referenceSystem</font>, which is a namespace '
        'folder and must not be), removes a second installation if it finds '
        'one, compiles the MEX gateway against the bundled SOFA and IERS '
        'sources, registers the documentation, and reports the leap-second '
        'horizon.', st['body']))

    story.append(Paragraph('3.1 &nbsp; External data', st['section']))
    story.append(tableOf([
        ['What', 'Needed for', 'How'],
        ['EOP series', 'Everything. There is no built-in default and no zero '
                       'fallback', 'Fetched by setup. Alone: <font '
                       'face="Courier">setupReferenceSystem(\'Fetch\', "eop")'
                       '</font>'],
        ['SPICE kernels', 'The <font face="Courier">"mice"</font> ephemeris '
                          'tier and PCK body frames',
         'Fetched by setup. To see the bill first, <font face="Courier">'
         'downloadKernels(\'Mode\', "list")</font>'],
        ['MICE toolkit', 'The same', 'Detected, never installed. It ships as '
                                     'platform-specific compiled MEX'],
        ['Geoid grid', 'Orthometric heights', 'Not bundled, for licensing and '
                                              'size reasons'],
    ], [32 * mm, 58 * mm, 60 * mm], st))
    story.append(Paragraph(
        '<b>Nothing is fetched by default</b>: setup installs the toolbox and '
        'leaves the data alone. Pass <font face="Courier">\'Fetch\', "all"'
        '</font> to install it, roughly 700 MB on a first run and nothing at '
        'all afterwards, because a file already on disk is skipped; '
        '<font face="Courier">\'KernelSet\', "minimal"</font> leaves out the '
        '650 MB small-body kernel. Where it goes is <font face="Courier">'
        'referenceSystem.dataFolder</font>, which remembers the choice. The '
        'exploratory call '
        'remains the harmless one: <font face="Courier">downloadKernels()'
        '</font> returns the plan and touches neither network nor disk.',
        st['note']))

    story.append(Paragraph('3.2 &nbsp; Checking the installation',
                           st['section']))
    story.append(Preformatted(
        '>> referenceSystem.mexInfo()          % gateway, SOFA release, OpenMP\n'
        '>> referenceSystem.toolboxVersion()   % version, author, provenance\n'
        '>> referenceSystem.runTestSuite()     % full suite + written report\n',
        st['code']))
    story.append(Paragraph(
        'The report is written to the <b>toolbox root</b>, not to the current '
        'folder, and its header states the version that produced it. Both '
        'properties exist because a report that follows the working directory '
        'leaves a stale one where people look, and a stale report is '
        'indistinguishable from a fresh one.', st['body']))


def chapterUsage(story, st):
    story.append(CondPageBreak(60 * mm))
    story.append(Paragraph('4 &nbsp; User guidelines', st['chapter']))

    story.append(Paragraph('4.1 &nbsp; The epoch type', st['section']))
    story.append(Paragraph(
        'Every function that takes a time takes an <font face="Courier">epoch'
        '</font> struct: an integer day, a second-of-day, and a scale name. '
        'Never a datenum, never a scalar of seconds. The reason is UTC: a leap '
        'second makes one day 86401 s long, and only a split representation can '
        'name an instant inside it.', st['body']))
    story.append(Preformatted(
        'utc = referenceSystem.daySecondToEpoch([57754 43200], "UTC");\n'
        'utc = referenceSystem.mjdToEpoch(57754.5, "UTC");\n'
        'utc = referenceSystem.datetimeToEpoch(datetime(2017,1,1,12,0,0), "UTC");\n'
        'tt  = referenceSystem.convertTimeScale(utc, "TT");\n', st['code']))

    story.append(Paragraph('4.2 &nbsp; Choosing a performance mode',
                           st['section']))
    story.append(tableOf([
        ['Mode', 'Use for', 'Interface'],
        ['<b>direct</b>', 'Everything except hot loops. The accuracy reference',
         '<font face="Courier">rotationItrsToGcrs(t, \'Eop\', eop)</font>'],
        ['<b>interpolated</b>', 'MATLAB-level loops and long arcs',
         '<font face="Courier">earthOrientationInterpolant(span, \'Eop\', eop)'
         '</font> then pass it as <font face="Courier">\'Interpolant\'</font>'],
        ['<b>C API</b>', 'Real orbit integration, measured at 0.564 &micro;s '
                         'per call', 'link <font face="Courier">rsApi.h</font> '
                         'from your own MEX'],
    ], [26 * mm, 62 * mm, 62 * mm], st))
    story.append(Paragraph(
        'MATLAB\'s own call and validation overhead is 5&ndash;15 &micro;s and '
        'cannot be optimised away from inside MATLAB. There is deliberately no '
        'MATLAB single-call performance target: a target below the language\'s '
        'floor is not a target. If an integrator needs better, the integrator '
        'must be in C &mdash; which is why the C API is a deliverable and not '
        'an afterthought.', st['body']))

    story.append(Paragraph('4.3 &nbsp; Things that will bite',
                           st['section']))
    for text in [
        '<b>Partials are per radian, not per arcsecond.</b> Polar motion is '
        'published in arcseconds; it reaches these functions in radians. A '
        'factor of 206265 in a Jacobian is invisible in the answer &mdash; it '
        'just makes the estimate converge to the wrong place. '
        '<font face="Courier">info.polarMotionUnits</font> says so on every '
        'call.',
        '<b>The zonal tide correction is refused without an opt-in.</b> A C04 '
        'series already contains those terms as observed values, so applying '
        'them again is invisible and costs metres.',
        '<b>The lunar body-fixed frame never defaults.</b> MOON_ME and MOON_PA '
        'differ by about 860 m at the surface. The caller names one.',
        '<b>The bundled ephemeris is kilometres, not millimetres.</b> The 1 mm '
        'BCRS transformation is millimetre-accurate <i>as a correction</i>, '
        'applied to a position whose own error is four orders larger. Do not '
        'combine them and quote the smaller number.',
        '<b>Mixed ephemeris generations warn, they do not fail.</b> SPICE '
        'resolves an overlapping body from whichever kernel was furnished '
        'last, so an unintended mixture is silent in the result. Read '
        '<font face="Courier">meta.generations</font>.',
    ]:
        story.append(Paragraph(text, st['bullet'], bulletText='\u2022'))


def chapterWalkthrough(story, st):
    story.append(CondPageBreak(60 * mm))
    story.append(Paragraph('5 &nbsp; Step-by-step guides', st['chapter']))

    story.append(Paragraph(
        '5.1 &nbsp; A GRACE-like arc: ECEF to ECI with velocities',
        st['section']))
    story.append(Preformatted(
        '% 1. Read the Earth orientation series once per session.\n'
        'eop = referenceSystem.readEop("eopc04_20.1962-now");\n\n'
        '% 2. Build the epoch column for the whole arc, in one call.\n'
        'day = repmat(57754, 5000, 1);\n'
        'sec = (0:4999).\' * 10;\n'
        'utc = referenceSystem.daySecondToEpoch([day sec], "UTC");\n\n'
        '% 3. One rotation call for the arc. Rdot comes free of a second\n'
        '%    pass: the three sample times per epoch are interpolated once.\n'
        '[R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(utc, ...\n'
        '    \'Eop\', eop);\n\n'
        '% 4. Apply it to position and velocity together.\n'
        '[rGcrs, vGcrs] = referenceSystem.applyRotation(R, Rdot, rItrs, vItrs);\n\n'
        'assert(info.path == "direct");\n', st['code']))

    story.append(Paragraph('5.2 &nbsp; The same arc, interpolated',
                           st['section']))
    story.append(Preformatted(
        '% Build the panels once for the span, then never touch the series.\n'
        'span = referenceSystem.daySecondToEpoch([57754 0; 57757 0], "UTC");\n'
        'eoi  = referenceSystem.earthOrientationInterpolant(span, \'Eop\', eop);\n\n'
        '% No \'Eop\' is passed: a seven-channel interpolant carries every\n'
        '% quantity the rotation needs, including the excess length of day.\n'
        '[R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(utc, ...\n'
        '    \'Interpolant\', eoi);\n\n'
        'assert(info.path == "interpolated");\n'
        'assert(info.sampleSource == "panels");   % nothing read the series\n',
        st['code']))

    story.append(Paragraph('5.3 &nbsp; An integrator hot loop, in C',
                           st['section']))
    story.append(Preformatted(
        '/* MATLAB writes the panels; C reads the file MATLAB wrote. */\n'
        'referenceSystem.writeInterpolant(eoi, "arc.eopi");   % in MATLAB\n\n'
        '/* Two-call protocol: header first, then sized arrays. */\n'
        'rsApiInterpolant ip;\n'
        'rsApiReadInterpolant("arc.eopi", &ip, NULL, 0, NULL, 0);\n'
        'coefficient = malloc(rsApiInterpolantSize(&ip) * sizeof(double));\n'
        'taiMinusUtc = malloc(ip.panelCount * sizeof(double));\n'
        'rsApiReadInterpolant("arc.eopi", &ip, coefficient,\n'
        '                     rsApiInterpolantSize(&ip),\n'
        '                     taiMinusUtc, ip.panelCount);\n\n'
        'double R[9];\n'
        'rsApiRotation(&ip, mjdUtc, R);      /* 0.564 us per call */\n'
        'rsApiRotationDaySecond(&ip, dayUtc, secUtc, R);   /* v2.1.236 */\n',
        st['code']))
    story.append(Paragraph(
        'If you build an <font face="Courier">rsApiInterpolant</font> by hand '
        'rather than reading a file, set <font face="Courier">quantityCount'
        '</font>. Zero means six, so code written before v2.1.179 keeps its '
        'meaning.', st['note']))
    story.append(Paragraph(
        'An MJD double resolves 0.63 &micro;s, so <font face="Courier">'
        'rsApiRotation</font> can be 2.3e-11 out, and a whole second of '
        'rotation in the last 0.3 &micro;s before a leap second. The '
        'day-and-second form has neither limit and gives MATLAB\'s matrix for '
        'the same day and second.', st['note']))

    story.append(Paragraph('5.4 &nbsp; Estimating EOP corrections',
                           st['section']))
    story.append(Preformatted(
        '[dRdXp, dRdYp, dRdDut1, info] = ...\n'
        '    referenceSystem.rotationItrsToGcrsPartials(utc, \'Eop\', eop);\n\n'
        '% Scale to the parameterisation your normal matrix uses.\n'
        'perArcsecond = referenceSystem.iersConstants().arcsecondsToRadians;\n'
        'dRdXpArcsec  = dRdXp * perArcsecond;\n', st['code']))


def chapterAccuracy(story, st):
    story.append(CondPageBreak(60 * mm))
    story.append(Paragraph('6 &nbsp; Accuracy and validation', st['chapter']))
    story.append(Paragraph(
        'Every figure below is <b>measured</b>. Where a figure was asserted '
        'and later measured, the measurement replaced it and the correction is '
        'recorded in the handover revision log.', st['body']))

    story.append(Paragraph('6.1 &nbsp; The rotation chain', st['section']))
    story.append(tableOf([
        ['Check', 'Against', 'Result'],
        ['CIP X, Y', 'SOFA cookbook', '9.0e-17, 2.9e-16'],
        ['Full ITRS&rarr;GCRS matrix', 'SOFA cookbook',
         '2.6e-15 (5e-4 &micro;as)'],
        ['ERA', 'SOFA cookbook', '5.9e-13 deg'],
        ['Equinox route vs CIO route', 'each other, swept over epochs',
         '4.4e-16 rad = 9.1e-5 &micro;as'],
        ['Orthogonality &#8214;R\'R &minus; I&#8214;', '&mdash;', '1.1e-16'],
        ['Skew invariant', '&mdash;', '4.2e-19 rad/s'],
        ['Interpolated vs direct', 'each other, across panel boundaries',
         '&lt; 5e-12 on a direction cosine'],
    ], [48 * mm, 56 * mm, 46 * mm], st))

    story.append(Paragraph('6.2 &nbsp; Against outside authorities',
                           st['section']))
    story.append(tableOf([
        ['Domain', 'Authority', 'Result'],
        ['Geodetic &harr; Cartesian, Helmert, ITRF2020 chain', 'PROJ 9.5.1',
         'bit for bit; 0.0 m; 1e-9 m'],
        ['Euler sequences and quaternion products', 'NAIF SPICE',
         '1e-14 over 9600 comparisons'],
        ['WGCCRE Table 1 pole and rate', 'orbital poles from the ephemeris; '
         'published periods', '0.011&ndash;0.034 deg; 2.5e-6&ndash;8.8e-11'],
        ['WGCCRE Table 1 transcription', 'NAIF PCK, independently encoded',
         '2e-6 in matrix elements &asymp; 0.4 arcsec'],
        ['Planetary ephemeris, "mice" tier', 'JPL HORIZONS fixture',
         '&lt; 1000 m (DE440 against DE441)'],
        ['Small-body path', 'JPL HORIZONS fixture',
         '8021.9 m for Ceres &mdash; 2e-8 of 2.77 au'],
        ['Attitude interpolation', 'held-out GRACE-FO flight data',
         '4.4e-6 rad at 2 s gaps'],
        ['Fundamental arguments', 'ported IERS FUNDARG.F',
         '9.8e-12 rad = 2.0 &micro;as'],
    ], [46 * mm, 48 * mm, 56 * mm], st))
    story.append(Paragraph(
        'The last row is the shape of an honest disagreement. The supplied '
        'Fortran truncates two constants and does not reproduce the test case '
        'in its own header; it is <b>pinned and measured rather than '
        'repaired</b>, because repairing it would break the byte-intactness '
        'under which the other five routines are validated.', st['caption']))

    story.append(Paragraph('6.3 &nbsp; Convergence and derivatives',
                           st['section']))
    story.append(Paragraph(
        'Rdot uses central differences at a measured optimum of 200 s, order '
        '2.14 confirmed from 600 to 300 s, with a roundoff plateau below about '
        '150 s. <b>Every step from 1 s to 1800 s meets a 1 nm/s velocity and '
        '1e-10 m/s&sup2; acceleration budget</b>, so the choice is not '
        'critical &mdash; the opposite of what an earlier unmeasured figure '
        'implied.', st['body']))
    story.append(Paragraph(
        'The EOP partials agree with a differenced rotation at 4.8e-9, 1.9e-9 '
        'and 1.7e-7. <b>All three are the difference\'s own roundoff floor, '
        'not the accuracy of the partials.</b> The third was swept over four '
        'decades of perturbation to establish that: it falls to 5.4e-10 at a '
        '0.1 s step, and the product of error and step has no trend, '
        'scattering about 4.3e-11 &mdash; roughly 28 ulp in the differenced '
        'rotation. A step-independent error could not have fallen by 306 '
        'times.', st['body']))

    story.append(Paragraph('6.4 &nbsp; The limit of every self-test',
                           st['section']))
    story.append(Paragraph(
        'A wrong Euler sense, quaternion order or product still yields an '
        'orthogonal, unit-determinant matrix that round-trips through its own '
        'inverse. <b>No self-test can catch a consistently wrong toolbox.</b> '
        'The conventions here are therefore checked against independent '
        'authorities, and the convention struct travels with the data so that '
        'a mismatch between two objects is detectable. That is a statement '
        'about what has been checked, not a proof of correctness.', st['note']))


def chapterApi(story, st, layers):
    story.append(PageBreak())
    story.append(Paragraph('7 &nbsp; API reference', st['chapter']))
    story.append(Paragraph(
        'Generated from the help block of each function, grouped by the layers '
        'of <font face="Courier">Contents.m</font>. Calls go downward only. '
        'For the full argument tables, the METHOD discussion and the worked '
        'examples, use <font face="Courier">help referenceSystem.&lt;name&gt;'
        '</font> or the browsable function reference &mdash; this chapter is '
        'the map, not the territory.', st['body']))

    for (code, title), entries in layers:
        story.append(CondPageBreak(40 * mm))
        story.append(Paragraph('%s &nbsp; %s' % (code, title), st['section']))
        rows = [['Function', 'Summary']]
        for name, summary in entries:
            rows.append(['<font face="Courier">%s</font>' % name,
                         escape(summary)])
        story.append(tableOf(rows, [46 * mm, 104 * mm], st))

    story.append(PageBreak())
    story.append(Paragraph('7.1 &nbsp; Accuracy statements, in full',
                           st['section']))
    story.append(Paragraph(
        'The <font face="Courier">ACCURACY</font> block is mandatory in this '
        'toolbox: every approximation is named and quantified where the '
        'function that makes it can be read. They are reproduced here so that '
        'the manual carries the same statements the code does, and cannot '
        'drift from them.', st['body']))

    for (code, title), entries in layers:
        for name, _ in entries:
            block = readHelpBlock(name)
            if block is None or 'ACCURACY' not in block['sections']:
                continue
            text = [line for line in block['sections']['ACCURACY']]
            while text and not text[0].strip():
                text.pop(0)
            while text and not text[-1].strip():
                text.pop()
            if not text:
                continue
            trimmed = text[:14]
            if len(text) > 14:
                trimmed.append('   ... see the function help for the rest.')
            story.append(KeepTogether([
                Paragraph('referenceSystem.%s' % name, st['fn']),
                Preformatted('\n'.join(line[2:] if line.startswith('  ')
                                       else line for line in trimmed),
                             st['api']),
            ]))


def chapterFurther(story, st, info):
    story.append(CondPageBreak(50 * mm))
    story.append(Paragraph('8 &nbsp; Where to look next', st['chapter']))
    story.append(tableOf([
        ['Document', 'What it holds'],
        ['<font face="Courier">HANDOVER_referenceSystem.md</font>',
         '<b>The single point of truth.</b> Design, decisions D1&ndash;D110, '
         'standing obligations O1&ndash;O31, the revision log and the open-items '
         'register'],
        ['<font face="Courier">BEST_PRACTICE.md</font>',
         'The lessons this project paid for, extracted as a template for '
         'future work'],
        ['<font face="Courier">doc/referenceSystem_functionReference.html'
         '</font>', 'Every function, every argument, generated'],
        ['<font face="Courier">doc/referenceSystem_accuracy.html</font>',
         'The full error budget'],
        ['<font face="Courier">doc/referenceSystem_ephemerides.html</font>',
         'Ephemeris tiers, BCRS, body frames, EOP partials'],
        ['<font face="Courier">doc/referenceSystem_cApi.html</font>',
         'The public C interface and the interpolant file format'],
        ['<font face="Courier">referenceSystem_testReport.txt</font>',
         'The last run: benchmarks, convergence, notes, failures'],
    ], [56 * mm, 94 * mm], st))
    story.append(Spacer(1, 6 * mm))
    story.append(Paragraph(
        'referenceSystem v%s &mdash; developed by %s with the assistance of '
        '%s. Built %s.' % (info['version'], info['author'], info['model'],
                           info['buildDate']), st['caption']))


def main():
    info = readVersionInfo()
    layers = readLayers()
    st = buildStyles()
    target = os.path.join(HERE, 'referenceSystem_manual.pdf')

    # THE SUBJECT CARRIES THE HANDOVER REVISION, AND THAT IS WHAT MAKES IT
    # CHECKABLE. The front-matter table has printed the revision since D107,
    # but it is page content: compressed into a content stream, so no reader
    # of the raw bytes can find it. The version is findable only because it
    # sits in the title, i.e. in the document metadata. Until D132 that was
    # enough - the version moved with the revision, so doc/manualStampIsStale
    # caught a stale manual every time. It no longer does, so the revision
    # goes where the version already is.
    doc = Manual(target, info,
                 title='referenceSystem v%s Reference Manual' % info['version'],
                 author=info['author'],
                 subject='handover revision 1.%s' % info['handoverRevision'])
    story = []
    cover(story, st, info)
    chapterTheory(story, st)
    chapterPhilosophy(story, st)
    chapterInstall(story, st, info)
    chapterUsage(story, st)
    chapterWalkthrough(story, st)
    chapterAccuracy(story, st)
    chapterApi(story, st, layers)
    chapterFurther(story, st, info)
    doc.build(story)

    print('wrote %s (%d layers, %d functions)' % (
        os.path.relpath(target, ROOT), len(layers),
        sum(len(entries) for _, entries in layers)))


if __name__ == '__main__':
    main()
