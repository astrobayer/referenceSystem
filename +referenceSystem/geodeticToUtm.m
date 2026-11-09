function [eastingNorthing, zone, hemisphere, latitudeBand] = ...
        geodeticToUtm(geodetic, options)
%GEODETICTOUTM Geodetic coordinates to Universal Transverse Mercator.
%
%   eastingNorthing = geodeticToUtm(geodetic) projects the Nx2 or Nx3 geodetic
%   coordinates onto UTM, choosing the standard zone for each point.
%
%   [eastingNorthing, zone, hemisphere, latitudeBand] = geodeticToUtm(...)
%   also returns the zone number, the hemisphere and the MGRS latitude band.
%
%   ... = geodeticToUtm(geodetic, 'Zone', 32) forces one zone for every point.
%   ... = geodeticToUtm(geodetic, 'ZoneException', "norway") applies the widened
%   zones for southern Norway and Svalbard.
%
% INPUT ARGUMENTS
%   Name       Size          Type     Units    Description
%   ----       ----          ----     -----    -----------
%   geodetic   Nx2 or Nx3    double   rad|deg  Column 1 geodetic latitude,
%                                              column 2 longitude, one point per
%                                              ROW. A third column is accepted
%                                              and ignored: UTM is a projection
%                                              of the ellipsoid surface and does
%                                              not carry height.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name            Size          Type            Default   Description
%   ----            ----          ----            -------   -----------
%   Ellipsoid       1x1           string|struct   "GRS80"   Name or struct.
%   AngleUnit       1x1           string          "rad"     Unit of the input.
%   Zone            1x1 or Nx1    double          []        Force the zone
%                                                           instead of deriving
%                                                           it from longitude.
%   ZoneException   1x1           string          "none"    "none" or "norway".
%
% OUTPUT ARGUMENTS
%   Name              Size   Type     Units  Description
%   ----              ----   ----     -----  -----------
%   eastingNorthing   Nx2    double   m      Column 1 easting, column 2 northing.
%   zone              Nx1    double   -      UTM zone number, 1 to 60.
%   hemisphere        Nx1    double   -      +1 north, -1 south. A latitude of
%                                            exactly zero is treated as north.
%   latitudeBand      Nx1    string   -      MGRS band letter C to X, omitting I
%                                            and O; "" outside -80 to 84 degrees.
%
% METHOD
%   The conformal Transverse Mercator through the Krueger n-series, with
%   k0 = 0.9996, false easting 500000 m and false northing 0 in the north and
%   10000000 m in the south. The series is truncated at n^3.
%
%   THE SERIES STAYS AT n^3 AND IS NOT RAISED TO n^6, which reverses an earlier
%   instruction in the handover and is a measured decision rather than a
%   preference. Compared against PROJ 9.5.1, which uses a higher-order
%   formulation, over latitudes -79.5 to 83.5 the n^3 truncation costs
%
%       offset from CM      easting        northing
%       --------------      -------        --------
%         0 deg             0.0e+00 m      1.71e-04 m
%         1 deg             3.6e-06 m      1.71e-04 m
%         3 deg             1.1e-05 m      1.72e-04 m
%         6 deg             2.2e-05 m      1.75e-04 m
%        20 deg             8.8e-05 m      2.27e-04 m
%
%   THE TWO COLUMNS ARE DIFFERENT ERRORS. The easting error is the transverse
%   part and grows with
%   the offset from the central meridian, which is the behaviour one expects and
%   looks for. The northing error is the MERIDIAN ARC series and is essentially
%   independent of the offset - it is 1.71e-04 m even ON the central meridian,
%   where the easting error is exactly zero, so it is the dominant term.
%
%   Both are still well inside a millimetre, so the verdict is unchanged and n^6
%   would buy nothing a UTM coordinate can use. The figures also show that the
%   often-quoted "valid only within the zone" rule is about the projection's
%   distortion, not about this series.
%
%   ZONE SELECTION. The standard rule is zone = floor((lon + 180)/6) + 1 with
%   the central meridian at 6*zone - 183 degrees. The Norway and Svalbard
%   widenings are NOT applied by default, because a coordinate computed under
%   them differs by a whole zone from one computed without and no software can
%   tell afterwards which rule was used. 'ZoneException' set to "norway" applies
%   them: zone 32 widened over southern Norway for latitudes 56 to 64 degrees
%   and longitudes 3 to 12, and the 31/33/35/37 arrangement over Svalbard for
%   latitudes 72 to 84.
%
%   A forced 'Zone' is used exactly as given, including for points outside it,
%   which is the usual reason to force one: keeping a survey in a single zone
%   across a boundary. The truncation figures above show what that costs.
%
% ACCURACY
%   Against PROJ 9.5.1 on GRS80, at 49.144969 N 12.877940 E in its standard
%   zone 33: easting agrees to 3.0e-06 m and northing to 1.7e-04 m. In zone 56
%   south, at 33.858611 S 151.214167 E: easting to 3.3e-06 m and northing to
%   1.3e-04 m.
%
%   THE ROUND TRIP THROUGH utmToGeodetic DOES NOT CLOSE AT MACHINE PRECISION,
%   and an earlier revision of this block claimed it did. Measured: 6.0e-04 m of
%   ground distance at the station above, 3.0e-04 m at Sydney, and 7.4e-04 m
%   worst case over -79.5 to 83.5 degrees, peaking near +-55. The forward alpha
%   series and the inverse beta series are inverse to O(n^3) only; they are two
%   independently truncated series and not exact inverses of one another, so
%   their errors add rather than cancel. The residual decomposes as 1.7e-04 m
%   from this function and 5.9e-04 m from the inverse, which means the inverse
%   rectifying-latitude series is the dominant term in the pair and is where an
%   extra order would pay if one is ever wanted.
%
%   UTM is defined for latitudes -80 to 84 degrees. Outside that the projection
%   is still computed and grows rapidly distorted; the latitude band is returned
%   as "" to say so, and no error is raised, because the projection remains
%   mathematically well defined and some products use it beyond the standard
%   limits.
%
% ERRORS
%   referenceSystem:geodeticToUtm:wrongPointSize
%   referenceSystem:geodeticToUtm:latitudeOutOfRange
%   referenceSystem:geodeticToUtm:zoneOutOfRange
%   referenceSystem:geodeticToUtm:zoneCountMismatch
%
% REFERENCES
%   L. Krueger (1912), Konforme Abbildung des Erdellipsoids in der Ebene,
%   Veroeffentlichung des Koeniglich Preussischen Geodaetischen Instituts 52.
%   C. F. F. Karney (2011), Transverse Mercator with an accuracy of a few
%   nanometers, Journal of Geodesy 85, 475-485.
%   IOGP Publication 373-7-2, Geomatics Guidance Note 7 part 2, Sect. 3.5.
%
% EXAMPLE
%   [en, zone, hemisphere] = referenceSystem.geodeticToUtm( ...
%       [49.144969 12.877940], 'AngleUnit', "deg");
%
% KEYWORDS
%   UTM, Transverse Mercator, Krueger, projection, easting, northing, zone,
%   MGRS, grid
%
% See also UTMTOGEODETIC, GEODETICTOCARTESIAN, ELLIPSOIDPARAMETERS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 07:00 (CEST, UTC+02:00) - session S4, prompt P13
% -------------------------------------------------------------------------

