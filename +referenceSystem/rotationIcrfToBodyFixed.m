function [rotation, info] = rotationIcrfToBodyFixed(body, epoch, options)
%ROTATIONICRFTOBODYFIXED Rotation from the ICRF to a body-fixed frame.
%
%   rotation = rotationIcrfToBodyFixed(body, epoch)
%   [rotation, info] = rotationIcrfToBodyFixed(body, epoch, Name, Value)
%
%   Builds the IAU WGCCRE body-fixed frame from the rotational elements of the
%   2015 report, Table 1: z along the pole, x through the prime meridian, y
%   completing a right-handed set.
%
%       rotation = Rz(W) * Rx(pi/2 - delta0) * Rz(pi/2 + alpha0)
%
%   The inverse is the transpose, as for every rotation in this toolbox.
%
% INPUT ARGUMENTS
%   Name    Size   Type            Units  Description
%   ----    ----   ----            -----  -----------
%   body    1x1    string | char   -      Body name, any case, e.g. "mars".
%   epoch   1x1    struct          -      Epoch struct, N entries, any scale
%                                         except UT1.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default     Description
%   ----         ----   ----     -------     -----------
%   Source       1x1    string   "iau"       "iau" for the bundled WGCCRE
%                                            Table 1, "pck" for any body a
%                                            furnished SPICE PCK covers -
%                                            Tables 1, 2 and 3.
%   Ephemeris    1x1    struct   struct([])  Furnished kernels; needed for "pck".
%   Frame        1x1    string   ""          Explicit SPICE frame, overriding
%                                            IAU_<BODY>. Required for the Moon:
%                                            "MOON_ME" or "MOON_PA".
%
% OUTPUT ARGUMENTS
%   Name       Size     Type     Units  Description
%   ----       ----     ----     -----  -----------
%   rotation   3x3xN    double   -      One orthonormal matrix per epoch,
%                                       mapping an ICRF column vector to the
%                                       body-fixed frame.
%   info       1x1      struct   -      As bodyRotationElements, plus
%                                       .composition naming the product.
%
% METHOD
%   THE TWO PROVIDERS TRAVEL IN OPPOSITE DIRECTIONS, AND THAT IS DELIBERATE.
%   With Source "iau" the three angles are primary and this rotation is
%   assembled from them; with Source "pck" the ROTATION is primary, because
%   that is what cspice_pxform returns, and bodyRotationElements derives the
%   angles from it instead. Each provider produces what its source actually
%   holds, and a kernel-backed test compares the two for the Table 1 bodies
%   where both are available - a check neither provider could perform alone.
%
%   For Source "iau" the three angles come from bodyRotationElements, which is
%   the single place the table is encoded. The geometry is the report's own Figure 1: the node Q
%   of the body equator on the ICRF equator lies at alpha0 + 90 degrees, the
%   inclination of the body equator to the celestial equator is 90 - delta0,
%   and W is measured from Q to the prime meridian along the body equator.
%
%   THE ROTATIONS ARE BUILT HERE AND NOT TAKEN FROM rotationX AND rotationZ,
%   WHICH IS DELIBERATE AND NOT DUPLICATION. Those functions take their sense
%   from attitudeConvention(), which a caller may set. The WGCCRE frame is
%   defined by the report and cannot depend on a session preference: a body
%   frame that silently transposed because somebody changed a global would be
%   a wrong answer with no symptom. The matrices used here are frame
%   (passive) rotations, fixed by this file, and the pole test below is what
%   proves the composition rather than the comment.
%
%   THE COMPOSITION IS ASSERTED BY A PROPERTY, NOT BY INSPECTION. Applying the
%   result to the pole direction (alpha0, delta0) expressed in the ICRF must
%   give exactly [0; 0; 1]. Any error in the order of the three rotations, in
%   the 90-degree offsets, or in the sense of any one of them moves the pole
%   off the z axis, so a single test covers all three.
%
% ACCURACY
%   Entirely that of the elements: see bodyRotationElements, where the report's
%   one-tenth-of-a-degree statement, the per-body validation against orbital
%   poles, and the Uranus prime-meridian caveat are given in full. This
%   function adds only orthonormal arithmetic, which is exact to roundoff -
%   measured departure from orthonormality below 1e-15 and determinant within
%   1e-15 of +1.
%
%   THE FRAME IS THE CARTOGRAPHIC ONE, NOT A DYNAMICAL ONE. The report notes
%   (section 2) that a principal-axis frame is not necessarily coincident with
%   a frame defined by synchronous or resonant rotation, and that principal
%   axis frames usually rely on a specific gravity field. For dynamical work,
%   and for the Moon at any precision, use a frame from the ephemeris instead.
%
% ERRORS
%   referenceSystem:bodyRotationElements:unknownBody
%   referenceSystem:bodyRotationElements:earthNotTabulated
%   referenceSystem:bodyRotationElements:moonNotTabulated
%   referenceSystem:bodyRotationElements:wrongScale
%       All raised by bodyRotationElements, which resolves the body. The
%       identifiers name that function because that is where the refusal is
%       decided; section C.2 binds an identifier to the deciding function.
%   referenceSystem:rotationIcrfToBodyFixed:staleEphemeris
%       Source "pck": the SPICE pool does not hold exactly the kernels the
%       Ephemeris struct names - a later readEphemeris replaced them, or other
%       code loaded an SPK beside them. Call readEphemeris again.
%
% REFERENCES
%   Archinal, B. A. et al., 2018, Celest. Mech. Dyn. Astron. 130, 22,
%       Section 2 and Figure 1.
%
% EXAMPLE
%   t = referenceSystem.datetimeToEpoch(datetime(2023, 3, 1), "TT");
%   R = referenceSystem.rotationIcrfToBodyFixed("mars", t);
%   rBodyFixed = R*rIcrf;          % and rIcrf = R.'*rBodyFixed
%
% KEYWORDS
%   WGCCRE, IAU, body-fixed, planetocentric, rotation, ICRF, pole, prime meridian
%
% See also BODYROTATIONELEMENTS, ROTATIONITRSTOGCRS, APPLYROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-30 21:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        body (1,1) string
        epoch (1,1) struct
        options.Source (1,1) string = "iau"
        options.Ephemeris struct = struct([])
        options.Frame (1,1) string = ""
    end

    [rightAscension, declination, primeMeridian, info] = ...
        referenceSystem.bodyRotationElements(body, epoch, ...
        Source = options.Source, Ephemeris = options.Ephemeris, ...
        Frame = options.Frame);

    if options.Source == "pck"
        % The kernel supplies the rotation directly; rebuilding it from the
        % derived angles would throw away the thing that was measured and
        % return a round trip through a decomposition instead.
        epoch = referenceSystem.convertTimeScale( ...
            referenceSystem.normalizeEpoch(epoch), "TDB");
        rotation = bodyFrameFromPck(body, epoch, options.Frame, ...
            options.Ephemeris, "rotationIcrfToBodyFixed");
        info.composition = "cspice_pxform('J2000', '" + info.frame + "')";
        return
    end

    rotation = localRotationZ(primeMeridian);
    rotation = pagemtimes(rotation, localRotationX(pi/2 - declination));
    rotation = pagemtimes(rotation, localRotationZ(pi/2 + rightAscension));

    info.composition = "Rz(W)*Rx(pi/2 - delta0)*Rz(pi/2 + alpha0)";
end

% =========================== local functions ===========================

function rotation = localRotationZ(angle)
%LOCALROTATIONZ Frame rotation about z, 3-by-3-by-N.
%   FIXED SENSE, INDEPENDENT OF attitudeConvention(). See METHOD.

    n = numel(angle);
    cosine = reshape(cos(angle), 1, 1, n);
    sine = reshape(sin(angle), 1, 1, n);
    zero = zeros(1, 1, n);
    one = ones(1, 1, n);

    rotation = [cosine, sine, zero; -sine, cosine, zero; zero, zero, one];
end

function rotation = localRotationX(angle)
%LOCALROTATIONX Frame rotation about x, 3-by-3-by-N.

    n = numel(angle);
    cosine = reshape(cos(angle), 1, 1, n);
    sine = reshape(sin(angle), 1, 1, n);
    zero = zeros(1, 1, n);
    one = ones(1, 1, n);

    rotation = [one, zero, zero; zero, cosine, sine; zero, -sine, cosine];
end
