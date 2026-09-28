%% run_memory_analysis_accuracy.m
% Memory-HRV-Gait accuracy/precision pipeline
% ------------------------------------------------------------
% This script reads FastWords recall files and an HRV-gait long CSV,
% builds an analysis-ready memory-HRV-gait table, runs binomial GLMMs,
% applies Benjamini-Hochberg FDR correction within each result family,
% and writes CSV/XLSX outputs.
%
% Main analytical rules:
% - BW walking segments are not used for memory models.
% - User can select 1 or 2 memory speed files.
% - Memory outcomes are modeled as binomial GLMMs.
% - HRV and gait predictor selection allows 0 to 5 predictors each. If HRV or gait selection is 0, the corresponding model family is skipped.

clear; clc;

fprintf('\n============================================================\n');
fprintf(' MEMORY-HRV-GAIT ACCURACY / PRECISION PIPELINE\n');
fprintf('============================================================\n\n');

%% Locate project folders
thisFile = mfilename('fullpath');
if isempty(thisFile)
    error('Please run this file as a saved MATLAB script, not by copying sections into the Command Window.');
end

srcDir = fileparts(thisFile);
projectRoot = fileparts(srcDir);
functionsDir = fullfile(srcDir, 'functions');
dataRawDir = fullfile(projectRoot, 'data_raw');
outputBaseDir = fullfile(projectRoot, 'outputs', 'accuracy');

if ~exist(functionsDir, 'dir')
    error('Functions folder was not found: %s', functionsDir);
end
addpath(functionsDir);

local_ensure_dir(dataRawDir);
local_ensure_dir(fullfile(outputBaseDir, 'merged'));
local_ensure_dir(fullfile(outputBaseDir, 'qc'));
local_ensure_dir(fullfile(outputBaseDir, 'results_csv'));
local_ensure_dir(fullfile(outputBaseDir, 'reports'));

%% Input files
fprintf('Step 1/8: Locating input files...\n');

hvgFile = local_resolve_file( ...
    fullfile(dataRawDir, 'LMM_HRV_GAIT_long.csv'), ...
    'Select LMM_HRV_GAIT_long.csv');

fprintf('  HRV-gait file:      %s\n\n', hvgFile);

%% User settings
fprintf('Step 2/8: Collecting user settings...\n');
presentedWords = local_ask_positive_integer('How many total words were presented?: ');
includePerturbation = local_ask_yes_no('Does this dataset include a perturbation/group variable? yes/no: ');
fprintf('  Presented words: %d\n', presentedWords);
fprintf('  Perturbation/group included: %s\n\n', local_yesno_text(includePerturbation));

%% Read source files
fprintf('Step 3/8: Reading source files...\n');

nMemoryFiles = local_ask_one_or_two('How many memory speed files should be used? Enter 1 or 2: ');
memoryTables = cell(nMemoryFiles, 1);
chosenSpeeds = NaN(nMemoryFiles, 1);

for iFile = 1:nMemoryFiles
    while true
        speedKmh = local_ask_positive_number(sprintf('What is the walking speed for memory file %d in km/h: ', iFile));
        if iFile > 1 && any(abs(chosenSpeeds(1:iFile-1) - speedKmh) < 1e-9)
            fprintf('That speed was already used for another memory file. Please enter a different speed.\n');
            continue;
        end
        chosenSpeeds(iFile) = speedKmh;
        break;
    end
    speedText = local_format_speed_label(speedKmh);

    memoryFile = local_resolve_file( ...
        fullfile(dataRawDir, "FastWords_recall_Speed" + speedText + ".xlsx"), ...
        sprintf('Select FastWords memory file %d', iFile));

    memorySpeedLabel = "Speed" + speedText + "KMH";
    memoryWalkSegment = "FWW_" + speedText + "KMH";

    memoryTables{iFile} = local_read_memory_file(memoryFile, memorySpeedLabel, memoryWalkSegment, false);

    fprintf('  Memory file %d: %s\n', iFile, memoryFile);
    fprintf('    Speed label:  %s\n', memorySpeedLabel);
    fprintf('    Walk segment: %s\n', memoryWalkSegment);
    fprintf('    Rows:         %d\n', height(memoryTables{iFile}));