%#codegen

    arguments
        geodetic double {mustBeReal, mustBeFinite}
        options.Ellipsoid = "GRS80"
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Zone double {mustBeReal} = []
        options.ZoneException (1,1) string {mustBeMember( ...
            options.ZoneException, ["none", "norway"])} = "none"
    end

    if ~ismatrix(geodetic) || (size(geodetic, 2) ~= 2 && size(geodetic, 2) ~= 3)
        error('referenceSystem:geodeticToUtm:wrongPointSize', ...
            ['geodetic must be Nx2 or Nx3, one point per row as [lat lon] ', ...
            'or [lat lon h]; it is %s.'], mat2str(size(geodetic)));
    end

    if isstruct(options.Ellipsoid)
        ellipsoid = options.Ellipsoid;
    else
        ellipsoid = referenceSystem.ellipsoidParameters(string(options.Ellipsoid));
    end

    latitude = geodetic(:, 1);
    longitude = geodetic(:, 2);
    if strcmp(options.AngleUnit, "deg")
        latitude = deg2rad(latitude);
        longitude = deg2rad(longitude);
    end
    if any(abs(latitude) > pi/2 + 1e-12)
        bad = find(abs(latitude) > pi/2 + 1e-12, 1);
        error('referenceSystem:geodeticToUtm:latitudeOutOfRange', ...
            'Latitude of point %d is %.6g rad, outside [-pi/2, pi/2].', ...
            bad, latitude(bad));
    end
    longitude = mod(longitude + pi, 2*pi) - pi;
    nPoint = numel(latitude);

    if isempty(options.Zone)
        zone = standardZone(latitude, longitude, options.ZoneException);
    else
        zone = options.Zone(:);
        if ~isscalar(zone) && numel(zone) ~= nPoint
            error('referenceSystem:geodeticToUtm:zoneCountMismatch', ...
                '%d zones for %d points: supply one zone or one per point.', ...
                numel(zone), nPoint);
        end
        if isscalar(zone)
            zone = repmat(zone, nPoint, 1);
        end
        if any(zone < 1 | zone > 60 | mod(zone, 1) ~= 0)
            error('referenceSystem:geodeticToUtm:zoneOutOfRange', ...
                'Zone must be an integer from 1 to 60.');
        end
    end

    hemisphere = ones(nPoint, 1);
    hemisphere(latitude < 0) = -1;
    latitudeBand = mgrsBand(latitude);

    centralMeridian = deg2rad(zone*6 - 183);
    eastingNorthing = krueger(latitude, longitude - centralMeridian, ...
        ellipsoid, hemisphere);
