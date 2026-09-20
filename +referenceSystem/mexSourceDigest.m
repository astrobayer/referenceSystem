function digest = mexSourceDigest(toolboxRoot)
%MEXSOURCEDIGEST Content digest of every C source the gateway is built from.
%   digest = mexSourceDigest(toolboxRoot) returns a number that changes when
%   any byte of any file under mex/ changes, and when a file is added or
%   removed. It is what setupReferenceSystem uses to decide whether the
%   compiled gateway is stale.
%
%   WHY NOT TIMESTAMPS
%   ------------------
%   Because they do not survive the way this toolbox is delivered. A ZIP entry
%   stores naive local time with no time zone, so an archive built on a UTC
%   machine and unpacked on a UTC+2 one produces sources that appear two hours
%   OLDER than they are: a changed C source can arrive stamped earlier than
%   the gateway built from the old one, and a timestamp check then reports the
%   binary current.
%
%   A content digest has no such failure mode. It is immune to the time zone,
%   to clock skew between machines, to a git checkout that writes every file
%   with the checkout time, and to an archive unpacked in any order.
%
% INPUT ARGUMENTS
%   Name          Size   Type     Units  Description
%   ----          ----   ----     -----  -----------
%   toolboxRoot   1x1    string   -      Distribution folder holding mex/.
%
% OUTPUT ARGUMENTS
%   Name     Size   Type     Units  Description
%   ----     ----   ----     -----  -----------
%   digest   1x1    double   -      Non-negative integer below 2^31. Equal
%                                   digests mean the sources are unchanged;
%                                   different digests mean they are not.
%
% METHOD
%   Every .c and .h under mex/, at the top level and in every subfolder, sorted
%   by path so the result cannot depend on the order the file system lists
%   them. Each file contributes a position-weighted sum of its bytes together
%   with its length and its name, and the file digests are folded together in
%   sorted order.
%
%   THE TOP LEVEL IS GLOBBED SEPARATELY FROM THE RECURSIVE PATTERN. Whether
%   MATLAB's ** spans zero folder levels is not something to rely on from
%   memory, and the answer decides whether mexGateway.c, rsCore.c, rsCheb.c and
%   rsApi.c are seen at all - they are the only files here that ever change,
%   since sofa/ and iers/ are vendored and frozen. The union is correct under
%   either reading.
%
% ACCURACY
%   Not a cryptographic hash and not intended as one. It answers "did these
%   files change", not "did an adversary change them". A weighted sum detects
%   any single-byte edit; two simultaneous edits that exactly cancel are
%   possible in principle and are not a failure mode a build check needs to
%   defend against.
%
% ERRORS
%   referenceSystem:mexSourceDigest:noSources
%
% REFERENCES
%   Handover section C.4 (MEX rules) and C.10 (installation).
%
% EXAMPLE
%   digest = referenceSystem.mexSourceDigest(pwd);
%
% KEYWORDS
%   build, staleness, digest, checksum, MEX
%
% See also buildMex, setupReferenceSystem, mexInfo
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-27 18:30 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        toolboxRoot (1,1) string
    end

    mexFolder = fullfile(toolboxRoot, 'mex');
    entry = [dir(fullfile(mexFolder, '*.c')); dir(fullfile(mexFolder, '*.h')); ...
        dir(fullfile(mexFolder, '**', '*.c')); dir(fullfile(mexFolder, '**', '*.h'))];
    if isempty(entry)
        error('referenceSystem:mexSourceDigest:noSources', ...
            'No C sources under %s.', mexFolder);
    end

    % Sorted and de-duplicated, because the two globs overlap wherever ** does
    % span zero levels, and because dir order is not a contract.
    sourcePath = unique(string(fullfile({entry.folder}', {entry.name}')));

    digest = 0;
    for k = 1:numel(sourcePath)
        fileId = fopen(sourcePath(k), 'r');
        if fileId < 0
            continue
        end
        byte = fread(fileId, inf, '*uint8');
        fclose(fileId);

        % Position weighting so that a transposition is not invisible. The
        % weight is kept under 65521 and the byte under 256, so the largest
        % term is about 1.7e7 and a ten-megabyte file still sums well inside
        % the 2^53 a double represents exactly.
        position = mod((1:numel(byte))', 65521);
        fileDigest = mod(sum(double(byte) .* position), 2147483647);

        [~, name, extension] = fileparts(sourcePath(k));
        nameDigest = mod(sum(double(char(name + extension))), 2147483647);

        digest = mod(digest * 31 + fileDigest + numel(byte) + nameDigest, ...
            2147483647);
    end
end
