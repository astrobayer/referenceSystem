function cartesian = enuToCartesian(enu, origin, options)
%ENUTOCARTESIAN Local East-North-Up to earth-fixed Cartesian coordinates.
%
%   cartesian = enuToCartesian(enu, origin) converts the Nx3 local East-North-Up
%   coordinates about the origin to the Nx3 earth-fixed coordinates.
%
%   cartesian = enuToCartesian(enu, origin, 'OriginFormat', "cartesian")
%
% INPUT ARGUMENTS
%   Name     Size          Type     Units      Description
%   ----     ----          ----     -----      -----------
%   enu      Nx3           double   m          East, North, Up, one point per ROW.
%   origin   1x3 or Nx3    double   see below  The local frame origin, given ONCE,
%                                              in the format named by
%                                              'OriginFormat'.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name           Size   Type            Default      Description
%   ----           ----   ----            -------      -----------
%   OriginFormat   1x1    string          "geodetic"   "geodetic" or "cartesian".
%   Ellipsoid      1x1    string|struct   "GRS80"      Name or struct.
%   AngleUnit      1x1    string          "rad"        Unit of the geodetic
%                                                      origin angles.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   cartesian   Nx3    double   m      One point per row: X, Y, Z.
%
% METHOD
%   x = x0 + R'*enu, the exact inverse of cartesianToEnu: R is orthogonal, so
%   its transpose is its inverse and nothing is solved. The origin is supplied
%   once and in a named format, for the reasons given in cartesianToEnu; the
%   two functions share that argument handling so that a round trip cannot use
%   two different origins.
%
%   The earth-fixed frame is the ITRS, commonly called ECEF; the inertial GCRS,
%   commonly called ECI, is not involved.
%
% ACCURACY
%   Exact to machine precision. Round trip through cartesianToEnu reproduces the
%   local vector to 3.7e-10 m at 100 km and 1.9e-09 m at 10000 km, limited by
%   the Cartesian differencing rather than by the rotation.
%
% ERRORS
%   referenceSystem:enuToCartesian:wrongPointSize
%   referenceSystem:enuToCartesian:wrongOriginSize
%   referenceSystem:enuToCartesian:originCountMismatch
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 4.1.
%
% EXAMPLE
%   xyz = referenceSystem.enuToCartesian(enu, [49.145 12.878 665], ...
%       'AngleUnit', "deg");
%
% KEYWORDS
%   ENU, East North Up, topocentric, local level, ECEF, ITRS, GCRS
%
% See also CARTESIANTOENU, ROTATIONECEFTOENU, AZIMUTHELEVATIONTOENU.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:10 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        enu double {mustBeReal, mustBeFinite}
        origin double {mustBeReal, mustBeFinite}
        options.OriginFormat (1,1) string {mustBeMember( ...
            options.OriginFormat, ["geodetic", "cartesian"])} = "geodetic"
        options.Ellipsoid = "GRS80"
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(enu) || (size(enu, 2) ~= 3 && ~isempty(enu))
        error('referenceSystem:enuToCartesian:wrongPointSize', ...
            'enu must be Nx3, one point per row; it is %s.', mat2str(size(enu)));
    end
    if ~ismatrix(origin) || size(origin, 2) ~= 3
        error('referenceSystem:enuToCartesian:wrongOriginSize', ...
            'origin must be 1x3 or Nx3; it is %s.', mat2str(size(origin)));
    end
    nPoint = size(enu, 1);
    nOrigin = size(origin, 1);
    if nOrigin ~= 1 && nOrigin ~= nPoint
        error('referenceSystem:enuToCartesian:originCountMismatch', ...
            '%d origins for %d points: supply one origin or one per point.', ...
            nOrigin, nPoint);
    end

    if strcmp(options.OriginFormat, "geodetic")
        originGeodetic = origin;
        originCartesian = referenceSystem.geodeticToCartesian(origin, ...
            'Ellipsoid', options.Ellipsoid, 'AngleUnit', options.AngleUnit);
        angleUnit = options.AngleUnit;
    else
        originCartesian = origin;
        originGeodetic = referenceSystem.cartesianToGeodetic(origin, ...
            'Ellipsoid', options.Ellipsoid);
        angleUnit = "rad";
    end

    R = referenceSystem.rotationEcefToEnu(originGeodetic, ...
        'AngleUnit', angleUnit);

    if nOrigin == 1
        cartesian = originCartesian + enu*R;
    else
        rotated = pagemtimes(pagetranspose(R), reshape(enu.', 3, 1, nPoint));
        cartesian = originCartesian + reshape(rotated, 3, nPoint).';
    end
end
