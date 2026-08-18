%% Ground station visibility
% Local-level geometry: earth-fixed to ENU, then to azimuth, elevation and
% range, with the conventions stated rather than assumed.
%
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 23:05 (CEST, UTC+02:00)

%% Set up
setupReferenceSystem;

%% The station and a satellite track
station = [49.144969, 12.877940, 665.0];        % geodetic, degrees and metres
trueAnomaly = linspace(0, 2 * pi, 721)';
radius = 6378137 + 470e3;
satelliteItrs = [radius .* cos(trueAnomaly), ...
    radius .* sin(trueAnomaly) * cos(deg2rad(89)), ...
    radius .* sin(trueAnomaly) * sin(deg2rad(89))];

%% To the local level frame
% ENU and NED are DISTINCT FRAMES in this toolbox, never a flag on one another:
% a boolean would make a call site unreadable.
enu = referenceSystem.cartesianToEnu(satelliteItrs, station, 'AngleUnit', "deg");

%% To azimuth, elevation and range
% Azimuth is measured CLOCKWISE FROM NORTH and lies in [0, 2*pi); elevation is
% above the local horizon. Both conventions are pinned by reference literals in
% the test suite, because a from-east or counter-clockwise convention produces
% an equally plausible number.
ael = referenceSystem.enuToAzimuthElevation(enu, 'AngleUnit', "deg");

%% Who is above the mask
maskDegrees = 10;
visible = ael(:, 2) > maskDegrees;
fprintf('%d of %d samples above %d deg, best elevation %.2f deg\n', ...
    sum(visible), numel(visible), maskDegrees, max(ael(:, 2)));

%% The same thing through the dispatcher
% convertCoordinates routes across the L3 and L4 graph. It does NOT include
% ITRS to GCRS: that leg needs Earth orientation data and nothing else does, so
% joining them would hide the requirement. Asking for "GCRS" raises an error
% that names the function to call instead.
alsoEnu = referenceSystem.convertCoordinates(satelliteItrs, "ITRS", "ENU", ...
    'Origin', station, 'AngleUnit', "deg");
fprintf('dispatcher agrees to %.3e m\n', max(abs(alsoEnu - enu), [], 'all'));

%% Plot
figure;
plot(ael(:, 1), ael(:, 2), '.');
hold on
yline(maskDegrees, 'r--', 'elevation mask');
xlabel('azimuth clockwise from north [deg]');
ylabel('elevation [deg]');
title('Pass geometry seen from the station');
grid on
