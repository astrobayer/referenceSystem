function [rotation, rightAscension, declination, primeMeridian] = ...
        bodyFrameFromPck(body, epoch, frameName, ephemeris, functionName)
%BODYFRAMEFROMPCK Body-fixed frame from a furnished SPICE PCK.
%
%   [rotation, alpha0, delta0, w] = bodyFrameFromPck(body, epoch, frame, eph, name)
%
%   PACKAGE-PRIVATE. The "pck" provider of bodyRotationElements and
%   rotationIcrfToBodyFixed. It asks cspice_pxform for the rotation and derives
%   the three elements from it, which is the OPPOSITE direction of travel from
%   the "iau" provider, where the elements are primary and the rotation is
%   assembled from them. That asymmetry is the point: each provider produces
%   what its source actually holds, and the two are compared against each other
%   by the kernel-backed tests.
%
% INPUT ARGUMENTS
%   Name           Size   Type      Units  Description
%   ----           ----   ----      -----  -----------
%   body           1x1    string    -      Body name, used to build IAU_<BODY>.
%   epoch          1x1    struct    -      Epoch struct, N entries, TDB reached
%                                          by the caller.
%   frameName      1x1    string    -      Explicit SPICE frame, or "" to use
%                                          IAU_<BODY>.
%   ephemeris      1x1    struct    -      Furnished kernels from readEphemeris.
%   functionName   1x1    string    -      Public caller, for the identifiers.
%
% OUTPUT ARGUMENTS
%   Name             Size     Type     Units  Description
%   ----             ----     ----     -----  -----------
%   rotation         3x3xN    double   -      ICRF to body-fixed.
%   rightAscension   1xN      double   rad    alpha0, derived from the rotation.
%   declination      1xN      double   rad    delta0, derived.
%   primeMeridian    1xN      double   rad    W, derived, in [0, 2*pi).
%
% METHOD
%   THE ELEMENTS ARE DERIVED FROM THE MATRIX, NOT READ FROM THE KERNEL. SPICE
%   exposes a rotation, not alpha0, delta0 and W, so the three are recovered by
%   inverting the geometry of the report's Figure 1: the third row of the
%   rotation IS the pole in the ICRF, which gives alpha0 and delta0 directly;
%   the node Q then follows as [-sin(alpha0); cos(alpha0); 0], and W is the
%   angle from Q to the first row measured about the pole,
%
%       W = atan2( (Q x x_body) . pole , Q . x_body )
%
%   which is the exact inverse of the Rodrigues construction the "iau" provider
%   is tested against. A body whose two providers disagree therefore fails in a
%   way that names which of the two is wrong.
%
%   SPICE's "J2000" IS USED AS THE ICRF, WHICH IS WHAT NAIF IMPLEMENTS. The
%   frame bias between the dynamical mean equinox of J2000 and the ICRF is not
%   applied by SPICE and is not applied here; the WGCCRE elements are referred
%   to the ICRF, so the two agree by construction rather than by coincidence.
%
% ACCURACY
%   Entirely the kernel's. pck00011.tpc encodes the same WGCCRE tables, so for
%   Table 1 bodies the two providers must agree to the resolution of the
%   tabulated digits; for Tables 2 and 3 the kernel is the ONLY source this
%   toolbox has, since no independent orbital-pole check exists for a satellite
%   or an asteroid without a satellite ephemeris.
%
% ERRORS
%   referenceSystem:<caller>:miceUnavailable
%   referenceSystem:<caller>:ephemerisRequired
%   referenceSystem:<caller>:frameNotFound
%
% REFERENCES
%   Archinal, B. A. et al., 2018, Celest. Mech. Dyn. Astron. 130, 22, Fig. 1.
%   NAIF SPICE Toolkit, cspice_pxform; generic text PCK pck00011.tpc.
%
% EXAMPLE
%   % Not called directly; see rotationIcrfToBodyFixed(..., Source = "pck").
%
% KEYWORDS
%   SPICE, PCK, pxform, body-fixed, IAU frame, private
%
% See also BODYROTATIONELEMENTS, ROTATIONICRFTOBODYFIXED, READEPHEMERIS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-31 17:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    if isempty(ephemeris)
        error(sprintf('referenceSystem:%s:ephemerisRequired', functionName), ...
            ['Source "pck" reads the frame from furnished kernels, so an ', ...
            'Ephemeris struct from readEphemeris is required. Fetch the ', ...
            'kernels with downloadKernels(Set = "orientation", Mode = ', ...
            '"download") and furnish pck00011.tpc.']);
    end
    if exist('cspice_pxform', 'file') ~= 2 && exist('cspice_pxform', 'file') ~= 3
        error(sprintf('referenceSystem:%s:miceUnavailable', functionName), ...
            ['Source "pck" needs the NAIF MICE toolkit on the MATLAB path ', ...
            'and cspice_pxform was not found. Source "iau" is bundled and ', ...
            'needs nothing, but covers WGCCRE Table 1 only.']);
    end
    ephemerisPool("require", ephemeris, functionName);

    if frameName == ""
        frameName = "IAU_" + upper(body);
    end

    constants = referenceSystem.iersConstants();
    ephemerisTime = (epoch.day - constants.mjdJ2000)*constants.secondsPerDay + ...
        epoch.sec;

    try
        rotation = cspice_pxform('J2000', char(frameName), ephemerisTime(:).');
    catch cause
        error(sprintf('referenceSystem:%s:frameNotFound', functionName), ...
            ['SPICE could not build frame "%s". Either the body is not in ', ...
            'the furnished PCK, or the frame needs a kernel that was not ', ...
            'furnished - MOON_ME and MOON_PA need both ', ...
            'moon_pa_de440_200625.bpc and moon_de440_250416.tf. SPICE ', ...
            'said: %s'], frameName, cause.message);
    end

    % Elements recovered from the geometry of Figure 1. See METHOD.
    pole = squeeze(rotation(3, :, :));
    if size(rotation, 3) == 1
        pole = pole(:);
    end
    declination = asin(max(-1, min(1, pole(3, :))));
    rightAscension = mod(atan2(pole(2, :), pole(1, :)), 2*pi);

    node = [-sin(rightAscension); cos(rightAscension); zeros(1, numel(declination))];
    xBody = squeeze(rotation(1, :, :));
    if size(rotation, 3) == 1
        xBody = xBody(:);
    end
    primeMeridian = mod(atan2(dot(cross(node, xBody), pole), ...
        dot(node, xBody)), 2*pi);
end
