function [y, info] = convertCoordinates(x, fromFrame, toFrame, options)
%CONVERTCOORDINATES Single point of access across the L3 and L4 transformations.
%
%   y = convertCoordinates(x, fromFrame, toFrame) routes the Nx3 coordinates
%   through the shortest chain of L3 and L4 functions that carries them from
%   one frame or representation to the other.
%
%   y = convertCoordinates(x, "ITRF2014", "ITRF2020", 'Epoch', 2020.0) changes
%   the terrestrial realization; an epoch is REQUIRED for such a path and
%   REFUSED for one that has no notion of time.
%
%   adjacency = convertCoordinates('graph') returns the whole graph, each edge
%   carrying the time semantics it declares, for documentation and for testing.
%
%   [y, info] = convertCoordinates(...) also returns the path that was chosen,
%   never printing it: this is library code (section B.1 principle 10).
%
% INPUT ARGUMENTS
%   Name        Size   Type     Units      Description
%   ----        ----   ----     -----      -----------
%   x           Nx3    double   see below  Coordinates, one point per ROW, in
%                                          whatever fromFrame means. Nx2 for the
%                                          UTM and (with 'graph') no argument at
%                                          all.
%   fromFrame   1x1    string   -          Source frame or representation, or
%                                          the literal "graph" as the only
%                                          argument.
%   toFrame     1x1    string   -          Target frame or representation.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name           Size          Type            Default      Description
%   ----           ----          ----            -------      -----------
%   Epoch          1x1 or Nx1    double          []           Decimal year.
%                                                             Required by, and
%                                                             only by, a path
%                                                             containing a
%                                                             realization edge.
%   Origin         1x3 or Nx3    double          []           Local frame origin
%                                                             [lat lon h],
%                                                             required by an ENU
%                                                             or NED endpoint.
%   Zone           1x1 or Nx1    double          []           UTM zone, required
%                                                             leaving UTM.
%   Hemisphere     1x1 or Nx1    double          []           +1 or -1, required
%                                                             leaving UTM.
%   Ellipsoid      1x1           string|struct   "GRS80"      Name or struct.
%   AngleUnit      1x1           string          "rad"        Unit of every
%                                                             angular quantity
%                                                             in and out.
%   Velocity       Nx3           double          zeros(0,3)   Velocities carried
%                                                             through a
%                                                             realization edge.
%   Verbose        1x1           logical         false        Add the per-edge
%                                                             record to info.
%
% OUTPUT ARGUMENTS
%   Name             Size   Type     Units      Description
%   ----             ----   ----     -----      -----------
%   y                Nx3    double   see below  Coordinates in toFrame; Nx2 for
%                                               a UTM target.
%   info             1x1    struct   -          What the router did.
%   .path            1xM    string   -          Canonical node names traversed.
%   .timeKind        1xM-1  string   -          Per-edge time semantics.
%   .edgeFunction    1xM-1  string   -          The function each leg called.
%   .zone            Nx1    double   -          UTM zone, when the target is UTM.
%   .hemisphere      Nx1    double   -          +1 north, -1 south, likewise.
%   .latitudeBand    Nx1    string   -          MGRS band, likewise.
%   .velocity        Nx3    double   m/a        Velocity, when one was carried.
%   .edge            1xM-1  struct   -          Full edge records, 'Verbose' only.
%
% METHOD
%   THIS FUNCTION CONTAINS NO TRANSFORMATION MATHEMATICS. It holds an
%   adjacency, finds a shortest path by breadth-first search, checks that the
%   supplied arguments match what the WHOLE path needs, and only then calls the
%   L3 and L4 functions in turn. A layering test checks the claim mechanically
%   rather than by review (seam item 1), and the edge functions are called by
%   explicit qualified name rather than through str2func precisely so that the
%   layering scan can see the dependencies: both source scanners blank string
%   literals, so a dynamically dispatched toolbox would look dependency-free to
%   the one test that guards this rule.
%
%   EVERY EDGE DECLARES ITS TIME SEMANTICS (decision D29). The graph mixes two
%   kinds of edge: pure geometry, which has no notion of time at all, and the
%   similarity transforms between terrestrial realizations, which are
%   parameterised by a decimal year. A router that walked both without
%   distinguishing them would eventually apply an epoch to a leg that has none,
%   or omit it from a leg that needs one, and both legs would "succeed". The
%   timeKind of every edge on the chosen path is therefore collected BEFORE any
%   of them executes, and a mismatch is an error. Nothing is coerced, no
%   missing epoch is defaulted, no supplied one is ignored.
%
%   THE GRAPH IS TWO DELIBERATELY DISCONNECTED COMPONENTS, and this is the
%   least obvious decision in the file. The geometry nodes hang off the generic
%   earth-fixed Cartesian node ITRS; the realization nodes connect only to each
%   other. They are not joined, because joining them creates the path
%   ITRF2014 -> GEODETIC -> ITRF2020, which costs no epoch, raises no error and
%   silently reinterprets a coordinate as belonging to a realization it does
%   not - D29's failure mode arriving through the back door, past the very
%   check written to stop it. Shortest-path search would usually prefer the
%   direct realization edge, but "usually" is not a guarantee, and a guarantee
%   is available for free by not building the bridge. Requesting a path across
%   the two therefore raises :noPath, and the message names the two-call
%   recipe, which is what the user wanted anyway:
%
%       x2 = convertCoordinates(x1, "ITRF2014", "ITRF2020", 'Epoch', 2020.0);
%       g  = convertCoordinates(x2, "ITRS", "GEODETIC");
%
%   ITRS <-> GCRS IS NOT AN EDGE (decision D29). It is the one transformation
%   needing an epoch struct rather than a decimal year, an EOP table read from
%   disk - an L1 file dependency inside an L6 dispatcher, the only place the
%   call-downward rule is at risk - and it produces a rate the caller almost
%   always needs and this interface cannot return. Asking for GCRS or ECI
%   raises :useRotationFunction naming rotationItrsToGcrs and applyRotation.
%
%   RSW IS NOT AN EDGE EITHER, and this departs from the P15 prompt's node
%   list. An orbit frame is defined by a satellite STATE rather than by a frame
%   parameter, and its only edge would run from GCRS, which is excluded above -
%   so as a node it would be permanently unreachable and every request for it
%   would return :noPath, which says nothing useful. It raises
%   :useRotationFunction naming rotationGcrsToRsw instead. A good error beats a
%   dead node.
%
%   UTM IS LOSSY AND SAYS SO. The projection carries no height, so
%   utmToGeodetic returns two columns and a path leaving UTM cannot continue to
%   a three-column representation; the leg function raises its own
%   wrongPointSize, which names itself and is clearer than anything this
%   function could add. Leaving UTM also needs the zone and the hemisphere,
%   which cannot be recovered from a northing because the false northing makes
%   the hemispheres overlap.
%
% ACCURACY
%   The router introduces no error of its own: it neither computes nor rounds
%   anything, and each leg is executed exactly once with the caller's data. The
%   accuracy of a result is the composition of the ACCURACY blocks of the
%   functions named in info.edgeFunction, and a path of M legs accumulates M of
%   them.
%
%   The one thing worth stating quantitatively is that a chain is not free: the
%   round trip ITRS -> GEODETIC -> ITRS closes to 1.4e-09 m, which is
%   cartesianToGeodetic's own closure and not an addition by this function, and
%   a path through UTM closes only to the 7.4e-04 m of the Krueger series.
%   Shortest-path routing therefore also minimises accumulated error, which is
%   a consequence of the unweighted search rather than a design goal, and would
%   stop being true if any edge were ever weighted by anything but hop count.
%
% ERRORS
%   referenceSystem:convertCoordinates:unknownFrame
%   referenceSystem:convertCoordinates:noPath
%   referenceSystem:convertCoordinates:missingOption
%   referenceSystem:convertCoordinates:timeKindMismatch
%   referenceSystem:convertCoordinates:useRotationFunction
%   referenceSystem:convertCoordinates:unroutableEdge
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 4 for the terrestrial
%   frames and Ch. 5 for the transformation excluded here.
%   Z. Altamimi et al. (2023), ITRF2020, Journal of Geodesy 97(47).
%
% EXAMPLE
%   g  = referenceSystem.convertCoordinates(x, "ITRS", "GEODETIC");
%   x2 = referenceSystem.convertCoordinates(x, "ITRF2014", "ITRF2020", ...
%       'Epoch', 2020.0);
%   adjacency = referenceSystem.convertCoordinates('graph');
%
% KEYWORDS
%   dispatch, frame, ECEF, ITRS, ECI, GCRS, geodetic, ENU, NED, UTM, spherical,
%   ITRF, realization, conversion, graph
%
% See also CARTESIANTOGEODETIC, CONVERTITRF, ROTATIONITRSTOGCRS, APPLYROTATION.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 22:55 (CEST, UTC+02:00) - session S5, prompt P15
% -------------------------------------------------------------------------

    arguments
        x
        fromFrame (1,1) string = ""
        toFrame (1,1) string = ""
        options.Epoch double {mustBeReal} = []
        options.Origin double {mustBeReal} = []
        options.Zone double {mustBeReal} = []
        options.Hemisphere double {mustBeReal} = []
        options.Ellipsoid = "GRS80"
        options.AngleUnit (1,1) string {mustBeMember(options.AngleUnit, ...
            ["rad", "deg"])} = "rad"
        options.Velocity double {mustBeReal} = zeros(0, 3)
        options.Verbose (1,1) logical = false
    end

    adjacency = buildGraph();

    if (isstring(x) || ischar(x)) && strcmp(string(x), "graph")
        y = adjacency;
        info = struct('path', "graph", 'timeKind', string.empty(1, 0), ...
            'edgeFunction', string.empty(1, 0));
        return
    end

    source = canonicalNode(fromFrame, adjacency);
    target = canonicalNode(toFrame, adjacency);

    [nodePath, edgeIndex] = shortestPath(adjacency, source, target);
    % Written as a loop rather than arrayfun: a uniform-output arrayfun over a
    % string-valued function is a MATLAB semantic this file would be asserting
    % rather than measuring, and the loop is shorter than the check would be.
    timeKind = strings(1, numel(edgeIndex));
    edgeFunction = strings(1, numel(edgeIndex));
    for k = 1:numel(edgeIndex)
        timeKind(k) = adjacency.edge(edgeIndex(k)).timeKind;
        edgeFunction(k) = adjacency.edge(edgeIndex(k)).functionName;
    end

    % THE WHOLE PATH IS VALIDATED BEFORE ANY LEG RUNS (seam item 2). Checking
    % leg by leg as it executes would leave the caller with a partially
    % transformed array and an error naming a function they never called.
    requiresEpoch = any(strcmp(timeKind, "decimalYear"));
    epochSupplied = ~isempty(options.Epoch);
    if requiresEpoch && ~epochSupplied
        error('referenceSystem:convertCoordinates:timeKindMismatch', ...
            ['The path %s crosses %d realization edge(s), each of which is a ', ...
            'similarity transformation parameterised by a decimal year, and ', ...
            'no Epoch was supplied. There is no default: the parameters are ', ...
            'linear in time and an assumed epoch is a silent metre.'], ...
            strjoin(nodePath, " -> "), sum(strcmp(timeKind, "decimalYear")));
    end
    if ~requiresEpoch && epochSupplied
        error('referenceSystem:convertCoordinates:timeKindMismatch', ...
            ['An Epoch was supplied but the path %s is pure geometry: every ', ...
            'edge on it declares timeKind "none" and none can use a decimal ', ...
            'year. Accepting and ignoring it would hide a wrong request.'], ...
            strjoin(nodePath, " -> "));
    end
    requireOptions(adjacency, edgeIndex, options, nodePath);

    y = x;
    carriedVelocity = options.Velocity;
    zone = zeros(0, 1);
    hemisphere = zeros(0, 1);
    latitudeBand = string.empty(0, 1);

    for k = 1:numel(edgeIndex)
        edge = adjacency.edge(edgeIndex(k));
        [y, carriedVelocity, zone, hemisphere, latitudeBand] = applyEdge( ...
            edge, y, carriedVelocity, options, zone, hemisphere, latitudeBand);
    end

    if nargout < 2
        return
    end
    info = struct( ...
        'path', nodePath, ...
        'timeKind', timeKind, ...
        'edgeFunction', edgeFunction, ...
        'zone', zone, ...
        'hemisphere', hemisphere, ...
        'latitudeBand', latitudeBand, ...
        'velocity', carriedVelocity);
    if options.Verbose
        info.edge = adjacency.edge(edgeIndex);
    end
