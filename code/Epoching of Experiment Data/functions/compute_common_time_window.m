function alignInfo = compute_common_time_window(sources)
%COMPUTE_COMMON_TIME_WINDOW Read XML metadata and compute common time window
%
% INPUT
%   sources : struct returned by find_source_folders
%
% OUTPUT
%   alignInfo : struct with fields
%       .entries         metadata per source
%       .commonStart     datetime
%       .commonEnd       datetime
%       .commonDurationSec
%       .sourceKeys
%
% Each alignInfo.entries.(key) contains:
%       .sourcePath
%       .sourceName
%       .targetName
%       .xmlPath
%       .timestampStart
%       .durationSec
%       .endTime

    arguments
        sources (1,1) struct
    end

    sourceKeys = fieldnames(sources);
    if isempty(sourceKeys)
        error('compute_common_time_window:NoSources', ...
            'No source folders were found.');
    end

    alignInfo = struct();
    alignInfo.entries = struct();
    alignInfo.sourceKeys = sourceKeys;

    startTimes = datetime.empty(0,1);
    endTimes = datetime.empty(0,1);

    for i = 1:numel(sourceKeys)
        key = sourceKeys{i};
        src = sources.(key);

        xmlPath = fullfile(src.sourcePath, 'unisens.xml');
        if ~isfile(xmlPath)
            error('compute_common_time_window:MissingXML', ...
                'unisens.xml not found in source folder: %s', src.sourcePath);
        end

        meta = read_unisens_xml(xmlPath);

        if isempty(meta.timestampStart)
            error('compute_common_time_window:MissingStartTime', ...
                'timestampStart missing or unreadable in: %s', xmlPath);
        end

        if ~isfinite(meta.durationSec) || isnan(meta.durationSec)
            error('compute_common_time_window:MissingDuration', ...
                'duration missing or unreadable in: %s', xmlPath);
        end

        ts = meta.timestampStart;

        % Normalize timezone for safe comparison
        if ~isempty(ts) && ~isempty(ts.TimeZone)
            ts.TimeZone = '';
        end

        entry = struct();
        entry.sourcePath = src.sourcePath;
        entry.sourceName = src.sourceName;
        entry.targetName = src.targetName;
        entry.typeKey = src.typeKey;
        entry.xmlPath = xmlPath;
        entry.timestampStart = ts;
        entry.durationSec = meta.durationSec;
        entry.endTime = ts + seconds(meta.durationSec);

        alignInfo.entries.(key) = entry;

        startTimes(end+1,1) = entry.timestampStart; %#ok<AGROW>
        endTimes(end+1,1) = entry.endTime; %#ok<AGROW>
    end

    alignInfo.commonStart = max(startTimes);
    alignInfo.commonEnd = min(endTimes);
    alignInfo.commonDurationSec = seconds(alignInfo.commonEnd - alignInfo.commonStart);

    if ~(alignInfo.commonEnd > alignInfo.commonStart)
        error('compute_common_time_window:InvalidWindow', ...
            'No valid common time window found. commonStart=%s | commonEnd=%s', ...
            char(alignInfo.commonStart), char(alignInfo.commonEnd));
    end
end