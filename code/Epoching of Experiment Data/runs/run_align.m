function run_align()
%RUN_ALIGN
% Align original timestamped source folders under Raw/VPXX into standardized
% folders:
%   Heart
%   Data Analyzer Heart
%   Hip
%   Data Analyzer Hip
%
% Uses:
%   - compute_common_time_window.m
%   - cut_file_for_alignment.m
%   - write_unisens_xml_aligned.m

    %% 0. PATH SETUP
    scriptDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(scriptDir);

    addpath(fullfile(projectRoot, 'configs'));
    addpath(fullfile(projectRoot, 'functions'));
    addpath(fullfile(projectRoot, 'runs'));

    %% 1. PARTICIPANT
    participantId = input('Enter participant ID for alignment (e.g., VP01): ', 's');
    cfg = config_heart(participantId);
    cfg.projectRoot = projectRoot;

    fprintf('\n=== STARTING ALIGNMENT FOR %s ===\n', participantId);
    fprintf('Project root: %s\n', cfg.projectRoot);

    %% 2. PARTICIPANT RAW FOLDER
    vpRawDir = fullfile(cfg.projectRoot, cfg.dir.raw, participantId);
    if ~isfolder(vpRawDir)
        error('run_align:ParticipantFolderNotFound', ...
            'Participant folder not found: %s', vpRawDir);
    end

    fprintf('Scanning participant raw folder:\n  %s\n', vpRawDir);

    %% 3. FIND SOURCE FOLDERS
    sources = find_source_folders_local(vpRawDir);
    sourceKeys = fieldnames(sources);

    if isempty(sourceKeys)
        error('run_align:NoSourceFolders', ...
            'No timestamped source folders were recognized under %s', vpRawDir);
    end

    fprintf('\nDetected source folders:\n');
    for i = 1:numel(sourceKeys)
        key = sourceKeys{i};
        s = sources.(key);
        fprintf('  %-20s -> %s\n', s.targetName, s.sourceName);
    end

    %% 4. COMPUTE COMMON TIME WINDOW
    fprintf('\nReading XML metadata and computing common time window...\n');
    alignInfo = compute_common_time_window(sources);

    fprintf('\nPer-source timing summary:\n');
    for i = 1:numel(alignInfo.sourceKeys)
        key = alignInfo.sourceKeys{i};
        e = alignInfo.entries.(key);

        fprintf('  [%s]\n', e.targetName);
        fprintf('    Source folder : %s\n', e.sourceName);
        fprintf('    Start         : %s\n', char(e.timestampStart));
        fprintf('    End           : %s\n', char(e.endTime));
        fprintf('    Duration (s)  : %.3f\n', e.durationSec);
    end

    fprintf('\nComputed common window:\n');
    fprintf('  commonStart     : %s\n', char(alignInfo.commonStart));
    fprintf('  commonEnd       : %s\n', char(alignInfo.commonEnd));
    fprintf('  commonDuration  : %.3f s\n', alignInfo.commonDurationSec);

    %% 5. CHECK / REMOVE EXISTING STANDARDIZED OUTPUT FOLDERS
    targetNames = {'Heart','Data Analyzer Heart','Hip','Data Analyzer Hip'};
    existingTargets = {};

    for i = 1:numel(targetNames)
        p = fullfile(vpRawDir, targetNames{i});
        if isfolder(p)
            existingTargets{end+1} = p; %#ok<AGROW>
        end
    end

    if ~isempty(existingTargets)
        fprintf('\nExisting standardized folders detected:\n');
        for i = 1:numel(existingTargets)
            fprintf('  %s\n', existingTargets{i});
        end

        response = input('Delete and recreate these folders? (Y/N): ', 's');
        if ~(strcmpi(response, 'Y') || strcmpi(response, 'E'))
            error('run_align:UserCancelled', 'Alignment cancelled by user.');
        end

        for i = 1:numel(existingTargets)
            rmdir(existingTargets{i}, 's');
            fprintf('Deleted: %s\n', existingTargets{i});
        end
    end

    %% 6. ALIGN EACH AVAILABLE SOURCE FOLDER
    fprintf('\n=== WRITING ALIGNED OUTPUTS ===\n');

    alignmentResults = struct();

    % Reference index maps:
    % Heart -> Data Analyzer Heart
    % Hip   -> Data Analyzer Hip
    heartReferenceIndexMap = struct();
    hipReferenceIndexMap = struct();

    orderedKeys = {'Heart','DataAnalyzerHeart','Hip','DataAnalyzerHip'};
    for i = 1:numel(orderedKeys)
        key = orderedKeys{i};
        if isfield(sources, key)
            src = sources.(key);
            fprintf('\nAligning source: %s\n', src.sourceName);

            if strcmp(key, 'Heart')
                result = align_one_source_folder_local(src, alignInfo, vpRawDir, heartReferenceIndexMap);
                heartReferenceIndexMap = result.referenceIndexMap;

            elseif strcmp(key, 'DataAnalyzerHeart')
                result = align_one_source_folder_local(src, alignInfo, vpRawDir, heartReferenceIndexMap);

            elseif strcmp(key, 'Hip')
                result = align_one_source_folder_local(src, alignInfo, vpRawDir, hipReferenceIndexMap);
                hipReferenceIndexMap = result.referenceIndexMap;

            elseif strcmp(key, 'DataAnalyzerHip')
                result = align_one_source_folder_local(src, alignInfo, vpRawDir, hipReferenceIndexMap);
            end

            alignmentResults.(key) = result;

            fprintf('  -> Created: %s\n', result.outputDir);
            fprintf('  -> Kept files: %d\n', numel(result.keptIds));
        end
    end

    %% 7. SIMPLE ALIGNMENT LOG
    logPath = fullfile(cfg.projectRoot, cfg.dir.logs, sprintf('%s_alignment_log.txt', participantId));
    if ~isfolder(fileparts(logPath))
        mkdir(fileparts(logPath));
    end

    fid = fopen(logPath, 'w');
    if fid ~= -1
        fprintf(fid, 'ALIGNMENT LOG FOR %s\n', participantId);
        fprintf(fid, 'Project root: %s\n\n', cfg.projectRoot);

        fprintf(fid, 'COMMON WINDOW\n');
        fprintf(fid, 'commonStart: %s\n', char(alignInfo.commonStart));
        fprintf(fid, 'commonEnd: %s\n', char(alignInfo.commonEnd));
        fprintf(fid, 'commonDurationSec: %.6f\n\n', alignInfo.commonDurationSec);

        fprintf(fid, 'SOURCE SUMMARY\n');
        for i = 1:numel(alignInfo.sourceKeys)
            key = alignInfo.sourceKeys{i};
            e = alignInfo.entries.(key);
            fprintf(fid, '[%s]\n', e.targetName);
            fprintf(fid, 'sourceName: %s\n', e.sourceName);
            fprintf(fid, 'sourcePath: %s\n', e.sourcePath);
            fprintf(fid, 'start: %s\n', char(e.timestampStart));
            fprintf(fid, 'end: %s\n', char(e.endTime));
            fprintf(fid, 'durationSec: %.6f\n\n', e.durationSec);
        end

        fprintf(fid, 'OUTPUT SUMMARY\n');
        resultKeys = fieldnames(alignmentResults);
        for i = 1:numel(resultKeys)
            key = resultKeys{i};
            r = alignmentResults.(key);
            fprintf(fid, '[%s]\n', key);
            fprintf(fid, 'outputDir: %s\n', r.outputDir);
            fprintf(fid, 'nFiles: %d\n', numel(r.keptIds));
            for k = 1:numel(r.keptIds)
                fprintf(fid, '  %s\n', r.keptIds{k});
            end
            fprintf(fid, '\n');
        end
        fclose(fid);
    end

    %% 8. FINAL MESSAGE
    fprintf('\n=== ALIGNMENT COMPLETED FOR %s ===\n', participantId);
    fprintf('Marker control should now be done in:\n');
    fprintf('  %s\n', fullfile(vpRawDir, 'Heart', 'unisens.xml'));
    fprintf('\nThen run your epoch pipeline on the standardized folders.\n');
    fprintf('Alignment log: %s\n', logPath);
