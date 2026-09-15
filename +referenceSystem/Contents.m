% referenceSystem — Time systems, Earth orientation and coordinate transformations
% Version 2.1.240 15-Sep-2026
%
%   Reference and time system transformations for satellite geodesy, built on
%   the IERS Conventions (2010) and the IAU SOFA library. All functions live in
%   the single-level +referenceSystem namespace and are called as
%   referenceSystem.<function>. Only the parent folder belongs on the MATLAB
%   path; never add +referenceSystem itself. Run setupReferenceSystem once in
%   the distribution folder and it arranges all of that for you, then
%   referenceSystem.buildMex once to compile the gateway.
%
%   The grouping below follows the layer architecture. A function may call
%   downward only; the layering test enforces this mechanically. Layers marked
%   "not yet implemented" arrive with their own prompt and are listed here so
%   the shape of the toolbox is visible from the first day.
%
% L0 — Time and constants
%   toolboxVersion       - Version, build date and provenance of the toolbox.
%   dataFolder           - Persistent data folder for installed EOP and kernels.
%   iersConstants        - Named IERS, IAU and BIPM constants.
%   ellipsoidParameters  - Defining and derived parameters of a reference ellipsoid.
%   timeScale            - Registry of the supported time scales.
%   normalizeEpoch       - Validate an epoch struct and put it in canonical form.
%   mjdToEpoch           - Epoch from a decimal Modified Julian Date.
%   daySecondToEpoch     - Epoch from an Nx2 day-number and seconds-of-day matrix.
%   datetimeToEpoch      - Epoch from a MATLAB datetime array.
%   gpsWeekToEpoch       - Epoch from a GPS week number and seconds of week.
%   j2000SecondsToEpoch  - Epoch from seconds elapsed since the J2000.0 epoch.
%   epochTo              - Epoch to one of the five external representations.
%   addSeconds           - Advance an epoch by seconds of its own time scale.
%   secondsBetween       - Seconds elapsed from one epoch to another.
%   leapSecondTable      - The single leap-second authority of the toolbox.
%   convertTimeScale     - Convert an epoch between any two supported time scales.
%   fundamentalArguments - Delaunay, planetary and Doodson arguments.
%
% L1 — Earth orientation parameters
%   readEop              - Read an IERS Earth orientation series into the eop struct.
%   interpolateEop       - Interpolate an EOP series to a vector of epochs.
%   subdailyEopCorrection - Sub-daily ocean tide and libration variation in the EOP.
%   zonalTideEopCorrection - Long-period zonal tide effect on Earth rotation.
%   downloadEop          - Fetch a current IERS series, with local caching (optional).
%
% L2 — Earth orientation transformation, ITRS <-> GCRS
%   cipCoordinates       - CIP coordinates and CIO locator, IAU 2006/2000A.
%   earthOrientationInterpolant - Chebyshev panels for the ITRS to GCRS chain.
%   earthOrientationPartials - Partials of the ITRS to GCRS rotation in the EOP.
%   rotationItrsToGcrsPartials - Partials of the ITRS-to-GCRS rotation w.r.t. EOP.
%   evaluateInterpolant  - Evaluate one panel of an Earth orientation interpolant.
%   writeInterpolant     - Write an Earth orientation interpolant to a file.
%   readInterpolant      - Read an interpolant written by writeInterpolant.
%   earthRotationAngleRate - Rate of advance of the Earth rotation angle.
%   earthRotationAngle   - Earth rotation angle and its rate of advance.
%   greenwichSiderealTime - Greenwich mean or apparent sidereal time.
%   equinoxNutationMatrix - Classical nutation-precession-bias matrix.
%   rotationGcrsToCirs   - Celestial-to-intermediate rotation from the CIP and CIO.
%   rotationTirsToItrs   - Polar motion rotation from the pole coordinates.
%   rotationItrsToGcrs   - Terrestrial-to-celestial rotation and its derivatives.
%   applyRotation        - Apply a rotation and its derivatives to a state.
%   invertRotation       - Inverse of a rotation and of its time derivatives.
%
% L3 — Terrestrial frame realizations
%   itrfParameters       - Published Helmert parameters from ITRF2020 to a past ITRF.
%   convertItrf          - Convert positions and velocities between ITRF realizations.
%   applyHelmert7        - Seven-parameter similarity transformation, exact both ways.
%   applyMolodensky      - Molodensky datum transformation, a legacy compatibility path.
%
% L4 — Coordinate representations
%   geodeticToCartesian  - Ellipsoidal geodetic coordinates to Cartesian coordinates.
%   cartesianToGeodetic  - Cartesian coordinates to ellipsoidal geodetic coordinates.
%   cartesianToEnu       - Earth-fixed Cartesian to local East-North-Up coordinates.
%   enuToCartesian       - Local East-North-Up to earth-fixed Cartesian coordinates.
%   enuToNed             - Local East-North-Up to local North-East-Down coordinates.
%   nedToEnu             - Local North-East-Down to local East-North-Up coordinates.
%   rotationEcefToEnu    - Earth-fixed to local East-North-Up rotation.
%   rotationEcefToNed    - Earth-fixed to local North-East-Down rotation.
%   enuToAzimuthElevation - Local East-North-Up to azimuth, elevation and range.
%   azimuthElevationToEnu - Azimuth, elevation and range to local East-North-Up.
%   cartesianToSpherical - Cartesian to geocentric spherical coordinates.
%   sphericalToCartesian - Geocentric spherical to Cartesian coordinates.
%   geodeticToUtm        - Geodetic coordinates to Universal Transverse Mercator.
%   utmToGeodetic        - Universal Transverse Mercator to geodetic coordinates.
%   geoidUndulation      - Interpolate the geoid undulation from a regular grid.
%   ellipsoidalToOrthometric - Ellipsoidal height to orthometric height.
%   orthometricToEllipsoidal - Orthometric height to ellipsoidal height.
%
% L4b — Rotation algebra
%   attitudeConvention   - Build or validate the rotation-algebra convention struct.
%   rotationX            - Elementary rotation about the x axis.
%   rotationY            - Elementary rotation about the y axis.
%   rotationZ            - Elementary rotation about the z axis.
%   rotationFromEulerSequence - Rotation matrix from an Euler angle sequence.
%   eulerSequenceFromRotation - Euler angles of a rotation, all twelve sequences.
%   rotationFromRollPitchYaw - Rotation matrix from roll, pitch and yaw.
%   rollPitchYawFromRotation - Roll, pitch and yaw of a rotation.
%   rotationFromQuaternion - Rotation matrix of a unit quaternion.
%   quaternionFromRotation - Unit quaternion of a rotation, by Shepperd's method.
%   rotationFromAxisAngle - Rotation matrix from an axis and an angle, Rodrigues.
%   axisAngleFromRotation - Rotation axis and angle of a rotation matrix.
%   quaternionFromEulerSequence - Quaternion from an Euler angle sequence.
%   eulerSequenceFromQuaternion - Euler angles of a quaternion, twelve sequences.
%   multiplyQuaternions  - Product of two quaternion series, conventions compared.
%   invertQuaternion     - Inverse of a unit quaternion, its conjugate.
%   normalizeQuaternion  - Unit norm and a consistent sign for a quaternion series.
%
% L5 — Orbit, attitude and navigation
%   rotationGcrsToRsw    - Inertial to orbit frame rotation from a satellite state.
%   interpolateQuaternions - Interpolate an attitude series to a vector of epochs.
%   rotationNavToBody    - Navigation-frame to body-frame rotation from roll, pitch and yaw.
%   angularVelocityToRotationRate - Rotation rate from an angular velocity.
%   angularVelocityFromRotationRate - Angular velocity from a rotation rate.
%   integrateAttitude    - Propagate attitude over a gyro rate series.
%   integrateAttitudeIncrements - Propagate attitude over integrated angle increments.
%   wanderAzimuthRotation - Wander-azimuth local-level mechanisation.
%   readImu1b            - Read a GRACE-FO IMU1B filtered-gyro-angle product.
%   graceFoImuAlignment  - GRACE-FO gyro axes and IMU-to-Satellite-Frame rotation.
%   graceFoImuIncrements - Satellite-Frame angle increments from GRACE-FO IMU1B.
%
% L5e — Solar-system ephemeris and the barycentric frame
%   ephemerisBodies      - Bodies a provider supplies, with their accuracy tier.
%   barycentricBodyState - Position and velocity of a body in the BCRS.
%   geocentricBodyState  - Position and velocity of a body seen from the Earth.
%   readEphemeris        - Furnish NAIF kernels and record what was furnished.
%   downloadKernels      - Fetch the SPICE kernels the MICE provider needs, or list them.
%   gcrsToBcrs           - Express a geocentric vector in barycentric coordinates.
%   bcrsToGcrs           - Express a barycentric-coordinate vector in the GCRS.
%
% L5f — Body-fixed frames (IAU WGCCRE)
%   bodyRotationElements - IAU WGCCRE rotational elements of the Sun and planets.
%   rotationIcrfToBodyFixed - Rotation from the ICRF to a body-fixed frame.
%
% L6 — Dispatch and infrastructure
%   convertCoordinates   - Single point of access across the L3 and L4 transformations.
%   mexInfo              - State of the MEX gateway and the leap-second authority.
%   mexSourceDigest      - Content digest of every C source the gateway uses.
%   buildMex             - Compile the package-private MEX gateway.
%   buildDocumentation   - Generate the function reference and the search database.
%   runTestSuite         - Run the test suite and write one plain-text report.
%   teardownReferenceSystem - Release the toolbox so its folder can be deleted.
%
%   See README.md for installation and a quick start, and
%   HANDOVER_referenceSystem.md for the design, the workflow and the rules
%   that govern every function in this package.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 20:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------
