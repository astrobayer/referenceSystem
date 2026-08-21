classdef TestEphemeris < matlab.unittest.TestCase
%TESTEPHEMERIS Solar-system ephemeris provider and the topocentric TDB term.
%
%   Covers the S10 deliverables ephemerisBodies, barycentricBodyState,
%   geocentricBodyState, readEphemeris and the Observer name-value pair of
%   convertTimeScale.
%
%   TWO OF THESE TESTS EXIST BECAUSE THE OBVIOUS TEST WOULD PASS ON A DEFECT.
%   The registry in ephemerisBodies mirrors an enum in mex/rsCore.h and nothing
%   in MATLAB can see that enum, so comparing the registry against a second copy
%   of the same list would agree with itself while the mapping was permuted.
%   Instead every body is fetched and required to sit in the heliocentric
%   distance band it alone occupies - which a permutation cannot survive. The
%   topocentric TDB term is checked the same way: against (v_E . r)/c2 assembled
%   from a different function, not against a second evaluation of iauDtdb.
%
%   The class lives outside +referenceSystem and calls referenceSystem.*
%   explicitly, as required by handover section C.5 rule 4.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 11:45 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    properties (Constant)
        % THE ONE PLACE THIS PROJECT DECLARES WHICH EPHEMERIS GENERATIONS IT
        % TREATS AS INTERCHANGEABLE, AND SINCE REV. 1.178 IT IS READ RATHER
        % THAN ASSERTED. Park et al. (2021), AJ 161:105, the DE440/DE441
        % release paper, states that the two were fit to the SAME DATA SET and
        % differ in one modelling choice: DE441 assumes no damping between the
        % lunar liquid core and mantle, which is what lets it be integrated
        % backwards for millennia without diverging. The consequences are
        % quantified there and are what this constant rests on:
        %
        %   planets   below 1 m over the 1100 years DE440 spans
        %   Moon      below 2 m across the LLR data span, 1970-2020, and
        %             growing outside it, mostly along-track
        %
        % Against the metre-level accuracy the MICE tier claims for itself,
        % those are at or below the floor, so for GRACE-era work the two are
        % interchangeable. The paper's own guidance is DE440 for modern data
        % and DE441 for historic epochs before DE440's span.
        %
        % RE-VERIFIED AT REV. 1.188 AGAINST THE PAPER ITSELF, not against the
        % rev. 1.178 reading of it: same data set and the lunar-core damping
        % difference (abstract); below 1 m for the planets over the 1100-year
        % span and below 2 m for the Moon across 1970-2020, growing outside it
        % and mostly along-track (section 1); DE440 1550-2650 against DE441
        % -13,200 to +17,191 (abstract); DE440 for modern data and DE441 for
        % historic (section 1); the ~100 km barycentre shift from DE430 and
        % its Kuiper-belt cause (section 2.2). Every figure below is the
        % paper's. DOI 10.3847/1538-3881/abd414.
        %
        % MY EARLIER WORDING - "one solution over two spans" - WAS WRONG AND
        % IS CORRECTED HERE. They are two integrations from one fit with a
        % different lunar core assumption. The distinction matters at the
        % Moon and outside 1970-2020, which is exactly where this project
        % works, so it is not a pedantic one.
        %
        % THE sb441 HALF IS NOW CITED TOO, AND THE CITATION CORRECTS THE
        % CLAIM RATHER THAN CONFIRMING IT (rev. 1.189). Park et al. never
        % mentions the distribution files; the authority for those is
        % Farnocchia, IOM 392R-21-005, 2021 March 30, and it says three
        % things that matter here.
        %
        %   1. The file holds the ephemerides of the small-body perturbers
        %      USED BY Park et al. FOR DE440 AND DE441 - the 343 inherited
        %      from DE431 plus 30 Kuiper-belt objects - so sb441 belongs to
        %      this fit and to no other. THAT is what the family declaration
        %      below needs, and it is now read rather than inferred.
        %   2. The memo states the file is for use with DE441: each perturber
        %      was integrated against DE441 as the reference planetary
        %      ephemeris, and the masses are set by the DE441 solution.
        %      **IT DOES NOT SAY sb441 PAIRS WITH DE440**, which is what this
        %      project had assumed from the naming. Furnishing sb441-n16
        %      beside a DE440 planetary kernel is therefore a MIXTURE - a
        %      bounded one: Park et al. puts the DE440-to-DE441 planetary
        %      difference below 1 m over 1550-2650, which is the whole error
        %      the substitution can introduce into the perturbers' reference,
        %      and that is under the metre-level accuracy this tier claims.
        %      A guess became a quantified approximation; it did not become
        %      an identity. The strictly consistent set is DE441 + sb441.
        %   3. The iteration-to-iteration differences are within about 1 km
        %      over 1500-2500 and reach 1000 km at the ends of the -8001 to
        %      +9000 span, and the memo says explicitly that these measure
        %      CONVERGENCE AND NOT EPHEMERIS UNCERTAINTY. So no published
        %      bound on Ceres is available even now: the 8 km measured at
        %      run 74 against HORIZONS remains a comparison between a frozen
        %      2021 sixth-iteration solution and a current one, and no
        %      planetary bound should be read against it.
        %
        % CHECKED ACROSS THE TWO DOCUMENTS RATHER THAN BELIEVED (O23 - a
        % reference must not be reconstructed by the route it verifies). The
        % memo's Table 1 gives Ceres and Vesta in au^3/d^2, Park et al.
        % Table 2 gives them in km^3/s^2; converting with au = 1.495978707e8
        % km and 86400 s/day:
        %
        %   Ceres  62.628889 against 62.628900 km^3/s^2, 1.8e-7 relative
        %   Vesta  17.288233 against 17.288245 km^3/s^2, 7.0e-7 relative
        %
        % Both differ by about 1.2e-5 km^3/s^2 - roughly one unit in the last
        % digit Park prints, and EQUAL IN ABSOLUTE TERMS across masses that
        % differ by a factor 3.6, which is the signature of rounding in the
        % printed table and not of a scale error in the conversion. The two
        % documents carry the same masses to the precision they publish, so
        % the file and the fit are the same solution.
        %
        % THE MEMO CONTRADICTS ITSELF TWICE AND NEITHER SLIP IS COPIED HERE:
        % its subject line reads "SB441-N16 and SB441-N343" while the body
        % describes SB441-N373 throughout, and one sentence calls the reduced
        % file "SB431-N16" where SB441-N16 is meant. Named because O26 counts
        % transcription failures in this project at about one row in four,
        % and a source that is itself inconsistent is where they start.
        % Ceres is SPICE ID 2000001 in Table 1, which is the id this suite
        % addresses it by.
        %
        % DE43x is excluded on the paper's own numbers: the barycentre moved
        % by about 100 km between DE430 and DE440, mainly from the added
        % Kuiper-belt masses. A test comparing against an undefined mixture of
        % the two would still be green, which is why the set is chosen rather
        % than furnished whole.
        CompatibleGenerations = ["DE440", "DE441"];

        % Heliocentric distance band each body occupies, in au: perihelion and
        % aphelion widened by a few per cent. NO TWO BANDS OVERLAP except
        % earth / moon / earthMoonBarycentre, which are separated by the lunar
        % test instead. Taken from published orbital elements, not from this
        % toolbox, which is the whole point of the test.
        distanceBand = struct( ...
            'sun',                 [0.000, 0.020], ...
            'mercury',             [0.290, 0.480], ...
            'venus',               [0.700, 0.740], ...
            'earth',               [0.975, 1.025], ...
            'moon',                [0.972, 1.028], ...
            'mars',                [1.370, 1.680], ...
            'jupiter',             [4.930, 5.470], ...
            'saturn',              [8.980, 10.150], ...
            'uranus',              [18.230, 20.150], ...
            'neptune',             [29.750, 30.400], ...
            'earthMoonBarycentre', [0.975, 1.025]);
    end

    methods (Access = private)

        function root = toolboxRoot(~)
            %TOOLBOXROOT Absolute path of the distribution folder.
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function epoch = sampleEpoch(~, count)
            %SAMPLEEPOCH A TT epoch of COUNT entries, one hour apart, at MJD 60000.
            day = repmat(60000, count, 1);
            sec = 43200 + 3600*(0:count - 1).';
            epoch = referenceSystem.daySecondToEpoch([day sec], "TT");
        end

        function ephemeris = requirePlanetaryKernel(testCase)
            %REQUIREPLANETARYKERNEL Furnish a COHERENT SPK set from data/, or skip.
            %
            %   D110 REMOVED THE REFUSAL THIS HELPER WAS LEANING ON. Until
            %   rev. 1.175 it offered everything in data/ and let readEphemeris
            %   refuse an incoherent set; now nothing refuses, so a folder
            %   holding DE430, DE440, DE441 and DE442 - which Matthias's does -
            %   would be furnished whole, and SPICE would resolve every
            %   overlapping body from whichever file happened to load last.
            %   **The ephemeris tests would then be checking against an
            %   undefined mixture and would still be green.** Choosing the set
            %   is now this helper's job, and it is done from the kernels'
            %   own comment areas rather than from their names.
            %
            %   THE FAMILY IS DECLARED IN ONE PLACE AND THIS DOCSTRING DOES
            %   NOT RESTATE IT. See CompatibleGenerations above: it carries
            %   the citation (Park et al. 2021, AJ 161:105) and the two
            %   figures the declaration rests on, and it is what admits the
            %   sb441 asteroid file beside a DE440 planetary kernel.
            %
            %   UNTIL REV. 1.188 THIS BLOCK HELD A SECOND COPY OF THAT
            %   ARGUMENT, AND THE COPY WENT STALE WHILE THE ORIGINAL DID NOT.
            %   It said the paper "has NOT been read here" ten revisions after
            %   rev. 1.178 read it, and it repeated the "one solution over two
            %   spans" wording that the same revision corrected as wrong. A
            %   reader ninety lines below the authority was told the opposite
            %   of what the authority says - O20: a mirror derives or it
            %   points; it never copies.
            %
            %   Digest is off: hashing a 650 MB small-body kernel per call
            %   would dominate the suite, and this helper checks pairing and
            %   coverage, never provenance.
            testCase.assumeTrue(exist('cspice_spkezr', 'file') == 2 || ...
                exist('cspice_spkezr', 'file') == 3, ...
                'MICE is not on the path; the kernel-backed tier is skipped.');
            planetary = fullfile(referenceSystem.dataFolder(), 'de440s.bsp');
            testCase.assumeTrue(isfile(planetary), ...
                "de440s.bsp is not in " + referenceSystem.dataFolder() + ...
                "; run setupReferenceSystem(Fetch = ""kernels"").");

            found = dir(fullfile(referenceSystem.dataFolder(), '*.bsp'));
            kernel = string(fullfile({found.folder}, {found.name}));
            family = TestEphemeris.CompatibleGenerations;

            keep = false(size(kernel));
            for k = 1:numel(kernel)
                single = referenceSystem.readEphemeris(kernel(k), ...
                    'Digest', false);
                keep(k) = ~single.meta.generationVerified || ...
                    any(single.meta.generations == family);
            end

            warningState = warning('off', ...
                'referenceSystem:readEphemeris:mixedGenerations');
            restoreWarning = onCleanup(@() warning(warningState)); %#ok<NASGU>
            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>

            ephemeris = referenceSystem.readEphemeris(kernel(keep), ...
                'Digest', false, 'AllowGenerations', family);

            if any(~keep)
                testCase.log(1, TestPerformance.noteRecord( ...
                    "furnished SPK set", ...
                    sum(keep) + " of " + numel(kernel) + " SPKs, " + ...
                    height(ephemeris.meta.bodies) + " bodies covered", ...
                    "excluded, outside the declared family " + ...
                    join(family, "+") + ": " + ...
                    join(string({found(~keep).name}), " ")));
            end
        end

        function fixture = horizonsFixture(testCase)
            %HORIZONSFIXTURE Parse the committed JPL HORIZONS state vectors.
            file = fullfile(testCase.toolboxRoot(), 'test', 'fixtures', ...
                'horizonsVectors.txt');
            testCase.assumeTrue(isfile(file), ...
                'horizonsVectors.txt is missing; run fetchHorizonsVectors.');
            text = string(splitlines(fileread(file)));
            text = text(startsWith(text, "VECTOR | ") & ~contains(text, "JDTDB"));

            fixture = struct('body', {}, 'julianDate', {}, 'state', {});
            for k = 1:numel(text)
                part = strtrim(split(text(k), "|"));
                number = str2double(strtrim(split(part(4), ",")));
                fixture(end + 1) = struct('body', part(2), ...
                    'julianDate', number(1), ...
                    'state', number(3:8)*1000);      %#ok<AGROW>
            end
        end

        function requireGateway(testCase)
            %REQUIREGATEWAY Assume the compiled gateway rather than fail without it.
            testCase.assumeTrue(referenceSystem.mexInfo().built, ...
                'The MEX gateway is not built; run referenceSystem.buildMex.');
        end

    end

    methods (Test, TestTags = {'contract'})

        function readEphemeris_contract_warnsOnTwoGenerationsFurnishedTogether(testCase)
            % D15's COMBINATION BRANCH, UNDER D110's RULE: IT WARNS, IT DOES
            % NOT REFUSE. Mixing generations is not harmless - different fits
            % differ by of order 100 km at the barycentre - but "not harmless"
            % is an argument for TELLING the caller, not for overruling them.
            % Comparing two generations deliberately is ordinary work, and a
            % library that will not let you do it is not protecting you.
            %
            % What must hold is that the mixture cannot happen UNNOTICED: the
            % warning fires, meta.generations lists every generation found,
            % and meta.ephemeris names the set rather than picking one of it.
            testCase.assumeTrue(exist('cspice_spkezr', 'file') == 2 || ...
                exist('cspice_spkezr', 'file') == 3, ...
                'MICE is not on the path; the kernel-backed tier is skipped.');
            found = dir(fullfile(referenceSystem.dataFolder(), '*.bsp'));
            testCase.assumeGreaterThanOrEqual(numel(found), 2, ...
                "Fewer than two SPKs are in data/, so no mixed set exists.");
            kernel = string(fullfile({found.folder}, {found.name}));

            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>
            mixed = testCase.verifyWarning(@() referenceSystem.readEphemeris( ...
                kernel, 'Digest', false), ...
                'referenceSystem:readEphemeris:mixedGenerations');

            testCase.assumeGreaterThanOrEqual(numel(mixed.meta.generations), 2, ...
                "The SPKs in data/ name one generation, so nothing is mixed.");
            testCase.verifyTrue(contains(mixed.meta.ephemeris, "+"), ...
                'A mixed set names its members, not one of them.');
            testCase.verifyTrue(mixed.meta.generationVerified, ...
                'Every generation was read from a comment area, so it is verified.');

            testCase.log(1, TestPerformance.noteRecord( ...
                "readEphemeris generation mix", ...
                join(mixed.meta.generations, "+"), ...
                "furnished together and accepted with a warning (D110)"));

            % AND EACH ALONE MUST RAISE NOTHING, or the warning above would be
            % telling us about the function rather than about the set.
            for k = 1:numel(kernel)
                lastwarn('', '');
                referenceSystem.readEphemeris(kernel(k), 'Digest', false);
                [~, raised] = lastwarn;
                testCase.verifyNotEqual(string(raised), ...
                    "referenceSystem:readEphemeris:mixedGenerations", ...
                    "A single kernel reported a mixture: " + kernel(k));
            end
        end

        function readEphemeris_contract_allowGenerationsSilencesTheWarning(testCase)
            % ONCE THE CALLER HAS DECIDED, THE WARNING MUST STOP - AND ONLY
            % FOR WHAT THEY DECIDED. A warning that keeps firing after the
            % question has been settled is how a WARNINGS section becomes
            % something a reader skips, which is the failure O17 exists to
            % prevent. So naming a set silences it for exactly that set.
            %
            % TWO PROPERTIES, AND THE SECOND IS THE ONE THAT MATTERS. Naming
            % every generation present silences the warning; naming only some
            % of them does not - a declaration that quietly covered a
            % generation the caller had not named would be the boolean this
            % option exists to avoid.
            testCase.assumeTrue(exist('cspice_spkezr', 'file') == 2 || ...
                exist('cspice_spkezr', 'file') == 3, ...
                'MICE is not on the path; the kernel-backed tier is skipped.');
            found = dir(fullfile(referenceSystem.dataFolder(), '*.bsp'));
            testCase.assumeGreaterThanOrEqual(numel(found), 2, ...
                "Fewer than two SPKs are in data/, so no mixed set exists.");
            kernel = string(fullfile({found.folder}, {found.name}));

            present = strings(0, 1);
            for k = 1:numel(kernel)
                single = referenceSystem.readEphemeris(kernel(k), ...
                    'Digest', false);
                if single.meta.generationVerified
                    present(end + 1, 1) = single.meta.ephemeris; %#ok<AGROW>
                end
            end
            distinct = unique(present);
            testCase.assumeGreaterThanOrEqual(numel(distinct), 2, ...
                "The SPKs in data/ name one generation, so nothing is mixed.");

            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>

            % DECLARING EVERY GENERATION PRESENT MUST SILENCE IT.
            lastwarn('', '');
            allowed = referenceSystem.readEphemeris(kernel, 'Digest', false, ...
                'AllowGenerations', distinct);
            [~, raised] = lastwarn;
            testCase.verifyNotEqual(string(raised), ...
                "referenceSystem:readEphemeris:mixedGenerations", ...
                'A fully declared family still warned.');
            testCase.verifyEqual(sort(allowed.meta.generations), ...
                reshape(sort(distinct), 1, []), ...
                'meta.generations must list every generation furnished.');

            % DECLARING ONLY SOME OF THEM MUST STILL WARN. This is the half a
            % boolean could not express and the reason the option takes a
            % list: the caller declares a FAMILY, not a mood.
            testCase.verifyWarning(@() referenceSystem.readEphemeris(kernel, ...
                'Digest', false, 'AllowGenerations', distinct(1)), ...
                'referenceSystem:readEphemeris:mixedGenerations');
        end

        function readEphemeris_contract_neverAcceptsAnUnverifiedGeneration(testCase)
            % OPEN ITEM B5, REWRITTEN AFTER RUN 68 REFUTED THE FIRST VERSION.
            % That version asserted that de440s.bsp with ExpectedEphemeris
            % "DE430" must raise mismatchedGeneration. IT DID NOT RAISE, and
            % the reason is a defect the test had no way to predict:
            % localCheckPairing returned the CALLER'S OWN declaration whenever
            % no comment area named a generation, and meta.ephemeris then
            % carried a declared value indistinguishable from a measured one -
            % which is precisely the distinction D15 exists to draw. The test
            % found a real fault by asserting the right thing about the wrong
            % assumption, which is the best outcome available to a first test.
            %
            % THIS VERSION ASSERTS THE PROPERTY THAT HOLDS IN BOTH WORLDS AND
            % FORBIDS THE DEFECT IN EITHER. A stated expectation must be
            % either REFUSED, because a comment area contradicts it, or
            % REPORTED AS UNVERIFIED. What may never happen is the third
            % thing: silent agreement. That is checkable without knowing what
            % this particular kernel's comment area contains, which the
            % previous version assumed and should not have (obligation O28 -
            % the file is the authority, and it had not been read).
            testCase.assumeTrue(exist('cspice_spkezr', 'file') == 2 || ...
                exist('cspice_spkezr', 'file') == 3, ...
                'MICE is not on the path; the kernel-backed tier is skipped.');
            kernel = fullfile(referenceSystem.dataFolder(), 'de440s.bsp');
            testCase.assumeTrue(isfile(kernel), ...
                "de440s.bsp is not in " + referenceSystem.dataFolder() + ...
                "; run setupReferenceSystem(Fetch = ""kernels"").");

            refused = false;
            reportedUnverified = false;
            warned = false;
            previous = warning('off', ...
                'referenceSystem:readEphemeris:generationNotVerified');
            restoreWarning = onCleanup(@() warning(previous)); %#ok<NASGU>
            % A TEST THAT RAISES A WARNING DELIBERATELY CONSUMES IT, which is
            % WarningRecordingPlugin's documented rule and not a workaround:
            % suppression does not hide a warning from lastwarn, so without
            % this the WARNINGS section fills with warnings somebody asked for
            % and stops being worth reading. A cleanup rather than a trailing
            % statement, so it fires on failure and on a filtered assumption
            % too - which rev. 1.167's trailing lastwarn('') did not.
            consumeWarning = onCleanup(@() lastwarn('', '')); %#ok<NASGU>
            lastwarn('');
            try
                ephemeris = referenceSystem.readEphemeris(string(kernel), ...
                    'ExpectedEphemeris', "DE430");
                reportedUnverified = ~ephemeris.meta.generationVerified;
                [~, warningId] = lastwarn;
                warned = string(warningId) == ...
                    "referenceSystem:readEphemeris:generationNotVerified";
            catch exception
                refused = string(exception.identifier) == ...
                    "referenceSystem:readEphemeris:mismatchedGeneration";
                if ~refused
                    rethrow(exception)
                end
            end

            testCase.verifyTrue(refused || reportedUnverified, ...
                ['A stated ExpectedEphemeris was neither refused nor ', ...
                'reported as unverified. Silent agreement with the ', ...
                'caller''s own declaration is the declared pairing D15 ', ...
                'forbids, wearing the measured one''s clothes.']);
            if reportedUnverified
                testCase.verifyTrue(warned, ...
                    ['generationVerified is false and no warning was ', ...
                    'raised. A flag nobody reads is not a report (O17).']);
            end

            % AND THE TRUTHFUL DECLARATION MUST BE ACCEPTED, or everything
            % above would pass on a function that refuses or doubts
            % everything. The pair is what makes either half an assertion.
            accepted = referenceSystem.readEphemeris(string(kernel), ...
                'ExpectedEphemeris', "DE440");
            testCase.verifyNotEmpty(accepted);

        end

            function ephemerisBodies_contract_returnsDocumentedColumns(testCase)
                bodies = referenceSystem.ephemerisBodies();

                testCase.verifyClass(bodies, 'table');
                testCase.verifyEqual(string(bodies.Properties.VariableNames), ...
                    ["Body", "NaifId", "Model", "PositionError", ...
                    "VelocityError", "BodyIndex"]);
                testCase.verifyEqual(height(bodies), 11, ...
                    'The SOFA provider supplies eleven bodies.');
                testCase.verifyClass(bodies.Body, 'string');
                testCase.verifyTrue(all(bodies.PositionError > 0));
                testCase.verifyTrue(all(bodies.VelocityError > 0));

                % The gateway index is zero-based and contiguous, because it is an
                % index into an enum and a gap would mean a body was removed from
                % one side of the boundary and not the other.
                testCase.verifyEqual(sort(bodies.BodyIndex), (0:10).');
                testCase.verifyEqual(numel(unique(bodies.Body)), 11, ...
                    'Body names must be unique; they are the lookup key.');
            end

            function ephemerisBodies_contract_unknownSourceIsRefused(testCase)
                testCase.verifyError( ...
                    @() referenceSystem.ephemerisBodies(Source = "de440"), ...
                    'referenceSystem:ephemerisBodies:unknownSource');
            end

            function ephemerisBodies_contract_miceNeedsAFurnishedKernelSet(testCase)
                % There is no fixed MICE body list, and answering from a table
                % rather than from the kernel is how a body gets reported that
                % cannot be evaluated.
                testCase.verifyError( ...
                    @() referenceSystem.ephemerisBodies(Source = "mice"), ...
                    'referenceSystem:ephemerisBodies:ephemerisRequired');
            end

            function barycentricBodyState_contract_shapeAndInfoFields(testCase)
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(5);

                [position, velocity, info] = ...
                    referenceSystem.barycentricBodyState("Mars", epoch);

                testCase.verifySize(position, [3 5], 'One column per epoch.');
                testCase.verifySize(velocity, [3 5]);
                testCase.verifyEqual(sort(string(fieldnames(info))), ...
                    sort(["body"; "naifId"; "source"; "model"; "frame"; "origin"; ...
                    "epochScale"; "positionError"; "velocityError"; ...
                    "frameBiasApplied"]));
                testCase.verifyEqual(info.body, "mars", ...
                    'The body name is resolved case-insensitively and returned canonical.');
                testCase.verifyEqual(info.epochScale, "TDB");
                testCase.verifyEqual(info.frame, "BCRS");
                testCase.verifyFalse(info.frameBiasApplied, ...
                    'The SOFA provider does not rotate iauPlan94 into the ICRS.');
            end

            function barycentricBodyState_contract_unknownBodyIsRefused(testCase)
                testCase.verifyError( ...
                    @() referenceSystem.barycentricBodyState("pluto", ...
                    testCase.sampleEpoch(1)), ...
                    'referenceSystem:barycentricBodyState:unknownBody');
            end

            function barycentricBodyState_contract_ut1EpochIsRefused(testCase)
                % UT1 reaches TDB only through Delta UT1 and this function takes
                % none; assuming zero is up to 0.9 s, which is 27 km of Earth
                % motion and five times the provider's own error.
                epoch = referenceSystem.daySecondToEpoch([60000 43200], "UT1");

                testCase.verifyError( ...
                    @() referenceSystem.barycentricBodyState("earth", epoch), ...
                    'referenceSystem:barycentricBodyState:wrongScale');
            end

            function geocentricBodyState_contract_reportsItsFrameHonestly(testCase)
                testCase.requireGateway();

                [~, ~, info] = referenceSystem.geocentricBodyState("moon", ...
                    testCase.sampleEpoch(1));

                % The field must not read "GCRS": it is a BCRS coordinate
                % difference and the ~6 m that separates the two is above the MICE
                % provider's accuracy tier.
                testCase.verifyFalse(strcmp(info.frame, "GCRS"), ...
                    'A coordinate difference must not be labelled a GCRS state.');
                testCase.verifySubstring(char(info.frame), 'coordinate difference');
            end

            function readEphemeris_contract_leapSecondKernelIsRefused(testCase)
                % Decision D89, and the guard is deliberately reachable on a
                % machine with no MICE: the refusal is checked BEFORE MICE is
                % looked for, or it would only hold where it is least likely to be
                % exercised.
                testCase.verifyError( ...
                    @() referenceSystem.readEphemeris("naif0012.tls"), ...
                    'referenceSystem:readEphemeris:leapSecondKernelRefused');
                testCase.verifyError( ...
                    @() referenceSystem.readEphemeris(["de440s.bsp", "naif0012.TLS"]), ...
                    'referenceSystem:readEphemeris:leapSecondKernelRefused', ...
                    'The extension test must be case-insensitive.');
            end

            function readEphemeris_contract_missingKernelIsNamed(testCase)
                missing = string(tempname) + ".bsp";

                % Either refusal is correct and which one fires depends on whether
                % MICE is installed; both name the problem rather than failing
                % somewhere inside cspice_furnsh.
                try
                    referenceSystem.readEphemeris(missing);
                    testCase.verifyFail('A non-existent kernel must be refused.');
                catch failure
                    testCase.verifyTrue(ismember(failure.identifier, ...
                        {'referenceSystem:readEphemeris:fileNotFound', ...
                        'referenceSystem:readEphemeris:miceUnavailable'}), ...
                        ['Unexpected identifier ' failure.identifier]);
                end
            end

            function convertTimeScale_contract_observerColumnCountIsChecked(testCase)
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(3);

                testCase.verifyError( ...
                    @() referenceSystem.convertTimeScale(epoch, "TDB", ...
                    Observer = [1 2; 3 4; 5 6]), ...
                    'referenceSystem:convertTimeScale:sizeMismatch');
            end


            function gcrsToBcrs_contract_scaleHasNoDefault(testCase)
                % Decision D67's rule, applied a third time. "none" and
                % "tdbCompatible" differ by L_C*|r| = 9.5 cm at the Earth's
                % surface, ninety-five times the 1 mm uncertainty the Conventions
                % state for the formula, and neither choice is visible in the
                % result.
                testCase.requireGateway();
                station = [4517590; 837897; 4442892];

                testCase.verifyError( ...
                    @() referenceSystem.gcrsToBcrs(station, [], testCase.sampleEpoch(1)), ...
                    'referenceSystem:gcrsToBcrs:scaleRequired');
                testCase.verifyError( ...
                    @() referenceSystem.bcrsToGcrs(station, [], testCase.sampleEpoch(1)), ...
                    'referenceSystem:bcrsToGcrs:scaleRequired');
                testCase.verifyError( ...
                    @() referenceSystem.gcrsToBcrs(station, [], testCase.sampleEpoch(1), ...
                    Scale = "tcbCompatible"), ...
                    'referenceSystem:gcrsToBcrs:unknownScale');
            end

            function gcrsToBcrs_contract_shapeAndInfoFields(testCase)
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(5);

                [rBcrs, ~, info] = referenceSystem.gcrsToBcrs( ...
                    [4517590; 837897; 4442892], [], epoch, ...
                    Scale = "tdbCompatible");

                testCase.verifySize(rBcrs, [3 5], ...
                    'One column per epoch, broadcast from a single column.');
                testCase.verifyEqual(sort(string(fieldnames(info))), ...
                    sort(["scale"; "scaleTerm"; "externalPotential"; ...
                    "potentialBodies"; "reference"; "statedUncertainty"]));
                testCase.verifyEqual(info.statedUncertainty, 1e-3, ...
                    'The Conventions state their own uncertainty as below 1 mm.');
                % AbsTol 0 because scaleTerm is not computed: it is L_C read
                % straight out of iersConstants and handed back. Any
                % difference at all would mean a second copy of the constant
                % exists somewhere, which is the thing worth catching here.
                testCase.verifyEqual(info.scaleTerm, ...
                    referenceSystem.iersConstants().lc, 'AbsTol', 0);
            end

            function gcrsToBcrs_contract_columnCountIsChecked(testCase)
                testCase.requireGateway();
                testCase.verifyError( ...
                    @() referenceSystem.gcrsToBcrs(zeros(3, 2), [], ...
                    testCase.sampleEpoch(5), Scale = "none"), ...
                    'referenceSystem:gcrsToBcrs:sizeMismatch');
            end

            function downloadKernels_contract_defaultModeDownloadsNothing(testCase)
                % One entry is 650 MB and another 2.6 GB, so the exploratory call
                % has to be the harmless one. This asserts that calling with no
                % arguments returns a plan and touches no network and no disk.
                manifest = referenceSystem.downloadKernels();

                testCase.verifyClass(manifest, 'table');
                testCase.verifyTrue(all(manifest.Status == "listed"), ...
                    'Mode "list" must not fetch or probe anything.');
                testCase.verifyTrue(all(isnan(manifest.Bytes)), ...
                    'Nothing is on disk, so no size may be reported.');
            end

            function downloadKernels_contract_setsAccumulateAndAllMeansAll(testCase)
                % D99, AND THE TEST IT REPLACES ASSERTED THE OPPOSITE. Rev. 1.134
                % gave "all" the meaning "everything except the 2.6 GB file",
                % documented it, and tested it - which turned a bad name into an
                % enforced one. A test is not neutral about a design: it makes the
                % behaviour it asserts expensive to change.
                minimal = referenceSystem.downloadKernels(Set = "minimal");
                orientation = referenceSystem.downloadKernels(Set = "orientation");
                everything = referenceSystem.downloadKernels(Set = "all");

                testCase.verifyTrue(all(ismember(minimal.File, orientation.File)), ...
                    'The sets must accumulate: orientation includes minimal.');
                testCase.verifyTrue(all(ismember(orientation.File, everything.File)), ...
                    'The sets must accumulate: all includes orientation.');
                testCase.verifyTrue(any(everything.File == "sb441-n16.bsp"), ...
                    '"all" must include the small bodies. It means all.');
            end

            function downloadKernels_contract_spanSelectsOneIssueOrBothOnRequest(testCase)
                % D114. de440s.bsp and de440.bsp are the SAME integration over
                % different intervals, so they agree in the overlap and SPICE
                % takes whichever was furnished last. Until rev. 1.191 that was
                % read as a reason to refuse both; D110 had already settled the
                % principle one level up, for whole generations - this toolbox
                % prevents an unknowing mixture, not a deliberate choice. So a
                % NAMED span still returns exactly one planetary kernel, and
                % "both" returns exactly the union of the two.
                for setName = ["minimal", "orientation", "all"]
                    for spanName = ["short", "full"]
                        manifest = referenceSystem.downloadKernels( ...
                            Set = setName, Span = spanName);
                        planetary = manifest.File(startsWith(manifest.File, "de440"));
                        testCase.verifyEqual(numel(planetary), 1, ...
                            sprintf(['Set "%s" Span "%s" returned %d planetary ', ...
                            'kernels; exactly one is correct.'], setName, ...
                            spanName, numel(planetary)));
                        if spanName == "short"
                            testCase.verifyEqual(planetary, "de440s.bsp");
                        else
                            testCase.verifyEqual(planetary, "de440.bsp");
                        end
                    end

                    both = referenceSystem.downloadKernels( ...
                        Set = setName, Span = "both");
                    testCase.verifyEqual( ...
                        sort(both.File(startsWith(both.File, "de440"))), ...
                        ["de440.bsp"; "de440s.bsp"], ...
                        sprintf(['Set "%s" Span "both" must return both ', ...
                        'issues of the planetary ephemeris.'], setName));

                    % "both" changes the SPAN axis and nothing else: the rest
                    % of the selection must be identical to either named span.
                    %
                    % (:) ON BOTH SIDES, AND RUN 82 IS WHY. For Set "minimal"
                    % every row is planetary, so both sides are empty - but
                    % they are empty in DIFFERENT SHAPES. The "short" manifest
                    % has ONE row, and MATLAB returns 0x0 when a SCALAR source
                    % is indexed by a false logical, while the two-row "both"
                    % manifest returns 0x1. verifyEqual compares size, so the
                    % test failed on a shape that carries no information. This
                    % is the same family as rev. 1.147's (:,1) rejecting a 0x0
                    % and B5's column-major flatten: an empty's orientation is
                    % an artefact of how it was made, never a result, so it is
                    % normalised before comparison and not asserted.
                    short = referenceSystem.downloadKernels( ...
                        Set = setName, Span = "short");
                    bothOther = sort(both.File(~startsWith(both.File, "de440")));
                    shortOther = sort(short.File(~startsWith(short.File, "de440")));
                    testCase.verifyEqual(bothOther(:), shortOther(:), ...
                        'Span must not disturb the Set selection.');
                end
            end

            function downloadKernels_contract_fullSpanSizeIsDe440NotDe441(testCase)
                % REV. 1.191: the catalogue carried 2.6e9 for de440.bsp, which
                % is DE441's scale, and the help, the refusal message and D99's
                % reasoning all leaned on it. The replacement is DERIVED, not
                % measured, so this asserts the ORDER and not the number: the
                % long file is the same integration at the same Chebyshev
                % degree over 1100 years against the short file's 300, so it
                % must be a few times larger and cannot be a hundred times.
                % Pinning 120e6 would pin an estimate and would have to be
                % rewritten by the first real fetch, which is the measurement
                % this bound is waiting for.
                manifest = referenceSystem.downloadKernels(Span = "both");
                shortBytes = manifest.ApproximateBytes( ...
                    manifest.File == "de440s.bsp");
                fullBytes = manifest.ApproximateBytes( ...
                    manifest.File == "de440.bsp");

                ratio = fullBytes/shortBytes;
                testCase.verifyGreaterThan(ratio, 2, ...
                    sprintf(['de440.bsp is %.2fx de440s.bsp; it covers 3.7x ', ...
                    'the span of the same integration.'], ratio));
                testCase.verifyLessThan(ratio, 10, ...
                    sprintf(['de440.bsp is %.2fx de440s.bsp. A figure this ', ...
                    'large is DE441 confused in - DE440 spans 1100 years, ', ...
                    'DE441 spans 33000.'], ratio));
            end

            function downloadKernels_contract_unknownSpanIsRefused(testCase)
                testCase.verifyError( ...
                    @() referenceSystem.downloadKernels(Span = "deepTime"), ...
                    'referenceSystem:downloadKernels:unknownSpan', ...
                    ['"deepTime" was a Set value until D99 and is now a Span ', ...
                    'that does not exist; the refusal must name the real ones.']);
            end

            function downloadKernels_contract_noLeapSecondKernelInTheCatalogue(testCase)
                % D89 AT THE OTHER END OF THE PATH. readEphemeris refuses to
                % furnish a .tls; this asserts that nothing offers to fetch one, so
                % a caller who trusted the catalogue could not acquire one to
                % furnish. Both ends, because either alone leaves a way through.
                manifest = referenceSystem.downloadKernels(Set = "all");
                testCase.verifyFalse(any(endsWith(lower(manifest.File), ".tls")), ...
                    'A leapseconds kernel must never appear in the catalogue.');

                full = referenceSystem.downloadKernels(Set = "all", Span = "full");
                testCase.verifyFalse(any(endsWith(lower(full.File), ".tls")));
            end

            function downloadKernels_contract_unknownSetAndModeAreRefused(testCase)
                testCase.verifyError( ...
                    @() referenceSystem.downloadKernels(Set = "everything"), ...
                    'referenceSystem:downloadKernels:unknownSet');
                testCase.verifyError( ...
                    @() referenceSystem.downloadKernels(Mode = "fetch"), ...
                    'referenceSystem:downloadKernels:unknownMode');
            end

            function downloadKernels_contract_smallBodiesUrlIsNotOnTheNaifTree(testCase)
                % OBLIGATION O26, TURNED INTO A TEST. sb441-n16.bsp is a JPL SSD
                % file; the NAIF asteroid directory holds codes_300ast_20100725.bsp,
                % a DE405-era set whose use with DE440 is the D15 generation error.
                % The handover carried the wrong host for four sessions, so the
                % distinction is asserted rather than described.
                manifest = referenceSystem.downloadKernels(Set = "all");
                smallBodies = manifest(manifest.File == "sb441-n16.bsp", :);

                testCase.verifySize(smallBodies, [1 10]);
                testCase.verifySubstring(char(smallBodies.Url), 'ssd.jpl.nasa.gov');
                testCase.verifyFalse(contains(smallBodies.Url, "naif.jpl.nasa.gov"), ...
                    'sb441-n16.bsp is NOT a NAIF generic kernel.');
                testCase.verifyFalse(any(contains(manifest.File, "codes_300ast")), ...
                    'The DE405-era perturber set must never be offered.');
            end

            function downloadKernels_contract_partialFetchWarnsAndReturnsTheManifest(testCase)
                % D98, AND THE ONLY TEST IN THIS CLASS WRITTEN BECAUSE A REAL RUN
                % FAILED. Rev. 1.134 raised on a partial fetch "so the rows that
                % succeeded are not lost". A MATLAB function that throws returns
                % NOTHING, so the manifest was destroyed by the very mechanism
                % meant to preserve it, and setup reported "0 kernels" with four on
                % disk. The contract is now: WARN, and return.
                %
                % REV. 1.191 FOUND THREE THINGS WRONG WITH THIS TEST, AND THE
                % COMMENT WAS ONE OF THEM. It claimed the failure was "exercised
                % with an unreachable host ... so it needs no network and cannot
                % become flaky", and the code below has always called the REAL
                % NAIF url with a one-second timeout. It does need the network.
                % Worse, nothing here asserted that the warning was raised, so on
                % a machine that connects inside one second every assertion would
                % still pass while the D98 path went untested - a vacuous pass,
                % which is the failure mode this suite fears most. And the
                % warning reached the console on every run, because consuming it
                % through lastwarn keeps it out of the report but does not stop
                % MATLAB printing it.
                %
                % So: display is suppressed and the identifier is then read from
                % lastwarn, which works precisely because SUPPRESSION DOES NOT
                % HIDE A WARNING FROM lastwarn - the fact WarningRecordingPlugin
                % has documented since S4 and rev. 1.174 re-measured. If the host
                % does answer in time the premise is gone, and the test is
                % FILTERED rather than passed, because a test that cannot do its
                % job should say so in the report.
                warningId = 'referenceSystem:downloadKernels:incompleteFetch';
                previousState = warning('off', warningId);
                restoreWarning = onCleanup(@() warning(previousState)); %#ok<NASGU>
                cleanup = onCleanup(@() lastwarn('', ''));              %#ok<NASGU>
                lastwarn('', '');
                scratch = string(tempname);

                manifest = [];
                try
                    manifest = referenceSystem.downloadKernels( ...
                        Set = "minimal", Mode = "verify", Timeout = 1);
                catch failure
                    testCase.verifyFail(['downloadKernels must not throw on a ', ...
                        'failed transfer; it threw ' failure.identifier]);
                end

                testCase.verifyClass(manifest, 'table', ...
                    'The manifest must survive a failure, because it IS the artifact.');
                testCase.verifyEqual(height(manifest), 1);

                testCase.assumeTrue(startsWith(manifest.Status(1), "FAILED"), ...
                    ['The NAIF host answered inside the one-second timeout, so ', ...
                    'there is no failed transfer to observe on this machine. ', ...
                    'Filtered rather than passed: the assertions below would ', ...
                    'all hold and would have tested nothing. See H.11 for the ', ...
                    'catalogue seam that would make this deterministic.']);

                [~, raisedId] = lastwarn;
                testCase.verifyEqual(string(raisedId), string(warningId), ...
                    'D98: a partial fetch WARNS, and this is the identifier.');
                testCase.verifyTrue(exist(scratch, 'dir') == 0, ...
                    'Mode "verify" must not create anything.');
            end

    end

    methods (Test, TestTags = {'reference'})

        function gcrsToBcrs_reference_velocityIsTheDerivativeOfThePosition(testCase)
            % P21b's ACTUAL VALIDATION, AND THE ORACLE SECTION H.7.7 PROMISED.
            % The IERS Conventions state no velocity transformation at all;
            % this one is differentiated from the spatial part of IAU 2000
            % Resolution B1.3 and divided by dT/dt from its time part. Nothing
            % in the toolbox can confirm that algebra - but a CENTRAL
            % DIFFERENCE of the position transformation can, and it shares no
            % line of code with it.
            %
            % The test is a convergence test, not a tolerance test (decision
            % D28). A correct derivative leaves a residual that falls as h^2; a
            % wrong one leaves a CONSTANT FLOOR. Halving h must therefore
            % quarter the residual, and that ratio is what is asserted -
            % measured 4.00 at every step from 100 s down to 3.125 s.
            % THE TRAJECTORY MUST BE CURVED OR THIS TEST MEASURES NOTHING.
            % The first version used a straight line, station + velocity*t,
            % which has no third derivative - so the central difference had
            % almost no truncation error, the residual sat on ROUNDOFF at
            % 1.7e-10 m/s, and the ratio came out 1.00 instead of 4.00. That
            % number is excellent news about the formula and useless as a
            % convergence test: it says the difference could not resolve the
            % truncation it was supposed to be measuring. A circular orbit
            % restores the regime the numpy validation ran in.
            testCase.requireGateway();
            base = 60000;
            radius = 6.8e6;
            rate = sqrt(referenceSystem.iersConstants().gmEarth/radius^3);
            tilt = 1.0;
            place = @(t) radius*[cos(rate*t); sin(rate*t)*cos(tilt); ...
                sin(rate*t)*sin(tilt)];
            move = @(t) radius*rate*[-sin(rate*t); cos(rate*t)*cos(tilt); ...
                cos(rate*t)*sin(tilt)];

            single = referenceSystem.daySecondToEpoch([base 43200], "TDB");
            [~, analytic] = referenceSystem.gcrsToBcrs(place(0), move(0), ...
                single, Scale = "none");

            step = [100, 50, 25];
            residual = zeros(size(step));
            for k = 1:numel(step)
                h = step(k);
                epochs = referenceSystem.daySecondToEpoch( ...
                    [repmat(base, 2, 1), 43200 + [-h; h]], "TDB");
                position = referenceSystem.gcrsToBcrs( ...
                    [place(-h), place(h)], [], epochs, Scale = "none");
                difference = (position(:, 2) - position(:, 1))/(2*h);
                residual(k) = norm(difference - analytic);
            end

            % LOGGED INTO THE D28 CONVERGENCE BLOCK, because this is the one
            % place in the toolbox where the order genuinely is two: the Rdot
            % rows sit at a reference floor below machine epsilon and can only
            % report a baseline. The step list is chosen to stay in the
            % truncation-dominated region, which is what a straight-line
            % trajectory failed to do at rev. 1.149.
            for k = 1:numel(step)
                if k == 1
                    order = NaN;
                    status = "baseline";
                else
                    order = log(residual(k - 1)/residual(k))/log(2);
                    status = "asserted";
                end
                testCase.log(1, TestPerformance.convergenceRecord( ...
                    "gcrsToBcrs v", step(k), residual(k), order, status));
            end

            % RelTol 0.15 on the ratio: the residual is dominated by the
            % difference's own h^2 truncation, so consecutive ratios must be 4
            % to within the noise of a straight-line trajectory. A constant
            % floor gives a ratio of 1 and cannot pass.
            testCase.verifyEqual(residual(1)/residual(2), 4, 'RelTol', 0.15, ...
                sprintf('residuals %.3e %.3e %.3e m/s', residual));
            testCase.verifyEqual(residual(2)/residual(3), 4, 'RelTol', 0.15, ...
                sprintf('residuals %.3e %.3e %.3e m/s', residual));
        end

        function barycentricBodyState_reference_miceMatchesTheHorizonsFixture(testCase)
            % THE CHECK SECTION H.7.5 ITEM 1 HAS BEEN WAITING FOR, AND THE
            % FIRST TIME THE "mice" PROVIDER HAS EVER BEEN EXECUTED. The
            % fixture is a committed record of what JPL HORIZONS returned on
            % 2026-07-29 for five bodies at three epochs - an authority
            % entirely outside this toolbox and outside the kernel.
            %
            % HORIZONS SERVES DE441 AND THE FURNISHED KERNEL IS DE440, SO THIS
            % MEASURES THAT DIFFERENCE RATHER THAN ASSUMING IT AWAY, which is
            % what section H.7.6 requires. The bound below is deliberately
            % loose on the first pass and the measured residual is reported in
            % the diagnostic; it is to be tightened from the measurement, never
            % from an expectation.
            %
            % Ceres needs sb441-n16.bsp, which is not in the "orientation"
            % kernel set, so its rows are skipped rather than failed - a body
            % the furnished kernels do not cover is not a defect.
            ephemeris = testCase.requirePlanetaryKernel();
            fixture = testCase.horizonsFixture();

            name = containers.Map( ...
                {'Sun', 'Moon', 'Mars Barycenter', 'Jupiter Barycenter'}, ...
                {"sun", "moon", "mars", "jupiter"});

            % CERES IS ADDED WHEN, AND ONLY WHEN, THE FURNISHED KERNELS COVER
            % IT (open item B4). The fixture has carried its three rows since
            % rev. 1.146 - THE FIXTURE WAS NEVER THE BLOCKER - and the reason
            % they were never checked is that de440s.bsp contains no asteroid.
            % Until now the map had no entry either, so the rows would have
            % been skipped EVEN WITH sb441-n16.bsp furnished: the test could
            % not have used the kernel if it were there.
            %
            % The registry is asked rather than assumed. readEphemeris reports
            % the union of the SPK body tables, and a body the bundled
            % ephemerisBodies does not name keeps the addressable naif<id>
            % form - Ceres is NAIF 2000001, so "naif2000001".
            if any(ephemeris.meta.bodies.NaifId == 2000001)
                name('Ceres') = "naif2000001";
            end

            worstPosition = [0 0];      % [planetary, small body]
            worstVelocity = [0 0];
            checked = 0;
            skipped = strings(0, 1);
            for k = 1:numel(fixture)
                if ~isKey(name, char(fixture(k).body))
                    % OPEN ITEM B4. THE SKIP IS NOW REPORTED RATHER THAN
                    % SILENT. Ceres needs sb441-n16.bsp, which is not in the
                    % "orientation" kernel set, so its rows cannot be checked
                    % here - but a fixture row that is quietly stepped over is
                    % indistinguishable in the report from one that passed,
                    % and the small-body path through Source = "mice" has
                    % therefore never been executed against an external
                    % authority without anything saying so. Obligation O17: a
                    % gap that reaches only the loop body reaches nobody.
                    %
                    % SINCE REV. 1.171 THIS IS REACHED ONLY FOR A BODY THE
                    % FURNISHED KERNELS GENUINELY DO NOT COVER, not for one
                    % the test simply had no name for.
                    skipped(end+1, 1) = string(fixture(k).body); %#ok<AGROW>
                    continue
                end
                % THERE IS NO julianDateToEpoch AND I NEARLY CALLED ONE.
                % The five constructors are mjdToEpoch, daySecondToEpoch,
                % datetimeToEpoch, gpsWeekToEpoch and j2000SecondsToEpoch.
                % The fixture epochs are exact half Julian days, so
                % JD - 2400000.5 is an integer MJD and the conversion is exact
                % rather than merely close.
                epoch = referenceSystem.mjdToEpoch(fixture(k).julianDate - ...
                    referenceSystem.iersConstants().julianDateOffset, "TDB");
                [position, velocity] = referenceSystem.barycentricBodyState( ...
                    name(char(fixture(k).body)), epoch, Source = "mice", ...
                    Ephemeris = ephemeris);

                % THE RESIDUALS ARE KEPT BY BODY CLASS, NOT POOLED, AND RUN 74
                % IS WHY. Pooling them put Ceres's 8021.9 m against a bound
                % chosen for planets, and the run then reported a "failure" in
                % a comparison that was working perfectly - it had simply
                % never been made before. A planetary ephemeris and a
                % small-body one are two accuracy regimes and one number
                % cannot bound both (obligation O8: a tolerance is a claim
                % about which error dominates, and here there are two).
                bodyId = TestEphemeris.naifIdOfName( ...
                    name(char(fixture(k).body)));
                if any(referenceSystem.ephemerisBodies().NaifId == bodyId)
                    class = 1;                     % in the bundled registry
                else
                    class = 2;                     % a small body from a kernel
                end
                worstPosition(class) = max(worstPosition(class), ...
                    norm(position - fixture(k).state(1:3)));
                worstVelocity(class) = max(worstVelocity(class), ...
                    norm(velocity - fixture(k).state(4:6)));
                checked = checked + 1;
            end

            testCase.verifyGreaterThanOrEqual(checked, 12, ...
                'Four bodies at three epochs must have been compared.');
            % AND FIFTEEN WHEN THE SMALL-BODY KERNEL IS THERE. A count that
            % only ever asserts its floor cannot notice that the kernel was
            % furnished and the rows still did not run, which is the exact
            % failure this item has already had once.
            if any(ephemeris.meta.bodies.NaifId == 2000001)
                testCase.verifyGreaterThanOrEqual(checked, 15, ...
                    ['sb441-n16.bsp is furnished, so Ceres must have been ', ...
                    'compared as well - five bodies at three epochs.']);
            end
            if ~isempty(skipped)
                % THE REASON IS DERIVED, NOT DECLARED. It read "sb441-n16.bsp
                % is not in the orientation kernel set" - a sentence that was
                % true when it was written and that the report went on
                % printing while the file sat in data/. That is the DECLARED
                % pairing all over again, in a diagnostic instead of in
                % metadata: a message asserting a fact about the world without
                % asking it. What is printed now is what was measured.
                testCase.log(1, TestPerformance.noteRecord( ...
                    "barycentricBodyState (mice)", ...
                    "not compared: " + join(unique(skipped), ","), ...
                    "the furnished kernels cover " + ...
                    height(ephemeris.meta.bodies) + " bodies and none of " + ...
                    "them is this one"));
            end
            % BOTH FIGURES ARE REPORTED WHETHER THEY PASS OR NOT, because a
            % bound that passes silently is how the small-body regime went
            % unmeasured for thirty revisions in the first place.
            testCase.log(1, TestPerformance.noteRecord( ...
                "barycentricBodyState (mice) vs HORIZONS", ...
                sprintf('planetary %.1f m, small body %.1f m', ...
                    worstPosition(1), worstPosition(2)), ...
                sprintf(['%d comparisons, DE440+sb441 (a bounded mixture: ', ...
                    'sb441 is referenced to DE441) against HORIZONS DE441'], ...
                    checked)));

            % 1000 m FOR THE PLANETARY BODIES. This bounds the DE440-minus-
            % DE441 difference plus any residual frame or unit error, and it
            % has held on every run since rev. 1.146.
            testCase.verifyLessThan(worstPosition(1), 1000, ...
                sprintf('worst planetary position residual %.3f m', ...
                worstPosition(1)));
            testCase.verifyLessThan(worstVelocity(1), 0.01, ...
                sprintf('worst planetary velocity residual %.6f m/s', ...
                worstVelocity(1)));

            % 50 km AND 0.1 m/s FOR A SMALL BODY, FROM THE MEASUREMENT AND NOT
            % FROM AN EXPECTATION. Run 74 measured 8021.9 m for Ceres, which
            % is 2e-8 of its 2.77 au distance: a frozen 2021 small-body
            % integration against HORIZONS' current solution, over epochs from
            % 2000 to 2025. **That is the ephemerides disagreeing, not this
            % toolbox being wrong**, and it is the first number the small-body
            % path has ever produced against an outside authority. The bound
            % keeps the discrimination that matters - a unit or frame blunder
            % is three to six orders larger and could not hide under it -
            % while leaving room for a different asteroid kernel.
            %
            % THE SOURCE MEMO DECLINES TO GIVE AN UNCERTAINTY AND SAYS SO IN
            % SO MANY WORDS (Farnocchia, IOM 392R-21-005; see
            % CompatibleGenerations). Its iteration-to-iteration differences
            % are within about 1 km over 1500-2500, and it states explicitly
            % that these measure CONVERGENCE, NOT EPHEMERIS UNCERTAINTY. So
            % 50 km cannot be derived from a published bound even now, and it
            % stays what it has been since rev. 1.177: a discrimination
            % threshold set from the measurement, with the measurement logged
            % beside it whether it passes or not.
            if worstPosition(2) > 0
                testCase.verifyLessThan(worstPosition(2), 50e3, ...
                    sprintf('worst small-body position residual %.1f m', ...
                    worstPosition(2)));
                testCase.verifyLessThan(worstVelocity(2), 0.1, ...
                    sprintf('worst small-body velocity residual %.6f m/s', ...
                    worstVelocity(2)));
            end
        end

            function bcrsToGcrs_reference_matchesADenseSolveOfTheConventions(testCase)
                % bcrsToGcrs HAD NO reference COVERAGE AND THE SUITE SAID SO.
                % The provenance audit reported it lacking, and the honest fix
                % is to write the test rather than claim the category is
                % impossible - this function HAS an authority, which is more
                % than the three entries exempted alongside it can say.
                %
                % THE ORACLE IS A DIFFERENT SOLVER, NOT A SECOND CALL. IERS
                % Eq. (11.19) is assembled here as an explicit 3-by-3 matrix
                % and inverted with MATLAB's backslash, a dense LU with
                % partial pivoting; the function under test uses
                % Sherman-Morrison on a rank-one update and never forms the
                % matrix. Agreement means the closed form is right, not merely
                % self-consistent.
                testCase.requireGateway();
                epoch = referenceSystem.daySecondToEpoch([60000 43200], "TT");
                constants = referenceSystem.iersConstants();
                station = [4517590; 837897; 4442892];

                [~, earthVelocity] = ...
                    referenceSystem.barycentricBodyState("earth", epoch);
                sunFromEarth = referenceSystem.geocentricBodyState("sun", epoch);
                moonFromEarth = referenceSystem.geocentricBodyState("moon", epoch);
                potential = constants.gmSun/norm(sunFromEarth) + ...
                    constants.gmMoon/norm(moonFromEarth);
                cSquared = constants.speedOfLight^2;

                % THE ORACLE IS AN INDEPENDENTLY WRITTEN FORWARD MAP APPLIED
                % TO THE FUNCTION'S OUTPUT. A dense solve of alpha*I +
                % beta*V*V' was the oracle until rev. 1.147, when Resolution
                % B1.3's quadratic acceleration terms made the map nonlinear -
                % NO MATRIX REPRESENTS IT, so the old oracle was testing a
                % formula the function no longer implements. The full B1.3
                % forward map is written out here from Soffel Appendix A1 and
                % must undo bcrsToGcrs exactly.
                acceleration = ...
                    constants.gmSun*sunFromEarth/norm(sunFromEarth)^3 + ...
                    constants.gmMoon*moonFromEarth/norm(moonFromEarth)^3;
                forward = @(r) r + (0.5*earthVelocity*(earthVelocity'*r) + ...
                    (potential + constants.lc*cSquared)*r + ...
                    r*(acceleration'*r) - 0.5*acceleration*(r'*r))/cSquared;

                % COMPARED WITH bcrsToGcrs, NOT COMPOSED WITH IT. The first
                % version wrote forward(bcrsToGcrs(station)) and expected the
                % input back - but `forward` IS what bcrsToGcrs computes, so
                % that applied the map twice. Resolution B1.3 states X(GCRS)
                % as a function of r(BCRS), so BCRS to GCRS is the direction
                % the resolution gives directly, applyBcrsToGcrs ADDS the
                % terms, and bcrsToGcrs is therefore the FORWARD map while
                % gcrsToBcrs is the iterated inverse. Two independent
                % implementations of one map, compared.
                expected = forward(station);
                actual = referenceSystem.bcrsToGcrs(station, [], epoch, ...
                    Scale = "tdbCompatible");

                % AbsTol 1e-9 m is the roundoff of a 3-by-3 solve at the
                % 6.4e6 m scale - 6.4e6 times eps is 1.4e-9 - and not a bound
                % chosen to make two different algorithms agree.
                testCase.verifyEqual(actual, expected, 'AbsTol', 1e-9, ...
                    ['bcrsToGcrs must agree with an independently written ', ...
                    'B1.3 forward map.']);
            end

            function barycentricBodyState_reference_everyBodyIsWhereItBelongs(testCase)
                % THE TEST THAT VALIDATES THE ENUM MAPPING, AND THE ONLY ONE THAT
                % CAN. ephemerisBodies mirrors RS_BODY_* in mex/rsCore.h and MATLAB
                % cannot see that enum; a test comparing the registry against a
                % second list would agree with itself. Every body is fetched
                % instead and required to lie in the heliocentric distance band it
                % alone occupies, taken from published orbital elements. A permuted
                % enum puts Jupiter at 1 au and cannot survive this.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(1);
                au = 1.49597870700e11;

                sunPosition = referenceSystem.barycentricBodyState("sun", epoch);
                bodies = referenceSystem.ephemerisBodies();

                for k = 1:height(bodies)
                    name = bodies.Body(k);
                    position = referenceSystem.barycentricBodyState(name, epoch);
                    if name == "sun"
                        distance = norm(position)/au;       % from the barycentre
                    else
                        distance = norm(position - sunPosition)/au;
                    end
                    band = testCase.distanceBand.(name);
                    testCase.verifyGreaterThanOrEqual(distance, band(1), ...
                        sprintf('%s is at %.4f au, below its band.', name, distance));
                    testCase.verifyLessThanOrEqual(distance, band(2), ...
                        sprintf('%s is at %.4f au, above its band.', name, distance));
                end
            end

            function geocentricBodyState_reference_lunarDistanceIsInBand(testCase)
                % The Moon's geocentric distance varies between about 356 400 and
                % 406 700 km. This separates the Moon from the Earth and from the
                % Earth-Moon barycentre, which the heliocentric bands cannot.
                testCase.requireGateway();

                position = referenceSystem.geocentricBodyState("moon", ...
                    testCase.sampleEpoch(1));
                distance = norm(position)/1000;

                testCase.verifyGreaterThan(distance, 356000, ...
                    sprintf('Lunar distance %.0f km is below perigee.', distance));
                testCase.verifyLessThan(distance, 407000, ...
                    sprintf('Lunar distance %.0f km is beyond apogee.', distance));
            end

            function barycentricBodyState_reference_earthSpeedMatchesTheKnownValue(testCase)
                % The Earth's barycentric speed is 29.29 to 30.29 km/s over a year.
                % This checks the au/day to m/s conversion, which is the one place
                % a factor of 86400 could be lost without changing any position.
                testCase.requireGateway();

                [~, velocity] = referenceSystem.barycentricBodyState("earth", ...
                    testCase.sampleEpoch(1));
                speed = norm(velocity)/1000;

                testCase.verifyGreaterThan(speed, 29.0, ...
                    sprintf('Earth barycentric speed %.3f km/s is too low.', speed));
                testCase.verifyLessThan(speed, 30.6, ...
                    sprintf('Earth barycentric speed %.3f km/s is too high.', speed));
            end

            function convertTimeScale_reference_topocentricTermMatchesTheLorentzTerm(testCase)
                % THE CROSS-PROMPT CHECK, AND IT USES NO SECOND EVALUATION OF
                % iauDtdb. The diurnal part of the topocentric TDB - TT term is
                % (v_E . r_obs)/c2 to first order, so an equatorial station sweeps
                % an amplitude of |v_E,equatorial| * a / c2. The Earth's barycentric
                % velocity comes from barycentricBodyState - a different function,
                % a different SOFA model - so the two prompts check each other with
                % physics neither of them contains. Measured residual 0.04 per cent
                % at MJD 60000; the tolerance is 1 per cent, which the omitted
                % potential and higher-order terms comfortably fit inside.
                testCase.requireGateway();

                equatorialRadius = referenceSystem.ellipsoidParameters("GRS80").a;
                speedOfLight = 299792458;
                sampleCount = 48;

                day = repmat(60000, sampleCount, 1);
                sec = (0:sampleCount - 1).'*(86400/sampleCount);
                epoch = referenceSystem.daySecondToEpoch([day sec], "TT");

                geocentric = referenceSystem.convertTimeScale(epoch, "TDB");
                station = referenceSystem.convertTimeScale(epoch, "TDB", ...
                    Observer = [equatorialRadius; 0; 0]);

                difference = (station.day - geocentric.day)*86400 + ...
                    (station.sec - geocentric.sec);
                measuredAmplitude = (max(difference) - min(difference))/2;

                [~, earthVelocity] = referenceSystem.barycentricBodyState("earth", ...
                    referenceSystem.daySecondToEpoch([60000 43200], "TT"));
                predictedAmplitude = hypot(earthVelocity(1), earthVelocity(2))* ...
                    equatorialRadius/speedOfLight^2;

                testCase.verifyEqual(measuredAmplitude, predictedAmplitude, ...
                    'RelTol', 0.01, ...
                    sprintf(['The diurnal topocentric term is %.4e s; the ', ...
                    'Lorentz term built from the Earth''s barycentric velocity ', ...
                    'predicts %.4e s.'], measuredAmplitude, predictedAmplitude));

                % And the size is worth asserting on its own: about 2 us, three
                % orders above iauDtdb's own accuracy, so it is not optional for
                % anything correlating a station clock.
                testCase.verifyGreaterThan(measuredAmplitude, 1.5e-6);
                testCase.verifyLessThan(measuredAmplitude, 2.5e-6);
            end

            function convertTimeScale_reference_polarStationLosesTheDiurnalTerm(testCase)
                % A second check that fails for a different reason than the first.
                % The diurnal term is proportional to the distance from the SPIN
                % AXIS, so at the pole it collapses while the term in the distance
                % north of the equator survives as a near-constant offset. A
                % transposed pair of observer arguments would pass the equatorial
                % test and fail here.
                testCase.requireGateway();

                polarRadius = referenceSystem.ellipsoidParameters("GRS80").b;
                sampleCount = 48;
                day = repmat(60000, sampleCount, 1);
                sec = (0:sampleCount - 1).'*(86400/sampleCount);
                epoch = referenceSystem.daySecondToEpoch([day sec], "TT");

                geocentric = referenceSystem.convertTimeScale(epoch, "TDB");
                polar = referenceSystem.convertTimeScale(epoch, "TDB", ...
                    Observer = [0; 0; polarRadius]);

                difference = (polar.day - geocentric.day)*86400 + ...
                    (polar.sec - geocentric.sec);

                testCase.verifyLessThan(max(difference) - min(difference), 5e-8, ...
                    'The diurnal term must vanish on the spin axis.');
                testCase.verifyGreaterThan(abs(mean(difference)), 1e-7, ...
                    'The term in the distance north of the equator must survive.');
            end

            function gcrsToBcrs_reference_termsMatchTheConventions(testCase)
                % EACH TERM OF IERS Eq. (11.19) IS CHECKED SEPARATELY AGAINST ITS
                % OWN CLOSED FORM, not against a second call to the same function.
                % The three are independently switchable: L_C appears only for
                % "tdbCompatible", U/c^2 is isotropic, and the Lorentz term is the
                % only one that depends on the direction of r.
                testCase.requireGateway();
                epoch = referenceSystem.daySecondToEpoch([60000 43200], "TT");
                constants = referenceSystem.iersConstants();
                station = [4517590; 837897; 4442892];

                withScale = referenceSystem.gcrsToBcrs(station, [], epoch, ...
                    Scale = "tdbCompatible");
                withoutScale = referenceSystem.gcrsToBcrs(station, [], epoch, ...
                    Scale = "none");

                % The difference between the two settings is exactly L_C * r.
                % RelTol 1e-6, AND THE FIRST VALUE HERE WAS 1e-12, WHICH THIS
                % ASSERTION CANNOT REACH. The identity is EXACT in real
                % arithmetic - only alpha differs between the two calls, by
                % L_C - but the two outputs are each about 6.4e6 m and differ
                % by 0.095 m, so the subtraction discards 7.8 significant
                % digits. One ulp at 4.5e6 m is 9.3e-10 m against a smallest
                % difference component of 0.0124 m, putting a floor of 7.5e-8
                % on the relative error; measured 1.5e-8. The bound is a
                % decade above the floor and bounds ROUNDOFF OF THE
                % SUBTRACTION, not any property of the transformation.
                testCase.verifyEqual(withoutScale - withScale, ...
                    constants.lc*station, 'RelTol', 1e-6, ...
                    'The two Scale settings must differ by exactly L_C times r.');

                % And it is 9.5 cm, which is why the option has no default.
                testCase.verifyGreaterThan(norm(withoutScale - withScale), 0.09);
                testCase.verifyLessThan(norm(withoutScale - withScale), 0.10);

                % Eq. (11.18) rebuilt term by term from independently obtained
                % quantities: the Earth's velocity and the solar and lunar
                % distances come from the ephemeris functions, not from info.
                [~, earthVelocity] = ...
                    referenceSystem.barycentricBodyState("earth", epoch);
                sunFromEarth = referenceSystem.geocentricBodyState("sun", epoch);
                moonFromEarth = referenceSystem.geocentricBodyState("moon", epoch);
                potential = constants.gmSun/norm(sunFromEarth) + ...
                    constants.gmMoon/norm(moonFromEarth);
                cSquared = constants.speedOfLight^2;
                % IERS Eq. (11.18) PLUS the two acceleration terms Resolution
                % B1.3 carries and IERS drops - 3 micrometres here, but the
                % function implements the resolution, so the oracle must
                % implement the same thing or it tests the wrong formula.
                acceleration = ...
                    constants.gmSun*sunFromEarth/norm(sunFromEarth)^3 + ...
                    constants.gmMoon*moonFromEarth/norm(moonFromEarth)^3;
                expected = station*(1 - potential/cSquared) - ...
                    0.5*(earthVelocity'*station/cSquared)*earthVelocity - ...
                    (station*(acceleration'*station) - ...
                    0.5*acceleration*(station'*station))/cSquared;

                testCase.verifyEqual(withoutScale, expected, 'AbsTol', 1e-9, ...
                    'Eq. (11.18) rebuilt term by term must reproduce the call.');
            end

            function gcrsToBcrs_reference_termSizesAreWhatTheHelpClaims(testCase)
                % THE HELP TEXT QUOTES THREE NUMBERS AND THIS ASSERTS THEM. An
                % ACCURACY block whose figures nothing checks is the failure O16
                % exists for, and these three are the numbers a reader uses to
                % decide whether the function matters to them at all.
                testCase.requireGateway();
                epoch = referenceSystem.daySecondToEpoch([60000 43200], "TT");
                station = [4517590; 837897; 4442892];

                rBcrs = referenceSystem.gcrsToBcrs(station, [], epoch, ...
                    Scale = "tdbCompatible");
                totalShift = norm(rBcrs) - norm(station);

                % Measured -0.1715 m; the band allows the annual variation in the
                % solar distance and in the direction of the Earth's velocity.
                testCase.verifyGreaterThan(abs(totalShift), 0.16);
                testCase.verifyLessThan(abs(totalShift), 0.19);
                testCase.verifyLessThan(totalShift, 0, ...
                    'The BCRS vector must be SHORTER: 1 - U/c^2 - L_C is below 1.');
            end

            function bcrsToGcrs_reference_theProviderBarelyMatters(testCase)
                % A COUNTER-INTUITIVE CLAIM IN THE HELP, ASSERTED RATHER THAN
                % STATED. U and V reach the result only through 1/c^2 terms, so
                % their errors are suppressed by 1e-8 and the bundled provider is
                % adequate although it is hopeless for an absolute position. The
                % check perturbs the Earth's velocity by the provider's OWN quoted
                % error and requires the result to move by far less than 1 mm.
                testCase.requireGateway();
                epoch = referenceSystem.daySecondToEpoch([60000 43200], "TT");
                constants = referenceSystem.iersConstants();
                station = [4517590; 837897; 4442892];

                [~, earthVelocity] = ...
                    referenceSystem.barycentricBodyState("earth", epoch);
                velocityError = referenceSystem.ephemerisBodies();
                velocityError = velocityError.VelocityError( ...
                    velocityError.Body == "earth");

                cSquared = constants.speedOfLight^2;
                perturbed = earthVelocity + velocityError/sqrt(3);
                lorentz = @(v) -0.5*(v'*station/cSquared)*v;
                shift = norm(lorentz(perturbed) - lorentz(earthVelocity));

                testCase.verifyLessThan(shift, 1e-6, ...
                    sprintf(['The provider''s own velocity error moves the ', ...
                    'result by %.2e m; the help claims far inside 1 mm.'], shift));
            end

    end

    methods (Test, TestTags = {'precision'})

        function gcrsToBcrs_precision_velocityRoundTripClosesWithThePosition(testCase)
            % The velocity plumbing, separately from the physics. The inverse
            % iterates rather than inverting in closed form - the acceleration
            % terms of Resolution B1.3 are quadratic in r, so Sherman-Morrison
            % no longer applies - and two iterations must bring both position
            % AND velocity back to roundoff.
            testCase.requireGateway();
            epoch = testCase.sampleEpoch(3);
            station = [4517590; 837897; 4442892];
            velocity = [-61.1; 329.4; 0.0];          % Earth rotation at that point

            [rBcrs, vBcrs] = referenceSystem.gcrsToBcrs(station, velocity, ...
                epoch, Scale = "tdbCompatible");
            [rBack, vBack] = referenceSystem.bcrsToGcrs(rBcrs, vBcrs, ...
                epoch, Scale = "tdbCompatible");

            % AbsTol 1e-7 m and 1e-10 m/s: roundoff of two iterations at the
            % 6.4e6 m and 3.4e2 m/s scales, not a bound chosen to pass.
            testCase.verifyEqual(rBack, repmat(station, 1, 3), 'AbsTol', 1e-7);
            testCase.verifyEqual(vBack, repmat(velocity, 1, 3), 'AbsTol', 1e-10);
        end

            function geocentricBodyState_precision_originIsExactlyTheDifference(testCase)
                % The geocentric origin must be the barycentric difference and not
                % a second evaluation of anything. The tolerance is the roundoff of
                % an addition and subtraction at the 1e11 m scale - 1e11 * 2.2e-16
                % is 2.2e-5 m - and is NOT a tolerance chosen to make the test pass.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(4);

                [bodyBary, bodyBaryVelocity] = ...
                    referenceSystem.barycentricBodyState("mars", epoch);
                [earthBary, earthBaryVelocity] = ...
                    referenceSystem.barycentricBodyState("earth", epoch);
                [geocentric, geocentricVelocity] = ...
                    referenceSystem.geocentricBodyState("mars", epoch);

                testCase.verifyEqual(geocentric, bodyBary - earthBary, ...
                    'AbsTol', 1e-4);
                testCase.verifyEqual(geocentricVelocity, ...
                    bodyBaryVelocity - earthBaryVelocity, 'AbsTol', 1e-9);
            end

            function barycentricBodyState_precision_heliocentricEarthClosure(testCase)
                % The Sun is built as pvb - pvh, so the Earth's barycentric vector
                % minus the Sun's must return pvh - the heliocentric Earth - whose
                % length is between 0.983 and 1.017 au by Kepler and not by this
                % toolbox. It closes the composition without trusting either half.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(1);
                au = 1.49597870700e11;

                earthPosition = referenceSystem.barycentricBodyState("earth", epoch);
                sunPosition = referenceSystem.barycentricBodyState("sun", epoch);
                distance = norm(earthPosition - sunPosition)/au;

                testCase.verifyGreaterThan(distance, 0.980);
                testCase.verifyLessThan(distance, 1.020);
            end

            function convertTimeScale_precision_geocentreIsTheDefaultExactly(testCase)
                % Observer at the origin must reproduce the default BIT FOR BIT,
                % not merely closely: with the distance from the axis and from the
                % equator both zero the topocentric contribution of iauDtdb
                % vanishes identically, so any difference at all would mean the
                % observer path is evaluating a different series. AbsTol 0 is
                % legitimate here because no arithmetic separates the two.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(6);

                byDefault = referenceSystem.convertTimeScale(epoch, "TDB");
                atOrigin = referenceSystem.convertTimeScale(epoch, "TDB", ...
                    Observer = [0; 0; 0]);

                testCase.verifyEqual(atOrigin.day, byDefault.day, 'AbsTol', 0);
                testCase.verifyEqual(atOrigin.sec, byDefault.sec, 'AbsTol', 0);
            end

            function convertTimeScale_precision_tdbRoundTripSurvivesTheObserver(testCase)
                % TDB to TT and back must be the identity to the resolution of the
                % epoch with the observer terms in play, which is what says the
                % inverse arm passes the SAME observer and not an empty one.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(4);
                observer = [4517590; 837897; 4442892];   % a mid-latitude station

                tdb = referenceSystem.convertTimeScale(epoch, "TDB", ...
                    Observer = observer);
                back = referenceSystem.convertTimeScale(tdb, "TT", ...
                    Observer = observer);

                testCase.verifyEqual(back.day, epoch.day, 'AbsTol', 0);
                testCase.verifyEqual(back.sec, epoch.sec, 'AbsTol', 1e-9);
            end

            function bcrsToGcrs_precision_roundTripIsExactNotApproximate(testCase)
                % Sherman-Morrison inverts the operator in closed form, so the
                % round trip must close at ROUNDOFF for a 6.4e6 m vector - about
                % 1e-9 m - and not at the 2e-16 relative level a negated-parameter
                % inverse would leave. The tolerance is the arithmetic, not a
                % threshold chosen to pass.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(4);
                station = [4517590; 837897; 4442892];

                for scale = ["none", "tdbCompatible"]
                    forward = referenceSystem.gcrsToBcrs(station, [], epoch, ...
                        Scale = scale);
                    back = referenceSystem.bcrsToGcrs(forward, [], epoch, Scale = scale);
                    testCase.verifyEqual(back, repmat(station, 1, 4), ...
                        'AbsTol', 1e-7, ...
                        sprintf('Round trip failed for Scale "%s".', scale));
                end
            end

            function gcrsToBcrs_precision_departsFromLinearityByTheQuadratic(testCase)
                % THIS TEST ASSERTED LINEARITY AND WAS RIGHT TO FAIL. Until
                % rev. 1.147 the transformation was IERS Eq. (11.18), exactly
                % linear in r. Resolution B1.3 adds r(a_E.r) and -(1/2)a_E r^2,
                % both QUADRATIC, so linearity is now false by construction, and
                % asserting a property the code deliberately gave up is worse than
                % not testing it.
                %
                % The replacement is stronger than a loosened tolerance: the
                % DEPARTURE from linearity must equal the quadratic terms,
                % rebuilt here from the same two bodies but not taken from the
                % function.
                testCase.requireGateway();
                epoch = referenceSystem.daySecondToEpoch([60000 43200], "TT");
                constants = referenceSystem.iersConstants();
                station = [4517590; 837897; 4442892];
                factor = 3;

                transform = @(r) referenceSystem.gcrsToBcrs(r, [], epoch, ...
                    Scale = "tdbCompatible");
                departure = transform(factor*station) - factor*transform(station);

                sunFromEarth = referenceSystem.geocentricBodyState("sun", epoch);
                moonFromEarth = referenceSystem.geocentricBodyState("moon", epoch);
                acceleration = ...
                    constants.gmSun*sunFromEarth/norm(sunFromEarth)^3 + ...
                    constants.gmMoon*moonFromEarth/norm(moonFromEarth)^3;
                quadratic = @(r) (r*(acceleration.'*r) - ...
                    0.5*acceleration*(r.'*r))/constants.speedOfLight^2;
                % NEGATED, BECAUSE gcrsToBcrs IS THE INVERSE. With
                % f(r) = r + L(r) + Q(r) the inverse is g(X) = X - L(X) - Q(X)
                % to this order, so its departure from linearity is MINUS the
                % forward's: g(3s) - 3g(s) = -[Q(3s) - 3Q(s)] = -6Q(s). The
                % first version asserted +6Q(s) and was wrong by exactly -1.
                expected = -(quadratic(factor*station) - ...
                    factor*quadratic(station));

                % AbsTol 1e-8 m, AND 1e-9 WAS TRIED FIRST AND LEAVES 1.164e-9.
                % The departure is a difference of two vectors of order 3e7 m
                % whose linear parts cancel exactly in real arithmetic but not
                % in binary: one ulp at 3e7 m is 6.6e-9, so the subtraction
                % alone floors the residual near 1e-9. The bound is a decade
                % above the measured value and bounds CANCELLATION, not the
                % transformation - the same trap as the L_C difference test.
                testCase.verifyEqual(departure, expected, 'AbsTol', 1e-8, ...
                    'The departure from linearity must be the B1.3 quadratic terms.');
                testCase.verifyGreaterThan(norm(expected), 1e-6, ...
                        'If the quadratic terms vanished this test would prove nothing.');
            end

    end

    methods (Static, Access = private)

        function id = naifIdOfName(bodyName)
            %NAIFIDOFNAME The NAIF identifier behind a body name, or NaN.
            %   The synthetic "naif<id>" form readEphemeris gives a body the
            %   bundled registry does not name is decoded here, so a fixture
            %   row can be classified without a second table of ids.
            if startsWith(bodyName, "naif")
                id = str2double(extractAfter(bodyName, "naif"));
                return
            end
            known = referenceSystem.ephemerisBodies();
            match = known.Body == bodyName;
            if any(match)
                id = known.NaifId(find(match, 1));
            else
                id = NaN;
            end
        end

    end

    methods (Test, TestTags = {'speed'})

        function barycentricBodyState_speed_theWholeEphemerisLayer(testCase)
            % OPEN ITEM B1. NONE OF THE SEVEN FUNCTIONS DELIVERED IN PART H
            % HAD A BENCHMARK, and the register put that beside P20's
            % unmeasured "the marginal cost is small" for a reason: the same
            % shape of claim about P19 was wrong by a factor of thirty. This
            % covers the four L5e entries in one method, because they are
            % called together and timing them apart would measure the setup
            % four times.
            %
            % THE PROVIDER IS "sofa", DELIBERATELY. It is the bundled path,
            % needs no kernel and is therefore the one every user meets; the
            % MICE path is dominated by cspice_spkezr, which is not this
            % toolbox's code and whose timing would say nothing about it.
            testCase.requireGateway();
            epoch = testCase.sampleEpoch(500);
            station = repmat([4517590; 837897; 4442892], 1, 500);

            referenceSystem.barycentricBodyState("earth", epoch);
            referenceSystem.geocentricBodyState("sun", epoch);
            referenceSystem.gcrsToBcrs(station, [], epoch, Scale = "none");

            barycentricTime = zeros(5, 1);
            geocentricTime = zeros(5, 1);
            forwardTime = zeros(5, 1);
            inverseTime = zeros(5, 1);
            for k = 1:5
                start = tic;
                referenceSystem.barycentricBodyState("earth", epoch);
                barycentricTime(k) = toc(start);
                start = tic;
                referenceSystem.geocentricBodyState("sun", epoch);
                geocentricTime(k) = toc(start);
                start = tic;
                barycentric = referenceSystem.gcrsToBcrs(station, [], epoch, ...
                    Scale = "none");
                forwardTime(k) = toc(start);
                start = tic;
                referenceSystem.bcrsToGcrs(barycentric, [], epoch, ...
                    Scale = "none");
                inverseTime(k) = toc(start);
            end

            % FOUR ROWS, NOT ONE AGGREGATE. geocentricBodyState is two
            % barycentric calls differenced, so it must come out near twice
            % the first row; gcrsToBcrs calls the ephemeris twice more for U
            % and V. A single total would hide both relations, and the
            % relations are the only part of this a later reader can check.
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "barycentricBodyState (sofa,N=500)", 500, ...
                median(barycentricTime), 0.05, min(barycentricTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "geocentricBodyState (sofa,N=500)", 500, ...
                median(geocentricTime), 0.10, min(geocentricTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "gcrsToBcrs (N=500)", 500, median(forwardTime), 0.20, ...
                min(forwardTime)));
            testCase.log(1, TestPerformance.verifiedBenchmark(testCase, ...
                "bcrsToGcrs (N=500)", 500, median(inverseTime), 0.20, ...
                min(inverseTime)));

            % THE INVERSE IS SHERMAN-MORRISON ON A RANK-ONE UPDATE AND MUST
            % NOT COST MORE THAN THE FORWARD MAP BY MUCH. D97 chose the closed
            % form over forming and factorising the matrix; if the ratio is
            % large that choice bought nothing and the help says it did.
            ratio = min(inverseTime)/min(forwardTime);
            testCase.verifyLessThan(ratio, 3, sprintf( ...
                ['The BCRS inverse costs %.2fx the forward map. The closed ', ...
                'form was adopted because it is the same arithmetic; well ', ...
                'above one means it is not.'], ratio));
        end

    end

    methods (Test, TestTags = {'vectorization'})

            function barycentricBodyState_vectorization_arcMatchesSingleEpochs(testCase)
                % An arc must be bit-identical to the same epochs one at a time.
                % The C loop carries no cross-epoch state, so anything else would
                % mean a blocking or indexing error in the 6xN layout.
                testCase.requireGateway();
                epoch = testCase.sampleEpoch(7);

                [arcPosition, arcVelocity] = ...
                    referenceSystem.barycentricBodyState("jupiter", epoch);

                for k = 1:numel(epoch.day)
                    single = referenceSystem.daySecondToEpoch( ...
                        [epoch.day(k) epoch.sec(k)], "TT");
                    [onePosition, oneVelocity] = ...
                        referenceSystem.barycentricBodyState("jupiter", single);
                    testCase.verifyEqual(arcPosition(:, k), onePosition, ...
                        'AbsTol', 0, sprintf('Position differs at epoch %d.', k));
                    testCase.verifyEqual(arcVelocity(:, k), oneVelocity, ...
                        'AbsTol', 0, sprintf('Velocity differs at epoch %d.', k));
                end
            end

    end

    methods (Test, TestTags = {'diagnostics'})

        function readEphemeris_diagnostics_reportsWhatTheCommentAreaNamed(testCase)
            % THE INSTRUMENT RUN 68 SHOULD HAVE HAD. The pairing check turned
            % out to be inert on the shipped kernel and NOTHING IN THE REPORT
            % SAID WHICH GENERATION HAD BEEN READ, so the failure could say
            % that the refusal did not happen and not why. This logs the two
            % facts that settle it - what was parsed, and whether it was
            % parsed at all - so the next run explains itself instead of
            % needing a separate command at the prompt (open item D1, in the
            % shape it takes for a value that is not a tolerance).
            %
            % It asserts nothing about WHICH generation. That is a property of
            % whichever kernel is installed, not of this toolbox, and a test
            % that pinned it would fail the day somebody furnished de440.bsp
            % instead of de440s.bsp - correctly furnishing a better kernel.
            testCase.assumeTrue(exist('cspice_spkezr', 'file') == 2 || ...
                exist('cspice_spkezr', 'file') == 3, ...
                'MICE is not on the path; the kernel-backed tier is skipped.');
            kernel = fullfile(referenceSystem.dataFolder(), 'de440s.bsp');
            testCase.assumeTrue(isfile(kernel), ...
                "de440s.bsp is not in " + referenceSystem.dataFolder() + ...
                "; run setupReferenceSystem(Fetch = ""kernels"").");

            ephemeris = referenceSystem.readEphemeris(string(kernel));

            % THE COMMENT AREA IS READ HERE, DIRECTLY, AND NOT THROUGH THE
            % FUNCTION UNDER DIAGNOSIS. Run 69 established that no generation
            % is parsed from this kernel; it could not say whether the comment
            % area is EMPTY or merely worded in a way the DE-?\d{3} pattern
            % misses, and those have different repairs - one closes B5 as a
            % property of the file, the other is a defect in the pattern.
            % Asking readEphemeris again would return the same silence.
            handle = cspice_dafopr(char(kernel));
            closeHandle = onCleanup(@() cspice_dafcls(handle));
            comment = strings(0, 1);
            done = false;
            while ~done
                % string(chunk), ONE STRING PER ROW OF THE CHAR MATRIX.
                % Rev. 1.167 wrote string(chunk(:)) here because it copied
                % the loop out of readEphemeris - INCLUDING ITS DEFECT - so
                % the "independent" read reproduced the library's column-major
                % flatten and the two agreed perfectly about nothing.
                % Obligation O23 in its purest form: a reference reconstructed
                % by the same route as the code under test is not a reference.
                [chunk, done] = cspice_dafec(handle, 100, 1000);
                comment = [comment; string(chunk)];         %#ok<AGROW>
            end
            clear closeHandle
            comment = strip(erase(comment, char(0)));
            comment = comment(strlength(comment) > 0);

            hasGeneration = ~isempty(regexp(join(comment, " "), ...
                'DE-?\d{3}', 'once'));
            if isempty(comment)
                firstLine = "(comment area is empty)";
            else
                firstLine = extractBefore(pad(comment(1), 61), 61);
            end

            testCase.log(1, TestPerformance.noteRecord( ...
                "readEphemeris comment area", ...
                sprintf('%d lines, DE token %d, meta "%s", verified %d', ...
                    numel(comment), hasGeneration, ...
                    ephemeris.meta.ephemeris, ...
                    ephemeris.meta.generationVerified), ...
                "first line: " + firstLine));

            % THE ONE ASSERTION IS THE ONE THAT CANNOT BE WRONG ABOUT A
            % KERNEL NOBODY CHOSE. Whether this file names a generation is a
            % property of whichever kernel is installed; what must hold is
            % that the flag agrees with the parse.
            testCase.verifyEqual(ephemeris.meta.generationVerified, ...
                hasGeneration, ['generationVerified disagrees with what the ', ...
                'comment area actually contains, which means the flag is ', ...
                'not reporting the parse it claims to report.']);

            % AND THE STRUCTURAL CHECK THAT WOULD HAVE CAUGHT REV. 1.167's
            % SHARED DEFECT, WHICH THE AGREEMENT ABOVE COULD NOT. Both sides
            % flattened the char matrix column-major, so both saw 43077
            % one-character "lines" and agreed that no DE token was present.
            % A comment area of single characters is not a comment area; the
            % median line is a sentence fragment, and one character is the
            % signature of exactly this mistake.
            if ~isempty(comment)
                testCase.verifyGreaterThan(median(strlength(comment)), 1, ...
                    sprintf(['The comment area parsed into %d "lines" with ', ...
                    'a median length of %g. Single-character lines mean the ', ...
                    'char matrix was flattened column-major instead of ', ...
                    'converted one string per row.'], numel(comment), ...
                    median(strlength(comment))));
            end
        end


            function barycentricBodyState_diagnostics_outOfRangeWarnsAggregated(testCase)
                % iauEpv00 reports epochs outside 1900-2100. A hundred of them are
                % ONE fact about the call, and a hundred identical warnings are how
                % a real one gets lost.
                %
                % THE OBVIOUS ASSERTION - count the warnings - CANNOT BE WRITTEN.
                % MATLAB exposes no warning callback and no counter, which
                % WarningRecordingPlugin records as a limitation it could not
                % design away; lastwarn holds only the last one, so a helper
                % returning "1" would report a number it does not have. That is the
                % false-instrument failure this project keeps paying for, so it is
                % not written.
                %
                % What CAN be asserted is the wording, and it is sufficient: a
                % message reading "100 of 100" is unreachable from a per-epoch
                % loop, which has no access to the total. The aggregation is
                % therefore checked through the only evidence that distinguishes it.
                testCase.requireGateway();
                cleanup = onCleanup(@() lastwarn('', ''));           %#ok<NASGU>
                day = (-58000:-57901).';            % about the year 1700
                epoch = referenceSystem.daySecondToEpoch( ...
                    [day repmat(43200, numel(day), 1)], "TT");

                testCase.verifyWarning( ...
                    @() referenceSystem.barycentricBodyState("earth", epoch), ...
                    'referenceSystem:barycentricBodyState:outsideModelRange');

                [message, identifier] = lastwarn();
                testCase.verifyEqual(identifier, ...
                    'referenceSystem:barycentricBodyState:outsideModelRange');
                testCase.verifySubstring(message, '100 of 100 epochs', ...
                    ['The warning must report the aggregate, which is what says ', ...
                    'it was raised once for the call rather than once per epoch.']);
            end

            function ephemerisBodies_diagnostics_accuracyTableIsOrdered(testCase)
                % A DIAGNOSTIC ABOUT THE DOCUMENT, NOT THE CODE. The whole reason
                % this table exists is that the SOFA provider must not look
                % adequate, so the Moon's error must be visibly above the 1e-10
                % m/s2 accelerometer floor when propagated as 3*(dr/r)*a. If a
                % future edit improved the tabulated lunar figure by an order of
                % magnitude without changing the model, this fires.
                bodies = referenceSystem.ephemerisBodies();
                moonError = bodies.PositionError(bodies.Body == "moon");

                lunarDistance = 3.844e8;
                lunarDifferentialAcceleration = 1.19e-6;
                accelerationError = 3*(moonError/lunarDistance)* ...
                    lunarDifferentialAcceleration;

                testCase.verifyGreaterThan(accelerationError, 5e-11, ...
                    ['The tabulated lunar error implies an acceleration error ', ...
                    'below the accelerometer noise floor, which would make the ', ...
                    'SOFA provider look adequate for POD. It is not.']);
            end

    end

end
