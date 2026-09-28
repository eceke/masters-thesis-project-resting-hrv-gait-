function outputPaths = local_write_valence_report(valenceReadyData, valenceLong, qcSummary, valenceResults, rawByParticipant, outputBaseDir, selectedHRV, selectedGait, selectedHRVTransforms, positivePresented, negativePresented, neutralPresented, includePerturbation)
%LOCAL_WRITE_VALENCE_REPORT Write valence-mode CSV and Excel outputs.
%
% valenceResults contains results for the modes that were run, identified
% by the speed_model and denominator_type columns:
%   Mode 1  : speed_model == "Mode1_SpeedCovariate", denominator_type == "PresentedWords"
%   Mode 2  : speed_model == "Mode2_SpeedInteraction", denominator_type == "PresentedWords"
%   Output 3: speed_model == "Mode1_SpeedCovariate", denominator_type == "ShareOfCorrect"


selectedHRV = string(selectedHRV);
selectedGait = string(selectedGait);
selectedHRVTransforms = string(selectedHRVTransforms);

mergedDir = fullfile(outputBaseDir, 'merged');
qcDir = fullfile(outputBaseDir, 'qc');
resultsDir = fullfile(outputBaseDir, 'results_csv');
reportsDir = fullfile(outputBaseDir, 'reports');

local_ensure_dir(mergedDir);
local_ensure_dir(qcDir);
local_ensure_dir(resultsDir);
local_ensure_dir(reportsDir);

valenceReadyFile = fullfile(mergedDir, 'MEMORY_HRV_GAIT_valence_ready.csv');
valenceLongFile = fullfile(mergedDir, 'MEMORY_valence_long.csv');
qcFile = fullfile(qcDir, 'MEMORY_QC_summary.csv');
resultsFile = fullfile(resultsDir, 'MEMORY_Valence_results.csv');
rawByParticipantFile = fullfile(resultsDir, 'MEMORY_RawValence_ByParticipant.csv');
excelReport = fullfile(reportsDir, 'Memory_General_Valence_Report.xlsx');

writetable(valenceReadyData, valenceReadyFile);
writetable(valenceLong, valenceLongFile);
writetable(qcSummary, qcFile);
writetable(valenceResults, resultsFile);
writetable(rawByParticipant, rawByParticipantFile);

hasSpeedModel = ismember('speed_model', valenceResults.Properties.VariableNames);
hasDenomType = ismember('denominator_type', valenceResults.Properties.VariableNames);

modelRows = height(valenceResults);
modelFailures = local_count_failures(valenceResults);

[mode1Rows, mode1Failures] = local_subset_count(valenceResults, hasSpeedModel, hasDenomType, "Mode1_SpeedCovariate", "PresentedWords");
[mode2Rows, mode2Failures] = local_subset_count(valenceResults, hasSpeedModel, hasDenomType, "Mode2_SpeedInteraction", "PresentedWords");
[output3Rows, output3Failures] = local_subset_count(valenceResults, hasSpeedModel, hasDenomType, "Mode1_SpeedCovariate", "ShareOfCorrect");

Metric = [ ...
    "mode"; ...
    "created_at"; ...
    "positive_presented"; ...
    "negative_presented"; ...
    "neutral_presented"; ...
    "total_presented"; ...
    "perturbation_included"; ...
    "selected_hrv_predictors"; ...
    "hrv_preprocessing"; ...
    "selected_gait_predictors"; ...
    "valence_ready_rows"; ...
    "valence_long_rows"; ...
    "participants"; ...
    "walking_segments"; ...
    "rest_conditions"; ...
    "result_rows_total"; ...
    "result_rows_with_error_or_skip"; ...
    "mode1_speed_covariate_presented_rows"; ...
    "mode1_speed_covariate_presented_failures"; ...
    "mode2_speed_interaction_presented_rows"; ...
    "mode2_speed_interaction_presented_failures"; ...
    "output3_share_of_correct_rows"; ...
    "output3_share_of_correct_failures" ...
];

