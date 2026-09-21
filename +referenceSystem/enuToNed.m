function ned = enuToNed(enu)
%ENUTONED Local East-North-Up to local North-East-Down coordinates.
%
%   ned = enuToNed(enu) exchanges the first two components and reverses the
%   third of the Nx3 local coordinates.
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   enu    Nx3    double   any    East, North, Up, one point per ROW. The unit is
%                                 whatever the caller uses; positions, velocities
%                                 and accelerations all transform the same way.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   ned    Nx3    double   any    North, East, Down, one point per row.
%
% METHOD
%   ned = [n, e, -u]. As a matrix the transformation is
%   P = [0 1 0; 1 0 0; 0 0 -1], which is its own inverse and has determinant -1
%   because it exchanges two axes and reflects the third; the composition with
%   an earth-fixed rotation is still a proper rotation, which is why
%   rotationEcefToNed has determinant +1.
%
%   ENU AND NED ARE DISTINCT FRAMES, NEVER A FLAG (decision D36). This function
%   and its partner nedToEnu exist as two names so that a call site says which
%   frame it produces. A boolean would leave a reader unable to tell which
%   convention a variable holds, and every wrong choice yields plausible numbers
%   of the right magnitude with two components exchanged and one sign wrong.
%
%   No time, no ellipsoid and no origin enter: the exchange is the same
%   everywhere on Earth.
%
% ACCURACY
%   Exact. Indexing and one sign change, no arithmetic. The round trip through
%   nedToEnu is bit-identical to the input.
%
% ERRORS
%   referenceSystem:enuToNed:wrongPointSize
%
% REFERENCES
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.1.
%
% EXAMPLE
%   ned = referenceSystem.enuToNed(enu);
%
% KEYWORDS
%   ENU, NED, local level, navigation frame, axis exchange, topocentric
%
% See also NEDTOENU, ROTATIONECEFTONED, CARTESIANTOENU.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:15 (CEST, UTC+02:00) - session S4, prompt P12
% -------------------------------------------------------------------------

%#codegen

    arguments
        enu double {mustBeReal}
    end

    if ~ismatrix(enu) || (size(enu, 2) ~= 3 && ~isempty(enu))
        error('referenceSystem:enuToNed:wrongPointSize', ...
            'enu must be Nx3, one point per row; it is %s.', mat2str(size(enu)));
    end

    ned = [enu(:, 2), enu(:, 1), -enu(:, 3)];
end
