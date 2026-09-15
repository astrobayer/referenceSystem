function versionInfo = toolboxVersion()
%TOOLBOXVERSION Version, build date and provenance of the referenceSystem toolbox.
%
%   versionInfo = toolboxVersion() returns a scalar struct describing the
%   release of this toolbox, the external authorities it is built against and
%   the provenance tag that every help block in the toolbox carries. It is the
%   single source of that information: no other file states a version literal.
%
% INPUT ARGUMENTS
%   (none)
%
% OUTPUT ARGUMENTS
%   Name                     Size   Type     Units  Description
%   ----                     ----   ----     -----  -----------
%   versionInfo              1x1    struct   -      Fields listed below.
%   .version                 1x1    string   -      Semantic version, release plus
%                                                  patch, e.g. '2.1.204'.
%   .release                 1x1    string   -      Major and minor only, '2.1'.
%   .patch                   1x1    string   -      Patch component, e.g. '204'.
%                                                  This IS the handover
%                                                  revision number (D107).
%   .buildDate               1x1    string   -      Source revision date, ISO 8601.
%   .sofaRelease             1x1    string   -      Bundled IAU SOFA release, '20231011'.
%   .iersConventions         1x1    string   -      IERS Conventions edition, '2010'.
%   .author                  1x1    string   -      Author of the toolbox.
%   .generator               1x1    string   -      Model and date the sources were written.
%   .versionTag              1x1    string   -      Version line of the help template.
%   .helpTag                 1x1    string   -      Authorship line of the help template.
%
% METHOD
%   All values are compile-time constants of the source revision, not runtime
%   queries: buildDate is the date the sources were written, never the date the
%   function is called, so a report generated from an archived copy of the
%   toolbox states the release that produced it. version, author and generator
%   are the only literals; versionTag and helpTag are composed from them, so the
%   two tag lines in every help block have exactly one authority each and a
%   provenance test can verify the agreement.
%
%   THE PATCH COMPONENT IS THE HANDOVER REVISION NUMBER (decision D107).
%   Version 2.1.N is the state of the sources at handover revision 1.N, and the
%   two are edited together or not at all. Major and minor identify the
%   RELEASE; the patch identifies the DOCUMENT REVISION that produced these
%   sources, so an archived copy can be tied to the revision log entry that
%   explains it without guessing from dates. A test and auditPackage.py both
%   read the top row of the handover's revision log and refuse a disagreement,
%   because a convention nothing checks is a convention that drifts.
%
%   versionTag CARRIES MAJOR.MINOR ONLY, AND DELIBERATELY. It appears in the
%   help footer of every file in the toolbox; putting the patch there would
%   rewrite 233 lines on every revision and bury each session's real diff. The
%   footer states the release, versionInfo.version states the revision, and the
%   test report prints the latter so a run is always traceable to a document.
%
%   THE FOOTER IS TWO LINES AND NOT ONE (decision D103). Naming the author in
%   full alongside the toolbox, the version and the model exceeds the 100-column
%   limit of handover section C.1 by three characters, and a coding standard is
%   not amended to fit a credit line. The version and the authorship are
%   therefore separate assertions, which is also the more useful split: a
%   version bump and a change of authorship are different events.
%
%   The function is deliberately not called version: a package function of that
%   name would shadow the MATLAB builtin version for every other function inside
%   +referenceSystem, silently (handover section C.5 rule 3).
%
% ACCURACY
%   Not applicable. The function returns metadata; no numerical quantity is
%   computed and no approximation is made.
%
% ERRORS
%   (none)
%
% REFERENCES
%   IAU SOFA Software Collection, release 2023-10-11, IAU SOFA Board.
%   IERS Conventions (2010), IERS Technical Note 36, G. Petit and B. Luzum (eds.).
%
% EXAMPLE
%   v = referenceSystem.toolboxVersion();
%   fprintf('%s (SOFA %s)\n', v.version, v.sofaRelease);
%
% KEYWORDS
%   version, provenance, build, SOFA, IERS Conventions, metadata
%
% See also IERSCONSTANTS, ELLIPSOIDPARAMETERS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-24 11:05 (CEST, UTC+02:00)
% Revised: 2026-08-09 10:15 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

%#codegen

    majorMinorVersion = "2.1";
    % D107: THE PATCH IS THE HANDOVER REVISION. Bump this in the same edit that
    % writes the revision log entry; the two are checked against each other.
    patchVersion = "241";
    buildDate = "2026-09-15";
    toolboxAuthor = "Matthias Weigelt";
    generatorModel = "Claude Opus 5 (Anthropic)";
    toolboxName = "referenceSystem";

    % THE THREE COMPONENTS ARE EXPOSED SEPARATELY AS WELL AS COMPOSED, so no
    % consumer ever has to take a substring of version to recover one of them.
    % That habit cost the whole test report at rev. 1.164 and is what
    % obligation O30 is about; here the fields are cheap and the parse is not
    % needed at all.
    versionInfo = struct( ...
        'version', majorMinorVersion + "." + patchVersion, ...
        'release', majorMinorVersion, ...
        'patch', patchVersion, ...
        'buildDate', buildDate, ...
        'sofaRelease', "20231011", ...
        'iersConventions', "2010", ...
        'author', toolboxAuthor, ...
        'generator', generatorModel + ", " + buildDate, ...
        'versionTag', toolboxName + " v" + majorMinorVersion, ...
        'helpTag', "Developed by " + toolboxAuthor + ...
            " with the assistance of " + generatorModel);
end