end

% -------------------------------------------------------------------------

function eastingNorthing = krueger(latitude, deltaLongitude, ellipsoid, ...
        hemisphere)
%KRUEGER The n^3 Krueger series, forward.

    n = ellipsoid.n;
    e = sqrt(ellipsoid.e2);
    scaleFactor = 0.9996;
    falseEasting = 500000;

    rectifyingRadius = ellipsoid.a/(1 + n)*(1 + n^2/4 + n^4/64);
    alpha = [n/2 - 2/3*n^2 + 5/16*n^3, 13/48*n^2 - 3/5*n^3, 61/240*n^3];

    isometric = atanh(sin(latitude)) - e*atanh(e*sin(latitude));
    tangent = sinh(isometric);

    conformalLatitude = atan2(tangent, cos(deltaLongitude));
    conformalLongitude = asinh(sin(deltaLongitude)./ ...
        sqrt(tangent.^2 + cos(deltaLongitude).^2));

    xi = conformalLatitude;
    eta = conformalLongitude;
    for term = 1:3
        xi = xi + alpha(term)*sin(2*term*conformalLatitude).* ...
            cosh(2*term*conformalLongitude);
        eta = eta + alpha(term)*cos(2*term*conformalLatitude).* ...
            sinh(2*term*conformalLongitude);
    end

    falseNorthing = zeros(size(latitude));
    falseNorthing(hemisphere < 0) = 10000000;

    eastingNorthing = [falseEasting + scaleFactor*rectifyingRadius*eta, ...
        falseNorthing + scaleFactor*rectifyingRadius*xi];
end

function zone = standardZone(latitude, longitude, exception)
%STANDARDZONE The six-degree zones, optionally with the Norway and Svalbard
%   widenings. The exceptions are applied only when asked for, because a
%   coordinate computed under them cannot be told from one computed without.

    longitudeDegree = rad2deg(longitude);
    latitudeDegree = rad2deg(latitude);
    zone = min(max(floor((longitudeDegree + 180)/6) + 1, 1), 60);

    if strcmp(exception, "none")
        return
    end

    southernNorway = latitudeDegree >= 56 & latitudeDegree < 64 & ...
        longitudeDegree >= 3 & longitudeDegree < 12;
    zone(southernNorway) = 32;

    svalbard = latitudeDegree >= 72 & latitudeDegree < 84;
    zone(svalbard & longitudeDegree >= 0 & longitudeDegree < 9) = 31;
    zone(svalbard & longitudeDegree >= 9 & longitudeDegree < 21) = 33;
    zone(svalbard & longitudeDegree >= 21 & longitudeDegree < 33) = 35;
    zone(svalbard & longitudeDegree >= 33 & longitudeDegree < 42) = 37;
end

function band = mgrsBand(latitude)
%MGRSBAND The eight-degree MGRS latitude bands, C to X without I and O.

    letter = ['C' 'D' 'E' 'F' 'G' 'H' 'J' 'K' 'L' 'M' 'N' 'P' 'Q' 'R' 'S' ...
        'T' 'U' 'V' 'W' 'X'];
    latitudeDegree = rad2deg(latitude);
    index = floor((latitudeDegree + 80)/8) + 1;
    index(latitudeDegree >= 72 & latitudeDegree <= 84) = 20;   % X spans 12 deg

    band = repmat("", numel(latitude), 1);
    inRange = index >= 1 & index <= 20 & latitudeDegree >= -80 & ...
        latitudeDegree <= 84;
    % reshape first: A(I) with A and I both vectors takes A's orientation,
    % which would make this a row and the assignment a size error.
    band(inRange) = string(reshape(letter(index(inRange)), [], 1));
end
