function alignment = graceFoImuAlignment(satellite)
%GRACEFOIMUALIGNMENT Gyro axes and IMU-to-Satellite-Frame rotation for GRACE-FO.
%
%   alignment = graceFoImuAlignment(satellite) returns the measured directions
%   of the four IMU gyro axes in the IMU frame, and the measured rotation from
%   the IMU frame to the Satellite Frame, for the named GRACE-FO satellite.
%   Both are ground-calibration constants; neither varies with time.
%
%   alignment = graceFoImuAlignment("list") returns a table of the supported
%   satellite identifiers instead.
%
% INPUT ARGUMENTS
%   Name        Size   Type            Units  Description
%   ----        ----   ----            -----  -----------
%   satellite   1x1    string | char   -      "C" or "D", any case, or "list".
%                                             This is the GRACEFO_id carried in
%                                             column 4 of every Level-1
%                                             product record.
%
% OUTPUT ARGUMENTS
%   Name                    Size   Type     Units  Description
%   ----                    ----   ----     -----  -----------
%   alignment               1x1    struct   -      Alignment constants.
%   .satellite              1x1    string   -      Canonical "C" or "D".
%   .gyroAxis               3x4    double   -      Unit direction of each gyro
%                                                  axis in the IMU frame, one
%                                                  COLUMN per gyro, gyro 1 in
%                                                  column 1.
%   .imuToSatelliteFrame    3x3    double   -      Rotation carrying a vector
%                                                  resolved in the IMU frame to
%                                                  the Satellite Frame.
%   .airbusSatelliteNumber  1x1    double   -      1 or 2, the row of the
%                                                  handbook tables this came
%                                                  from. See METHOD.
%   .source                 1x1    string   -      Citation of the tables.
%
%   For satellite == "list" the output is instead a 2x3 table with variables
%   satellite, airbusSatelliteNumber and description.
%
% METHOD
%   THE FOUR GYROS ARE A TETRAHEDRON, NOT AN ORTHOGONAL TRIAD. The four axes of
%   .gyroAxis are mutually separated by the tetrahedral angle acos(-1/3) =
%   109.4712 deg; measured from the shipped table the twelve pairwise angles lie
%   between 109.4341 and 109.5045 deg. Any three of them span the space, which
%   is what makes the fourth redundant rather than necessary. Decision D83
%   governs which three are used and what the fourth is used for; see
%   graceFoImuIncrements.
%
%   .imuToSatelliteFrame is a proper rotation to the digits published: the
%   worst element of R'*R - I is 7.2e-16 for satellite C and 6.3e-16 for
%   satellite D, and both determinants are +1 to sixteen digits. It is applied
%   as v_sf = R * v_imu.
%
%   THE SATELLITE FRAME AND THE SCIENCE REFERENCE FRAME SHARE THEIR AXES.
%   Handbook section 3.2.3 defines the SRF as having the same origin and the
%   same coordinate axes as the SF, and states that all Level-1B products are
%   provided in the SRF. No rotation therefore separates the output of
%   graceFoImuIncrements from the frame the SCA1B attitude quaternions refer to.
%
%   THE HANDBOOK TABLES ARE KEYED BY AIRBUS SATELLITE NUMBER AND THE DATA IS
%   KEYED BY SCIENCE IDENTIFIER, AND THE BRIDGE IS TABLE 3. Tables 23 and 24
%   name their rows "Satellite 1" and "Satellite 2", taken from the Airbus
%   alignment report; the Level-1 products name their satellite "C" or "D".
%   Handbook Table 3 maps the Astrium/Airbus system nomenclature FM 1 to GRACE C
%   and FM 2 to GRACE D, so satellite 1 is C and satellite 2 is D.
%
%   THAT MAPPING IS AN INFERENCE AND IT CANNOT BE CHECKED AGAINST A
%   THREE-GYRO FILE, WHICH IS WHY IT IS STATED HERE RATHER THAN ASSUMED. Three
%   gyros give three equations in three unknowns, so any alignment reproduces
%   the measurements exactly and leaves no residual to look at. The two
%   satellites' tables differ by a rotation of 214.5 arcsec, which is far too
%   small to notice in a single epoch and large enough to matter: see the
%   ACCURACY block of graceFoImuIncrements for what it costs over a day. A file
%   carrying gyro 4 would discriminate them through the D83 residual.
%
% ACCURACY
%   The tables are reproduced to every digit published. They are ground
%   calibration values and the handbook states no uncertainty for them, so
%   none is quoted here; an in-flight alignment estimate is outside this
%   toolbox.
%
%   The axis directions are used as published and are NOT re-normalised. Each
%   column of the shipped table already has unit norm to 1e-9, and forcing the
%   norm would silently change a published constant to hide a discrepancy that
%   should be visible instead.
%
% ERRORS
%   referenceSystem:graceFoImuAlignment:unknownSatellite
%
% REFERENCES
%   Wen, H. Y., et al. (2019), GRACE-FO Level-1 Data Product User Handbook,
%   JPL D-56935, Tables 23 and 24 (section 4.2.10) and Table 3 (section 2.5.1).
%   Fischer, D. (2017), AOCS Sensor Alignment, GFO-TN-ADSF-AO-50002328 Issue 3,
%   Airbus DS GmbH — the source of Tables 23 and 24.
%
% EXAMPLE
%   alignment = referenceSystem.graceFoImuAlignment("C");
%   axisAngles = acosd(alignment.gyroAxis(:,1)' * alignment.gyroAxis);
%
% KEYWORDS
%   GRACE-FO, IMU, gyro, tetrahedron, alignment, satellite frame, SRF
%
% See also GRACEFOIMUINCREMENTS, READIMU1B, INTEGRATEATTITUDE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 21:05 (CEST, UTC+02:00) - session S9, prompt P27
% -------------------------------------------------------------------------

    arguments
        satellite (1,1) string
    end

    % Handbook Table 23: components of each gyro axis in the IMU frame, one
    % COLUMN per gyro. Transcribed from the handbook, never from memory.
    gyroAxisSatellite1 = [ ...
         0.942826211, -0.472597539, -0.470092696,  0.000592072; ...
         0.001810853,  0.815825089, -0.817231401, -0.000382796; ...
         0.33327985 ,  0.333288147,  0.333385204, -0.999999751];
    gyroAxisSatellite2 = [ ...
         0.942687237, -0.471344745, -0.471100307,  0.000753399; ...
         0.000111944,  0.816437037, -0.816914065,  0.000461058; ...
         0.33367763 ,  0.333563632,  0.332740005, -0.99999961 ];

    % Handbook Table 24: rotation from the IMU frame to the Satellite Frame.
    imuToSatelliteFrame1 = [ ...
        -0.501252164183920,  0.865301254687325, -0.000080854668175; ...
         0.865300283426991,  0.501251737450002,  0.001454374272271; ...
         0.001299000425484,  0.000659044684221, -0.999998939128437];
    imuToSatelliteFrame2 = [ ...
        -0.501005885615109,  0.865443870184570,  0.000100692470726; ...
         0.865443802410115,  0.501005791604386,  0.000470795904316; ...
         0.000356999918493,  0.000323015193725, -0.999999884106115];

    citation = "JPL D-56935 Tables 23 and 24; satellite mapping from Table 3";

    if strcmpi(satellite, "list")
        alignment = table( ...
            ["C"; "D"], [1; 2], ...
            ["GRACE C, Airbus FM 1, leading at launch"; ...
             "GRACE D, Airbus FM 2, trailing at launch"], ...
            'VariableNames', ...
            {'satellite', 'airbusSatelliteNumber', 'description'});
        return
    end

    switch upper(strtrim(satellite))
        case "C"
            alignment = struct( ...
                'satellite', "C", ...
                'gyroAxis', gyroAxisSatellite1, ...
                'imuToSatelliteFrame', imuToSatelliteFrame1, ...
                'airbusSatelliteNumber', 1, ...
                'source', citation);
        case "D"
            alignment = struct( ...
                'satellite', "D", ...
                'gyroAxis', gyroAxisSatellite2, ...
                'imuToSatelliteFrame', imuToSatelliteFrame2, ...
                'airbusSatelliteNumber', 2, ...
                'source', citation);
        otherwise
            error('referenceSystem:graceFoImuAlignment:unknownSatellite', ...
                ['Satellite "%s" is not a GRACE-FO identifier. Use "C" or ' ...
                 '"D", which are the values column 4 of a Level-1 record ' ...
                 'takes, or "list" for the supported set.'], satellite);
    end
end
