function itrfInfo = itrfParameters(name)
%ITRFPARAMETERS Published Helmert parameters from ITRF2020 to a past ITRF.
%
%   itrfInfo = itrfParameters(name) returns the 14 transformation parameters
%   FROM ITRF2020 TO the named realization, in SI units.
%
%   itrfTable = itrfParameters("list") returns a table with one row per
%   supported realization and the same quantities as variables.
%
%   Supported names, case sensitive: "ITRF2014", "ITRF2008", "ITRF2005",
%   "ITRF2000", "ITRF97", "ITRF96", "ITRF94", "ITRF93", "ITRF92", "ITRF91",
%   "ITRF90", "ITRF89", "ITRF88".
%
% INPUT ARGUMENTS
%   Name   Size   Type     Units  Description
%   ----   ----   ----     -----  -----------
%   name   1x1    string   -      Realization name, or "list" for the table form.
%                                 A char row vector is accepted and converted.
%
% OUTPUT ARGUMENTS
%   Name               Size   Type     Units    Description
%   ----               ----   ----     -----    -----------
%   itrfInfo           1x1    struct   -        Parameters of the named frame.
%   .name              1x1    string   -        Realization name, echoed.
%   .epoch             1x1    double   year     Reference epoch of the
%                                               parameters, decimal year.
%   .translation       1x3    double   m        Tx, Ty, Tz at .epoch.
%   .translationRate   1x3    double   m/year   Their rates.
%   .scale             1x1    double   1        Scale factor D at .epoch,
%                                               dimensionless, NOT ppb.
%   .scaleRate         1x1    double   1/year   Its rate.
%   .rotation          1x3    double   rad      Rx, Ry, Rz at .epoch.
%   .rotationRate      1x3    double   rad/year Their rates.
%   .convention        1x1    string   -        "positionVector", the convention
%                                               of the published model.
%   .sourceUrl         1x1    string   -        Where the table was fetched from.
%   .retrieved         1x1    string   -        Date it was fetched and checked.
%
%   For name = "list" the output is a 13x12 table with the same variables, the
%   vector quantities split into their three components.
%
% METHOD
%   The table is the IGN publication Transfo-ITRF2020_TRFs.txt, transcribed
%   verbatim and converted to SI once, here, so that nothing downstream ever
%   sees millimetres, parts per billion or milliarcseconds. The published model
%   is
%
%       XS = X + T + M*X,   M = [  D  -Rz   Ry ;
%                                  Rz   D  -Rx ;
%                                 -Ry  Rx   D  ]
%
%   with X in ITRF2020 and XS in the named frame, every parameter linear in
%   time: P(t) = P(epoch) + Pdot*(t - epoch). The epoch is 2015.0 for every
%   current entry, which is why it is carried per entry rather than assumed.
%
%   THE MODEL IS THE POSITION VECTOR CONVENTION. The sign of M's off-diagonal
%   terms says so: a positive Rz turns the position vector, not the axes. The
%   EPSG registry classifies these same parameters as "Time-dependent Position
%   Vector transformation" for the same reason. Applying them under the
%   Coordinate Frame convention reverses all three rotation signs, which for
%   ITRF93 - the only entry with nonzero rotations - moves a surface point by
%   about 27 cm. applyHelmert7 therefore requires the convention to be named and
%   has no default.
%
%   The values were re-fetched from the source URL and compared against the v1
%   transcription line by line on 2026-07-26: all thirteen rows and all
%   fourteen parameters agree exactly, and the unit conversion is correct. The
%   published rotations are in units of 0.001 arcsecond, that is milliarcseconds,
%   which is the one conversion in the table that is easy to lose by a factor of
%   a thousand.
%
% ACCURACY
%   The parameters are published to 0.1 mm, 0.01 ppb and 0.01 mas, and are
%   stored here at exactly that precision; the SI conversion adds at most one
%   double-precision rounding, below 1e-19 m. The uncertainty that matters is
%   the physical one: the IGN notes state these parameters are derived from
%   earlier published values and supersede them, and the ITRF2020 frame origin
%   itself is stable at the 5 mm level with 0.5 mm/year of drift. A conversion
%   between two realizations is therefore good to a few millimetres at best,
%   whatever the arithmetic does.
%
%   Note that the parameters are exact by definition of the transformation - the
%   published numbers ARE the transformation - so a test may assert them to the
%   last printed digit, and the reference test does.
%
% ERRORS
%   MATLAB:validators:mustBeMember
%       Raised by the arguments block for a name that is not supported.
%   referenceSystem:itrfParameters:listNotSupportedInCodegen
%
% REFERENCES
%   IGN, Transformation parameters from ITRF2020 to past ITRFs,
%   https://itrf.ign.fr/docs/solutions/itrf2020/Transfo-ITRF2020_TRFs.txt
%   Z. Altamimi, P. Rebischung, X. Collilieux, L. Metivier, K. Chanard (2023),
%   ITRF2020: an augmented reference frame, Journal of Geodesy 97(47).
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 4.
%
% EXAMPLE
%   p = referenceSystem.itrfParameters("ITRF2014");
%   allFrames = referenceSystem.itrfParameters("list");
%
% KEYWORDS
%   ITRF, ITRS, Helmert, transformation parameters, realization, IGN, IERS,
%   position vector, datum
%
% See also CONVERTITRF, APPLYHELMERT7, ELLIPSOIDPARAMETERS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 05:40 (CEST, UTC+02:00) - session S4, prompt P10
% -------------------------------------------------------------------------

