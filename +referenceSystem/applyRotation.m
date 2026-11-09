function [r2, v2, a2] = applyRotation(R, second, third, fourth, fifth, sixth, options)
%APPLYROTATION Apply a rotation and its derivatives to a state.
%
%   r2 = applyRotation(R, r)
%   [r2, v2] = applyRotation(R, Rdot, r, v)
%   [r2, v2, a2] = applyRotation(R, Rdot, Rddot, r, v, a)
%   ... = applyRotation(..., 'Inverse', true)
%
%   Rotates a position, a position and velocity, or a position, velocity and
%   acceleration from one frame to another, carrying the frame-rate terms that
%   a rotating frame demands. The call shape is chosen by the number of
%   arguments: d rotation matrices followed by d vectors, for d = 1, 2 or 3.
%
% INPUT ARGUMENTS
%   Name    Size     Type     Units    Description
%   ----    ----     ----     -----    -----------
%   R       3x3xN    double   -        Rotation, one page per epoch, or 3x3 for
%                                      a single epoch or one rotation applied
%                                      to every column.
%   Rdot    3x3xN    double   1/s      First time derivative, depth 2 and 3.
%   Rddot   3x3xN    double   1/s^2    Second time derivative, depth 3.
%   r       3xN      double   any      Position, one column per epoch.
%   v       3xN      double   any/s    Velocity, depth 2 and 3.
%   a       3xN      double   any/s^2  Acceleration, depth 3.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name      Size   Type      Default   Description
%   ----      ----   ----      -------   -----------
%   Inverse   1x1    logical   false     Apply the transposed rotation, that is
%                                        the reverse transformation.
%
% OUTPUT ARGUMENTS
%   Name   Size   Type     Units    Description
%   ----   ----   ----     -----    -----------
%   r2     3xN    double   any      Rotated position.
%   v2     3xN    double   any/s    Rotated velocity, depth 2 and 3.
%   a2     3xN    double   any/s^2  Rotated acceleration, depth 3.
%
% METHOD
%   The transformation of a state between frames in relative rotation is
%
%       r2 = R r
%       v2 = R v + Rdot r
%       a2 = R a + 2 Rdot v + Rddot r
%
%   THE FACTOR 2 ON THE MIDDLE TERM OF THE ACCELERATION is the classic error in
%   this formula and it has its own test. It is the Coriolis-like term, and it
%   carries a 2 because differentiating R v twice produces Rdot v from the
%   product rule in two places. Dropping it, or writing 1 instead of 2, gives
%   an acceleration that is wrong by roughly the Coriolis acceleration itself -
%   about 0.1 m/s^2 at low Earth orbit, which is nine orders above the GRACE
%   accelerometer noise floor and would nevertheless leave every orthogonality
%   check in this toolbox perfectly happy.
%
%   ONE FUNCTION, NOT TWO (decision D23). The inverse relations are the same
%   formulas with every matrix transposed,
%
%       r1 = R' r2,   v1 = R' v2 + Rdot' r2,   a1 = R' a2 + 2 Rdot' v2 + Rddot' r2
%
%   so 'Inverse' does not select a second code path. It selects the 'transpose'
%   flag of pagemtimes, which the BLAS honours without forming a transposed
%   copy: zero extra flops and zero extra allocation. There is consequently no
%   separate inverse implementation to test, only transposed inputs, and a
%   round-trip test is a real check rather than a tautology.
%
%   CALL SHAPE AND 'Inverse'. The number of arguments chooses the shape, and
%   the shape is read from which optional slots were filled rather than from
%   nargin, which counts a name-value pair as two arguments and therefore
%   cannot distinguish applyRotation(R, r, 'Inverse', true) from
%   applyRotation(R, Rdot, r, v). The first release of this function used
%   nargin and silently returned the forward rotation for both round-trip
%   calls; the failure is recorded in the handover revision log because the
%   symptom - a plausible wrong state rather than an error - is the class of
%   defect this toolbox exists to refuse.
%
%   VECTORISATION. The multiplication is a single pagemtimes over all N epochs.
%   A 3x3 R with a 3xN r applies one rotation to every column, which is the
%   common case of a single epoch with many points; a 3x3xN R with a 3xN r
%   applies page k to column k. Mixed shapes that mean neither of those are an
%   error rather than a broadcast, because a silent broadcast of the wrong axis
%   produces a full-size result that is wrong everywhere.
%
% ACCURACY
%   The arithmetic is three inner products of length three per vector, so the
%   relative error is a few units in the last place of the inputs, below
%   1e-15 relative. Nothing here is approximated.
%
%   A round trip through the forward and inverse transformation returns the
%   original state to better than 1e-15 relative in position and velocity,
%   measured over the epoch sweep in TestRotation.
%
% ERRORS
%   referenceSystem:applyRotation:wrongArgumentCount
%   referenceSystem:applyRotation:wrongMatrixSize
%   referenceSystem:applyRotation:wrongVectorSize
%   referenceSystem:applyRotation:sizeMismatch
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.1.
%   Montenbruck, O. and Gill, E., 2000, Satellite Orbits, Sec. 5.3.
%
% EXAMPLE
%   [R, Rdot] = referenceSystem.rotationItrsToGcrs(epoch, 'Eop', eop);
%   [rGcrs, vGcrs] = referenceSystem.applyRotation(R, Rdot, rItrs, vItrs);
%   [back, backRate] = referenceSystem.applyRotation(R, Rdot, rGcrs, vGcrs, ...
%       'Inverse', true);
%
% KEYWORDS
%   rotation, pagemtimes, velocity, Coriolis, frame transformation, state
%
% See also ROTATIONITRSTOGCRS, INVERTROTATION, ROTATIONGCRSTOCIRS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 22:25 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        R {mustBeNumeric}
        second {mustBeNumeric}
        third {mustBeNumeric} = zeros(3, 0)
        fourth {mustBeNumeric} = zeros(3, 0)
        fifth {mustBeNumeric} = zeros(3, 0)
        sixth {mustBeNumeric} = zeros(3, 0)
        options.Inverse (1,1) logical = false
    end

    % THE DEPTH IS DETERMINED BY WHICH SLOTS WERE FILLED, NEVER BY nargin.
    %
    % The first version of this function computed it from nargin and the first
    % run falsified it: both round trips through 'Inverse' returned a wrong
    % state instead of erroring. nargin in a function that mixes optional
    % positional arguments with name-value arguments counts the name and the
    % value too, so applyRotation(R, r, 'Inverse', true) reported four
    % positional arguments when two were given, and the function silently
    % dispatched to the wrong shape. Reading the defaults instead is true
    % under either counting rule, which is the point: this is the only
    % function in the toolbox that mixes the two argument kinds, and it must
    % not depend on a MATLAB semantic that has already been guessed wrong once
    % (handover obligations O9 and O10).
    %
    % The declared class is mustBeNumeric and not double for the same reason.
    % A double declaration CONVERTS rather than validates, so a stray
    % 'Inverse' bound positionally would arrive as the 1x7 double of its
    % characters and be indistinguishable from data. mustBeNumeric refuses it,
    % which either pushes MATLAB to the name-value reading or produces a loud
    % validation error naming the argument. Silence was the defect.
    supplied = [~isempty(third), ~isempty(fourth), ~isempty(fifth), ...
        ~isempty(sixth)];

    if isequal(supplied, [false false false false])
        matrix = {R};
        vector = {second};
    elseif isequal(supplied, [true true false false])
        matrix = {R, second};
        vector = {third, fourth};
    elseif isequal(supplied, [true true true true])
        matrix = {R, second, third};
        vector = {fourth, fifth, sixth};
    else
        error('referenceSystem:applyRotation:wrongArgumentCount', ...
            ['applyRotation takes 2, 4 or 6 numeric arguments - d rotation ', ...
            'matrices followed by d vectors, for d = 1, 2 or 3 - and %d ', ...
            'were given. The shapes are applyRotation(R, r), ', ...
            'applyRotation(R, Rdot, r, v) and applyRotation(R, Rdot, ', ...
            'Rddot, r, v, a).'], 2 + sum(supplied));
    end

    depth = numel(matrix);
    for k = 1:depth
        matrix{k} = localCheckMatrix(matrix{k}, k);
        vector{k} = localCheckVector(vector{k}, k);
    end

    pageCount = max(cellfun(@(m) size(m, 3), matrix));
    columnCount = max(cellfun(@(v) size(v, 2), vector));
    if pageCount ~= 1 && columnCount ~= 1 && pageCount ~= columnCount
        error('referenceSystem:applyRotation:sizeMismatch', ...
            ['The rotation has %d pages and the state has %d columns. They ', ...
            'must agree, or one of them must be single, so that there is ', ...
            'no question which rotation was applied to which point.'], ...
            pageCount, columnCount);
    end

    if options.Inverse
        transposeFlag = 'transpose';
    else
        transposeFlag = 'none';
    end

    % r2 = R r, and with the inverse flag R' r. pagemtimes takes the transpose
    % through the BLAS flag, so no transposed copy is ever formed.
    r2 = localProduct(matrix{1}, transposeFlag, vector{1});

    if depth >= 2
        v2 = localProduct(matrix{1}, transposeFlag, vector{2}) + ...
            localProduct(matrix{2}, transposeFlag, vector{1});
    end
    if depth >= 3
        a2 = localProduct(matrix{1}, transposeFlag, vector{3}) + ...
            2 * localProduct(matrix{2}, transposeFlag, vector{2}) + ...
            localProduct(matrix{3}, transposeFlag, vector{1});
    end
