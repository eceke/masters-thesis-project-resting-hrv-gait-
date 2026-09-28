function run_merge_kinesis_to_full_table()
%RUN_MERGE_KINESIS_TO_FULL_TABLE Merge Kinesis outcomes into FULL master table.

fprintf('\n=====================================\n');
fprintf('MERGE KINESIS TO FULL TABLE START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();

%% Load FULL table
full_file = fullfile(cfg.paths.features_root, 'FULL_master_table_stage1_cleanwide.csv');

if ~isfile(full_file)
    error('run_merge_kinesis_to_full_table:MissingFullTable', ...
        'FULL table not found: %s', full_file);
end

FULL = readtable(full_file);

fprintf('\nLoaded FULL table:\n%s\n', full_file);
fprintf('Rows: %d\n', height(FULL));
fprintf('Columns: %d\n', width(FULL));

%% Load and clean Kinesis
loaded_kinesis = load_kinesis_excel(cfg);
cleaned_kinesis = clean_kinesis_data(cfg, loaded_kinesis);

fprintf('\nCleaned Kinesis rows: %d\n', height(cleaned_kinesis.cleaned_table));

%% Merge
out = merge_kinesis_to_full_table(cfg, FULL, cleaned_kinesis);

fprintf('\n--- MERGE QC ---\n');
disp(out.qc);

fprintf('\n--- WARNINGS ---\n');
if isempty(out.warnings)
    fprintf('No warnings.\n');
else
    disp(out.warnings');
end

%% Save merged table
output_file = fullfile(cfg.paths.features_root, 'FULL_master_table_with_kinesis.csv');
writetable(out.merged_table, output_file);

fprintf('\nSaved merged FULL table:\n%s\n', output_file);
fprintf('Rows: %d\n', height(out.merged_table));
fprintf('Columns: %d\n', width(out.merged_table));

fprintf('\n--- FIRST 10 ROWS KEY COLUMNS ---\n');

preview_cols = {'participant_id','sensor','segment_name','segment_type','kinesis_condition'};

possible_gait_cols = { ...
    'kinesis_Cadence_steps_min_', ...
    'kinesis_AverageStrideLength_cm_', ...
    'kinesis_AverageStrideVelocity_cm_s_', ...
    'kinesis_WalkTime_s_', ...
    'kinesis_DistanceTravelled_m_'};

preview_cols = [preview_cols, possible_gait_cols];
preview_cols = preview_cols(ismember(preview_cols, out.merged_table.Properties.VariableNames));

disp(head(out.merged_table(:, preview_cols), 10));

fprintf('\n=====================================\n');
fprintf('MERGE KINESIS TO FULL TABLE END\n');
fprintf('=====================================\n');

end