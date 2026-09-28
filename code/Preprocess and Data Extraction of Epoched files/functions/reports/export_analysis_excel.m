function export_analysis_excel(cfg, merged_table)
%EXPORT_ANALYSIS_EXCEL Create readable multi-sheet Excel report.

output_file = fullfile(cfg.paths.features_root, 'Analysis_Report.xlsx');

if isfile(output_file)
    delete(output_file);
end

T = merged_table;

%% Base columns
base_cols = {'participant_id','segment_name','segment_type','kinesis_condition'};
base_cols = base_cols(ismember(base_cols, T.Properties.VariableNames));

%% Helper
get_cols = @(pattern) T.Properties.VariableNames(startsWith(T.Properties.VariableNames, pattern));

%% -------------------------
% 1. Overview
overview = unique(T(:, base_cols), 'rows', 'stable');
writetable(overview, output_file, 'Sheet', 'Overview');

%% -------------------------
% 2. Heart ECG
cols = [base_cols, get_cols('heart_ecg_')];
cols = cols(ismember(cols, T.Properties.VariableNames));
writetable(T(:, cols), output_file, 'Sheet', 'Heart_ECG');

%% -------------------------
% 3. Heart HR Live
cols = [base_cols, get_cols('heart_hr_live_')];
cols = cols(ismember(cols, T.Properties.VariableNames));
writetable(T(:, cols), output_file, 'Sheet', 'Heart_HR_Live');

%% -------------------------
% 4. Heart NN
cols = [base_cols, get_cols('heart_nn_live_')];
cols = cols(ismember(cols, T.Properties.VariableNames));
writetable(T(:, cols), output_file, 'Sheet', 'Heart_NN');

%% -------------------------
% 5. Heart Other
cols = [base_cols, get_cols('heart_temp_'), get_cols('heart_acc_'), get_cols('heart_angularrate_')];
cols = unique(cols, 'stable');
cols = cols(ismember(cols, T.Properties.VariableNames));

writetable(T(:, cols), output_file, 'Sheet', 'Heart_Other');

%% -------------------------
% 6. Hip Motion
cols = [base_cols, get_cols('hip_acc_'), get_cols('hip_angularrate_'), ...
        get_cols('hip_movementacceleration_'), get_cols('hip_stepcount_')];

cols = unique(cols, 'stable');
cols = cols(ismember(cols, T.Properties.VariableNames));

writetable(T(:, cols), output_file, 'Sheet', 'Hip_Motion');

%% -------------------------
% 7. Kinesis
kinesis_cols = T.Properties.VariableNames(startsWith(T.Properties.VariableNames, 'kinesis_'));
kinesis_cols = setdiff(kinesis_cols, {'kinesis_condition', 'kinesis_condition_original_segment_only'}, 'stable');

cols = [base_cols, kinesis_cols];
cols = cols(ismember(cols, T.Properties.VariableNames));

writetable(T(:, cols), output_file, 'Sheet', 'Kinesis_Gait');

fprintf('\nAnalysis Excel exported:\n%s\n', output_file);

end