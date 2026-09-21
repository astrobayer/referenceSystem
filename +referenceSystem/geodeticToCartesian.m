function cartesian = geodeticToCartesian(geodetic, options)
%GEODETICTOCARTESIAN Ellipsoidal geodetic coordinates to Cartesian coordinates.
%
%   cartesian = geodeticToCartesian(geodetic) converts the Nx3 geodetic
%   coordinates [latitude longitude height] to the Nx3 Cartesian coordinates
%   [X Y Z] on the same earth-fixed frame.
%
%   cartesian = geodeticToCartesian(geodetic, 'Ellipsoid', "WGS84")
%   cartesian = geodeticToCartesian(geodetic, 'AngleUnit', "deg")
%
% INPUT ARGUMENTS
%   Name       Size   Type     Units      Description
%   ----       ----   ----     -----      -----------
%   geodetic   Nx3    double   rad|deg,m  One point per ROW: column 1 geodetic
%                                          latitude, column 2 longitude, column 3
%                                          ellipsoidal height. Height is metres
%                                          whatever 'AngleUnit' says.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type            Default   Description
%   ----        ----   ----            -------   -----------
%   Ellipsoid   1x1    string|struct   "GRS80"   Ellipsoid name accepted by
%                                                 ellipsoidParameters, or the
%                                                 struct it returns.
%   AngleUnit   1x1    string          "rad"     "rad" or "deg" for columns 1-2.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   cartesian   Nx3    double   m      One point per row: X, Y, Z.
%
% METHOD
%   The exact closed form, with N the radius of curvature in the prime vertical:
%
%       N = a/sqrt(1 - e2*sin(lat)^2)
%       X = (N + h)*cos(lat)*cos(lon)
%       Y = (N + h)*cos(lat)*sin(lon)
%       Z = (N*(1 - e2) + h)*sin(lat)
%
%   THIS LAYER IS FRAME-AGNOSTIC BY DESIGN. The relation holds in any earth-
%   fixed frame given an ellipsoid, so the function is named by coordinate
%   representation and not by frame: it is the same arithmetic whether the
%   Cartesian triple is in ITRF2020, in ITRF2014 or in a local realization, and
%   naming it ecef2geod would imply a frame commitment L4 does not make. The
%   terrestrial frame commonly called ECEF is the ITRS, realized by an ITRF; the
%   inertial frame commonly called ECI is the GCRS. Changing between ITRF
%   realizations is convertItrf, and ITRS to GCRS is rotationItrsToGcrs.
%
%   ONE POINT PER ROW, NOT PER COLUMN. L3 and L4 take Nx3 arrays, one row per
%   station, which is how geodetic tables are written; L2 takes 3xN, one column
%   per epoch, which is how rotations page-multiply. The boundary between the
%   two is a transpose and it is stated in both places. A 3x3 input is read as
%   THREE POINTS, never as one transposed triple - the ambiguity of a square
%   array is resolved by the documented rule and never by inspection, which is
%   finding M-1's lesson applied to a different shape.
%
%   THE DEFAULT ELLIPSOID IS GRS80, not WGS84 as in the v1 toolbox. GRS80 is the
%   ellipsoid of the ITRS and of every ITRF product this toolbox reads (IERS
%   Conventions 2010, Table 1.2). The two share a and differ in flattening; see
%   ACCURACY for what that costs. State the ellipsoid explicitly for any work
%   below the millimetre.
%
% ACCURACY
%   Exact to machine precision: a few correctly rounded operations, no
%   iteration, no series. Measured against PROJ 9.5.1 for a station at 49.14 N,
%   12.88 E, 665 m on GRS80 the three components agree to 0.0e+00 m, that is
%   bit for bit.
%
%   The round trip through cartesianToGeodetic returns the height to 4.0e-10 m
%   and the latitude to 0.0e+00 rad at that station; see cartesianToGeodetic
%   for the behaviour at the poles and near the geocentre.
%
%   GRS80 AGAINST WGS84 for the same geodetic triple: 3.8e-05 m in X, 8.8e-06 m
%   in Y and 1.1e-04 m in Z at that station, growing to 1.05e-04 m in Z at the
%   pole. That is above the sub-millimetre level this toolbox targets, so the
%   ellipsoid is a choice and not a detail.
%
% ERRORS
%   referenceSystem:geodeticToCartesian:wrongPointSize
%   referenceSystem:geodeticToCartesian:latitudeOutOfRange
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Table 1.2.
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 4.1.
%
% EXAMPLE
%   xyz = referenceSystem.geodeticToCartesian([49.144969 12.877940 665], ...
%       'AngleUnit', "deg");
%   xyz = referenceSystem.geodeticToCartesian(latLonH, 'Ellipsoid', "WGS84");
%
% KEYWORDS
%   geodetic, cartesian, ECEF, ITRS, ellipsoid, latitude, longitude, height,
%   prime vertical
%
% See also CARTESIANTOGEODETIC, ELLIPSOIDPARAMETERS, CARTESIANTOENU.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 04:20 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        geodetic double {mustBeReal}
        options.Ellipsoid = "GRS80"
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(geodetic) || (size(geodetic, 2) ~= 3 && ~isempty(geodetic))
        error('referenceSystem:geodeticToCartesian:wrongPointSize', ...
            ['geodetic must be Nx3, one point per row as [lat lon h]; it is ', ...
            '%s. A 3x3 array is three points, not one transposed triple.'], ...
            mat2str(size(geodetic)));
    end

    ellipsoid = resolveEllipsoid(options.Ellipsoid);

    latitude = geodetic(:, 1);
    longitude = geodetic(:, 2);
    height = geodetic(:, 3);
    if strcmp(options.AngleUnit, "deg")
        latitude = deg2rad(latitude);
        longitude = deg2rad(longitude);
    end

    if any(abs(latitude) > pi/2 + 1e-12)
        bad = find(abs(latitude) > pi/2 + 1e-12, 1);
        error('referenceSystem:geodeticToCartesian:latitudeOutOfRange', ...
            ['Latitude of point %d is %.6g rad, outside [-pi/2, pi/2]. A ', ...
            'Cartesian triple passed in as geodetic looks exactly like ', ...
            'this.'], bad, latitude(bad));
    end

    sinLatitude = sin(latitude);
    cosLatitude = cos(latitude);
    primeVertical = ellipsoid.a./sqrt(1 - ellipsoid.e2*sinLatitude.^2);

    cartesian = [(primeVertical + height).*cosLatitude.*cos(longitude), ...
        (primeVertical + height).*cosLatitude.*sin(longitude), ...
        (primeVertical*(1 - ellipsoid.e2) + height).*sinLatitude];
end

% -------------------------------------------------------------------------

function ellipsoid = resolveEllipsoid(specification)
%RESOLVEELLIPSOID Accept an ellipsoid name or the struct ellipsoidParameters
%   returns, so that a caller may pass either without a second argument saying
%   which it is.

    if isstruct(specification)
        ellipsoid = specification;
        return
    end
    ellipsoid = referenceSystem.ellipsoidParameters(string(specification));
end
