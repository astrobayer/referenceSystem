function fa = fundamentalArguments(epoch, options)
%FUNDAMENTALARGUMENTS Delaunay, planetary and Doodson arguments of nutation and tides.
%
%   fa = fundamentalArguments(epoch)
%   fa = fundamentalArguments(epoch, 'Ut1Epoch', ut1Epoch)
%
%   Returns all three argument sets, each field an Nx1 column in radians
%   wrapped to [0, 2*pi), computed from a TT epoch. The three sets are named
%   explicitly because "fundamental arguments" is ambiguous and feeding a tidal
%   model the wrong set is a silent error.
%
% INPUT ARGUMENTS
%   Name       Size   Type     Units  Description
%   ----       ----   ----     -----  -----------
%   epoch      1x1    struct   -      Epoch struct, N entries, scale TT.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name       Size   Type     Default  Description
%   ----       ----   ----     -------  -----------
%   Ut1Epoch   1x1    struct   none     Epoch struct, N entries, scale UT1, at
%                                       the same instants as epoch. Required
%                                       for the Doodson argument tau and used
%                                       for nothing else.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units  Description
%   ----        ----   ----     -----  -----------
%   fa          1x1    struct   -      Fields below, IERS symbols verbatim.
%   .l          Nx1    double   rad    Delaunay: mean anomaly of the Moon.
%   .lPrime     Nx1    double   rad    Delaunay: mean anomaly of the Sun.
%   .F          Nx1    double   rad    Delaunay: L - Omega.
%   .D          Nx1    double   rad    Delaunay: mean elongation of the Moon
%                                      from the Sun.
%   .Omega      Nx1    double   rad    Delaunay: mean longitude of the
%                                      ascending node of the Moon.
%   .lMe        Nx1    double   rad    Planetary: mean longitude of Mercury.
%   .lVe        Nx1    double   rad    Planetary: mean longitude of Venus.
%   .lE         Nx1    double   rad    Planetary: mean longitude of Earth.
%   .lMa        Nx1    double   rad    Planetary: mean longitude of Mars.
%   .lJ         Nx1    double   rad    Planetary: mean longitude of Jupiter.
%   .lSa        Nx1    double   rad    Planetary: mean longitude of Saturn.
%   .lU         Nx1    double   rad    Planetary: mean longitude of Uranus.
%   .lNe        Nx1    double   rad    Planetary: mean longitude of Neptune.
%   .pA         Nx1    double   rad    Planetary: general accumulated
%                                      precession in longitude. NOT wrapped,
%                                      see METHOD.
%   .tau        Nx1    double   rad    Doodson: mean lunar time. NaN unless
%                                      Ut1Epoch was supplied.
%   .s          Nx1    double   rad    Doodson: mean longitude of the Moon.
%   .h          Nx1    double   rad    Doodson: mean longitude of the Sun.
%   .p          Nx1    double   rad    Doodson: longitude of lunar perigee.
%   .nPrime     Nx1    double   rad    Doodson: negative longitude of the
%                                      lunar node.
%   .pStar      Nx1    double   rad    Doodson: longitude of solar perigee.
%   .scale      1x1    string   -      "TT", the scale the arguments were
%                                      computed from, carried so a consumer
%                                      cannot lose it.
%
% METHOD
%   The Delaunay and planetary sets come from the unmodified SOFA routines
%   iauFal03, iauFalp03, iauFaf03, iauFad03, iauFaom03 and iauFame03 through
%   iauFapa03, evaluated in C through the MEX gateway. They are fifth-degree
%   polynomials in Julian centuries of TT, about a hundred floating-point
%   operations for the whole set.
%
%   The Doodson set is derived from them by the relations of IERS Conventions
%   (2010) Chapter 6:
%
%       s      = F + Omega            mean longitude of the Moon
%       h      = s - D                mean longitude of the Sun
%       p      = s - l                longitude of lunar perigee
%       nPrime = -Omega               negative longitude of the lunar node
%       pStar  = s - D - lPrime       longitude of solar perigee
%       tau    = theta + pi - s       mean lunar time, theta = GMST
%
%   It is returned rather than left to the caller because the solid-Earth and
%   ocean-tide models of Chapter 6 use exactly this set, and the tau relation
%   in particular is easy to get wrong. Field names follow the IERS symbols
%   verbatim (handover section C.7 Tier 1) rather than the function-name
%   grammar, which is why they are single letters.
%
%   tau needs Greenwich Mean Sidereal Time and therefore UT1, which is a
%   measured quantity from the Earth orientation series and not a function of
%   TT. This is layer L0 and cannot reach the L1 series, so the caller supplies
%   the UT1 epoch when it wants tau. Without it tau is NaN - the documented
%   undefined-but-valid value permitted by section C.6 rule 5, chosen over an
%   error so that a caller wanting only the Delaunay set is not obstructed, and
%   over a silent substitution of UTC for UT1, which would be wrong by up to
%   0.9 s of Earth rotation, that is 12 arcseconds. The other five Doodson
%   arguments do not depend on UT1 and are always filled.
%
%   pA is the one field not wrapped to [0, 2*pi) (decision D52). It is the
%   accumulated general precession, a secular quantity rather than a cyclic
%   angle: it passes through zero at J2000.0 and reaches only about 0.16 rad
%   over 1400 to 2600, so it never needs a wrap, and wrapping it would report
%   a value near 2*pi for every epoch before J2000.0 and mislead anyone reading
%   it directly. Inside a trigonometric series the two forms are identical.
%
%   The epoch must be TT. A non-TT epoch is refused rather than converted,
%   because a silent conversion is how a tidal model ends up driven by the
%   wrong time scale, and because the caller that has a UTC epoch also has the
%   information needed to convert it deliberately.
%
%   Decision D27, the duplication this function exposes. The toolbox computes
%   these arguments in two places: SOFA iauFa*03 here, and the ported IERS
%   FUNDARG inside subdailyEopCorrection and zonalTideEopCorrection. Both are
%   kept. This function is the public authority and no other MATLAB-level
%   function may compute the arguments another way; the ported IERS routines
%   keep their own FUNDARG byte-intact so that their published test-case
%   validation stands unmodified. The agreement between the two is measured by
%   a test rather than assumed, and the achieved number is in ACCURACY below.
%
% ACCURACY
%   The polynomials are exact to their published coefficients; the evaluation
%   adds a few units in the last place, below 1e-15 rad. Their physical
%   accuracy is that of Simon et al. (1994), a few microarcseconds per century
%   over the twentieth and twenty-first centuries and degrading outside them.
%
%   Decision D27 agreement, re-measured in session S2 across 1960 to 2100
%   rather than at the single epoch S1 used. SOFA iauFa*03 against the ported
%   IERS FUNDARG in mex/iers/:
%
%       l, F, Omega    agree exactly, to the bit, at every epoch
%       lPrime         9.75e-12 rad = 2.01 microarcseconds, worst case
%       D              9.83e-12 rad = 2.03 microarcseconds, worst case
%
%   S1 recorded "better than 1e-13 rad" from one epoch. That was wrong, and
%   the sweep is what found it. The discrepancy is not noise and it is not
%   random: it is confined to exactly the two arguments whose leading constant
%   the supplied FUNDARG.F carries with two digits fewer than SOFA does,
%   1287104.79305 against 1287104.793048 and 1072260.70369 against
%   1072260.703692. Two truncated digits of 2e-6 arcsec each account for the
%   whole 9.7e-12 rad.
%
%   Note which one is right: SOFA reproduces the test case printed in
%   FUNDARG.F's own header to 1e-16, and the supplied FUNDARG.F does not
%   reproduce it. The file is internally inconsistent. This function uses SOFA
%   and is therefore on the correct constants; the ported routines keep the
%   file's constants so that their own published validation still stands
%   (D27), and 2 microarcseconds of lunisolar argument reaches the tidal
%   models as under 1e-9 microarcseconds of polar motion, which is nothing.
%
%   tau inherits the accuracy of the supplied Delta UT1, of order 10 us for the
%   IERS C04 series, which is 4.4e-9 rad of Earth rotation; that dominates
%   everything else in this function by six orders of magnitude.
%
%   The wrap to [0, 2*pi) is exact in the sense that it adds a multiple of
%   2*pi; near the wrap point the relative resolution of the result is
%   therefore that of a number near 2*pi, about 4.4e-16 rad, and continuity
%   across the wrap is asserted by a precision test.
%
% ERRORS
%   referenceSystem:fundamentalArguments:wrongScale
%   referenceSystem:fundamentalArguments:sizeMismatch
%   referenceSystem:fundamentalArguments:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.7.1 to 5.7.2 and
%     Ch. 6 (Doodson arguments and the tidal models that use them).
%   Simon, J.-L. et al., 1994, Astron. Astrophys. 282, 663.
%   IAU SOFA release 20231011, iauFal03 to iauFapa03 and iauGmst06.
%   IERS Conventions software FUNDARG.F, published test case.
%
% EXAMPLE
%   tt = referenceSystem.daySecondToEpoch([54465 0], "TT");
%   fa = referenceSystem.fundamentalArguments(tt);
%   assert(abs(fa.l - 2.291187512612069) < 1e-12);
%
% KEYWORDS
%   fundamental arguments, Delaunay, Doodson, nutation, tides, SOFA, FUNDARG
%
% See also CONVERTTIMESCALE, NORMALIZEEPOCH, TIMESCALE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 20:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
        options.Ut1Epoch struct = struct([])
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "TT"
        error('referenceSystem:fundamentalArguments:wrongScale', ...
            ['The fundamental arguments are defined on TT and this epoch is ', ...
            '%s. Convert it deliberately with convertTimeScale; converting ', ...
            'it here would hide which scale drove a tidal model.'], epoch.scale);
    end

    epochCount = numel(epoch.day);
    hasUt1 = ~isempty(options.Ut1Epoch);
    ut1Day = 0;
    ut1Second = 0;

    if hasUt1
        ut1 = referenceSystem.normalizeEpoch(options.Ut1Epoch);
        if ut1.scale ~= "UT1"
            error('referenceSystem:fundamentalArguments:wrongScale', ...
                'Ut1Epoch must be a UT1 epoch; this one is %s.', ut1.scale);
        end
        if numel(ut1.day) ~= epochCount
            error('referenceSystem:fundamentalArguments:sizeMismatch', ...
                ['Ut1Epoch must hold one entry per TT epoch; it holds %d ', ...
                'for %d.'], numel(ut1.day), epochCount);
        end
        ut1Day = ut1.day;
        ut1Second = ut1.sec;
    end

    try
        block = mexGateway('fa', epoch.day, epoch.sec, ut1Day, ut1Second, ...
            double(hasUt1));
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:fundamentalArguments:gatewayMissing', ...
                ['The fundamental arguments come from SOFA through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end

    % Column order is fixed by the RS_FA_COLUMNS enum of mex/rsCore.h. The
    % names below are the only place that order is turned into field names, and
    % a contract test asserts the two agree.
    fieldName = ["l", "lPrime", "F", "D", "Omega", ...
        "lMe", "lVe", "lE", "lMa", "lJ", "lSa", "lU", "lNe", "pA", ...
        "tau", "s", "h", "p", "nPrime", "pStar"];

    fa = struct();
    for k = 1:numel(fieldName)
        fa.(fieldName(k)) = block(:,k);
    end
    fa.scale = epoch.scale;
end
