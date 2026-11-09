function spherical = cartesianToSpherical(cartesian, options)
%CARTESIANTOSPHERICAL Cartesian to geocentric spherical coordinates.
%
%   spherical = cartesianToSpherical(cartesian) converts the Nx3 Cartesian
%   coordinates to the Nx3 spherical coordinates
%   [geocentricLatitude longitude radius].
%
%   spherical = cartesianToSpherical(cartesian, 'AngleUnit', "deg")
%
% INPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   cartesian   Nx3    double   m      One point per ROW: X, Y, Z.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default   Description
%   ----        ----   ----     -------   -----------
%   AngleUnit   1x1    string   "rad"     Unit of the output angles.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units      Description
%   ----        ----   ----     -----      -----------
%   spherical   Nx3    double   rad|deg,m  Column 1 GEOCENTRIC latitude, the
%                                          angle from the equatorial plane, in
%                                          [-pi/2, pi/2]; column 2 longitude in
%                                          (-pi, pi]; column 3 geocentric radius.
%
% METHOD
%       radius    = sqrt(X^2 + Y^2 + Z^2)
%       latitude  = asin(Z/radius)
%       longitude = atan2(Y, X)
%
%   THE LATITUDE IS GEOCENTRIC AND NOT GEODETIC, and the difference is large:
%   up to 11.5 arcminutes, that is 21 km along the meridian, at 45 degrees
%   latitude. The two are equal only on the equator and at the poles. Use
%   cartesianToGeodetic for the geodetic latitude, which is the one meant by
%   "latitude" without qualification in every geodetic product. The longitude is
%   identical in the two systems; the radius is not a height.
%
%   No ellipsoid enters and none is accepted: spherical coordinates are a
%   representation of the Cartesian triple, so this function is frame-agnostic
%   in the same sense as the rest of L4 and works unchanged in a body-fixed
%   frame of any body. That is why the deferred planetary work (Part H) needs no
%   spherical function of its own.
%
% ACCURACY
%   Exact to machine precision. Round trip through sphericalToCartesian
%   reproduces the position to 2.4e-16 relative over radii from 1 m to
%   1e12 m.
%
%   At the geocentre, radius 0, the latitude is NaN and the longitude 0. This is
%   the documented undefined-but-valid case of section C.6 rule 5 rather than an
%   error, since the origin is a legitimate point of the frame; the radius,
%   which carries the information, is exactly 0.
%
% ERRORS
%   referenceSystem:cartesianToSpherical:wrongPointSize
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 4.1.
%
% EXAMPLE
%   sph = referenceSystem.cartesianToSpherical(xyz, 'AngleUnit', "deg");
%
% KEYWORDS
%   spherical, geocentric latitude, radius, longitude, cartesian, ECEF, ITRS
%
% See also SPHERICALTOCARTESIAN, CARTESIANTOGEODETIC, GEODETICTOCARTESIAN.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:26 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        cartesian double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(cartesian) || (size(cartesian, 2) ~= 3 && ~isempty(cartesian))
        error('referenceSystem:cartesianToSpherical:wrongPointSize', ...
            'cartesian must be Nx3, one point per row; it is %s.', ...
            mat2str(size(cartesian)));
    end

    radius = sqrt(sum(cartesian.^2, 2));
    latitude = asin(cartesian(:, 3)./radius);
    longitude = atan2(cartesian(:, 2), cartesian(:, 1));

    if strcmp(options.AngleUnit, "deg")
        latitude = rad2deg(latitude);
        longitude = rad2deg(longitude);
    end
    spherical = [latitude, longitude, radius];
end
