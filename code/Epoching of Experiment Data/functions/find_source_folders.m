function sources = find_source_folders(vpRawDir)
%FIND_SOURCE_FOLDERS Find original timestamped source folders under Raw/VPXX
%
% INPUT
%   vpRawDir : e.g. C:\...\Pertuba\Raw\VP01
%
% OUTPUT
%   sources : struct with possible fields:
%       .Heart
%       .DataAnalyzerHeart
%       .Hip
%       .DataAnalyzerHip
%
%   Each existing field contains:
%       .sourcePath   full folder path
%       .sourceName   original folder name
%       .targetName   standardized target folder name
%       .typeKey      internal key

    arguments
        vpRawDir (1,:) char
    end

    if ~isfolder(vpRawDir)
        error('find_source_folders:FolderNotFound', ...
            'Participant raw folder not found: %s', vpRawDir);
    end

    d = dir(vpRawDir);
    d = d([d.isdir]);
    names = {d.name};

    % remove . and ..
    names = names(~ismember(names, {'.','..'}));

    sources = struct();

    for i = 1:numel(names)
        folderName = names{i};
        fullPath = fullfile(vpRawDir, folderName);

        lowerName = lower(folderName);

        % Skip already standardized output folders
        if any(strcmp(folderName, {'Heart','Data Analyzer Heart','Hip','Data Analyzer Hip'}))
            continue;
        end

        if contains(lowerName, 'data analyzer_heart')
            sources.DataAnalyzerHeart = make_source_entry(fullPath, folderName, ...
                'Data Analyzer Heart', 'DataAnalyzerHeart');

        elseif contains(lowerName, 'csv_heart')
            sources.Heart = make_source_entry(fullPath, folderName, ...
                'Heart', 'Heart');

        elseif contains(lowerName, 'data analyzer_hip')
            sources.DataAnalyzerHip = make_source_entry(fullPath, folderName, ...
                'Data Analyzer Hip', 'DataAnalyzerHip');

        elseif contains(lowerName, 'csv_hip')
            sources.Hip = make_source_entry(fullPath, folderName, ...
                'Hip', 'Hip');
        end
    end
end

function s = make_source_entry(sourcePath, sourceName, targetName, typeKey)
    s = struct();
    s.sourcePath = sourcePath;
    s.sourceName = sourceName;
    s.targetName = targetName;
    s.typeKey = typeKey;
end