end

memoryData = vertcat(memoryTables{:});
hvgRaw = local_read_table_preserve_names(hvgFile);

fprintf('  Combined memory rows: %d\n', height(memoryData));
fprintf('  HRV-gait raw rows:    %d\n\n', height(hvgRaw));

%% Detect and select HRV / gait predictors
fprintf('Step 4/8: Detecting candidate predictors...\n\n');

[hrvCandidates, hrvMissing, hrvOther] = local_detect_hrv_candidates(hvgRaw);
[gaitCandidates, gaitMissing, gaitOther] = local_detect_gait_candidates(hvgRaw);

fprintf('Detected HRV candidates from the predefined HRV pool:\n');
local_print_candidate_table(hrvCandidates);
local_print_missing_list('HRV pool items not detected', hrvMissing);
local_print_possible_other('Other HRV-like columns not auto-selected', hrvOther);

[selectedHRV, selectedHRVCanonical] = local_select_predictors(hrvCandidates, 5, 'HRV');
fprintf('\nSelected HRV predictors: %s\n', local_join_or_none(selectedHRV));
selectedHRVInputScale = local_get_selected_hrv_input_scale(hrvCandidates, selectedHRV);
selectedHRVTransforms = local_default_hrv_transforms(selectedHRVCanonical, selectedHRVInputScale);
fprintf('HRV preprocessing (automatic): %s\n\n', local_format_hrv_preprocessing(selectedHRV, selectedHRVTransforms));

fprintf('Detected gait candidates from the predefined gait pool:\n');
local_print_candidate_table(gaitCandidates);
local_print_missing_list('Gait pool items not detected', gaitMissing);
local_print_possible_other('Other gait-like columns not auto-selected', gaitOther);

[selectedGait, selectedGaitCanonical] = local_select_predictors(gaitCandidates, 5, 'gait');
fprintf('\nSelected gait predictors: %s\n\n', local_join_or_none(selectedGait));

%% Build merged analysis-ready table
fprintf('Step 5/8: Building memory-HRV-gait analysis-ready table...\n');

[mergedData, qcSummary] = local_build_memory_hvg_table( ...
    memoryData, hvgRaw, presentedWords, includePerturbation, ...
    selectedHRV, selectedGait, selectedHRVCanonical, selectedGaitCanonical, selectedHRVTransforms);

fprintf('  Merged analysis-ready rows: %d\n', height(mergedData));
fprintf('  Participants in merged data: %d\n', numel(unique(string(mergedData.participant_id))));
fprintf('  Walking segments retained: %s\n', strjoin(unique(string(mergedData.walk_segment)), ', '));
fprintf('  Rest conditions retained: %s\n\n', strjoin(unique(string(mergedData.rest_condition)), ', '));

%% Fit GLMM models
fprintf('Step 6/8: Fitting binomial GLMM models...\n');
fprintf('  This may take a while depending on the number of selected predictors.\n\n');

successVar = "Correct";
outcomes = struct([]);
outcomes(1).type = "RecallPerformance";
outcomes(1).denominator = "Presented_Words";
outcomes(2).type = "RecallPrecision";
outcomes(2).denominator = "Total_Recalled";

resultFields = [ ...
    "RecallPerformance_HRV", ...
    "RecallPerformance_GAIT", ...
    "RecallPerformance_HRV_GAIT", ...
    "RecallPrecision_HRV", ...
    "RecallPrecision_GAIT", ...
    "RecallPrecision_HRV_GAIT" ...
];

results = struct();
for iField = 1:numel(resultFields)
    results.(char(resultFields(iField))) = table();
end

restLevels = unique(string(mergedData.rest_condition), 'stable');

% Gait-only models should not be triplicated across EO1/EC/EO2.
% The source table usually repeats gait values once for each rest condition.
% For gait-only models, we collapse to unique participant x FW-segment rows.
gaitModelData = local_make_gait_model_table(mergedData, selectedGait, includePerturbation);

