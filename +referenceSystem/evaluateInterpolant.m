function value = evaluateInterpolant(interpolant, mjd, panelIndex)
%EVALUATEINTERPOLANT Evaluate one panel of an Earth orientation interpolant.
%   value = evaluateInterpolant(interpolant, mjd, panelIndex) returns the
%   fitted quantities at the given UTC MJD, one column per entry of
%   interpolant.quantity, read from the panel at panelIndex.
%
%   This is the low-level reader. rotationItrsToGcrs selects the panel and
%   assembles the rotation itself when given 'Interpolant'; this function is
%   how the panels are reached directly, and it is what the C API exposes.
%
% INPUT ARGUMENTS
%   Name          Size   Type     Units  Description
%   ----          ----   ----     -----  -----------
%   interpolant   1x1    struct   -      Output of earthOrientationInterpolant.
%   mjd           Nx1    double   d      UTC Modified Julian Dates, all inside
%                                        the named panel.
%   panelIndex    1x1    double   -      Index into interpolant.panelStartMjd.
%
% OUTPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   value   NxQ    double   mixed  One column per entry of interpolant.quantity,
%                                  Q = numel(interpolant.quantity), in that
%                                  order. Units by name: radians for X, Y, s,
%                                  xp and yp; seconds for dut1; seconds per day
%                                  for lod.
%
% METHOD
%   Clenshaw evaluation in mex/rsCheb.c, reached through the gateway, so this
%   function and the public C API share one evaluator rather than agreeing by
%   inspection. The panel is not searched for here: the caller names it,
%   because in an integrator hot loop the panel changes once per day and
%   searching for it at every step would cost more than the evaluation.
%
% ACCURACY
%   Exact to roundoff against the coefficients it is given. The accuracy of
%   those coefficients against the direct chain is earthOrientationInterpolant's
%   claim and is recorded in interpolant.meta.residual.
%
% ERRORS
%   referenceSystem:evaluateInterpolant:badPanel
%   referenceSystem:mex:outOfPanel
%
% REFERENCES
%   Handover sections B.9.1 and B.9.2, decision D82.
%
% EXAMPLE
%   eop = referenceSystem.readEop('eop20c04.txt');
%   span = referenceSystem.daySecondToEpoch([57754 0; 57755 0], "UTC");
%   ip = referenceSystem.earthOrientationInterpolant(span, 'Eop', eop);
%   value = referenceSystem.evaluateInterpolant(ip, 57754.5, 1);
%
% KEYWORDS
%   Chebyshev, evaluation, Earth orientation, interpolation
%
% See also earthOrientationInterpolant, rotationItrsToGcrs
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 10:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        interpolant (1,1) struct
        mjd (:,1) double {mustBeFinite}
        panelIndex (1,1) double {mustBeInteger, mustBePositive}
    end

    if panelIndex > numel(interpolant.panelStartMjd)
        error('referenceSystem:evaluateInterpolant:badPanel', ...
            ['Panel %d was asked for and the interpolant holds %d. The ', ...
            'panel is named by the caller rather than searched for, so an ', ...
            'index past the end is a caller error and not an extrapolation.'], ...
            panelIndex, numel(interpolant.panelStartMjd));
    end

    value = mexGateway('chebeval', interpolant.coefficient(:, :, panelIndex), ...
        interpolant.panelStartMjd(panelIndex), interpolant.panelSpan, mjd);
end
