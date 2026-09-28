function run_hrv_gait_analysis(varargin)
%RUN_HRV_GAIT_ANALYSIS Main entry point for the resting-state HRV -> gait
%   performance LMM pipeline. Requires MATLAB's Statistics and Machine
%   Learning Toolbox (fitlme, fitlm, lillietest).
%
%   run_hrv_gait_analysis() uses the default config (config/analysis_config.m)
%   run_hrv_gait_analysis('DataFile', path) overrides the input CSV location
%   run_hrv_gait_analysis('OutputDir', path) overrides the output folder
%
%   Pipeline stages:
%     1-2. Load + validate LMM_HRV_GAIT_long.csv
%     3.   Cast design columns to categorical (explicit reference levels)
%     4.   ln-transform (RMSSD/HF) + z-score HRV predictors and gait outcomes
%     5.   Missingness report
%     6-8. Fit 126 HRV-gait models (3 HRV x 7 gait x 3 rest conditions x
%          2 random-effects structures): 63 'primary' (random_slope) and
%          63 'exploratory_sensitivity' (random_intercept_only); extract
%          HRV, HRV x speed, and walking_task terms, apply BH-FDR within
%          each family x model_variant. Neither variant is ever chosen by significance.
%     6b.  Fit 9 log-outcome sensitivity models for cfg.log_sensitivity_outcome
%          (SwingTimeVariability by default; 3 rest conditions x 3 HRV
%          predictors, primary random_slope structure only -- toggle via
%          cfg.enable_log_sensitivity) and build the raw-vs-log comparison
%          table. Own FDR family; never affects candidate selection or
%          follow-up modelling.
%     9a.  Build the random-effects robustness comparison (primary vs.
%          sensitivity, all 63 combinations, independent of candidacy)
%     9b.  Identify candidate HRV-gait pairs from primary (random_slope)
%          rows when a 1 or 4 km/h HRV slope has p_raw < .05 and
%          |beta| >= .30 in at least one resting condition; sensitivity-only
%          reported separately and never trigger follow-up
%    10-11. Fit BOTH follow-up random-effects variants (primary +
%          exploratory sensitivity) for every primary candidate; extract
%          the HRV x rest_condition omnibus test (the primary follow-up
%          inferential test), six condition-by-speed simple slopes, and
%          three pairwise resting-condition contrasts (gated by the
%          primary model's own omnibus FDR result, never by the
%          sensitivity model's); full diagnostics including
%          leave-one-out influence across all six slopes
%    12.  Export all outputs to output_dir

p = inputParser;
addParameter(p, 'DataFile', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'OutputDir', '', @(x) ischar(x) || isstring(x));
parse(p, varargin{:});

cfg = analysis_config();
if ~isempty(p.Results.DataFile)
    cfg.data_file = char(p.Results.DataFile);
end
if ~isempty(p.Results.OutputDir)
    cfg.output_dir = char(p.Results.OutputDir);
end

fprintf('=== HRV-gait LMM pipeline ===\n');

fprintf('\n[Step 1-2] Loading and validating data...\n');
[T, load_report] = load_gait_hrv_data(cfg.data_file, cfg);

fprintf('\n[Step 3] Preparing categorical variables...\n');
T = prepare_categorical_variables(T, cfg);

fprintf('\n[Step 4] Transforming and standardizing variables...\n');
[T, transform_qc] = transform_and_standardize(T, cfg);

fprintf('\n[Step 5] Building missingness report...\n');
missingness = build_missingness_report(T, cfg);

qc_summary = struct();
qc_summary.n_rows_loaded = load_report.n_rows;
qc_summary.n_participants_loaded = load_report.n_participants;

% Expected row count is based on the number of participants and the
% configured rest condition, walking task, and speed levels. 
key_cols = {cfg.participant_col, cfg.rest_condition_col, cfg.walking_task_col, cfg.speed_col};
unique_key_rows = unique(T(:, key_cols));
qc_summary.n_unique_participants = numel(unique(T.(cfg.participant_col)));
qc_summary.n_unique_participant_rest_task_speed_combinations = height(unique_key_rows);
qc_summary.n_duplicate_keys = height(T) - height(unique_key_rows);
qc_summary.expected_rows = qc_summary.n_unique_participants * numel(cfg.rest_condition_levels) * ...
    numel(cfg.walking_task_levels) * numel(cfg.speed_levels);
qc_summary.observed_rows = height(T);
qc_summary.row_count_difference = qc_summary.observed_rows - qc_summary.expected_rows;

for i = 1:numel(cfg.hrv_var_names)
    v = cfg.hrv_var_names{i};
    qc_summary.(['n_log_transform_invalid_' v]) = transform_qc.log_transform_invalid.(v);
end
% Log-outcome sensitivity variable (cfg.log_sensitivity_outcome, e.g.
% SwingTimeVariability): surfaces the same dynamically-computed QC count
% transform_and_standardize.m already builds for it, alongside the HRV
% ones above. isfield-guarded since the field is only populated when
% cfg.enable_log_sensitivity is true.
if isfield(transform_qc.log_transform_invalid, cfg.log_sensitivity_outcome)
    qc_summary.(['n_log_transform_invalid_' cfg.log_sensitivity_outcome]) = ...
        transform_qc.log_transform_invalid.(cfg.log_sensitivity_outcome);
end

n_primary = numel(cfg.hrv_var_names) * numel(cfg.gait_vars) * numel(cfg.rest_condition_levels) * 2;
fprintf('\n[Step 6-8] Fitting %d primary HRV-gait models (%d HRV x %d gait x %d rest conditions x 2 random-effects structures)...\n', ...
    n_primary, numel(cfg.hrv_var_names), numel(cfg.gait_vars), numel(cfg.rest_condition_levels));
[primary_results, primary_warnings, primary_models] = run_primary_models(T, cfg);

if cfg.enable_log_sensitivity
    fprintf('\n[Step 6b] Fitting %d log-outcome sensitivity models for %s (%d rest conditions x %d HRV predictors, primary random_slope structure only)...\n', ...
        numel(cfg.rest_condition_levels) * numel(cfg.hrv_var_names), cfg.log_sensitivity_outcome, ...
        numel(cfg.rest_condition_levels), numel(cfg.hrv_var_names));
else
    fprintf('\n[Step 6b] Log-outcome sensitivity analysis disabled (cfg.enable_log_sensitivity = false).\n');
end
[log_sensitivity_results, log_sensitivity_warnings, log_sensitivity_models] = run_log_sensitivity_models(T, cfg);

fprintf('\n[Step 6c] Comparing raw vs. log-transformed %s primary models...\n', cfg.log_sensitivity_outcome);
swing_time_log_comparison = build_swing_time_log_comparison(primary_results, log_sensitivity_results, cfg);

fprintf('\n[Step 9a] Building random-effects robustness comparison (primary vs. sensitivity)...\n');
robustness_comparison = build_robustness_comparison(primary_results, cfg);

fprintf('\n[Step 9b] Identifying candidate HRV-gait pairs for follow-up (primary random_slope only)...\n');
[candidates, sensitivity_only_patterns] = identify_candidate_pairs(primary_results, cfg);
fprintf('  %d primary candidate pair(s) identified (p_raw < %.2f & |beta| >= %.2f in >=1 rest condition).\n', ...
    height(candidates), cfg.candidate_p_threshold, cfg.candidate_effect_threshold);
fprintf('  %d sensitivity-only candidate-like pattern(s) (random_intercept_only only, not followed up).\n', ...
    height(sensitivity_only_patterns));

fprintf('\n[Step 10-11] Fitting resting-condition follow-up models (both variants per candidate)...\n');
[followup_results, followup_warnings, followup_models, followup_simple_slopes, ...
    followup_rest_condition_contrasts] = run_followup_models(T, candidates, cfg);

fprintf('\n[Step 12] Exporting outputs...\n');
qc_summary.sensitivity_only_pattern_present = height(sensitivity_only_patterns) > 0;

data = struct();
data.T_final = T;
data.missingness = missingness;
data.primary_results = primary_results;
data.robustness_comparison = robustness_comparison;
data.candidates = candidates;
data.sensitivity_only_patterns = sensitivity_only_patterns;
data.followup_results = followup_results;
data.followup_simple_slopes = followup_simple_slopes;
data.followup_rest_condition_contrasts = followup_rest_condition_contrasts;
data.log_sensitivity_results = log_sensitivity_results;
data.swing_time_log_comparison = swing_time_log_comparison;
data.qc_summary = qc_summary;
data.warnings_log = [primary_warnings(:); followup_warnings(:); log_sensitivity_warnings(:)];
data.primary_models = primary_models;
data.followup_models = followup_models;
data.log_sensitivity_models = log_sensitivity_models;
data.cfg = cfg;

export_all_outputs(cfg.output_dir, data);

fprintf('\n=== Pipeline complete ===\n');

end
