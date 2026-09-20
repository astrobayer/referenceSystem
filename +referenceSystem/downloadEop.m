function [file, info] = downloadEop(series, options)
%DOWNLOADEOP Fetch a current IERS Earth orientation series, with local caching.
%
%   file = downloadEop(series)
%   file = downloadEop(series, 'CacheDir', folder)
%   [file, info] = downloadEop(...)
%
%   Downloads one of the series readEop understands and returns the path of the
%   cached copy. This is the only function in the toolbox that touches the
%   network, it is never required, and no test may depend on it.
%
% INPUT ARGUMENTS
%   Name     Size   Type            Units  Description
%   ----     ----   ----            -----  -----------
%   series   1x1    string | char   -      "EOP 20 C04" (default source of
%                                          record), "EOP 14 C04",
%                                          "EOP 20 C04 dPsiDEpsilon" or
%                                          "finals2000A".
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name       Size  Type      Default        Description
%   ----       ----  ----      -------        -----------
%   CacheDir   1x1   string    data/ under    Folder the copy is written to.
%                              the toolbox    Created if absent.
%   MaxAge     1x1   duration  days(7)        Reuse an existing cached file
%                                             younger than this instead of
%                                             fetching. Set to days(0) to force.
%   Timeout    1x1   double    60             Seconds before the request fails.
%
% OUTPUT ARGUMENTS
%   Name          Size   Type       Units  Description
%   ----          ----   ----       -----  -----------
%   file          1x1    string     -      Path of the cached series.
%   info          1x1    struct     -      What happened. Fields below.
%   .series       1x1    string     -      Series requested.
%   .url          1x1    string     -      Source, or "" when the cache served.
%   .fromCache    1x1    logical    -      True where nothing was fetched.
%   .fileAge      1x1    duration   -      Age of the returned file.
%   .bytes        1x1    double     -      Size of the returned file.
%   .duration     1x1    double     s      Wall-clock time of the call.
%
% METHOD
%   The toolbox must work on a machine with no network, so this function is
%   strictly optional: nothing else calls it, no test requires it, and a user
%   who supplies their own file never needs it. That constraint is why the
%   download is a separate function rather than a fallback inside readEop, where
%   it would make an offline session fail at an unpredictable moment.
%
%   Caching is by file age rather than by content hash. The IERS updates these
%   series daily, so an age test answers the question a user actually has (is
%   this recent enough) at no cost, whereas a hash would require the download it
%   is meant to avoid.
%
%   The fetch is atomic in the sense that matters: the download goes to a
%   temporary name in the cache folder and is moved into place only on success,
%   so an interrupted transfer cannot leave a truncated series where a complete
%   one was. A truncated EOP file is the worst possible failure here, because it
%   parses, it validates, and it silently shortens the usable epoch range.
%
%   The downloaded file is NOT parsed or validated here. Pass it to readEop,
%   which owns format identification and validation; doing it in two places
%   would be two sources of truth about what a valid series is.
%
% ACCURACY
%   Not applicable: this function transfers bytes and computes nothing. The
%   accuracy of the result is that of the series, which readEop records in
%   eop.meta.
%
%   One operational caveat that is an accuracy matter in disguise: the predicted
%   part of finals2000A degrades with lead time, reaching tens of milliarcseconds
%   in polar motion and milliseconds in UT1 a year ahead. Prefer a C04 series for
%   anything reprocessed, and check eop.meta.series before quoting an accuracy.
%
% ERRORS
%   referenceSystem:downloadEop:downloadFailed
%   referenceSystem:downloadEop:cacheNotWritable
%
% REFERENCES
%   IERS EOP Product Centre, https://hpiers.obspm.fr/eoppc/eop/
%   IERS Rapid Service / Prediction Centre, https://maia.usno.navy.mil/
%
% EXAMPLE
%   file = referenceSystem.downloadEop("EOP 20 C04");
%   eop = referenceSystem.readEop(file);
%
% KEYWORDS
%   EOP, download, cache, C04, finals2000A, IERS
%
% See also READEOP, INTERPOLATEEOP.
%
% -------------------------------------------------------------------------
% referenceSystem v2.2
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-25 12:45 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        series (1,1) string {mustBeMember(series, ["EOP 14 C04", ...
            "EOP 20 C04", "EOP 20 C04 dPsiDEpsilon", "finals2000A"])} = "EOP 20 C04"
        options.CacheDir (1,1) string = localDefaultCache()
        options.MaxAge (1,1) duration = days(7)
        options.Timeout (1,1) double {mustBePositive} = 60
    end

    startTime = tic;
    source = localSourceRegistry();
    % String-array comparison, not strcmp on a cell of string scalars; see the
    % note in readEop/localLookup for why that silently matches nothing.
    entry = source([source.series] == series);
    file = fullfile(options.CacheDir, entry.localName);

    if ~isfolder(options.CacheDir)
        [made, message] = mkdir(options.CacheDir);
        if ~made
            error('referenceSystem:downloadEop:cacheNotWritable', ...
                'Could not create the cache folder "%s": %s', ...
                options.CacheDir, message);
        end
    end

    [useCache, age] = localCacheIsFresh(file, options.MaxAge);
    if useCache
        info = localInfo(series, "", true, age, file, startTime);
        return
    end

    temporaryFile = file + ".part";
    try
        requestOptions = weboptions('Timeout', options.Timeout, ...
            'ContentType', 'text');
        websave(temporaryFile, entry.url, requestOptions);
        movefile(temporaryFile, file, 'f');
    catch cause
        if isfile(temporaryFile)
            delete(temporaryFile);
        end
        error('referenceSystem:downloadEop:downloadFailed', ...
            ['Could not download the %s series from %s: %s\n', ...
            'This function is optional; nothing else in the toolbox needs ', ...
            'the network. Fetch the file by hand and pass it to readEop.'], ...
            series, entry.url, cause.message);
    end

    [~, age] = localCacheIsFresh(file, options.MaxAge);
    info = localInfo(series, entry.url, false, age, file, startTime);