for iOutcome = 1:numel(outcomes)
    outcomeType = outcomes(iOutcome).type;
    denominatorVar = outcomes(iOutcome).denominator;

    %% HRV-only models: run separately by rest condition
    hrvField = char(outcomeType + "_HRV");
    if isempty(selectedHRV)
        results.(hrvField) = local_fit_binomial_glmm( ...
            table(), outcomeType, successVar, denominatorVar, "Memory-HRV", "", "", ...
            includePerturbation, "not_run", "Skipped: no HRV predictors were selected.");
    else
        for iRest = 1:numel(restLevels)
            restLabel = restLevels(iRest);
            Trest = mergedData(string(mergedData.rest_condition) == restLabel, :);
            for iH = 1:numel(selectedHRV)
                R = local_fit_binomial_glmm( ...
                    Trest, outcomeType, successVar, denominatorVar, "Memory-HRV", selectedHRV(iH), "", ...
                    includePerturbation, restLabel, "");
                results.(hrvField) = local_append_table(results.(hrvField), R);
            end
        end
    end

    %% Gait-only models: one deduplicated FW table, no rest-condition triplication
    gaitField = char(outcomeType + "_GAIT");
    if isempty(selectedGait)
        results.(gaitField) = local_fit_binomial_glmm( ...
            table(), outcomeType, successVar, denominatorVar, "Memory-Gait", "", "", ...
            includePerturbation, "not_run", "Skipped: no gait predictors were selected.");
    else
        for iG = 1:numel(selectedGait)
            R = local_fit_binomial_glmm( ...
                gaitModelData, outcomeType, successVar, denominatorVar, "Memory-Gait", "", selectedGait(iG), ...
                includePerturbation, "all_FW_no_HRV", "");
            results.(gaitField) = local_append_table(results.(gaitField), R);
        end
    end

    %% HRV + Gait models: run separately by rest condition
    combinedField = char(outcomeType + "_HRV_GAIT");
    if isempty(selectedHRV) || isempty(selectedGait)
        if isempty(selectedHRV) && isempty(selectedGait)
            skipMsg = "Skipped: no HRV or gait predictors were selected.";
        elseif isempty(selectedHRV)
            skipMsg = "Skipped: no HRV predictors were selected, so HRV-Gait models cannot be fitted.";
        else
            skipMsg = "Skipped: no gait predictors were selected, so HRV-Gait models cannot be fitted.";
        end
        results.(combinedField) = local_fit_binomial_glmm( ...
            table(), outcomeType, successVar, denominatorVar, "Memory-HRV-Gait", "", "", ...
            includePerturbation, "not_run", skipMsg);
    else
        for iRest = 1:numel(restLevels)
            restLabel = restLevels(iRest);
            Trest = mergedData(string(mergedData.rest_condition) == restLabel, :);
            for iH = 1:numel(selectedHRV)
                for iG = 1:numel(selectedGait)
                    R = local_fit_binomial_glmm( ...
                        Trest, outcomeType, successVar, denominatorVar, "Memory-HRV-Gait", selectedHRV(iH), selectedGait(iG), ...
                        includePerturbation, restLabel, "");
                    results.(combinedField) = local_append_table(results.(combinedField), R);
                end
            end
        end
    end
end

%% FDR correction
fprintf('Step 7/8: Applying Benjamini-Hochberg FDR correction...\n');
for iField = 1:numel(resultFields)
    f = char(resultFields(iField));
    results.(f) = local_bh_fdr(results.(f));
end
fprintf('  FDR correction applied separately within each result family.\n\n');

%% Write outputs
fprintf('Step 8/8: Writing output files...\n');
outputPaths = local_write_memory_report( ...
    mergedData, qcSummary, results, outputBaseDir, "accuracy", ...
    selectedHRV, selectedGait, selectedHRVTransforms, presentedWords, includePerturbation);

