function run_build_analysis_table()
%RUN_BUILD_ANALYSIS_TABLE Build participant+segment analysis-ready table.

fprintf('\n=====================================\n');
fprintf('BUILD ANALYSIS TABLE START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();

input_file = fullfile(cfg.paths.features_root, 'FULL_master_table_with_kinesis.csv');

if ~isfile(input_file)
    error('run_build_analysis_table:MissingInput', ...
        'Merged FULL table not found: %s', input_file);
end

T = readtable(input_file);

fprintf('\nLoaded merged FULL table:\n%s\n', input_file);
fprintf('Rows: %d\n', height(T));
fprintf('Columns: %d\n', width(T));

out = build_analysis_table(cfg, T);

fprintf('\n--- ANALYSIS TABLE QC ---\n');
disp(out.qc);

fprintf('\n--- WARNINGS ---\n');
if isempty(out.warnings)
    fprintf('No warnings.\n');
else
    disp(out.warnings');
end

output_file = fullfile(cfg.paths.features_root, 'ANALYSIS_TABLE_participant_segment.csv');
writetable(out.analysis_table, output_file);

fprintf('\nSaved analysis table:\n%s\n', output_file);
fprintf('Rows: %d\n', height(out.analysis_table));
fprintf('Columns: %d\n', width(out.analysis_table));

fprintf('\n--- FIRST 10 ROWS BASIC VIEW ---\n');

preview_cols = { ...
    'participant_id', ...
    'segment_name', ...
    'segment_type', ...
    'kinesis_condition', ...
    'heart_ecg_meanHR_ecg', ...
    'heart_ecg_RMSSD_ecg', ...
    'heart_nn_live_meanHR_nn', ...
    'heart_nn_live_RMSSD_nn', ...
    'hip_acc_accmag_mean', ...
    'hip_angularrate_angmag_mean', ...
    'kinesis_Cadence_steps_min_', ...
    'kinesis_AverageStrideVelocity_cm_s_'};

preview_cols = preview_cols(ismember(preview_cols, out.analysis_table.Properties.VariableNames));

disp(head(out.analysis_table(:, preview_cols), 10));

fprintf('\n=====================================\n');
fprintf('BUILD ANALYSIS TABLE END\n');
fprintf('=====================================\n');

end