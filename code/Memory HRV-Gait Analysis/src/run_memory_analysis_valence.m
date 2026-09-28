%% run_memory_analysis_valence.m
% General valence recall pipeline for FastWords memory + HRV/gait data
% ------------------------------------------------------------
% This script reads FastWords recall files and an HRV-gait long CSV,
% builds an analysis-ready FW-only memory-HRV-gait table, converts memory
% recall into valence-long format, runs grouped-binomial GLMMs, applies
% Benjamini-Hochberg FDR correction, and writes CSV/XLSX outputs.
%
% Main analytical rules:
% - BW walking segments are never used for memory models.
% - User can select 1 or 2 memory speed files.
% - Gait-only and base valence models are deduplicated across rest conditions.
% - HRV and gait predictor selection allows 0 to 5 predictors each.
%
% The valence pipeline can produce three analysis modes. Mode 2 requires
% at least two speed levels and is not fitted for Base models.
%
%   MODE 1 (primary): speed is included when multiple levels are available.
%       Each model includes valence, predictors selected for its family,
%       optional perturbation group, and a participant random intercept.
%       Runs for Base, HRV, Gait, and HRV-Gait families.
%
%   MODE 2 (follow-up): does the HRV/gait-memory relationship itself
%       differ between 1 km/h and 4 km/h? This is answered by the
%       HRV:speed / gait:speed interaction term, NOT by comparing two
%       separately-fit models' p-values (that comparison is not a valid
%       test of difference). Runs for HRV/Gait/HRV-Gait (Base has no
%       predictor to interact with speed, so it is skipped for Mode 2).
%
%   OUTPUT 3 (share-of-correct): same combined structure as Mode 1, but
%       the outcome is valence_correct/valence_total_correct instead of
%       valence_correct/valence_presented -- i.e. "of what this
%       participant actually recalled, what share was positive/negative/
%       neutral?", instead of "of what was presented in this category,
%       how much was recalled?". See local_build_memory_valence_long.m
%       for the statistical caveat on this denominator (compositional/
%       multinomial-like data approximated with grouped-binomial GLMMs).
%
% Results from the modes that were run share the valenceResults table.
% The speed_model and denominator_type columns distinguish them. FDR
% correction is applied separately within each model_family x speed_model
% x denominator_type group.

clear; clc;

fprintf('\n============================================================\n');
fprintf(' MEMORY-HRV-GAIT VALENCE RECALL PIPELINE\n');
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
outputBaseDir = fullfile(projectRoot, 'outputs', 'valence');

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
fprintf('Step 1/9: Locating input files...\n');

hvgFile = local_resolve_file( ...
    fullfile(dataRawDir, 'LMM_HRV_GAIT_long.csv'), ...
    'Select LMM_HRV_GAIT_long.csv');

fprintf('  HRV-gait file:      %s\n\n', hvgFile);

%% User settings
fprintf('Step 2/9: Collecting user settings...\n');
positivePresented = local_ask_positive_integer('How many positive words were presented?: ');
negativePresented = local_ask_positive_integer('How many negative words were presented?: ');
neutralPresented  = local_ask_positive_integer('How many neutral words were presented?: ');
includePerturbation = local_ask_yes_no('Does this dataset include a perturbation/group variable? yes/no: ');

presentedWordsTotal = positivePresented + negativePresented + neutralPresented;
fprintf('  Positive presented: %d\n', positivePresented);
fprintf('  Negative presented: %d\n', negativePresented);
fprintf('  Neutral presented:  %d\n', neutralPresented);
fprintf('  Total presented:    %d\n', presentedWordsTotal);
fprintf('  Perturbation/group included: %s\n\n', local_yesno_text(includePerturbation));

%% Read source files
fprintf('Step 3/9: Reading source files...\n');

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

    memoryTables{iFile} = local_read_memory_file(memoryFile, memorySpeedLabel, memoryWalkSegment, true);

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
fprintf('Step 4/9: Detecting candidate predictors...\n\n');

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

%% Build FW-only merged table first, then valence-long table
fprintf('Step 5/9: Building FW-only memory-HRV-gait table...\n');

[valenceReadyData, qcBase] = local_build_memory_hvg_table( ...
    memoryData, hvgRaw, presentedWordsTotal, includePerturbation, ...
    selectedHRV, selectedGait, selectedHRVCanonical, selectedGaitCanonical, selectedHRVTransforms);

