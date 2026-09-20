classdef TestTime < matlab.unittest.TestCase
%TESTTIME Layer L0 test suite — time, constants and the toolbox metadata.
%
%   Covers the P0 deliverables toolboxVersion, iersConstants and
%   ellipsoidParameters. The epoch type, leap seconds, time-scale conversion and
%   the fundamental arguments are added to this class by P1 to P4 and P24.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly, as required by handover section C.5 rule 4. It must never
%   import referenceSystem.*: an import would hide a function accidentally left
%   out of the namespace, which is exactly what these tests exist to catch.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 11:05 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    properties (TestParameter)
        % Every ellipsoid supported by ellipsoidParameters.
        ellipsoidName = {'WGS84', 'GRS80', 'Bessel1841', 'Hayford1924', 'Krassovsky1940'};
    end

    methods (Test, TestTags = {'contract'})

        function toolboxVersion_contract_returnsDocumentedFields(testCase)
            versionInfo = referenceSystem.toolboxVersion();

            testCase.verifyClass(versionInfo, 'struct');
            testCase.verifySize(versionInfo, [1 1]);
            testCase.verifyEqual(sort(string(fieldnames(versionInfo))), ...
                sort(["version"; "release"; "patch"; "buildDate"; ...
                "sofaRelease"; "iersConventions"; "author"; "generator"; ...
                "versionTag"; "helpTag"]));

            fieldName = string(fieldnames(versionInfo));
            for k = 1:numel(fieldName)
                value = versionInfo.(fieldName(k));
                testCase.verifyClass(value, 'string', ...
                    "Field " + fieldName(k) + " must be a string scalar.");
                testCase.verifySize(value, [1 1]);
            end

            % NO VERSION LITERAL IS ASSERTED HERE ANY MORE (D107). It would
            % have to be edited in this file on every revision, and a literal
            % that must be edited in step with the thing it checks is not a
            % check. What is asserted is the COMPOSITION - that version is
            % major.minor.patch and that its patch is the handover revision -
            % which holds for every revision without being rewritten for any.
            testCase.verifyEqual(versionInfo.version, ...
                versionInfo.release + "." + versionInfo.patch, ...
                'version must be exactly release.patch.');
            testCase.verifyEqual(versionInfo.versionTag, ...
                "referenceSystem v" + versionInfo.release, ...
                'The footer tag carries the release and never the patch.');
            testCase.verifyEqual(versionInfo.sofaRelease, "20231011");
            testCase.verifyEqual(versionInfo.iersConventions, "2010");

            % D103: BOTH TAG LINES MUST FIT THE SECTION C.1 COLUMN LIMIT WITH
            % THE COMMENT PREFIX ON THEM, and that is the property the split
            % exists to satisfy - not the split itself, which is only how it
            % was satisfied. Asserting the limit rather than the wording means
            % a later change of author or model that no longer fits is caught
            % here, in one place, instead of as 233 style failures in the audit.
            testCase.verifyLessThanOrEqual( ...
                strlength("% " + versionInfo.versionTag), 100);
            testCase.verifyLessThanOrEqual( ...
                strlength("% " + versionInfo.helpTag), 100);
            testCase.verifyTrue(contains(versionInfo.helpTag, versionInfo.author), ...
                'The authorship tag must name the author it is composed from.');
            testCase.verifyFalse(contains(versionInfo.versionTag, "Claude"), ...
                'The version line carries no provenance; that is the other line.');
        end

        function toolboxVersion_contract_patchIsTheHandoverRevision(testCase)
            % DECISION D107, ENFORCED RATHER THAN CONVENTIONAL. The patch
            % component of the semantic version IS the handover revision
            % number: version 2.1.166 is the state of these sources at
            % revision 1.166. That ties an archived copy of the toolbox to the
            % revision log entry that explains it, which dates cannot do - two
            % revisions on one day are ordinary here.
            %
            % THE HANDOVER IS THE AUTHORITY AND THE VERSION IS THE CONSUMER,
            % so the parse runs in that direction. The top row of the revision
            % log is the current revision, because the log is written newest
            % first; anchoring on the first "| 1.x |" line therefore needs no
            % sort and no maximum, and a row inserted in the wrong place shows
            % up here rather than silently becoming the version.
            handover = fullfile(testCase.toolboxRoot(), ...
                'HANDOVER_referenceSystem.md');
            testCase.assumeTrue(isfile(handover), ...
                ['The handover document is not in this distribution, so ', ...
                'decision D107 cannot be checked here. auditPackage.py ', ...
                'checks it in the development tree, where it is always ', ...
                'present.']);

            token = regexp(string(fileread(handover)), ...
                '^\|\s*1\.(\d+)\s*\|', 'tokens', 'lineanchors', 'once');
            testCase.assertNotEmpty(token, ...
                'The handover revision log has no parseable "| 1.x |" row.');

            % READ AS A FIELD, NEVER PARSED OUT OF version. That is O30's
            % rule and the reason toolboxVersion exposes patch at all.
            versionInfo = referenceSystem.toolboxVersion();

            % token{1}, NOT token(1): with 'once' the tokens come back as a
            % cell array of char, so the braces are what yields the text and
            % the parentheses would hand sprintf a cell.
            testCase.verifyEqual(versionInfo.patch, string(token{1}), sprintf( ...
                ['The version is %s and the handover is at revision 1.%s. ', ...
                'D107 makes these the same number, and they are written in ', ...
                'the same edit: bump patchVersion in toolboxVersion.m when ', ...
                'you write the revision log entry, not afterwards.'], ...
                versionInfo.version, token{1}));
        end

        function toolboxVersion_contract_versionMatchesContents(testCase)
            % toolboxVersion is the single source of the version string; the
            % Contents.m header is a consumer and must agree with it.
            contentsText = fileread(fullfile(testCase.packageFolder(), 'Contents.m'));
            token = regexp(contentsText, '^%\s*Version\s+(\d+\.\d+\.\d+)', ...
                'tokens', 'lineanchors', 'once');

            testCase.assertNotEmpty(token, ...
                'Contents.m has no parseable "% Version x.y.z" line.');
            testCase.verifyEqual(string(token{1}), referenceSystem.toolboxVersion().version);
        end

        function iersConstants_contract_returnsScalarStructOfDoubles(testCase)
            constants = referenceSystem.iersConstants();

            testCase.verifyClass(constants, 'struct');
            testCase.verifySize(constants, [1 1]);
            testCase.verifyEqual(sort(string(fieldnames(constants))), ...
                sort(["ttMinusTai"; "lg"; "lb"; "tdb0"; "gpsMinusTai"; "bdtMinusTai"; ...
                "earthRotationRate"; "eraRatePerUt1Second"; ...
                "arcsecondsToRadians"; "julianDateOffset"; ...
                "mjdJ2000"; "secondsPerDay"; "mjdTai1977"; "mjdTt1977"; ...
                "speedOfLight"; "lc"; "gmSun"; "gmEarth"; ...
                "moonEarthMassRatio"; "gmMoon"]));

            fieldName = string(fieldnames(constants));
            for k = 1:numel(fieldName)
                value = constants.(fieldName(k));
                testCase.verifyClass(value, 'double', ...
                    "Field " + fieldName(k) + " must be a double scalar.");
                testCase.verifySize(value, [1 1]);
                testCase.verifyTrue(isfinite(value), ...
                    "Field " + fieldName(k) + " must be finite.");
            end
        end

        function ellipsoidParameters_contract_returnsDocumentedFields(testCase, ellipsoidName)
            ellipsoidInfo = referenceSystem.ellipsoidParameters(ellipsoidName);

            testCase.verifyClass(ellipsoidInfo, 'struct');
            testCase.verifySize(ellipsoidInfo, [1 1]);
            testCase.verifyEqual(string(fieldnames(ellipsoidInfo)), ...
                ["a"; "b"; "f"; "e2"; "ep2"; "n"; "name"]);

            testCase.verifyClass(ellipsoidInfo.name, 'string');
            testCase.verifyEqual(ellipsoidInfo.name, string(ellipsoidName));

            numericField = ["a", "b", "f", "e2", "ep2", "n"];
            for k = 1:numel(numericField)
                value = ellipsoidInfo.(numericField(k));
                testCase.verifyClass(value, 'double');
                testCase.verifySize(value, [1 1]);
                testCase.verifyGreaterThan(value, 0);
            end
        end

        function ellipsoidParameters_contract_acceptsCharInput(testCase)
            fromChar = referenceSystem.ellipsoidParameters('WGS84');
            fromString = referenceSystem.ellipsoidParameters("WGS84");

            testCase.verifyEqual(fromChar, fromString);
            testCase.verifyClass(fromChar.name, 'string');
        end

        function ellipsoidParameters_contract_rejectsUnknownName(testCase)
            testCase.verifyError(@() referenceSystem.ellipsoidParameters("Airy1830"), ...
                'MATLAB:validators:mustBeMember');
        end

        function ellipsoidParameters_contract_isCaseSensitive(testCase)
            % Documented behaviour: mustBeMember matches exactly, so a lower-case
            % name is rejected rather than silently normalised.
            testCase.verifyError(@() referenceSystem.ellipsoidParameters("wgs84"), ...
                'MATLAB:validators:mustBeMember');
        end

        function ellipsoidParameters_contract_listReturnsTable(testCase)
            ellipsoidTable = referenceSystem.ellipsoidParameters("list");

            testCase.verifyClass(ellipsoidTable, 'table');
            testCase.verifyEqual(height(ellipsoidTable), 5);
            testCase.verifyEqual(string(ellipsoidTable.Properties.VariableNames), ...
                ["name", "a", "b", "f", "e2", "ep2", "n"]);
            testCase.verifyClass(ellipsoidTable.name, 'string');

            % The table is assembled from the struct path, so the two must agree.
            for k = 1:height(ellipsoidTable)
                ellipsoidInfo = referenceSystem.ellipsoidParameters(ellipsoidTable.name(k));
                testCase.verifyEqual(ellipsoidTable.a(k), ellipsoidInfo.a);
                testCase.verifyEqual(ellipsoidTable.b(k), ellipsoidInfo.b);
                testCase.verifyEqual(ellipsoidTable.e2(k), ellipsoidInfo.e2);
            end
        end

    end

    methods (Test, TestTags = {'reference'})

        function iersConstants_reference_tableOneOneValuesAndTheDerivedMoon(testCase)
            % The six values added for P21b, against IERS Conventions (2010)
            % Table 1.1 rather than against each other. gmMoon is DERIVED from
            % the ratio and gmEarth, so it is checked as a derivation and not
            % as a seventh literal - a second copy is what would drift.
            constants = referenceSystem.iersConstants();

            testCase.verifyEqual(constants.speedOfLight, 299792458, 'AbsTol', 0, ...
                'c is a defining constant and must be exact.');
            testCase.verifyEqual(constants.lc, 1.48082686741e-8, 'AbsTol', 0);
            testCase.verifyEqual(constants.gmSun, 1.32712442099e20, 'AbsTol', 0);
            testCase.verifyEqual(constants.gmEarth, 3.986004418e14, 'AbsTol', 0);
            testCase.verifyEqual(constants.moonEarthMassRatio, 0.0123000371, ...
                'AbsTol', 0);
            testCase.verifyEqual(constants.gmMoon, ...
                constants.moonEarthMassRatio*constants.gmEarth, 'AbsTol', 0, ...
                'gmMoon must be derived, not stated.');

            % THE TWO ROTATION RATES MUST NOT BE EQUAL, AND THE TEST SAYS SO.
            % earthRotationRate is a nominal mean rate its own help forbids
            % using to propagate an angle; eraRatePerUt1Second is the exact
            % slope of the ERA formula in UT1. They differ by 2.0e-8 relative,
            % and a future edit that "tidied" one into the other would bias
            % every Delta UT1 partial by that amount, silently.
            testCase.verifyEqual(constants.eraRatePerUt1Second, ...
                2*pi*1.00273781191135448/86400, 'AbsTol', 0);
            testCase.verifyNotEqual(constants.eraRatePerUt1Second, ...
                constants.earthRotationRate, ...
                'These are different constants and must stay different.');
            testCase.verifyEqual(abs(constants.eraRatePerUt1Second/ ...
                constants.earthRotationRate - 1), 2.0e-8, 'RelTol', 0.05, ...
                'The two rates must differ by the documented 2e-8.');

            % L_B is a current estimate of L_C + L_G - L_C*L_G (IAU 2006 B3,
            % note 2), which relates three constants this struct holds through
            % an identity none of them was fitted to.
            testCase.verifyEqual(constants.lb, ...
                constants.lc + constants.lg - constants.lc*constants.lg, ...
                'RelTol', 1e-9, ...
                'L_B must agree with L_C + L_G - L_C*L_G to the stated tier.');
        end

        function iersConstants_reference_sofaHeaderLiterals(testCase)
            % Independent literals: the constants of IAU SOFA sofa.h, release
            % 20231011. Exact equality, no tolerance: these are defining values
            % and their double representations must be bit-identical.
            constants = referenceSystem.iersConstants();
            julianDateOfJ2000 = 2451545.0;   % SOFA DJM00

            testCase.verifyEqual(constants.ttMinusTai, 32.184);            % SOFA TTMTAI
            testCase.verifyEqual(constants.secondsPerDay, 86400.0);        % SOFA DAYSEC
            testCase.verifyEqual(constants.julianDateOffset, 2400000.5);   % SOFA DJM0
            testCase.verifyEqual(constants.mjdJ2000, ...
                julianDateOfJ2000-constants.julianDateOffset);
            testCase.verifyEqual(constants.arcsecondsToRadians, ...
                4.848136811095359935899141e-6);                            % SOFA DAS2R
        end

        function iersConstants_reference_iauResolutionValues(testCase)
            % IAU 2000 Resolution B1.9 (L_G), IAU 2006 Resolution B3 (L_B, TDB0),
            % IERS Conventions (2010) TN36 Table 1.1 (omega_earth), and the GNSS
            % time-scale definitions. Exact equality: all are defining offsets.
            constants = referenceSystem.iersConstants();

            testCase.verifyEqual(constants.lg, 6.969290134e-10);
            testCase.verifyEqual(constants.lb, 1.550519768e-8);
            testCase.verifyEqual(constants.tdb0, -6.55e-5);
            testCase.verifyEqual(constants.earthRotationRate, 7.292115e-5);
            testCase.verifyEqual(constants.gpsMinusTai, -19.0);
            testCase.verifyEqual(constants.bdtMinusTai, -33.0);
            testCase.verifyEqual(constants.mjdTai1977, 43144.0);
        end

        function ellipsoidParameters_reference_publishedSemiMinorAxes(testCase)
            % Published semi-minor axes, each from the defining authority rather
            % than recomputed here. AbsTol equals the last published digit and
            % therefore bounds the publication precision, not the derivation.
            expectedB = struct( ...
                'WGS84', 6356752.3142, ...          % NIMA TR8350.2, 4 decimals
                'GRS80', 6356752.3141, ...          % Moritz 1980, 4 decimals
                'Bessel1841', 6356078.963, ...      % Torge & Mueller, 3 decimals
                'Hayford1924', 6356911.946, ...     % Torge & Mueller, 3 decimals
                'Krassovsky1940', 6356863.019);     % Torge & Mueller, 3 decimals
            absoluteTolerance = [0.5e-4, 0.5e-4, 0.5e-3, 0.5e-3, 0.5e-3];

            name = string(fieldnames(expectedB));
            for k = 1:numel(name)
                ellipsoidInfo = referenceSystem.ellipsoidParameters(name(k));
                testCase.verifyEqual(ellipsoidInfo.b, expectedB.(name(k)), ...
                    'AbsTol', absoluteTolerance(k), ...
                    "Semi-minor axis of " + name(k) + " disagrees with the published value.");
            end
        end

        function ellipsoidParameters_reference_publishedEccentricities(testCase)
            % WGS84 eccentricities as published in NIMA TR8350.2 to twelve
            % significant digits; RelTol bounds that publication precision.
            ellipsoidInfo = referenceSystem.ellipsoidParameters("WGS84");

            testCase.verifyEqual(ellipsoidInfo.e2, 6.694379990141e-3, 'RelTol', 1e-12);
            testCase.verifyEqual(ellipsoidInfo.ep2, 6.739496742276e-3, 'RelTol', 1e-12);
            testCase.verifyEqual(1.0/ellipsoidInfo.f, 298.257223563, 'RelTol', 1e-14);
        end

    end

    methods (Test, TestTags = {'precision'})

        function iersConstants_precision_derivedEpochConsistency(testCase)
            % mjdTt1977 must be mjdTai1977 advanced by exactly TT-TAI. AbsTol is
            % one unit in the last place of a day number near 43144 (7.3e-12 d),
            % which bounds the loss of resolution in an unsplit day number and is
            % the quantitative reason the epoch type of P1 carries day and second
            % separately.
            constants = referenceSystem.iersConstants();

            testCase.verifyEqual(constants.mjdTt1977-constants.mjdTai1977, ...
                constants.ttMinusTai/constants.secondsPerDay, 'AbsTol', 1e-11);
        end

        function iersConstants_precision_arcsecondRoundTrip(testCase)
            % A full circle expressed in arcseconds and converted to radians must
            % return 2*pi. RelTol bounds the two roundings of the conversion
            % factor and the product, not any physical quantity.
            constants = referenceSystem.iersConstants();
            arcsecondsPerRevolution = 360.0*3600.0;

            testCase.verifyEqual(arcsecondsPerRevolution*constants.arcsecondsToRadians, ...
                2.0*pi, 'RelTol', 4*eps);
        end

        function ellipsoidParameters_precision_derivedParameterIdentities(testCase, ellipsoidName)
            % Each derived quantity is recomputed here from a and b by a formula
            % different from the one the function uses, so the check is an
            % identity test and not an echo. RelTol bounds the double-precision
            % evaluation of the identities; no ellipsoid uncertainty enters.
            ellipsoidInfo = referenceSystem.ellipsoidParameters(ellipsoidName);
            a = ellipsoidInfo.a;
            b = ellipsoidInfo.b;

            testCase.verifyEqual(ellipsoidInfo.f, (a-b)/a, 'RelTol', 1e-13);
            testCase.verifyEqual(ellipsoidInfo.e2, (a*a-b*b)/(a*a), 'RelTol', 1e-12);
            testCase.verifyEqual(ellipsoidInfo.ep2, (a*a-b*b)/(b*b), 'RelTol', 1e-12);
            testCase.verifyEqual(ellipsoidInfo.n, (a-b)/(a+b), 'RelTol', 1e-13);
            testCase.verifyLessThan(ellipsoidInfo.b, ellipsoidInfo.a);
        end

        function ellipsoidParameters_precision_wgs84AndGrs80AreNotInterchangeable(testCase)
            % The two share a but not 1/f. The ACCURACY block claims their
            % semi-minor axes differ by 1.05e-4 m; assert that claim so it cannot
            % rot. AbsTol bounds the derivation of b, not the ellipsoids.
            wgs84 = referenceSystem.ellipsoidParameters("WGS84");
            grs80 = referenceSystem.ellipsoidParameters("GRS80");

            testCase.verifyEqual(wgs84.a, grs80.a);
            testCase.verifyEqual(wgs84.b-grs80.b, 1.048e-4, 'AbsTol', 1e-7);
        end

    end


    % =====================================================================
    % Session S1 — the epoch type, leap seconds, time scales and the
    % fundamental arguments (prompts P1, P3, P4 and P24).
    %
    % Every test that needs the compiled gateway assumes it rather than
    % requiring it, so an unbuilt toolbox reports those tests as filtered
    % instead of drowning the report in failures that all have one cause.
    % =====================================================================

    methods (Test, TestTags = {'contract'})

        function iersConstants_contract_theCacheIsNotReachableByACaller(testCase)
            % PROMPT P28. The struct is now built once per session and cached.
            % The hazard a cache introduces is not staleness - the values are
            % literals of this source and MATLAB discards a persistent when its
            % own file changes - but ALIASING: if a caller could reach the
            % cached copy, one function corrupting a constant would corrupt it
            % for every later call in the session, silently and permanently.
            % MATLAB copy-on-write makes that impossible and this test says so,
            % because the property is a language semantic rather than something
            % the function does, and it is the only thing standing between the
            % cache and a whole-session defect.
            first = referenceSystem.iersConstants();
            first.secondsPerDay = 1;                    % deliberate corruption
            first.arcsecondsToRadians = 0;

            second = referenceSystem.iersConstants();

            % AbsTol 0 is exact and not a tolerance claim: no arithmetic is
            % performed between the two calls, so the second must return the
            % same doubles bit for bit or the cache has been reached.
            testCase.verifyEqual(second.secondsPerDay, 86400, 'AbsTol', 0, ...
                'The caller reached the cached constants struct.');
            testCase.verifyEqual(second.arcsecondsToRadians, pi/648000, ...
                'AbsTol', 0, 'The caller reached the cached constants struct.');
        end

        function iersConstants_contract_repeatedCallsAreBitIdentical(testCase)
            % PROMPT P28. Three calls, because section D.1 fixes the minimum at
            % three and because the first populates the cache while the second
            % and third read it - so a cache that returns something different
            % from what it stored fails here and nowhere else.
            first = referenceSystem.iersConstants();
            second = referenceSystem.iersConstants();
            third = referenceSystem.iersConstants();

            % AbsTol 0 is exact: same literals, no arithmetic, no BLAS call, so
            % obligation O13 does not apply and bit-identity is the claim.
            testCase.verifyEqual(second, first, 'AbsTol', 0);
            testCase.verifyEqual(third, first, 'AbsTol', 0);
        end

        function timeScale_contract_theRegistryIsNotReachableByACaller(testCase)
            % PROMPT P28. The timeScale cache was reverted at rev. 1.84 after
            % the profile showed it made the function slower, so there is no
            % longer state for a caller to corrupt. THE TEST STAYS ANYWAY: it
            % asserts that the list branch hands back a table the caller owns,
            % which is the property that would have to hold if anyone ever
            % caches the registry again - and rev. 1.81 shows someone will.
            listing = referenceSystem.timeScale("list");
            listing.name(1) = "CORRUPTED";
            listing.isUniform(6) = true;                % UTC is not uniform

            reread = referenceSystem.timeScale("list");
            testCase.verifyEqual(reread.name(1), "TAI", ...
                'A caller reached shared registry state through the list table.');
            testCase.verifyFalse(reread.isUniform(6), ...
                'A caller reached shared registry state through the list table.');

            info = referenceSystem.timeScale("UTC");
            testCase.verifyEqual(info.name, "UTC");
            testCase.verifyFalse(info.isUniform);
        end

        function timeScale_contract_canonicalisesAndRejects(testCase)
            info = referenceSystem.timeScale("tt");
            testCase.verifyEqual(info.name, "TT");
            testCase.verifyTrue(info.isUniform);
            testCase.verifyFalse(info.isLeapBearing);

            testCase.verifyEqual(referenceSystem.timeScale("GLONASS").name, "GLONASS");
            testCase.verifyTrue(referenceSystem.timeScale("UTC").isLeapBearing);
            testCase.verifyTrue(referenceSystem.timeScale("GLONASS").isLeapBearing);

            % Decision D10 and principle 12: the v1 aliases are gone, not
            % silently accepted, so a call site names exactly one scale.
            for alias = ["GAL", "BEIDOU", "GLONASST"]
                testCase.verifyError(@() referenceSystem.timeScale(alias), ...
                    'referenceSystem:timeScale:unknownScale', ...
                    "The v1 alias " + alias + " must not be accepted.");
            end
        end

        function timeScale_contract_listHasEverySupportedScale(testCase)
            scaleTable = referenceSystem.timeScale("list");
            testCase.verifyClass(scaleTable, 'table');
            testCase.verifyEqual(height(scaleTable), 11);
            testCase.verifyEqual(sort(scaleTable.name), sort(["TAI"; "TT"; "TDB"; ...
                "TCG"; "TCB"; "UTC"; "UT1"; "GPS"; "GST"; "BDT"; "GLONASS"]));
            testCase.verifyEqual(scaleTable.name(~scaleTable.isUniform), ...
                ["UTC"; "GLONASS"]);
        end

        function normalizeEpoch_contract_returnsCanonicalFields(testCase)
            epoch = referenceSystem.normalizeEpoch(struct('day', 60310, ...
                'sec', 90000, 'scale', 'tt'));

            testCase.verifyEqual(sort(string(fieldnames(epoch))), ...
                sort(["day"; "sec"; "scale"; "source"]));
            testCase.verifyEqual(epoch.day, 60311);
            testCase.verifyEqual(epoch.sec, 3600);
            testCase.verifyEqual(epoch.scale, "TT");
            testCase.verifyEqual(epoch.source, "unspecified");
            testCase.verifySize(epoch.day, [1 1]);
        end

        function normalizeEpoch_contract_broadcastsAndColumnises(testCase)
            epoch = referenceSystem.normalizeEpoch(struct('day', [60310 60311], ...
                'sec', 0, 'scale', "TAI", 'source', "test"));

            testCase.verifySize(epoch.day, [2 1]);
            testCase.verifySize(epoch.sec, [2 1]);
            testCase.verifyEqual(epoch.source, "test");
        end

        function normalizeEpoch_contract_rejectsDocumentedBadInput(testCase)
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', 1, 'sec', 0)), ...
                'referenceSystem:normalizeEpoch:missingField');
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', "x", 'sec', 0, 'scale', "TAI")), ...
                'referenceSystem:normalizeEpoch:badFieldType');
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', Inf, 'sec', 0, 'scale', "TAI")), ...
                'referenceSystem:normalizeEpoch:badFieldType');
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', [1 2 3], 'sec', [0 0], 'scale', "TAI")), ...
                'referenceSystem:normalizeEpoch:sizeMismatch');
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', 60310.5, 'sec', 0, 'scale', "UTC")), ...
                'referenceSystem:normalizeEpoch:nonIntegerDay');
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', 57753, 'sec', 3e5, 'scale', "UTC")), ...
                'referenceSystem:normalizeEpoch:secondsOutOfRange');
            testCase.verifyError(@() referenceSystem.normalizeEpoch( ...
                struct('day', 1, 'sec', 0, 'scale', "ATOMIC")), ...
                'referenceSystem:timeScale:unknownScale');
        end

        function normalizeEpoch_contract_foldsFractionalDayOnUniformScales(testCase)
            % A fractional day is arithmetic on a uniform scale, not a guess:
            % 60310.5 is exactly 60310 plus 43200 s.
            epoch = referenceSystem.normalizeEpoch(struct('day', 60310.5, ...
                'sec', 0, 'scale', "TT"));
            testCase.verifyEqual(epoch.day, 60310);
            testCase.verifyEqual(epoch.sec, 43200, 'AbsTol', 1e-9);
        end

        function daySecondToEpoch_contract_rejectsWrongColumnCount(testCase)
            testCase.verifyError(@() referenceSystem.daySecondToEpoch( ...
                [60310 0 0], "TAI"), ...
                'referenceSystem:daySecondToEpoch:incorrectNumberOfColumns');
            testCase.verifyError(@() referenceSystem.daySecondToEpoch( ...
                [60310; 60311], "TAI"), ...
                'referenceSystem:daySecondToEpoch:incorrectNumberOfColumns');
        end

        function epochConstructors_contract_areUnambiguousAboutShape(testCase)
            % Finding M-1: v1 guessed whether a 1x2 input was two epochs or one
            % day-plus-seconds pair. Under this design the function name fixes
            % it, and the two readings are both reachable and different.
            twoEpochs = referenceSystem.mjdToEpoch([60310 43200], "TT");
            oneEpoch = referenceSystem.daySecondToEpoch([60310 43200], "TT");

            testCase.verifyNumElements(twoEpochs.day, 2);
            testCase.verifyNumElements(oneEpoch.day, 1);
            testCase.verifyEqual(oneEpoch.sec, 43200);
        end

        function gpsWeekToEpoch_contract_rejectsNonIntegerWeek(testCase)
            testCase.verifyError(@() referenceSystem.gpsWeekToEpoch(2295.5, 0), ...
                'referenceSystem:gpsWeekToEpoch:nonIntegerWeek');
            testCase.verifyError(@() referenceSystem.gpsWeekToEpoch([1 2 3]', [0 0]'), ...
                'referenceSystem:gpsWeekToEpoch:sizeMismatch');
        end

        function datetimeToEpoch_contract_rejectsZonedNonUtc(testCase)
            zoned = datetime(2024, 1, 1, 'TimeZone', 'UTC');
            testCase.verifyError(@() referenceSystem.datetimeToEpoch(zoned, "TT"), ...
                'referenceSystem:datetimeToEpoch:zonedScaleMismatch');
            testCase.verifyEqual( ...
                referenceSystem.datetimeToEpoch(zoned, "UTC").scale, "UTC");
        end

        function epochTo_contract_rejectsDocumentedBadInput(testCase)
            epoch = referenceSystem.daySecondToEpoch([60310 0], "TT");
            testCase.verifyError(@() referenceSystem.epochTo(epoch, "julian"), ...
                'MATLAB:validators:mustBeMember');
            testCase.verifyError(@() referenceSystem.epochTo(epoch, "gpsWeek"), ...
                'referenceSystem:epochTo:wrongScale');

            leapEpoch = referenceSystem.daySecondToEpoch([57753 86400.5], "UTC");
            testCase.verifyError(@() referenceSystem.epochTo(leapEpoch, "datetime"), ...
                'referenceSystem:epochTo:unrepresentableLeapSecond');
        end

        function secondsBetween_contract_rejectsScaleMismatch(testCase)
            a = referenceSystem.daySecondToEpoch([60310 0], "TT");
            b = referenceSystem.daySecondToEpoch([60310 0], "TAI");
            testCase.verifyError(@() referenceSystem.secondsBetween(a, b), ...
                'referenceSystem:secondsBetween:scaleMismatch');
        end

        function addSeconds_contract_refusesToCrossALeapSecond(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % 2016-12-31 23:59:00 UTC plus two minutes spans the leap second.
            epoch = referenceSystem.daySecondToEpoch([57753 86340], "UTC");
            testCase.verifyError(@() referenceSystem.addSeconds(epoch, 120), ...
                'referenceSystem:addSeconds:leapSecondCrossed');
            % The same arithmetic within the day is exact and permitted.
            inside = referenceSystem.addSeconds(epoch, 30);
            testCase.verifyEqual(inside.sec, 86370);
        end

        function convertTimeScale_contract_rejectsUnknownScale(testCase)
            epoch = referenceSystem.daySecondToEpoch([60310 0], "TAI");
            testCase.verifyError(@() referenceSystem.convertTimeScale(epoch, "GAL"), ...
                'referenceSystem:timeScale:unknownScale');
            testCase.verifyError(@() referenceSystem.convertTimeScale(epoch, "UT1", ...
                'DeltaUt1', [0.1 0.2]'), ...
                'referenceSystem:convertTimeScale:sizeMismatch');
        end

        function convertTimeScale_contract_warnsWhenDeltaUt1IsDefaultedForUt1(testCase)
            % Decision D113 (rev. 1.184). Delta UT1 reaches +/-0.9 s, which is
            % 15 arcseconds of Earth rotation, and a UT1 conversion that took
            % it as zero silently was D67's forbidden shape: a consequential
            % physical choice defaulted with no sign in the result. The rule:
            % an OMISSION warns and proceeds with zero, an EXPLICIT zero is a
            % decision and passes silently, and the values are identical, so
            % the warning is the only difference between the two calls.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % This test raises the warning deliberately, so it consumes it -
            % WarningRecordingPlugin's rule, because suppression does not hide
            % a warning from lastwarn.
            cleanup = onCleanup(@() lastwarn('', ''));
            epoch = referenceSystem.daySecondToEpoch([60310 43200], "UTC");

            % verifyWarning FORWARDS the function's outputs - unlike
            % verifyError, whose rev. 1.143 lesson does not transfer: there
            % the function threw and had no outputs, here it completes and
            % they propagate. Documented under verifyWarning's own signature
            % [output1, ...] = verifyWarning(___).
            warned = testCase.verifyWarning( ...
                @() referenceSystem.convertTimeScale(epoch, "UT1"), ...
                'referenceSystem:convertTimeScale:deltaUt1Defaulted');

            silent = referenceSystem.convertTimeScale(epoch, "UT1", ...
                'DeltaUt1', 0);
            testCase.verifyEqual(warned.day, silent.day, ...
                'The warning must not change the arithmetic.');
            testCase.verifyEqual(warned.sec, silent.sec, ...
                'The warning must not change the arithmetic.');

            % UTC to TT does not touch UT1, so an omitted DeltaUt1 there is
            % not a choice at all and must stay quiet.
            testCase.verifyWarningFree( ...
                @() referenceSystem.convertTimeScale(epoch, "TT"));
        end

        function convertTimeScale_contract_identityKeepsTheEpoch(testCase)
            epoch = referenceSystem.daySecondToEpoch([60310 12345.678], "TT");
            same = referenceSystem.convertTimeScale(epoch, "TT");
            testCase.verifyEqual(same.day, epoch.day);
            testCase.verifyEqual(same.sec, epoch.sec);
            testCase.verifyTrue(startsWith(same.source, "convertTimeScale"));
        end

        function leapSecondTable_contract_commandsBehaveAsDocumented(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            stepTable = referenceSystem.leapSecondTable("list");
            testCase.verifyClass(stepTable, 'timetable');
            testCase.verifyEqual(string(stepTable.Properties.VariableNames), ...
                ["mjd", "deltaAt"]);
            testCase.verifyGreaterThan(height(stepTable), 20);
            testCase.verifyTrue(issorted(stepTable.mjd));

            testCase.verifyClass(referenceSystem.leapSecondTable("validThrough"), ...
                'datetime');
            testCase.verifyClass(referenceSystem.leapSecondTable("validFrom"), ...
                'datetime');

            % THE TWO FORMS OF EACH BOUND MUST BE THE SAME INSTANT, which is
            % the whole reason the day numbers are published: a consumer that
            % compares against epoch.day must not have to rebuild one from the
            % other and put a copy of the MJD epoch in its own file. The
            % conversion is written out HERE, once, precisely because it is
            % what the rest of the toolbox no longer does.
            mjdOrigin = datetime(1858, 11, 17, 0, 0, 0);
            for bound = ["validFrom", "validThrough"]
                asDate = referenceSystem.leapSecondTable(bound);
                asDay = referenceSystem.leapSecondTable(bound + "Day");
                testCase.verifyClass(asDay, 'double');
                testCase.verifyEqual(asDay, floor(days(asDate - mjdOrigin)), ...
                    "The two forms of " + bound + " are different instants.");
            end

            % validFrom is the first row of the ACTIVE table, so it is also the
            % day before which deltaAT refuses outright.
            testCase.verifyEqual(referenceSystem.leapSecondTable("validFromDay"), ...
                stepTable.mjd(1));
            testCase.verifyError(@() referenceSystem.leapSecondTable("deltaAT", ...
                referenceSystem.daySecondToEpoch( ...
                [referenceSystem.leapSecondTable("validFromDay") - 1, 0], "UTC")), ...
                'referenceSystem:leapSecondTable:beforeUtcEpoch');

            state = referenceSystem.leapSecondTable("state");
            testCase.verifyEqual(sort(string(fieldnames(state))), ...
                sort(["source"; "stepCount"; "lastChange"; "lastDeltaAt"; ...
                "validThrough"]));
            testCase.verifyEqual(state.source, "SOFA iauDat");

            utc = referenceSystem.daySecondToEpoch([60310 0], "UTC");
            testCase.verifyError(@() referenceSystem.leapSecondTable("deltaAT", ...
                referenceSystem.convertTimeScale(utc, "TAI")), ...
                'referenceSystem:leapSecondTable:wrongScale');
            testCase.verifyError(@() referenceSystem.leapSecondTable("deltaAT", ...
                referenceSystem.daySecondToEpoch([40000 0], "UTC")), ...
                'referenceSystem:leapSecondTable:beforeUtcEpoch');
        end

        function fundamentalArguments_contract_isTtOnly(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % Seam contract S1 item 5: a silent conversion here is how a tidal
            % model ends up driven by the wrong time scale.
            utc = referenceSystem.daySecondToEpoch([54465 0], "UTC");
            testCase.verifyError(@() referenceSystem.fundamentalArguments(utc), ...
                'referenceSystem:fundamentalArguments:wrongScale');

            tt = referenceSystem.daySecondToEpoch([54465 0], "TT");
            fa = referenceSystem.fundamentalArguments(tt);
            testCase.verifyEqual(fa.scale, "TT");
            testCase.verifyTrue(isnan(fa.tau), 'tau needs UT1 and must be NaN without it.');
        end

        function fundamentalArguments_contract_fieldCountMatchesTheCEnum(testCase)
            % The RS_FA_COLUMNS enum in mex/rsCore.h is the authority for the
            % block layout; this asserts the MATLAB field list has not drifted
            % from it, which is the realistic failure when a column is added.
            headerText = fileread(fullfile(testCase.toolboxRoot(), 'mex', 'rsCore.h'));
            enumName = regexp(headerText, 'RS_FA_[A-Z]+', 'match');
            enumName = unique(string(enumName));
            columnCount = numel(setdiff(enumName, "RS_FA_COLUMNS"));

            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            fa = referenceSystem.fundamentalArguments( ...
                referenceSystem.daySecondToEpoch([54465 0], "TT"));
            numericField = setdiff(string(fieldnames(fa)), "scale");

            testCase.verifyEqual(numel(numericField), columnCount, ...
                'The MATLAB field list and the RS_FA enum disagree in length.');
        end

    end

    methods (Test, TestTags = {'reference'})

        function leapSecondTable_reference_sofaPublishedDeltaAt(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % IAU SOFA validation program t_sofa_c.c, t_dat: the calendar dates
            % 2003-06-01, 2008-01-17 and 2017-09-01, which are MJD 52791, 54482
            % and 57997. Exact equality: TAI - UTC is an integer by definition.
            epoch = referenceSystem.daySecondToEpoch( ...
                [52791 0; 54482 0; 57997 0], "UTC");
            testCase.verifyEqual(referenceSystem.leapSecondTable("deltaAT", epoch), ...
                [32; 33; 37]);
        end

        function convertTimeScale_reference_sofaUtcToTai(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % IAU SOFA t_utctai: UTC JD 2453750.5 + 0.892100694 becomes TAI
            % JD 2453750.5 + 0.8924826384444444444, a difference of exactly 33 s.
            utc = referenceSystem.daySecondToEpoch([53750 0.892100694*86400], "UTC");
            tai = referenceSystem.convertTimeScale(utc, "TAI");

            testCase.verifyEqual(tai.day, 53750);
            testCase.verifyEqual(tai.sec, 0.8924826384444444444*86400, 'AbsTol', 1e-6);
        end

        function convertTimeScale_reference_definingOffsets(testCase)
            % IERS Conventions (2010) TN36 Table 1.1 and the GNSS interface
            % specifications. All four offsets are exact by definition.
            tai = referenceSystem.daySecondToEpoch([60310 43200], "TAI");

            testCase.verifyEqual( ...
                referenceSystem.convertTimeScale(tai, "TT").sec, ...
                43200 + 32.184, 'AbsTol', 1e-12);
            testCase.verifyEqual( ...
                referenceSystem.convertTimeScale(tai, "GPS").sec, ...
                43200 - 19, 'AbsTol', 1e-12);
            testCase.verifyEqual( ...
                referenceSystem.convertTimeScale(tai, "BDT").sec, ...
                43200 - 33, 'AbsTol', 1e-12);
            testCase.verifyEqual( ...
                referenceSystem.convertTimeScale(tai, "GST").sec, ...
                referenceSystem.convertTimeScale(tai, "GPS").sec);
        end

        function convertTimeScale_reference_tdbAgreesWithTheAlmanac(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % Finding C-1. The independent literal is the Astronomical Almanac
            % three-term approximation of TDB - TT, evaluated here from the
            % published formula. AbsTol 3e-5 s bounds the truncation of that
            % approximation itself, which is measured at below 1e-5 s over these
            % epochs. It is deliberately far tighter than the error of the
            % corrupted v1 series, which reaches 1.7e-4 s at the 2020 and 2024
            % epochs below, so this test fails if that table ever returns.
            mjd = [51544.5; 55197.0; 58849.0; 60310.0];
            tt = referenceSystem.mjdToEpoch(mjd, "TT");
            tdb = referenceSystem.convertTimeScale(tt, "TDB");
            difference = (tdb.day - tt.day)*86400 + (tdb.sec - tt.sec);

            daysFromJ2000 = mjd - 51544.5;
            g = deg2rad(357.53 + 0.9856003*daysFromJ2000);
            l = deg2rad(246.11 + 0.90251792*daysFromJ2000);
            almanac = 0.001657*sin(g) + 0.000022*sin(l);

            testCase.verifyEqual(difference, almanac, 'AbsTol', 3e-5);
            testCase.verifyLessThan(max(abs(difference)), 2e-3, ...
                'TDB - TT is a bounded periodic term of about 1.7 ms.');
        end

        function fundamentalArguments_reference_iersFundargTestCase(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % IERS Conventions (2010) software FUNDARG.F, published test case at
            % T = 0.07995893223819302 centuries, that is TT MJD 54465. This is
            % also the decision D27 agreement measurement between the SOFA
            % arguments used publicly and the ported IERS routines used inside
            % the tidal models: AbsTol 1e-12 rad, achieved better than 1e-13.
            fa = referenceSystem.fundamentalArguments( ...
                referenceSystem.daySecondToEpoch([54465 0], "TT"));

            testCase.verifyEqual(fa.l, 2.291187512612069099, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lPrime, 6.212931111003726414, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.F, 3.658025792050572989, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.D, 4.554139562402433228, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.Omega, -0.5167379217231804489 + 2*pi, ...
                'AbsTol', 1e-12);
        end

        function fundamentalArguments_reference_sofaValidationValues(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % IAU SOFA validation program t_sofa_c.c at T = 0.80 centuries,
            % which is TT MJD 80764.5, that is day 80764 and 43200 s exactly.
            fa = referenceSystem.fundamentalArguments( ...
                referenceSystem.daySecondToEpoch([80764 43200], "TT"));

            testCase.verifyEqual(fa.l, 5.132369751108684150, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lMe, 5.417338184297289661, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lVe, 3.424900460533758000, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lE, 1.744713738913081846, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lMa, 3.275506840277781492, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lJ, 5.275711665202481138, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lSa, 5.371574539440827046, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lU, 5.180636450180413523, 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.lNe, 2.079343830860413523, 'AbsTol', 1e-12);
            % Decision D52: pA is secular and is returned unwrapped, so it keeps
            % the published sign and magnitude rather than a value near 2*pi.
            testCase.verifyEqual(fa.pA, 0.1950884762240000000e-1, 'AbsTol', 1e-12);
        end

    end

    methods (Test, TestTags = {'reference'})

        function fundamentalArguments_reference_agreesWithPortedFundarg(testCase)
            % Seam contract S1 item 6 and decision D27. The toolbox keeps two
            % implementations of these arguments on purpose: SOFA iauFa*03,
            % which this function exposes publicly, and the ported IERS FUNDARG
            % held byte-intact inside the tidal routines so that their own
            % published validation still stands. The duplication is answered by
            % measuring the agreement rather than by unifying the code.
            %
            % The ported routines arrive with P7, in mex/iers/. Until they do
            % this test is filtered, not omitted: it is written now so that it
            % starts running by itself the moment they land, and the assumption
            % below states exactly what is missing.
            % The comparison itself belongs in C, where both implementations
            % live: P7 adds a standalone test that evaluates the ported FUNDARG
            % over 1960 to 2100 and writes its values to the fixture read here.
            % No gateway command exposes FUNDARG, and none should - it is an
            % internal detail of a closed, validated unit (decision D27).
            fixtureFile = fullfile(testCase.toolboxRoot(), 'test', 'fixtures', ...
                'fundargIers.csv');
            testCase.assumeTrue(isfile(fixtureFile), ...
                ['The ported IERS FUNDARG sweep has not been generated. Run ', ...
                'sh test/c/runStandaloneTests.sh once; it writes this ', ...
                'fixture as a build product. Obligation O3 closed in S2.']);
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');

            % Columns: day, sec, L, LP, F, D, OM, as written by the C test.
            %
            % Tolerance, MEASURED in S2 over the whole 1960 to 2100 sweep and
            % not the single epoch S1 checked: l, F and Omega agree bit for
            % bit, while lPrime and D differ by up to 9.8e-12 rad, that is 2.0
            % microarcseconds. The cause is two truncated digits in the
            % supplied FUNDARG.F, isolated in test/c/testIersModels.c. 2e-11 is
            % just above the measured worst case, so the figure stays pinned:
            % a corrected FUNDARG.F or a changed SOFA release fails here.
            ported = readmatrix(fixtureFile);
            epoch = referenceSystem.daySecondToEpoch(ported(:,1:2), "TT");
            fa = referenceSystem.fundamentalArguments(epoch);
            wrap = @(x) mod(x, 2*pi);

            testCase.verifyEqual(fa.l, wrap(ported(:,3)), 'AbsTol', 1e-15);
            testCase.verifyEqual(fa.F, wrap(ported(:,5)), 'AbsTol', 1e-15);
            testCase.verifyEqual(fa.Omega, wrap(ported(:,7)), 'AbsTol', 1e-15);
            testCase.verifyEqual(fa.lPrime, wrap(ported(:,4)), 'AbsTol', 2e-11);
            testCase.verifyEqual(fa.D, wrap(ported(:,6)), 'AbsTol', 2e-11);
        end

    end

    methods (Test, TestTags = {'precision'})

        function epochTo_precision_roundTripsEveryFormat(testCase)
            % Tolerances bound the resolution of each outbound representation,
            % not any physical quantity: daySecond and gpsWeek are exact, mjd
            % and j2000Seconds collapse the split form into one double, and
            % datetime resolves about a nanosecond.
            daySecond = [60310 43200.125; 60311 0.5];
            epoch = referenceSystem.daySecondToEpoch(daySecond, "TT");
            testCase.verifyEqual(referenceSystem.epochTo(epoch, "daySecond"), ...
                daySecond);

            mjd = [60310.5; 60311.25];
            testCase.verifyEqual( ...
                referenceSystem.epochTo(referenceSystem.mjdToEpoch(mjd, "TT"), "mjd"), ...
                mjd, 'AbsTol', 2*eps(60311));

            j2000 = [7.5e8; 7.5e8 + 0.125];
            testCase.verifyEqual(referenceSystem.epochTo( ...
                referenceSystem.j2000SecondsToEpoch(j2000, "TT"), "j2000Seconds"), ...
                j2000, 'AbsTol', 1e-6);

            t = datetime(2024, 1, 1, 12, 0, 0) + seconds([0; 0.125]);
            testCase.verifyEqual(referenceSystem.epochTo( ...
                referenceSystem.datetimeToEpoch(t, "TT"), "datetime"), t, ...
                'AbsTol', milliseconds(1e-3));

            week = [2295; 2296];
            secondOfWeek = [345600.5; 0];
            testCase.verifyEqual(referenceSystem.epochTo( ...
                referenceSystem.gpsWeekToEpoch(week, secondOfWeek), "gpsWeek"), ...
                [week secondOfWeek]);
        end

        function addSeconds_precision_accumulatesWithoutDrift(testCase)
            % The seconds field stays inside [0, 1] here, where one unit in the
            % last place is 2.2e-16 s, so ten thousand additions are bounded by
            % 1.1e-12 s. AbsTol 1e-9 bounds the accumulation of the split
            % representation; no physical quantity enters.
            epoch = referenceSystem.daySecondToEpoch([60310 0], "TT");
            step = 1e-4;
            for k = 1:10000
                epoch = referenceSystem.addSeconds(epoch, step);
            end

            testCase.verifyEqual(epoch.day, 60310);
            testCase.verifyEqual(epoch.sec, 1.0, 'AbsTol', 1e-9);
        end

        function secondsBetween_precision_isExactAcrossDays(testCase)
            a = referenceSystem.daySecondToEpoch([60310 0.125], "TAI");
            b = referenceSystem.daySecondToEpoch([60320 0.125], "TAI");
            testCase.verifyEqual(referenceSystem.secondsBetween(a, b), 10*86400);
            testCase.verifyEqual(referenceSystem.secondsBetween(b, a), -10*86400);
        end

        function convertTimeScale_precision_leapSecondRoundTrip(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % Finding C-3, the regression case. UTC to TAI to UTC across
            % 2016-12-31T23:59:60 must be the exact identity, with no tolerance:
            % the arithmetic is integer seconds on an unchanged day number and
            % anything less than exact means the leap second was mishandled.
            utc = referenceSystem.daySecondToEpoch( ...
                [57753 86399.5; 57753 86400.0; 57753 86400.5; 57754 0.5], "UTC");
            tai = referenceSystem.convertTimeScale(utc, "TAI");
            back = referenceSystem.convertTimeScale(tai, "UTC");

            testCase.verifyEqual(back.day, utc.day);
            testCase.verifyEqual(back.sec, utc.sec);

            % TAI runs continuously through the insertion. The four UTC epochs
            % are 0.5 s apart *by their labels*, but day 57753 is 86401 s long,
            % so the step from its 86400.5 to the next day's 0.5 spans the whole
            % inserted second and is 1.0 s of TAI, not 0.5. Asserting the true
            % spacing is what makes this a leap-second test rather than a
            % uniform-scale one; an earlier draft expected 0.5 throughout and
            % was wrong exactly where the leap second lives (rev. 1.37).
            taiLinear = tai.day*86400 + tai.sec;
            testCase.verifyEqual(diff(taiLinear), [0.5; 0.5; 1.0], 'AbsTol', 1e-9);
        end

        function convertTimeScale_precision_everyScaleRoundTrips(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % AbsTol 1e-9 s bounds the arithmetic of the hub conversion itself:
            % for TDB and TCB it also covers the one-step inversion of
            % TDB - TT, whose residual is below 1e-10 s.
            start = referenceSystem.daySecondToEpoch([60310 43200.25], "TAI");
            for scaleName = ["TT", "TDB", "TCG", "TCB", "UTC", "GPS", "GST", ...
                    "BDT", "GLONASS"]
                other = referenceSystem.convertTimeScale(start, scaleName);
                back = referenceSystem.convertTimeScale(other, "TAI");
                residual = (back.day - start.day)*86400 + (back.sec - start.sec);
                testCase.verifyEqual(residual, 0, 'AbsTol', 1e-9, ...
                    "Round trip through " + scaleName + " did not close.");
            end

            ut1 = referenceSystem.convertTimeScale(start, "UT1", 'DeltaUt1', -0.1734);
            back = referenceSystem.convertTimeScale(ut1, "TAI", 'DeltaUt1', -0.1734);
            testCase.verifyEqual((back.day - start.day)*86400 + ...
                (back.sec - start.sec), 0, 'AbsTol', 1e-9);
        end

        function convertTimeScale_precision_secularScalesGrowAsDefined(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % TCG - TT and TCB - TDB are exactly L_G and L_B times the elapsed
            % time from the 1977 origin, so the check is the definition itself
            % rather than a remembered magnitude. RelTol bounds the double
            % evaluation of that identity.
            constants = referenceSystem.iersConstants();
            tt = referenceSystem.daySecondToEpoch([58849 0], "TT");
            elapsed = (58849 - constants.mjdTt1977)*86400;

            tcg = referenceSystem.convertTimeScale(tt, "TCG");
            testCase.verifyEqual((tcg.day - tt.day)*86400 + (tcg.sec - tt.sec), ...
                constants.lg/(1 - constants.lg)*elapsed, 'RelTol', 1e-9);

            tdb = referenceSystem.convertTimeScale(tt, "TDB");
            tcb = referenceSystem.convertTimeScale(tt, "TCB");
            testCase.verifyEqual((tcb.day - tdb.day)*86400 + (tcb.sec - tdb.sec), ...
                constants.lb/(1 - constants.lb)*elapsed - ...
                constants.tdb0/(1 - constants.lb), 'RelTol', 1e-6);
        end

        function fundamentalArguments_precision_doodsonDerivations(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % The IERS Conventions Ch. 6 relations, recomputed here from the
            % Delaunay set. AbsTol 1e-12 rad bounds the wrap arithmetic only.
            tt = referenceSystem.daySecondToEpoch([54465 43200], "TT");
            ut1 = referenceSystem.daySecondToEpoch([54465 43200 - 65.0], "UT1");
            fa = referenceSystem.fundamentalArguments(tt, 'Ut1Epoch', ut1);

            wrap = @(x) mod(x, 2*pi);
            testCase.verifyEqual(fa.s, wrap(fa.F + fa.Omega), 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.h, wrap(fa.s - fa.D), 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.p, wrap(fa.s - fa.l), 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.nPrime, wrap(-fa.Omega), 'AbsTol', 1e-12);
            testCase.verifyEqual(fa.pStar, wrap(fa.s - fa.D - fa.lPrime), ...
                'AbsTol', 1e-12);
            testCase.verifyFalse(isnan(fa.tau), 'tau must be filled when UT1 is given.');
        end

        function fundamentalArguments_precision_wrapAndRange(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % Continuity across the 2*pi wrap: the arguments are sampled densely
            % enough that consecutive values differ by much less than pi, so any
            % jump larger than that is a wrap and must be exactly 2*pi.
            tt = referenceSystem.daySecondToEpoch( ...
                [(54465:54495)' zeros(31,1)], "TT");
            fa = referenceSystem.fundamentalArguments(tt);

            cyclicField = ["l", "lPrime", "F", "D", "Omega", "lMe", "lVe", ...
                "lE", "lMa", "lJ", "lSa", "lU", "lNe", "s", "h", "p", ...
                "nPrime", "pStar"];
            for name = cyclicField
                value = fa.(name);
                testCase.verifyTrue(all(value >= 0 & value < 2*pi), ...
                    name + " is not wrapped to [0, 2*pi).");
                step = diff(value);
                step(step < -pi) = step(step < -pi) + 2*pi;
                step(step > pi) = step(step > pi) - 2*pi;
                testCase.verifyLessThan(max(abs(diff(step))), 1e-3, ...
                    name + " is not continuous across the wrap.");
            end

            % Decision D52: pA is not wrapped, and is negative before J2000.0.
            early = referenceSystem.fundamentalArguments( ...
                referenceSystem.daySecondToEpoch([40000 0], "TT"));
            testCase.verifyLessThan(early.pA, 0, ...
                'pA must stay secular and negative before J2000.0.');
        end

    end

    methods (Test, TestTags = {'vectorization'})

        function convertTimeScale_vectorization_matchesScalarLoop(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            daySecond = [57753 86400.5; 57754 0; 58849 43200; 60310 1.25];
            utc = referenceSystem.daySecondToEpoch(daySecond, "UTC");
            batch = referenceSystem.convertTimeScale(utc, "TT");

            for k = 1:size(daySecond, 1)
                single = referenceSystem.convertTimeScale( ...
                    referenceSystem.daySecondToEpoch(daySecond(k,:), "UTC"), "TT");
                testCase.verifyEqual(batch.day(k), single.day);
                testCase.verifyEqual(batch.sec(k), single.sec);
            end
        end

        function fundamentalArguments_vectorization_matchesScalarLoop(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            daySecond = [54465 0; 58849 43200; 60310 12345.5];
            batch = referenceSystem.fundamentalArguments( ...
                referenceSystem.daySecondToEpoch(daySecond, "TT"));

            for k = 1:size(daySecond, 1)
                single = referenceSystem.fundamentalArguments( ...
                    referenceSystem.daySecondToEpoch(daySecond(k,:), "TT"));
                testCase.verifyEqual(batch.l(k), single.l);
                testCase.verifyEqual(batch.Omega(k), single.Omega);
                testCase.verifyEqual(batch.pA(k), single.pA);
            end
        end

    end

    methods (Test, TestTags = {'diagnostics'})

        function leapSecondTable_diagnostics_oneWarningRegardlessOfN(testCase)
            % THIS TEST ASSERTS A WARNING, SO IT CONSUMES IT. The report lists
            % warnings nobody claimed, and an asserted warning is claimed.
            % Registered as a cleanup so it fires on pass, on failure and on a
            % filtered assumption alike. See WarningRecordingPlugin.
            consumeWarning = onCleanup(@() lastwarn('', ''));
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % Section C.6 rule 2. The bundled SOFA release flags every year more
            % than five beyond its own, so epochs past the coverage end raise the
            % dubious-year warning - once per call, not once per epoch.
            epochCount = 10000;
            beyond = referenceSystem.leapSecondTable("validThroughDay") ...
                + (1:epochCount)';
            epoch = referenceSystem.daySecondToEpoch( ...
                [beyond zeros(epochCount,1)], "UTC");

            testCase.verifyWarning(@() referenceSystem.leapSecondTable("deltaAT", epoch), ...
                'referenceSystem:leapSecondTable:dubiousYear');

            % Aggregation is the property under test, not the mere presence of a
            % warning: the single message must account for all N epochs, which is
            % what section C.6 rule 2 asks for and what a per-epoch warning could
            % not do.
            lastwarn('');
            previousState = warning('off', 'referenceSystem:leapSecondTable:dubiousYear');
            restoreWarning = onCleanup(@() warning(previousState));
            [~] = referenceSystem.leapSecondTable("deltaAT", epoch);
            [message, identifier] = lastwarn();

            testCase.verifyEqual(identifier, 'referenceSystem:leapSecondTable:dubiousYear');
            testCase.verifyTrue(contains(message, string(epochCount)), ...
                'The aggregated warning does not state how many epochs were affected.');
        end

        function convertTimeScale_diagnostics_returnsNoStatus(testCase)
            % Decision D3: no public function in this toolbox returns a numeric
            % status. A second output must not exist at all.
            epoch = referenceSystem.daySecondToEpoch([60310 0], "TAI");
            testCase.verifyError( ...
                @() localTwoOutputs(@referenceSystem.convertTimeScale, epoch, "TT"), ...
                'MATLAB:TooManyOutputs');
        end

        function leapSecondTable_diagnostics_overrideReachesEveryConsumer(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % Seam contract S1 item 2: leapSecondTable is the single authority, so a
            % table installed through the documented override must be observed by
            % convertTimeScale and by normalizeEpoch as well, not only by
            % leapSecondTable itself.
            restore = onCleanup(@() referenceSystem.leapSecondTable("reset"));

            overrideFile = fullfile(tempdir, "referenceSystem_leapOverride.txt");
            removeFile = onCleanup(@() delete(overrideFile));
            % One fictitious step: TAI - UTC becomes 99 s at MJD 58000, and a
            % positive second is inserted at the end of MJD 57999.
            writematrix([41317 10; 58000 99], overrideFile, ...
                'FileType', 'text', 'Delimiter', ' ');

            referenceSystem.leapSecondTable("load", overrideFile);
            testCase.verifyTrue(startsWith( ...
                referenceSystem.leapSecondTable("state").source, "override"));

            utc = referenceSystem.daySecondToEpoch([58849 0], "UTC");
            testCase.verifyEqual(referenceSystem.leapSecondTable("deltaAT", utc), 99);

            tai = referenceSystem.convertTimeScale(utc, "TAI");
            testCase.verifyEqual(tai.sec, 99, 'AbsTol', 1e-9, ...
                'convertTimeScale did not observe the leap-second override.');

            % normalizeEpoch reads the same table: the day before the fictitious
            % step is 86400 + 89 s long, so a seconds-of-day just past 86400 on
            % it is accepted rather than carried into the next day.
            normalised = referenceSystem.normalizeEpoch(struct('day', 57999, ...
                'sec', 86400.5, 'scale', "UTC"));
            testCase.verifyEqual(normalised.day, 57999, ...
                'normalizeEpoch did not observe the leap-second override.');
        end

    end

    methods (Test, TestTags = {'contract'})

        function leapSecondTable_contract_derivedColumnsFollowTheActiveTable(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % PROMPT P28b, rev. 1.122. deltaAT no longer reads the timetable;
            % it reads columns derived when the active table was installed. The
            % hazard a derived cache introduces is staleness on the ONE event
            % that changes the table, and there are exactly two such events.
            % This test makes both happen and requires the answer to move both
            % times.
            %
            % The existing diagnostics test asserts that an override reaches
            % convertTimeScale and normalizeEpoch. It would also fail on a
            % stale cache, and that is deliberate redundancy: this test names
            % the mechanism, that one names the consequence, and a reader who
            % sees only one of them still learns something true.
            restore = onCleanup(@() referenceSystem.leapSecondTable("reset"));

            utc = referenceSystem.daySecondToEpoch([58849 0], "UTC");
            sofaValue = referenceSystem.leapSecondTable("deltaAT", utc);
            testCase.assertEqual(sofaValue, 37, ...
                'The SOFA table should give TAI - UTC = 37 s in 2020.');

            overrideFile = fullfile(tempdir, ...
                "referenceSystem_p28bColumnCache.txt");
            removeFile = onCleanup(@() delete(overrideFile));
            writematrix([41317 10; 58000 99], overrideFile, ...
                'FileType', 'text', 'Delimiter', ' ');

            referenceSystem.leapSecondTable("load", overrideFile);
            testCase.verifyEqual(referenceSystem.leapSecondTable("deltaAT", utc), 99, ...
                'The derived columns did not follow the loaded override.');

            referenceSystem.leapSecondTable("reset");
            testCase.verifyEqual(referenceSystem.leapSecondTable("deltaAT", utc), ...
                sofaValue, 'The derived columns did not follow the reset.');
        end

        function leapSecondTable_contract_aListsExpirySetsTheCoverage(testCase)
            % F12 of the review. dubiousYear told the caller to load a newer
            % table, and loading one never moved the coverage it is judged
            % against. A leap-seconds.list states its own expiry on the "#@"
            % line; loading it must move validThrough to the day before that
            % expiry and silence the warning for epochs it covers, and "reset"
            % must bring the SOFA coverage and the warning back. A two-column
            % table states no expiry and keeps the SOFA coverage.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            restore = onCleanup(@() referenceSystem.leapSecondTable("reset"));
            consumeWarning = onCleanup(@() lastwarn('', ''));
            sofaDay = referenceSystem.leapSecondTable("validThroughDay");
            beyond = referenceSystem.daySecondToEpoch([sofaDay + 400, 0], "UTC");
            testCase.verifyWarning(@() referenceSystem.leapSecondTable( ...
                "deltaAT", beyond), 'referenceSystem:leapSecondTable:dubiousYear');

            % NTP stamps: seconds from 1900-01-01, MJD 15020. The expiry is
            % 2000 days past the SOFA coverage.
            expiryDay = sofaDay + 2000;
            listFile = fullfile(tempdir, "referenceSystem_leapSecondsList.txt");
            removeFile = onCleanup(@() delete(listFile));
            fileId = fopen(listFile, 'w');
            fprintf(fileId, '#$ 3913697179\n#@ %d\n', (expiryDay - 15020) * 86400);
            fprintf(fileId, '%d 10 # 1 Jan 1972\n', (41317 - 15020) * 86400);
            fprintf(fileId, '%d 37 # 1 Jan 2017\n', (57754 - 15020) * 86400);
            fclose(fileId);

            referenceSystem.leapSecondTable("load", listFile);
            testCase.verifyEqual(referenceSystem.leapSecondTable("validThroughDay"), ...
                expiryDay - 1, 'The list''s expiry did not set the coverage.');
            testCase.verifyEqual(referenceSystem.leapSecondTable("state").validThrough, ...
                referenceSystem.leapSecondTable("validThrough"));
            lastwarn('', '');
            testCase.verifyEqual(referenceSystem.leapSecondTable("deltaAT", beyond), 37);
            [~, raised] = lastwarn;
            testCase.verifyNotEqual(string(raised), ...
                "referenceSystem:leapSecondTable:dubiousYear", ...
                'An epoch inside the loaded coverage still warned.');

            tableFile = fullfile(tempdir, "referenceSystem_leapTwoColumn.txt");
            removeTable = onCleanup(@() delete(tableFile));
            writematrix([41317 10; 57754 37], tableFile, 'FileType', 'text', ...
                'Delimiter', ' ');
            referenceSystem.leapSecondTable("load", tableFile);
            testCase.verifyEqual(referenceSystem.leapSecondTable("validThroughDay"), ...
                sofaDay, 'A table with no expiry must keep the SOFA coverage.');

            referenceSystem.leapSecondTable("reset");
            testCase.verifyEqual(referenceSystem.leapSecondTable("validThroughDay"), sofaDay);
            testCase.verifyWarning(@() referenceSystem.leapSecondTable( ...
                "deltaAT", beyond), 'referenceSystem:leapSecondTable:dubiousYear');
        end

        function convertTimeScale_contract_everyScaleLabelIsTheCanonicalName(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % PROMPT P28b-2, decision D88. localShift no longer routes its
            % output through normalizeEpoch, so the scale label it writes is the
            % LITERAL from the switch rather than a name the registry returned.
            % That is 2.84 us saved per call and one new way to be wrong: a typo
            % in one of those literals would propagate into epochOut.scale and
            % be caught by nothing downstream.
            %
            % THE ASSUMPTION IS THEREFORE CONVERTED INTO A TEST rather than
            % argued for in a comment. Every scale the registry knows is
            % reached, both directions, and the label is compared against the
            % registry's own canonical spelling.
            scaleName = referenceSystem.timeScale("list").name;
            % 2020-06-15, far from any leap second, so GLONASS is representable
            % and no branch is taken for a reason other than the scale.
            utc = referenceSystem.daySecondToEpoch([59015 43200], "UTC");

            for k = 1:numel(scaleName)
                target = scaleName(k);
                % 'DeltaUt1', 0 is EXPLICIT since D113 (rev. 1.185): the loop
                % is data-driven and reaches UT1, where an omitted value now
                % warns. This test checks LABELS, not physics - the value of
                % UT1 - UTC cannot change what epochOut.scale says - so zero
                % is the right deliberate choice, and for every other scale
                % the option is validated and unused. Run 78 flagged this
                % method as the suite's one warned test; a literal grep had
                % swept the blast radius and cannot see a loop over
                % timeScale("list") (obligation O34).
                forward = referenceSystem.convertTimeScale(utc, target, ...
                    'DeltaUt1', 0);
                testCase.verifyEqual(forward.scale, target, ...
                    "convertTimeScale to " + target + " labelled its output " + ...
                    forward.scale + ".");

                back = referenceSystem.convertTimeScale(forward, "UTC", ...
                    'DeltaUt1', 0);
                testCase.verifyEqual(back.scale, "UTC", ...
                    "The return trip from " + target + " lost the UTC label.");
                testCase.verifyEqual(back.day, utc.day, ...
                    "The return trip from " + target + " changed the day.");
                testCase.verifyEqual(back.sec, utc.sec, 'AbsTol', 1e-9, ...
                    "The return trip from " + target + " changed the second.");
            end
        end

        function normalizeEpoch_contract_theCarryIsSharedNotCopied(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % D88 puts the carry in one place and lets two callers reach it, one
            % validating and one not. The property that matters is that they
            % cannot diverge: for an epoch already canonical apart from its
            % seconds, the validating path and the internal path must produce
            % the SAME numbers, and a leap-second day is where a second copy of
            % the carry would first disagree.
            %
            % convertTimeScale is the internal path, exercised through the
            % identity UTC -> TAI -> UTC across the 2016 leap second; the
            % validating path is normalizeEpoch called directly. Bit-identity is
            % asserted rather than a tolerance, because both routes perform the
            % same additions of 86400 and of integer days.
            leapDay = 57753;   % 2016-12-31, the day carrying the leap second
            secondsPerDay = referenceSystem.iersConstants().secondsPerDay;

            for offset = [-0.5, 0.0, 0.5, 1.0, 1.5]
                raw = struct('day', leapDay, 'sec', secondsPerDay + offset, ...
                    'scale', "UTC", 'source', "test");
                viaNormalize = referenceSystem.normalizeEpoch(raw);

                tai = referenceSystem.convertTimeScale(viaNormalize, "TAI");
                viaConvert = referenceSystem.convertTimeScale(tai, "UTC");

                testCase.verifyEqual(viaConvert.day, viaNormalize.day, ...
                    sprintf('Day disagreed at offset %+.1f s.', offset));
                testCase.verifyEqual(viaConvert.sec, viaNormalize.sec, ...
                    'AbsTol', 0, ...
                    sprintf('Second disagreed at offset %+.1f s.', offset));
            end

            % The out-of-range guard still belongs to normalizeEpoch BY
            % IDENTIFIER although the check now lives in the shared carry: it is
            % what the help of both callers documents and what a caller catches,
            % and moving code must not move that.
            testCase.verifyError(@() referenceSystem.normalizeEpoch(struct( ...
                'day', leapDay, 'sec', 3*secondsPerDay, 'scale', "UTC")), ...
                'referenceSystem:normalizeEpoch:secondsOutOfRange');
        end

        function leapSecondTable_contract_derivedColumnsAreNotReachableByACaller(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % The aliasing hazard, asserted the way prompt P28 asserted it for
            % iersConstants and timeScale. MATLAB copy-on-write means a caller
            % cannot reach the persistent through the timetable "list" hands
            % back - but that is a language semantic rather than something this
            % function does, which is exactly why it needs a test. It is the
            % only thing between a cache and a whole-session defect.
            utc = referenceSystem.daySecondToEpoch([58849 0], "UTC");
            before = referenceSystem.leapSecondTable("deltaAT", utc);

            stepTable = referenceSystem.leapSecondTable("list");
            stepTable.deltaAt(:) = -12345;
            stepTable.mjd(:) = 0;

            testCase.verifyEqual(referenceSystem.leapSecondTable("deltaAT", utc), ...
                before, ...
                'Corrupting the returned table changed what deltaAT answers.');
            freshTable = referenceSystem.leapSecondTable("list");
            testCase.verifyNotEqual(freshTable.deltaAt(end), -12345, ...
                'Corrupting the returned table reached the table itself.');
            testCase.verifyTrue(all(freshTable.mjd > 0), ...
                'Corrupting the returned step days reached the table itself.');
        end

    end

    methods (Test, TestTags = {'speed'})

        function fundamentalArguments_speed_singleEpochAndArc(testCase)
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built.');
            % P24 sets the target on the arithmetic: below 2 us per epoch,
            % which is a batch property and is asserted on the arc below. A
            % single MATLAB call cannot meet it, and it was never meant to:
            % measured on R2026a the one-epoch call is about 1.4 ms, of which
            % the arithmetic is far under 1 us and the rest is the fixed cost
            % of one MATLAB-to-MEX round trip plus the arguments block, the
            % normalizeEpoch entry and the struct assembly. Handover section
            % B.9 states this cost explicitly and states the fix for a hot loop
            % is the C API of P19, not a faster single call. The N=1 row is
            % therefore benchmarked against a call-overhead target of 3 ms so
            % that it reports OK when the overhead is normal and FAIL only when
            % something has made a single call pathologically slow; the useful
            % per-epoch figure is the arc row.
            single = referenceSystem.daySecondToEpoch([58849 0], "TT");
            arc = referenceSystem.daySecondToEpoch( ...
                [58849*ones(86400,1) (0:86399)'], "TT");

            singleMedian = TestPerformance.medianDuration( ...
                @() referenceSystem.fundamentalArguments(single), 5);
            arcMedian = TestPerformance.medianDuration( ...
                @() referenceSystem.fundamentalArguments(arc), 3);

            testCase.log(1, TestPerformance.benchmarkRecord( ...
                "fundamentalArguments(N=1,call)", 1, singleMedian, 3e-3));
            testCase.log(1, TestPerformance.benchmarkRecord( ...
                "fundamentalArguments(N=86400)", 86400, arcMedian, 0.2));

            % The contract is the per-epoch arithmetic target, not the single
            % call: 2 us times 86400 epochs is 0.173 s, and the arc must beat
            % five times that. It measured 0.027 s, a factor of six inside even
            % the one-times target.
            testCase.verifyLessThan(arcMedian, 5*2e-6*86400, ...
                'The per-epoch arithmetic is slower than five times its target.');
        end

    end

    methods (Access = private)

        function folder = packageFolder(testCase)
            %PACKAGEFOLDER Absolute path of +referenceSystem, found from this file.
            folder = fullfile(testCase.toolboxRoot(), '+referenceSystem');
        end

        function root = toolboxRoot(~)
            %TOOLBOXROOT Absolute path of the distribution folder.
            root = fileparts(fileparts(mfilename('fullpath')));
        end

    end


    methods (Test, TestTags = {'contract'})

        function j2000SecondsToEpoch_contract_shapeAndUnknownScale(testCase)
            epoch = referenceSystem.j2000SecondsToEpoch([0; 86400; -86400], "TT");

            testCase.verifySize(epoch.day, [3 1], 'One day number per input.');
            testCase.verifySize(epoch.sec, [3 1], 'One second-of-day per input.');
            testCase.verifyEqual(epoch.scale, "TT", 'The scale is carried through.');
            testCase.verifyError(@() referenceSystem.j2000SecondsToEpoch(0, "ZULU"), ...
                'referenceSystem:timeScale:unknownScale');
            % A leap-bearing scale is refused by name: counted from J2000.0 it
            % fails in normalizeEpoch for any date more than a day away, with an
            % error that names neither this function nor the cause.
            for scale = ["UTC", "GLONASS"]
                testCase.verifyError(@() referenceSystem.j2000SecondsToEpoch( ...
                    7.5e8, scale), ...
                    'referenceSystem:j2000SecondsToEpoch:leapBearingScale', ...
                    scale + " was not refused by name.");
            end
        end

    end

    methods (Test, TestTags = {'reference'})

        function j2000SecondsToEpoch_reference_zeroIsTheJ2000Epoch(testCase)
            % J2000.0 is 2000 January 1, 12h TT = JD 2451545.0 = MJD 51544.5,
            % which is the defining epoch of the IAU 2006/2000A models and of
            % every polynomial in this toolbox. Zero seconds from it must land
            % on day 51544 at 43200 s, and the assertion is EXACT because both
            % numbers are integers in binary.
            epoch = referenceSystem.j2000SecondsToEpoch(0, "TT");

            testCase.verifyEqual(epoch.day, 51544, 'AbsTol', 0, ...
                'The J2000.0 day number is not MJD 51544.');
            testCase.verifyEqual(epoch.sec, 43200, 'AbsTol', 0, ...
                'The J2000.0 second of day is not noon.');
        end

        function datetimeToEpoch_reference_matchesTheJ2000Definition(testCase)
            % The same published instant reached through the calendar rather
            % than through a count of seconds. Two constructors agreeing on one
            % published epoch is what makes either of them trustworthy; agreeing
            % with each other would not be (finding M-1).
            epoch = referenceSystem.datetimeToEpoch( ...
                datetime(2000, 1, 1, 12, 0, 0), "TT");

            testCase.verifyEqual(epoch.day, 51544, 'AbsTol', 0, ...
                'The calendar route gives a different J2000.0 day number.');
            % 1e-9 s bounds the conversion of a calendar time to a
            % second-of-day through datetime's own millisecond representation.
            % It is not a clock accuracy: the input is an exact instant.
            testCase.verifyEqual(epoch.sec, 43200, 'AbsTol', 1e-9, ...
                'The calendar route gives a different second of day.');
        end

        function gpsWeekToEpoch_reference_weekZeroIsThePublishedGpsEpoch(testCase)
            % GPS time began at 1980 January 6, 0h UTC, which is MJD 44244, and
            % has run without leap seconds since (IS-GPS-200). Week 0 second 0
            % must be exactly that day at zero seconds.
            epoch = referenceSystem.gpsWeekToEpoch(0, 0);

            testCase.verifyEqual(epoch.day, 44244, 'AbsTol', 0, ...
                'GPS week zero is not MJD 44244.');
            testCase.verifyEqual(epoch.sec, 0, 'AbsTol', 0, ...
                'GPS week zero does not begin at 0h.');
            testCase.verifyEqual(epoch.scale, "GPS", ...
                'The GPS constructor did not tag the scale.');
        end

        function epochTo_reference_returnsThePublishedJ2000Values(testCase)
            % The outbound direction, against the same published epoch. Decision
            % D32 collapsed five epochToX functions into one epochTo(epoch,
            % format); this asserts that each format returns the published value
            % rather than only that the five agree with one another.
            epoch = referenceSystem.j2000SecondsToEpoch(0, "TT");

            % An MJD of 51544.5 is exact in binary, and so is zero.
            testCase.verifyEqual(referenceSystem.epochTo(epoch, "mjd"), 51544.5, ...
                'AbsTol', 0, 'epochTo mjd does not return the J2000.0 MJD.');
            testCase.verifyEqual(referenceSystem.epochTo(epoch, "j2000Seconds"), 0, ...
                'AbsTol', 0, 'epochTo j2000Seconds does not return zero at J2000.0.');
            testCase.verifyEqual(referenceSystem.epochTo(epoch, "daySecond"), ...
                [51544 43200], 'AbsTol', 0, ...
                'epochTo daySecond does not return the two-part form.');
        end

        function secondsBetween_reference_countsThePublishedCalendarSpan(testCase)
            % 2000 was a leap year - divisible by 400 - so 2000-01-01 to
            % 2001-01-01 is 366 days. TAI is used rather than UTC deliberately:
            % TAI has no leap seconds, so the span is a pure calendar fact and
            % the test is about the arithmetic rather than about the leap-second
            % table, which has its own tests.
            first = referenceSystem.datetimeToEpoch(datetime(2000, 1, 1), "TAI");
            second = referenceSystem.datetimeToEpoch(datetime(2001, 1, 1), "TAI");

            elapsed = referenceSystem.secondsBetween(first, second);

            % 1e-9 s bounds the two calendar conversions; the difference itself
            % is exact in the two-part form, which is the point of decision D9.
            testCase.verifyEqual(elapsed, 366 * 86400, 'AbsTol', 1e-9, ...
                'The year 2000 did not come out as 366 days.');
        end

    end

    methods (Test, TestTags = {'precision'})

        function normalizeEpoch_precision_carriesTheDayWithoutLosingResolution(testCase)
            % THE WHOLE POINT OF THE TWO-PART EPOCH (decision D9) IS THAT THE
            % SECONDS FIELD KEEPS ITS RESOLUTION WHATEVER THE DAY NUMBER IS. A
            % decimal MJD holds about 5 us at MJD 60000; the split form holds
            % the nanosecond below, and normalizeEpoch is the function that must
            % not throw that away while it carries the overflow into the day.
            raw = struct('day', 51544, 'sec', 86400 + 1e-9, 'scale', "TAI", ...
                'source', "test");

            epoch = referenceSystem.normalizeEpoch(raw);

            testCase.verifyEqual(epoch.day, 51545, 'AbsTol', 0, ...
                'The overflowing second was not carried into the day.');
            % 2e-11 s, AND THE PREMISE OF THE FIRST DRAFT WAS WRONG. It
            % asserted AbsTol 0, on the reasoning that 1e-9 is exact relative
            % to zero. It is - but the INPUT is not: 86400 + 1e-9 rounds to the
            % nearest multiple of eps(86400) = 1.46e-11, so the nanosecond is
            % already quantised before normalizeEpoch is called and cannot be
            % recovered by it. The bound is therefore one eps of the seconds
            % field the caller wrote, which is what the split form protects
            % ONCE SPLIT and cannot protect beforehand.
            testCase.verifyEqual(epoch.sec, 1e-9, 'AbsTol', 2e-11, ...
                'A nanosecond was lost while normalising a day-sized epoch.');
        end

        function normalizeEpoch_precision_isIdempotent(testCase)
            % A canonical form that is not a fixed point of its own normaliser
            % is not canonical. Asserted bit for bit: normalising an already
            % normal epoch must move nothing at all.
            once = referenceSystem.normalizeEpoch(struct('day', 60000, ...
                'sec', 43200.25, 'scale', "TT", 'source', "test"));

            twice = referenceSystem.normalizeEpoch(once);

            testCase.verifyEqual(twice.day, once.day, 'AbsTol', 0, ...
                'Normalising twice moved the day number.');
            testCase.verifyEqual(twice.sec, once.sec, 'AbsTol', 0, ...
                'Normalising twice moved the second of day.');
        end

    end

    methods (Test, TestTags = {'speed'})

        function registryLookups_speed_tenThousandCalls(testCase)
            % PROMPT P28, AND THE ONLY ROW IN THE REPORT THAT CAN SEE THE CACHE
            % REGRESS. Neither of these functions computes anything a user
            % waits for; they are called by everything else, and the run-14
            % profile of a single-epoch rotationItrsToGcrs call recorded 24
            % calls to iersConstants and 20 to timeScale. Their cost is
            % therefore paid per call of the toolbox, not per call of
            % themselves, and a change that quietly restored the per-call
            % rebuild would show up here and in the N=1 rotation row and
            % nowhere else in 439 tests.
            %
            % The targets are PREDICTIONS in the sense risk R17 warns about -
            % neither function has ever been benchmarked - and they are set on
            % one host, so rev. 1.76's rule (twice the slowest host measured)
            % cannot be applied yet. Re-argue them against the first two
            % platforms rather than adopting them.
            callCount = 10000;
            constantsTarget = 0.10;
            scaleTarget = 0.20;

            constantsSeconds = TestPerformance.medianDuration(@() ...
                localRepeat(@referenceSystem.iersConstants, callCount), 3);
            scaleSeconds = TestPerformance.medianDuration(@() ...
                localRepeat(@referenceSystem.timeScale, callCount, "TT"), 3);

            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("iersConstants (cached, 6.1x)", ...
                callCount, constantsSeconds, constantsTarget));
            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("timeScale", ...
                callCount, scaleSeconds, scaleTarget));

            if constantsSeconds > constantsTarget
                warning('referenceSystem:test:slowerThanTarget', ...
                    'iersConstants took %.3f s against a %.3f s target.', ...
                    constantsSeconds, constantsTarget);
            end
            if scaleSeconds > scaleTarget
                warning('referenceSystem:test:slowerThanTarget', ...
                    'timeScale took %.3f s against a %.3f s target.', ...
                    scaleSeconds, scaleTarget);
            end
            testCase.verifyLessThan(constantsSeconds, 5 * constantsTarget);
            testCase.verifyLessThan(scaleSeconds, 5 * scaleTarget);
        end

        function convertTimeScale_speed_oneMillionEpochs(testCase)
            % Section B.7 publishes a 0.2 s target for a million UTC to TT
            % conversions and the suite has never measured it. It is the
            % conversion a reprocessing campaign does most often - every data
            % record carries a UTC tag and every model wants TT - so it is worth
            % a row in the report even though nothing about it is subtle.
            targetSeconds = 0.2;
            day = 60000 + floor(linspace(0, 999, 1000000)');
            second = mod(linspace(0, 86399, 1000000)', 86400);
            utc = referenceSystem.daySecondToEpoch([day, second], "UTC");

            medianSeconds = TestPerformance.medianDuration(@() ...
                referenceSystem.convertTimeScale(utc, "TT"), 3);

            testCase.log(matlab.unittest.Verbosity.Concise, ...
                TestPerformance.benchmarkRecord("convertTimeScale(UTC>TT)", 1000000, ...
                medianSeconds, targetSeconds));
            if medianSeconds > targetSeconds
                warning('referenceSystem:test:slowerThanTarget', ...
                    'convertTimeScale took %.3f s against a %.3f s target.', ...
                    medianSeconds, targetSeconds);
            end
            testCase.verifyLessThan(medianSeconds, 5 * targetSeconds);
        end

    end

end

% =========================== local functions ===========================

function localRepeat(operation, callCount, varargin)
%LOCALREPEAT Call operation callCount times with fixed arguments, discarding
%   the result.
%   One call to iersConstants is far below the resolution of tic/toc, and it is
%   the PER-CALL cost that prompt P28 changed, so the loop is the measurement
%   and not an amplifier of it.
%
%   THE ARGUMENTS ARE PASSED THROUGH RATHER THAN CLOSED OVER (rev. 1.82). In
%   rev. 1.81 this helper took no arguments, so iersConstants was timed through
%   a plain function handle while timeScale was timed through the anonymous
%   wrapper @() timeScale("TT"). An anonymous call costs something, only one of
%   the two rows paid it, and run 15 then reported 0.43 us against 7.25 us as
%   though the difference were entirely in the functions. It was not entirely
%   in the functions. Both rows now enter through the same construction.
for k = 1:callCount
    operation(varargin{:});
end
end

function [first, second] = localTwoOutputs(operation, varargin)
%LOCALTWOOUTPUTS Request two outputs from a function, so that a function which
%   returns only one raises MATLAB:TooManyOutputs. Used by the decision D3
%   diagnostics test, which asserts that no public function returns a status.
    [first, second] = operation(varargin{:});
end
