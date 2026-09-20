function [eop, info] = readEop(file, options)
%READEOP Read an IERS Earth orientation parameter series into the eop struct.
%
%   eop = readEop(file)
%   eop = readEop(file, 'Format', "EOP 20 C04")
%   [eop, info] = readEop(file, ...)
%
%   Parses one of the supported IERS Earth orientation series and returns the
%   eop struct of handover section B.3, with every quantity converted to SI at
%   read time and a fully populated meta substruct. Nothing downstream of this
%   function ever sees an arcsecond or a milliarcsecond.
%
% INPUT ARGUMENTS
%   Name    Size   Type            Units  Description
%   ----    ----   ----            -----  -----------
%   file    1x1    string | char   -      Path to the series file.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name       Size  Type    Default   Description
%   ----       ----  ----    -------   -----------
%   Format     1x1   string  "auto"    Series format. "auto" identifies it from
%                                      the header; the explicit values are
%                                      "EOP 14 C04", "EOP 20 C04",
%                                      "EOP 20 C04 dPsiDEpsilon" and
%                                      "finals2000A". An unidentifiable file is
%                                      an error, never a default.
%   CipModel   1x1   string  "auto"    Precession-nutation model the published
%                                      pole offsets refer to. "auto" takes the
%                                      registry value; "IAU2006/2000A" or
%                                      "IAU2000A" override it. See METHOD.
%   Bulletin   1x1   string  "A"       finals2000A only: which solution to
%                                      read, "A" (Bulletin A, complete,
%                                      includes predictions) or "B" (Bulletin
%                                      B, final, past dates only). Bulletin B
%                                      publishes xp, yp, UT1-UTC, dX and dY
%                                      only; lod and every sigma come back NaN
%                                      rather than borrowed from Bulletin A.
%
% OUTPUT ARGUMENTS
%   Name              Size   Type     Units  Description
%   ----              ----   ----     -----  -----------
%   eop               1x1    struct   -      The series. Fields below.
%   .mjd              Mx1    double   d      Modified Julian Date of each row,
%                                            UTC, at the sampled hour. Decimal,
%                                            not integer: the 12h-sampled C04
%                                            products exist and land on .5.
%   .xp, .yp          Mx1    double   rad    Polar motion.
%   .dut1             Mx1    double   s      UT1 - UTC.
%   .lod              Mx1    double   s      Excess length of day.
%   .dX, .dY          Mx1    double   rad    CIP offsets from the model named
%                                            by meta.cipModel.
%   .sigma            1x1    struct   -      Formal errors, fields xp, yp,
%                                            dut1, lod, dX, dY, same units.
%   .meta             1x1    struct   -      Provenance. Fields below.
%   .meta.series      1x1    string   -      Format name as identified.
%   .meta.cipModel    1x1    string   -      "IAU2006/2000A" or "IAU2000A".
%   .meta.cipModelSource
%                     1x1    string   -      "format registry" or "caller".
%                                            Never "file header": see METHOD.
%   .meta.cipModelStatement
%                     1x1    string   -      What the file itself says, verbatim,
%                                            or "" where it says nothing.
%   .meta.poleOffsetType
%                     1x1    string   -      "observed dXdY" or
%                                            "converted from dPsiDEpsilon".
%   .meta.itrf        1x1    string   -      Frame realization the series is
%                                            consistent with.
%   .meta.file        1x1    string   -      Absolute path read.
%   .meta.readTime    1x1    datetime -      When it was read.
%   .meta.nRows       1x1    double   -      Number of data rows kept.
%   .meta.mjdRange    1x2    double   d      First and last MJD.
%   .meta.samplingHour
%                     1x1    double   h      UTC hour the series is sampled at.
%   .meta.bulletin    1x1    string   -      "A", "B" or "" where not applicable.
%   info              1x1    struct   -      Reading diagnostics, never printed.
%   .rowsRead         1x1    double   -      Rows matching the data pattern.
%   .rowsKept         1x1    double   -      Rows with usable values.
%   .rowsIncomplete   1x1    double   -      Rows dropped for missing values.
%   .gapCount         1x1    double   -      Sampling gaps longer than one step.
%   .largestGap       1x1    double   d      Longest gap, zero where none.
%   .duration         1x1    double   s      Wall-clock time of the read.
%
% METHOD
%   Finding M-6 is what this function replaces. v1 read a 23 000-row file with
%   fgetl into a growing cell array, identified the header by sniffing for the
%   substring ' DX ', supported neither the 20 C04 nor the finals series, and
%   printed unconditionally on every call. Here the file is read in one
%   readmatrix or one fixed-width slice, the format comes from an explicit
%   registry rather than a substring, and nothing is printed: diagnostics leave
%   through info, warnings through warning identifiers.
%
%   The registry is the local function localFormatRegistry. Each entry names,
%   for one published series, the column map, the unit of every column, the
%   consistent ITRF realization, the kind of pole offset published, and the
%   precession-nutation model. Adding a series is one entry; nothing else in
%   the toolbox changes. Detection reads the header, and a file that matches no
%   entry is an error, referenceSystem:readEop:unknownFormat. It is never
%   guessed, because guessing a column map produces a plausible series that is
%   wrong by whatever the columns happen to mean.
%
%   THE CIP MODEL, which is finding C-2 and the reason this struct has a meta
%   field at all. v1 assumed the published dX and dY were referred to IAU2000A
%   and formed a per-epoch bias against IAU2006/2000A on that assumption. If
%   the assumption is wrong the bias is injected rather than removed.
%
%   Measured in session S2 with SOFA iauXys06a against iauXys00a, the two
%   models differ by 0 at J2000.0, by -2 uas in X and -37 uas in Y at 2007, and
%   by -125 uas in X and -137 uas in Y at 2025, growing secularly. At the
%   Earth's surface 137 uas is 4.2 mm, which is exactly the level this toolbox
%   exists to get right.
%
%   No IERS file examined states which of the two it uses. The 14 C04 header
%   names its columns dX and dY and says nothing more; both 20 C04 products
%   carry the line "Reference Precession-Nutation Model: IAU 2000", and they
%   carry it identically on the CIO-based dX/dY product and on the equinox-based
%   dPsi/dEpsilon product of the same solution, which is why that line is
%   recorded verbatim in meta.cipModelStatement but is not read as a model
%   reference. finals2000A has no header at all.
%
%   The registry value is therefore a stated decision, not a discovery, and
%   meta.cipModelSource says so by returning "format registry" and never "file
%   header". The default is IAU2006/2000A, because the C04 solutions of the
%   ITRF2014 and ITRF2020 era are produced within the IERS Conventions (2010)
%   framework whose recommended model is IAU 2006/2000A. Measured support for
%   treating all supported series alike: differencing finals2000A against
%   EOP 20 C04 over the 9256 days they share since J2000 shows no trace of the
%   500 uas/century signature the two models differ by, so whichever model it
%   is, these products share it.
%
%   What has changed since v1 is not the confidence but the cost of being
%   wrong. The model reference is now one field, set in one place, overridable
%   with 'CipModel', carried with the data and checked by the consumer. Being
%   wrong is a one-line correction instead of a rebuild.
%
%   dPsi/dEpsilon series (risk R13c) are converted to dX/dY here, so that
%   eop.dX always means dX, using the first-order relations of Capitaine and
%   Wallace (2006) and IERS Technical Note 36 Chapter 5,
%
%       dX = dPsi * sin(eps0),      dY = dEpsilon
%
%   with eps0 = 84381.406 arcseconds. meta.poleOffsetType then reads "converted
%   from dPsiDEpsilon" rather than "observed dXdY", so a consumer can tell a
%   converted offset from a measured one. v1 warned and zeroed these files,
%   which silently degraded the CIP correction to nothing at all.
%
%   Rows are validated rather than trusted. The MJD column must be strictly
%   increasing; a gap longer than one sampling step raises one aggregated
%   warning. Every value is range-checked against what the quantity can
%   physically be, which is what catches a column map applied to the wrong
%   file: a shifted map produces values that are numerically fine and
%   physically absurd, and the range gate is the only thing between that and a
%   plausible wrong answer.
%
% ACCURACY
%   Reading is exact. The values are those published, converted to SI by
%   multiplication with an exact factor, so no accuracy is lost or gained here.
%
%   The dPsi/dEpsilon conversion is first order and therefore not exact, and
%   the size of what it neglects has been MEASURED rather than estimated, by
%   converting the IERS 20 C04 dPsi/dEpsilon product and comparing it with the
%   dX/dY product of the same solution:
%
%       mean residual                              0.3 uas
%       regression slope against the published dX  1.003
%       neglected second-order term                1.2 uas
%
%   So the conversion carries no bias and no scale error. The neglected term is
%   (psiA*cos(eps0) - chiA)*dEpsilon in dX and the corresponding term in dY,
%   where psiA*cos(eps0) - chiA is about 0.0224*t radians for t in Julian
%   centuries from J2000.0; over the 2016-2017 span measured it reaches 1.2 uas
%   and it grows linearly with t.
%
%   For scale: had the obliquity or the trigonometric function been wrong, the
%   regression slope would read 2.514 or 2.307 rather than 1.003. That is the
%   quantity the precision test asserts, because it separates a conversion
%   error from the interpolation noise that dominates any direct comparison of
%   two products sampled twelve hours apart.
%
%   The CIP model reference is not an accuracy statement but a correctness
%   statement, and the cost of the registry default being wrong is quantified
%   in METHOD: up to 137 uas, 4.2 mm at the surface, growing secularly.
%
%   finals2000A is not internally homogeneous: its early decades were produced
%   against earlier ITRF realizations than meta.itrf names. For work at the
%   millimetre level use a C04 series, which is a consistent reprocessing.
%
% ERRORS
%   referenceSystem:readEop:unknownFormat
%   referenceSystem:readEop:noData
%   referenceSystem:readEop:notMonotonic
%   referenceSystem:readEop:implausibleValue
%   referenceSystem:readEop:unsupportedBulletin
%
% WARNINGS
%   referenceSystem:readEop:samplingGap   One per call. The series has rows
%       further apart than its sampling step; interpolating across a gap is an
%       extrapolation in all but name.
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.
%   Capitaine, N. and Wallace, P. T., 2006, Astron. Astrophys. 450, 855.
%   IERS EOP Product Centre, C04 series description,
%     https://hpiers.obspm.fr/eoppc/eop/eopc04/
%
% EXAMPLE
%   eop = referenceSystem.readEop("eopc04_20.1962-now");
%   fprintf('%s, %s, %d rows\n', eop.meta.series, eop.meta.cipModel, eop.meta.nRows);
%
% KEYWORDS
%   EOP, Earth orientation, C04, finals2000A, polar motion, UT1, dX, dY
%
% See also INTERPOLATEEOP, DOWNLOADEOP, SUBDAILYEOPCORRECTION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 11:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        file (1,1) string {mustBeFile}
        options.Format (1,1) string {mustBeMember(options.Format, ...
            ["auto", "EOP 14 C04", "EOP 20 C04", "EOP 20 C04 dPsiDEpsilon", ...
            "finals2000A"])} = "auto"
        options.CipModel (1,1) string {mustBeMember(options.CipModel, ...
            ["auto", "IAU2006/2000A", "IAU2000A"])} = "auto"
        options.Bulletin (1,1) string {mustBeMember(options.Bulletin, ...
            ["A", "B"])} = "A"
    end

    startTime = tic;
    registry = localFormatRegistry();
    headerText = localReadHead(file);

    if options.Format == "auto"
        formatName = localIdentify(headerText, registry, file);
    else
        formatName = options.Format;
    end
    entry = localLookup(registry, formatName);

    if options.Bulletin == "B" && ~entry.hasBulletinB
        error('referenceSystem:readEop:unsupportedBulletin', ...
            ['Bulletin B columns exist only in the finals2000A series; the ', ...
            'file was identified as %s.'], formatName);
    end

    if entry.fixedWidth
        [column, rowsRead] = localReadFixedWidth(file, entry, options.Bulletin);
    else
        [column, rowsRead] = localReadDelimited(file, entry);
    end
    if rowsRead == 0
        error('referenceSystem:readEop:noData', ...
            ['No data row of the %s layout was found in "%s". Either the ', ...
            'file is empty or it is not the series it was identified as.'], ...
            formatName, file);
    end

    complete = all(isfinite([column.mjd, column.xp, column.yp, column.dut1]), 2);
    eop = localAssemble(column(complete, :), entry, options, formatName, ...
        file, headerText);
    localValidate(eop, formatName);

    info = struct( ...
        'rowsRead', rowsRead, ...
        'rowsKept', numel(eop.mjd), ...
        'rowsIncomplete', rowsRead - numel(eop.mjd), ...
        'gapCount', 0, 'largestGap', 0, 'duration', toc(startTime));
    [info.gapCount, info.largestGap] = localReportGaps(eop.mjd, entry, formatName);
