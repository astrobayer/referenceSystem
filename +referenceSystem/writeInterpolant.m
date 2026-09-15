function file = writeInterpolant(interpolant, file)
%WRITEINTERPOLANT Write an Earth orientation interpolant to a portable file.
%   file = writeInterpolant(interpolant, file) writes the panels produced by
%   earthOrientationInterpolant in the format mex/rsApi.h reads, so an orbit
%   integrator written in C can obtain the rotation with no MATLAB in its loop.
%
% INPUT ARGUMENTS
%   Name          Size   Type     Units  Description
%   ----          ----   ----     -----  -----------
%   interpolant   1x1    struct   -      Output of earthOrientationInterpolant.
%   file          1x1    string   -      Destination path.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   file   1x1    string   -      The path written, for chaining.
%
% METHOD
%   TEXT, NOT BINARY, AND THE COEFFICIENTS CARRY %.17g. Seventeen significant
%   decimal digits round-trip an IEEE-754 double EXACTLY, so nothing is lost
%   while the file stays inspectable, diffable, and free of endianness and
%   struct padding. A binary format would be shorter and would make a byte-order
%   defect look like an accuracy problem in an integrator days later, which is
%   the characteristic failure of this domain.
%
%   Coefficients are panel-major and quantity-major within a panel, the layout
%   rsApi.h documents: one panel is contiguous, because an integrator stays
%   inside one for a whole day.
%
%   ONE VALUE PER LINE. Wider rows would be shorter, but a reader that lost
%   count would resynchronise silently on the next line; one per line makes a
%   truncated file a parse failure rather than a shifted array.
%
%   The tidal setting is written because A READER MUST BE ABLE TO REFUSE A
%   MISMATCH: an interpolant built without the sub-daily terms differs by tens
%   of microarcseconds and the resulting rotation gives no sign of it. The
%   interpolation method and zonal-tide treatment the panels were fitted
%   through are written as provenance when the interpolant carries them.
%
% ACCURACY
%   Exact. Every coefficient survives the round trip bit for bit, and the test
%   asserts it with AbsTol 0 rather than a tolerance.
%
% ERRORS
%   referenceSystem:writeInterpolant:badInterpolant
%   referenceSystem:writeInterpolant:cannotOpen
%
% REFERENCES
%   mex/rsApi.h for the same layout on the C side; handover D82.
%
% EXAMPLE
%   eop = referenceSystem.readEop('eop20c04.txt');
%   span = referenceSystem.daySecondToEpoch([57754 0; 57757 0], "UTC");
%   ip = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
%   referenceSystem.writeInterpolant(ip, "arc.eopi");
%
% KEYWORDS
%   interpolant, serialisation, Chebyshev, C interface, Earth orientation
%
% See also earthOrientationInterpolant, readInterpolant, evaluateInterpolant
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 21:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        interpolant (1,1) struct
        file (1,1) string
    end

    required = ["panelStartMjd", "panelSpan", "degree", "quantity", ...
        "coefficient", "taiMinusUtc", "meta"];
    missing = required(~isfield(interpolant, required));
    if ~isempty(missing)
        error('referenceSystem:writeInterpolant:badInterpolant', ...
            'The interpolant is missing %s.', strjoin(missing, ", "));
    end

    fileId = fopen(file, 'w');
    if fileId < 0
        error('referenceSystem:writeInterpolant:cannotOpen', ...
            'Could not open %s for writing.', file);
    end
    cleanup = onCleanup(@() fclose(fileId));

    panelCount = numel(interpolant.panelStartMjd);
    % FORMAT 2 SINCE P19c: SEVEN CHANNELS, THE SEVENTH BEING THE EXCESS LENGTH
    % OF DAY. The version is bumped rather than the channel count being left to
    % be inferred, and BOTH readers accept 1 and 2 - the committed arc.eopi
    % fixture is format 1 and is the only end-to-end evidence that the C side
    % reads what MATLAB wrote, so a bump that invalidated it would have
    % destroyed that check while claiming to extend the format.
    fprintf(fileId, 'referenceSystemInterpolant 2\n');
    fprintf(fileId, 'degree %d\n', interpolant.degree);
    fprintf(fileId, 'panelCount %d\n', panelCount);
    fprintf(fileId, 'panelSpan %.17g\n', interpolant.panelSpan);
    fprintf(fileId, 'firstPanelMjd %.17g\n', interpolant.panelStartMjd(1));
    fprintf(fileId, 'cipModel %s\n', interpolant.meta.cipModel);
    fprintf(fileId, 'tidalCorrections %d\n', interpolant.meta.tidalCorrections);
    for key = ["method", "zonalTides"]
        if isfield(interpolant.meta, key)
            fprintf(fileId, '%s %s\n', key, interpolant.meta.(key));
        end
    end
    fprintf(fileId, 'quantity %s\n', strjoin(interpolant.quantity, " "));
    fprintf(fileId, 'taiMinusUtc');
    fprintf(fileId, ' %.17g', interpolant.taiMinusUtc);
    fprintf(fileId, '\ncoefficient\n');

    for panel = 1:panelCount
        for quantity = 1:numel(interpolant.quantity)
            fprintf(fileId, '%.17g\n', ...
                interpolant.coefficient(:, quantity, panel));
        end
    end
    clear cleanup
end
