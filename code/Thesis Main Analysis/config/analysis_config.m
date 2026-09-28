function cfg = analysis_config()
%ANALYSIS_CONFIG Central configuration for the resting-state HRV -> gait
%   performance LMM pipeline. Every variable name, factor level, and
%   decision threshold used by the pipeline is defined here so the
%   analysis code never hard-codes them inline.

cfg = struct();

here = fileparts(mfilename('fullpath'));
project_root = fileparts(here);

% ---- Input/output paths ----
cfg.data_file  = fullfile(project_root, 'data', 'LMM_HRV_GAIT_long.csv');
cfg.output_dir = fullfile(project_root, 'output');

% ---- Design / grouping columns ----
cfg.participant_col     = 'participant_id';
cfg.rest_condition_col  = 'rest_condition';
cfg.walking_task_col    = 'walking_task';
cfg.speed_col           = 'speed_factor';
cfg.kinesis_col         = 'kinesis_condition';

% rest_condition_levels(1) and speed_reference define the reference
% (omitted) level used in dummy coding for fitlme -- must stay first.
cfg.rest_condition_levels = {'EO1', 'EC', 'EO2'};
cfg.speed_levels          = {'1', '4'};   % km/h
cfg.speed_reference       = '1';
cfg.walking_task_levels = {'BW', 'FWW'};
cfg.kinesis_levels      = {'N', 'P'};

% ---- HRV predictors: raw column -> whether it needs ln() before z-scoring ----
cfg.hrv_vars = struct( ...
    'meanHR_ecg', struct('log_transform', false), ...
    'RMSSD_ecg',  struct('log_transform', true), ...
    'HF_ecg',     struct('log_transform', true) ...
);
cfg.hrv_var_names = fieldnames(cfg.hrv_vars);

% ---- Gait outcomes ----
cfg.gait_vars = {'StrideLength', 'Cadence', 'StrideTime', 'DoubleSupportTime', ...
                  'SwingTimeVariability', 'StanceTime', 'SwingTime'};

% ---- Stage-2 candidate screening rule ----
cfg.candidate_p_threshold      = 0.05;
cfg.candidate_effect_threshold = 0.30;

% ---- Diagnostics thresholds ----
cfg.alpha              = 0.05;
cfg.singular_var_tol   = 1e-4;   % random-effect SD below sqrt(this) => boundary/near-zero variance
cfg.singular_corr_tol  = 0.999;  % |random-effect correlation| above this => boundary fit
cfg.influence_flag_z   = 3;      % |standardized residual| above this => flagged observation
cfg.loo_influence_se_multiple = 3; % leave-one-participant-out beta shift > this*SE => flagged

% ---- Minimum data required to attempt a model ----
cfg.min_participants_per_model = 3;
cfg.min_rows_per_model         = 8;

% ---- Random-effects structures fitted as separate model variants ----
% Both structures are fit for every HRV-gait combination and exported as
% independent rows (model_variant = 'random_slope' | 'random_intercept_only')
% -- re_fallback is not an automatic fallback used only when re_full fails.
% The name is kept for backward compatibility with the rest of the code.
cfg.re_full     = '(1 + speed_factor | participant_id)';
cfg.re_fallback = '(1 | participant_id)';

% ---- Log-outcome sensitivity analysis (limited scope: one gait outcome) ----
% A natural-log-transformed, separately z-scored version of ONLY this gait
% outcome is built (transform_and_standardize.m) and refit with the SAME
% fixed-effects structure as the raw primary random_slope model, across
% all 3 resting conditions x 3 HRV predictors (9 models total) -- see
% run_log_sensitivity_models.m. These models never affect candidate
% selection, never trigger follow-up modelling, and are never mixed into
% the primary/sensitivity FDR families. Set enable_log_sensitivity = false
% to skip this stage entirely and run the rest of the pipeline unchanged.
cfg.log_sensitivity_outcome = 'SwingTimeVariability';
cfg.enable_log_sensitivity  = true;

end
