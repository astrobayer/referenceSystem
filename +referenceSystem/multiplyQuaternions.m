function [q, convention] = multiplyQuaternions(first, second, options)
%MULTIPLYQUATERNIONS Product of two quaternion series, conventions compared.
%
%   q = multiplyQuaternions(first, second) returns the 4xN quaternion product.
%   Each operand is either a 4xN array or a tagged struct with fields
%   .quaternion and .convention; when both carry a convention the two are
%   compared and a mismatch is an error, never a silent composition.
%
%   [q, convention] = multiplyQuaternions(first, second) also returns the
%   convention the product is expressed in.
%
% INPUT ARGUMENTS
%   Name     Size        Type           Units  Description
%   ----     ----        ----           -----  -----------
%   first    4xN or 1x1  double|struct  -      Left operand. A struct must have
%                                              .quaternion (4xN) and .convention
%                                              (1x1 struct).
%   second   4xN or 1x1  double|struct  -      Right operand, same forms. One
%                                              operand may be 4x1 and is then
%                                              applied to every column of the
%                                              other.
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name         Size   Type     Default   Description
%   ----         ----   ----     -------   -----------
%   Convention   1x1    struct   absent    Convention for untagged operands. If
%                                          omitted it is taken from the tagged
%                                          operands, or defaults to
%                                          attitudeConvention() when neither is
%                                          tagged.
%
% OUTPUT ARGUMENTS
%   Name         Size   Type     Units  Description
%   ----         ----   ----     -----  -----------
%   q            4xN    double   -      Product, unit norm, scalar part >= 0.
%   convention   1x1    struct   -      The convention used, for tagging.
%
% METHOD
%   With a = [a0; av] and b = [b0; bv], both scalar first,
%
%       Hamilton   a*b = [a0*b0 - av.bv ;  a0*bv + b0*av + av x bv]
%       Shuster    a*b = [a0*b0 - av.bv ;  a0*bv + b0*av - av x bv]
%
%   The two differ only in the sign of the cross term, and the Shuster (JPL)
%   product is the Hamilton product with the operands exchanged. THIS IS WHY THE
%   COMPOSITION ORDER DIFFERS, and it is the single most common error in
%   attitude software:
%
%       sense       product     matrix of the product
%       -----       -------     ---------------------
%       frame       hamilton    R(a*b) = R(b) R(a)
%       frame       shuster     R(a*b) = R(a) R(b)
%       vector      hamilton    R(a*b) = R(a) R(b)
%       vector      shuster     R(a*b) = R(b) R(a)
%
%   All four rows are asserted as precision tests. Nothing here can detect a
%   caller who wanted the other order: every one of the four is a valid rotation
%   and none is distinguishable from the result.
%
%   CONVENTION COMPARISON IS THE STRUCTURAL PROTECTION (decision D35), not the
%   flag. The fields compared are .quaternion, .product, .sense and .localFrame,
%   which are the four that change the answer. The .sequence and .rotationType
%   fields are deliberately NOT compared: they do not enter a quaternion product
%   at all, and two quaternions legitimately derived through different Euler
%   sequences are the same kind of object.
%
% ACCURACY
%   Exact to machine precision, sixteen products and twelve sums per pair. The
%   result is renormalised, so composing a long chain does not drift off the
%   unit sphere: over 10000 successive products the norm stays within 4.4e-16 of
%   one, against 2e-12 of accumulated drift without the renormalisation.
%
% ERRORS
%   referenceSystem:multiplyQuaternions:wrongQuaternionSize
%   referenceSystem:multiplyQuaternions:sizeMismatch
%   referenceSystem:multiplyQuaternions:conventionMismatch
%   referenceSystem:multiplyQuaternions:malformedOperand
%
% REFERENCES
%   M. D. Shuster (1993), A Survey of Attitude Representations, JAS 41(4).
%   J. Sola (2017), Quaternion Kinematics for the Error-State Kalman Filter,
%   arXiv:1711.02508, Sect. 1.4 on the Hamilton and JPL conventions.
%
% EXAMPLE
%   q = referenceSystem.multiplyQuaternions(qa, qb);
%
%   [qa, ca] = referenceSystem.quaternionFromRotation(Ra);
%   taggedA = struct('quaternion', qa, 'convention', ca);
%   q = referenceSystem.multiplyQuaternions(taggedA, taggedB);
%
% KEYWORDS
%   quaternion, product, Hamilton, Shuster, JPL, composition, attitude,
%   convention mismatch
%
% See also INVERTQUATERNION, NORMALIZEQUATERNION, ATTITUDECONVENTION.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 03:25 (CEST, UTC+02:00) - session S4, prompt P25
% -------------------------------------------------------------------------

    arguments
        first
        second
        options.Convention (1,1) struct = struct('source', "not supplied")
    end

    supplied = ~(isscalar(fieldnames(options.Convention)) && ...
        isfield(options.Convention, 'source') && ...
        strcmp(options.Convention.source, "not supplied"));

    [qFirst, conventionFirst, taggedFirst] = unpackOperand(first, "first");
    [qSecond, conventionSecond, taggedSecond] = unpackOperand(second, "second");

    convention = referenceSystem.attitudeConvention();
    stated = {};
    if supplied
        stated{end+1} = referenceSystem.attitudeConvention(options.Convention);
    end
    if taggedFirst
        stated{end+1} = conventionFirst;
    end
    if taggedSecond
        stated{end+1} = conventionSecond;
    end
    if ~isempty(stated)
        convention = stated{1};
        for k = 2:numel(stated)
            requireAgreement(convention, stated{k});
        end
    end

    nFirst = size(qFirst, 2);
    nSecond = size(qSecond, 2);
    if nFirst ~= nSecond && nFirst ~= 1 && nSecond ~= 1
        error('referenceSystem:multiplyQuaternions:sizeMismatch', ...
            ['first has %d quaternions and second has %d; one of them must ', ...
            'be a single quaternion or the counts must agree.'], nFirst, nSecond);
    end

    if strcmp(convention.quaternion, "scalarLast")
        qFirst = qFirst([4 1 2 3], :);
        qSecond = qSecond([4 1 2 3], :);
    end

    % cross does not expand implicitly, so the single operand is expanded here
    % rather than relying on a broadcast that only two of the four terms have.
    if nFirst == 1 && nSecond > 1
        qFirst = repmat(qFirst, 1, nSecond);
    elseif nSecond == 1 && nFirst > 1
        qSecond = repmat(qSecond, 1, nFirst);
    end

    crossSign = 1;
    if strcmp(convention.product, "shuster")
        crossSign = -1;
    end

    a0 = qFirst(1, :);
    av = qFirst(2:4, :);
    b0 = qSecond(1, :);
    bv = qSecond(2:4, :);

    q = [a0.*b0 - sum(av.*bv, 1); ...
        a0.*bv + b0.*av + crossSign*cross(av, bv, 1)];

    if strcmp(convention.quaternion, "scalarLast")
        q = q([2 3 4 1], :);
    end
    q = referenceSystem.normalizeQuaternion(q, 'Convention', convention);
