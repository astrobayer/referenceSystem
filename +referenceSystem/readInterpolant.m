function interpolant = readInterpolant(file)
%READINTERPOLANT Read an interpolant written by writeInterpolant.
%   interpolant = readInterpolant(file) reconstructs the struct
%   earthOrientationInterpolant produced, so a file written on one machine can
%   be used on another and so the round trip is testable from MATLAB.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   file   1x1    string   -      Path written by writeInterpolant.
%
% OUTPUT ARGUMENTS
%   Name          Size   Type     Units  Description
%   ----          ----   ----     -----  -----------
%   interpolant   1x1    struct   -      As earthOrientationInterpolant returns
%                                        it, except that .meta carries only
%                                        what the file holds: cipModel,
%                                        tidalCorrections and, where written,
%                                        method and zonalTides.
%
% METHOD
%   Header keys are read BY NAME, not by position, so a field added to the
%   writer does not shift everything after it.
%
%   AN UNKNOWN VERSION IS REFUSED rather than read hopefully. A format that
%   changed and a reader that guessed would produce coefficients that are
%   plausible and wrong, which is how every silent failure in this project has
%   presented itself.
%
%   THE RESIDUAL IS NOT CARRIED. earthOrientationInterpolant measures it
%   against samples the fit did not see; a number copied through a file is no
%   longer a measurement of anything. A caller who needs it rebuilds.
%
% ACCURACY
%   Exact. Every coefficient is recovered bit for bit from the %.17g written.
%
% ERRORS
%   referenceSystem:readInterpolant:cannotOpen
%   referenceSystem:readInterpolant:badFormat
%
% REFERENCES
%   mex/rsApi.h for the same layout on the C side.
%
% EXAMPLE
%   ip = referenceSystem.readInterpolant("arc.eopi");   % written earlier by
%   value = referenceSystem.evaluateInterpolant(ip, ...   % writeInterpolant
%       ip.panelStartMjd(1) + 0.5, 1);
%
% KEYWORDS
%   interpolant, deserialisation, Chebyshev, Earth orientation
%
% See also writeInterpolant, earthOrientationInterpolant
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 21:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        file (1,1) string
    end

    if ~isfile(file)
        error('referenceSystem:readInterpolant:cannotOpen', ...
            'No such file: %s.', file);
    end
    line = string(splitlines(strtrim(fileread(file))));

    % FORMATS 1 AND 2 ARE BOTH READ, AND THE CHANNEL COUNT COMES FROM THE
    % FILE'S OWN quantity LINE RATHER THAN FROM THE VERSION. Format 2 appends
    % the excess length of day (P19c); everything below already sizes itself
    % from numel(quantity), so the only thing the version guards is that an
    % UNKNOWN format is refused instead of being read hopefully.
    knownFormat = "referenceSystemInterpolant " + ["1", "2"];
    if ~any(startsWith(line(1), knownFormat))
        error('referenceSystem:readInterpolant:badFormat', ...
            ['%s is not a version 1 or 2 interpolant file; its first line ', ...
            'reads "%s". A reader that guessed at an unknown version would ', ...
            'return coefficients that are plausible and wrong.'], ...
            file, line(1));
    end

    keyValue = @(key) strtrim(extractAfter( ...
        line(find(startsWith(line, key + " "), 1)), strlength(key)));
    degree = str2double(keyValue("degree"));
    panelCount = str2double(keyValue("panelCount"));
    panelSpan = str2double(keyValue("panelSpan"));
    quantity = split(keyValue("quantity"))';

    coefficientStart = find(line == "coefficient", 1) + 1;
    if isempty(coefficientStart)
        error('referenceSystem:readInterpolant:badFormat', ...
            '%s has no coefficient block.', file);
    end
    expected = (degree + 1) * numel(quantity) * panelCount;
    body = str2double(line(coefficientStart:end));
    if numel(body) ~= expected
        error('referenceSystem:readInterpolant:badFormat', ...
            ['%s holds %d coefficients and its header describes %d. A ', ...
            'truncated file is refused rather than padded.'], ...
            file, numel(body), expected);
    end

    interpolant = struct( ...
        'panelStartMjd', str2double(keyValue("firstPanelMjd")) + ...
            (0:panelCount-1)' * panelSpan, ...
        'panelSpan', panelSpan, ...
        'degree', degree, ...
        'quantity', string(quantity), ...
        'taiMinusUtc', str2double(split(keyValue("taiMinusUtc"))), ...
        'coefficient', reshape(body, degree + 1, numel(quantity), panelCount), ...
        'meta', struct('cipModel', keyValue("cipModel"), ...
            'tidalCorrections', ...
            logical(str2double(keyValue("tidalCorrections")))));
    % Provenance written by writeInterpolant when the panels carry it.
    for key = ["method", "zonalTides"]
        if any(startsWith(line, key + " "))
            interpolant.meta.(key) = keyValue(key);
        end
    end
end
