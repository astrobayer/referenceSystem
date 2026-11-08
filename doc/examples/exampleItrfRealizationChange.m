%% Moving a station between ITRF realizations
% A station coordinate is meaningless without its realization and its epoch.
% This example moves one between two of them and shows what each step is worth.
%
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 23:05 (CEST, UTC+02:00)

%% Set up
setupReferenceSystem;

%% The published parameters
% ITRF parameters are published FROM ITRF2020 TO a past realization, with rates.
% The toolbox reports them rather than hiding them inside the transformation.
parameters = referenceSystem.itrfParameters("ITRF2008");
disp(parameters)

%% The station
% One point per ROW in L3 and L4. This is the opposite of the L2 convention,
% where a 3xN array is one column per epoch, and the boundary is a transpose.
stationItrf2008 = [4075532.4772, 931770.2186, 4801623.4210];   % metres
epochDecimalYear = 2015.5;

%% Convert
stationItrf2020 = referenceSystem.convertItrf(stationItrf2008, ...
    "ITRF2008", "ITRF2020", epochDecimalYear);
fprintf('shift: %.4f m\n', norm(stationItrf2020 - stationItrf2008));

%% With a velocity
% The velocity picks up the rate terms and the cross terms. A station moving at
% 2.5 cm/yr accumulates 25 cm in a decade, which is far larger than the frame
% shift itself - so an epoch is not a formality.
velocityItrf2008 = [-0.0139, 0.0165, 0.0104];                  % m/yr
[positionOut, velocityOut] = referenceSystem.convertItrf(stationItrf2008, ...
    "ITRF2008", "ITRF2020", epochDecimalYear, 'Velocity', velocityItrf2008);
fprintf('velocity change: %.6f m/yr\n', norm(velocityOut - velocityItrf2008));

%% Round trip
% Every inverse is SOLVED, never obtained by negating the parameters. Negation
% is wrong by 1e-3 m at legacy datum scale, which is the scale it was
% traditionally used at.
back = referenceSystem.convertItrf(stationItrf2020, "ITRF2020", "ITRF2008", ...
    epochDecimalYear);
fprintf('round trip closure: %.3e m\n', norm(back - stationItrf2008));

%% And in geodetic coordinates
% The default ellipsoid is GRS80, the ITRS ellipsoid of IERS Conventions Table
% 1.2 - NOT WGS84, whose polar radius differs by 1.05e-4 m.
geodetic = referenceSystem.cartesianToGeodetic(stationItrf2020, ...
    'AngleUnit', "deg");
fprintf('lat %.9f deg  lon %.9f deg  h %.4f m\n', geodetic);
