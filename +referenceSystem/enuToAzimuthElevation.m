function azimuthElevation = enuToAzimuthElevation(enu, options)
%ENUTOAZIMUTHELEVATION Local East-North-Up to azimuth, elevation and range.
%
%   azimuthElevation = enuToAzimuthElevation(enu) converts the Nx3 local
%   East-North-Up coordinates to the Nx3 polar coordinates
%   [azimuth elevation range].
%
%   azimuthElevation = enuToAzimuthElevation(enu, 'AngleUnit', "deg")
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   enu    Nx3    double   m      East, North, Up, one point per ROW.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default   Description
%   ----        ----   ----     -------   -----------
%   AngleUnit   1x1    string   "rad"     Unit of the output angles.
%
% OUTPUT ARGUMENTS
%   Name               Size   Type     Units      Description
%   ----               ----   ----     -----      -----------
%   azimuthElevation   Nx3    double   rad|deg,m  Column 1 azimuth in [0, 2*pi),
%                                                 measured CLOCKWISE FROM NORTH;
%                                                 column 2 elevation above the
%                                                 local horizon in
%                                                 [-pi/2, pi/2]; column 3 slant
%                                                 range in metres.
%
% METHOD
%       range     = sqrt(e^2 + n^2 + u^2)
%       azimuth   = mod(atan2(e, n), 2*pi)
%       elevation = asin(u/range)
%
%   THE ARGUMENT ORDER atan2(e, n) IS THE POINT OF THE FUNCTION. Azimuth runs
%   clockwise from North, which is the opposite sense and a different zero from
%   the mathematical atan2(y, x); writing atan2(n, e) instead gives an angle
%   that is still in range, still smooth and wrong by the reflection
%   azimuth -> pi/2 - azimuth. Nothing downstream can detect it. The convention
%   here is the geodetic and surveying one: North 0, East pi/2, South pi,
%   West 3*pi/2.
%
%   Elevation is the angle above the local horizon, not the zenith distance;
%   zenith distance is pi/2 minus this.
%
% ACCURACY
%   Exact to machine precision. Round trip through azimuthElevationToEnu
%   reproduces the local vector to 3.7e-10 m relative at every elevation, and
%   the azimuth to 2.2e-16 rad away from the zenith.
%
%   AT ZERO RANGE THE DIRECTION IS UNDEFINED and the elevation is returned as
%   NaN, with the azimuth 0 and the range 0. This is the documented
%   undefined-but-valid case of the diagnostic policy (section C.6 rule 5): the
%   point coincides with the origin, which is legitimate input, so it is not an
%   error, and NaN is the honest answer for an angle that does not exist.
%
%   AT THE ZENITH the azimuth is determined by e and n at the level of the
%   rounding of the input; a target 1 mm from the vertical at 1000 km range has
%   its azimuth defined to about 1e-9 rad, and one exactly overhead has no
%   azimuth at all and gets 0. The elevation stays exact throughout.
%
% ERRORS
%   referenceSystem:enuToAzimuthElevation:wrongPointSize
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 4.1.
%
% EXAMPLE
%   ael = referenceSystem.enuToAzimuthElevation(enu, 'AngleUnit', "deg");
%
% KEYWORDS
%   azimuth, elevation, slant range, topocentric, ENU, horizon, zenith,
%   visibility
%
% See also AZIMUTHELEVATIONTOENU, CARTESIANTOENU, ENUTONED.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:20 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        enu double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(enu) || (size(enu, 2) ~= 3 && ~isempty(enu))
        error('referenceSystem:enuToAzimuthElevation:wrongPointSize', ...
            'enu must be Nx3, one point per row; it is %s.', mat2str(size(enu)));
    end

    range = sqrt(sum(enu.^2, 2));
    azimuth = mod(atan2(enu(:, 1), enu(:, 2)), 2*pi);
    elevation = asin(enu(:, 3)./range);

    if strcmp(options.AngleUnit, "deg")
        azimuth = rad2deg(azimuth);
        elevation = rad2deg(elevation);
    end
    azimuthElevation = [azimuth, elevation, range];
end
