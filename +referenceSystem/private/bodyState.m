function [position, velocity, info] = bodyState(body, epoch, options, ...
        origin, functionName)
%BODYSTATE Shared implementation of barycentricBodyState and geocentricBodyState.
%
%   [position, velocity, info] = bodyState(body, epoch, options, origin, name)
%
%   PACKAGE-PRIVATE, AND THE SINGLE IMPLEMENTATION OF THE ADAPTER. The two
%   public functions differ in exactly one argument - the origin - and in what
%   their ACCURACY blocks are entitled to claim. Keeping two help blocks and one
%   body is the arrangement rsRotationItrsToGcrs and rsRotationItrsToGcrsFromCip
%   already use in C: two entry points, one assembly.
%
%   IT RAISES IDENTIFIERS NAMING ITS CALLER, NOT ITSELF. Section C.2 binds an
%   identifier to the function the user called, and the user never calls this
%   one; carryEpoch sets the same precedent. functionName is therefore not
%   cosmetic and must be the caller's own name.
%
% INPUT ARGUMENTS
%   Name           Size   Type      Units  Description
%   ----           ----   ----      -----  -----------
%   body           1x1    string    -      Body name, any case. Validated here.
%   epoch          1x1    struct    -      Epoch struct, N entries. Validated here.
%   options        1x1    struct    -      Source and Ephemeris, from the caller's
%                                          arguments block.
%   origin         1x1    string    -      "barycentre" or "geocentre".
%   functionName   1x1    string    -      Public caller, for the identifiers.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type     Units  Description
%   ----       ----   ----     -----  -----------
%   position   3xN    double   m      One column per epoch.
%   velocity   3xN    double   m/s    One column per epoch.
%   info       1x1    struct   -      Documented in the two public help blocks.
%
% METHOD
%   Resolve the body against ephemerisBodies, convert the epoch to TDB, call the
%   provider, reshape the 6xN block the gateway returns, and assemble info.
%
%   THE STATUS BECOMES AT MOST ONE WARNING PER CALL, WHATEVER N IS. A thousand
%   epochs outside the model interval are one fact about the call, and a
%   thousand identical warnings are how a real one gets lost.
%
% ACCURACY
%   Not applicable; this function performs no arithmetic of its own beyond a
%   reshape. Every number it returns came from the provider and every accuracy
%   figure from ephemerisBodies.
%
% ERRORS
%   referenceSystem:<caller>:unknownBody
%   referenceSystem:<caller>:wrongScale
%   referenceSystem:<caller>:gatewayMissing
%   referenceSystem:<caller>:providerNotAvailable
%
% REFERENCES
%   Handover sections C.2 (identifiers), C.5 rule 2 (private helpers), C.6.
%
% EXAMPLE
%   % Not called directly; see barycentricBodyState.
%
% KEYWORDS
%   ephemeris, adapter, provider, BCRS, private
%
% See also BARYCENTRICBODYSTATE, GEOCENTRICBODYSTATE, EPHEMERISBODIES.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 10:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    registry = referenceSystem.ephemerisBodies(Source = options.Source, ...
        Ephemeris = options.Ephemeris);

    row = find(strcmpi(registry.Body, body), 1);
    if isempty(row)
        error(sprintf('referenceSystem:%s:unknownBody', functionName), ...
            ['Body "%s" is not supplied by source "%s". Supported: %s. ', ...
            'ephemerisBodies lists them with their accuracy.'], ...
            body, options.Source, strjoin(registry.Body, ", "));
    end
    entry = registry(row, :);

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale == "UT1"
        error(sprintf('referenceSystem:%s:wrongScale', functionName), ...
            ['The epoch is UT1, which reaches TDB only through Delta UT1. ', ...
            'This function does not accept Delta UT1, and taking it as zero ', ...
            'is a silent error of up to 0.9 s - 27 km of Earth motion, five ', ...
            'times the provider''s own error. Convert deliberately with ', ...
            'convertTimeScale(epoch, "TDB", DeltaUt1 = ...) first.']);
    end
    tdb = referenceSystem.convertTimeScale(epoch, "TDB");

    originIndex = double(origin == "geocentre");

    switch lower(options.Source)
        case "sofa"
            [state, status] = localSofaState(tdb, entry.BodyIndex, ...
                originIndex, functionName);
            frameBiasApplied = false;
        case "mice"
            [state, status] = localMiceState(tdb, entry, originIndex, ...
                options.Ephemeris, functionName);
            frameBiasApplied = true;
        otherwise
            % Unreachable: ephemerisBodies has already rejected it above. Kept
            % so that a source added there without an arm here fails loudly.
            error(sprintf('referenceSystem:%s:providerNotAvailable', ...
                functionName), 'Source "%s" has no arm here.', options.Source);
    end

    position = state(1:3, :);
    velocity = state(4:6, :);

    localReportStatus(status, functionName);

    if origin == "geocentre"
        frameName = "BCRS coordinate difference from the geocentre";
        originName = "Earth centre of mass";
    else
        frameName = "BCRS";
        originName = "solar system barycentre";
    end

    info = struct( ...
        'body', entry.Body, ...
        'naifId', entry.NaifId, ...
        'source', lower(options.Source), ...
        'model', entry.Model, ...
        'frame', frameName, ...
        'origin', originName, ...
        'epochScale', "TDB", ...
        'positionError', entry.PositionError, ...
        'velocityError', entry.VelocityError, ...
        'frameBiasApplied', frameBiasApplied);
