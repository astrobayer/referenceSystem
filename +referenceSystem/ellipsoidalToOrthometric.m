function orthometricHeight = ellipsoidalToOrthometric(ellipsoidalHeight, ...
        undulation)
%ELLIPSOIDALTOORTHOMETRIC Ellipsoidal height to orthometric height.
%
%   orthometricHeight = ellipsoidalToOrthometric(ellipsoidalHeight,
%   undulation) computes H = h - N elementwise.
%
% INPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   ellipsoidalHeight   any    double   m      h, height above the ellipsoid.
%   undulation     any    double   m      N, height of the geoid above the
%                                              ellipsoid, positive where the
%                                              geoid is above it. Same size as h,
%                                              or scalar.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   orthometricHeight   any    double   m      H, height above the geoid.
%
% METHOD
%   H = h - N. One line, and the value of the function is not the arithmetic but
%   the three things around it: the name states the direction, so no flag can be
%   set the wrong way; the sign of N is documented, positive where the geoid is
%   above the ellipsoid, which is the IAG convention and the one every published
%   geoid model uses; and the sizes are checked, so a column of heights and a
%   row of undulations cannot expand implicitly into a matrix of every
%   combination.
%
%   THE ARGUMENT IS NAMED undulation AND NOT geoidUndulation, which reads worse
%   and is nevertheless right: geoidUndulation is a sibling function in this
%   namespace, and a local variable of that name is indistinguishable, to a
%   reader and to the static namespace scan alike, from an unqualified call to
%   it. The S4 run flagged exactly that. This is decision D54's rule - the one
%   that renamed leapSeconds - applied to a variable rather than to a function.
%
%   That last one is a real hazard rather than a hypothetical: MATLAB's implicit
%   expansion turns a 1000x1 and a 1x1000 into a 1000x1000 array without a word,
%   and the result is plausible until it is plotted.
%
%   The relation is a definition and not an approximation, but H is only as good
%   as N. The two heights refer to different surfaces and to different physics -
%   h is geometric, H is a levelled height along the plumb line - so the
%   difference is the geoid model's error, not a rounding.
%
% ACCURACY
%   Exact: one subtraction, error at most half an ulp, below 1e-12 m for any
%   terrestrial height.
%
%   The accuracy of H is that of N. EGM2008 is quoted at about 0.1 m globally
%   and better than 0.05 m over well surveyed regions; a regional quasigeoid
%   such as GCG2016 reaches 0.01 m. Interpolating a grid adds the error stated
%   in geoidUndulation. Nothing here can improve on that, and the millimetre
%   claims made elsewhere in this toolbox do not extend to orthometric heights.
%
% ERRORS
%   referenceSystem:ellipsoidalToOrthometric:sizeMismatch
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 3.4.
%   N. K. Pavlis et al. (2012), The development and evaluation of EGM2008,
%   Journal of Geophysical Research 117, B04406.
%
% EXAMPLE
%   N = referenceSystem.geoidUndulation(latLon, grid);
%   H = referenceSystem.ellipsoidalToOrthometric(h, N);
%
% KEYWORDS
%   orthometric height, ellipsoidal height, geoid undulation, levelling, EGM2008
%
% See also ORTHOMETRICTOELLIPSOIDAL, GEOIDUNDULATION, CARTESIANTOGEODETIC.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 07:25 (CEST, UTC+02:00) - session S4, prompt P13
% -------------------------------------------------------------------------

%#codegen

    arguments
        ellipsoidalHeight double {mustBeReal}
        undulation double {mustBeReal}
    end

    if ~isequal(size(ellipsoidalHeight), size(undulation)) && ...
            ~isscalar(ellipsoidalHeight) && ~isscalar(undulation)
        error('referenceSystem:ellipsoidalToOrthometric:sizeMismatch', ...
            ['ellipsoidalHeight is %s and undulation is %s. They must ', ...
            'match or one must be scalar; implicit expansion of a column ', ...
            'against a row would silently build every combination.'], ...
            mat2str(size(ellipsoidalHeight)), mat2str(size(undulation)));
    end

    orthometricHeight = ellipsoidalHeight - undulation;
end