fprintf('  FW-only ready rows: %d\n', height(valenceReadyData));
fprintf('  Participants in ready data: %d\n', numel(unique(string(valenceReadyData.participant_id))));
fprintf('  Walking segments retained: %s\n', strjoin(unique(string(valenceReadyData.walk_segment)), ', '));
fprintf('  Rest conditions retained: %s\n\n', strjoin(unique(string(valenceReadyData.rest_condition)), ', '));

fprintf('Step 6/9: Building valence-long table...\n');
[valenceLong, qcValence] = local_build_memory_valence_long( ...
    valenceReadyData, memoryData, positivePresented, negativePresented, neutralPresented, ...
    includePerturbation, selectedHRV, selectedGait);

qcSummary = [qcBase; qcValence];

fprintf('  Valence-long rows: %d\n', height(valenceLong));
fprintf('  Valence categories: %s\n\n', strjoin(string(categories(valenceLong.valence)), ', '));

fprintf('Step 6b/9: Building raw per-participant valence summary...\n');
rawByParticipant = local_build_raw_valence_by_participant( ...
    memoryData, positivePresented, negativePresented, neutralPresented);
fprintf('  Raw valence summary rows (participants): %d\n\n', height(rawByParticipant));

%% Fit valence GLMM models
fprintf('Step 7/9: Fitting valence binomial GLMM models...\n');
fprintf('  This may take a while depending on the number of selected predictors.\n\n');

baseValenceData = local_make_base_valence_model_table(valenceLong, includePerturbation);
gaitValenceData = local_make_valence_gait_model_table(valenceLong, selectedGait, includePerturbation);
restLevels = unique(string(valenceLong.rest_condition), 'stable');

speedLevels = string(valenceLong.speed);
speedLevels = speedLevels(~ismissing(speedLevels) & strlength(strtrim(speedLevels)) > 0 & lower(speedLevels) ~= "nan");
speedLevels = unique(speedLevels, 'stable');
runModeTwo = numel(speedLevels) >= 2;
if isempty(speedLevels)
    speedLevelText = "none";
else
    speedLevelText = strjoin(speedLevels, ', ');
end
fprintf('  Speed levels available for valence models: %s\n', char(speedLevelText));

valenceResults = table();

% ---- MODE 1 (primary): speed as covariate, presented-word denominator ----
fprintf('  Mode 1/3 - primary analysis (speed as covariate, valence_correct/valence_presented)...\n');
modeOneResults = local_run_all_families( ...
    valenceLong, baseValenceData, gaitValenceData, selectedHRV, selectedGait, restLevels, includePerturbation, ...
    "ValenceRecall", "valence_presented", "PresentedWords", false, true);
valenceResults = local_append_table(valenceResults, modeOneResults);
fprintf('    Mode 1 result rows: %d\n', height(modeOneResults));

% ---- MODE 2 (follow-up): HRV/gait x speed interaction, presented-word denominator ----
if runModeTwo
    fprintf('  Mode 2/3 - does the HRV/gait-memory relationship differ by speed (interaction)...\n');
    modeTwoResults = local_run_all_families( ...
        valenceLong, baseValenceData, gaitValenceData, selectedHRV, selectedGait, restLevels, includePerturbation, ...
        "ValenceRecall", "valence_presented", "PresentedWords", true, false);
    valenceResults = local_append_table(valenceResults, modeTwoResults);
    fprintf('    Mode 2 result rows: %d\n', height(modeTwoResults));
else
    modeTwoResults = table();
    fprintf('  Mode 2/3 - skipped because only one speed level is available (%s). No Mode 2 output rows will be written.\n', char(speedLevelText));
end

% ---- OUTPUT 3: share-of-correct denominator, Mode-1-style (no interaction) ----
fprintf('  Output 3/3 - share of correctly recalled words by valence (valence_correct/valence_total_correct)...\n');
outputThreeResults = local_run_all_families( ...
    valenceLong, baseValenceData, gaitValenceData, selectedHRV, selectedGait, restLevels, includePerturbation, ...
    "ValenceShareOfCorrect", "valence_total_correct", "ShareOfCorrect", false, true);
valenceResults = local_append_table(valenceResults, outputThreeResults);
fprintf('    Output 3 result rows: %d\n\n', height(outputThreeResults));

%% FDR correction
fprintf('Step 8/9: Applying Benjamini-Hochberg FDR correction...\n');
valenceResults = local_apply_fdr_by_model_family(valenceResults);
fprintf('  FDR correction applied separately within each (model_family x speed_model x denominator_type) group.\n\n');

