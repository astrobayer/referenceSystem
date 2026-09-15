function interpolant = earthOrientationInterpolant(epoch, options)
%EARTHORIENTATIONINTERPOLANT Chebyshev panels for the ITRS to GCRS chain.
%   interpolant = earthOrientationInterpolant(epoch, 'Eop', eop) fits the
%   quantities the terrestrial-to-celestial rotation and its rate need - the
%   CIP X and Y, the CIO locator s, the two pole coordinates, UT1 minus UTC
%   and the excess length of day - over the span covered by epoch, and returns
%   them as Chebyshev coefficients on consecutive panels, one channel per
%   entry of .quantity.
%
%   The result is accepted by rotationItrsToGcrs through its 'Interpolant'
%   option, and it is the same object the public C API evaluates, so an
%   integrator written in C can obtain the rotation with no MATLAB in its loop.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, scale UTC. Only the
%                                  earliest and latest entries are read: they
%                                  bound the span to be covered. N = 2 is the
%                                  usual call and N = 1 is refused, because a
%                                  single instant does not describe a span.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default  Description
%   ----        ----   ----     -------  -----------
%   Eop         1x1    struct   none     Series from readEop. Required: the
%                                        pole and UT1 are measured and cannot
%                                        be modelled.
%   Degree      1x1    double   20       Chebyshev degree per panel. The
%                                        default is decision D82 and is
%                                        measured, not assumed - see METHOD.
%   PanelSpan   1x1    double   1        Panel length in days.
%   ApplyTidalCorrections
%               1x1    logical  true     Whether the sub-daily ocean tide and
%                                        libration are folded into the fitted
%                                        pole and UT1. MUST MATCH the setting
%                                        the consumer uses; an interpolant
%                                        built without them is wrong by tens of
%                                        microarcseconds for a caller that
%                                        wants them, which is why the choice is
%                                        recorded in .meta rather than assumed.
%   Tolerance   1x1    double   0.5      Residual the fit must achieve, in
%                                        microarcseconds. Checked against
%                                        samples the fit has NOT seen. A fit
%                                        that misses it raises toleranceNotMet
%                                        rather than returning quietly. The
%                                        same number gates every channel but
%                                        lod, as microarcseconds of rotation:
%                                        dut1's residual is converted at the
%                                        ERA rate, 15.04 uas per us. lod is
%                                        reported, not gated, because it is
%                                        not an angle.
%
% OUTPUT ARGUMENTS
%   Name              Size          Type     Units  Description
%   ----              ----          ----     -----  -----------
%   interpolant       1x1           struct   -      The panels. Fields below.
%   .panelStartMjd    Px1           double   d      UTC MJD at which each panel
%                                                   begins. Consecutive and
%                                                   equally spaced.
%   .panelSpan        1x1           double   d      Panel length.
%   .degree           1x1           double   -      Chebyshev degree.
%   .taiMinusUtc      Px1           double   s      Leap second count on each
%                                                   panel. The public C
%                                                   interface needs it to reach
%                                                   TT from UTC without a leap
%                                                   second table of its own, and
%                                                   a per-panel scalar is EXACT
%                                                   rather than approximate
%                                                   because a leap second may
%                                                   only fall on a panel
%                                                   boundary; one inside a
%                                                   panel is refused (see
%                                                   LEAP SECONDS).
%   .quantity         1xQ           string   -      Channel names, in column
%                                                   order. THE SINGLE AUTHORITY
%                                                   for the count Q and the
%                                                   order; no caller may assume
%                                                   either.
%   .coefficient      (D+1)xQxP     double   mixed  Chebyshev coefficients,
%                                                   D = degree, one column per
%                                                   entry of .quantity. Units
%                                                   by name: radians for X, Y,
%                                                   s, xp and yp; seconds for
%                                                   dut1; seconds per day for
%                                                   lod.
%   .meta             1x1           struct   -      Provenance. Fields below.
%   .meta.residual    1xQ           double   mixed  Worst error against the
%                                                   direct chain at samples the
%                                                   fit did not see, one entry
%                                                   per entry of .quantity:
%                                                   microarcseconds for the
%                                                   five angles, microseconds
%                                                   for dut1 and for lod.
%   .meta.tolerance   1x1           double   uas    Tolerance that was met, by
%                                                   every channel but lod (see
%                                                   Tolerance).
%   .meta.cipModel    1x1           string   -      Frame of the CIP offsets.
%   .meta.eopFile     1x1           string   -      Series the fit was built on.
%   .meta.spanMjd     1x2           double   d      Span actually covered,
%                                                   which is the requested span
%                                                   rounded outward to whole
%                                                   panels.
%   .meta.tidalCorrections
%                     1x1           logical  -      Whether the sub-daily terms
%                                                   are in the fit.
%   .meta.builtOn     1x1           string   -      Toolbox version and date.
%
% METHOD
%   One panel per PanelSpan days, aligned to whole days so that panel
%   boundaries fall where the EOP series changes row. Inside a panel each
%   quantity is a Chebyshev expansion on Gauss-Lobatto nodes.
%
%   THE FIT IS NOT PERFORMED HERE. The nodes, the fit and the evaluation are
%   the C routines in mex/rsCheb.c, reached through the gateway. A second
%   implementation in MATLAB would be a second authority for the same
%   arithmetic, and the MATLAB path and the C API would then agree only by
%   inspection. They now share one fit by construction.
%
%   DEGREE 20 OVER ONE DAY IS MEASURED, NOT PROPOSED. Handover section B.9.2
%   records the sweep. The binding quantity is not the CIP, which reaches its
%   double-precision floor at degree 8 over a day and does not improve after,
%   but the sub-daily ocean tide and libration, whose semi-diurnal terms need
%   degree 20 to reach 2.6e-7 uas. Degree 16 reaches 3.6e-4 uas and degree 12
%   only 0.2 uas. Risk R5 proposed 300 s node spacing from rev. 1.0; degree 20
%   over a day is an effective 4320 s and lands four orders below the tightest
%   tolerance this interface offers, so the proposal was over-conservative by
%   about fifteen and was aimed at the wrong quantity.
%
%   THE RESIDUAL IS COMPUTED AT POINTS THE FIT HAS NOT SEEN. Evaluating at the
%   nodes returns the node values to roundoff by construction and would report
%   a residual of zero for any degree, which is worse than reporting none. The
%   check therefore samples the midpoints between nodes, where a Chebyshev fit
%   is at its weakest, and compares against the same direct chain
%   rotationItrsToGcrs would have evaluated.
%
%   LEAP SECONDS. A panel carries one TAI-UTC, so a leap second may fall on a
%   panel boundary and nowhere else. One-day panels always meet that; a
%   longer PanelSpan with a leap second strictly inside a panel is refused
%   with leapSecondInsidePanel. The panel that ENDS in a leap second takes its
%   last node at 23:59:60, the instant its own linear time reaches, with
%   UT1-UTC continued in that day's convention - which is what lets a span
%   cross 2017-01-01 at all. Evaluation follows the MJD a caller hands in,
%   and the one second 23:59:60 has no MJD of its own, so rotationItrsToGcrs
%   refuses a sample inside it (insideLeapSecond) and the C API returns
%   RS_API_OUT_OF_RANGE for a difference shoulder that lands in it. Across the
%   boundary itself, measured on 2017-01-01 at twelve epochs from 0.9 d before
%   to 0.9 d after, including two 86.4 s from it: R within 2.3e-16 and Rdot
%   within 5.6e-19 1/s of the direct path.
%
% ACCURACY
%   With the default degree and panel span, against the direct chain:
%     CIP X, Y, s              better than 1e-4 uas
%     pole xp, yp              better than 1e-3 uas
%     UT1 - UTC                better than 1e-4 us
%     excess length of day     better than 1e-8 us (of seconds per day)
%   Measured at rev. 1.219 on six spans of test/fixtures/eop20c04.txt between
%   MJD 57655 and 57853: the worst readings were 6.8e-5 uas (Y), 4.9e-7 uas
%   (xp), 3.2e-8 us (dut1) and 7.7e-10 us (lod). The lod figure enters only
%   the Earth rotation rate, where 1e-8 us per day is below 1e-23 1/s.
%   These are fit errors only. They do not improve on the EOP series itself,
%   whose own formal errors are tens of microarcseconds, and they are not a
%   claim about the accuracy of the rotation - only that interpolating it costs
%   nothing measurable against evaluating it directly.
%
%   The interpolant is C-infinity inside a panel and continuous but not
%   differentiable across a panel boundary. That is still an improvement on the
%   direct path, whose piecewise linear EOP interpolation puts a slope
%   discontinuity at every midnight into a variable-step integrator's right
%   hand side.
%
% ERRORS
%   referenceSystem:earthOrientationInterpolant:missingEop
%   referenceSystem:earthOrientationInterpolant:wrongScale
%   referenceSystem:earthOrientationInterpolant:singleEpoch
%   referenceSystem:earthOrientationInterpolant:spanNotCovered
%   referenceSystem:earthOrientationInterpolant:leapSecondInsidePanel
%   referenceSystem:earthOrientationInterpolant:toleranceNotMet
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, chapter 5.
%   Handover section B.9.1 and B.9.2, decisions D22 and D82, risk R5.
%
% EXAMPLE
%   eop = referenceSystem.readEop('eop20c04.txt');
%   span = referenceSystem.daySecondToEpoch([57754 0; 57764 0], "UTC");
%   ip = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
%   R = referenceSystem.rotationItrsToGcrs(epoch, 'Interpolant', ip);
%
% KEYWORDS
%   Chebyshev, interpolation, Earth orientation, CIP, polar motion, UT1,
%   length of day, precise orbit determination
%
% See also rotationItrsToGcrs, cipCoordinates, interpolateEop, readEop
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 10:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Eop (1,1) struct
        options.Degree (1,1) double {mustBeInteger, mustBePositive} = 20
        options.PanelSpan (1,1) double {mustBePositive, mustBeFinite} = 1
        options.Tolerance (1,1) double {mustBePositive, mustBeFinite} = 0.5
        options.ApplyTidalCorrections (1,1) logical = true
    end

    if ~isfield(options, 'Eop')
        error('referenceSystem:earthOrientationInterpolant:missingEop', ...
            ['An EOP series is required. The pole coordinates and UT1 are ', ...
            'measured quantities and there is no model to fall back on.']);
    end
    if epoch.scale ~= "UTC"
        error('referenceSystem:earthOrientationInterpolant:wrongScale', ...
            ['The span is given in UTC, not %s. It is not converted for you, ', ...
            'because a span silently reinterpreted in another scale is a ', ...
            'panel grid that no longer aligns with the EOP series rows.'], ...
            epoch.scale);
    end

    % epoch.sec, not epoch.second. The field name was taken from memory at
    % rev. 1.89 rather than from daySecondToEpoch, which is the authority
    % for it, and every test of this function failed on the same line.
    requestedMjd = epoch.day + epoch.sec / 86400;
    if numel(requestedMjd) < 2
        error('referenceSystem:earthOrientationInterpolant:singleEpoch', ...
            ['A single instant does not describe a span. Supply at least ', ...
            'two epochs; the earliest and the latest are what is read.']);
    end

    % Panels are aligned to whole days rather than to the requested start, so
    % that a boundary falls where the EOP series changes row and two callers
    % asking for overlapping spans get the SAME panels rather than two grids
    % offset by an arbitrary fraction of a day.
    firstStart = floor(min(requestedMjd) / options.PanelSpan) * options.PanelSpan;
    lastStart = floor(max(requestedMjd) / options.PanelSpan) * options.PanelSpan;
    panelStartMjd = (firstStart:options.PanelSpan:lastStart)';
    panelCount = numel(panelStartMjd);

    % A PANEL CARRIES ONE TAI-UTC, SO A LEAP SECOND MAY FALL ON A PANEL BOUNDARY
    % AND NOWHERE ELSE (rev. 1.226, H.11 item 9). One-day panels always meet
    % that, because leap seconds start a UTC day. A longer PanelSpan can put
    % one strictly inside a panel, and that is refused here by name - until
    % this revision it surfaced as toleranceNotMet, with advice to raise Degree
    % that could not help.
    taiAtStart = localLeapSeconds(panelStartMjd);
    for k = 1:panelCount
        panelEnd = panelStartMjd(k) + options.PanelSpan;
        interiorDay = (floor(panelStartMjd(k)) + 1:ceil(panelEnd) - 1)';
        interiorDay = interiorDay(interiorDay > panelStartMjd(k) & interiorDay < panelEnd);
        if isempty(interiorDay)
            continue
        end
        changed = localLeapSeconds(interiorDay) ~= taiAtStart(k);
        if any(changed)
            error('referenceSystem:earthOrientationInterpolant:leapSecondInsidePanel', ...
                ['A leap second starts MJD %d, which lies inside panel %d ', ...
                '(MJD %g to %g). A panel carries one TAI-UTC and cannot straddle ', ...
                'a leap second. Choose a PanelSpan that puts a panel boundary on ', ...
                'that day; PanelSpan 1 always does.'], ...
                interiorDay(find(changed, 1)), k, panelStartMjd(k), panelEnd);
        end
    end

    % All nodes of all panels in one column, so the chain below is evaluated
    % once for the whole interpolant rather than once per panel. At a ten-day
    % span that is one call of 210 epochs instead of ten calls of 21.
    nodeCount = options.Degree + 1;
    nodeMjd = zeros(nodeCount, panelCount);
    for k = 1:panelCount
        nodeMjd(:, k) = mexGateway('chebnodes', panelStartMjd(k), ...
            options.PanelSpan, options.Degree);
    end
    [value, cipModel] = localEvaluateChain(nodeMjd(:), options.Eop, ...
        options.ApplyTidalCorrections);

    % THE LAST NODE OF A PANEL THAT ENDS IN A LEAP SECOND IS TAKEN AT 23:59:60,
    % AS THE LEFT LIMIT OF ITS OWN PANEL (rev. 1.226). Until this revision it
    % was taken at 0h of the next day, where the series has already stepped:
    % with the sub-daily terms, UT1-UTC read +0.591313 s at 2017-01-01 0h
    % against -0.408687 s one second before 23:59:60, so the panel fitted a
    % one-second step and the build failed at 3.58e5. At 23:59:60 the TT, the
    % CIP and the pole continue the panel smoothly, but interpolateEop reports
    % UT1-UTC in the NEW day's convention, so the step in TAI-UTC is taken back
    % out to continue the old one. The node is row 1 of its panel: rsChebNodes
    % puts u = cos(0) = 1, the panel's end, first.
    taiAtEnd = localLeapSeconds(panelStartMjd + options.PanelSpan);
    endsInLeap = find(taiAtEnd ~= taiAtStart);
    if ~isempty(endsInLeap)
        endRow = (endsInLeap - 1) * nodeCount + 1;
        leapDay = panelStartMjd(endsInLeap) + options.PanelSpan - 1;
        assert(all(nodeMjd(endRow) == leapDay + 1), ...
            'The end node of a panel is not the first node of its block.');
        leapValue = localEvaluateEpochs(referenceSystem.daySecondToEpoch( ...
            [leapDay, repmat(86400, numel(leapDay), 1)], "UTC"), ...
            options.Eop, options.ApplyTidalCorrections);
        isUt1 = localQuantityNames() == "dut1";
        leapValue(:, isUt1) = leapValue(:, isUt1) - ...
            (taiAtEnd(endsInLeap) - taiAtStart(endsInLeap));
        value(endRow, :) = leapValue;
    end

    % THE CHANNEL COUNT IS TAKEN FROM THE DATA, NOT WRITTEN DOWN A SECOND
    % TIME. P19c added a seventh channel by editing a literal 7 here and
    % missing an unrelated literal 6 in localResidual eighty lines below;
    % every interpolant test then failed on a size mismatch. A magic number
    % that appears twice will eventually appear twice with different values
    % (obligation O33). localQuantityNames is the single authority for what
    % the columns are, and everything else counts them.
    coefficient = zeros(nodeCount, size(value, 2), panelCount);
    for k = 1:panelCount
        rows = (k - 1) * nodeCount + (1:nodeCount);
        coefficient(:, :, k) = mexGateway('chebfit', value(rows, :));
    end

    interpolant = struct( ...
        'panelStartMjd', panelStartMjd, ...
        'panelSpan', options.PanelSpan, ...
        'degree', options.Degree, ...
        'quantity', localQuantityNames(), ...
        'taiMinusUtc', localLeapSeconds(panelStartMjd), ...
        'coefficient', coefficient, ...
        'meta', struct());

    residual = localResidual(interpolant, options.Eop, ...
        options.ApplyTidalCorrections);
    % THE LENGTH-OF-DAY CHANNEL IS FITTED BUT NOT GATED, AND THE REASON IS
    % DIMENSIONAL. Tolerance is stated in microarcseconds of ANGLE. Excess LOD
    % does not enter the angle at all - it enters the ERA RATE - so bounding
    % it in microarcseconds is a category error, not a strict or a lax choice.
    % Its residual is reported in meta.residual alongside the others so it is
    % visible, and the gate is applied to every other channel.
    %
    % DUT1 IS GATED AS THE ANGLE IT BECOMES (rev. 1.225, H.11 item 8). Its
    % residual is in microseconds, and until this revision it was compared
    % with the tolerance as if that number were microseconds too: at the
    % default 0.5, dut1 was held to 7.5 uas of rotation while the angles were
    % held to 0.5 - the category error the lod exclusion above avoids, made
    % in the other direction. A UT1 error of dt turns the Earth by
    % omega*dt, so the residual is scaled by the ERA rate (D63) into
    % microarcseconds, 15.04 uas per us, before the comparison. meta.residual
    % still reports microseconds.
    name = string(interpolant.quantity);
    constants = referenceSystem.iersConstants();
    asAngle = residual;
    isUt1 = name == "dut1";
    asAngle(isUt1) = residual(isUt1) * ...
        referenceSystem.earthRotationAngleRate() / constants.arcsecondsToRadians;
    gated = name ~= "lod";
    if any(asAngle(gated) > options.Tolerance)
        [worst, worstIndex] = max(asAngle .* gated);
        error('referenceSystem:earthOrientationInterpolant:toleranceNotMet', ...
            ['The fit reached %.4g uas of rotation in %s against a tolerance ', ...
            'of %.4g uas (dut1 counted at 15.04 uas per us). Raise Degree or ', ...
            'shorten PanelSpan; handover section B.9.2 tabulates what each ', ...
            'buys.'], worst, name(worstIndex), options.Tolerance);
    end

    versionInfo = referenceSystem.toolboxVersion();
    interpolant.meta = struct( ...
        'residual', residual, ...
        'tolerance', options.Tolerance, ...
        'cipModel', cipModel, ...
        'eopFile', options.Eop.meta.file, ...
        'spanMjd', [panelStartMjd(1), panelStartMjd(end) + options.PanelSpan], ...
        'tidalCorrections', options.ApplyTidalCorrections, ...
        'builtOn', versionInfo.generator);
