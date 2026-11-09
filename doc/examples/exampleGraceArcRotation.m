%% Rotating a GRACE-like arc from the ITRS to the GCRS, with velocities
% Shows the hot path of the toolbox: one day of one-second epochs, the rotation
% and its first derivative, and the state transformation that needs both.
%
% Open this file in the Live Editor and save it as .mlx if you prefer a live
% script; it is written with |%%| section breaks so that conversion is one
% command and needs no editing.
%
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 23:05 (CEST, UTC+02:00)

%% Set up
% Only the DISTRIBUTION folder goes on the path, never +referenceSystem.
setupReferenceSystem;

%% Read an Earth orientation series
% Units are converted once, here. Nothing downstream sees arcseconds.
eop = referenceSystem.readEop(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'test', 'fixtures', 'eop20c04.txt'));
disp(eop.meta.series)
disp(eop.meta.cipModel)

%% Build the epoch series
% The epoch is a two-part struct because a decimal MJD holds only about 5 us at
% MJD 60000 - not enough for GRACE ranging. Build the day and the second
% separately and never fold an offset into the day number.
dayNumber = 57660;
secondOfDay = (0:86399)';
utc = referenceSystem.daySecondToEpoch( ...
    [repmat(dayNumber, numel(secondOfDay), 1), secondOfDay], "UTC");

%% Rotate
% Two outputs means R and Rdot. Asking for Rdot evaluates the CIP series at
% three epochs instead of one, so it roughly triples the dominant cost; asking
% for Rddot as well adds nothing further.
tic
[R, Rdot, ~, info] = referenceSystem.rotationItrsToGcrs(utc, 'Eop', eop);
fprintf('%d epochs in %.3f s, path "%s", derivatives by "%s"\n', ...
    numel(utc.day), toc, info.path, info.derivativeMethod);

%% Apply it to a state
% v_gcrs = R*v_itrs + Rdot*r_itrs. Dropping the Rdot term costs about 350 m/s
% at low Earth orbit, so it is not optional.
rItrs = [6378137 + 470e3; 0; 0] + zeros(3, numel(utc.day));
vItrs = [0; 7.5e3; 0] + zeros(3, numel(utc.day));
[rGcrs, vGcrs] = referenceSystem.applyRotation(R, Rdot, rItrs, vItrs);

%% Go back
% There is no direction option anywhere in this toolbox: an orthogonal
% rotation's inverse is its transpose, and 'Inverse' passes that straight to
% pagemtimes at no cost.
[rBack, vBack] = referenceSystem.applyRotation(R, Rdot, rGcrs, vGcrs, ...
    'Inverse', true);
fprintf('round trip: position %.3e m, velocity %.3e m/s\n', ...
    max(abs(rBack - rItrs), [], 'all'), max(abs(vBack - vItrs), [], 'all'));

%% What the rotation is actually worth
% The tidal corrections are ON by default and are worth about 15 mm at the
% surface. Turn them off only to reproduce a v1 number.
% An epoch struct holds ARRAYS in its fields, so it is never indexed with (1):
% build a one-entry epoch instead.
firstUtc = referenceSystem.daySecondToEpoch([dayNumber, 0], "UTC");
Rplain = referenceSystem.rotationItrsToGcrs(firstUtc, 'Eop', eop, ...
    'ApplyTidalCorrections', false);
fprintf('tidal correction at this epoch: %.3e rad = %.2f mm at the equator\n', ...
    max(abs(R(:, :, 1) - Rplain), [], 'all'), ...
    max(abs(R(:, :, 1) - Rplain), [], 'all') * 6378137 * 1e3);
