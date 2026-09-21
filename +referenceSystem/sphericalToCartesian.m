function cartesian = sphericalToCartesian(spherical, options)
%SPHERICALTOCARTESIAN Geocentric spherical to Cartesian coordinates.
%
%   cartesian = sphericalToCartesian(spherical) converts the Nx3 spherical
%   coordinates [geocentricLatitude longitude radius] to the Nx3 Cartesian
%   coordinates.
%
%   cartesian = sphericalToCartesian(spherical, 'AngleUnit', "deg")
%
% INPUT ARGUMENTS
%   Name        Size   Type     Units      Description
%   ----        ----   ----     -----      -----------
%   spherical   Nx3    double   rad|deg,m  Column 1 GEOCENTRIC latitude, column 2
%                                          longitude, column 3 geocentric radius.
%                                          One point per ROW.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default   Description
%   ----        ----   ----     -------   -----------
%   AngleUnit   1x1    string   "rad"     Unit of the input angles.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   cartesian   Nx3    double   m      One point per row: X, Y, Z.
%
% METHOD
%       X = radius*cos(latitude)*cos(longitude)
%       Y = radius*cos(latitude)*sin(longitude)
%       Z = radius*sin(latitude)
%
%   The latitude is GEOCENTRIC. Passing a geodetic latitude here is the most
%   likely misuse and it is undetectable from the result: it displaces the point
%   by up to 21 km along the meridian while leaving a perfectly plausible
%   Cartesian triple. Convert with geodeticToCartesian instead, which takes the
%   ellipsoid the geodetic latitude is referred to.
%
%   No ellipsoid enters; the function is frame-agnostic.
%
% ACCURACY
%   Exact to machine precision. Round trip through cartesianToSpherical
%   reproduces the position to 2.4e-16 relative.
%
% ERRORS
%   referenceSystem:sphericalToCartesian:wrongPointSize
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 4.1.
%
% EXAMPLE
%   xyz = referenceSystem.sphericalToCartesian([48.5 12.0 6371000], ...
%       'AngleUnit', "deg");
%
% KEYWORDS
%   spherical, geocentric latitude, radius, cartesian, ECEF, ITRS
%
% See also CARTESIANTOSPHERICAL, GEODETICTOCARTESIAN, CARTESIANTOGEODETIC.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:28 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        spherical double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(spherical) || (size(spherical, 2) ~= 3 && ~isempty(spherical))
        error('referenceSystem:sphericalToCartesian:wrongPointSize', ...
            'spherical must be Nx3, one point per row; it is %s.', ...
            mat2str(size(spherical)));
    end

    latitude = spherical(:, 1);
    longitude = spherical(:, 2);
    radius = spherical(:, 3);
    if strcmp(options.AngleUnit, "deg")
        latitude = deg2rad(latitude);
        longitude = deg2rad(longitude);
    end

    equatorial = radius.*cos(latitude);
    cartesian = [equatorial.*cos(longitude), equatorial.*sin(longitude), ...
        radius.*sin(latitude)];
end