end

function [value, cipModel] = localEvaluateChain(mjd, eop, applyTidal)
%LOCALEVALUATECHAIN The seven quantities at a column of UTC MJD.
%   One place, called by both the fit and the residual check, so that the
%   thing being fitted and the thing it is compared against cannot drift
%   apart. That is the whole reason this is a function and not two blocks -
%   and rev. 1.91 shows it is not enough on its own, because when this
%   function was wrong BOTH of them were wrong together and agreed.
%
%   THE SUB-DAILY CORRECTIONS ARE APPLIED HERE, and rev. 1.90 did not apply
%   them. Without them xp, yp and dut1 are a piecewise LINEAR interpolation of
%   daily table rows, which any degree above one reproduces exactly - so the
%   residual sat at the CIP's double-precision floor, degree 12 measured the
%   same as degree 20, and degree 4 passed a tolerance it should have failed
%   by orders of magnitude. The tests said so and the diagnosis was not that
%   the tests were badly chosen. It was that the interpolant did not contain
%   the physics that decides its own degree: section B.9.2 measured the
%   ocean tide and libration as the binding quantity, and this function was
%   omitting exactly those terms.

    utc = referenceSystem.daySecondToEpoch( ...
        [floor(mjd), (mjd - floor(mjd)) * 86400], "UTC");
    [value, cipModel] = localEvaluateEpochs(utc, eop, applyTidal);