end

% =========================== local functions ===========================

function [state, status] = localSofaState(tdb, bodyIndex, originIndex, functionName)
%LOCALSOFASTATE The bundled provider, through the MEX gateway.

    try
        [state, status] = mexGateway('bodystate', tdb.day, tdb.sec, ...
            bodyIndex, originIndex);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error(sprintf('referenceSystem:%s:gatewayMissing', functionName), ...
                ['The SOFA planetary and lunar theories are evaluated in C ', ...
                'through the MEX gateway, which is not built. Run ', ...
                'referenceSystem.buildMex once.']);
        end
        rethrow(cause);
    end
end

function [state, status] = localMiceState(tdb, entry, originIndex, ...
        ephemeris, functionName)
%LOCALMICESTATE The NAIF provider, through cspice_spkezr.
%
%   ET IS PASSED, NOT A CALENDAR STRING, AND NO LEAPSECONDS KERNEL IS LOADED.
%   cspice_spkezr takes TDB seconds past J2000 directly and convertTimeScale has
%   already produced TDB, so furnishing naif0012.tls would install a second
%   leap-second authority beside leapSecondTable, observed by whichever code
%   happened to ask SPICE instead of the package. That is decision D89 and it is
%   why this function converts in MATLAB and hands over a number.

    if isempty(ephemeris)
        error(sprintf('referenceSystem:%s:providerNotAvailable', functionName), ...
            ['Source "mice" needs a furnished kernel set. Call ', ...
            'readEphemeris first and pass its result as Ephemeris.']);
    end
    if exist('cspice_spkezr', 'file') ~= 2 && exist('cspice_spkezr', 'file') ~= 3
        error(sprintf('referenceSystem:%s:providerNotAvailable', functionName), ...
            ['Source "mice" needs the NAIF MICE toolkit on the MATLAB path ', ...
            'and cspice_spkezr was not found. MICE is free and is at ', ...
            'https://naif.jpl.nasa.gov/naif/toolkit_MATLAB.html . The ', ...
            'bundled Source "sofa" needs nothing and works out of the box, ', ...
            'at the accuracy ephemerisBodies tabulates.']);
    end
    ephemerisPool("require", ephemeris, functionName);

    constants = referenceSystem.iersConstants();
    ephemerisTime = (tdb.day - constants.mjdJ2000)*constants.secondsPerDay + ...
        tdb.sec;
    observer = "SSB";
    if originIndex == 1
        observer = "EARTH";
    end

    % SPICE returns km and km/s; the SI boundary of this toolbox is metres, and
    % the factor lives here so that no caller repeats it.
    stateKm = cspice_spkezr(char(string(entry.NaifId)), ephemerisTime(:).', ...
        'J2000', 'NONE', char(observer));
    state = stateKm*1000;
    status = zeros(numel(ephemerisTime), 1);
end

function localReportStatus(status, functionName)
%LOCALREPORTSTATUS One warning per call, whatever N is.

    if any(status == 1)
        warning(sprintf('referenceSystem:%s:outsideModelRange', functionName), ...
            ['%d of %d epochs lie outside the interval over which the ', ...
            'model''s stated accuracy holds. The state is still returned; ', ...
            'ephemerisBodies documents how fast the error grows outside it.'], ...
            sum(status == 1), numel(status));
    end
    if any(status == 2)
        warning(sprintf('referenceSystem:%s:seriesNotConverged', functionName), ...
            ['The planetary series failed to converge at %d of %d epochs. ', ...
            'Treat those states as unusable rather than merely degraded.'], ...
            sum(status == 2), numel(status));
    end
end
