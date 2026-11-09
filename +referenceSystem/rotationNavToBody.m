function [R, info] = rotationNavToBody(rollPitchYaw, options)
%ROTATIONNAVTOBODY Navigation-frame to body-frame rotation from roll, pitch and yaw.
%
%   R = rotationNavToBody(rollPitchYaw, 'Convention', convention) returns the
%   3x3xN rotation from the local navigation frame to the body frame. The
%   convention is REQUIRED and has no default, because the ENU-versus-NED
%   choice changes what pitch and yaw MEAN, not merely their sign.
%
%   [R, info] = rotationNavToBody(...) also returns which frames the rotation
%   runs between and the local-level frame the angles were read against.
%
% INPUT ARGUMENTS
%   Name           Size   Type     Units    Description
%   ----           ----   ----     -----    -----------
%   rollPitchYaw   3xN    double   rad|deg  Row 1 roll (about the body x axis),
%                                           row 2 pitch (y), row 3 yaw (z), one
%                                           attitude per COLUMN. The order is
%                                           the reverse of the ZYX sequence
%                                           order, as in
%                                           rotationFromRollPitchYaw.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default   Description
%   ----         ----   ----     -------   -----------
%   Convention   1x1    struct   none      REQUIRED. .localFrame, .sequence,
%                                          .rotationType and .sense are read.
%   AngleUnit    1x1    string   "rad"     "rad" or "deg".
%
% OUTPUT ARGUMENTS
%   Name          Size     Type     Units  Description
%   ----          ----     ----     -----  -----------
%   R             3x3xN    double   -      Rotation matrices, one page each.
%   info          1x1      struct   -      Diagnostics.
%   .fromFrame    1x1      string   -      "NAV".
%   .toFrame      1x1      string   -      "BODY".
%   .localFrame   1x1      string   -      "ENU" or "NED", from the convention.
%   .angleOrder   1x3      string   -      What each input row is.
%
% METHOD
%   THE DELIVERABLE IS THE NAMING, NOT THE ARITHMETIC. Roll, pitch and yaw are
%   the intrinsic ZYX Euler angles by definition, so this function delegates
%   wholly to rotationFromRollPitchYaw and adds only the statement of which two
%   frames the result runs between. That statement is what a navigation user
%   needs and what a bare Euler-angle function cannot give: NAV and BODY are
%   frames whose realization the caller supplies (a body frame is defined by
%   its platform, a nav frame by its origin), so the toolbox validates the
%   names and requires the defining parameters explicitly rather than
%   defaulting them (section B.3).
%
%   WHY THE CONVENTION IS REQUIRED HERE AND OPTIONAL ELSEWHERE. Under ENU the
%   third axis is Up and yaw increases from East towards North; under NED it is
%   Down and yaw is the familiar heading clockwise from North. The two differ
%   by more than a sign: the same three numbers describe two different
%   attitudes, both orthogonal, both plausible, and nothing at runtime
%   distinguishes them. That is decision D35's argument at its sharpest, so
%   this is the one place the default is withdrawn. Pass
%   attitudeConvention("aerospace") for NED, attitudeConvention("geodetic")
%   for ENU, and say which you mean.
%
%   The earth-fixed frame underlying the nav frame is whichever the caller
%   supplied to rotationEcefToEnu or rotationEcefToNed - rigorously the ITRS if
%   it came from rotationItrsToGcrs, and the GCRS is not involved at all. L4
%   and L5 make no frame commitment of their own (section C.7).
%
% ACCURACY
%   Exact to machine precision; the accuracy is that of rotationFromRollPitchYaw,
%   whose orthogonality residual max|R'R - I| measures 4.4e-16. Verified against
%   an independent Python implementation at roll 10, pitch 20, yaw 30 degrees,
%   intrinsic ZYX in the frame sense, agreeing to 2.2e-16 elementwise with
%   determinant 1 to one unit in the last place.
%
%   This function performs no arithmetic of its own, so it adds no error.
%
% ERRORS
%   referenceSystem:rotationNavToBody:conventionRequired
%   referenceSystem:rotationNavToBody:localFrameRequired
%   referenceSystem:rotationNavToBody:wrongAngleSize
%
% REFERENCES
%   D. H. Titterton and J. L. Weston (2004), Strapdown Inertial Navigation
%   Technology, 2nd ed., Sect. 3.5 and 3.6.
%   P. D. Groves (2013), Principles of GNSS, Inertial and Multisensor
%   Integrated Navigation Systems, 2nd ed., Sect. 2.2.
%
% EXAMPLE
%   convention = referenceSystem.attitudeConvention("aerospace");
%   R = referenceSystem.rotationNavToBody([10; 20; 30], ...
%       'Convention', convention, 'AngleUnit', "deg");
%
% KEYWORDS
%   strapdown, attitude, roll, pitch, yaw, heading, body frame, navigation
%   frame, NED, ENU, inertial navigation
%
% See also ROTATIONFROMROLLPITCHYAW, ROTATIONECEFTONED, ROTATIONECEFTOENU,
%   ANGULARVELOCITYTOROTATIONRATE.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 22:30 (CEST, UTC+02:00) - session S5, prompt P26
% -------------------------------------------------------------------------

    arguments
        rollPitchYaw double {mustBeReal, mustBeFinite}
        options.Convention (1,1) struct = struct('source', "not supplied")
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
    end

    % The sentinel is a struct with only .source, which no valid convention is:
    % attitudeConvention requires all seven fields. Same pattern as D67's
    % required 'Convention' and 'Units' on applyHelmert7.
    if isscalar(fieldnames(options.Convention)) && ...
            isfield(options.Convention, 'source') && ...
            strcmp(options.Convention.source, "not supplied")
        error('referenceSystem:rotationNavToBody:conventionRequired', ...
            ['Convention must be supplied. The ENU and NED local frames give ', ...
            'the same three angles two different meanings - under ENU the ', ...
            'third axis is Up, under NED it is Down - and both produce a ', ...
            'valid rotation, so there is nothing at runtime to catch the ', ...
            'wrong choice. Use attitudeConvention("geodetic") for ENU or ', ...
            'attitudeConvention("aerospace") for NED.']);
    end

    convention = referenceSystem.attitudeConvention(options.Convention);

    if strcmp(convention.localFrame, "none")
        error('referenceSystem:rotationNavToBody:localFrameRequired', ...
            ['The convention names no local frame. A navigation frame is ', ...
            'either ENU or NED here; "none" says nothing about which axis ', ...
            'pitch and yaw turn about.']);
    end

    if size(rollPitchYaw, 1) ~= 3 || ~ismatrix(rollPitchYaw)
        error('referenceSystem:rotationNavToBody:wrongAngleSize', ...
            ['rollPitchYaw must be 3xN, one attitude per column; it is %s. ', ...
            'Row 1 is roll, row 2 pitch, row 3 yaw.'], ...
            mat2str(size(rollPitchYaw)));
    end

    R = referenceSystem.rotationFromRollPitchYaw(rollPitchYaw, ...
        'AngleUnit', options.AngleUnit, 'Convention', convention);

    if nargout < 2
        return
    end
    info = struct( ...
        'fromFrame', "NAV", ...
        'toFrame', "BODY", ...
        'localFrame', convention.localFrame, ...
        'angleOrder', ["roll", "pitch", "yaw"]);
end