end

% -------------------------------------------------------------------------

function adjacency = buildGraph()
%BUILDGRAPH The whole graph, in one place, as data.
%   Edges are DATA and applyEdge is the only code that knows how to call them,
%   so the set of edges has exactly one authority. A contract test executes
%   every edge published here, which is what keeps the two in step.
%
%   BUILT ONCE PER SESSION AND CACHED. The graph is a pure function of this
%   file - fourteen realizations, twelve geometry edges, no input - so there
%   is nothing for a cache to go stale against, and MATLAB clears a persistent
%   when its own file is edited, which is the only way the answer could change.
%
%   IT WAS REBUILT ON EVERY CALL UNTIL SESSION S7, and the cost is a FIXED
%   2 to 3 ms on GLNXA64 and 20 to 39 ms on PCWIN64, independent of N. At a
%   million points that is under two per cent and invisible. At one point it
%   is the whole call, so a loop over ten thousand single-point conversions
%   spent between twenty seconds and six minutes assembling the same 194 edges.
%   Measured two ways that agree: the N = 1e6 benchmark against its own bare
%   leg, and the 194-call edge test divided by its call count.
%
%   THE COST IS NOT THE STRUCT GROWTH. The 182 realization edges were already
%   preallocated when this was investigated, and only the twelve geometry
%   edges grow - which is nothing. What it costs is 194 struct constructions
%   carrying five string fields each, plus a unique() over 388 strings. The
%   platform ratio said as much before the code was read: the arithmetic leg
%   differs 3.4x between the two hosts and this overhead differs about 10x,
%   which is the signature of allocation and string work rather than of
%   floating point.

    persistent cached
    if ~isempty(cached)
        adjacency = cached;
        return
    end

    realization = ["ITRF2020", "ITRF2014", "ITRF2008", "ITRF2005", ...
        "ITRF2000", "ITRF97", "ITRF96", "ITRF94", "ITRF93", "ITRF92", ...
        "ITRF91", "ITRF90", "ITRF89", "ITRF88"];

    edge = geometryEdge("ITRS", "GEODETIC", "cartesianToGeodetic", ...
        string.empty(1, 0));
    edge(end+1) = geometryEdge("GEODETIC", "ITRS", "geodeticToCartesian", ...
        string.empty(1, 0));
    edge(end+1) = geometryEdge("ITRS", "SPHERICAL", "cartesianToSpherical", ...
        string.empty(1, 0));
    edge(end+1) = geometryEdge("SPHERICAL", "ITRS", "sphericalToCartesian", ...
        string.empty(1, 0));
    edge(end+1) = geometryEdge("ITRS", "ENU", "cartesianToEnu", "Origin");
    edge(end+1) = geometryEdge("ENU", "ITRS", "enuToCartesian", "Origin");
    edge(end+1) = geometryEdge("ENU", "NED", "enuToNed", string.empty(1, 0));
    edge(end+1) = geometryEdge("NED", "ENU", "nedToEnu", string.empty(1, 0));
    edge(end+1) = geometryEdge("ENU", "AZIMUTHELEVATION", ...
        "enuToAzimuthElevation", string.empty(1, 0));
    edge(end+1) = geometryEdge("AZIMUTHELEVATION", "ENU", ...
        "azimuthElevationToEnu", string.empty(1, 0));
    edge(end+1) = geometryEdge("GEODETIC", "UTM", "geodeticToUtm", ...
        string.empty(1, 0));
    edge(end+1) = geometryEdge("UTM", "GEODETIC", "utmToGeodetic", ...
        ["Zone", "Hemisphere"]);

    % Every realization connects directly to every other, because convertItrf
    % already routes through ITRF2020 internally: a chain of realization hops
    % would apply its rounding twice. Preallocated rather than grown, since
    % fourteen realizations make 182 edges (section C.1).
    geometryCount = numel(edge);
    edge = [edge, repmat(edge(1), 1, numel(realization)*(numel(realization)-1))];
    written = geometryCount;
    for source = realization
        for target = realization
            if strcmp(source, target)
                continue
            end
            written = written + 1;
            edge(written) = struct('from', source, 'to', target, ...
                'functionName', "convertItrf", 'timeKind', "decimalYear", ...
                'requires', string.empty(1, 0));
        end
    end

    node = unique([string({edge.from}), string({edge.to})], 'stable');

    % RSW, RTN, GCRS and the rest are NOT aliases here: canonicalNode refuses
    % them by name before it reads this table, so listing them would be a dead
    % entry that a later reader would take for a supported route.
    aliasName = ["ECEF", "CARTESIAN", "IGS20", "IGS14", "IGB14", "IGS08", ...
        "IGB08", "IGS05", "IGS00", "IGB00"];
    aliasTarget = ["ITRS", "ITRS", "ITRF2020", "ITRF2014", "ITRF2014", ...
        "ITRF2008", "ITRF2008", "ITRF2005", "ITRF2000", "ITRF2000"];

    % Assigned field by field rather than through struct(): a struct ARRAY
    % passed as a value to struct() is a construction rule this file would be
    % assuming, and the assignment form has no such question.
    adjacency.node = node;
    adjacency.edge = edge;
    adjacency.aliasName = aliasName;
    adjacency.aliasTarget = aliasTarget;
    adjacency.realization = realization;

    % Stored last, so a failure part way through leaves nothing cached and the
    % next call rebuilds rather than serving a half-built graph.
    cached = adjacency;
