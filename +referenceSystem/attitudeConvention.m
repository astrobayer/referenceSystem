function convention = attitudeConvention(specification)
%ATTITUDECONVENTION Build or validate the rotation-algebra convention struct.
%
%   convention = attitudeConvention() returns the geodetic default: scalar-first
%   Hamilton quaternions, ENU local frame, frame (passive) rotations and the
%   intrinsic ZYX Euler sequence.
%
%   convention = attitudeConvention(presetName) returns a named preset,
%   "geodetic" or "aerospace".
%
%   convention = attitudeConvention(userStruct) validates a struct the caller
%   built and returns it in canonical form. Any unknown field, any missing
%   field and any unknown value is an error; nothing is silently ignored and
%   nothing is silently filled in.
%
% INPUT ARGUMENTS
%   Name            Size   Type            Units  Description
%   ----            ----   ----            -----  -----------
%   specification   1x1    string|struct   -      Preset name or a convention
%                                                 struct to validate. A char row
%                                                 vector is accepted for the
%                                                 name and converted.
%
% OUTPUT ARGUMENTS
%   Name             Size   Type     Units  Description
%   ----             ----   ----     -----  -----------
%   convention       1x1    struct   -      Validated convention.
%   .sequence        1x1    string   -      Euler sequence, one of the twelve
%                                           "XYZ".."ZYZ", or "" where none
%                                           applies.
%   .rotationType    1x1    string   -      "intrinsic" (body-fixed axes) or
%                                           "extrinsic" (space-fixed axes).
%   .sense           1x1    string   -      "frame" (passive, alias) or
%                                           "vector" (active, alibi).
%   .quaternion      1x1    string   -      "scalarFirst" [q0 q1 q2 q3] or
%                                           "scalarLast" [q1 q2 q3 q0].
%   .product         1x1    string   -      "hamilton" or "shuster".
%   .localFrame      1x1    string   -      "ENU", "NED" or "none".
%   .source          1x1    string   -      Provenance, free text.
%
% METHOD
%   Navigation and geodesy disagree on every line of that table, and every
%   wrong combination produces a matrix that is still orthogonal, still of unit
%   determinant, and still round trips through its own inverse. There is no
%   runtime symptom. The error appears only when the result meets somebody
%   else's data, which is finding C-2's failure mode exactly, and it is why the
%   convention is a struct carried with the data rather than ten name-value
%   flags spread over the call sites.
%
%   The two presets:
%
%     field          geodetic (default)   aerospace
%     -----          ------------------   ---------
%     sequence       ZYX                  ZYX
%     rotationType   intrinsic            intrinsic
%     sense          frame                frame
%     quaternion     scalarFirst          scalarLast
%     product        hamilton             shuster
%     localFrame     ENU                  NED
%
%   The geodetic default agrees with SOFA's matrix conventions, with the
%   GRACE-FO SCA1B quaternion convention and with the rest of this toolbox.
%   ZYX intrinsic is the default sequence because it is the near-universal
%   choice wherever roll, pitch and yaw are meant, and naming a sequence at all
%   is meaningless without one.
%
%   THE DEFAULT IS A DEFAULT, NEVER AN ASSUMPTION. Every function that returns
%   a rotation object records the convention it used; every function that
%   consumes one reads it. Functions taking two rotation objects compare their
%   conventions and error on a mismatch rather than composing across it.
%
%   Validation is exhaustive in MATLAB. The scan for unknown fields uses
%   fieldnames and is therefore guarded by coder.target, so it is eliminated
%   from generated code; every other check is a static field read and survives
%   code generation. A struct reaching generated code is assumed to have been
%   validated in MATLAB first.
%
% ACCURACY
%   Exact. This function performs no arithmetic; it names and checks a
%   convention. Its whole accuracy contribution is that it makes the silent
%   convention mismatch impossible, which is worth up to 180 degrees of
%   attitude error and is not detectable by any numerical test on the result.
%
% ERRORS
%   referenceSystem:attitudeConvention:unknownPreset
%   referenceSystem:attitudeConvention:wrongType
%   referenceSystem:attitudeConvention:unknownField
%   referenceSystem:attitudeConvention:missingField
%   referenceSystem:attitudeConvention:unknownValue
%
% REFERENCES
%   M. D. Shuster (1993), A Survey of Attitude Representations, Journal of the
%   Astronautical Sciences 41(4), 439-517.
%   J. Sola (2017), Quaternion Kinematics for the Error-State Kalman Filter,
%   arXiv:1711.02508, Sect. 1 on the Hamilton and JPL conventions.
%   IERS Conventions (2010), IERS Technical Note 36, Ch. 5 for the frame sense.
%
% EXAMPLE
%   c = referenceSystem.attitudeConvention();
%   q = referenceSystem.quaternionFromRotation(R, 'Convention', c);
%   navigationConvention = referenceSystem.attitudeConvention("aerospace");
%
% KEYWORDS
%   attitude, convention, quaternion, Hamilton, Shuster, JPL, Euler, intrinsic,
%   extrinsic, passive, active, ENU, NED
%
% See also QUATERNIONFROMROTATION, ROTATIONFROMEULERSEQUENCE, MULTIPLYQUATERNIONS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 02:05 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

