function [X, Y, s] = cipCoordinates(epoch, options)
%CIPCOORDINATES CIP coordinates and CIO locator, IAU 2006/2000A.
%
%   [X, Y, s] = cipCoordinates(epoch)
%   [X, Y, s] = cipCoordinates(epoch, 'Eop', eopAtEpoch)
%   [X, Y, s] = cipCoordinates(epoch, 'DeltaX', dX, 'DeltaY', dY, ...
%                              'CipModel', "IAU2006/2000A")
%
%   Returns the coordinates X and Y of the Celestial Intermediate Pole in the
%   GCRS and the CIO locator s, evaluated directly from the IAU 2006/2000A
%   precession-nutation model and optionally corrected by the observed
%   celestial pole offsets. The offsets are added in the frame they are
%   referred to, which is the whole point of this function; see METHOD.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, scale TT.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name          Size        Type            Default  Description
%   ----          ----        ----            -------  -----------
%   Eop           1x1         struct          none     Output of
%                                                      interpolateEop at these
%                                                      epochs. Supplies dX, dY
%                                                      and meta.cipModel in one
%                                                      argument.
%   DeltaX        1x1 | Nx1   double          0        Observed dX in radians,
%                                                      when Eop is not given.
%   DeltaY        1x1 | Nx1   double          0        Observed dY in radians.
%   CipModel      1x1         string          from Eop Frame the offsets are
%                                                      referred to, either
%                                                      "IAU2006/2000A" or
%                                                      "IAU2000A". Required
%                                                      whenever an offset is
%                                                      non-zero.
%   Interpolant   1x1         struct          none     Reserved. Supplying it
%                                                      raises notImplemented;
%                                                      see METHOD.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   X      Nx1    double   rad    CIP x-coordinate in the GCRS.
%   Y      Nx1    double   rad    CIP y-coordinate in the GCRS.
%   s      Nx1    double   rad    CIO locator, the position of the CIO on the
%                                 CIP equator relative to the point whose
%                                 direction is unchanged by precession-nutation.
%
% METHOD
%   FINDING C-2, WHICH IS WHY THIS FUNCTION EXISTS SEPARATELY. The observed
%   celestial pole offsets dX and dY are corrections to a model, and they are
%   meaningless without knowing which model. v1 assumed IAU 2000A always, and
%   therefore added the model bias (X00 - X06) at every epoch:
%
%       v1:    X = X06 + (X00 - X06) + dX      unconditionally
%
%   For a series whose offsets are already referred to IAU 2006/2000A that
%   injects the bias as a spurious offset. Measured with the bundled SOFA
%   release, (X00 - X06, Y00 - Y06) is (2.5, 39.1) microarcseconds at 2007 and
%   (121.3, 134.7) at 2025, growing secularly. At 2025 that is 4.2 mm at the
%   Earth's surface, which is exactly the level GRACE-like processing cares
%   about. v1 also paid for a second full nutation series to compute it.
%
%   Here the frame of the offsets is a property of the data:
%
%       "IAU2006/2000A"   X = X06 + dX                iauXys00a never called
%       "IAU2000A"        X = X06 + (X00 - X06) + dX  the bias is correct here
%
%   and eop.meta.cipModel carries it from readEop, where it was recorded from
%   the format registry or from the file. An unknown model is an error, not a
%   default: the wrong choice produces a rotation that is orthogonal, smooth
%   and plausible, and wrong by millimetres, which is a failure mode no runtime
%   check downstream can catch.
%
%   The decision itself lives in C, in rsCipAt of mex/rsCore.c, and is reached
%   from here and from rotationItrsToGcrs alike (decision D61). Putting it in
%   MATLAB would have meant either two implementations of one fix or six MEX
%   round trips per single-epoch rotation.
%
%   The model is evaluated DIRECTLY at every epoch, through SOFA iauXys06a.
%   There is no interpolated path in v2.0 (decisions D17 and D24): interpolation
%   belongs to earthOrientationInterpolant, which interpolates X, Y and s
%   alongside the EOP quantities, and two mechanisms for one job would mean two
%   error budgets and two code paths. 'Interpolant' is declared here so that the
%   signature is final now and P19 changes no call site later.
%
%   The vocabulary is direct and interpolated at every level of this toolbox,
%   never exact and interp.
%
% ACCURACY
%   Against the SOFA cookbook worked example of 2007-04-05 12:00:00 UTC
%   (sofa_pn_c.pdf sections 5.3 and 5.5), measured, not asserted:
%
%       X, offsets referred to IAU2006/2000A    8.99e-17 rad
%       Y, offsets referred to IAU2006/2000A    2.88e-16 rad
%       s                                       1.89e-11 arcsec
%       X, offsets referred to IAU2000A         2.98e-17 rad
%       Y, offsets referred to IAU2000A         1.24e-16 rad
%
%   The two branches reach the same physical pole to 1.1e-13 rad, that is
%   0.023 microarcseconds. That residual is the cookbook's own difference
%   between its sections 5.3 and 5.5 and is the rounding of the published
%   offsets to four decimals of a milliarcsecond, not an error here.
%
%   The intrinsic evaluation noise of the series, measured as the residual of a
%   degree-6 fit over a two-hour window where the model is smooth to far higher
%   degree, is 4.5e-18 rad rms in X, 5.2e-17 in Y and 1.9e-20 in s. That is the
%   floor of any finite difference built on this function and it is why
%   rotationItrsToGcrs states a measured step rather than an assumed one.
%
%   The physical accuracy of the model itself is that of IAU 2006/2000A, of
%   order 0.2 milliarcseconds, which is four orders above everything above and
%   is what the observed offsets exist to remove.
%
% ERRORS
%   referenceSystem:cipCoordinates:wrongScale
%   referenceSystem:cipCoordinates:unknownCipModel
%   referenceSystem:cipCoordinates:cipModelRequired
%   referenceSystem:cipCoordinates:sizeMismatch
%   referenceSystem:cipCoordinates:conflictingOffsets
%   referenceSystem:cipCoordinates:notImplemented
%   referenceSystem:cipCoordinates:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.4 to 5.5.
%   Wallace, P.T. and Capitaine, N., 2006, Astron. Astrophys. 459, 981
%     (the IAU 2006/2000A CIP and the X, Y, s parameterisation).
%   IAU SOFA release 20231011, iauXys06a, iauXys00a.
%   SOFA Tools for Earth Attitude, sofa_pn_c.pdf, sections 5.3 and 5.5.
%
% EXAMPLE
%   tt = referenceSystem.daySecondToEpoch([54195 43265.184], "TT");
%   [X, Y, s] = referenceSystem.cipCoordinates(tt);
%   assert(abs(X - 0.0007122638811749682) < 1e-15);
%
% KEYWORDS
%   CIP, CIO, celestial intermediate pole, precession, nutation, dX, dY, SOFA
%
% See also ROTATIONGCRSTOCIRS, ROTATIONITRSTOGCRS, INTERPOLATEEOP, READEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 21:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Eop struct = struct([])
        options.DeltaX (:,1) double = 0
        options.DeltaY (:,1) double = 0
        options.CipModel (1,1) string = ""
        options.Interpolant = []
    end

    if ~isempty(options.Interpolant)
        error('referenceSystem:cipCoordinates:notImplemented', ...
            ['An interpolated CIP path is deferred to v2.1 (prompt P19). ', ...
            'The name-value pair is declared now so that the signature is ', ...
            'final and no call site changes when it arrives; until then the ', ...
            'model is evaluated directly at every epoch.']);
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "TT"
        error('referenceSystem:cipCoordinates:wrongScale', ...
            ['The precession-nutation model is a function of TT and this ', ...
            'epoch is %s. Convert it deliberately with convertTimeScale.'], ...
            epoch.scale);
    end
    epochCount = numel(epoch.day);

    [deltaX, deltaY, cipModel] = localOffsets(options, epochCount);

    try
        [X, Y, s] = mexGateway('cip', epoch.day, epoch.sec, cipModel, ...
            deltaX, deltaY);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:cipCoordinates:gatewayMissing', ...
                ['The CIP series is evaluated in C through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end
end

% -------------------------------------------------------------------------

function [deltaX, deltaY, cipModel] = localOffsets(options, epochCount)
%LOCALOFFSETS Resolve the pole offsets and the frame they are referred to.
%
%   Local to this file: a package function's local functions see only their own
%   file, so nothing here calls a sibling (handover section C.5 rule 2).

    hasEop = ~isempty(options.Eop);
    hasExplicit = any(options.DeltaX ~= 0) || any(options.DeltaY ~= 0);

    if hasEop && hasExplicit
        error('referenceSystem:cipCoordinates:conflictingOffsets', ...
            ['Both an Eop struct and explicit DeltaX or DeltaY were given. ', ...
            'Supply one or the other, so that there is no question which ', ...
            'set of offsets reached the model.']);
    end

    modelName = options.CipModel;
    if hasEop
        deltaX = options.Eop.dX;
        deltaY = options.Eop.dY;
        if modelName == "" && isfield(options.Eop, 'meta') && ...
                isfield(options.Eop.meta, 'cipModel')
            modelName = string(options.Eop.meta.cipModel);
        end
    else
        deltaX = options.DeltaX;
        deltaY = options.DeltaY;
    end

    deltaX = localBroadcast(deltaX, epochCount, "DeltaX");
    deltaY = localBroadcast(deltaY, epochCount, "DeltaY");

    if any(deltaX ~= 0) || any(deltaY ~= 0)
        if modelName == ""
            error('referenceSystem:cipCoordinates:cipModelRequired', ...
                ['Pole offsets were supplied but the model they are ', ...
                'referred to is unknown. Set CipModel, or pass an Eop ', ...
                'struct whose meta.cipModel carries it. Guessing is what ', ...
                'finding C-2 was: the wrong choice shifts the pole by about ', ...
                '135 microarcseconds at 2025, which is 4 mm at the surface ', ...
                'and produces a rotation that looks entirely healthy.']);
        end
    elseif modelName == ""
        % No offsets, so the frame of the offsets cannot matter. Pick the model
        % actually evaluated rather than erroring on a question with no content.
        modelName = "IAU2006/2000A";
    end

    switch modelName
        case "IAU2006/2000A"
            cipModel = 2006;
        case "IAU2000A"
            cipModel = 2000;
        otherwise
            error('referenceSystem:cipCoordinates:unknownCipModel', ...
                ['CipModel is "%s"; it must be "IAU2006/2000A" or ', ...
                '"IAU2000A". These are the two frames an IERS series ', ...
                'publishes its celestial pole offsets in.'], modelName);
    end
end

% -------------------------------------------------------------------------

function value = localBroadcast(value, epochCount, name)
%LOCALBROADCAST Expand a scalar to one value per epoch, or check the length.

    if isscalar(value)
        value = repmat(value, epochCount, 1);
    elseif numel(value) ~= epochCount
        error('referenceSystem:cipCoordinates:sizeMismatch', ...
            '%s must be scalar or hold %d values; it holds %d.', ...
            name, epochCount, numel(value));
    end
end