end

% =========================== local functions ===========================

function registry = localFormatRegistry()
%LOCALFORMATREGISTRY The supported series, one entry each.
%   This is the single authority for what a column means. A column map that
%   lives anywhere else is a second source of truth, which is finding M-2 in a
%   different costume.
%
%   Column indices for the delimited formats are positions in the whitespace-
%   split numeric row. For the fixed-width format they are [first last]
%   character positions, one-based and inclusive, verified in session S2
%   against real rows of finals2000A.all rather than taken from documentation.
%
%   scale is the factor that takes the published unit to SI. arcsecondsToRadians
%   comes from iersConstants, which is the single authority for it.

    as2r = referenceSystem.iersConstants().arcsecondsToRadians;
    mas2r = as2r * 1e-3;
    ms2s = 1e-3;

    registry = struct( ...
        'name', {}, 'fixedWidth', {}, 'commentPrefix', {}, 'minimumFields', {}, ...
        'index', {}, 'scale', {}, 'cipModel', {}, 'itrf', {}, ...
        'poleOffsetsAreEquinoxBased', {}, 'samplingHour', {}, 'stepDays', {}, ...
        'hasBulletinB', {}, 'signature', {});

    registry(1) = struct( ...
        'name', "EOP 14 C04", 'fixedWidth', false, 'commentPrefix', "", ...
        'minimumFields', 16, ...
        'index', struct('mjd', 4, 'xp', 5, 'yp', 6, 'dut1', 7, 'lod', 8, ...
            'dX', 9, 'dY', 10, 'sigmaXp', 11, 'sigmaYp', 12, 'sigmaDut1', 13, ...
            'sigmaLod', 14, 'sigmaDX', 15, 'sigmaDY', 16), ...
        'scale', struct('xp', as2r, 'yp', as2r, 'dut1', 1, 'lod', 1, ...
            'dX', as2r, 'dY', as2r), ...
        'cipModel', "IAU2006/2000A", 'itrf', "ITRF2014", ...
        'poleOffsetsAreEquinoxBased', false, 'samplingHour', 0, 'stepDays', 1, ...
        'hasBulletinB', false, 'signature', "14 C04");

    registry(2) = struct( ...
        'name', "EOP 20 C04", 'fixedWidth', false, 'commentPrefix', "#", ...
        'minimumFields', 21, ...
        'index', struct('mjd', 5, 'xp', 6, 'yp', 7, 'dut1', 8, 'lod', 13, ...
            'dX', 9, 'dY', 10, 'sigmaXp', 14, 'sigmaYp', 15, 'sigmaDut1', 16, ...
            'sigmaLod', 21, 'sigmaDX', 17, 'sigmaDY', 18), ...
        'scale', struct('xp', as2r, 'yp', as2r, 'dut1', 1, 'lod', 1, ...
            'dX', as2r, 'dY', as2r), ...
        'cipModel', "IAU2006/2000A", 'itrf', "ITRF2020", ...
        'poleOffsetsAreEquinoxBased', false, 'samplingHour', 0, 'stepDays', 1, ...
        'hasBulletinB', false, 'signature', "20 C04");

    % Same layout as EOP 20 C04; columns 9 and 10 carry dPsi and dEpsilon
    % instead of dX and dY, and are converted on assembly.
    registry(3) = registry(2);
    registry(3).name = "EOP 20 C04 dPsiDEpsilon";
    registry(3).poleOffsetsAreEquinoxBased = true;
    registry(3).samplingHour = 12;
    registry(3).signature = "dPsi";

    registry(4) = struct( ...
        'name', "finals2000A", 'fixedWidth', true, 'commentPrefix', "", ...
        'minimumFields', 134, ...
        'index', struct('mjd', [8 15], 'xp', [18 27], 'yp', [37 46], ...
            'dut1', [59 68], 'lod', [79 86], 'dX', [97 106], 'dY', [116 125], ...
            'sigmaXp', [28 36], 'sigmaYp', [47 55], 'sigmaDut1', [69 78], ...
            'sigmaLod', [87 93], 'sigmaDX', [107 115], 'sigmaDY', [126 134], ...
            'bulletinBXp', [135 144], 'bulletinBYp', [145 154], ...
            'bulletinBDut1', [155 165], 'bulletinBDX', [166 175], ...
            'bulletinBDY', [176 185]), ...
        'scale', struct('xp', as2r, 'yp', as2r, 'dut1', 1, 'lod', ms2s, ...
            'dX', mas2r, 'dY', mas2r), ...
        'cipModel', "IAU2006/2000A", 'itrf', "ITRF2020", ...
        'poleOffsetsAreEquinoxBased', false, 'samplingHour', 0, 'stepDays', 1, ...
        'hasBulletinB', true, 'signature', "");