%#codegen

    arguments
        specification = "geodetic"
    end

    if isstruct(specification)
        convention = validateConvention(specification);
        return
    end

    if ~(isstring(specification) || ischar(specification))
        error('referenceSystem:attitudeConvention:wrongType', ...
            ['specification must be a preset name or a convention struct; ', ...
            'it is a %s.'], class(specification));
    end

    presetName = string(specification);
    if ~isscalar(presetName)
        error('referenceSystem:attitudeConvention:wrongType', ...
            'A preset name must be a single string, not %d strings.', ...
            numel(presetName));
    end

    if strcmp(presetName, "geodetic")
        convention = buildConvention("ZYX", "intrinsic", "frame", ...
            "scalarFirst", "hamilton", "ENU", "geodetic preset");
    elseif strcmp(presetName, "aerospace")
        convention = buildConvention("ZYX", "intrinsic", "frame", ...
            "scalarLast", "shuster", "NED", "aerospace preset");
    else
        error('referenceSystem:attitudeConvention:unknownPreset', ...
            ['"%s" is not a preset. The presets are "geodetic" and ', ...
            '"aerospace"; build any other convention as a struct and pass ', ...
            'it here to be validated.'], presetName);
    end
end

% -------------------------------------------------------------------------

function convention = buildConvention(sequence, rotationType, sense, ...
        quaternion, product, localFrame, source)
%BUILDCONVENTION Assemble the struct in its canonical field order.

    convention = struct( ...
        'sequence', sequence, ...
        'rotationType', rotationType, ...
        'sense', sense, ...
        'quaternion', quaternion, ...
        'product', product, ...
        'localFrame', localFrame, ...
        'source', source);
end

function convention = validateConvention(candidate)
%VALIDATECONVENTION Check every field of a user-built convention struct.

    if ~isscalar(candidate)
        error('referenceSystem:attitudeConvention:wrongType', ...
            'A convention must be a 1x1 struct; it is %s.', ...
            mat2str(size(candidate)));
    end

    knownField = ["sequence", "rotationType", "sense", "quaternion", ...
        "product", "localFrame", "source"];

    % fieldnames is a compile-time constant under codegen but the set
    % difference is not, so the unknown-field scan is MATLAB only (D39
    % pattern). Everything below it is a static field read.
    if coder.target('MATLAB')
        presentField = string(fieldnames(candidate));
        unknown = setdiff(presentField, knownField);
        if ~isempty(unknown)
            error('referenceSystem:attitudeConvention:unknownField', ...
                ['The convention carries unknown field(s) %s. A field that ', ...
                'is not read is worse than one that is missing, so it is ', ...
                'refused rather than ignored. Known fields: %s.'], ...
                strjoin("'" + unknown(:)' + "'", ", "), ...
                strjoin(knownField, ", "));
        end
    end

    requireField(candidate, "sequence");
    requireField(candidate, "rotationType");
    requireField(candidate, "sense");
    requireField(candidate, "quaternion");
    requireField(candidate, "product");
    requireField(candidate, "localFrame");

    sequence = checkValue(candidate.sequence, "sequence", ...
        ["XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX", ...
        "XYX", "XZX", "YXY", "YZY", "ZXZ", "ZYZ", ""]);
    rotationType = checkValue(candidate.rotationType, "rotationType", ...
        ["intrinsic", "extrinsic"]);
    sense = checkValue(candidate.sense, "sense", ["frame", "vector"]);
    quaternion = checkValue(candidate.quaternion, "quaternion", ...
        ["scalarFirst", "scalarLast"]);
    product = checkValue(candidate.product, "product", ["hamilton", "shuster"]);
    localFrame = checkValue(candidate.localFrame, "localFrame", ...
        ["ENU", "NED", "none"]);

    if isfield(candidate, 'source')
        source = string(candidate.source);
    else
        source = "user struct";
    end

    convention = buildConvention(sequence, rotationType, sense, quaternion, ...
        product, localFrame, source);
end

function requireField(candidate, name)
%REQUIREFIELD Refuse a convention that omits a field rather than defaulting it.

    if ~isfield(candidate, name)
        error('referenceSystem:attitudeConvention:missingField', ...
            ['The convention has no field "%s". Every field is required, ', ...
            'because a field filled in silently is an assumption the caller ', ...
            'never made. Start from referenceSystem.attitudeConvention() and ', ...
            'change what you need.'], name);
    end
end

function value = checkValue(candidate, name, permitted)
%CHECKVALUE Require one of the documented values for one field.

    if ~(isstring(candidate) || ischar(candidate))
        error('referenceSystem:attitudeConvention:unknownValue', ...
            'Field "%s" must be text; it is a %s.', name, class(candidate));
    end
    value = string(candidate);
    if ~isscalar(value) || ~any(strcmp(value, permitted))
        error('referenceSystem:attitudeConvention:unknownValue', ...
            'Field "%s" is "%s"; the permitted values are %s.', name, ...
            join(value, " "), strjoin("""" + permitted + """", ", "));
    end
end
