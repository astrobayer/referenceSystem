function [partialXp, partialYp, partialDeltaUt1, info] = ...
        earthOrientationPartials(epoch, options)
%EARTHORIENTATIONPARTIALS Partials of the ITRS to GCRS rotation in the EOP.
%   [dXp, dYp, dUt1] = earthOrientationPartials(epoch, 'Eop', eop) returns the
%   partial derivatives of the terrestrial-to-celestial rotation with respect to
%   the two pole coordinates and to UT1 minus UTC.
%
%   These are the columns a least-squares adjustment needs when the Earth
%   orientation parameters are estimated rather than held fixed - in precise
%   orbit determination, in terrestrial frame realisation, and wherever an
%   observation residual has to be differentiated with respect to the pole.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, any scale.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name          Size   Type     Default  Description
%   ----          ----   ----     -------  -----------
%   Eop           1x1    struct   none     Series from readEop, as
%                                          rotationItrsToGcrs takes it.
%   Interpolant   1x1    struct   []       Panels from
%                                          earthOrientationInterpolant.
%   Rotation      3x3xN   double  []       A rotation already computed for
%                                          these epochs. Supply it and the
%                                          chain is not evaluated again; the
%                                          partials are three matrix products.
%
% OUTPUT ARGUMENTS
%   Name              Size     Type     Units    Description
%   ----              ----     ----     -----    -----------
%   partialXp         3x3xN    double   1/rad    dR/dxp.
%   partialYp         3x3xN    double   1/rad    dR/dyp.
%   partialDeltaUt1   3x3xN    double   1/s      dR/d(UT1-UTC).
%   info              1x1      struct   -        .generatorAxis, the three
%                                                terrestrial axes used, as a
%                                                3x3 whose columns correspond
%                                                to the three outputs; and
%                                                .rotationSupplied, whether the
%                                                caller provided R.
%
% METHOD
%   Every one of the three has the same shape:
%
%       dR/dp = R * skew(a_p)
%
%   with a_p a CONSTANT axis in the terrestrial frame. That is not an
%   approximation of convenience; it follows from each parameter entering the
%   product W*R3(theta)*Q through exactly one factor, and from the identity
%   skew(R*v) = R*skew(v)*R'. The axes are
%
%       xp        a = ( 0, -1,  0)
%       yp        a = (-1,  0,  0)
%       UT1-UTC   a = ( 0,  0,  omega)      omega from earthRotationAngleRate
%
%   xp ROTATES ABOUT MINUS Y AND yp ABOUT MINUS X, not the other way round.
%   iauPom00 builds W as R3(-s')*R2(xp)*R1(yp), so xp enters through the
%   SECOND-axis factor and yp through the first. The natural reading of "the x
%   pole coordinate" is a rotation about x, and it is wrong; the
%   finite-difference test holds the assignment.
%
%   THE SIGNS WERE MEASURED, NOT DERIVED FROM THE FACTOR ORDER OF iauPom00.
%   The generators were finite-differenced against rsRotationItrsToGcrs
%   itself, so the code being
%   differentiated is the authority for its own derivative. Differentiating a
%   remembered factor order is the one place in this function where a sign error
%   is likely, and a sign error in a partial does not announce itself - it slows
%   a least-squares convergence or biases an estimate, and it looks like a
%   modelling problem rather than a defect. The measurement also produced a free
%   check: all three generators came out SKEW-SYMMETRIC, which the generator of
%   a rotation must be and which a finite difference has no way to satisfy by
%   accident.
%
% ACCURACY
%   The constant-axis form neglects terms of order xp, yp and s', which are
%   below 1e-6 radians, so the partials are exact to about one part in 1e6 of
%   themselves. That is six orders better than any use a partial is put to: a
%   normal matrix built from these is limited by the observation model, never by
%   this. The exact form would carry the CIP unit vector and the pole through
%   each generator; it is not used because it would cost a second evaluation of
%   the chain to buy accuracy nothing needs.
%
%   The partials are exact derivatives of the DIRECT path. If an interpolant is
%   supplied, they are the derivatives of the interpolated rotation, which
%   differs from the direct one by the fit residual in interpolant.meta.
%
% ERRORS
%   referenceSystem:earthOrientationPartials:sizeMismatch
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, chapter 5.
%   Handover section H.10 (P20) for the measured generators.
%
% EXAMPLE
%   eop = referenceSystem.readEop('eop20c04.txt');
%   utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");
%   [dXp, dYp, dUt1] = referenceSystem.earthOrientationPartials(utc, 'Eop', eop);
%
% KEYWORDS
%   partial derivative, Earth orientation, polar motion, UT1, least squares,
%   precise orbit determination
%
% See also rotationItrsToGcrs, rotationItrsToGcrsPartials,
%   earthRotationAngleRate, interpolateEop
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 20:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Eop struct = struct([])
        options.Interpolant = []
        options.Rotation double = []
    end

    if isempty(options.Rotation)
        forwarded = {};
        if ~isempty(options.Eop)
            forwarded = [forwarded, {'Eop', options.Eop}];
        end
        if ~isempty(options.Interpolant)
            forwarded = [forwarded, {'Interpolant', options.Interpolant}];
        end
        rotation = referenceSystem.rotationItrsToGcrs(epoch, forwarded{:});
        rotationSupplied = false;
    else
        % A caller in an estimation loop already has R and should not pay for
        % it twice; the partials are then three matrix products. The size is
        % checked against the epoch rather than trusted, because a rotation
        % from a different arc would give partials that are individually
        % well-formed and collectively meaningless.
        epochCount = numel(epoch.day);
        % size() of a 3-by-3-by-1 returns [3 3], because MATLAB drops trailing
        % singleton dimensions - so isequal against [3 3 1] failed for every
        % single-epoch call. size(x,3) returns 1 for a 3-by-3, which is the
        % right question to ask.
        if size(options.Rotation, 1) ~= 3 || size(options.Rotation, 2) ~= 3 ...
                || size(options.Rotation, 3) ~= epochCount
            error('referenceSystem:earthOrientationPartials:sizeMismatch', ...
                ['The supplied rotation is %s and the epoch has %d entries, ', ...
                'so it must be 3-by-3-by-%d.'], ...
                mat2str([size(options.Rotation, 1), size(options.Rotation, 2), ...
                size(options.Rotation, 3)]), epochCount, epochCount);
        end
        rotation = options.Rotation;
        rotationSupplied = true;
    end

    omega = referenceSystem.earthRotationAngleRate();

    % Columns are the three outputs, in the order they are returned. One place,
    % so the help text, the info struct and the arithmetic cannot disagree
    % about which axis belongs to which parameter.
    generatorAxis = [0, -1, 0; -1, 0, 0; 0, 0, omega]';

    partialXp = localApplyGenerator(rotation, generatorAxis(:, 1));
    partialYp = localApplyGenerator(rotation, generatorAxis(:, 2));
    partialDeltaUt1 = localApplyGenerator(rotation, generatorAxis(:, 3));

    if nargout >= 4
        info = struct('generatorAxis', generatorAxis, ...
            'rotationSupplied', rotationSupplied);
    end
end

function product = localApplyGenerator(rotation, axis)
%LOCALAPPLYGENERATOR R * skew(axis), page by page.
%   pagemtimes rather than a loop: the generator is one 3-by-3 and broadcasts
%   across every page, so an arc of 86400 epochs is one call.

    skew = [0, -axis(3), axis(2); ...
            axis(3), 0, -axis(1); ...
            -axis(2), axis(1), 0];
    product = pagemtimes(rotation, skew);
end
