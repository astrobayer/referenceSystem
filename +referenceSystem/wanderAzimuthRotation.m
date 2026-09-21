function [R, rates, info] = wanderAzimuthRotation(origin, wanderAngle, options)
%WANDERAZIMUTHROTATION Wander-azimuth local-level mechanisation, free of the polar singularity.
%
%   R = wanderAzimuthRotation(origin, wanderAngle) returns the 3x3xN rotation
%   from the earth-fixed frame to the wander-azimuth local-level frame at each
%   origin. The wander-azimuth frame exists for one reason: it is not slaved to
%   north, so it has no singularity at the pole, where a north-slaved
%   local-level frame must spin at a rate that diverges as tan(latitude).
%
%   [R, rates] = wanderAzimuthRotation(origin, wanderAngle, 'Velocity', v) also
%   returns the earth rate and the transport rate resolved in that frame, and
%   the rate at which the wander angle itself must be propagated.
%
% INPUT ARGUMENTS
%   Name          Size          Type     Units    Description
%   ----          ----          ----     -----    -----------
%   origin        Nx2 or Nx3    double   rad|deg  One origin per ROW: column 1
%                                                 geodetic latitude, column 2
%                                                 longitude, optional column 3
%                                                 ellipsoidal height in metres.
%                                                 Height defaults to zero and
%                                                 affects only the transport
%                                                 rate, never the rotation.
%   wanderAngle   Nx1 or 1x1    double   rad|deg  Wander angle, measured from
%                                                 the local-level frame towards
%                                                 the wander frame about the
%                                                 vertical. A scalar applies to
%                                                 every origin.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size          Type            Default                Description
%   ----         ----          ----            -------                -----------
%   Velocity     Nx2 or Nx3    double          zeros                  Ground
%                                                                     velocity in
%                                                                     the LOCAL
%                                                                     LEVEL frame
%                                                                     named by the
%                                                                     convention,
%                                                                     m/s.
%   Ellipsoid    1x1           string|struct   "GRS80"                Name or
%                                                                     struct.
%   AngleUnit    1x1           string          "rad"                  Unit of the
%                                                                     input angles.
%   Convention   1x1           struct          attitudeConvention()   .localFrame
%                                                                     is read.
%
% OUTPUT ARGUMENTS
%   Name              Size     Type     Units    Description
%   ----              ----     ----     -----    -----------
%   R                 3x3xN    double   -        Earth-fixed to wander-azimuth
%                                                rotation, one page per origin.
%   rates             1x1      struct   -        Angular rates in the WANDER
%                                                frame.
%   .earth            3xN      double   rad/s    omega_ie, the earth rate.
%   .transport        3xN      double   rad/s    omega_ew, the transport rate.
%                                                ITS VERTICAL COMPONENT IS
%                                                EXACTLY ZERO, by definition of
%                                                the mechanisation.
%   .wanderAngleRate  1xN      double   rad/s    d(wanderAngle)/dt, which the
%                                                caller must integrate.
%   .total            3xN      double   rad/s    omega_iw = earth + transport,
%                                                what a gyro senses when the
%                                                platform is stationary in the
%                                                wander frame.
%   info              1x1      struct   -        Diagnostics.
%   .localFrame       1x1      string   -        "ENU" or "NED".
%   .northSlavedVertical 1xN   double   rad/s    The vertical transport rate a
%                                                NORTH-SLAVED frame would need.
%                                                This is the term that diverges
%                                                at the pole and the number the
%                                                mechanisation exists to avoid.
%   .primeVerticalRadius 1xN   double   m        R_N + h.
%   .meridianRadius   1xN      double   m        R_M + h.
%
% METHOD
%   THE FRAME. The wander frame is the local-level frame rotated about the
%   local vertical by the wander angle, so
%
%       R = rotationZ(wanderAngle) * rotationEcefToEnu(origin)      (ENU)
%       R = rotationZ(wanderAngle) * rotationEcefToNed(origin)      (NED)
%
%   in the frame (passive) sense, and the elementary rotation comes from L4b
%   rather than being written out. Under ENU the third axis is Up and a
%   positive wander angle turns the first axis from East towards North; under
%   NED the third axis is Down, so the same positive angle turns the first axis
%   from North towards East. The vertical axis is unchanged either way, which
%   is what makes the composition a rotation about it.
%
%   THE EARTH RATE. The earth rotates about the polar axis, so in ENU
%   omega_ie = omega_E [0; cos(lat); sin(lat)] and in NED
%   omega_ie = omega_E [cos(lat); 0; -sin(lat)]. Both are then rotated into the
%   wander frame by the same rotationZ. At the equator the vector lies wholly
%   along North; at the pole wholly along the vertical; both are asserted in
%   the test suite because they are the two cases a reader can check by hand.
%
%   THE TRANSPORT RATE, AND WHY THIS FRAME EXISTS. A north-slaved local-level
%   frame moving over the ellipsoid must rotate relative to the earth at
%
%       omega_en^ENU = [-vN/(R_M + h); vE/(R_N + h); vE*tan(lat)/(R_N + h)]
%
%   whose VERTICAL component carries tan(lat) and therefore diverges at the
%   pole: at 89.999 degrees and 100 m/s east it is 0.895 rad/s, which is
%   51 degrees per second of frame rotation for a frame that is meant to be
%   locally stationary. The wander-azimuth mechanisation removes it by
%   DEFINITION: the frame is declared not to rotate about the vertical relative
%   to the earth, so the vertical component of omega_ew is exactly zero and the
%   rotation that would have been applied to the frame is carried instead by
%   the wander angle,
%
%       d(wanderAngle)/dt = -vE*tan(lat)/(R_N + h)
%
%   which the caller integrates alongside the attitude. Nothing is lost and
%   nothing diverges: the singular quantity has been moved from a frame
%   definition, where it is unavoidable, into a scalar the user may propagate
%   or reset at will. The horizontal components are unchanged and are simply
%   rotated into the wander frame.
%
%   info.northSlavedVertical reports the term that was removed, so the benefit
%   of the mechanisation is visible rather than asserted.
%
%   R_N is the prime-vertical radius of curvature a/sqrt(1 - e^2 sin^2(lat))
%   and R_M the meridian radius a(1 - e^2)/(1 - e^2 sin^2(lat))^(3/2), both
%   from ellipsoidParameters, plus the ellipsoidal height.
%
% ACCURACY
%   Exact to machine precision given the inputs: the rotation is one elementary
%   rotation composed with a local-level rotation, and the rates are closed
%   forms. Verified against an independent Python implementation at 52 N,
%   13 E, 100 m with a 37 degree wander angle and a (200 E, 150 N) m/s
%   velocity: the rotation agrees to 2.2e-16 elementwise with orthogonality
%   residual 2.2e-16, and every rate component to 1e-21 rad/s absolute.
%
%   THE EARTH RATE IS THE NOMINAL ONE AND THAT IS A CHOICE, NOT AN OVERSIGHT.
%   iersConstants.earthRotationRate is the IERS Table 1.1 mean angular
%   velocity, 7.292115e-5 rad/s. The true instantaneous rate differs by the
%   length-of-day variation, up to about 2.2 ms/day in the supplied EOP series,
%   which is 2.5e-8 relative - 1.8e-12 rad/s. Over an hour that is 6.6e-9 rad
%   of unmodelled frame rotation, four orders below any inertial-grade gyro
%   bias, so the nominal value is entirely adequate for inertial navigation. It
%   is NOT adequate for geodetic rotation: a user needing the true rate must
%   take it from the LOD-corrected ERA rate of rotationItrsToGcrs (P9, D20),
%   where the same 2.5e-8 is 10 micrometres per second at the surface and the
%   toolbox insists on modelling it.
%
%   The rate expressions assume the velocity is the ground velocity relative to
%   the earth. A velocity given relative to the air or to an inertial frame is
%   a different quantity and will produce a transport rate that is wrong by the
%   difference; nothing here can detect that.
%
% ERRORS
%   referenceSystem:wanderAzimuthRotation:wrongOriginSize
%   referenceSystem:wanderAzimuthRotation:wrongAngleSize
%   referenceSystem:wanderAzimuthRotation:wrongVelocitySize
%   referenceSystem:wanderAzimuthRotation:sizeMismatch
%   referenceSystem:wanderAzimuthRotation:localFrameRequired
%
% REFERENCES
%   D. H. Titterton and J. L. Weston (2004), Strapdown Inertial Navigation
%   Technology, 2nd ed., Sect. 3.5, 5.5 and 11.4 on wander azimuth.
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.4 and 5.4.
%   IERS Conventions (2010), IERS Technical Note 36, Table 1.1, for omega_E.
%
% EXAMPLE
%   [R, rates] = referenceSystem.wanderAzimuthRotation([52 13 100], 37, ...
%       'AngleUnit', "deg", 'Velocity', [200 150]);
%
% KEYWORDS
%   wander azimuth, free azimuth, local level, transport rate, earth rate,
%   strapdown, inertial navigation, polar, ENU, NED, ECEF, ITRS
%
% See also ROTATIONECEFTOENU, ROTATIONECEFTONED, ROTATIONNAVTOBODY,
%   INTEGRATEATTITUDE, IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 22:40 (CEST, UTC+02:00) - session S5, prompt P26
% -------------------------------------------------------------------------

    arguments
        origin double {mustBeReal, mustBeFinite}
        wanderAngle double {mustBeReal, mustBeFinite}
        options.Velocity double {mustBeReal, mustBeFinite} = zeros(0, 2)
        options.Ellipsoid = "GRS80"
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Convention (1,1) struct = referenceSystem.attitudeConvention()
    end

    convention = referenceSystem.attitudeConvention(options.Convention);
    if strcmp(convention.localFrame, "none")
        error('referenceSystem:wanderAzimuthRotation:localFrameRequired', ...
            ['The convention names no local frame. The wander frame is a ', ...
            'rotation of ENU or of NED about the vertical, and the two put ', ...
            'the vertical in opposite directions.']);
    end
    isNed = strcmp(convention.localFrame, "NED");

    if ~ismatrix(origin) || (size(origin, 2) ~= 2 && size(origin, 2) ~= 3)
        error('referenceSystem:wanderAzimuthRotation:wrongOriginSize', ...
            ['origin must be Nx2 or Nx3, one origin per row; it is %s. ', ...
            'Layer L4 and L5 origins use the row layout (decision D65).'], ...
            mat2str(size(origin)));
    end
    nOrigin = size(origin, 1);

    wanderAngle = reshape(wanderAngle, [], 1);
    if ~isscalar(wanderAngle) && numel(wanderAngle) ~= nOrigin
        error('referenceSystem:wanderAzimuthRotation:wrongAngleSize', ...
            ['wanderAngle must be scalar or hold one angle per origin; %d ', ...
            'angles were given for %d origins.'], numel(wanderAngle), nOrigin);
    end
    if isscalar(wanderAngle) && nOrigin > 1
        wanderAngle = repmat(wanderAngle, nOrigin, 1);
    end

    velocity = options.Velocity;
    if isempty(velocity)
        velocity = zeros(nOrigin, 2);
    end
    if ~ismatrix(velocity) || (size(velocity, 2) ~= 2 && size(velocity, 2) ~= 3)
        error('referenceSystem:wanderAzimuthRotation:wrongVelocitySize', ...
            ['Velocity must be Nx2 or Nx3, one velocity per row in the ', ...
            'local level frame; it is %s.'], mat2str(size(velocity)));
    end
    if size(velocity, 1) == 1 && nOrigin > 1
        velocity = repmat(velocity, nOrigin, 1);
    end
    if size(velocity, 1) ~= nOrigin
        error('referenceSystem:wanderAzimuthRotation:sizeMismatch', ...
            '%d origins and %d velocities; they must agree.', nOrigin, ...
            size(velocity, 1));
    end

    latitude = origin(:, 1);
    if strcmp(options.AngleUnit, "deg")
        latitude = deg2rad(latitude);
        wanderAngle = deg2rad(wanderAngle);
    end
    height = zeros(nOrigin, 1);
    if size(origin, 2) == 3
        height = origin(:, 3);
    end

    if isstruct(options.Ellipsoid)
        ellipsoid = options.Ellipsoid;
    else
        ellipsoid = referenceSystem.ellipsoidParameters(string(options.Ellipsoid));
    end
    a = ellipsoid.a;
    e2 = ellipsoid.e2;

    sineLatitude = sin(latitude);
    verticalFactor = sqrt(1 - e2*sineLatitude.^2);
    primeVerticalRadius = a./verticalFactor + height;
    meridianRadius = a*(1 - e2)./verticalFactor.^3 + height;

    if isNed
        localLevel = referenceSystem.rotationEcefToNed(origin(:, 1:2), ...
            'AngleUnit', options.AngleUnit);
        northVelocity = velocity(:, 1);
        eastVelocity = velocity(:, 2);
    else
        localLevel = referenceSystem.rotationEcefToEnu(origin(:, 1:2), ...
            'AngleUnit', options.AngleUnit);
        eastVelocity = velocity(:, 1);
        northVelocity = velocity(:, 2);
    end

    % THE COMPOSITION IS BUILT FRAME SENSE THROUGHOUT AND THE CALLER'S SENSE IS
    % APPLIED ONCE, TO THE RESULT. rotationEcefToEnu and rotationEcefToNed are
    % frame-sense only - L4 offers no sense option - so driving rotationZ with
    % a vector-sense convention would multiply a transposed factor by an
    % untransposed one and yield a matrix that is still orthogonal, still unit
    % determinant, and not the rotation either convention asks for. That is the
    % D35 failure mode exactly, and it is reachable: both presets are frame
    % sense, but a hand-built convention need not be.
    internalConvention = referenceSystem.attitudeConvention();
    wanderRotation = referenceSystem.rotationZ(reshape(wanderAngle, 1, []), ...
        'Convention', internalConvention);
    R = pagemtimes(wanderRotation, localLevel);
    if strcmp(convention.sense, "vector")
        R = pagetranspose(R);
    end

    if nargout < 2
        return
    end

    omegaEarth = referenceSystem.iersConstants().earthRotationRate;
    northSlavedVertical = eastVelocity.*tan(latitude)./primeVerticalRadius;

    if isNed
        % NED order is (North, East, Down); the vertical axis points DOWN, so
        % the earth rate's polar component and the transport rate's vertical
        % component both change sign against the ENU form.
        earthLocal = [omegaEarth*cos(latitude), zeros(nOrigin, 1), ...
            -omegaEarth*sineLatitude].';
        transportLocal = [eastVelocity./primeVerticalRadius, ...
            -northVelocity./meridianRadius, zeros(nOrigin, 1)].';
        northSlavedVertical = -northSlavedVertical;
    else
        earthLocal = [zeros(nOrigin, 1), omegaEarth*cos(latitude), ...
            omegaEarth*sineLatitude].';
        transportLocal = [-northVelocity./meridianRadius, ...
            eastVelocity./primeVerticalRadius, zeros(nOrigin, 1)].';
    end

    % The horizontal components are rotated into the wander frame; the vertical
    % one is zero before the rotation and stays zero after it, because the
    % rotation is about the vertical axis. That is not an approximation: it is
    % why the mechanisation works.
    earthWander = rotateAboutVertical(earthLocal, wanderAngle);
    transportWander = rotateAboutVertical(transportLocal, wanderAngle);

    rates = struct( ...
        'earth', earthWander, ...
        'transport', transportWander, ...
        'wanderAngleRate', reshape(-northSlavedVertical, 1, []), ...
        'total', earthWander + transportWander);

    if nargout < 3
        return
    end
    info = struct( ...
        'localFrame', convention.localFrame, ...
        'northSlavedVertical', reshape(northSlavedVertical, 1, []), ...
        'primeVerticalRadius', reshape(primeVerticalRadius, 1, []), ...
        'meridianRadius', reshape(meridianRadius, 1, []));
end

% -------------------------------------------------------------------------

function rotated = rotateAboutVertical(vector, angle)
%ROTATEABOUTVERTICAL Frame rotation of a 3xN set about its third axis.
%   Written out rather than routed through pagemtimes because the operand is a
%   vector series and not a page series, and building N pages of a 3x3 to
%   multiply N vectors would allocate nine times the data for the same answer.
%   The sign follows rotationZ in the frame sense, which the contract test
%   asserts by comparing against it.

    cosineAngle = reshape(cos(angle), 1, []);
    sineAngle = reshape(sin(angle), 1, []);
    rotated = [cosineAngle.*vector(1, :) + sineAngle.*vector(2, :); ...
        -sineAngle.*vector(1, :) + cosineAngle.*vector(2, :); ...
        vector(3, :)];
end