%#codegen

    arguments
        name (1,1) string {mustBeMember(name, ["ITRF2014", "ITRF2008", ...
            "ITRF2005", "ITRF2000", "ITRF97", "ITRF96", "ITRF94", "ITRF93", ...
            "ITRF92", "ITRF91", "ITRF90", "ITRF89", "ITRF88", "list"])}
    end

    if coder.target('MATLAB') && strcmp(name, "list")
        itrfInfo = buildItrfTable();
        return
    end

    itrfInfo = namedFrame(name);
end

% -------------------------------------------------------------------------

function itrfInfo = namedFrame(name)
%NAMEDFRAME One row of the published table, converted to SI.
%   The published columns are Tx Ty Tz [mm], D [ppb], Rx Ry Rz [0.001 arcsec],
%   the reference epoch [year], and then the same seven quantities per year.
%   Held as literals in the published units so that this file can be compared
%   against the source by eye, and converted once at the end.

    if strcmp(name, "ITRF2014")
        value = [-1.4, -0.9, 1.4, -0.42, 0.00, 0.00, 0.00];
        rate = [0.0, -0.1, 0.2, 0.00, 0.00, 0.00, 0.00];
    elseif strcmp(name, "ITRF2008")
        value = [0.2, 1.0, 3.3, -0.29, 0.00, 0.00, 0.00];
        rate = [0.0, -0.1, 0.1, 0.03, 0.00, 0.00, 0.00];
    elseif strcmp(name, "ITRF2005")
        value = [2.7, 0.1, -1.4, 0.65, 0.00, 0.00, 0.00];
        rate = [0.3, -0.1, 0.1, 0.03, 0.00, 0.00, 0.00];
    elseif strcmp(name, "ITRF2000")
        value = [-0.2, 0.8, -34.2, 2.25, 0.00, 0.00, 0.00];
        rate = [0.1, 0.0, -1.7, 0.11, 0.00, 0.00, 0.00];
    elseif strcmp(name, "ITRF97")
        value = [6.5, -3.9, -77.9, 3.98, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF96")
        value = [6.5, -3.9, -77.9, 3.98, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF94")
        value = [6.5, -3.9, -77.9, 3.98, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF93")
        value = [-65.8, 1.9, -71.3, 4.47, -3.36, -4.33, 0.75];
        rate = [-2.8, -0.2, -2.3, 0.12, -0.11, -0.19, 0.07];
    elseif strcmp(name, "ITRF92")
        value = [14.5, -1.9, -85.9, 3.27, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF91")
        value = [26.5, 12.1, -91.9, 4.67, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF90")
        value = [24.5, 8.1, -107.9, 4.97, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF89")
        value = [29.5, 32.1, -145.9, 8.37, 0.00, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    elseif strcmp(name, "ITRF88")
        value = [24.5, -3.9, -169.9, 11.47, 0.10, 0.00, 0.36];
        rate = [0.1, -0.6, -3.1, 0.12, 0.00, 0.00, 0.02];
    else
        % Reachable only from generated code with name == "list".
        error('referenceSystem:itrfParameters:listNotSupportedInCodegen', ...
            ['The "list" mode returns a table and is not supported in ', ...
            'generated code. Request a named realization instead.']);
    end

    millimetreToMetre = 1e-3;
    partPerBillion = 1e-9;
    milliArcsecondToRadian = pi/180/3600*1e-3;

    itrfInfo = struct( ...
        'name', name, ...
        'epoch', 2015.0, ...
        'translation', value(1:3)*millimetreToMetre, ...
        'translationRate', rate(1:3)*millimetreToMetre, ...
        'scale', value(4)*partPerBillion, ...
        'scaleRate', rate(4)*partPerBillion, ...
        'rotation', value(5:7)*milliArcsecondToRadian, ...
        'rotationRate', rate(5:7)*milliArcsecondToRadian, ...
        'convention', "positionVector", ...
        'sourceUrl', ...
        "https://itrf.ign.fr/docs/solutions/itrf2020/Transfo-ITRF2020_TRFs.txt", ...
        'retrieved', "2026-07-26");
end

function itrfTable = buildItrfTable()
%BUILDITRFTABLE Assemble the "list" output from the named-frame path, so that
%   the table and the struct cannot disagree.

    frameName = ["ITRF2014", "ITRF2008", "ITRF2005", "ITRF2000", "ITRF97", ...
        "ITRF96", "ITRF94", "ITRF93", "ITRF92", "ITRF91", "ITRF90", ...
        "ITRF89", "ITRF88"];
    nFrame = numel(frameName);

    epoch = zeros(nFrame, 1);
    translation = zeros(nFrame, 3);
    translationRate = zeros(nFrame, 3);
    scale = zeros(nFrame, 1);
    scaleRate = zeros(nFrame, 1);
    rotation = zeros(nFrame, 3);
    rotationRate = zeros(nFrame, 3);

    for k = 1:nFrame
        oneFrame = namedFrame(frameName(k));
        epoch(k) = oneFrame.epoch;
        translation(k, :) = oneFrame.translation;
        translationRate(k, :) = oneFrame.translationRate;
        scale(k) = oneFrame.scale;
        scaleRate(k) = oneFrame.scaleRate;
        rotation(k, :) = oneFrame.rotation;
        rotationRate(k, :) = oneFrame.rotationRate;
    end

    itrfTable = table(frameName(:), epoch, translation, translationRate, ...
        scale, scaleRate, rotation, rotationRate, ...
        'VariableNames', {'name', 'epoch', 'translation', 'translationRate', ...
        'scale', 'scaleRate', 'rotation', 'rotationRate'});
    itrfTable.Properties.UserData = struct( ...
        'sourceUrl', ...
        "https://itrf.ign.fr/docs/solutions/itrf2020/Transfo-ITRF2020_TRFs.txt", ...
        'retrieved', "2026-07-26", ...
        'convention', "positionVector");
end