end

function [value, cipModel] = localEvaluateEpochs(utc, eop, applyTidal)
%LOCALEVALUATEEPOCHS The seven quantities at a UTC epoch struct.
%   The body of localEvaluateChain, taking the epoch itself so that the one
%   instant an MJD cannot name - 23:59:60 of a leap-second day - can still be
%   evaluated by the same chain (rev. 1.226).

    if applyTidal
        correction = referenceSystem.subdailyEopCorrection(utc);
        eopAt = referenceSystem.interpolateEop(eop, utc, ...
            'Correction', correction);
    else
        eopAt = referenceSystem.interpolateEop(eop, utc);
    end
    tt = referenceSystem.convertTimeScale(utc, "TT");
    [X, Y, s] = referenceSystem.cipCoordinates(tt, 'Eop', eopAt);

    % SEVEN CHANNELS SINCE P19c, AND THE SEVENTH IS WHAT LETS THE ROTATION
    % STOP INTERPOLATING THE SERIES. The excess length of day is the only
    % quantity 'ApplyLengthOfDay' needs and the only reason the interpolated
    % path still called interpolateEop; fitting it here costs one more
    % Chebyshev expansion per panel and removes that call entirely.
    value = [X, Y, s, eopAt.xp, eopAt.yp, eopAt.dut1, eopAt.lod];
    assert(size(value, 2) == numel(localQuantityNames()), ...
        'localEvaluateChain and localQuantityNames disagree on the columns.');
    cipModel = eopAt.meta.cipModel;
