function run_correlation_analysis()
%RUN_CORRELATION_ANALYSIS Exploratory physiology–gait correlations.
% Clean exploratory correlation analysis:
% Resting Heart physiology -> Walking Hip motion + Kinesis gait outcomes.
%
% Uses only interpretable scientific features.
% Excludes QC/count/validity/sample-size features.

fprintf('\n=====================================\n');
fprintf('RUN CLEAN CORRELATION ANALYSIS START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();

input_file = fullfile(cfg.paths.features_root, 'ANALYSIS_TABLE_participant_segment.csv');

if ~isfile(input_file)
    error('run_correlation_analysis_clean:MissingInput', ...
        'Analysis table not found: %s', input_file);
end

T = readtable(input_file);

fprintf('\nLoaded analysis table:\n%s\n', input_file);
fprintf('Rows: %d\n', height(T));
fprintf('Columns: %d\n', width(T));

%% Output folder
out_dir = fullfile(cfg.paths.features_root, 'Correlation Reports Clean');

if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% Normalize key columns
T.participant_id = cellstr(string(T.participant_id));
T.segment_name = cellstr(string(T.segment_name));
T.segment_type = cellstr(string(T.segment_type));

if ismember('kinesis_condition', T.Properties.VariableNames)
    T.kinesis_condition = cellstr(string(T.kinesis_condition));
end

%% Segment definitions
rest_segments = {'RS_EO1','RS_EC','RS_EO2'};
walk_segments = {'BW_1KMH','BW_4KMH','FWW_1KMH','FWW_4KMH'};

%% Select clean predictors and outcomes
predictor_cols = local_select_clean_predictors(T);
outcome_cols   = local_select_clean_outcomes(T);

fprintf('\nClean predictor columns selected: %d\n', numel(predictor_cols));
fprintf('Clean outcome columns selected: %d\n', numel(outcome_cols));

%% Run correlations
rows = {};

for rs = 1:numel(rest_segments)

    rest_segment = rest_segments{rs};
    Xtab = T(strcmp(T.segment_name, rest_segment), :);

    for ws = 1:numel(walk_segments)

        walk_segment = walk_segments{ws};
        Ytab = T(strcmp(T.segment_name, walk_segment), :);

        left_vars = {'participant_id'};

        if ismember('kinesis_condition', Xtab.Properties.VariableNames)
            left_vars{end+1} = 'kinesis_condition';
        end

        left_vars = [left_vars, predictor_cols];

        Pair = innerjoin( ...
            Xtab, ...
            Ytab, ...
            'Keys', 'participant_id', ...
            'LeftVariables', left_vars, ...
            'RightVariables', [{'participant_id'}, outcome_cols]);

        for px = 1:numel(predictor_cols)

            predictor = predictor_cols{px};

            if ~ismember(predictor, Pair.Properties.VariableNames)
                continue;
            end

            x = Pair.(predictor);

            for oy = 1:numel(outcome_cols)

                outcome = outcome_cols{oy};
                outcome_join_name = local_find_joined_variable(Pair, outcome);

                if isempty(outcome_join_name)
                    continue;
                end

                y = Pair.(outcome_join_name);

                result = local_compute_correlation(x, y);

                rows(end+1,:) = { ...
                    string(rest_segment), ...
                    string(walk_segment), ...
                    string(predictor), ...
                    string(outcome), ...
                    string(local_feature_group(predictor)), ...
                    string(local_feature_group(outcome)), ...
                    result.n_complete, ...
                    result.spearman_rho, ...
                    result.spearman_p, ...
                    result.pearson_r, ...
                    result.pearson_p, ...
                    result.is_valid, ...
                    string(result.skip_reason)}; %#ok<AGROW>
            end
        end
    end
end

R = cell2table(rows, 'VariableNames', { ...
    'rest_segment', ...
    'walk_segment', ...
    'predictor', ...
    'outcome', ...
    'predictor_group', ...
    'outcome_group', ...
    'n_complete', ...
    'spearman_rho', ...
    'spearman_p', ...
    'pearson_r', ...
    'pearson_p', ...
    'is_valid', ...
    'skip_reason'});

%% FDR
R.abs_spearman_rho = abs(R.spearman_rho);
R.abs_pearson_r = abs(R.pearson_r);

R_valid = R(R.is_valid, :);

R_valid.p_fdr_spearman = local_bh_fdr(R_valid.spearman_p);
R_valid.p_fdr_pearson  = local_bh_fdr(R_valid.pearson_p);

R_valid.p_fdr_spearman_by_pair = NaN(height(R_valid), 1);
R_valid.p_fdr_pearson_by_pair  = NaN(height(R_valid), 1);

[Gpair, ~] = findgroups(R_valid.rest_segment, R_valid.walk_segment);

for g = 1:max(Gpair)
    idx = Gpair == g;

    R_valid.p_fdr_spearman_by_pair(idx) = local_bh_fdr(R_valid.spearman_p(idx));
    R_valid.p_fdr_pearson_by_pair(idx)  = local_bh_fdr(R_valid.pearson_p(idx));
end

R_valid = sortrows(R_valid, 'abs_spearman_rho', 'descend');

R_kinesis = R_valid(strcmp(R_valid.outcome_group, "kinesis"), :);
R_hip = R_valid(startsWith(R_valid.outcome_group, "hip_"), :);

%% Feature lists
PredictorList = table(string(predictor_cols(:)), ...
    local_group_list(predictor_cols(:)), ...
    'VariableNames', {'predictor','predictor_group'});

OutcomeList = table(string(outcome_cols(:)), ...
    local_group_list(outcome_cols(:)), ...
    'VariableNames', {'outcome','outcome_group'});

%% QC table
QC = table();
QC.metric = { ...
    'input_rows'; ...
    'input_columns'; ...
    'clean_predictor_columns'; ...
    'clean_outcome_columns'; ...
    'total_tests'; ...
    'valid_tests'; ...
    'invalid_tests'; ...
    'kinesis_valid_tests'; ...
    'hip_valid_tests'};
QC.value = [ ...
    height(T); ...
    width(T); ...
    numel(predictor_cols); ...
    numel(outcome_cols); ...
    height(R); ...
    height(R_valid); ...
    sum(~R.is_valid); ...
    height(R_kinesis); ...
    height(R_hip)];

%% Save CSV
all_csv = fullfile(out_dir, 'clean_correlation_results_all.csv');
valid_csv = fullfile(out_dir, 'clean_correlation_results_valid_sorted.csv');
kinesis_csv = fullfile(out_dir, 'clean_correlation_results_kinesis_only.csv');
hip_csv = fullfile(out_dir, 'clean_correlation_results_hip_only.csv');

writetable(R, all_csv);
writetable(R_valid, valid_csv);
writetable(R_kinesis, kinesis_csv);
writetable(R_hip, hip_csv);

%% Save Excel
excel_file = fullfile(out_dir, 'clean_correlation_report.xlsx');

if isfile(excel_file)
    delete(excel_file);
end

writetable(QC, excel_file, 'Sheet', 'Overview');
writetable(R_valid, excel_file, 'Sheet', 'Valid_Sorted');
writetable(R_kinesis, excel_file, 'Sheet', 'Kinesis_Only');
writetable(R_hip, excel_file, 'Sheet', 'Hip_Only');
writetable(R, excel_file, 'Sheet', 'All_Tests');
writetable(PredictorList, excel_file, 'Sheet', 'Predictors');
writetable(OutcomeList, excel_file, 'Sheet', 'Outcomes');

%% Print
fprintf('\n--- CLEAN CORRELATION QC ---\n');
disp(QC);

fprintf('\nSaved clean correlation outputs:\n');
fprintf('%s\n', all_csv);
fprintf('%s\n', valid_csv);
fprintf('%s\n', kinesis_csv);
fprintf('%s\n', hip_csv);
fprintf('%s\n', excel_file);

fprintf('\n--- TOP 20 CLEAN VALID SPEARMAN RESULTS ---\n');

disp(head(R_valid(:, { ...
    'rest_segment', ...
    'walk_segment', ...
    'predictor', ...
    'outcome', ...
    'n_complete', ...
    'spearman_rho', ...
    'spearman_p', ...
    'p_fdr_spearman', ...
    'p_fdr_spearman_by_pair', ...
    'pearson_r', ...
    'pearson_p', ...
    'p_fdr_pearson'}), 20));

fprintf('\n=====================================\n');
fprintf('RUN CLEAN CORRELATION ANALYSIS END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function predictor_cols = local_select_clean_predictors(T)

vars = T.Properties.VariableNames;

wanted = false(size(vars));

% ECG-derived interpretable HR/HRV
wanted = wanted | ismember(vars, { ...
    'heart_ecg_meanHR_ecg', ...
    'heart_ecg_meanNN_ecg', ...
    'heart_ecg_RMSSD_ecg', ...
    'heart_ecg_SDNN_ecg', ...
    'heart_ecg_pNN50_ecg'});

% NN-derived interpretable HR/HRV
wanted = wanted | ismember(vars, { ...
    'heart_nn_live_meanHR_nn', ...
    'heart_nn_live_meanNN_nn', ...
    'heart_nn_live_RMSSD_nn', ...
    'heart_nn_live_SDNN_nn', ...
    'heart_nn_live_pNN50_nn'});

% HR live summary
wanted = wanted | ismember(vars, { ...
    'heart_hr_live_hr_mean', ...
    'heart_hr_live_hr_std', ...
    'heart_hr_live_hr_min', ...
    'heart_hr_live_hr_max', ...
    'heart_hr_live_hr_median'});

% RMSSD live summary
wanted = wanted | ismember(vars, { ...
    'heart_hrvrmssd_live_rmssd_live_mean', ...
    'heart_hrvrmssd_live_rmssd_live_std', ...
    'heart_hrvrmssd_live_rmssd_live_min', ...
    'heart_hrvrmssd_live_rmssd_live_max', ...
    'heart_hrvrmssd_live_rmssd_live_median'});

% BPMBXB interpretable HR summary
wanted = wanted | ismember(vars, { ...
    'heart_bpmbxb_live_bpmbxb_mean', ...
    'heart_bpmbxb_live_bpmbxb_std', ...
    'heart_bpmbxb_live_bpmbxb_min', ...
    'heart_bpmbxb_live_bpmbxb_max', ...
    'heart_bpmbxb_live_bpmbxb_median'});

% Heart temperature context
wanted = wanted | ismember(vars, { ...
    'heart_temp_temp_mean', ...
    'heart_temp_temp_std', ...
    'heart_temp_temp_min', ...
    'heart_temp_temp_max', ...
    'heart_temp_temp_median'});

predictor_cols = vars(wanted);
predictor_cols = local_keep_numeric_and_nonempty(T, predictor_cols);

end

%% ========================================================================
function outcome_cols = local_select_clean_outcomes(T)

vars = T.Properties.VariableNames;

wanted = false(size(vars));

% Kinesis gait outcomes
wanted = wanted | ismember(vars, { ...
    'kinesis_Cadence_steps_min_', ...
    'kinesis_AverageStrideLength_cm_', ...
    'kinesis_AverageStrideVelocity_cm_s_', ...
    'kinesis_WalkTime_s_', ...
    'kinesis_DistanceTravelled_m_', ...
    'kinesis_StrideVelocityVariability___', ...
    'kinesis_StrideLengthVariability___', ...
    'kinesis_StrideTimeVariability___', ...
    'kinesis_StepTimeVariability___', ...
    'kinesis_StrideTimeAsymmetry___', ...
    'kinesis_StepTimeAsymmetry___', ...
    'kinesis_StrideLengthAsymmetry___', ...
    'kinesis_StrideVelocityAsymmetry___', ...
    'kinesis_SpeedScore___', ...
    'kinesis_VariabilityScore___', ...
    'kinesis_SymmetryScore___'});

% Hip ACC interpretable motion features
wanted = wanted | ismember(vars, { ...
    'hip_acc_accmag_mean', ...
    'hip_acc_accmag_std', ...
    'hip_acc_accmag_min', ...
    'hip_acc_accmag_max', ...
    'hip_acc_accmag_range', ...
    'hip_acc_accmag_rms', ...
    'hip_acc_accmag_energy'});

% Hip angularrate interpretable motion features
wanted = wanted | ismember(vars, { ...
    'hip_angularrate_gyromag_mean', ...
    'hip_angularrate_gyromag_std', ...
    'hip_angularrate_gyromag_min', ...
    'hip_angularrate_gyromag_max', ...
    'hip_angularrate_gyromag_range', ...
    'hip_angularrate_gyromag_rms', ...
    'hip_angularrate_gyromag_energy'});

% Hip movementacceleration interpretable features
wanted = wanted | ismember(vars, { ...
    'hip_movementacceleration_movementacceleration_mean', ...
    'hip_movementacceleration_movementacceleration_std', ...
    'hip_movementacceleration_movementacceleration_min', ...
    'hip_movementacceleration_movementacceleration_max', ...
    'hip_movementacceleration_movementacceleration_range', ...
    'hip_movementacceleration_movementacceleration_median'});

% Stepcount only interpretable totals/rates, not QC increments/errors
wanted = wanted | ismember(vars, { ...
    'hip_stepcount_stepcount_total_positive_increment', ...
    'hip_stepcount_stepcount_final_value', ...
    'hip_stepcount_step_rate_per_min'});

outcome_cols = vars(wanted);
outcome_cols = local_keep_numeric_and_nonempty(T, outcome_cols);

end

%% ========================================================================
function cols_out = local_keep_numeric_and_nonempty(T, cols_in)

cols_out = {};

for i = 1:numel(cols_in)
    col = cols_in{i};

    if ~ismember(col, T.Properties.VariableNames)
        continue;
    end

    if ~isnumeric(T.(col))
        continue;
    end

    if all(isnan(T.(col)))
        continue;
    end

    cols_out{end+1} = col; %#ok<AGROW>
end

end

%% ========================================================================
function result = local_compute_correlation(x, y)

result = struct();
result.n_complete = 0;
result.spearman_rho = NaN;
result.spearman_p = NaN;
result.pearson_r = NaN;
result.pearson_p = NaN;
result.is_valid = false;
result.skip_reason = "";

x = double(x(:));
y = double(y(:));

valid = ~isnan(x) & ~isnan(y);

xv = x(valid);
yv = y(valid);

result.n_complete = numel(xv);

if result.n_complete < 3
    result.skip_reason = "n_complete < 3";
    return;
end

if std(xv, 'omitnan') == 0
    result.skip_reason = "zero variance predictor";
    return;
end

if std(yv, 'omitnan') == 0
    result.skip_reason = "zero variance outcome";
    return;
end

[rho, p_s] = corr(xv, yv, ...
    'Type', 'Spearman', ...
    'Rows', 'complete');

[r, p_p] = corr(xv, yv, ...
    'Type', 'Pearson', ...
    'Rows', 'complete');

result.spearman_rho = rho;
result.spearman_p = p_s;
result.pearson_r = r;
result.pearson_p = p_p;
result.is_valid = true;
result.skip_reason = "";

end

%% ========================================================================
function joined_name = local_find_joined_variable(Pair, original_name)

joined_name = '';

if ismember(original_name, Pair.Properties.VariableNames)
    joined_name = original_name;
    return;
end

candidate = [original_name '_right'];

if ismember(candidate, Pair.Properties.VariableNames)
    joined_name = candidate;
    return;
end

candidate = [original_name '_Y'];

if ismember(candidate, Pair.Properties.VariableNames)
    joined_name = candidate;
    return;
end

end

%% ========================================================================
function group = local_feature_group(feature_name)

feature_name = char(feature_name);

if startsWith(feature_name, 'heart_ecg_')
    group = "heart_ecg";
elseif startsWith(feature_name, 'heart_nn_live_')
    group = "heart_nn";
elseif startsWith(feature_name, 'heart_hr_live_')
    group = "heart_hr_live";
elseif startsWith(feature_name, 'heart_hrvrmssd_live_')
    group = "heart_hrvrmssd_live";
elseif startsWith(feature_name, 'heart_bpmbxb_live_')
    group = "heart_bpmbxb_live";
elseif startsWith(feature_name, 'heart_temp_')
    group = "heart_temp";
elseif startsWith(feature_name, 'kinesis_')
    group = "kinesis";
elseif startsWith(feature_name, 'hip_acc_')
    group = "hip_acc";
elseif startsWith(feature_name, 'hip_angularrate_')
    group = "hip_angularrate";
elseif startsWith(feature_name, 'hip_movementacceleration_')
    group = "hip_movementacceleration";
elseif startsWith(feature_name, 'hip_stepcount_')
    group = "hip_stepcount";
else
    group = "other";
end

end

%% ========================================================================
function groups = local_group_list(features)

groups = strings(numel(features), 1);

for i = 1:numel(features)
    groups(i) = local_feature_group(features{i});
end

end

%% ========================================================================
function p_fdr = local_bh_fdr(p)

p_original_shape = size(p);
p = p(:);

p_fdr = NaN(size(p));

valid = ~isnan(p);

if ~any(valid)
    p_fdr = reshape(p_fdr, p_original_shape);
    return;
end

p_valid = p(valid);
m = numel(p_valid);

[ps, sort_idx] = sort(p_valid, 'ascend');

adjusted_sorted = ps .* m ./ (1:m)';

for i = m-1:-1:1
    adjusted_sorted(i) = min(adjusted_sorted(i), adjusted_sorted(i+1));
end

adjusted_sorted = min(adjusted_sorted, 1);

adjusted_valid = NaN(size(p_valid));
adjusted_valid(sort_idx) = adjusted_sorted;

p_fdr(valid) = adjusted_valid;

p_fdr = reshape(p_fdr, p_original_shape);

end