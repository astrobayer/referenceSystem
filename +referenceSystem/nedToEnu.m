function enu = nedToEnu(ned)
%NEDTOENU Local North-East-Down to local East-North-Up coordinates.
%
%   enu = nedToEnu(ned) exchanges the first two components and reverses the
%   third of the Nx3 local coordinates.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   ned    Nx3    double   any    North, East, Down, one point per ROW.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   enu    Nx3    double   any    East, North, Up, one point per row.
%
% METHOD
%   enu = [e, n, -d], the same permutation and reflection as enuToNed, which is
%   its own inverse. It is written as a separate file rather than as a direction
%   flag because the frame belongs in the name (decision D36); see enuToNed for
%   the full argument.
%
% ACCURACY
%   Exact. Indexing and one sign change. The round trip through enuToNed is
%   bit-identical to the input.
%
% ERRORS
%   referenceSystem:nedToEnu:wrongPointSize
%
% REFERENCES
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.1.
%
% EXAMPLE
%   enu = referenceSystem.nedToEnu(ned);
%
% KEYWORDS
%   NED, ENU, local level, navigation frame, axis exchange, topocentric
%
% See also ENUTONED, ROTATIONECEFTOENU, ROTATIONECEFTONED.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:16 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        ned double {mustBeReal}
    end

    if ~ismatrix(ned) || (size(ned, 2) ~= 3 && ~isempty(ned))
        error('referenceSystem:nedToEnu:wrongPointSize', ...
            'ned must be Nx3, one point per row; it is %s.', mat2str(size(ned)));
    end

    enu = [ned(:, 2), ned(:, 1), -ned(:, 3)];
end
