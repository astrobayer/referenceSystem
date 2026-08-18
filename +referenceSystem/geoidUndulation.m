function undulation = geoidUndulation(geodetic, geoidGrid, options)
%GEOIDUNDULATION Interpolate the geoid undulation from a regular grid.
%
%   undulation = geoidUndulation(geodetic, geoidGrid) interpolates the geoid
%   undulation N at the Nx2 or Nx3 query points from a regular latitude and
%   longitude grid.
%
%   undulation = geoidUndulation(geodetic, geoidGrid, 'Method', "spline")
%
% INPUT ARGUMENTS
%   Name          Size   Type     Units    Description
%   ----          ----   ----     -----    -----------
%   geodetic      Nx2    double   rad|deg  Query points, column 1 latitude,
%                                          column 2 longitude, one per ROW. A
%                                          third column is accepted and ignored.
%   geoidGrid     1x1    struct   -        The grid; see below.
%   .latitude     1xM    double   deg      Grid latitudes, strictly monotonic,
%                                          ascending or descending.
%   .longitude    1xK    double   deg      Grid longitudes, strictly ascending.
%                                          Either convention, -180 to 180 or
%                                          0 to 360; queries are wrapped into it.
%   .undulation   MxK    double   m        N on the grid, rows latitude, columns
%                                          longitude, positive where the geoid is
%                                          above the ellipsoid.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default    Description
%   ----        ----   ----     -------    -----------
%   Method      1x1    string   "linear"   "linear", "spline" or "cubic", passed
%                                          to interp2.
%   AngleUnit   1x1    string   "rad"      Unit of the query angles. THE GRID IS
%                                          ALWAYS IN DEGREES.
%
% OUTPUT ARGUMENTS
%   Name         Size   Type     Units  Description
%   ----         ----   ----     -----  -----------
%   undulation   Nx1    double   m      N at each query point.
%
% METHOD
%   Bilinear interpolation of the grid by default, with the query longitudes
%   wrapped into the grid's own range so that a grid on 0 to 360 and a query at
%   -10 degrees meet correctly. The grid is not bundled with this toolbox and
%   never will be: EGM96 is about 2 MB and EGM2008 at 1 arcminute is about
%   2.6 GB, and a geoid model is a choice the user makes, not a constant.
%
%   LOADING A GRID. Any source works as long as it becomes the struct above.
%   For the NGA distributions the 15 arcminute EGM96 file and the 1 or
%   2.5 arcminute EGM2008 files are plain binary grids of single precision
%   values, row major from north to south and from 0 degrees east; read them
%   with fread, reshape, and build the two coordinate vectors from the stated
%   spacing. A GeoTIFF or NetCDF distribution can be read with readgeoraster or
%   ncread and needs the same three fields.
%
%   A POINT OUTSIDE THE GRID IS AN ERROR, not a NaN. A regional grid is a common
%   input and a query outside it is a mistake in the data or in the region, not
%   an undefined geometry: returning NaN would put it into a height that looks
%   like a number until it is differenced. The longitude cannot be outside, since
%   it wraps; only the latitude range can be violated. This differs from the
%   undefined-but-valid NaN of enuToAzimuthElevation, and the difference is
%   exactly the one section C.6 rule 5 draws.
%
%   THE NAME IS geoidUndulation AND NOT geoidheight. N is the undulation, the
%   separation between the geoid and the ellipsoid; "geoid height" is ambiguous
%   with the orthometric height H, which is the height OF A POINT above the
%   geoid. The v1 function also shadowed the Aerospace Toolbox function of that
%   name with a different argument order, which the namespace already solves;
%   the rename is on terminological merit.
%
% ACCURACY
%   The interpolation error, not the geoid model error. Bilinear interpolation
%   of a smooth field on a grid of spacing d carries an error of about
%   d^2/8 times the second derivative of N. For EGM2008 on a 1 arcminute grid
%   this is below 1 mm in mountainous terrain and far less elsewhere; on the
%   15 arcminute EGM96 grid it reaches a few centimetres in areas of strong
%   gradient. "spline" reduces the interpolation error by roughly an order of
%   magnitude on a smooth grid and is worth using on the coarser ones.
%
%   The model error dominates in every case: about 0.1 m globally for EGM2008,
%   better than 0.05 m over well surveyed regions, and 0.01 m for a modern
%   regional quasigeoid. No interpolation method improves on that.
%
% ERRORS
%   referenceSystem:geoidUndulation:wrongPointSize
%   referenceSystem:geoidUndulation:malformedGrid
%   referenceSystem:geoidUndulation:gridNotMonotonic
%   referenceSystem:geoidUndulation:outsideGrid
%
% REFERENCES
%   N. K. Pavlis, S. A. Holmes, S. C. Kenyon, J. K. Factor (2012), The
%   development and evaluation of the Earth Gravitational Model 2008 (EGM2008),
%   Journal of Geophysical Research 117, B04406.
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Sect. 6.
%
% EXAMPLE
%   grid = struct('latitude', -90:0.25:90, 'longitude', 0:0.25:359.75, ...
%       'undulation', N);
%   n = referenceSystem.geoidUndulation([49.14 12.88], grid, ...
%       'AngleUnit', "deg");
%
% KEYWORDS
%   geoid, undulation, EGM96, EGM2008, quasigeoid, interpolation, grid,
%   orthometric height
%
% See also ELLIPSOIDALTOORTHOMETRIC, ORTHOMETRICTOELLIPSOIDAL, CARTESIANTOGEODETIC.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 07:40 (CEST, UTC+02:00) - session S4, prompt P13
% -------------------------------------------------------------------------

    arguments
        geodetic double {mustBeReal, mustBeFinite}
        geoidGrid (1,1) struct
        options.Method (1,1) string {mustBeMember(options.Method, ...
            ["linear", "spline", "cubic"])} = "linear"
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(geodetic) || (size(geodetic, 2) ~= 2 && size(geodetic, 2) ~= 3)
        error('referenceSystem:geoidUndulation:wrongPointSize', ...
            ['geodetic must be Nx2 or Nx3, one point per row as [lat lon]; ', ...
            'it is %s.'], mat2str(size(geodetic)));
    end
    for field = ["latitude", "longitude", "undulation"]
        if ~isfield(geoidGrid, field)
            error('referenceSystem:geoidUndulation:malformedGrid', ...
                ['geoidGrid has no field "%s". It needs .latitude (1xM deg), ', ...
                '.longitude (1xK deg) and .undulation (MxK m).'], field);
        end
    end

    gridLatitude = double(geoidGrid.latitude(:)).';
    gridLongitude = double(geoidGrid.longitude(:)).';
    gridUndulation = double(geoidGrid.undulation);

    if ~isequal(size(gridUndulation), [numel(gridLatitude), numel(gridLongitude)])
        error('referenceSystem:geoidUndulation:malformedGrid', ...
            ['undulation is %s but the grid is %dx%d; rows must be latitude ', ...
            'and columns longitude.'], mat2str(size(gridUndulation)), ...
            numel(gridLatitude), numel(gridLongitude));
    end
    if any(diff(gridLongitude) <= 0) || any(diff(gridLatitude) == 0) || ...
            (any(diff(gridLatitude) > 0) && any(diff(gridLatitude) < 0))
        error('referenceSystem:geoidUndulation:gridNotMonotonic', ...
            ['Grid longitudes must be strictly ascending and grid latitudes ', ...
            'strictly monotonic.']);
    end

    queryLatitude = geodetic(:, 1);
    queryLongitude = geodetic(:, 2);
    if strcmp(options.AngleUnit, "rad")
        queryLatitude = rad2deg(queryLatitude);
        queryLongitude = rad2deg(queryLongitude);
    end

    % Wrap the query longitude into the grid's own convention, whichever it is.
    queryLongitude = mod(queryLongitude - gridLongitude(1), 360) + ...
        gridLongitude(1);

    latitudeLimit = sort([gridLatitude(1), gridLatitude(end)]);
    outside = queryLatitude < latitudeLimit(1) | queryLatitude > latitudeLimit(2);
    if any(outside)
        bad = find(outside, 1);
        error('referenceSystem:geoidUndulation:outsideGrid', ...
            ['Point %d is at latitude %.6g deg, outside the grid range ', ...
            '%.6g to %.6g deg. A query outside a regional grid is a mistake ', ...
            'in the data, not an undefined value, so it is refused rather ', ...
            'than returned as NaN.'], bad, queryLatitude(bad), ...
            latitudeLimit(1), latitudeLimit(2));
    end

    undulation = interp2(gridLongitude, gridLatitude, gridUndulation, ...
        queryLongitude, queryLatitude, char(options.Method));
end
