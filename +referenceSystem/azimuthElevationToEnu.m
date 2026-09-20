function enu = azimuthElevationToEnu(azimuthElevation, options)
%AZIMUTHELEVATIONTOENU Azimuth, elevation and range to local East-North-Up.
%
%   enu = azimuthElevationToEnu(azimuthElevation) converts the Nx3 polar
%   coordinates [azimuth elevation range] to the Nx3 local East-North-Up
%   coordinates.
%
%   enu = azimuthElevationToEnu(azimuthElevation, 'AngleUnit', "deg")
%
% INPUT ARGUMENTS
%   Name               Size   Type     Units      Description
%   ----               ----   ----     -----      -----------
%   azimuthElevation   Nx3    double   rad|deg,m  Column 1 azimuth clockwise from
%                                                 North, column 2 elevation above
%                                                 the horizon, column 3 slant
%                                                 range in metres. One point per
%                                                 ROW.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default   Description
%   ----        ----   ----     -------   -----------
%   AngleUnit   1x1    string   "rad"     Unit of the input angles.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   enu    Nx3    double   m      East, North, Up, one point per row.
%
% METHOD
%       e = range*cos(elevation)*sin(azimuth)
%       n = range*cos(elevation)*cos(azimuth)
%       u = range*sin(elevation)
%
%   Note sin against the azimuth for East and cos for North, which is the
%   clockwise-from-North convention of enuToAzimuthElevation and the exact
%   inverse of it. The azimuth is not range checked: any real value is
%   meaningful modulo a full turn, and wrapping it silently would hide a caller
%   who supplied degrees under the default radian setting - a value of 275 is a
%   plausible azimuth in degrees and an implausible one in radians, so it is
%   left to produce a visibly rotated result rather than a quietly wrapped one.
%
% ACCURACY
%   Exact to machine precision. Round trip through enuToAzimuthElevation
%   reproduces the angles to 2.2e-16 rad and the range to 2.3e-16 relative.
%
%   An elevation outside [-pi/2, pi/2] is not refused; it produces a negative
%   effective range through the cosine, which is the mathematically consistent
%   continuation and is documented rather than guarded, since the round trip
%   then returns the equivalent canonical triple.
%
% ERRORS
%   referenceSystem:azimuthElevationToEnu:wrongPointSize
%
% REFERENCES
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 4.1.
%
% EXAMPLE
%   enu = referenceSystem.azimuthElevationToEnu([45 30 1000], ...
%       'AngleUnit', "deg");
%
% KEYWORDS
%   azimuth, elevation, slant range, topocentric, ENU, pointing, horizon
%
% See also ENUTOAZIMUTHELEVATION, ENUTOCARTESIAN, CARTESIANTOENU.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:22 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        azimuthElevation double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(azimuthElevation) || (size(azimuthElevation, 2) ~= 3 && ...
            ~isempty(azimuthElevation))
        error('referenceSystem:azimuthElevationToEnu:wrongPointSize', ...
            'azimuthElevation must be Nx3, one point per row; it is %s.', ...
            mat2str(size(azimuthElevation)));
    end

    azimuth = azimuthElevation(:, 1);
    elevation = azimuthElevation(:, 2);
    range = azimuthElevation(:, 3);
    if strcmp(options.AngleUnit, "deg")
        azimuth = deg2rad(azimuth);
        elevation = deg2rad(elevation);
    end

    horizontal = range.*cos(elevation);
    enu = [horizontal.*sin(azimuth), horizontal.*cos(azimuth), ...
        range.*sin(elevation)];
end