%% Write outputs
fprintf('Step 9/9: Writing output files...\n');
outputPaths = local_write_valence_report( ...
    valenceReadyData, valenceLong, qcSummary, valenceResults, rawByParticipant, outputBaseDir, ...
    selectedHRV, selectedGait, selectedHRVTransforms, positivePresented, negativePresented, neutralPresented, includePerturbation);

%% Command-window summary
fprintf('\n============================================================\n');
fprintf(' VALENCE PIPELINE FINISHED\n');
fprintf('============================================================\n');
fprintf('Valence-ready data:\n  %s\n', outputPaths.valenceReadyFile);
fprintf('Valence-long data:\n  %s\n', outputPaths.valenceLongFile);
fprintf('QC summary:\n  %s\n', outputPaths.qcFile);
fprintf('Valence results:\n  %s\n', outputPaths.resultsFile);
fprintf('Raw per-participant valence summary:\n  %s\n', outputPaths.rawByParticipantFile);
fprintf('Excel report:\n  %s\n', outputPaths.excelReport);
fprintf('\nSelected HRV predictors:  %s\n', local_join_or_none(selectedHRV));
fprintf('HRV preprocessing:        %s\n', local_format_hrv_preprocessing(selectedHRV, selectedHRVTransforms));
fprintf('Selected gait predictors: %s\n', local_join_or_none(selectedGait));

nFailures = local_count_failures(valenceResults);
fprintf('Model rows with error/skip messages (all modes combined): %d\n', nFailures);
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
        fprintf('Please enter a positive integer.\n');
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
        % Already z-standardized input: use as-is, without another log/z.
        if inputScale(i) == "z" || inputScale(i) == "ln_z"
            transforms(i) = "asis";
            continue;
        end

        % Already log-transformed input: only z-standardize it.
        if inputScale(i) == "ln"
            transforms(i) = "none";
            continue;
        end

        % Automatic defaults for raw HRV input.
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

function T = local_make_base_valence_model_table(valenceLong, includePerturbation)
    baseCols = ["participant_id", "speed", "memory_speed_label", "walk_segment", ...
                "valence", "valence_correct", ...
                "valence_presented", "valence_recall_rate", ...
                "valence_total_correct", "valence_share_of_correct"];
    if includePerturbation && ismember('perturbation_group', valenceLong.Properties.VariableNames)
        baseCols = [baseCols, "perturbation_group"];
    end
    cols = baseCols(ismember(baseCols, string(valenceLong.Properties.VariableNames)));
    T = unique(valenceLong(:, cellstr(cols)), 'rows', 'stable');
    T.rest_condition = repmat("all_FW_no_HRV", height(T), 1);
end

function T = local_make_valence_gait_model_table(valenceLong, selectedGait, includePerturbation)
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
                "valence", "valence_correct", ...
                "valence_presented", "valence_recall_rate", ...
                "valence_total_correct", "valence_share_of_correct"];
    if includePerturbation && ismember('perturbation_group', valenceLong.Properties.VariableNames)
        baseCols = [baseCols, "perturbation_group"];
    end

    cols = unique([baseCols, selectedGait(:).', zGait(:).'], 'stable');
    cols = cols(ismember(cols, string(valenceLong.Properties.VariableNames)));
    T = unique(valenceLong(:, cellstr(cols)), 'rows', 'stable');
    T.rest_condition = repmat("all_FW_no_HRV", height(T), 1);
end

function results = local_run_all_families(valenceLong, baseValenceData, gaitValenceData, selectedHRV, selectedGait, restLevels, includePerturbation, outcomeType, denominatorVar, denominatorLabel, useSpeedInteraction, includeBase)
%LOCAL_RUN_ALL_FAMILIES Fit valence model families for one denominator
% and speed-model combination. Called for Mode 1 and Output 3, and for
% Mode 2 when at least two speed levels are available. The Base family
% is omitted from Mode 2.

successVar = "valence_correct";
results = table();

% --- Base family: not triplicated across rest condition, no interaction
%     (there is no HRV/gait predictor in the base model to interact with
%     speed, so includeBase is only ever called with useSpeedInteraction = false
%     by the three call sites above).
if includeBase
    R = local_fit_valence_binomial_glmm( ...
        baseValenceData, outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-Base", "", "", ...
        includePerturbation, "all_FW_no_HRV", false, "");
    results = local_append_table(results, R);
end