end

% -------------------------------------------------------------------------

function product = localProduct(matrix, transposeFlag, vector)
%LOCALPRODUCT One page-wise matrix-vector product, shaped back to 3xN.

    pageProduct = pagemtimes(matrix, transposeFlag, ...
        reshape(vector, 3, 1, []), 'none');
    product = reshape(pageProduct, 3, []);
end

% -------------------------------------------------------------------------

function matrix = localCheckMatrix(matrix, position)
%LOCALCHECKMATRIX Require a 3x3 or 3x3xN rotation.

    if size(matrix, 1) ~= 3 || size(matrix, 2) ~= 3 || ndims(matrix) > 3
        error('referenceSystem:applyRotation:wrongMatrixSize', ...
            'Rotation argument %d must be 3x3 or 3x3xN; it is %s.', ...
            position, mat2str(size(matrix)));
    end
end

% -------------------------------------------------------------------------

function vector = localCheckVector(vector, position)
%LOCALCHECKVECTOR Require a 3xN state, accepting a single 3x1 column.

    if size(vector, 1) ~= 3 || ~ismatrix(vector)
        error('referenceSystem:applyRotation:wrongVectorSize', ...
            ['State argument %d must be 3xN with one column per point; it ', ...
            'is %s. A 3xN layout and not Nx3: the columns are the vectors, ', ...
            'which is what pagemtimes multiplies.'], ...
            position, mat2str(size(vector)));
    end
end
