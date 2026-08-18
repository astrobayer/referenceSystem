function ellipsoidalHeight = orthometricToEllipsoidal(orthometricHeight, ...
        undulation)
%ORTHOMETRICTOELLIPSOIDAL Orthometric height to ellipsoidal height.
%
%   ellipsoidalHeight = orthometricToEllipsoidal(orthometricHeight,
%   undulation) computes h = H + N elementwise.
%
% INPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   orthometricHeight   any    double   m      H, height above the geoid.
%   undulation     any    double   m      N, height of the geoid above the
%                                              ellipsoid, positive where the
%                                              geoid is above it. Same size as H,
%                                              or scalar.
%
% OUTPUT ARGUMENTS
%   Name                Size   Type     Units  Description
%   ----                ----   ----     -----  -----------
%   ellipsoidalHeight   any    double   m      h, height above the ellipsoid.
%
% METHOD
%   h = H + N, the exact inverse of ellipsoidalToOrthometric. Two named
%   functions rather than one with a direction flag: the direction belongs in
%   the name (section C.7 rule 2), and a sign flag on a one-line function is
%   pure risk with no benefit. Revision 1.0 of the design merged the pair into a
%   single heightConvert with a direction argument; decision D6 reversed that.
%
%   THE ARGUMENT IS NAMED undulation AND NOT geoidUndulation, which reads worse
%   and is nevertheless right: geoidUndulation is a sibling function in this
%   namespace, and a local variable of that name is indistinguishable, to a
%   reader and to the static namespace scan alike, from an unqualified call to
%   it. The S4 run flagged exactly that. This is decision D54's rule - the one
%   that renamed leapSeconds - applied to a variable rather than to a function.
%
%   The sign convention for N is the IAG one, positive where the geoid lies
%   above the ellipsoid, which is what every published geoid model supplies.
%   Sizes are checked so that a column of heights and a row of undulations
%   cannot expand implicitly into a matrix of every combination.
%
% ACCURACY
%   Exact: one addition, error at most half an ulp, below 1e-12 m for any
%   terrestrial height.
%
%   The accuracy of h is that of N. EGM2008 is quoted at about 0.1 m globally
%   and better than 0.05 m over well surveyed regions; a regional quasigeoid
%   reaches 0.01 m. Interpolating a grid adds the error stated in
%   geoidUndulation.
%
% ERRORS
%   referenceSystem:orthometricToEllipsoidal:sizeMismatch
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 3.4.
%   N. K. Pavlis et al. (2012), The development and evaluation of EGM2008,
%   Journal of Geophysical Research 117, B04406.
%
% EXAMPLE
%   N = referenceSystem.geoidUndulation(latLon, geoidGrid);
%   h = referenceSystem.orthometricToEllipsoidal(H, N);
%
% KEYWORDS
%   ellipsoidal height, orthometric height, geoid undulation, levelling, EGM2008
%
% See also ELLIPSOIDALTOORTHOMETRIC, GEOIDUNDULATION, GEODETICTOCARTESIAN.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 07:28 (CEST, UTC+02:00) - session S4, prompt P13
% -------------------------------------------------------------------------

%#codegen

    arguments
        orthometricHeight double {mustBeReal}
        undulation double {mustBeReal}
    end

    if ~isequal(size(orthometricHeight), size(undulation)) && ...
            ~isscalar(orthometricHeight) && ~isscalar(undulation)
        error('referenceSystem:orthometricToEllipsoidal:sizeMismatch', ...
            ['orthometricHeight is %s and undulation is %s. They must ', ...
            'match or one must be scalar; implicit expansion of a column ', ...
            'against a row would silently build every combination.'], ...
            mat2str(size(orthometricHeight)), mat2str(size(undulation)));
    end

    ellipsoidalHeight = orthometricHeight + undulation;
end
