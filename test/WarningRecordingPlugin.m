classdef WarningRecordingPlugin < matlab.unittest.plugins.TestRunnerPlugin
%WARNINGRECORDINGPLUGIN Record which tests raise MATLAB warnings.
%
%   A warning raised inside a test does not appear in a TestResult and does not
%   appear in the report. It goes to the console, where it is seen only if
%   somebody is watching the run and reads it. In session S4 exactly that
%   happened: a test raised a genuine gimbal-lock warning for four consecutive
%   runs and the suite reported nothing, because the suite had no way to know.
%   It was found by the user reading the console.
%
%   The cost of routine console noise is not the noise, it is what the noise
%   hides. A suite that always prints something is one in which a new warning
%   goes unread, so the useful question is not "were there warnings" but "which
%   test raised one, and is it meant to".
%
% METHOD
%   The plugin overrides runTestMethod, clears lastwarn before the method runs
%   and reads it afterwards, attributing whatever it finds to pluginData.Name.
%   The previous lastwarn state is restored, so the plugin cannot be detected by
%   the tests it observes.
%
%   ONE LIMITATION, STATED PLAINLY BECAUSE IT CANNOT BE DESIGNED AWAY: lastwarn
%   holds the LAST warning, so a test raising three warnings is recorded once,
%   with the third. MATLAB exposes no warning callback and no warning counter,
%   so there is no supported way to capture all of them; evalc around each
%   method would capture the text but would also swallow the framework's own
%   output and change what the tests see. The recorded count is therefore the
%   number of TESTS THAT WARNED, never the number of warnings, and the report
%   says so in those words rather than implying a total it does not have.
%
%   A warning with an empty identifier is still recorded, because warning()
%   called without one is a legitimate and common form and the message is what
%   a reader needs.
%
%   SUPPRESSING A WARNING DOES NOT HIDE IT FROM lastwarn, and the first run of
%   this plugin is what established that. Its own help previously claimed the
%   opposite - that a test suppressing a warning with warning('off', ...) would
%   correctly not appear here - and the run returned six warnings of which every
%   single one was deliberate: four asserted through verifyWarning, two
%   suppressed with warning('off', ...). Both forms set lastwarn. The claim was
%   a MATLAB semantic asserted rather than measured, in the help of the very
%   instrument built to measure things, one revision after obligation O16 was
%   written down.
%
%   THE RULE THAT REPLACES IT: A TEST THAT ASSERTS A WARNING CONSUMES IT, by
%   registering onCleanup(@() lastwarn('', '')). The report then lists the
%   warnings nobody claimed, which is the only list worth reading. This needs no
%   allow-list of expected identifiers, no heuristic on test names and no
%   guessing about warning state - all of which were considered and all of which
%   would have needed maintaining. A cleanup rather than a trailing statement,
%   so it fires on pass, on failure and on a filtered assumption alike.
%
%   A section that lists six expected warnings is worse than no section: it
%   trains the reader to skip it, which is the failure O17 exists to prevent.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-26 18:10 (CEST, UTC+02:00) - session S4, warning visibility
% -------------------------------------------------------------------------

    properties (SetAccess = private)
        % Name, identifier and message of every test that raised a warning.
        WarningRecord = struct('name', {}, 'identifier', {}, 'message', {})
    end

    methods (Access = protected)

        function runTestMethod(plugin, pluginData)
            [previousMessage, previousIdentifier] = lastwarn();
            lastwarn('', '');

            runTestMethod@matlab.unittest.plugins.TestRunnerPlugin( ...
                plugin, pluginData);

            [message, identifier] = lastwarn();
            if strlength(string(message)) > 0
                plugin.WarningRecord(end+1) = struct( ...
                    'name', string(pluginData.Name), ...
                    'identifier', string(identifier), ...
                    'message', string(message));
            end

            lastwarn(previousMessage, previousIdentifier);
        end

    end

end
