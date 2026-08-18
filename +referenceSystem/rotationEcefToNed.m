function R = rotationEcefToNed(origin, options)
%ROTATIONECEFTONED Earth-fixed to local North-East-Down rotation.
%
%   R = rotationEcefToNed(origin) returns the 3x3xN rotation from the earth-
%   fixed frame to the local North-East-Down frame at each of the N geodetic
%   origins.
%
%   R = rotationEcefToNed(origin, 'AngleUnit', "deg")
%
% INPUT ARGUMENTS
%   Name     Size          Type     Units    Description
%   ----     ----          ----     -----    -----------
%   origin   Nx2 or Nx3    double   rad|deg  One origin per ROW: geodetic
%                                            latitude, longitude and an optional
%                                            ignored height.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name        Size   Type     Default   Description
%   ----        ----   ----     -------   -----------
%   AngleUnit   1x1    string   "rad"     "rad" or "deg" for the origin angles.
%
% OUTPUT ARGUMENTS
%   Name   Size     Type     Units  Description
%   ----   ----     ----     -----  -----------
%   R      3x3xN    double   -      Rotation matrices. Row 1 is the North unit
%                                   vector in earth-fixed components, row 2
%                                   East, row 3 Down.
%
% METHOD
%   Composed from elementary rotations, as rotationEcefToEnu:
%
%       R = rotationY(-(latitude + pi/2)) * rotationZ(longitude)
%
%   NED IS A DISTINCT FRAME, NEVER A FLAG ON ENU (decision D36). The two differ
%   by an axis exchange composed with a reflection of the third axis, so a
%   boolean argument would make them indistinguishable at a call site: a reader
%   could not tell which one a variable holds, and both give plausible numbers.
%   Two named functions make the frame part of the name, which is the same rule
%   that gives this toolbox geodeticToCartesian rather than a direction flag.
%
%   NED is left handed in the sense that navigation uses it - North, East, Down
%   with Down positive towards the ellipsoid - and the matrix is still a proper
%   rotation with determinant +1, because the axis exchange and the sign flip
%   each contribute -1. Check the determinant if in doubt; it is asserted in a
%   precision test.
%
%   The earth-fixed frame is the ITRS, commonly called ECEF; the inertial frame
%   commonly called ECI is the GCRS and is not involved here.
%
% ACCURACY
%   Exact to machine precision. Orthogonality residual max|R'R - I| measured
%   4.4e-16 over a global grid of origins, determinant 1 to 2.2e-16, and the
%   identity R_ned = P*R_enu with P the [N E D] permutation of [E N U] holds to
%   2.8e-16.
%
% ERRORS
%   referenceSystem:rotationEcefToNed:wrongOriginSize
%   referenceSystem:rotationEcefToNed:latitudeOutOfRange
%
% REFERENCES
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.1.
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., Sect. 4.1.
%
% EXAMPLE
%   R = referenceSystem.rotationEcefToNed([49.145 12.878], 'AngleUnit', "deg");
%
% KEYWORDS
%   NED, North East Down, local level, navigation frame, ECEF, ITRS, GCRS,
%   rotation
%
% See also ROTATIONECEFTOENU, ENUTONED, ROTATIONY, ROTATIONZ.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 04:55 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        origin double {mustBeReal, mustBeFinite}
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    if ~ismatrix(origin) || (size(origin, 2) ~= 2 && size(origin, 2) ~= 3)
        error('referenceSystem:rotationEcefToNed:wrongOriginSize', ...
            ['origin must be Nx2 or Nx3, one origin per row as [lat lon] or ', ...
            '[lat lon h]; it is %s.'], mat2str(size(origin)));
    end

    latitude = origin(:, 1).';
    longitude = origin(:, 2).';
    if strcmp(options.AngleUnit, "deg")
        latitude = deg2rad(latitude);
        longitude = deg2rad(longitude);
    end
    if any(abs(latitude) > pi/2 + 1e-12)
        bad = find(abs(latitude) > pi/2 + 1e-12, 1);
        error('referenceSystem:rotationEcefToNed:latitudeOutOfRange', ...
            'Latitude of origin %d is %.6g rad, outside [-pi/2, pi/2].', ...
            bad, latitude(bad));
    end

    R = pagemtimes(referenceSystem.rotationY(-(latitude + pi/2)), ...
        referenceSystem.rotationZ(longitude));
end
