function cartesian = applyHelmert7(cartesian, parameters, options)
%APPLYHELMERT7 Seven-parameter similarity transformation, exact in both directions.
%
%   cartesian = applyHelmert7(cartesian, parameters, 'Convention', c, ...
%   'Units', u) applies the seven-parameter (Bursa-Wolf) transformation to the
%   Nx3 earth-fixed positions. The convention and the units are both required:
%   neither can be guessed and both change the answer.
%
%   cartesian = applyHelmert7(..., 'Inverse', true) applies the exact inverse.
%
% INPUT ARGUMENTS
%   Name          Size   Type     Units      Description
%   ----          ----   ----     -----      -----------
%   cartesian     Nx3    double   m          Positions, one point per ROW.
%   parameters    1x1    struct   see Units  Transformation parameters.
%   .translation  1x3    double   see Units  Tx, Ty, Tz.
%   .rotation     1x3    double   see Units  Rx, Ry, Rz.
%   .scale        1x1    double   see Units  Scale correction.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type      Default    Description
%   ----         ----   ----      -------    -----------
%   Convention   1x1    string    REQUIRED   "positionVector" or
%                                            "coordinateFrame".
%   Units        1x1    string    REQUIRED   "si" (m, rad, 1), "itrf"
%                                            (mm, mas, ppb) or "datum"
%                                            (m, arcsec, ppm).
%   Inverse      1x1    logical   false      Solve the transformation instead of
%                                            applying it.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   cartesian   Nx3    double   m      Transformed positions.
%
% METHOD
%       XS = T + (1 + s)*R*X
%
%   with R the linearised small-angle rotation matrix. The two conventions
%   differ in the sign of every rotation:
%
%       positionVector    R = [  1  -rz   ry ;  rz   1  -rx ; -ry  rx   1 ]
%       coordinateFrame   R = [  1   rz  -ry ; -rz   1   rx ;  ry -rx   1 ]
%
%   THE CONVENTION HAS NO DEFAULT, and that is the point of the argument. Both
%   are in daily use - EPSG, IERS and the IGN ITRF tables publish position
%   vector, while several national and legacy datum sets publish coordinate
%   frame - and choosing the wrong one is a pure sign error on the rotations
%   that leaves the result looking entirely plausible. For the ITRF93
%   parameters, the only ITRF entry with arcsecond-level rotations, the two
%   conventions differ by about 0.27 m at the surface. A default here would be a
%   silent 50 percent chance of that error, so there is none.
%
%   THE UNITS HAVE NO DEFAULT EITHER, for the same reason at a larger scale:
%   the same seven numbers mean a millimetre-level or a metre-level shift
%   depending on the publication, and mistaking mas for arcsec is a factor of
%   1000 on the rotations.
%
%   THE INVERSE IS SOLVED EXACTLY, X = R'*(XS - T)/(1 + s), and NOT by negating
%   the seven parameters (finding M-10). v1 carried two Helmert implementations
%   that disagreed on this: one negated, one solved. Negation is a linearisation
%   of the inverse and its error grows with the rotations and the scale. Measured
%   on a 6.4e6 m position:
%
%       parameters                     exact solve   parameter negation
%       ITRF-scale (0 as, 0.4 ppb)     0.0e+00 m     1.2e-10 m
%       modern datum (0.03 as, 1 ppm)  4.7e-10 m     5.0e-06 m
%       legacy datum (3 as, 5 ppm)     0.0e+00 m     9.9e-04 m
%       extreme (100 as, 20 ppm)       9.3e-10 m     1.4e+00 m
%
%   So negation is sub-millimetre for modern parameters and wrong at the
%   millimetre level for exactly the legacy datums it is traditionally used for.
%   The exact solve costs one 3x3 factorisation for the whole array.
%
%   THE SMALL-ANGLE FORM IS GUARDED. R is linearised, so it is a rotation only
%   to first order in the angles; at 100 arcseconds the departure from
%   orthogonality is 1.2e-7 relative, which is 0.8 m at the Earth's surface.
%   Above that the function errors rather than silently applying a matrix that
%   is not a rotation. Use a rigorous rotation from L4b if genuinely large
%   angles are meant.
%
%   All N points share one matrix, so the whole array costs one matrix product;
%   v1 reshaped three separate X, Y and Z arrays with no check that they had the
%   same shape (finding m-4), which this signature makes impossible.
%
% ACCURACY
%   Exact to machine precision given the parameters. Agreement with an
%   independent PROJ 9.5.1 helmert pipeline, both conventions, on a 6.4e6 m
%   position: 0.0e+00 m, bit for bit. The forward-inverse round trip closes to
%   4.7e-10 m for arcsecond-level rotations.
%
%   The linearisation itself is an approximation of the published rotation
%   matrix and not of this code: published parameter sets are DERIVED under the
%   linearised model, so applying them with a rigorous rotation matrix would be
%   less accurate, not more. That is why the guard is at 100 arcseconds rather
%   than a switch to a rigorous form.
%
% ERRORS
%   referenceSystem:applyHelmert7:wrongPointSize
%   referenceSystem:applyHelmert7:conventionRequired
%   referenceSystem:applyHelmert7:unitsRequired
%   referenceSystem:applyHelmert7:missingParameter
%   referenceSystem:applyHelmert7:rotationTooLarge
%
% REFERENCES
%   IOGP Publication 373-7-2, Geomatics Guidance Note 7 part 2, Coordinate
%   Conversions and Transformations including Formulas, Sect. 4.3.3.
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 4.
%
% EXAMPLE
%   p = struct('translation', [0.06155 -0.01087 -0.04019], ...
%       'rotation', [-0.0394924 -0.0327221 -0.0328979], 'scale', -0.009994);
%   x = referenceSystem.applyHelmert7(x, p, 'Convention', "positionVector", ...
%       'Units', "datum");
%
% KEYWORDS
%   Helmert, Bursa-Wolf, seven parameter, similarity, datum, position vector,
%   coordinate frame, ITRF, transformation
%
% See also CONVERTITRF, ITRFPARAMETERS, APPLYMOLODENSKY.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 06:20 (CEST, UTC+02:00) - session S4, prompt P11
% -------------------------------------------------------------------------

