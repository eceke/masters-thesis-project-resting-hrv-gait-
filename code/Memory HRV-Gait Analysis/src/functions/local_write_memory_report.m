function outputPaths = local_write_memory_report(mergedData, qcSummary, results, outputBaseDir, modeName, selectedHRV, selectedGait, selectedHRVTransforms, presentedWords, includePerturbation)
%LOCAL_WRITE_MEMORY_REPORT Write merged data, QC, CSV results, and Excel report.

selectedHRV = string(selectedHRV);
selectedGait = string(selectedGait);
selectedHRVTransforms = lower(string(selectedHRVTransforms));
modeName = string(modeName);

if isempty(selectedHRVTransforms)
    selectedHRVTransforms = repmat("none", numel(selectedHRV), 1);
end

mergedDir = fullfile(outputBaseDir, 'merged');
qcDir = fullfile(outputBaseDir, 'qc');
resultsDir = fullfile(outputBaseDir, 'results_csv');
reportsDir = fullfile(outputBaseDir, 'reports');

local_ensure_dir(mergedDir);
local_ensure_dir(qcDir);
local_ensure_dir(resultsDir);
local_ensure_dir(reportsDir);

mergedFile = fullfile(mergedDir, 'MEMORY_HRV_GAIT_accuracy_ready.csv');
qcFile = fullfile(qcDir, 'MEMORY_QC_summary.csv');
excelReport = fullfile(reportsDir, 'Memory_Accuracy_Analysis_Report.xlsx');

writetable(mergedData, mergedFile);
writetable(qcSummary, qcFile);

resultFiles = struct();
resultFields = fieldnames(results);
for i = 1:numel(resultFields)
    fieldName = resultFields{i};
    outFile = fullfile(resultsDir, ['MEMORY_' fieldName '_results.csv']);
    writetable(results.(fieldName), outFile);
    resultFiles.(fieldName) = outFile;
end

% Build overview sheet
modelRows = 0;
modelFailures = 0;
for i = 1:numel(resultFields)
    T = results.(resultFields{i});
    if istable(T)
        modelRows = modelRows + height(T);
        if height(T) > 0 && ismember('error_message', T.Properties.VariableNames)
            msg = string(T.error_message);
            modelFailures = modelFailures + sum(strlength(strtrim(msg)) > 0);
        end
    end
end

Metric = [ ...
    "mode"; ...
    "created_at"; ...
    "presented_words"; ...
    "perturbation_included"; ...
    "selected_hrv_predictors"; ...
    "hrv_preprocessing"; ...
    "selected_gait_predictors"; ...
    "merged_rows"; ...
    "merged_participants"; ...
    "merged_segments"; ...
    "merged_rest_conditions"; ...
    "result_rows_total"; ...
    "result_rows_with_error_or_skip" ...
];

Value = [ ...
    modeName; ...
    string(datetime('now')); ...
    string(presentedWords); ...
    string(includePerturbation); ...
    local_join_or_none(selectedHRV); ...
    local_format_hrv_preprocessing(selectedHRV, selectedHRVTransforms); ...
    local_join_or_none(selectedGait); ...
    string(height(mergedData)); ...
    string(numel(unique(string(mergedData.participant_id)))); ...
    strjoin(unique(string(mergedData.walk_segment), 'stable'), ', '); ...
    strjoin(unique(string(mergedData.rest_condition), 'stable'), ', '); ...
    string(modelRows); ...
    string(modelFailures) ...
];

overview = table(Metric, Value);

% Build failure table
failureTable = table();
for i = 1:numel(resultFields)
    T = results.(resultFields{i});
    if istable(T) && height(T) > 0 && ismember('error_message', T.Properties.VariableNames)
        msg = string(T.error_message);
        F = T(strlength(strtrim(msg)) > 0, :);
        if height(F) > 0
            F.result_family = repmat(string(resultFields{i}), height(F), 1);
            failureTable = local_append_table(failureTable, F);
        end
    end
end
if isempty(failureTable)
    failureTable = table("none", "No model failures or skips were recorded.", ...
        'VariableNames', {'status', 'message'});
end

% Write Excel workbook
if exist(excelReport, 'file')
    delete(excelReport);
end

writetable(overview, excelReport, 'Sheet', 'Overview');
writetable(qcSummary, excelReport, 'Sheet', 'Merged_Data_QC');

sheetMap = struct();
sheetMap.RecallPerformance_HRV = 'RecallPerformance_HRV';
sheetMap.RecallPerformance_GAIT = 'RecallPerformance_GAIT';
sheetMap.RecallPerformance_HRV_GAIT = 'RecallPerformance_HRV_GAIT';
sheetMap.RecallPrecision_HRV = 'RecallPrecision_HRV';
sheetMap.RecallPrecision_GAIT = 'RecallPrecision_GAIT';
sheetMap.RecallPrecision_HRV_GAIT = 'RecallPrecision_HRV_GAIT';

for i = 1:numel(resultFields)
    fieldName = resultFields{i};
    if isfield(sheetMap, fieldName)
        sheetName = sheetMap.(fieldName);
    else
        sheetName = fieldName;
    end
    writetable(results.(fieldName), excelReport, 'Sheet', sheetName);
end
writetable(failureTable, excelReport, 'Sheet', 'Model_Failures');

outputPaths = struct();
outputPaths.mergedFile = mergedFile;
outputPaths.qcFile = qcFile;
outputPaths.excelReport = excelReport;
outputPaths.resultFiles = resultFiles;
end

function T = local_append_table(T, newRows)
    if isempty(T) || width(T) == 0
        T = newRows;
    else
        T = [T; newRows];
    end
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
    if numel(transforms) ~= numel(selectedHRV)
        txt = "not recorded";
        return;
    end
    parts = strings(numel(selectedHRV), 1);
    for i = 1:numel(selectedHRV)
        if transforms(i) == "ln"
            parts(i) = selectedHRV(i) + "=ln->z";
        else
            parts(i) = selectedHRV(i) + "=z";
        end
    end
    txt = strjoin(parts, '; ');
end
