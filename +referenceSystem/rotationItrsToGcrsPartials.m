function [dRdXp, dRdYp, dRdDeltaUt1, info, dRdotdXp, dRdotdYp, ...
        dRdotdDeltaUt1] = rotationItrsToGcrsPartials(epoch, options)
%ROTATIONITRSTOGCRSPARTIALS Partials of the ITRS-to-GCRS rotation w.r.t. EOP.
%
%   [dRdXp, dRdYp, dRdDeltaUt1] = rotationItrsToGcrsPartials(epoch, Eop = eop)
%   [..., info] = rotationItrsToGcrsPartials(...)
%   [..., info, dRdotdXp, dRdotdYp, dRdotdDeltaUt1] = rotationItrsToGcrsPartials(...)
%
%   For estimating Earth orientation parameters alongside an orbit, or for
%   propagating their formal errors into a state. All three rotation partials
%   are ANALYTIC and cost about as much as one extra matrix product each.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, UTC or convertible.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name              Size   Type      Default  Description
%   ----              ----   ----      -------  -----------
%   Eop               1x1    struct    none     Series from readEop. Required.
%   CipModel          1x1    string    ""       Frame of the pole offsets:
%                                               "IAU2006/2000A" or "IAU2000A".
%                                               Empty takes it from the series'
%                                               own metadata, which is the right
%                                               default because the series
%                                               declares its frame.
%   DifferenceStep    1x1    double    200      Half-offset h of the central
%                                               difference in seconds, for the
%                                               RATE partials only: they sample
%                                               at t-h and t+h and divide by
%                                               2h, EXACTLY the meaning the
%                                               same option has in
%                                               rotationItrsToGcrs (D112).
%                                               Ignored when the rate partials
%                                               are not requested.
%   ApplyTidalCorrections 1x1 logical  true     Sub-daily EOP corrections.
%
% OUTPUT ARGUMENTS
%   Name              Size    Type     Units      Description
%   ----              ----    ----     -----      -----------
%   dRdXp             3x3xN   double   1/rad      d R / d xp.
%   dRdYp             3x3xN   double   1/rad      d R / d yp.
%   dRdDeltaUt1       3x3xN   double   1/s        d R / d Delta UT1.
%   info              1x1     struct   -          Fields listed below.
%   dRdotdXp          3x3xN   double   1/(rad s)  d Rdot / d xp.
%   dRdotdYp          3x3xN   double   1/(rad s)  d Rdot / d yp.
%   dRdotdDeltaUt1    3x3xN   double   1/s^2      d Rdot / d Delta UT1.
%   .cipModel         1x1     string   -          Model actually used.
%   .differenceStep   1x1     double   s          Step used for the rate
%                                                 partials, NaN if not asked for.
%   .rateConstruction 1x1     string   -          How the rate partials were
%                                                 formed. See METHOD.
%   .polarMotionUnits 1x1     string   -          "radian", stated because the
%                                                 series is published in arcsec.
%
%   OUTPUTS ARE nargout-GATED AND ORDERED BY COST (design principle 15). The
%   three rotation partials are analytic and nearly free, info is free, and the
%   three rate partials each need two more evaluations - so asking for FIVE
%   outputs is where the cost changes.
%
%   info SITS FOURTH AND NOT LAST, WHICH DEPARTS FROM rotationItrsToGcrs ON
%   PURPOSE. There, the outputs are one series of increasing derivative order
%   and info is genuinely last and free. Here there are two GROUPS, and burying
%   info behind the expensive one makes the cheap path unable to report itself:
%   with info seventh, asking for provenance would trip the gate and compute
%   all three rate partials, and info.differenceStep = NaN - the value that
%   says no rate was computed - would be unreachable. Principle 15 orders by
%   increasing cost, and info costs nothing.
%
% METHOD
%   The rotation is assembled as R = (W Z Q)' - polar motion, then Earth
%   rotation, then precession-nutation, transposed because rsCore stores the
%   celestial-to-terrestrial product. Each EOP enters exactly one factor, which
%   is why the partials are analytic and cheap:
%
%     W = Rx(-yp) Ry(-xp) Rz(s')        [SOFA iauPom00, read from pom00.c]
%     Z = Rz(ERA)
%     Q = C2I(X, Y, s)
%
%     dR/dxp        = ( Rx(-yp) * (-Ry'(-xp)) * Rz(s') * Z * Q )'
%     dR/dyp        = ( (-Rx'(-yp)) * Ry(-xp) * Rz(s') * Z * Q )'
%     dR/dDeltaUT1  = ( W * Z'(ERA) * omega_ERA * Q )'
%
%   The minus signs are not decoration: iauPom00 applies Ry and Rx with NEGATED
%   arguments, so the chain rule contributes a factor of -1 to each of the two
%   polar-motion partials and to neither of the others.
%
%   omega_ERA IS iersConstants().eraRatePerUt1Second AND NOT earthRotationRate.
%   The two differ by 2.0e-8 relative, and earthRotationRate's own help forbids
%   using it to propagate an angle: it is a nominal mean rate, while ERA is
%   exactly linear in UT1 with the slope 2*pi*1.00273781191135448/86400. Using
%   the wrong one biases every Delta UT1 partial by 2e-8, systematically and
%   invisibly. Length of day does not enter: LOD relates UT1 to TAI, not ERA
%   to UT1.
%
%   THE RATE PARTIALS ARE THE DIFFERENCE OF TWO ANALYTIC PARTIALS (decision
%   D102), not the derivative of a differenced quantity:
%
%     dRdot/dp  =  [ dR/dp (t+h) - dR/dp (t-h) ] / (2h),   h = DifferenceStep
%
%   Differentiate with respect to the parameter first, difference in time
%   second. h here IS the h of rotationItrsToGcrs's Rdot under D28 - the
%   half-offset, samples at t-h and t+h, divisor 2h - and the default 200 s is
%   that function's measured default, so with the defaults the rate partial is
%   the partial of the Rdot the rotation actually returns (decision D112).
%   The other order - differentiating the already-differenced Rdot -
%   would agree only to the differencing error and would drift from Rdot as
%   the step changed. info.rateConstruction records which was done, because
%   the two are not interchangeable and a reader cannot tell from the numbers.
%
% ACCURACY
%   The rotation partials are exact to roundoff: they are closed-form products
%   of the same factors the rotation itself is built from, with one elementary
%   rotation replaced by its derivative. Verified against a central difference
%   of rotationItrsToGcrs with a perturbed EOP value; the derivation was
%   checked in an independent implementation before this file was written, with
%   residuals of 5.2e-11, 5.1e-11 and 4.0e-13 at the difference's own roundoff
%   floor.
%
%   THE RATE PARTIALS CARRY THE DIFFERENCING ERROR AND NOTHING BETTER. They are
%   O(h^2) accurate like Rdot, and the default h = 200 s is the measured D28
%   optimum rotationItrsToGcrs uses for Rdot itself; a smaller step trades
%   truncation for cancellation and the convergence block in the test report
%   shows where the floor is.
%
%   THERE ARE NO PARTIALS OF Rddot, AND THAT IS A DECISION (D105, open item
%   B2). P20 delivers dR/dp and dRdot/dp; the second derivative is untouched.
%   Rddot exists because Qddot reaches 1.4e-10 m/s^2, the GRACE accelerometer
%   noise floor, which is a FORCE-MODEL argument: it matters to an integrator
%   propagating a state, not to an estimator solving for EOP. A normal matrix
%   is built from partials of the OBSERVED quantities, and no observation in
%   this toolbox's scope is a function of Rddot. Adding them would cost two
%   further evaluations per epoch, following D102's ordering a second time, to
%   populate a block nothing multiplies. Recorded rather than left ambiguous:
%   the question was asked and answered, not overlooked. If an estimator ever
%   does need them, the construction is the one already used here and the
%   decision is cheap to reverse.
%
%   THE PARTIALS ARE PER RADIAN, NOT PER ARCSECOND. Polar motion is published
%   in arcseconds and Delta UT1 in seconds; xp and yp reach this function in
%   RADIANS, as everywhere else in the toolbox, so a caller building a normal
%   matrix from an arcsecond-parameterised estimate must scale by
%   iersConstants().arcsecondsToRadians. info.polarMotionUnits says so on every
%   call, because a factor of 206265 in a partial is not visible in the answer.
%
% ERRORS
%   referenceSystem:rotationItrsToGcrsPartials:eopRequired
%   referenceSystem:rotationItrsToGcrsPartials:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.
%   IAU SOFA release 20231011, iauPom00, iauC2ixys, iauEra00, iauSp00.
%   Handover decisions D9 (EOP estimation in scope), D28, D102.
%
% EXAMPLE
%   eop = referenceSystem.readEop("eopc04_20.1962-now");
%   t   = referenceSystem.daySecondToEpoch([57754 43200], "UTC");
%   [dXp, dYp, dUt1] = referenceSystem.rotationItrsToGcrsPartials(t, Eop = eop);
%
% KEYWORDS
%   partial derivative, EOP, polar motion, Delta UT1, estimation, POD, Jacobian
%
% See also ROTATIONITRSTOGCRS, EARTHORIENTATIONPARTIALS, INTERPOLATEEOP,
%   IERSCONSTANTS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-08-05 09:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Eop struct = struct([])
        options.CipModel (1,1) string = ""
        options.DifferenceStep (1,1) double {mustBePositive} = 200
        options.ApplyTidalCorrections (1,1) logical = true
    end

    if isempty(options.Eop)
        error('referenceSystem:rotationItrsToGcrsPartials:eopRequired', ...
            ['An Earth orientation series is required: pass Eop with the ', ...
            'output of readEop. There is no built-in default and no zero ', ...
            'fallback, for the reason rotationItrsToGcrs gives - a rotation ', ...
            'built from zero EOP is wrong by several metres and looks ', ...
            'entirely healthy, and so is its Jacobian.']);
    end

    wantRate = nargout > 4;
    [dRdXp, dRdYp, dRdDeltaUt1, resolvedModel] = localPartials(epoch, options);

    if wantRate
        % DifferenceStep is the HALF-OFFSET h, the meaning it has in
        % rotationItrsToGcrs: samples at t-h and t+h, divisor 2h (D112).
        % Until rev. 1.184 the samples sat at t-h/2 and t+h/2 with divisor h,
        % so the same option name meant the full span here and the half-offset
        % there, and the D102 same-step consistency claim was not met.
        h = options.DifferenceStep;
        [beforeXp, beforeYp, beforeUt1] = localPartials( ...
            localShift(epoch, -h), options);
        [afterXp, afterYp, afterUt1] = localPartials( ...
            localShift(epoch, h), options);
        dRdotdXp = (afterXp - beforeXp)/(2*h);
        dRdotdYp = (afterYp - beforeYp)/(2*h);
        dRdotdDeltaUt1 = (afterUt1 - beforeUt1)/(2*h);
    else
        dRdotdXp = [];
        dRdotdYp = [];
        dRdotdDeltaUt1 = [];
    end

    step = options.DifferenceStep;
    if ~wantRate
        step = NaN;
    end
    % info REPORTS THE MODEL ACTUALLY USED, NOT THE OPTION AS GIVEN. With the
    % default the option is empty and the series decides, so echoing the
    % option back would answer a different question than the field name asks.
    % Taken from the first localPartials call rather than a second one: the
    % first version fetched it with an extra full evaluation, which doubled
    % the cost of the cheap path to obtain a string it already had.
    info = struct( ...
        'cipModel', resolvedModel, ...
        'differenceStep', step, ...
        'rateConstruction', "difference of two analytic partials (D102)", ...
        'polarMotionUnits', "radian");
end

% =========================== local functions ===========================

function shifted = localShift(epoch, seconds)
%LOCALSHIFT Move an epoch by a number of seconds, keeping the split form.

    shifted = referenceSystem.normalizeEpoch(epoch);
    shifted.sec = shifted.sec + seconds;
    shifted = referenceSystem.normalizeEpoch(shifted);
end

function [dRdXp, dRdYp, dRdDeltaUt1, cipModel] = localPartials(epoch, options)
%LOCALPARTIALS The three analytic partials at one set of epochs.
%
%   Each EOP enters exactly one factor of R = (W Z Q)', so each partial is that
%   product with one elementary rotation replaced by its derivative. See METHOD.

    constants = referenceSystem.iersConstants();
    utc = referenceSystem.convertTimeScale( ...
        referenceSystem.normalizeEpoch(epoch), "UTC");

    % THE CALL IS COPIED FROM rotationItrsToGcrs, NOT COMPOSED FROM MEMORY.
    % Two things were wrong in the first version: the argument order is
    % (eop, epoch) and not (epoch, eop), and the sub-daily corrections are
    % applied by passing a 'Correction' STRUCT from subdailyEopCorrection -
    % there is no 'ApplyTidalCorrections' name-value here. That name belongs to
    % rotationItrsToGcrs, and carrying it across was the assumption that two
    % functions in one toolbox spell the same idea the same way.
    correction = struct([]);
    if options.ApplyTidalCorrections
        correction = referenceSystem.subdailyEopCorrection(utc);
    end
    if isempty(correction)
        sampled = referenceSystem.interpolateEop(options.Eop, utc);
    else
        sampled = referenceSystem.interpolateEop(options.Eop, utc, ...
            'Correction', correction);
    end
    tt = referenceSystem.convertTimeScale(utc, "TT");
    % sampled.dut1, NOT sampled.deltaUt1 - interpolateEop returns the series'
    % own column names and rotationItrsToGcrs reads it as sampled.dut1.
    ut1 = referenceSystem.convertTimeScale(utc, "UT1", ...
        'DeltaUt1', sampled.dut1);

    % THE CIP GOES THROUGH cipCoordinates AND c2ixys, NOT THROUGH dcmcip.
    % dcmcip takes fourteen arguments and returns the WHOLE rotation with a
    % supplied CIP; it is not a way to obtain Q. That was the first thing
    % written here and it was a guess at a signature - the same shape of error
    % as O27, caught by reading mexGateway.c instead of shipping it.
    cipModel = options.CipModel;
    if cipModel == "" && isfield(sampled, 'meta') && ...
            isfield(sampled.meta, 'cipModel')
        cipModel = string(sampled.meta.cipModel);
    end

    try
        era = mexGateway('era00', ut1.day, ut1.sec);
        sp = mexGateway('sp00', tt.day, tt.sec);
        % THE MODEL IS RESOLVED FROM THE SERIES, EXACTLY AS rotationItrsToGcrs
        % DOES IT, AND THE OFFSETS COME FROM THE SAMPLE.
        %
        % Three things had to be read rather than assumed here. (1) The
        % accepted values are "IAU2006/2000A" and "IAU2000A"; the first
        % version passed "2006", which is the C LAYER'S integer convention -
        % rsCore tests cipModel != 2006 - leaking into a MATLAB call.
        % Verifying the option NAME said nothing about its VALUE DOMAIN, and
        % the arguments block carries no mustBeMember, so the accepted set
        % lives in the body of cipCoordinates. (2) Passing 'Eop' ALONGSIDE
        % non-zero DeltaX or DeltaY is a hard conflictingOffsets error, so the
        % two cannot both be supplied. (3) cipCoordinates' own Eop branch
        % reads the RAW series column, not the value interpolated to these
        % epochs - which is the wrong quantity here. So the offsets come from
        % the sample and only the model name is taken from the metadata.
        [cipX, cipY, cipS] = referenceSystem.cipCoordinates(tt, ...
            'DeltaX', sampled.dX, 'DeltaY', sampled.dY, ...
            'CipModel', cipModel);
        q = mexGateway('c2ixys', cipX, cipY, cipS);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:rotationItrsToGcrsPartials:gatewayMissing', ...
                ['The rotation factors are evaluated in C through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex.']);
        end
        rethrow(cause);
    end

    z = pageRotationZ(era(:).');
    zDot = pageRotationZDerivative(era(:).');

    xp = sampled.xp(:).';
    yp = sampled.yp(:).';
    spRow = sp(:).';

    % W = Rx(-yp) Ry(-xp) Rz(sp). THE NEGATED ARGUMENTS ARE WHY EACH POLAR
    % MOTION PARTIAL PICKS UP A FACTOR OF -1 and the Delta UT1 one does not.
    rzSp = pageRotationZ(spRow);
    ryXp = pageRotationY(-xp);
    rxYp = pageRotationX(-yp);
    w = pagemtimes(rxYp, pagemtimes(ryXp, rzSp));

    dWdXp = pagemtimes(rxYp, ...
        pagemtimes(-pageRotationYDerivative(-xp), rzSp));
    dWdYp = pagemtimes(-pageRotationXDerivative(-yp), ...
        pagemtimes(ryXp, rzSp));

    zq = pagemtimes(z, q);
    dRdXp = pagetranspose(pagemtimes(dWdXp, zq));
    dRdYp = pagetranspose(pagemtimes(dWdYp, zq));
    dRdDeltaUt1 = pagetranspose(pagemtimes(w, ...
        pagemtimes(zDot*constants.eraRatePerUt1Second, q)));
end

function m = pageRotationZ(angle)
%PAGEROTATIONZ SOFA-sense frame rotation about z, 3-by-3-by-N.
%   The same convention as rsRotationZ in mex/rsCore.c, which is asserted
%   rather than assumed: a test compares this against the gateway's own
%   assembly of the full rotation.

    n = numel(angle);
    c = reshape(cos(angle), 1, 1, n);
    s = reshape(sin(angle), 1, 1, n);
    o = zeros(1, 1, n);
    i = ones(1, 1, n);
    m = [c, s, o; -s, c, o; o, o, i];
end

function m = pageRotationZDerivative(angle)
%PAGEROTATIONZDERIVATIVE d/dtheta of pageRotationZ.
%   Matches rsRotationZFirstDerivative in mex/rsCore.c element for element.
%   THIS IS NOT A ROTATION - it is singular - which is exactly why rsCore
%   writes it out rather than calling iauRz on an identity.

    n = numel(angle);
    c = reshape(cos(angle), 1, 1, n);
    s = reshape(sin(angle), 1, 1, n);
    o = zeros(1, 1, n);
    m = [-s, c, o; -c, -s, o; o, o, o];
end

function m = pageRotationY(angle)
%PAGEROTATIONY SOFA-sense frame rotation about y, 3-by-3-by-N.

    n = numel(angle);
    c = reshape(cos(angle), 1, 1, n);
    s = reshape(sin(angle), 1, 1, n);
    o = zeros(1, 1, n);
    i = ones(1, 1, n);
    m = [c, o, -s; o, i, o; s, o, c];
end

function m = pageRotationYDerivative(angle)
%PAGEROTATIONYDERIVATIVE d/dtheta of pageRotationY.

    n = numel(angle);
    c = reshape(cos(angle), 1, 1, n);
    s = reshape(sin(angle), 1, 1, n);
    o = zeros(1, 1, n);
    m = [-s, o, -c; o, o, o; c, o, -s];
end

function m = pageRotationX(angle)
%PAGEROTATIONX SOFA-sense frame rotation about x, 3-by-3-by-N.

    n = numel(angle);
    c = reshape(cos(angle), 1, 1, n);
    s = reshape(sin(angle), 1, 1, n);
    o = zeros(1, 1, n);
    i = ones(1, 1, n);
    m = [i, o, o; o, c, s; o, -s, c];
end

function m = pageRotationXDerivative(angle)
%PAGEROTATIONXDERIVATIVE d/dtheta of pageRotationX.

    n = numel(angle);
    c = reshape(cos(angle), 1, 1, n);
    s = reshape(sin(angle), 1, 1, n);
    o = zeros(1, 1, n);
    m = [o, o, o; o, -s, c; o, -c, -s];
end