end

function record = geometryEdge(from, to, functionName, requires)
%GEOMETRYEDGE One pure-geometry edge: no notion of time anywhere on it.

    record = struct('from', from, 'to', to, 'functionName', functionName, ...
        'timeKind', "none", 'requires', requires);
end

function canonical = canonicalNode(name, adjacency)
%CANONICALNODE Resolve an alias, refuse the excluded frames by name.

    requested = upper(strtrim(name));
    if strcmp(requested, "")
        error('referenceSystem:convertCoordinates:unknownFrame', ...
            ['No frame was named. Call convertCoordinates(x, from, to) or ', ...
            'convertCoordinates(''graph'') to see the frames.']);
    end

    celestial = ["GCRS", "ECI", "CIRS", "TIRS", "ICRS", "BCRS"];
    if any(strcmp(requested, celestial))
        error('referenceSystem:convertCoordinates:useRotationFunction', ...
            ['"%s" is a celestial frame and is deliberately not in this ', ...
            'graph. The terrestrial-to-celestial transformation is not ', ...
            'geometry: it needs an epoch struct rather than a decimal year, ', ...
            'it needs an Earth orientation table read from disk, and it ', ...
            'produces a rate that you will need and that this interface has ', ...
            'no way to return. Routing it here would silently discard Rdot ', ...
            'to save one line. Use:\n', ...
            '    [R, Rdot] = referenceSystem.rotationItrsToGcrs(t, ''Eop'', eop);\n', ...
            '    [rGcrs, vGcrs] = referenceSystem.applyRotation(R, Rdot, r, v);\n', ...
            'and referenceSystem.invertRotation or the ''Inverse'' option of ', ...
            'applyRotation for the other direction.'], name);
    end

    orbit = ["RSW", "RTN", "LVLH", "NTW"];
    if any(strcmp(requested, orbit))
        error('referenceSystem:convertCoordinates:useRotationFunction', ...
            ['"%s" is an orbit frame defined by a satellite STATE, not by a ', ...
            'frame parameter, so it cannot be an endpoint of a coordinate ', ...
            'graph: the same point has a different orbit frame for every ', ...
            'satellite that sees it. Its one edge would run from the GCRS, ', ...
            'which is excluded above. Use:\n', ...
            '    R = referenceSystem.rotationGcrsToRsw(r, v, ''Frame'', "%s");\n', ...
            '    y = referenceSystem.applyRotation(R, x);'], name, requested);
    end

    isAlias = strcmp(requested, adjacency.aliasName);
    if any(isAlias)
        requested = adjacency.aliasTarget(isAlias);
    end
    isNode = strcmp(requested, upper(adjacency.node));
    if ~any(isNode)
        error('referenceSystem:convertCoordinates:unknownFrame', ...
            ['"%s" is not a frame or representation in this graph. ', ...
            'Representations: %s. Realizations: %s. Aliases: %s.'], name, ...
            strjoin(adjacency.node(~startsWith(adjacency.node, "ITRF")), ", "), ...
            strjoin(adjacency.realization, ", "), ...
            strjoin(adjacency.aliasName, ", "));
    end
    canonical = adjacency.node(isNode);
    canonical = canonical(1);