Value = [ ...
    "valence"; ...
    string(datetime('now')); ...
    string(positivePresented); ...
    string(negativePresented); ...
    string(neutralPresented); ...
    string(positivePresented + negativePresented + neutralPresented); ...
    string(includePerturbation); ...
    local_join_or_none(selectedHRV); ...
    local_format_hrv_preprocessing(selectedHRV, selectedHRVTransforms); ...
    local_join_or_none(selectedGait); ...
    string(height(valenceReadyData)); ...
    string(height(valenceLong)); ...
    string(numel(unique(string(valenceLong.participant_id)))); ...
    strjoin(unique(string(valenceLong.walk_segment), 'stable'), ', '); ...
    strjoin(unique(string(valenceLong.rest_condition), 'stable'), ', '); ...
    string(modelRows); ...
    string(modelFailures); ...
    string(mode1Rows); ...
    string(mode1Failures); ...
    string(mode2Rows); ...
    string(mode2Failures); ...
    string(output3Rows); ...
    string(output3Failures) ...
];

overview = table(Metric, Value);

failureTable = table();
if height(valenceResults) > 0 && ismember('error_message', valenceResults.Properties.VariableNames)
    msg = string(valenceResults.error_message);
    failureTable = valenceResults(strlength(strtrim(msg)) > 0, :);
end
if isempty(failureTable)
    failureTable = table("none", "No model failures or skips were recorded.", ...
        'VariableNames', {'status', 'message'});
end

if exist(excelReport, 'file')
    delete(excelReport);
end

writetable(overview, excelReport, 'Sheet', 'Overview');
writetable(qcSummary, excelReport, 'Sheet', 'Merged_Data_QC');