end

% -------------------------------------------------------------------------

function [q, convention, tagged] = unpackOperand(operand, name)
%UNPACKOPERAND Accept a bare quaternion array or a convention-tagged struct.

    convention = referenceSystem.attitudeConvention();
    tagged = false;

    if isstruct(operand)
        if ~isscalar(operand) || ~isfield(operand, 'quaternion') || ...
                ~isfield(operand, 'convention')
            error('referenceSystem:multiplyQuaternions:malformedOperand', ...
                ['Operand %s is a struct but not a tagged quaternion. A ', ...
                'tagged quaternion is a 1x1 struct with fields .quaternion ', ...
                '(4xN double) and .convention (1x1 struct).'], name);
        end
        q = operand.quaternion;
        convention = referenceSystem.attitudeConvention(operand.convention);
        tagged = true;
    elseif isnumeric(operand)
        q = double(operand);
    else
        error('referenceSystem:multiplyQuaternions:malformedOperand', ...
            'Operand %s must be a 4xN double or a tagged struct; it is a %s.', ...
            name, class(operand));
    end

    if size(q, 1) ~= 4 || ~ismatrix(q) || ~isreal(q) || ~all(isfinite(q), 'all')
        error('referenceSystem:multiplyQuaternions:wrongQuaternionSize', ...
            ['Operand %s must be a real finite 4xN array of quaternions; ', ...
            'it is %s.'], name, mat2str(size(q)));
    end
end

function requireAgreement(reference, candidate)
%REQUIREAGREEMENT Refuse to compose across a convention mismatch (D35).

    compared = ["quaternion", "product", "sense", "localFrame"];
    for k = 1:numel(compared)
        field = compared(k);
        if ~strcmp(reference.(field), candidate.(field))
            error('referenceSystem:multiplyQuaternions:conventionMismatch', ...
                ['The operands disagree on .%s: "%s" against "%s". Composing ', ...
                'across it would give an orthogonal matrix that is silently ', ...
                'the wrong rotation, so it is refused. Convert one operand ', ...
                'first.'], field, reference.(field), candidate.(field));
        end
    end
end