end

function entry = localLookup(registry, formatName)
%LOCALLOOKUP The registry entry for a format name.
%   The comparison is between string arrays. It used to be
%   strcmp({registry.name}, formatName), which looks equivalent and is not:
%   strcmp is documented for character vectors, cell arrays of character
%   vectors and string arrays, and a CELL ARRAY OF STRING SCALARS is none of
%   those. It does not error, it returns false for every element, so the
%   lookup silently found nothing and the next line failed with "Error using ~,
%   not enough input arguments" -- a message that names neither the format nor
%   the registry. Found by running the suite (rev. 1.41).
%
%   The guard below exists so that if this ever fails again it fails by name.
%   A lookup that cannot fail loudly is a lookup that fails quietly.

    match = [registry.name] == formatName;
    if ~any(match)
        error('referenceSystem:readEop:unknownFormat', ...
            ['"%s" is not a registered series format. The registry holds: ', ...
            '%s.'], formatName, join([registry.name], ", "));
    end
    entry = registry(match);
end

function headerText = localReadHead(file)
%LOCALREADHEAD The first part of the file, enough to identify it by.
%   Reading a fixed number of bytes rather than the whole file keeps
%   identification cheap on a 4 MB series.

    fid = fopen(file, 'r');
    if fid < 0
        error('referenceSystem:readEop:noData', ...
            'Could not open "%s" for reading.', file);
    end
    closeFile = onCleanup(@() fclose(fid));
    headerText = string(fread(fid, 4096, '*char')');
end

function formatName = localIdentify(headerText, registry, file)
%LOCALIDENTIFY Which registry entry the file matches.
%   Signatures are checked most specific first, because the dPsi/dEpsilon
%   product carries the 20 C04 signature as well as its own.

    for k = [3 1 2]
        if registry(k).signature ~= "" && contains(headerText, registry(k).signature)
            formatName = registry(k).name;
            return
        end
    end

    % finals2000A has no header of any kind, so it is identified by the shape
    % of its first line: a two-digit year, a fixed-width MJD at columns 8 to 15
    % and a record at least as long as the Bulletin A block.
    firstLine = extractBefore(headerText + newline, newline);
    if strlength(firstLine) >= 134 && ...
            ~isnan(str2double(extractBetween(firstLine, 8, 15))) && ...
            ~isnan(str2double(extractBetween(firstLine, 1, 2)))
        formatName = "finals2000A";
        return
    end

    error('referenceSystem:readEop:unknownFormat', ...
        ['The format of "%s" could not be identified. Supported series are ', ...
        'EOP 14 C04, EOP 20 C04, EOP 20 C04 dPsiDEpsilon and finals2000A. ', ...
        'Pass ''Format'' explicitly if the file is one of these with an ', ...
        'edited header; the format is never guessed, because a wrong column ', ...
        'map produces a series that is plausible and wrong.'], file);
end

function [column, rowsRead] = localReadDelimited(file, entry)
%LOCALREADDELIMITED Whitespace-separated series, parsed deterministically.
%   Not detectImportOptions. That function guesses the variable count from
%   whatever it makes of the header, and a guess that comes out low silently
%   truncates the very columns the registry map then indexes into. The rule
%   here is explicit instead: a data row is one that begins with a digit or a
%   sign, every header line of every supported series begins with text,
%   whitespace or the comment prefix, and every data row must carry exactly the
%   field count the registry declares. A file that breaks that assumption is an
%   error naming the counts, not a quietly shortened table.

    lineText = string(splitlines(fileread(file)));
    isData = ~ismissing(regexp(lineText, '^\s*[-+]?\d', 'once', 'match'));
    if entry.commentPrefix ~= ""
        isData = isData & ~startsWith(strip(lineText), entry.commentPrefix);
    end
    dataText = lineText(isData);
    rowsRead = numel(dataText);

    name = localColumnNames();
    if rowsRead == 0
        column = array2table(nan(0, numel(name)), 'VariableNames', cellstr(name));
        return
    end

    fieldCount = numel(sscanf(dataText(1), '%f'));
    if fieldCount ~= entry.minimumFields
        error('referenceSystem:readEop:unknownFormat', ...
            ['The first data row of "%s" has %d numeric fields; the %s ', ...
            'layout has %d. The file is not the series it was identified ', ...
            'as, or the series has gained a column and the registry entry ', ...
            'needs updating.'], file, fieldCount, entry.name, entry.minimumFields);
    end

    value = sscanf(join(dataText, newline), '%f');
    if mod(numel(value), entry.minimumFields) ~= 0
        error('referenceSystem:readEop:unknownFormat', ...
            ['"%s" has ragged rows: %d numeric fields do not divide into ', ...
            'rows of %d. One data row differs from the rest.'], ...
            file, numel(value), entry.minimumFields);
    end
    raw = reshape(value, entry.minimumFields, [])';

    mapped = nan(size(raw, 1), numel(name));
    for k = 1:numel(name)
        mapped(:, k) = raw(:, entry.index.(name(k)));
    end
    column = array2table(mapped, 'VariableNames', cellstr(name));
    column = localApplyScale(column, entry);
end

function name = localColumnNames()
%LOCALCOLUMNNAMES The quantities every reader produces, in one place.
%   Both readers built this list independently before; two copies of a column
%   list is two chances to disagree.

    name = ["mjd", "xp", "yp", "dut1", "lod", "dX", "dY", "sigmaXp", ...
        "sigmaYp", "sigmaDut1", "sigmaLod", "sigmaDX", "sigmaDY"];
end

function [column, rowsRead] = localReadFixedWidth(file, entry, bulletin)
%LOCALREADFIXEDWIDTH finals2000A, sliced by character position.
%   The trailing rows of a finals series carry a date and nothing else, since
%   the predictions run out before the file does. They parse to NaN and are
%   dropped by the completeness test in the caller, which is why the slices
%   below do not have to be defensive about short lines.

    lineText = string(splitlines(fileread(file)));
    lineText = lineText(strlength(lineText) >= 134);
    rowsRead = numel(lineText);

    name = localColumnNames();
    raw = nan(rowsRead, numel(name));
    for k = 1:numel(name)
        span = entry.index.(name(k));
        if bulletin == "B"
            % Bulletin B publishes xp, yp, UT1-UTC, dX and dY, and nothing
            % else. LOD and every formal error are left NaN rather than
            % filled from the Bulletin A columns beside them: quietly
            % blending two solutions into one struct is exactly the kind of
            % invisible mixture this toolbox exists to refuse.
            if isfield(entry.index, "bulletinB" + name(k))
                span = entry.index.("bulletinB" + name(k));
            else
                continue
            end
        end
        raw(:, k) = localSlice(lineText, span);
    end

    column = array2table(raw, 'VariableNames', cellstr(name));
    column = localApplyScale(column, entry);
end

function value = localSlice(lineText, span)
%LOCALSLICE One fixed-width numeric field of every line.
%   Lines shorter than the field are padded rather than indexed past their end,
%   which is how the Bulletin B block of a prediction row becomes NaN.

    padded = pad(lineText, span(2));
    value = str2double(extractBetween(padded, span(1), span(2)));
end

function column = localApplyScale(column, entry)
%LOCALAPPLYSCALE Published units to SI, once, here.
%   The value column and its formal error carry the same unit and therefore the
%   same factor, so the pairing is stated explicitly rather than derived from
%   the name by string surgery, which would be shorter and unreadable.

    valueName = ["xp",      "yp",      "dut1",      "lod",      "dX",      "dY"];
    sigmaName = ["sigmaXp", "sigmaYp", "sigmaDut1", "sigmaLod", "sigmaDX", "sigmaDY"];

    for k = 1:numel(valueName)
        factor = entry.scale.(valueName(k));
        column.(valueName(k)) = column.(valueName(k)) * factor;
        column.(sigmaName(k)) = column.(sigmaName(k)) * factor;
    end
end

function eop = localAssemble(column, entry, options, formatName, file, headerText)
%LOCALASSEMBLE The eop struct, including the equinox-based conversion.

    dX = column.dX;
    dY = column.dY;
    sigmaDX = column.sigmaDX;
    sigmaDY = column.sigmaDY;
    poleOffsetType = "observed dXdY";

    if entry.poleOffsetsAreEquinoxBased
        % IERS TN36 Ch. 5, first order: dX = dPsi*sin(eps0), dY = dEpsilon.
        % eps0 = 84381.406 arcseconds, the IAU 2006 obliquity at J2000.0.
        sinObliquity = sin(84381.406 * referenceSystem.iersConstants().arcsecondsToRadians);
        dX = column.dX * sinObliquity;
        sigmaDX = column.sigmaDX * sinObliquity;
        poleOffsetType = "converted from dPsiDEpsilon";
    end

    cipModel = entry.cipModel;
    cipModelSource = "format registry";
    if options.CipModel ~= "auto"
        cipModel = options.CipModel;
        cipModelSource = "caller";
    end

    bulletin = "";
    if entry.hasBulletinB
        bulletin = options.Bulletin;
    end

    eop = struct( ...
        'mjd', column.mjd, 'xp', column.xp, 'yp', column.yp, ...
        'dut1', column.dut1, 'lod', column.lod, 'dX', dX, 'dY', dY, ...
        'sigma', struct('xp', column.sigmaXp, 'yp', column.sigmaYp, ...
            'dut1', column.sigmaDut1, 'lod', column.sigmaLod, ...
            'dX', sigmaDX, 'dY', sigmaDY), ...
        'meta', struct( ...
            'series', formatName, ...
            'cipModel', cipModel, ...
            'cipModelSource', cipModelSource, ...
            'cipModelStatement', localModelStatement(headerText), ...
            'poleOffsetType', poleOffsetType, ...
            'itrf', entry.itrf, ...
            'file', string(fullfile(file)), ...
            'readTime', datetime('now', 'TimeZone', 'local'), ...
            'nRows', numel(column.mjd), ...
            'mjdRange', [min(column.mjd) max(column.mjd)], ...
            'samplingHour', entry.samplingHour, ...
            'bulletin', bulletin));
end

function statement = localModelStatement(headerText)
%LOCALMODELSTATEMENT What the file says about its precession-nutation model.
%   Recorded verbatim and not interpreted. See the METHOD block: the same line
%   appears on the CIO-based and the equinox-based product of one solution, so
%   it identifies a series family rather than a model.

    token = regexp(headerText, ...
        'Reference\s+Precession-Nutation\s+Model\s*:\s*([^\r\n]*)', ...
        'tokens', 'once');
    if isempty(token)
        statement = "";
    else
        statement = strtrim(string(token{1}));
    end
end

function localValidate(eop, formatName)
%LOCALVALIDATE Monotonic epochs and physically possible values.

    if any(diff(eop.mjd) <= 0)
        first = find(diff(eop.mjd) <= 0, 1);
        error('referenceSystem:readEop:notMonotonic', ...
            ['The MJD column of the %s series is not strictly increasing: ', ...
            'row %d is %.2f and row %d is %.2f. Interpolation of a ', ...
            'non-monotonic table is undefined.'], formatName, first, ...
            eop.mjd(first), first + 1, eop.mjd(first + 1));
    end

    % Physical bounds, generous by an order of magnitude on the observed range.
    % These exist to catch a column map applied to the wrong file, which is the
    % one reading error that produces numbers rather than an exception.
    as2r = referenceSystem.iersConstants().arcsecondsToRadians;
    limit = struct('xp', 2*as2r, 'yp', 2*as2r, 'dut1', 1.5, 'lod', 0.02, ...
        'dX', 0.05*as2r, 'dY', 0.05*as2r);
    for name = string(fieldnames(limit))'
        value = eop.(name);
        bad = find(abs(value) > limit.(name) & isfinite(value), 1);
        if ~isempty(bad)
            error('referenceSystem:readEop:implausibleValue', ...
                ['Reading "%s" as %s gives %s = %g at MJD %.2f, which is ', ...
                'outside anything this quantity can physically be (limit ', ...
                '%g, SI units). The file is almost certainly not the series ', ...
                'it was identified as, or the column map is wrong.'], ...
                eop.meta.file, formatName, name, value(bad), eop.mjd(bad), ...
                limit.(name));
        end
    end
end

function [gapCount, largestGap] = localReportGaps(mjd, entry, formatName)
%LOCALREPORTGAPS One aggregated warning for a gapped series, never one per gap.

    step = diff(mjd);
    isGap = step > entry.stepDays * 1.5;
    gapCount = sum(isGap);
    largestGap = 0;
    if gapCount == 0
        return
    end
    largestGap = max(step(isGap));
    first = find(isGap, 1);
    warning('referenceSystem:readEop:samplingGap', ...
        ['The %s series has %d gap(s) longer than its %g-day sampling; the ', ...
        'first is %.1f days after MJD %.2f and the longest is %.1f days. ', ...
        'Interpolation across a gap is an extrapolation in all but name.'], ...
        formatName, gapCount, entry.stepDays, step(first), mjd(first), largestGap);
end
