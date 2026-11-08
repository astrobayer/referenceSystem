function ellipsoidInfo = ellipsoidParameters(name)
%ELLIPSOIDPARAMETERS Defining and derived parameters of a reference ellipsoid.
%
%   ellipsoidInfo = ellipsoidParameters(name) returns a scalar struct with the
%   defining and derived parameters of the named rotational reference ellipsoid.
%
%   ellipsoidTable = ellipsoidParameters('list') returns a table with one row per
%   supported ellipsoid and the same quantities as variables.
%
%   Supported names, case sensitive: 'WGS84', 'GRS80', 'Bessel1841',
%   'Hayford1924', 'Krassovsky1940'.
%
% INPUT ARGUMENTS
%   Name    Size   Type     Units  Description
%   ----    ----   ----     -----  -----------
%   name    1x1    string   -      Ellipsoid name, or 'list' for the table form.
%                                  A char row vector is accepted and converted.
%
% OUTPUT ARGUMENTS
%   Name             Size   Type     Units  Description
%   ----             ----   ----     -----  -----------
%   ellipsoidInfo    1x1    struct   -      Parameters of the named ellipsoid.
%   .a               1x1    double   m      Semi-major axis, defining.
%   .b               1x1    double   m      Semi-minor axis, derived.
%   .f               1x1    double   1      Flattening, derived from 1/f.
%   .e2              1x1    double   1      First eccentricity squared, derived.
%   .ep2             1x1    double   1      Second eccentricity squared, derived.
%   .n               1x1    double   1      Third flattening f/(2-f), derived.
%   .name            1x1    string   -      Name as supplied, echoed for provenance.
%
%   For name = 'list' the output is a 5x7 table with variables name, a, b, f,
%   e2, ep2, n; name is a string column, the remaining variables are double.
%
% METHOD
%   Each ellipsoid is stored by its two defining parameters only, the semi-major
%   axis a and the inverse flattening 1/f as published by the defining authority.
%   Everything else is computed here, so no derived value can drift from the
%   defining pair:
%       f   = 1/(1/f)
%       b   = a*(1-f)
%       e2  = f*(2-f)
%       ep2 = e2/(1-e2)
%       n   = f/(2-f)
%   The struct echoes the requested name as a string. Carrying it makes the
%   ellipsoid self-describing, so a downstream function can verify rather than
%   assume which ellipsoid a coordinate set belongs to (design principle 3).
%   That the field is a string and not a char row vector is deliberate and is
%   documented here because v1's refell returned char and callers indexed it.
%
%   'list' is available in MATLAB only. The table type is not supported by
%   MATLAB Coder, so the branch is guarded by coder.target and eliminated from
%   generated code; the named-ellipsoid path is codegen-clean.
%
% ACCURACY
%   a and 1/f are exact by definition. The derived quantities carry one to three
%   double-precision roundings, at most 1.5e-9 m in b and 1e-18 in e2, which is
%   four orders of magnitude below any geodetic requirement.
%
%   GRS80 uses the published inverse flattening 298.257222101, which is itself
%   the rounded value derived from the defining set (a, GM, J2, omega). The
%   rounding shifts b by 8.4e-9 m relative to the unrounded derivation, again
%   negligible, and the published value is used because it is the one every
%   other geodetic product uses.
%
%   WGS84 and GRS80 share a but not 1/f. Their semi-minor axes differ by
%   1.05e-4 m, so at sub-millimetre precision the two are not interchangeable
%   and the choice must be stated, never defaulted, by the caller.
%
% ERRORS
%   MATLAB:validators:mustBeMember
%       Raised by the arguments block for a name that is not supported. The
%       message lists the permitted values; matching is case sensitive.
%   referenceSystem:ellipsoidParameters:listNotSupportedInCodegen
%       Raised when 'list' is requested from generated code.
%
% REFERENCES
%   NIMA TR8350.2 (2000), Department of Defense World Geodetic System 1984.
%   H. Moritz (1980), Geodetic Reference System 1980, Bull. Geodesique 54(3).
%   W. Torge and J. Mueller (2012), Geodesy, 4th ed., de Gruyter, Table 4.1.
%   IERS Conventions (2010), IERS Technical Note 36, Table 1.2.
%
% EXAMPLE
%   e = referenceSystem.ellipsoidParameters("GRS80");
%   allEllipsoids = referenceSystem.ellipsoidParameters("list");
%
% KEYWORDS
%   ellipsoid, WGS84, GRS80, Bessel, Hayford, Krassovsky, flattening,
%   eccentricity, semi-major axis, geodetic
%
% See also IERSCONSTANTS, TOOLBOXVERSION.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 11:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