end

%% ========================= LOCAL FUNCTIONS =========================

function sources = find_source_folders_local(vpRawDir)
    d = dir(vpRawDir);
    d = d([d.isdir]);
    names = {d.name};
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
            sources.DataAnalyzerHeart = make_source_entry_local(fullPath, folderName, ...
                'Data Analyzer Heart', 'DataAnalyzerHeart');

        elseif contains(lowerName, 'csv_heart')
            sources.Heart = make_source_entry_local(fullPath, folderName, ...
                'Heart', 'Heart');

        elseif contains(lowerName, 'data analyzer_hip')
            sources.DataAnalyzerHip = make_source_entry_local(fullPath, folderName, ...
                'Data Analyzer Hip', 'DataAnalyzerHip');

        elseif contains(lowerName, 'csv_hip')
            sources.Hip = make_source_entry_local(fullPath, folderName, ...
                'Hip', 'Hip');
        end
    end
end

function s = make_source_entry_local(sourcePath, sourceName, targetName, typeKey)
    s = struct();
    s.sourcePath = sourcePath;
    s.sourceName = sourceName;
    s.targetName = targetName;
    s.typeKey = typeKey;
end

function result = align_one_source_folder_local(src, alignInfo, vpRawDir, referenceIndexMap)
    key = src.typeKey;
    entryMeta = alignInfo.entries.(key);

    sourceDir = src.sourcePath;
    outputDir = fullfile(vpRawDir, src.targetName);

    if ~isfolder(outputDir)
        mkdir(outputDir);
    end

    xmlPath = fullfile(sourceDir, 'unisens.xml');
    if ~isfile(xmlPath)
        error('align_one_source_folder_local:MissingXML', ...
            'unisens.xml not found in %s', sourceDir);
    end

    keptIds = {};
    fileLogs = struct([]);

    meta = read_unisens_xml(xmlPath);

    isReferenceCsv = strcmp(key, 'Heart') || strcmp(key, 'Hip');
    isDataAnalyzer = strcmp(key, 'DataAnalyzerHeart') || strcmp(key, 'DataAnalyzerHip');

    for iFile = 1:length(meta.fileIds)
        fileId = meta.fileIds{iFile};
        fieldName = meta.fileFieldNames{iFile};
        srcPath = fullfile(sourceDir, fileId);

        if ~isfile(srcPath)
            continue;
        end

        info = meta.files.(fieldName);
        dstPath = fullfile(outputDir, fileId);

        try
            if isReferenceCsv
                % CSV reference side: compute exact indices here
                [ok, cutInfo] = cut_file_for_alignment( ...
                    srcPath, dstPath, info, ...
                    entryMeta.timestampStart, ...
                    alignInfo.commonStart, ...
                    alignInfo.commonEnd);

                if ok
                    keptIds{end+1} = fileId; %#ok<AGROW>

                    % Store exact indices for matching BIN side
                    baseKey = erase(fileId, '.csv');
                    referenceIndexMap.(baseKey) = struct( ...
                        'startIndex', cutInfo.startIndex, ...
                        'endIndex', cutInfo.endIndex, ...
                        'entryType', cutInfo.entryType, ...
                        'sampleRate', cutInfo.sampleRate);
                end

            elseif isDataAnalyzer
                % BIN/Data Analyzer side: reuse exact CSV indices
                baseKey = erase(fileId, '.bin');
                if strcmpi(fileId, 'nn_live.csv')
                    baseKey = 'nn_live';
                elseif strcmpi(fileId, 'bpmbxb_live.csv')
                    baseKey = 'bpmbxb_live';
                end

                if ~isfield(referenceIndexMap, baseKey)
                    warning('No reference indices found for %s in %s. Skipping.', fileId, src.targetName);
                    continue;
                end

                ref = referenceIndexMap.(baseKey);

                [ok, cutInfo] = cut_file_for_alignment( ...
                    srcPath, dstPath, info, ...
                    entryMeta.timestampStart, ...
                    alignInfo.commonStart, ...
                    alignInfo.commonEnd, ...
                    ref.startIndex, ...
                    ref.endIndex);

                if ok
                    keptIds{end+1} = fileId; %#ok<AGROW>
                end
            else
                ok = false;
                cutInfo = struct();
            end

            if ok
                logEntry = cutInfo;
                logEntry.sourceType = src.targetName;
                logEntry.sourceFolder = src.sourceName;
                if isempty(fileLogs)
                    fileLogs = logEntry;
                else
                    fileLogs(end+1) = logEntry; %#ok<AGROW>
                end
            end

        catch ME
            warning('align_one_source_folder_local:CutFailed', ...
                'Failed to align %s\n%s', srcPath, ME.message);
        end
    end

    write_unisens_xml_aligned( ...
        outputDir, keptIds, ...
        alignInfo.commonStart, ...
        alignInfo.commonDurationSec, ...
        xmlPath);

    result = struct();
    result.outputDir = outputDir;
    result.keptIds = keptIds;
    result.fileLogs = fileLogs;
    result.referenceIndexMap = referenceIndexMap;
end