end

% =========================== local functions ===========================

function source = localSourceRegistry()
%LOCALSOURCEREGISTRY Where each series comes from and what it is called locally.
%   Separate from the format registry in readEop on purpose: that one describes
%   what a file means, this one describes where a file lives. Publication URLs
%   change without the format changing, and vice versa.

    source = struct( ...
        'series', {"EOP 14 C04", "EOP 20 C04", "EOP 20 C04 dPsiDEpsilon", ...
                   "finals2000A"}, ...
        'url', {"https://hpiers.obspm.fr/iers/eop/eopc04_14/eopc04_IAU2000.62-now", ...
                "https://hpiers.obspm.fr/iers/eop/eopc04/eopc04.1962-now", ...
                "https://hpiers.obspm.fr/iers/eop/eopc04/eopc04_12h_dPsi_dEps.1984-now", ...
                "https://maia.usno.navy.mil/ser7/finals2000A.all"}, ...
        'localName', {"eopc04_14_IAU2000.62-now", "eopc04_20.1962-now", ...
                      "eopc04_20_12h_dPsi_dEps.1984-now", "finals2000A.all"});
end

function folder = localDefaultCache()
%LOCALDEFAULTCACHE The toolbox data folder, from its one authority.
%
%   D119: this function used to compose data/ from its own mfilename, and so
%   did its twin in the sibling downloader. Two definitions of one location
%   cannot be moved together, and a caller who set one was surprised by the
%   other. Both now ask referenceSystem.dataFolder.

    folder = referenceSystem.dataFolder();
end

function [isFresh, age] = localCacheIsFresh(file, maxAge)
%LOCALCACHEISFRESH Whether an existing copy is young enough to reuse.

    isFresh = false;
    age = duration(missing);
    entry = dir(file);
    if isempty(entry)
        return
    end
    age = datetime('now') - datetime(entry.datenum, 'ConvertFrom', 'datenum');
    isFresh = age <= maxAge;
end

function info = localInfo(series, url, fromCache, age, file, startTime)
%LOCALINFO The diagnostics struct, returned rather than printed.

    entry = dir(file);
    bytes = 0;
    if ~isempty(entry)
        bytes = entry.bytes;
    end
    info = struct('series', series, 'url', string(url), ...
        'fromCache', fromCache, 'fileAge', age, 'bytes', bytes, ...
        'duration', toc(startTime));
end
