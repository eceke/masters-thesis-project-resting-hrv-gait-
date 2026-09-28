function logPath = write_epoch_log(confirmedMarkers, epochTable, cutInfo, logInfo, daCutInfo, cfg)
% Create Excel log file with all processing information
% Logs Data Analyzer Heart (.bin/.csv) cut indices (startSample/endSample etc.)

    arguments
        confirmedMarkers (:,1) struct
        epochTable table
        cutInfo struct
        logInfo struct
        daCutInfo struct
        cfg (1,1) struct
    end
    
    % Create log directory if it doesn't exist
    logDir = fullfile(cfg.projectRoot, cfg.dir.logs);
    if ~exist(logDir, 'dir')
        mkdir(logDir);
        fprintf('  Created log directory: %s\n', logDir);
    end
    
    % Create filename with timestamp
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    if isfield(cfg.log, 'fileName')
        baseName = cfg.log.fileName;
    else
        baseName = 'EpochLog.xlsx';
    end
    
    logFileName = sprintf('%s_%s_%s', cfg.participantId, timestamp, baseName);
    logPath = fullfile(logDir, logFileName);
    
    fprintf('  Creating Excel log: %s\n', logFileName);
    
    %% 1. MARKERS SHEET
    markerLabels = {
        'RS_EO1_end';
        'RS_EC_end';
        'RS_EO2_end';
        'BW_1KMH_start';
        'BW_1KMH_end';
        'FWW_1KMH_start';
        'FWW_1KMH_end';
        'BW_4KMH_start';
        'BW_4KMH_end';
        'FWW_4KMH_start';
        'FWW_4KMH_end';
    };
    
    % Create markers table
    markersData = cell(length(markerLabels), 6);
    for i = 1:length(markerLabels)
        markersData{i, 1} = i;
        markersData{i, 2} = markerLabels{i};
        markersData{i, 3} = confirmedMarkers(i).timeSec;
        markersData{i, 4} = confirmedMarkers(i).selectConfidence;
        
        % Check for manual override
        if isfield(confirmedMarkers, 'manualOverride')
            markersData{i, 5} = confirmedMarkers(i).manualOverride;
        else
            markersData{i, 5} = false;
        end
        
        % Determine source
        if markersData{i, 5}
            markersData{i, 6} = 'manual_override';
        else
            markersData{i, 6} = 'auto_detected';
        end
    end
    
    markersTable = cell2table(markersData, ...
        'VariableNames', {'Index', 'Label', 'TimeSec', 'Confidence', 'ManualOverride', 'Source'});
    
    %% 2. SEGMENTS SHEET
    % Copy epochTable and add extra information
    segmentsTable = epochTable;
    
    % Add file paths if available in cutInfo
    if ~isempty(cutInfo)
        matFiles = cell(height(segmentsTable), 1);
        csvPaths = cell(height(segmentsTable), 1);
        
        for i = 1:min(length(cutInfo), height(segmentsTable))
            if isfield(cutInfo(i), 'matFile')
                matFiles{i} = cutInfo(i).matFile;
            end
            if isfield(cutInfo(i), 'csvDir')
                csvPaths{i} = cutInfo(i).csvDir;
            end
        end
        
        segmentsTable.MatFile = matFiles;
        segmentsTable.CsvFolder = csvPaths;
    end

    %% 2B. DATA ANALYZER SEGMENT ROOT (optional convenience)
    % We don't assume per-segment folder names here; only log the intended root.
    daEpochRoot = fullfile(cfg.projectRoot, cfg.dir.epochs, cfg.participantId, 'DataAnalyzerHeart');
    if isfolder(daEpochRoot)
        segmentsTable.DataAnalyzerEpochRoot = repmat({daEpochRoot}, height(segmentsTable), 1);
    else
        segmentsTable.DataAnalyzerEpochRoot = repmat({''}, height(segmentsTable), 1);
    end
    
    %% 3. PROCESSING INFO SHEET
    processingInfo = {
        'Participant ID', cfg.participantId;
        'Processing Date', datestr(now, 'yyyy-mm-dd HH:MM:SS');
        'Config Version', 'config_heart_v1';
        'User Verified', logInfo.userVerified;
        'Interactive Rounds', logInfo.numIterations;
        'Total Segments', height(epochTable);
        'Project Root', cfg.projectRoot;
        'Raw Data Path', fullfile(cfg.projectRoot, cfg.dir.raw, cfg.participantId);
        'Epochs Path', fullfile(cfg.projectRoot, cfg.dir.epochs, cfg.participantId);
        'DataAnalyzer Epochs Path', daEpochRoot;
        'Log Path', logPath;
        'Notes', 'Interactive epoch extraction completed';
    };
    
    processingTable = cell2table(processingInfo, 'VariableNames', {'Parameter', 'Value'});
    
    %% 4. CORRECTION HISTORY SHEET (if any)
    if isfield(logInfo, 'correctionHistory') && ~isempty(logInfo.correctionHistory)
        correctionData = {};
        row = 1;
        
        for iIter = 1:length(logInfo.correctionHistory)
            if isfield(logInfo.correctionHistory(iIter), 'corrections')
                for iCorr = 1:length(logInfo.correctionHistory(iIter).corrections)
                    corr = logInfo.correctionHistory(iIter).corrections(iCorr);
                    
                    correctionData{row, 1} = iIter;
                    correctionData{row, 2} = corr.idx;
                    correctionData{row, 3} = markerLabels{corr.idx};
                    
                    if ~isempty(corr.oldTime)
                        correctionData{row, 4} = corr.oldTime;
                    else
                        correctionData{row, 4} = NaN;
                    end
                    
                    correctionData{row, 5} = corr.newTime;
                    correctionData{row, 6} = corr.method;
                    
                    row = row + 1;
                end
            end
        end
        
        if ~isempty(correctionData)
            correctionTable = cell2table(correctionData, ...
                'VariableNames', {'Iteration', 'MarkerIndex', 'MarkerLabel', 'OldTime', 'NewTime', 'Method'});
        else
            correctionTable = table();
        end
    else
        correctionTable = table();
    end

    %% 4B. DATA ANALYZER CUTS SHEET (NEW)
    daCutsTable = table();
    if ~isempty(daCutInfo) && isfield(daCutInfo, 'segments')
        segFields = fieldnames(daCutInfo.segments);
        if ~isempty(segFields)
            n = numel(segFields);
            rows = cell(n, 9);

            for i = 1:n
                s = daCutInfo.segments.(segFields{i});
                rows(i,:) = {
                    string(s.segmentName)
                    string(s.fileId)
                    double(s.fs)
                    double(s.startSample)
                    double(s.endSample)
                    double(s.nTotalSamples)
                    double(s.endSample - s.startSample + 1)   % nCutSamples
                    logical(s.cutOk)
                    string(segFields{i})                      % internal key
                };
            end

            daCutsTable = cell2table(rows, 'VariableNames', { ...
                'segmentName','fileId','fs','startSample','endSample','nTotalSamples','nCutSamples','cutOk','internalKey' ...
            });
        end
    end
    
    %% 5. WRITE TO EXCEL
    try
        writetable(markersTable, logPath, 'Sheet', 'Markers');
        writetable(segmentsTable, logPath, 'Sheet', 'Segments');
        writetable(processingTable, logPath, 'Sheet', 'ProcessingInfo');
        
        if ~isempty(correctionTable)
            writetable(correctionTable, logPath, 'Sheet', 'Corrections');
        end

        if ~isempty(daCutsTable)
            writetable(daCutsTable, logPath, 'Sheet', 'DataAnalyzerCuts');
        end
        
        fprintf('  Excel log created successfully: %s\n', logPath);
        
    catch ME
        warning(ME.identifier, "Failed to write Excel file: %s", ME.message);
        
        % Fallback: save as .mat
        matLogPath = strrep(logPath, '.xlsx', '.mat');
        save(matLogPath, 'markersTable', 'segmentsTable', 'processingTable', 'cfg', 'daCutsTable');
        fprintf('  Saved log as .mat instead: %s\n', matLogPath);
        logPath = matLogPath;
    end
end