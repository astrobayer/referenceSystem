function correction = zonalTideEopCorrection(epoch)
%ZONALTIDEEOPCORRECTION Long-period zonal tide effect on the rotation of the Earth.
%
%   correction = zonalTideEopCorrection(epoch)
%
%   Returns the effect of the long-period zonal Earth tides on UT1, on the
%   excess length of day and on the rotational speed, as a tagged struct whose
%   sense field states that the numbers REGULARISE a series rather than correct
%   it. It is a pure function of time and needs no EOP file.
%
%   Read the METHOD block before using this function. Applying it in the wrong
%   sense is the largest silent error available anywhere in this toolbox.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   epoch   1x1    struct   -      Epoch struct, N entries, scale TT.
%
% OUTPUT ARGUMENTS
%   Name        Size   Type     Units    Description
%   ----        ----   ----     -----    -----------
%   correction  1x1    struct   -        Tagged correction. Fields below.
%   .dut1       Nx1    double   s        Zonal tide effect on UT1.
%   .dlod       Nx1    double   s        Effect on excess length of day, per day.
%   .domega     Nx1    double   rad/s    Effect on rotational speed.
%   .sense      1x1    string   -        "regularization". See METHOD.
%   .source     1x1    string   -        "zonalTideEopCorrection".
%   .model      1x1    string   -        The model evaluated.
%
% METHOD
%   A port of IERS Conventions (2010) RG_ZONT2: 62 terms combining the Yoder et
%   al. (1981) elastic body tide, the Wahr and Bergen (1986) inelastic body tide
%   and the Kantha et al. (1998) ocean tide models, as Chapter 8 recommends.
%   Evaluated in C through the MEX gateway. This is new capability; v1 had no
%   zonal tide model at all (handover approximation #6).
%
%   WHAT THESE NUMBERS ARE FOR, decision D30, and the reason this help text
%   leads with a warning. The zonal tides make the Earth spin measurably faster
%   and slower over periods from five days to 18.6 years. A measured UT1 series
%   such as C04 already contains that signal, because it was observed. This
%   function does not supply missing signal; it supplies the signal to REMOVE if
%   you want regularised UT1R, which is a smoother quantity easier to
%   interpolate and to model.
%
%   So the correct use is subtraction, and interpolateEop does the subtraction
%   for you when it is asked to:
%
%       UT1R = UT1 - dut1
%
%   and the function therefore returns sense "regularization", which
%   interpolateEop REFUSES unless 'Regularize', true is passed. Its counterpart
%   subdailyEopCorrection returns "additive" and is accepted by default. That
%   asymmetry is the whole protection, and it is structural rather than
%   documentary because the failure it guards has no symptom: adding this to a
%   C04 series produces a rotation matrix that is orthogonal, unit-determinant,
%   smooth in time and wrong.
%
%   THE TIME SCALE. The epoch must be TT, which is what RG_ZONT2's own header
%   states (strictly TDB, which it says makes no significant difference: the
%   two differ by under 2 ms, against a shortest period of five days). A non-TT
%   epoch is refused rather than converted, for the same reason
%   fundamentalArguments refuses one.
%
%   THE THIRD OUTPUT. domega is the effect on rotational speed and is returned
%   because RG_ZONT2 computes it in the same pass and because it is the natural
%   input to an angular-momentum budget. It is not used by anything else in this
%   toolbox and interpolateEop ignores it.
%
% ACCURACY
%   The port reproduces the original IERS Fortran to 1.7e-16 relative, measured
%   in session S2 over 2001 epochs spanning 1960 to 2100 against RG_ZONT2.F
%   compiled with gfortran, and reproduces the routine's published test case
%   exactly in dut1 and to 4e-20 in dlod.
%
%   HOW BIG THE MISTAKE IS, measured over one 18.6-year nodal period, because
%   decision D30 rests on this number and it must not be a remembered one:
%
%     full 62-term model, peak |dut1|          167.7 ms   = 78 m at the equator
%     short-period part alone, 35-day high-pass  2.07 ms  = 0.96 m
%     peak |dlod|                              0.93 ms/day
%
%   The model is dominated by the 18.6-year nodal term, whose UT1 amplitude is
%   0.162 s. The short-period figure is the part that separates UT1R from UT1
%   under the conventional 35-day boundary. At the equator one millisecond of
%   UT1 is 0.465 m of surface displacement.
%
%   The model's own accuracy is that of IERS Conventions (2010) Chapter 8; the
%   coefficients are tabulated to four decimals in units of 1e-4 s, so the
%   representation floor is about 10 ns in UT1.
%
% ERRORS
%   referenceSystem:zonalTideEopCorrection:wrongScale
%   referenceSystem:zonalTideEopCorrection:gatewayMissing
%
% REFERENCES
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 8, pp. 105-106.
%   Yoder, C. F., Williams, J. G., Parke, M. E., 1981, J. Geophys. Res. 86, 881.
%   Wahr, J. and Bergen, Z., 1986, Geophys. J. Roy. astr. Soc. 87, 633.
%   Kantha, L. H., Stewart, J. S., Desai, S. D., 1998, J. Geophys. Res. 103, 12639.
%   IERS Conventions software RG_ZONT2.F, published test case.
%
% EXAMPLE
%   utc = referenceSystem.daySecondToEpoch([57754 0], "UTC");
%   tt = referenceSystem.convertTimeScale(utc, "TT");
%   correction = referenceSystem.zonalTideEopCorrection(tt);
%   % Regularised UT1R, and only because it was asked for explicitly:
%   e = referenceSystem.interpolateEop(eop, utc, ...
%       'Correction', correction, 'Regularize', true);
%
% KEYWORDS
%   EOP, zonal tide, UT1R, regularization, length of day, RG_ZONT2
%
% See also INTERPOLATEEOP, SUBDAILYEOPCORRECTION, READEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 12:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        epoch (1,1) struct
    end

    epoch = referenceSystem.normalizeEpoch(epoch);
    if epoch.scale ~= "TT"
        error('referenceSystem:zonalTideEopCorrection:wrongScale', ...
            ['RG_ZONT2 is defined on TT and this epoch is %s. Convert it ', ...
            'deliberately with convertTimeScale; converting it here would ', ...
            'hide which scale drove a tidal model.'], epoch.scale);
    end

    try
        [dut1, dlod, domega] = mexGateway('zonaltide', epoch.day, epoch.sec);
    catch cause
        if strcmp(cause.identifier, 'MATLAB:UndefinedFunction')
            error('referenceSystem:zonalTideEopCorrection:gatewayMissing', ...
                ['The zonal tide model is evaluated in C through the MEX ', ...
                'gateway, which is not built. Run referenceSystem.buildMex ', ...
                'once.']);
        end
        rethrow(cause);
    end

    correction = struct( ...
        'dut1', dut1, 'dlod', dlod, 'domega', domega, ...
        'sense', "regularization", ...
        'source', "zonalTideEopCorrection", ...
        'model', "RG_ZONT2, IERS Conventions (2010) Ch. 8, 62 terms");
end
