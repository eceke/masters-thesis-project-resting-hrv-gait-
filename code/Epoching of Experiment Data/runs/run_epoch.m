function run_epoch()
%RUN_EPOCH Interactive epoch extraction pipeline.
    
    %% 0. ADD NECESSARY PATHS
    % Get the directory where this script is located
    scriptDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(scriptDir);  % Go up one level to project root
    
    % Add all necessary folders to MATLAB path
    addpath(fullfile(projectRoot, 'configs'));
    addpath(fullfile(projectRoot, 'functions'));
    addpath(fullfile(projectRoot, 'runs'));

    %% 1. GET PARTICIPANT ID
    participantId = input('Enter participant ID (e.g., VP01): ', 's');
    cfg = config_heart(participantId);
    
    % Override projectRoot with actual path
    cfg.projectRoot = projectRoot;
    
    fprintf('\n=== STARTING PIPELINE FOR %s ===\n', participantId);
    fprintf('Project root: %s\n', cfg.projectRoot);
    
    %% 2. SETUP FILE PATHS (HEART = REFERENCE)
    rawParticipantDir = fullfile(cfg.projectRoot, cfg.dir.raw, participantId);

    heartDir = fullfile(rawParticipantDir, 'Heart');
    if ~exist(heartDir, 'dir')
        error('Heart folder not found: %s', heartDir);
    end
    fprintf('Using Heart folder: %s\n', heartDir);

    xmlPath = fullfile(heartDir, 'unisens.xml');
    if ~isfile(xmlPath)
        error('XML file not found: %s', xmlPath);
    end
    
    %% 3. READ HEART METADATA
    fprintf('Reading Heart metadata...\n');
    meta = read_unisens_xml(xmlPath);
    
    %% 4. LOAD HEART CHANNELS INTO dataStruct (RAW + PHYS)
    fprintf('Loading Heart channels into dataStruct (RAW + PHYS)...\n');
    dataStruct = struct();

    for iFile = 1:length(meta.fileIds)
        fileId    = meta.fileIds{iFile};           % e.g., 'ecg.csv'
        fieldName = meta.fileFieldNames{iFile};    % e.g., 'ecg_csv'

        fprintf('  %s... ', fileId);

        csvPath = fullfile(heartDir, fileId);
        if ~isfile(csvPath)
            fprintf('File not found, skipping.\n');
            continue;
        end

        try
            % --- 1) Read RAW (unscaled) values exactly as in CSV
            rawData = read_channel_csv(csvPath, ...
                meta.files.(fieldName).csv.separator, ...
                meta.files.(fieldName).csv.decimalSeparator);

            % --- 2) Convert to physical units
            baseline = [];
            lsbValue = [];

            if isfield(meta.files.(fieldName), 'baseline')
                baseline = meta.files.(fieldName).baseline;
            end
            if isfield(meta.files.(fieldName), 'lsbValue')
                lsbValue = meta.files.(fieldName).lsbValue;
            end

            try
                physData = convert_raw_to_physical(rawData, baseline, lsbValue);
            catch
                physData = rawData;
                if isfield(cfg, 'advanced') && isfield(cfg.advanced, 'verbose') && cfg.advanced.verbose
                    warning('Physical conversion failed for %s -> using phys=raw fallback.', fileId);
                end
            end

            % Clean field name: remove '_csv' suffix
            cleanFieldName = strrep(fieldName, '_csv', '');

            % --- 3) Store BOTH representations
            dataStruct.(cleanFieldName).raw  = rawData;
            dataStruct.(cleanFieldName).phys = physData;
            dataStruct.(cleanFieldName).data = physData;  % backward compat

            dataStruct.(cleanFieldName).fs = meta.files.(fieldName).sampleRate;
            dataStruct.(cleanFieldName).originalFile = fileId;

            if isfield(meta.files.(fieldName), 'unit')
                dataStruct.(cleanFieldName).unit = meta.files.(fieldName).unit;
            else
                dataStruct.(cleanFieldName).unit = '';
            end

            fprintf('OK (fs=%g Hz, %d samples)\n', ...
                dataStruct.(cleanFieldName).fs, size(physData, 1));

        catch ME
            fprintf('ERROR: %s\n', ME.message);
            warning('Failed to load %s: %s', fileId, ME.message);
        end
    end
    
    %% 5. MARKER DETECTION (using HEART ACC PHYSICAL)
    fprintf('\nDetecting markers from Heart ACC...\n');

    if ~isfield(dataStruct, 'acc')
        error('ACC data not found in Heart. Required for marker detection.');
    end

    if isfield(dataStruct.acc, 'phys') && ~isempty(dataStruct.acc.phys)
        accPhys = dataStruct.acc.phys;
    else
        accPhys = dataStruct.acc.data;
    end

    fsAcc = dataStruct.acc.fs;
    fprintf('Heart ACC: %g Hz, %d samples\n', fsAcc, size(accPhys, 1));

    candidates = detect_marker_candidates(accPhys, fsAcc, cfg);

    % Gyro for pattern validation
    if isfield(dataStruct, 'angularrate')
        if isfield(dataStruct.angularrate, 'phys') && ~isempty(dataStruct.angularrate.phys)
            gyroPhys = dataStruct.angularrate.phys;
        else
            gyroPhys = dataStruct.angularrate.data;
        end
        fprintf('Heart Gyro: %g Hz\n', dataStruct.angularrate.fs);
    else
        gyroPhys = [];
        fprintf('  Note: No gyro data found for pattern validation.\n');
    end
    
    %% 6. SELECT 11 MARKERS
    fprintf('Selecting 11 markers...\n');
    [selectedMarkers, selectionInfo] = select_markers_sequence_based(...
        candidates, accPhys, gyroPhys, fsAcc, cfg); %#ok<NASGU>
    
    %% 7. INTERACTIVE VERIFICATION
    fprintf('\n=== INTERACTIVE MARKER VERIFICATION ===\n');
    [confirmedMarkers, logInfo] = confirm_markers(...
        selectedMarkers, candidates, fsAcc, cfg);
    
    %% 8. BUILD EPOCH TABLE
    fprintf('\nBuilding epoch table...\n');
    epochTable = build_epoch_table(confirmedMarkers, cfg);
    
    % Display summary
    fprintf('\n=== EPOCH TABLE SUMMARY ===\n');
    for i = 1:height(epochTable)
        fprintf('%2d. %-12s: %6.1f - %6.1f s (%5.1f s)\n', ...
            i, epochTable.segmentName{i}, ...
            epochTable.startSec(i), epochTable.endSec(i), ...
            epochTable.durationSec(i));
    end
    
    %% 9. CUT AND SAVE HEART EPOCHS
    fprintf('\nCutting and saving Heart epochs...\n');
    
    cfg.output.channelsToSave = {
        'acc'
        'angularrate'
        'charging'
        'ecg'
        'hr_live'
        'hrvisvalid_live'
        'hrvrmssd_live'
        'movementacceleration_live'
        'nn_live'
        'bpmbxb_live'
        'press'
        'stateofcharge'
        'stepcount_live'
        'temp'
        'tempmean_live'
    };
    
    [epochFilesHeart, cutInfoHeart] = cut_and_save_epochs( ...
        epochTable, dataStruct, cfg, meta, 'Heart', 'Heart'); %#ok<NASGU>

    %% 10. CUT AND SAVE HIP EPOCHS (OPTIONAL, SAME EPOCH TABLE)
    hipDir = fullfile(rawParticipantDir, 'Hip');
    hasHipCsv = isfolder(hipDir) && isfile(fullfile(hipDir, 'unisens.xml'));

    if hasHipCsv
        fprintf('\nCutting and saving HIP epochs using Heart-derived epochTable...\n');

        hipXmlPath = fullfile(hipDir, 'unisens.xml');
        metaHip = read_unisens_xml(hipXmlPath);

        dataStructHip = struct();

        for iFile = 1:length(metaHip.fileIds)
            fileId    = metaHip.fileIds{iFile};
            fieldName = metaHip.fileFieldNames{iFile};

            fprintf('  [HIP] %s... ', fileId);

            csvPath = fullfile(hipDir, fileId);
            if ~isfile(csvPath)
                fprintf('File not found, skipping.\n');
                continue;
            end

            try
                rawData = read_channel_csv(csvPath, ...
                    metaHip.files.(fieldName).csv.separator, ...
                    metaHip.files.(fieldName).csv.decimalSeparator);

                baseline = [];
                lsbValue = [];

                if isfield(metaHip.files.(fieldName), 'baseline')
                    baseline = metaHip.files.(fieldName).baseline;
                end
                if isfield(metaHip.files.(fieldName), 'lsbValue')
                    lsbValue = metaHip.files.(fieldName).lsbValue;
                end

                try
                    physData = convert_raw_to_physical(rawData, baseline, lsbValue);
                catch
                    physData = rawData;
                end

                cleanFieldName = strrep(fieldName, '_csv', '');

                dataStructHip.(cleanFieldName).raw  = rawData;
                dataStructHip.(cleanFieldName).phys = physData;
                dataStructHip.(cleanFieldName).data = physData;
                dataStructHip.(cleanFieldName).fs = metaHip.files.(fieldName).sampleRate;
                dataStructHip.(cleanFieldName).originalFile = fileId;

                if isfield(metaHip.files.(fieldName), 'unit')
                    dataStructHip.(cleanFieldName).unit = metaHip.files.(fieldName).unit;
                else
                    dataStructHip.(cleanFieldName).unit = '';
                end

                fprintf('OK (fs=%g Hz, %d samples)\n', ...
                    dataStructHip.(cleanFieldName).fs, size(physData, 1));

            catch ME
                fprintf('ERROR: %s\n', ME.message);
                warning('Failed to load HIP file %s: %s', fileId, ME.message);
            end
        end

        [epochFilesHip, cutInfoHip] = cut_and_save_epochs( ...
            epochTable, dataStructHip, cfg, metaHip, 'Hip', 'Hip'); %#ok<NASGU>
    else
        epochFilesHip = struct(); %#ok<NASGU>
        cutInfoHip = struct(); %#ok<NASGU>
    end

    %% 11. VERIFY BIN<->CSV EQUIVALENCE BEFORE BIN CUTTING
    fprintf('\n[CHECK] Verifying BIN<->CSV equivalence before BIN cutting...\n');

    % --- HEART CHECK ---
    reportHeart = compare_bin_vs_csv('Heart', participantId);
    failHeart = reportHeart(reportHeart.binExists & reportHeart.csvExists & ...
        ~(reportHeart.sameSize & reportHeart.exactEqual), :);

    hipCsvDir = fullfile(rawParticipantDir, 'Hip');
    hipBinDir = fullfile(rawParticipantDir, 'Data Analyzer Hip');
    hasHipPair = isfolder(hipCsvDir) && isfolder(hipBinDir);

    % --- HEART FAILS -> BLOCK HEART BIN CUTTING ---
    if ~isempty(failHeart)
        fprintf('\n[ERROR] HEART BIN<->CSV mismatch detected. HEART BIN cutting aborted.\n');
        fprintf('Mismatching HEART files (base ids):\n');

        for i = 1:height(failHeart)
            fprintf('  - %s | sameSize=%d | exactEqual=%d | maxAbsDiff=%g\n', ...
                string(failHeart.id{i}), failHeart.sameSize(i), failHeart.exactEqual(i), failHeart.maxAbsDiff(i));
        end

        error('HEART BIN cutting aborted due to HEART BIN<->CSV mismatch.');
    else
        fprintf('[CHECK] All HEART BIN<->CSV pairs match exactly.\n');
    end

    % --- HIP CHECK (only if folders exist) ---
    if hasHipPair
        reportHip = compare_bin_vs_csv('Hip', participantId);
        failHip = reportHip(reportHip.binExists & reportHip.csvExists & ...
            ~(reportHip.sameSize & reportHip.exactEqual), :);

        if ~isempty(failHip)
            fprintf('\n[ERROR] HIP BIN<->CSV mismatch detected. HIP BIN cutting aborted.\n');
            fprintf('Mismatching HIP files (base ids):\n');

            for i = 1:height(failHip)
                fprintf('  - %s | sameSize=%d | exactEqual=%d | maxAbsDiff=%g\n', ...
                    string(failHip.id{i}), failHip.sameSize(i), failHip.exactEqual(i), failHip.maxAbsDiff(i));
            end

            error('HIP BIN cutting aborted due to HIP BIN<->CSV mismatch.');
        else
            fprintf('[CHECK] All HIP BIN<->CSV pairs match exactly.\n');
        end
    end

    fprintf('[CHECK] Required BIN<->CSV checks passed. Proceeding to BIN cutting.\n');

    %% 12. CUT AND SAVE DATA ANALYZER HEART EPOCHS
    fprintf('\nCutting and saving Data Analyzer Heart (.bin/.csv) epochs...\n');
    [daEpochFilesHeart, daCutInfoHeart] = cut_and_save_dataanalyzer_epochs( ...
        epochTable, cfg, 'Data Analyzer Heart', 'DataAnalyzerHeart'); %#ok<NASGU>

    %% 13. CUT AND SAVE DATA ANALYZER HIP EPOCHS (OPTIONAL)
    if hasHipPair
        fprintf('\nCutting and saving Data Analyzer Hip (.bin/.csv) epochs...\n');
        [daEpochFilesHip, daCutInfoHip] = cut_and_save_dataanalyzer_epochs( ...
            epochTable, cfg, 'Data Analyzer Hip', 'DataAnalyzerHip'); %#ok<NASGU>
    else
        daEpochFilesHip = struct(); %#ok<NASGU>
        daCutInfoHip = struct(); %#ok<NASGU>
    end
    
    %% 14. WRITE EXCEL LOG (Heart-based epoch log)
    fprintf('\nWriting Excel log...\n');
    logPath = write_epoch_log(confirmedMarkers, epochTable, cutInfoHeart, logInfo, daCutInfoHeart, cfg);
    
    %% 15. QC PLOTS (optional, Heart-based QC plots)
    if isfield(cfg, 'qc') && isfield(cfg.qc, 'createPlots') && cfg.qc.createPlots
        fprintf('Creating QC plots...\n');
    
        try
            qcPaths = make_qc_plots(confirmedMarkers, dataStruct, epochTable, cfg);
    
            fprintf('  QC plots created: %d files\n', numel(qcPaths));
            fprintf('  QC plot folder: %s\n', ...
                fullfile(cfg.projectRoot, cfg.dir.qcPlots, cfg.participantId));
    
        catch ME
            warning('run_epoch:QCPlotFailed', '%s', ...
                sprintf('QC plot creation failed: %s', ME.message));
        
            fprintf('  Cutting outputs were already created, but QC plots were not saved.\n');
        end
    end
    
    %% 16. COMPLETION
    fprintf('\n=== PIPELINE COMPLETED FOR %s ===\n', participantId);
    fprintf('Summary:\n');
    fprintf('  Segments: %d\n', height(epochTable));
    fprintf('  Epochs root: %s\n', fullfile(cfg.projectRoot, cfg.dir.epochs, participantId));
    fprintf('  Heart CSV epochs: %s\n', fullfile(cfg.projectRoot, cfg.dir.epochs, participantId, 'Heart'));
    
    if hasHipCsv
        fprintf('  Hip CSV epochs: %s\n', fullfile(cfg.projectRoot, cfg.dir.epochs, participantId, 'Hip'));
    end

    fprintf('  DataAnalyzer Heart epochs: %s\n', fullfile(cfg.projectRoot, cfg.dir.epochs, participantId, 'DataAnalyzerHeart'));
    if hasHipPair
        fprintf('  DataAnalyzer Hip epochs: %s\n', fullfile(cfg.projectRoot, cfg.dir.epochs, participantId, 'DataAnalyzerHip'));
    end

    if exist('logPath', 'var') && ~isempty(logPath)
        fprintf('  Log file: %s\n', logPath);
    end
    
    if exist('cutInfoHeart', 'var') && ~isempty(cutInfoHeart)
        if isfield(cutInfoHeart, 'numChannels')
            totalChannelsHeart = sum([cutInfoHeart.numChannels]);
            fprintf('  Total HEART channel-segments: %d\n', totalChannelsHeart);
        end
    end
    
    % Save workspace variables for debugging
    if isfield(cfg, 'advanced') && isfield(cfg.advanced, 'saveIntermediate') && cfg.advanced.saveIntermediate
        logDir = fullfile(cfg.projectRoot, cfg.dir.logs);
        if ~exist(logDir, 'dir')
            mkdir(logDir);
        end
        wsPath = fullfile(logDir, sprintf('%s_workspace.mat', participantId));
        save(wsPath, ...
            'confirmedMarkers', 'epochTable', ...
            'cutInfoHeart', 'cutInfoHip', ...
            'logInfo', 'cfg', 'dataStruct');
        fprintf('  Workspace saved: %s\n', wsPath);
    end
    
    fprintf('\nDone!\n');
end