%#codegen

    arguments
        cartesian double {mustBeReal, mustBeFinite}
        parameters (1,1) struct
        options.Convention (1,1) string {mustBeMember(options.Convention, ...
            ["positionVector", "coordinateFrame", ""])} = ""
        options.Units (1,1) string {mustBeMember(options.Units, ...
            ["si", "itrf", "datum", ""])} = ""
        options.Inverse (1,1) logical = false
    end

    if ~ismatrix(cartesian) || (size(cartesian, 2) ~= 3 && ~isempty(cartesian))
        error('referenceSystem:applyHelmert7:wrongPointSize', ...
            'cartesian must be Nx3, one point per row; it is %s.', ...
            mat2str(size(cartesian)));
    end
    if strcmp(options.Convention, "")
        error('referenceSystem:applyHelmert7:conventionRequired', ...
            ['Convention must be named: "positionVector" (EPSG, IERS and the ', ...
            'IGN ITRF tables) or "coordinateFrame" (several national and ', ...
            'legacy sets). The two differ by the sign of all three rotations ', ...
            'and there is no default, because the wrong one is invisible in ', ...
            'the result.']);
    end
    if strcmp(options.Units, "")
        error('referenceSystem:applyHelmert7:unitsRequired', ...
            ['Units must be named: "si" (m, rad, 1), "itrf" (mm, mas, ppb) ', ...
            'or "datum" (m, arcsec, ppm). The same seven numbers mean ', ...
            'different transformations in each.']);
    end
    % Unrolled rather than looped over a string array, so that the check
    % survives code generation, where iterating a string array does not.
    requireField(parameters, "translation");
    requireField(parameters, "rotation");
    requireField(parameters, "scale");

    [translation, rotation, scale] = toSiUnits(parameters, options.Units);

    arcsecond = pi/180/3600;
    if any(abs(rotation) > 100*arcsecond)
        error('referenceSystem:applyHelmert7:rotationTooLarge', ...
            ['Rotation %.4g arcseconds exceeds the 100 arcsecond limit of ', ...
            'the linearised form, where the matrix departs from orthogonality ', ...
            'by more than 1.2e-7 relative, that is 0.8 m at the surface. Use ', ...
            'a rigorous rotation instead.'], max(abs(rotation))/arcsecond);
    end

    R = [1, -rotation(3), rotation(2); ...
        rotation(3), 1, -rotation(1); ...
        -rotation(2), rotation(1), 1];
    if strcmp(options.Convention, "coordinateFrame")
        R = R.';
    end
    M = (1 + scale)*R;

    if options.Inverse
        cartesian = (cartesian - translation)/M.';
    else
        cartesian = translation + cartesian*M.';
    end
end

% -------------------------------------------------------------------------

function requireField(parameters, name)
%REQUIREFIELD Refuse a parameter set that omits one of the three groups.

    if ~isfield(parameters, name)
        error('referenceSystem:applyHelmert7:missingParameter', ...
            'parameters has no field "%s".', name);
    end
end

function [translation, rotation, scale] = toSiUnits(parameters, units)
%TOSIUNITS Convert one published parameter set to metres, radians and unity.

    if strcmp(units, "si")
        translationScale = 1;
        rotationScale = 1;
        scaleScale = 1;
    elseif strcmp(units, "itrf")
        translationScale = 1e-3;
        rotationScale = pi/180/3600*1e-3;
        scaleScale = 1e-9;
    else
        translationScale = 1;
        rotationScale = pi/180/3600;
        scaleScale = 1e-6;
    end

    translation = reshape(double(parameters.translation), 1, 3)*translationScale;
    rotation = reshape(double(parameters.rotation), 1, 3)*rotationScale;
    scale = double(parameters.scale)*scaleScale;
end