%#codegen

    arguments
        name (1,1) string {mustBeMember(name, ["WGS84", "GRS80", "Bessel1841", ...
            "Hayford1924", "Krassovsky1940", "list"])}
    end

    % coder.target is constant-folded, so the table branch is removed entirely
    % from generated code and only the named-ellipsoid path is compiled.
    if coder.target('MATLAB') && strcmp(name, "list")
        ellipsoidInfo = buildEllipsoidTable();
        return
    end

    ellipsoidInfo = namedEllipsoid(name);
end

function ellipsoidInfo = namedEllipsoid(name)
%NAMEDELLIPSOID Defining pair of one ellipsoid and everything derived from it.
%   Held separately from the main function so that buildEllipsoidTable can reach
%   it without calling the main function by name: inside a package file only
%   file-local names and qualified names resolve (§C.5 rule 2).

    % An if-chain on strcmp rather than a switch: MATLAB Coder accepts a switch
    % expression only if it is numeric, char or an enumeration, and the whole
    % point of this dispatch is that it stays codegen-clean.
    if strcmp(name, "WGS84")
        a = 6378137.0;
        inverseFlattening = 298.257223563;
    elseif strcmp(name, "GRS80")
        a = 6378137.0;
        inverseFlattening = 298.257222101;
    elseif strcmp(name, "Bessel1841")
        a = 6377397.155;
        inverseFlattening = 299.1528128;
    elseif strcmp(name, "Hayford1924")
        a = 6378388.0;
        inverseFlattening = 297.0;
    elseif strcmp(name, "Krassovsky1940")
        a = 6378245.0;
        inverseFlattening = 298.3;
    else
        % Reachable only from generated code with name == "list": the validator
        % admits it but the table branch above is compiled out.
        error('referenceSystem:ellipsoidParameters:listNotSupportedInCodegen', ...
            ['The ''list'' mode returns a table and is not supported in ', ...
            'generated code. Request a named ellipsoid instead.']);
    end

    f = 1.0/inverseFlattening;
    b = a*(1.0-f);
    e2 = f*(2.0-f);

    ellipsoidInfo = struct( ...
        'a', a, ...
        'b', b, ...
        'f', f, ...
        'e2', e2, ...
        'ep2', e2/(1.0-e2), ...
        'n', f/(2.0-f), ...
        'name', name);
end

function ellipsoidTable = buildEllipsoidTable()
%BUILDELLIPSOIDTABLE Assemble the 'list' output from the named-ellipsoid path.
%   The table is built from namedEllipsoid once per name, so the table and the
%   struct can never disagree.

    names = ["WGS84", "GRS80", "Bessel1841", "Hayford1924", "Krassovsky1940"];
    nEllipsoid = numel(names);

    a = zeros(nEllipsoid, 1);
    b = zeros(nEllipsoid, 1);
    f = zeros(nEllipsoid, 1);
    e2 = zeros(nEllipsoid, 1);
    ep2 = zeros(nEllipsoid, 1);
    n = zeros(nEllipsoid, 1);

    for k = 1:nEllipsoid
        oneEllipsoid = namedEllipsoid(names(k));
        a(k) = oneEllipsoid.a;
        b(k) = oneEllipsoid.b;
        f(k) = oneEllipsoid.f;
        e2(k) = oneEllipsoid.e2;
        ep2(k) = oneEllipsoid.ep2;
        n(k) = oneEllipsoid.n;
    end

    ellipsoidTable = table(names(:), a, b, f, e2, ep2, n, ...
        'VariableNames', {'name', 'a', 'b', 'f', 'e2', 'ep2', 'n'});
end