%% Command-window summary
fprintf('\n============================================================\n');
fprintf(' PIPELINE FINISHED\n');
fprintf('============================================================\n');
fprintf('Analysis-ready data:\n  %s\n', outputPaths.mergedFile);
fprintf('QC summary:\n  %s\n', outputPaths.qcFile);
fprintf('Excel report:\n  %s\n', outputPaths.excelReport);
fprintf('\nSelected HRV predictors:  %s\n', local_join_or_none(selectedHRV));
fprintf('HRV preprocessing:        %s\n', local_format_hrv_preprocessing(selectedHRV, selectedHRVTransforms));
fprintf('Selected gait predictors: %s\n', local_join_or_none(selectedGait));

nFailures = local_count_failures(results);
fprintf('Model rows with error/skip messages: %d\n', nFailures);
fprintf('Done.\n\n');

%% Local utility functions for this runner
function local_ensure_dir(folderPath)
    if ~exist(folderPath, 'dir')
        mkdir(folderPath);
    end
end

function filePath = local_resolve_file(defaultPath, dialogTitle)
    if exist(defaultPath, 'file')
        filePath = defaultPath;
        return;
    end

    fprintf('Default file not found:\n  %s\n', defaultPath);
    fprintf('Please select it manually.\n');

    try
        [fileName, folderName] = uigetfile({'*.xlsx;*.csv;*.txt', 'Data files (*.xlsx, *.csv, *.txt)'; '*.*', 'All files'}, dialogTitle);
        if isequal(fileName, 0)
            error('File selection cancelled.');
        end
        filePath = fullfile(folderName, fileName);
    catch ME
        error('Could not resolve input file. Details: %s', ME.message);
    end
end


function n = local_ask_one_or_two(promptText)
    while true
        raw = strtrim(input(promptText, 's'));
        n = str2double(raw);

        if isfinite(n) && ismember(n, [1 2])
            return;
        end

        fprintf('Please enter 1 or 2.\n');
    end
end

function x = local_ask_positive_number(promptText)
    while true
        raw = strtrim(input(promptText, 's'));
        x = str2double(raw);

        if isfinite(x) && x > 0
            return;
        end

        fprintf('Please enter a positive number, e.g., 1, 4, or 8.\n');
    end
end

function txt = local_format_speed_label(speedKmh)
    txt = string(sprintf('%.6g', speedKmh));
end

function n = local_ask_positive_integer(promptText)
    while true
        raw = strtrim(input(promptText, 's'));
        n = str2double(raw);
        if isfinite(n) && n > 0 && abs(n - round(n)) < eps
            n = round(n);
            return;
        end
        fprintf('Please enter a positive integer, e.g., 133.\n');
    end
end

function tf = local_ask_yes_no(promptText)
    while true
        raw = lower(strtrim(input(promptText, 's')));
        if any(strcmp(raw, {'yes', 'y', 'evet', 'e'}))
            tf = true;
            return;
        elseif any(strcmp(raw, {'no', 'n', 'hayir', 'hayır', 'h'}))
            tf = false;
            return;
        end
        fprintf('Please answer yes/no. Turkish answers evet/hayır also work.\n');
    end
end

function txt = local_yesno_text(tf)
    if tf
        txt = 'yes';
    else
        txt = 'no';
    end
end

function local_print_candidate_table(C)
    if isempty(C) || height(C) == 0
        fprintf('  No candidates detected. You may select 0 for this predictor family.\n');
        return;
    end
    for i = 1:height(C)
        fprintf('  %2d) %-22s -> %s\n', C.Index(i), C.CanonicalName(i), C.ColumnName(i));
    end
end

function local_print_missing_list(titleText, missingItems)
    if isempty(missingItems)
        fprintf('  %s: none\n', titleText);
    else
        fprintf('  %s: %s\n', titleText, strjoin(string(missingItems), ', '));
    end
end

function local_print_possible_other(titleText, otherTable)
    if isempty(otherTable) || height(otherTable) == 0
        fprintf('  %s: none\n\n', titleText);
        return;
    end
    fprintf('  %s:\n', titleText);
    for i = 1:height(otherTable)
        fprintf('    - %s\n', otherTable.ColumnName(i));
    end
    fprintf('\n');
end