end

function [nodePath, edgeIndex] = shortestPath(adjacency, source, target)
%SHORTESTPATH Breadth-first search over an unweighted graph.
%   Unweighted because every edge is one function call and there is no
%   meaningful cost to prefer between them. Breadth-first therefore returns a
%   path of the fewest legs, which is also the fewest accumulated ACCURACY
%   blocks - a consequence, not a design goal.

    if strcmp(source, target)
        nodePath = source;
        edgeIndex = zeros(1, 0);
        return
    end

    node = adjacency.node;
    fromNode = string({adjacency.edge.from});
    toNode = string({adjacency.edge.to});

    predecessorNode = zeros(1, numel(node));
    predecessorEdge = zeros(1, numel(node));
    visited = false(1, numel(node));
    sourceIndex = find(strcmp(node, source), 1);
    targetIndex = find(strcmp(node, target), 1);
    visited(sourceIndex) = true;
    % A breadth-first queue visits each node at most once, so numel(node) is
    % an exact bound and the queue never grows (section C.1).
    queue = zeros(1, numel(node));
    queue(1) = sourceIndex;
    head = 1;
    tail = 1;

    while head <= tail
        current = queue(head);
        head = head + 1;
        if current == targetIndex
            break
        end
        outgoing = find(strcmp(fromNode, node(current)));
        for k = outgoing
            next = find(strcmp(node, toNode(k)), 1);
            if visited(next)
                continue
            end
            visited(next) = true;
            predecessorNode(next) = current;
            predecessorEdge(next) = k;
            tail = tail + 1;
            queue(tail) = next;
        end
    end

    if ~visited(targetIndex)
        error('referenceSystem:convertCoordinates:noPath', ...
            ['No path from "%s" to "%s". The graph is two deliberately ', ...
            'disconnected components: the geometric representations hang ', ...
            'off the generic earth-fixed node ITRS, and the terrestrial ', ...
            'realizations connect only to each other. They are NOT joined, ', ...
            'because a join would create paths such as ', ...
            'ITRF2014 -> GEODETIC -> ITRF2020 that need no epoch, raise no ', ...
            'error and silently reinterpret the realization. Do it in two ', ...
            'calls instead, which is explicit about which step needs the ', ...
            'epoch:\n', ...
            '    x2 = convertCoordinates(x1, "ITRF2014", "ITRF2020", ''Epoch'', 2020.0);\n', ...
            '    g  = convertCoordinates(x2, "ITRS", "GEODETIC");'], ...
            source, target);
    end

    % A simple path visits at most every node once, so the walk back is
    % preallocated to that bound and trimmed.
    edgeBuffer = zeros(1, numel(node));
    nodeBuffer = strings(1, numel(node)+1);
    nodeBuffer(end) = target;
    walker = targetIndex;
    legCount = 0;
    while walker ~= sourceIndex
        legCount = legCount + 1;
        edgeBuffer(end-legCount+1) = predecessorEdge(walker);
        walker = predecessorNode(walker);
        nodeBuffer(end-legCount) = node(walker);
    end
    edgeIndex = edgeBuffer(end-legCount+1:end);
    nodePath = nodeBuffer(end-legCount:end);
