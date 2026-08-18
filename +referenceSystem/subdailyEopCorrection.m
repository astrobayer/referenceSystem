function correction = subdailyEopCorrection(epoch)
%SUBDAILYEOPCORRECTION Sub-daily ocean tide and libration variation in the EOP.
%
%   correction = subdailyEopCorrection(epoch)
%
%   Returns the diurnal and semidiurnal variation in polar motion and UT1 that
%   a daily-tabulated EOP series cannot carry, as a tagged struct whose sense
%   field states that the numbers are additive. It is a pure function of time
%   and needs no EOP file.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, scale UTC.
%
% OUTPUT ARGUMENTS
%   Name             Size   Type     Units  Description
%   ----             ----   ----     -----  -----------
%   correction       1x1    struct   -      Tagged correction. Fields below.
%   .dxp, .dyp       Nx1    double   rad    Polar motion variation.
%   .dut1            Nx1    double   s      UT1 variation.
%   .sense           1x1    string   -      "additive". See METHOD.
%   .source          1x1    string   -      "subdailyEopCorrection".
%   .model           1x1    string   -      The three models summed.
%
% METHOD
%   The sum of three IERS Conventions (2010) models, ported to C in mex/iers/
%   and evaluated through the MEX gateway:
%
%     ORTHO_EOP   diurnal and semidiurnal ocean tides in xp, yp and UT1
%     PMSDNUT2    diurnal lunisolar libration in xp and yp
%     UTLIBR      subdiurnal libration in UT1
%
%   They are summed rather than returned separately because they are always
%   applied together; offering them individually would invite a caller to apply
%   two of the three and get a result that is wrong by the amount of the
%   missing one, with nothing to indicate it.
%
%   v1 buried these inside its C rotation core, where they could not be
%   inspected, tested or plotted from MATLAB, and defaulted them off. They are
%   first-class functions here and handover approximation #5 makes them default
%   on for the workflow, because omitting them is a 15 mm error at the surface
%   for GRACE-class work.
%
%   THE SENSE TAG, decision D30. This function returns sense "additive", which
%   is what interpolateEop accepts by default, because these terms genuinely
%   are signal a daily series does not contain. Its counterpart
%   zonalTideEopCorrection returns "regularization" and is refused by default.
%   The tag travels with the numbers and is checked at the consumer, so that
%   the two cannot be confused by a caller who reads neither help text.
%
%   THE TIME SCALE, decision D57 and handover finding m-8. The epoch must be
%   UTC. The original Fortran routines take a Modified Julian Date and their
%   headers do not state its scale to better than a minute; they are nominally
%   UT1 or TT quantities. UTC is used because it is the scale the EOP series is
%   tabulated against, because it is what the validated v1 pipeline fed them,
%   and above all because using UT1 would make this function depend on the EOP
%   series it exists to correct. The cost is quantified in ACCURACY.
%
%   A non-UTC epoch is refused rather than converted. A silent conversion is how
%   a tidal model ends up driven by the wrong time scale, and a caller holding a
%   TT epoch also holds everything needed to convert it deliberately.
%
%   No dlod field. UTLIBR computes a libration LOD term and it is deliberately
%   discarded, because ORTHO_EOP publishes no matching ocean-tide LOD term:
%   a returned dlod would read as "the sub-daily LOD correction" and would in
%   fact be a fraction of it. A partial quantity that looks complete is worse
%   than an absent one (decision D55). Where the sub-daily LOD effect is needed,
%   differentiate dut1.
%
% ACCURACY
%   The three models reproduce the original IERS Fortran to round-off. Measured
%   in session S2 by compiling the Fortran with gfortran and differencing over
%   2001 epochs spanning 1960 to 2100: the largest disagreement is 1.8e-14 in
%   the routines' own units, which is 4e-16 relative. ORTHO_EOP is bit-identical.
%
%   Amplitudes: up to about 0.5 mas in polar motion and 50 microseconds in UT1,
%   that is roughly 15 mm and 23 mm respectively at the Earth's surface. This is
%   the size of the error made by omitting this correction, which is why the
%   workflow defaults it on.
%
%   Feeding UTC where the models nominally expect UT1 or TT (finding m-8)
%   displaces the argument by at most about 70 seconds. Against periods of half
%   a day and amplitudes of tens of microarcseconds this is below 0.1 uas, that
%   is under 0.003 mm at the surface, four orders of magnitude below the models'
%   own accuracy. It is stated because it is an undocumented approximation in
%   v1, not because it is significant.
%
%   The models themselves are conventional: they carry the accuracy of IERS
%   Conventions (2010) Chapter 8, of order 10 per cent of their own amplitude in
%   the ocean-tide terms.
%
%   PMSDNUT2 is evaluated with IBAND = 1, as the original hard-codes: the ten
%   quasi-diurnal terms only. The fifteen long-period terms and the secular
%   drift are excluded, following IERS Conventions (2010) section 5.5.1.1, since
%   a daily EOP series already carries those frequencies as observed.
%
% ERRORS
%   referenceSystem:subdailyEopCorrection:wrongScale
%   referenceSystem:subdailyEopCorrection:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5.5.1 and Ch. 8.
%   Ray, R. D., Steinberg, D. J., Chao, B. F., Cartwright, D. E., 1994,
%     Science 264, 830 (the ocean tide model behind ORTHO_EOP).
%   Brzezinski, A., 2001, and Brzezinski and Capitaine, 2003 (libration).
%   IERS Conventions software ORTHO_EOP.F, PMSDNUT2.F, UTLIBR.F.
%
% EXAMPLE
%   utc = referenceSystem.daySecondToEpoch([57754*ones(24,1) (0:3600:82800)'], "UTC");
%   correction = referenceSystem.subdailyEopCorrection(utc);
%   e = referenceSystem.interpolateEop(eop, utc, 'Correction', correction);
%
% KEYWORDS
%   EOP, ocean tide, libration, sub-daily, polar motion, UT1, ORTHO_EOP
%
% See also INTERPOLATEEOP, ZONALTIDEEOPCORRECTION, READEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 12:15 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "UTC"
        error('referenceSystem:subdailyEopCorrection:wrongScale', ...
            ['The sub-daily models are driven with UTC in this toolbox and ', ...
            'this epoch is %s. Convert it deliberately with ', ...
            'convertTimeScale; converting it here would hide which scale ', ...
            'drove a tidal model.'], epoch.scale);
    end

    try
        [dxp, dyp, dut1] = mexGateway('subdaily', epoch.day, epoch.sec);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:subdailyEopCorrection:gatewayMissing', ...
                ['The sub-daily models are evaluated in C through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end

    correction = struct( ...
        'dxp', dxp, 'dyp', dyp, 'dut1', dut1, ...
        'sense', "additive", ...
        'source', "subdailyEopCorrection", ...
        'model', "ORTHO_EOP + PMSDNUT2 + UTLIBR, IERS Conventions (2010)");
end