function txt = local_join_or_none(x)
    x = string(x);
    if isempty(x)
        txt = 'none';
    else
        txt = strjoin(x, ', ');
    end
end

function inputScale = local_get_selected_hrv_input_scale(candidates, selectedHRV)
    selectedHRV = string(selectedHRV(:));
    inputScale = repmat("raw", numel(selectedHRV), 1);
    if isempty(selectedHRV) || ~ismember('InputScale', candidates.Properties.VariableNames)
        return;
    end
    for i = 1:numel(selectedHRV)
        idx = find(string(candidates.ColumnName) == selectedHRV(i), 1, 'first');
        if ~isempty(idx)
            inputScale(i) = string(candidates.InputScale(idx));
        end
    end
end

function transforms = local_default_hrv_transforms(selectedCanonical, inputScale)
    selectedCanonical = string(selectedCanonical(:));
    inputScale = lower(string(inputScale(:)));
    transforms = repmat("none", numel(selectedCanonical), 1);

    for i = 1:numel(selectedCanonical)
        % If the source is already z-standardized, preserve it as-is and do
        % not log or standardize it a second time.
        if inputScale(i) == "z" || inputScale(i) == "ln_z"
            transforms(i) = "asis";
            continue;
        end

        % If the source is already ln/log transformed, only z-standardize it.
        if inputScale(i) == "ln"
            transforms(i) = "none";
            continue;
        end

        % Raw-input defaults used by this pipeline: RMSSD and HF are
        % natural-log transformed before z-standardization; the remaining
        % common HRV measures are z-standardized on their supplied scale.
        if any(strcmpi(selectedCanonical(i), ["RMSSD", "HF"]))
            transforms(i) = "ln";
        else
            transforms(i) = "none";
        end
    end
end

function txt = local_format_hrv_preprocessing(selectedHRV, transforms)
    selectedHRV = string(selectedHRV(:));
    transforms = lower(string(transforms(:)));
    if isempty(selectedHRV)
        txt = 'none';
        return;
    end
    parts = strings(numel(selectedHRV), 1);
    for i = 1:numel(selectedHRV)
        if transforms(i) == "ln"
            parts(i) = selectedHRV(i) + "=ln->z";
        elseif transforms(i) == "asis"
            parts(i) = selectedHRV(i) + "=input-z(as-is)";
        else
            parts(i) = selectedHRV(i) + "=z";
        end
    end
    txt = strjoin(parts, '; ');
end

function T = local_make_gait_model_table(mergedData, selectedGait, includePerturbation)
    if isempty(selectedGait)
        T = table();
        return;
    end

    selectedGait = string(selectedGait);
    zGait = strings(size(selectedGait));
    for i = 1:numel(selectedGait)
        zGait(i) = string(matlab.lang.makeValidName("z_" + selectedGait(i)));
    end

    baseCols = ["participant_id", "speed", "memory_speed_label", "walk_segment", ...
                "Correct", "Intrusions", "Presented_Words", "Total_Recalled", ...
                "Recall_Performance", "Recall_Precision"];
    if includePerturbation && ismember('perturbation_group', mergedData.Properties.VariableNames)
        baseCols = [baseCols, "perturbation_group"];
    end

    cols = unique([baseCols, selectedGait(:).', zGait(:).'], 'stable');
    cols = cols(ismember(cols, string(mergedData.Properties.VariableNames)));
    T = unique(mergedData(:, cellstr(cols)), 'rows', 'stable');
    T.rest_condition = repmat("all_FW_no_HRV", height(T), 1);
end

function T = local_append_table(T, newRows)
    if isempty(T) || width(T) == 0
        T = newRows;
    else
        T = [T; newRows];
    end
end

function nFailures = local_count_failures(results)
    nFailures = 0;
    f = fieldnames(results);
    for i = 1:numel(f)
        T = results.(f{i});
        if istable(T) && height(T) > 0 && ismember('error_message', T.Properties.VariableNames)
            msg = string(T.error_message);
            nFailures = nFailures + sum(strlength(strtrim(msg)) > 0);
        end
    end
end