end

function requireOptions(adjacency, edgeIndex, options, nodePath)
%REQUIREOPTIONS Refuse a path whose legs need an option that was not supplied.
%   Collected over the WHOLE path before anything executes, for the same
%   reason as the timeKind check: a half-transformed array is worse than a
%   refusal.

    needed = string.empty(1, 0);
    for k = edgeIndex
        needed = [needed, adjacency.edge(k).requires];  %#ok<AGROW>
    end
    needed = unique(needed, 'stable');

    explanation = struct( ...
        'Origin', ['a local level frame is defined by its origin, and there ' ...
        'is no sensible default for one'], ...
        'Zone', ['a UTM easting and northing mean nothing without the zone ' ...
        'they were computed in'], ...
        'Hemisphere', ['the false northing makes the two hemispheres ' ...
        'overlap, so it cannot be recovered from the northing']);

    for k = 1:numel(needed)
        name = needed(k);
        if ~isempty(options.(name))
            continue
        end
        error('referenceSystem:convertCoordinates:missingOption', ...
            ['The path %s needs the ''%s'' option: %s.'], ...
            strjoin(nodePath, " -> "), name, explanation.(name));
    end
end

function [y, velocity, zone, hemisphere, latitudeBand] = applyEdge(edge, x, ...
        velocity, options, zone, hemisphere, latitudeBand)
