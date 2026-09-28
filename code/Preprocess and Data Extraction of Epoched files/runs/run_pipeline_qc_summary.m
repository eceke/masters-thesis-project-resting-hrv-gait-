function run_pipeline_qc_summary()
%RUN_PIPELINE_QC_SUMMARY Create compact QC summary for the completed pipeline.

fprintf('\n=====================================\n');
fprintf('RUN PIPELINE QC SUMMARY START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();

out_dir = fullfile(cfg.paths.qc_root, 'Pipeline Summary');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% Paths
discovery_file = fullfile(cfg.paths.logs_root, 'discovery_log.csv');
stage1_qc_file = fullfile(cfg.paths.qc_root, 'stage1_qc_long.csv');
full_file = fullfile(cfg.paths.features_root, 'FULL_master_table_stage1_cleanwide.csv');
merged_file = fullfile(cfg.paths.features_root, 'FULL_master_table_with_kinesis.csv');
analysis_file = fullfile(cfg.paths.features_root, 'ANALYSIS_TABLE_participant_segment.csv');
ecg_test_file = fullfile(cfg.paths.qc_root, 'ECG Tests', 'test_clean_ecg_all_qc.csv');
ecg_summary_file = fullfile(cfg.paths.qc_root, 'ECG Tests', 'test_clean_ecg_all_summary.csv');

%% Load files if available
Discovery = local_read_if_exists(discovery_file);
StageQC = local_read_if_exists(stage1_qc_file);
Full = local_read_if_exists(full_file);
Merged = local_read_if_exists(merged_file);
Analysis = local_read_if_exists(analysis_file);
ECG = local_read_if_exists(ecg_test_file);
ECGSummary = local_read_if_exists(ecg_summary_file);

%% Overview summary
overview = {};

overview(end+1,:) = {'discovery_log_exists', ~isempty(Discovery)};
overview(end+1,:) = {'stage1_qc_exists', ~isempty(StageQC)};
overview(end+1,:) = {'full_table_exists', ~isempty(Full)};
overview(end+1,:) = {'merged_table_exists', ~isempty(Merged)};
overview(end+1,:) = {'analysis_table_exists', ~isempty(Analysis)};
overview(end+1,:) = {'ecg_test_summary_exists', ~isempty(ECG)};

if ~isempty(Discovery)
    overview(end+1,:) = {'discovery_rows', height(Discovery)};
end

if ~isempty(StageQC)
    overview(end+1,:) = {'stage1_qc_rows', height(StageQC)};
end

if ~isempty(Full)
    overview(end+1,:) = {'full_table_rows', height(Full)};
    overview(end+1,:) = {'full_table_columns', width(Full)};
end

if ~isempty(Merged)
    overview(end+1,:) = {'merged_table_rows', height(Merged)};
    overview(end+1,:) = {'merged_table_columns', width(Merged)};
end

if ~isempty(Analysis)
    overview(end+1,:) = {'analysis_table_rows', height(Analysis)};
    overview(end+1,:) = {'analysis_table_columns', width(Analysis)};
    overview(end+1,:) = {'analysis_participants', numel(unique(string(Analysis.participant_id)))};
    overview(end+1,:) = {'analysis_segments', numel(unique(string(Analysis.segment_name)))};
end

Overview = cell2table(overview, 'VariableNames', {'metric','value'});

%% Stage 1 signal QC summary
SignalQC = table();

if ~isempty(StageQC)

    if ismember('signal_name', StageQC.Properties.VariableNames)

        signals = unique(string(StageQC.signal_name), 'stable');

        rows = {};

        for i = 1:numel(signals)
            sig = signals(i);
            S = StageQC(strcmp(string(StageQC.signal_name), sig), :);

            rows(end+1,:) = { ...
                sig, ...
                height(S), ...
                local_sum_if_exists(S, 'source_available'), ...
                local_sum_if_exists(S, 'warning_all_nan_output'), ...
                local_sum_if_exists(S, 'warning_zero_variance'), ...
                local_sum_if_exists(S, 'warning_high_artifact_ratio'), ...
                local_mean_if_exists(S, 'valid_fraction_final'), ...
                local_sum_if_exists(S, 'final_nan_count')}; %#ok<AGROW>
        end

        SignalQC = cell2table(rows, 'VariableNames', { ...
            'signal_name', ...
            'n_rows', ...
            'n_source_available', ...
            'n_all_nan_warning', ...
            'n_zero_variance_warning', ...
            'n_high_artifact_warning', ...
            'mean_valid_fraction_final', ...
            'total_final_nan_count'});
    end
end

%% ECG QC summary
ECG_QC = table();

if ~isempty(ECG)

    rows = {};

    sensors = unique(string(ECG.sensor), 'stable');

    for i = 1:numel(sensors)
        sensor = sensors(i);
        E = ECG(strcmp(string(ECG.sensor), sensor), :);

        rows(end+1,:) = { ...
            sensor, ...
            height(E), ...
            local_sum_if_exists(E, 'ran_successfully'), ...
            local_sum_if_exists(E, 'usable_data_available'), ...
            local_sum_if_exists(E, 'usable_suggestion'), ...
            sum(E.warning_high_artifact_ratio), ...
            sum(E.warning_too_few_beats), ...
            local_mean_ecg_summary(ECGSummary, sensor, 'meanHR_ecg'), ...
            local_mean_ecg_summary(ECGSummary, sensor, 'RMSSD_ecg')}; %#ok<AGROW>
    end

    ECG_QC = cell2table(rows, 'VariableNames', { ...
        'sensor', ...
        'n_rows', ...
        'n_successful', ...
        'n_usable_data_available', ...
        'n_usable_suggestion', ...
        'n_high_artifact_warning', ...
        'n_too_few_beats_warning', ...
        'mean_meanHR_ecg', ...
        'mean_RMSSD_ecg'});
end

%% Kinesis merge QC from merged/analysis table
KinesisQC = table();

if ~isempty(Merged)

    walk_segments = {'BW_1KMH','BW_4KMH','FWW_1KMH','FWW_4KMH'};
    is_walk = ismember(string(Merged.segment_name), walk_segments);

    kinesis_cols = Merged.Properties.VariableNames(startsWith(Merged.Properties.VariableNames, 'kinesis_'));
    kinesis_cols = setdiff(kinesis_cols, {'kinesis_condition','kinesis_condition_original_segment_only'}, 'stable');

    has_any_kinesis = false(height(Merged),1);

    for i = 1:numel(kinesis_cols)
        col = kinesis_cols{i};

        if isnumeric(Merged.(col))
            has_any_kinesis = has_any_kinesis | ~isnan(Merged.(col));
        end
    end

    KinesisQC = table();
    KinesisQC.n_rows = height(Merged);
    KinesisQC.n_walk_rows = sum(is_walk);
    KinesisQC.n_rest_rows = sum(~is_walk);
    KinesisQC.n_walk_rows_with_kinesis = sum(is_walk & has_any_kinesis);
    KinesisQC.n_walk_rows_without_kinesis = sum(is_walk & ~has_any_kinesis);
    KinesisQC.n_rest_rows_with_kinesis = sum(~is_walk & has_any_kinesis);

    if ismember('kinesis_condition', Merged.Properties.VariableNames)
        KinesisQC.n_rows_without_condition = sum(cellfun(@isempty, cellstr(string(Merged.kinesis_condition))));
    else
        KinesisQC.n_rows_without_condition = height(Merged);
    end

    KinesisQC.n_kinesis_feature_columns = numel(kinesis_cols);
end

%% Analysis table missingness summary
AnalysisMissing = table();

if ~isempty(Analysis)

    feature_cols = setdiff(Analysis.Properties.VariableNames, { ...
        'participant_id','segment_name','segment_type','kinesis_condition'}, 'stable');

    rows = {};

    for i = 1:numel(feature_cols)
        col = feature_cols{i};

        if isnumeric(Analysis.(col))
            missing_fraction = mean(isnan(Analysis.(col)));
            nonmissing_count = sum(~isnan(Analysis.(col)));
        else
            x = string(Analysis.(col));
            missing_fraction = mean(ismissing(x) | strlength(x) == 0);
            nonmissing_count = sum(~(ismissing(x) | strlength(x) == 0));
        end

        rows(end+1,:) = { ...
            string(col), ...
            nonmissing_count, ...
            missing_fraction}; %#ok<AGROW>
    end

    AnalysisMissing = cell2table(rows, 'VariableNames', { ...
        'feature_name', ...
        'nonmissing_count', ...
        'missing_fraction'});

    AnalysisMissing = sortrows(AnalysisMissing, 'missing_fraction', 'descend');
end

%% Save CSV files
writetable(Overview, fullfile(out_dir, 'pipeline_overview.csv'));

if ~isempty(SignalQC)
    writetable(SignalQC, fullfile(out_dir, 'stage1_signal_qc_summary.csv'));
end

if ~isempty(ECG_QC)
    writetable(ECG_QC, fullfile(out_dir, 'ecg_qc_summary.csv'));
end

if ~isempty(KinesisQC)
    writetable(KinesisQC, fullfile(out_dir, 'kinesis_merge_qc_summary.csv'));
end

if ~isempty(AnalysisMissing)
    writetable(AnalysisMissing, fullfile(out_dir, 'analysis_table_missingness_summary.csv'));
end

%% Save Excel report
excel_file = fullfile(out_dir, 'pipeline_qc_summary.xlsx');

if isfile(excel_file)
    delete(excel_file);
end

writetable(Overview, excel_file, 'Sheet', 'Overview');

if ~isempty(SignalQC)
    writetable(SignalQC, excel_file, 'Sheet', 'Stage1_Signal_QC');
end

if ~isempty(ECG_QC)
    writetable(ECG_QC, excel_file, 'Sheet', 'ECG_QC');
end

if ~isempty(KinesisQC)
    writetable(KinesisQC, excel_file, 'Sheet', 'Kinesis_Merge_QC');
end

if ~isempty(AnalysisMissing)
    writetable(AnalysisMissing, excel_file, 'Sheet', 'Analysis_Missingness');
end

%% Print
fprintf('\n--- PIPELINE OVERVIEW ---\n');
disp(Overview);

fprintf('\n--- STAGE 1 SIGNAL QC ---\n');
if isempty(SignalQC)
    fprintf('No Stage 1 signal QC summary generated.\n');
else
    disp(SignalQC);
end

fprintf('\n--- ECG QC ---\n');
if isempty(ECG_QC)
    fprintf('No ECG QC summary generated.\n');
else
    disp(ECG_QC);
end

fprintf('\n--- KINESIS MERGE QC ---\n');
if isempty(KinesisQC)
    fprintf('No Kinesis QC summary generated.\n');
else
    disp(KinesisQC);
end

fprintf('\nSaved pipeline QC summary folder:\n%s\n', out_dir);
fprintf('\nSaved Excel report:\n%s\n', excel_file);

fprintf('\n=====================================\n');
fprintf('RUN PIPELINE QC SUMMARY END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function T = local_read_if_exists(file_path)

if isfile(file_path)
    T = readtable(file_path);
else
    T = table();
end

end

%% ========================================================================
function s = local_sum_if_exists(T, col)

if ismember(col, T.Properties.VariableNames)
    x = T.(col);

    if islogical(x) || isnumeric(x)
        s = sum(x, 'omitnan');
    else
        s = sum(strcmpi(string(x), "true") | strcmp(string(x), "1"));
    end
else
    s = NaN;
end

end

%% ========================================================================
function m = local_mean_if_exists(T, col)

if ismember(col, T.Properties.VariableNames) && isnumeric(T.(col))
    m = mean(T.(col), 'omitnan');
else
    m = NaN;
end

end

%% ========================================================================
function m = local_mean_ecg_summary(T, sensor, col)

if isempty(T) || ~ismember('sensor', T.Properties.VariableNames) || ...
        ~ismember(col, T.Properties.VariableNames)
    m = NaN;
    return;
end

S = T(strcmp(string(T.sensor), string(sensor)), :);

if isempty(S) || ~isnumeric(S.(col))
    m = NaN;
else
    m = mean(S.(col), 'omitnan');
end

end