% --- Split valenceResults into sheets ---
% Sheet names kept short (Excel's 31-character limit):
%   M1-*   = Mode 1, speed as covariate, presented-word denominator (primary)
%   M2-*   = Mode 2, HRV/gait x speed interaction, presented-word denominator
%   O3-*   = Output 3, share-of-correct denominator (Mode-1-style, no interaction)
if hasSpeedModel && hasDenomType
    hasMode2Rows = any(string(valenceResults.speed_model) == "Mode2_SpeedInteraction");

    sheetSpecs = { ...
        "Mode1_SpeedCovariate",   "PresentedWords", "Valence-Base",     "M1-Base"; ...
        "Mode1_SpeedCovariate",   "PresentedWords", "Valence-HRV",      "M1-HRV"; ...
        "Mode1_SpeedCovariate",   "PresentedWords", "Valence-Gait",     "M1-Gait"; ...
        "Mode1_SpeedCovariate",   "PresentedWords", "Valence-HRV-Gait", "M1-HRVGait"; ...
        "Mode2_SpeedInteraction", "PresentedWords", "Valence-HRV",      "M2-HRV"; ...
        "Mode2_SpeedInteraction", "PresentedWords", "Valence-Gait",     "M2-Gait"; ...
        "Mode2_SpeedInteraction", "PresentedWords", "Valence-HRV-Gait", "M2-HRVGait"; ...
        "Mode1_SpeedCovariate",   "ShareOfCorrect",  "Valence-Base",     "O3-Base"; ...
        "Mode1_SpeedCovariate",   "ShareOfCorrect",  "Valence-HRV",      "O3-HRV"; ...
        "Mode1_SpeedCovariate",   "ShareOfCorrect",  "Valence-Gait",     "O3-Gait"; ...
        "Mode1_SpeedCovariate",   "ShareOfCorrect",  "Valence-HRV-Gait", "O3-HRVGait"; ...
    };

    coveredMask = false(height(valenceResults), 1);
    for i = 1:size(sheetSpecs, 1)
        speedModelVal = sheetSpecs{i, 1};
        denomTypeVal = sheetSpecs{i, 2};
        famVal = sheetSpecs{i, 3};
        sheetName = sheetSpecs{i, 4};

        rowMask = string(valenceResults.speed_model) == speedModelVal & ...
                  string(valenceResults.denominator_type) == denomTypeVal & ...
                  string(valenceResults.model_family) == famVal;
        coveredMask = coveredMask | rowMask;

        % If the dataset has only one speed level, Mode 2 is not run at all.
        % In that case, do not create empty M2 sheets in the Excel report.
        if string(speedModelVal) == "Mode2_SpeedInteraction" && ~hasMode2Rows
            continue;
        end

        subT = valenceResults(rowMask, :);
        if height(subT) == 0
            subT = valenceResults(1:0, :); % keep same columns, zero rows
        end
        writetable(subT, excelReport, 'Sheet', sheetName);
    end

    % Safety net: any rows not matched by the explicit specs above still get written out under an auto-generated sheet name, rather than being silently dropped.
    leftover = valenceResults(~coveredMask, :);
    if height(leftover) > 0
        leftoverKeys = unique(string(leftover.speed_model) + "|" + string(leftover.denominator_type) + "|" + string(leftover.model_family), 'stable');
        for i = 1:numel(leftoverKeys)
            parts = string(strsplit(leftoverKeys(i), "|"));
            rowMask = string(leftover.speed_model) == parts(1) & ...
                      string(leftover.denominator_type) == parts(2) & ...
                      string(leftover.model_family) == parts(3);
            subT = leftover(rowMask, :);
            sheetName = char(matlab.lang.makeValidName("X-" + strrep(parts(3), '-', '_') + "-" + parts(1) + "-" + parts(2)));
            sheetName = sheetName(1:min(31, numel(sheetName)));
            writetable(subT, excelReport, 'Sheet', sheetName);
        end
    end
else
    % Backward-compatible fallback: split by model_family only, exactly as the original (pre speed-model/denominator-type) version did.
    familySheetMap = struct( ...
        'Valence_Base', "Valence-Base", ...
        'Valence_HRV', "Valence-HRV", ...
        'Valence_Gait', "Valence-Gait", ...
        'Valence_HRV_GAIT', "Valence-HRV-Gait");

    familySheetNames = fieldnames(familySheetMap);
    coveredFamilies = strings(0, 1);
    for i = 1:numel(familySheetNames)
        sheetName = familySheetNames{i};
        famValue = familySheetMap.(sheetName);
        coveredFamilies(end+1, 1) = famValue; %#ok<AGROW>
        subT = valenceResults(string(valenceResults.model_family) == famValue, :);
        if height(subT) == 0
            subT = valenceResults(1:0, :);
        end
        writetable(subT, excelReport, 'Sheet', sheetName);
    end

    allFamilies = unique(string(valenceResults.model_family), 'stable');
    leftoverFamilies = setdiff(allFamilies, coveredFamilies, 'stable');
    for i = 1:numel(leftoverFamilies)
        fam = leftoverFamilies(i);
        sheetName = char(matlab.lang.makeValidName(strrep(fam, '-', '_')));
        subT = valenceResults(string(valenceResults.model_family) == fam, :);
        writetable(subT, excelReport, 'Sheet', sheetName);
    end
end

% rawByParticipant already contains both. So a single sheet covers both denominator views -- no need to duplicate it.
writetable(rawByParticipant, excelReport, 'Sheet', 'Raw_Valence_ByParticipant');
writetable(failureTable, excelReport, 'Sheet', 'Model_Failures');

outputPaths = struct();
outputPaths.valenceReadyFile = valenceReadyFile;
outputPaths.valenceLongFile = valenceLongFile;
outputPaths.qcFile = qcFile;
outputPaths.resultsFile = resultsFile;
outputPaths.rawByParticipantFile = rawByParticipantFile;
outputPaths.excelReport = excelReport;
end

function local_ensure_dir(folderPath)
    if ~exist(folderPath, 'dir')
        mkdir(folderPath);
    end
end

function txt = local_join_or_none(x)
    x = string(x);
    if isempty(x)
        txt = "none";
    else
        txt = strjoin(x, ', ');
    end
end

function txt = local_format_hrv_preprocessing(selectedHRV, transforms)
    selectedHRV = string(selectedHRV(:));
    transforms = lower(string(transforms(:)));
    if isempty(selectedHRV)
        txt = "none";
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

function n = local_count_failures(T)
    n = 0;
    if istable(T) && height(T) > 0 && ismember('error_message', T.Properties.VariableNames)
        msg = string(T.error_message);
        n = sum(strlength(strtrim(msg)) > 0);
    end
end

function [n, nFail] = local_subset_count(T, hasSpeedModel, hasDenomType, speedModelVal, denomTypeVal)
    n = 0;
    nFail = 0;
    if ~hasSpeedModel || ~hasDenomType || height(T) == 0
        return;
    end
    mask = string(T.speed_model) == speedModelVal & string(T.denominator_type) == denomTypeVal;
    subT = T(mask, :);
    n = height(subT);
    nFail = local_count_failures(subT);
end