end

function residual = localResidual(interpolant, eop, applyTidal)
%LOCALRESIDUAL Worst error at samples the fit has not seen, per quantity.
%   The midpoints between nodes, where a Chebyshev fit is at its weakest.
%   Evaluating at the nodes themselves would return the node values to
%   roundoff for any degree and report a residual of zero, which is a worse
%   answer than reporting none.
%
%   Units: microarcseconds for the five angles, microseconds for dut1. The
%   two are not mixed in one number because a tolerance that meant different
%   things in different columns would be a tolerance nobody could reason about.

    nodeCount = interpolant.degree + 1;
    panelCount = numel(interpolant.panelStartMjd);

    sampleMjd = zeros(nodeCount - 1, panelCount);
    fitted = zeros((nodeCount - 1) * panelCount, ...
        size(interpolant.coefficient, 2));
    for k = 1:panelCount
        node = mexGateway('chebnodes', interpolant.panelStartMjd(k), ...
            interpolant.panelSpan, interpolant.degree);
        midpoint = 0.5 * (node(1:end-1) + node(2:end));
        sampleMjd(:, k) = midpoint;
        rows = (k - 1) * (nodeCount - 1) + (1:nodeCount - 1);
        fitted(rows, :) = mexGateway('chebeval', ...
            interpolant.coefficient(:, :, k), interpolant.panelStartMjd(k), ...
            interpolant.panelSpan, midpoint);
    end

    truth = localEvaluateChain(sampleMjd(:), eop, applyTidal);
    difference = abs(fitted - truth);

    % Radians to microarcseconds for the angles; seconds to microseconds for
    % dut1. The conversion is spelled out rather than taken from
    % iersConstants.arcsecondsToRadians inverted, because inverting a constant
    % named for the other direction is how a factor of pi goes missing.
    % THE SCALE IS BUILT FROM THE QUANTITY NAMES, so a channel added without
    % a matching entry here is a named error rather than a silent mis-scaling
    % by 2e11. dut1 and lod are both seconds; the other five are angles.
    name = string(interpolant.quantity);
    radiansToMicroarcseconds = 648000 / pi * 1e6;
    scale = repmat(radiansToMicroarcseconds, 1, numel(name));
    scale(ismember(name, ["dut1", "lod"])) = 1e6;
    residual = max(difference, [], 1) .* scale;
end

function name = localQuantityNames()
%LOCALQUANTITYNAMES The fitted channels, in column order. THE ONE AUTHORITY.
%   Everything else counts these or looks them up by name: the coefficient
%   array is sized from the data, the residual scale is built from the names,
%   and the tolerance gate selects the angular ones by name. Adding a channel
%   means editing this list and localEvaluateChain, and an assertion there
%   refuses the two to disagree.

    name = ["X", "Y", "s", "xp", "yp", "dut1", "lod"];
end

function taiMinusUtc = localLeapSeconds(panelStartMjd)
%LOCALLEAPSECONDS TAI minus UTC at the start of each panel, in seconds.
%   Obtained by converting and differencing rather than by reading the leap
%   second table directly, so that this function and every other consumer of
%   TAI in the toolbox agree by construction about what the offset is.

    utc = referenceSystem.daySecondToEpoch( ...
        [panelStartMjd, zeros(numel(panelStartMjd), 1)], "UTC");
    tai = referenceSystem.convertTimeScale(utc, "TAI");
    taiMinusUtc = (tai.day - utc.day) * 86400 + (tai.sec - utc.sec);
end