% --- HRV family: separate by rest condition ---
if isempty(selectedHRV)
    R = local_fit_valence_binomial_glmm( ...
        table(), outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-HRV", "", "", ...
        includePerturbation, "not_run", useSpeedInteraction, "Skipped: no HRV predictors were selected.");
    results = local_append_table(results, R);
else
    for iRest = 1:numel(restLevels)
        restLabel = restLevels(iRest);
        Trest = valenceLong(string(valenceLong.rest_condition) == restLabel, :);
        for iH = 1:numel(selectedHRV)
            R = local_fit_valence_binomial_glmm( ...
                Trest, outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-HRV", selectedHRV(iH), "", ...
                includePerturbation, restLabel, useSpeedInteraction, "");
            results = local_append_table(results, R);
        end
    end
end

% --- Gait family: not triplicated across rest condition ---
if isempty(selectedGait)
    R = local_fit_valence_binomial_glmm( ...
        table(), outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-Gait", "", "", ...
        includePerturbation, "not_run", useSpeedInteraction, "Skipped: no gait predictors were selected.");
    results = local_append_table(results, R);
else
    for iG = 1:numel(selectedGait)
        R = local_fit_valence_binomial_glmm( ...
            gaitValenceData, outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-Gait", "", selectedGait(iG), ...
            includePerturbation, "all_FW_no_HRV", useSpeedInteraction, "");
        results = local_append_table(results, R);
    end
end

% --- HRV-Gait family: separate by rest condition ---
if isempty(selectedHRV) || isempty(selectedGait)
    if isempty(selectedHRV) && isempty(selectedGait)
        skipMsg = "Skipped: no HRV or gait predictors were selected.";
    elseif isempty(selectedHRV)
        skipMsg = "Skipped: no HRV predictors were selected, so Valence-HRV-Gait models cannot be fitted.";
    else
        skipMsg = "Skipped: no gait predictors were selected, so Valence-HRV-Gait models cannot be fitted.";
    end
    R = local_fit_valence_binomial_glmm( ...
        table(), outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-HRV-Gait", "", "", ...
        includePerturbation, "not_run", useSpeedInteraction, skipMsg);
    results = local_append_table(results, R);
else
    for iRest = 1:numel(restLevels)
        restLabel = restLevels(iRest);
        Trest = valenceLong(string(valenceLong.rest_condition) == restLabel, :);
        for iH = 1:numel(selectedHRV)
            for iG = 1:numel(selectedGait)
                R = local_fit_valence_binomial_glmm( ...
                    Trest, outcomeType, successVar, denominatorVar, denominatorLabel, "Valence-HRV-Gait", selectedHRV(iH), selectedGait(iG), ...
                    includePerturbation, restLabel, useSpeedInteraction, "");
                results = local_append_table(results, R);
            end
        end
    end
end
end

function T = local_append_table(T, newRows)
    if isempty(T) || width(T) == 0
        T = newRows;
    else
        T = [T; newRows];
    end
end

function T = local_apply_fdr_by_model_family(T)
% Groups rows for Benjamini-Hochberg correction by the combination of
% model_family, speed_model, and denominator_type (when present), so
% Mode 1 / Mode 2 / Output 3 results never share a correction family.
% Falls back to model_family alone (or no grouping) for older-style
% result tables that lack the new columns.
    if isempty(T) || height(T) == 0 || ~ismember('model_family', T.Properties.VariableNames)
        T = local_bh_fdr(T);
        return;
    end

    if ~ismember('p_FDR', T.Properties.VariableNames)
        T.p_FDR = NaN(height(T), 1);
    else
        T.p_FDR(:) = NaN;
    end

    groupKey = string(T.model_family);
    if ismember('speed_model', T.Properties.VariableNames)
        groupKey = groupKey + "|" + string(T.speed_model);
    end
    if ismember('denominator_type', T.Properties.VariableNames)
        groupKey = groupKey + "|" + string(T.denominator_type);
    end

    groups = unique(groupKey, 'stable');
    for i = 1:numel(groups)
        idx = groupKey == groups(i);
        subT = local_bh_fdr(T(idx, :));
        if ismember('p_FDR', subT.Properties.VariableNames)
            T.p_FDR(idx) = subT.p_FDR;
        end
    end
end

function nFailures = local_count_failures(T)
    nFailures = 0;
    if istable(T) && height(T) > 0 && ismember('error_message', T.Properties.VariableNames)
        msg = string(T.error_message);
        nFailures = sum(strlength(strtrim(msg)) > 0);
    end
end