%APPLYEDGE Call the one L3 or L4 function this edge names.
%   Explicit qualified calls, not str2func: both source scanners blank string
%   literals, so dynamic dispatch would make this file look dependency-free to
%   the layering test that is the whole point of the layering rule.
%   Section C.5 rule 6 permits str2func with a qualified name; it is declined
%   here for the stronger property.

    switch edge.functionName
        case "cartesianToGeodetic"
            y = referenceSystem.cartesianToGeodetic(x, ...
                'Ellipsoid', options.Ellipsoid, 'AngleUnit', options.AngleUnit);
        case "geodeticToCartesian"
            y = referenceSystem.geodeticToCartesian(x, ...
                'Ellipsoid', options.Ellipsoid, 'AngleUnit', options.AngleUnit);
        case "cartesianToSpherical"
            y = referenceSystem.cartesianToSpherical(x, ...
                'AngleUnit', options.AngleUnit);
        case "sphericalToCartesian"
            y = referenceSystem.sphericalToCartesian(x, ...
                'AngleUnit', options.AngleUnit);
        case "cartesianToEnu"
            y = referenceSystem.cartesianToEnu(x, options.Origin, ...
                'Ellipsoid', options.Ellipsoid, 'AngleUnit', options.AngleUnit);
        case "enuToCartesian"
            y = referenceSystem.enuToCartesian(x, options.Origin, ...
                'Ellipsoid', options.Ellipsoid, 'AngleUnit', options.AngleUnit);
        case "enuToNed"
            y = referenceSystem.enuToNed(x);
        case "nedToEnu"
            y = referenceSystem.nedToEnu(x);
        case "enuToAzimuthElevation"
            y = referenceSystem.enuToAzimuthElevation(x, ...
                'AngleUnit', options.AngleUnit);
        case "azimuthElevationToEnu"
            y = referenceSystem.azimuthElevationToEnu(x, ...
                'AngleUnit', options.AngleUnit);
        case "geodeticToUtm"
            [y, zone, hemisphere, latitudeBand] = ...
                referenceSystem.geodeticToUtm(x, 'Ellipsoid', ...
                options.Ellipsoid, 'AngleUnit', options.AngleUnit);
        case "utmToGeodetic"
            y = referenceSystem.utmToGeodetic(x, options.Zone, ...
                options.Hemisphere, 'Ellipsoid', options.Ellipsoid, ...
                'AngleUnit', options.AngleUnit);
        case "convertItrf"
            [y, velocity] = referenceSystem.convertItrf(x, edge.from, ...
                edge.to, options.Epoch, 'Velocity', velocity);
        otherwise
            error('referenceSystem:convertCoordinates:unroutableEdge', ...
                ['The graph publishes an edge %s -> %s calling "%s", and ', ...
                'this function has no branch for it. That is an internal ', ...
                'inconsistency between the edge table and its execution, ', ...
                'and it is guarded rather than left to fail as an ', ...
                'unassigned output. The contract test that executes every ', ...
                'published edge is what proves it cannot happen.'], ...
                edge.from, edge.to, edge.functionName);
    end
end
