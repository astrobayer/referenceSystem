function [imu, info] = readImu1b(fileName)
%READIMU1B Read a GRACE-FO IMU1B filtered-gyro-angle product.
%
%   imu = readImu1b(fileName) reads the ASCII IMU1B product named by fileName
%   and returns the filtered gyro angles with their epochs, exactly as the file
%   states them: one record per gyro per sample, angles in degrees, epochs in
%   GPS time. Nothing is differenced, unwrapped, resampled or projected here;
%   graceFoImuIncrements does that.
%
%   [imu, info] = readImu1b(fileName) also returns what the file was found to
%   contain and what was checked.
%
% INPUT ARGUMENTS
%   Name       Size   Type            Units  Description
%   ----       ----   ----            -----  -----------
%   fileName   1x1    string | char   -      Path to an IMU1B ASCII file.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   imu                 1x1    struct   -      The product.
%   .epoch              1x1    struct   -      Canonical epoch, N entries, GPS.
%   .gyroId             Nx1    double   -      Gyro number, 1 to 4.
%   .filteredAngle      Nx1    double   deg    The FiltAng field, VERBATIM.
%                                              Accumulated, not an increment.
%   .qualityFlag        Nx1    string   -      The eight-character qualflg.
%   .satellite          1x1    string   -      "C" or "D", from column 4.
%   .meta               1x1    struct   -      Provenance.
%   .meta.file          1x1    string   -      Absolute path read.
%   .meta.product       1x1    string   -      "IMU1B".
%   .meta.timeReference 1x1    string   -      "G", the value of column 3.
%   .meta.angleUnit     1x1    string   -      "degrees".
%   .meta.declaredRecordCount 1x1 double -     num_records from the header.
%   info                1x1    struct   -      Diagnostics.
%   .recordCount        1x1    double   -      Records read.
%   .gyroIdPresent      1xG    double   -      Sorted gyro numbers found.
%   .recordsPerGyro     1xG    double   -      Count for each of them.
%   .sampleIntervalMedian 1x1  double   s      Median spacing per gyro series.
%   .sampleIntervalRange 1x2   double   s      Smallest and largest spacing.
%   .largestGap         1x1    double   s      Largest spacing in any series.
%   .flaggedRecordCount 1x1    double   -      Records whose qualflg is not
%                                              all zeros.
%
% METHOD
%   THE RECORD LAYOUT IS ASSERTED IN TWO INDEPENDENT WAYS AND TRUSTED IN
%   NEITHER ALONE. Handbook section 3.4.2 warns that a reader should not be
%   built to depend on the header, and a reader that ignores the header cannot
%   notice a layout change at all. So the seven expected column names are held
%   here, the header's variables block must agree with them in order when it is
%   present, and the first data record must independently have seven fields of
%   the right kinds. A file that fails either check is refused rather than
%   indexed.
%
%   THE TIME SCALE IS READ FROM COLUMN 3 AND NOT FROM THE HEADER, BECAUSE THE
%   HEADER OF A REAL FILE IS WRONG ABOUT IT. IMU1B shares its format with
%   IMU1A, and the shipped 2020-01-01 GRACE C product carries the inherited
%   long_name "... in OBC Time" for column 1 while column 3 reads "G" and
%   handbook section 4.2.10 states that IMU1B time tags are in GPS Time. A
%   reader that believed the header would tag a GPS series as OBC time, which
%   nothing downstream could detect. Column 3 must read "G": an IMU1A file
%   needs TIM1B and CLK1B to reach GPS time and this toolbox does not do that
%   conversion, so it is refused by name rather than read as if it were 1B.
%
%   THE EPOCH IS BUILT THROUGH THE PACKAGE CONSTRUCTOR. GRACE-FO counts GPS
%   seconds from 2000-01-01T12:00:00 GPS, which is exactly what
%   j2000SecondsToEpoch means by its "GPS" scale, so the integer and fractional
%   columns are recombined and handed over without any leap-second arithmetic
%   here.
%
%   THE DECLARED RECORD COUNT IS CHECKED. A truncated file parses perfectly and
%   yields a shorter arc, which is a defect that looks like a short day.
%
% ACCURACY
%   Lossless. The angle is the file's decimal converted to the nearest double;
%   the shipped values carry fifteen significant digits, below the resolution
%   of a double at 5757 deg (9.1e-13 deg), so the conversion is exact to the
%   printed precision.
%
%   The epoch is exact to the microsecond the file states: the fractional
%   column is an integer number of microseconds, and it enters the seconds
%   field of the split epoch, where one unit in the last place is 1.5e-11 s.
%
% ERRORS
%   referenceSystem:readImu1b:fileNotFound
%   referenceSystem:readImu1b:headerNotTerminated
%   referenceSystem:readImu1b:unexpectedLayout
%   referenceSystem:readImu1b:wrongTimeReference
%   referenceSystem:readImu1b:mixedSatellite
%   referenceSystem:readImu1b:recordCountMismatch
%   referenceSystem:readImu1b:noData
%
% REFERENCES
%   Wen, H. Y., et al. (2019), GRACE-FO Level-1 Data Product User Handbook,
%   JPL D-56935, sections 3.4.2, 3.4.3 and 4.2.10.
%
% EXAMPLE
%   fileName = fullfile("test", "fixtures", "imu1bGraceC.txt");
%   [imu, info] = referenceSystem.readImu1b(fileName);
%   disp(info.recordsPerGyro);
%
% KEYWORDS
%   GRACE-FO, IMU1B, gyro, filtered angle, delta-theta, attitude
%
% See also GRACEFOIMUINCREMENTS, GRACEFOIMUALIGNMENT, READEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 21:20 (CEST, UTC+02:00) - session S9, prompt P27
% -------------------------------------------------------------------------

    arguments
        fileName (1,1) string
    end

    expectedVariable = ["rcvtime_intg", "rcvtime_frac", "time_ref", ...
        "GRACEFO_id", "gyro_id", "FiltAng", "qualflg"];

    resolved = localResolveFile(fileName);
    fid = fopen(resolved, 'r');
    if fid < 0
        error('referenceSystem:readImu1b:fileNotFound', ...
            'Cannot open "%s" for reading.', resolved);
    end
    closer = onCleanup(@() fclose(fid));

    [headerVariable, declaredCount] = localReadHeader(fid, resolved);
    localCheckLayout(headerVariable, expectedVariable, resolved);

    columns = textscan(fid, '%f %f %s %s %f %f %s', ...
        'CollectOutput', false, 'ReturnOnError', false);

    recordCount = numel(columns{1});
    if recordCount == 0
        error('referenceSystem:readImu1b:noData', ...
            'File "%s" has a header but no data records.', resolved);
    end
    if ~isnan(declaredCount) && declaredCount ~= recordCount
        error('referenceSystem:readImu1b:recordCountMismatch', ...
            ['File "%s" declares num_records = %d in its header and holds ' ...
             '%d data records. A truncated file parses perfectly and yields ' ...
             'a short arc, so the difference is refused rather than read.'], ...
            resolved, declaredCount, recordCount);
    end

    timeReference = unique(string(columns{3}));
    if ~isscalar(timeReference) || timeReference ~= "G"
        error('referenceSystem:readImu1b:wrongTimeReference', ...
            ['Column 3 of "%s" reads %s; IMU1B carries "G" for GPS time. ' ...
             'An IMU1A file reads "R" and its time tags need TIM1B and ' ...
             'CLK1B to reach GPS time, which this toolbox does not do.'], ...
            resolved, strjoin("""" + timeReference + """", ", "));
    end

    satellite = unique(string(columns{4}));
    if ~isscalar(satellite)
        error('referenceSystem:readImu1b:mixedSatellite', ...
            ['File "%s" carries records for satellites %s. The gyro ' ...
             'alignment is per satellite, so a mixed file cannot be ' ...
             'projected into one Satellite Frame.'], ...
            resolved, strjoin("""" + satellite + """", ", "));
    end

    gpsSecond = columns{1} + columns{2}*1e-6;
    imu = struct( ...
        'epoch', referenceSystem.j2000SecondsToEpoch(gpsSecond, "GPS"), ...
        'gyroId', columns{5}, ...
        'filteredAngle', columns{6}, ...
        'qualityFlag', string(columns{7}), ...
        'satellite', satellite, ...
        'meta', struct( ...
            'file', string(resolved), ...
            'product', "IMU1B", ...
            'timeReference', timeReference, ...
            'angleUnit', "degrees", ...
            'declaredRecordCount', declaredCount));

    info = localSummarize(imu, gpsSecond, recordCount);
end

% -------------------------------------------------------------------------
function resolved = localResolveFile(fileName)
    % Report the path that was actually looked for, not the one supplied, so a
    % relative name that missed says where it was resolved to.
    found = which(fileName);
    if isempty(found)
        resolved = char(fileName);
    else
        resolved = found;
    end
    if exist(resolved, 'file') ~= 2
        error('referenceSystem:readImu1b:fileNotFound', ...
            'No file "%s". Resolved from "%s".', resolved, fileName);
    end
end

% -------------------------------------------------------------------------
function [headerVariable, declaredCount] = localReadHeader(fid, resolved)
    % Read to the end-of-header marker, collecting num_records and the ordered
    % list of variable names. This is a two-field extraction and deliberately
    % not a YAML parser: only these two items are used, and both are
    % cross-checked against the body.
    headerVariable = strings(0, 1);
    declaredCount = NaN;
    inVariables = false;
    terminated = false;
    while true
        line = fgetl(fid);
        if ~ischar(line)
            break
        end
        trimmed = string(strtrim(line));
        if startsWith(trimmed, "# End of YAML header")
            terminated = true;
            break
        end
        if startsWith(trimmed, "num_records:")
            declaredCount = str2double(extractAfter(trimmed, "num_records:"));
        elseif trimmed == "variables:"
            inVariables = true;
        elseif inVariables && startsWith(trimmed, "- ") && endsWith(trimmed, ":")
            headerVariable(end+1, 1) = extractBetween(trimmed, 3, ...
                strlength(trimmed) - 1); %#ok<AGROW>
        end
    end
    if ~terminated
        error('referenceSystem:readImu1b:headerNotTerminated', ...
            ['File "%s" has no "# End of YAML header" line. Every Level-1 ' ...
             'product carries one and the data records begin after it.'], ...
            resolved);
    end
end

% -------------------------------------------------------------------------
function localCheckLayout(headerVariable, expectedVariable, resolved)
    if isempty(headerVariable)
        error('referenceSystem:readImu1b:unexpectedLayout', ...
            ['The header of "%s" declares no variables block, so the column ' ...
             'layout cannot be confirmed. Expected, in order: %s.'], ...
            resolved, strjoin(expectedVariable, ", "));
    end
    if numel(headerVariable) ~= numel(expectedVariable) || ...
            ~all(headerVariable(:)' == expectedVariable)
        error('referenceSystem:readImu1b:unexpectedLayout', ...
            ['The header of "%s" declares the columns %s. IMU1B is %s. ' ...
             'Reading column six of a different layout would return a ' ...
             'plausible number that is not an angle.'], ...
            resolved, strjoin(headerVariable(:)', ", "), ...
            strjoin(expectedVariable, ", "));
    end
end

% -------------------------------------------------------------------------
function info = localSummarize(imu, gpsSecond, recordCount)
    gyroIdPresent = unique(imu.gyroId(:))';
    recordsPerGyro = zeros(1, numel(gyroIdPresent));
    intervalMedian = NaN(1, numel(gyroIdPresent));
    smallest = Inf;
    largest = 0;
    for k = 1:numel(gyroIdPresent)
        selected = sort(gpsSecond(imu.gyroId == gyroIdPresent(k)));
        recordsPerGyro(k) = numel(selected);
        spacing = diff(selected);
        if ~isempty(spacing)
            intervalMedian(k) = median(spacing);
            smallest = min(smallest, min(spacing));
            largest = max(largest, max(spacing));
        end
    end
    if ~isfinite(smallest)
        smallest = NaN;
        largest = NaN;
    end
    info = struct( ...
        'recordCount', recordCount, ...
        'gyroIdPresent', gyroIdPresent, ...
        'recordsPerGyro', recordsPerGyro, ...
        'sampleIntervalMedian', median(intervalMedian, 'omitnan'), ...
        'sampleIntervalRange', [smallest, largest], ...
        'largestGap', largest, ...
        'flaggedRecordCount', sum(imu.qualityFlag ~= "00000000"));
end
