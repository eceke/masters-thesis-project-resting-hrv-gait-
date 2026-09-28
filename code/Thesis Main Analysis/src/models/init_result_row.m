function row = init_result_row(model_id, family, rest_condition, gait_outcome, hrv_predictor, model_variant)
%INIT_RESULT_ROW Create a struct with every results-table column
%   pre-populated (NaN / empty defaults), so a skipped or failed model still
%   produces a row of the exact same shape as a successful one -- this keeps
%   rows_to_table's struct concatenation well-defined regardless of outcome.
%
%   model_variant identifies which of the two random-effects
%   structures this row is for: 'random_slope' or 'random_intercept_only'.
%   Both are always fit and exported as fully separate rows.

row = struct();
row.model_id = model_id;
row.model_family = family;
row.model_variant = model_variant;
row.model_label = sprintf('%s|%s|%s|%s|%s', family, rest_condition, hrv_predictor, gait_outcome, model_variant);
row.rest_condition = rest_condition;
row.gait_outcome = gait_outcome;
row.hrv_predictor = hrv_predictor;
row.random_effect_structure_used = '';

% inferential_role classifies which of the two always-fitted random-effects
% structures this row. Set by the caller from model_variant.
row.inferential_role = '';

% primary_model_available / primary_model_issue / sensitivity_model_available
% (primary-model-table only; left NaN for follow-up rows) describe THIS
% COMBINATION's random-slope (primary) fit status and are identical on
% both this combination's rows (primary and sensitivity), regardless of
% which row you are looking at. primary_model_available is false if the
% random-slope model failed to fit, did not converge, was singular, or its
% HRV coefficients could not be extracted; the random-intercept-only
% sensitivity result is still computed and reported in that case, but is
% never silently promoted to "primary". No model is ever chosen based on
% p-value or significance.
row.primary_model_available = NaN;
row.primary_model_issue = '';
row.sensitivity_model_available = NaN;

% estimate_HRV        = HRV simple slope at 1 km/h (the reference speed level)
% estimate_HRV_4kmh   = HRV simple slope at 4 km/h
% estimate_HRVxSpeed  = difference between the 4 km/h and 1 km/h HRV slopes
row.estimate_HRV = NaN; row.SE_HRV = NaN; row.t_HRV = NaN;
row.p_HRV_raw = NaN; row.p_HRV_FDR = NaN;
row.CI_HRV_lower = NaN; row.CI_HRV_upper = NaN;

row.estimate_HRVxSpeed = NaN; row.SE_HRVxSpeed = NaN; row.t_HRVxSpeed = NaN;
row.p_HRVxSpeed_raw = NaN; row.p_HRVxSpeed_FDR = NaN;
row.CI_HRVxSpeed_lower = NaN; row.CI_HRVxSpeed_upper = NaN;

% HRV simple slope at 4 km/h (beta_HRV + beta_HRVxSpeed, with its own
% linear-combination SE/df/p/CI -- see compute_hrv_simple_slope_4kmh.m).
% p_HRV_4kmh_FDR is its own separate BH-FDR family, never combined with
% p_HRV_FDR / p_HRVxSpeed_FDR / p_WalkingTask_FDR.
row.estimate_HRV_4kmh = NaN;
row.SE_HRV_4kmh = NaN;
row.t_HRV_4kmh = NaN;
row.p_HRV_4kmh_raw = NaN;
row.p_HRV_4kmh_FDR = NaN;
row.CI_HRV_4kmh_lower = NaN;
row.CI_HRV_4kmh_upper = NaN;

% Walking-task fixed effect (FWW versus BW) on the gait outcome.
row.walking_task_term_name = '';
row.estimate_WalkingTask = NaN; row.SE_WalkingTask = NaN; row.t_WalkingTask = NaN;
row.p_WalkingTask_raw = NaN; row.p_WalkingTask_FDR = NaN;
row.CI_WalkingTask_lower = NaN; row.CI_WalkingTask_upper = NaN;

% follow-up-only (HRV x rest_condition) -- left blank/NaN for primary models.
% These individual EC/EO2-vs-EO1 reference-level coefficients represent the
% same underlying comparisons as the "EC_vs_EO1"/"EO2_vs_EO1" rows of the
% separate followup_rest_condition_contrasts table; kept for backward
% compatibility, see Followup Rest
% Condition Contrasts for the reporting-hierarchy pairwise comparisons.
row.hrv_x_restcondition_role = 'technical_reference_level_coefficients';
row.hrv_x_restcondition_terms = '';
row.estimate_HRVxRestCondition_list = '';
row.p_HRVxRestCondition_raw_list = '';
row.p_HRVxRestCondition_raw_min = NaN;
row.p_HRVxRestCondition_FDR_min = NaN;

% follow-up-only omnibus test: does the HRV-gait slope differ AT ALL
% across EO1/EC/EO2 (joint test of both HRV x rest_condition interaction
% coefficients being simultaneously zero)? it only tests whether there
% is some difference somewhere among EO1/EC/EO2. Left blank/NaN for
% primary models. This omnibus test is the PRIMARY follow-up inferential
% test for a given candidate pair when inferential_role = 'primary'
% (random_slope); the pairwise contrasts and six simple slopes are
% interpreted underneath it (see omnibus_passed_FDR /
% followup_inferential_status below and the interpretation-status columns
% on the contrasts/simple-slopes tables).
row.omnibus_HRVxRestCondition_F = NaN;
row.omnibus_HRVxRestCondition_df1 = NaN;
row.omnibus_HRVxRestCondition_df2 = NaN;
row.omnibus_HRVxRestCondition_p_raw = NaN;
row.omnibus_HRVxRestCondition_p_FDR = NaN;

% Interpretation-hierarchy fields, filled in by run_followup_models.m only
% after FDR correction (the gate depends on the FDR-adjusted omnibus
% p-value, which is only known once every follow-up model's omnibus
% p-value has been collected). followup_pair_id links this row to its
% sibling (same candidate pair, other model_variant) follow-up row -- both
% variants are always fit for every candidate. Left NaN/blank for primary
% (non-follow-up) models.
row.followup_pair_id = NaN;
row.omnibus_passed_FDR = NaN;
row.followup_inferential_status = '';

% followup_model_available / followup_model_issue (follow-up-table only;
% left NaN/blank for primary models): whether THIS row's own follow-up fit
% is usable at all -- fit successfully, converged, not singular, HRV main
% effect and HRV x speed coefficients extractable, and the omnibus
% HRV x rest_condition test (including its p-value) computable. this field is independent
% per follow-up row -- the primary and sensitivity follow-up fits for the
% same candidate pair can have different availability. Availability gates
% ONLY the decision/interpretation status columns below (omnibus_passed_FDR,
% followup_inferential_status, and the contrasts/simple-slopes
% interpretation-status columns).
row.followup_model_available = NaN;
row.followup_model_issue = '';

row.R2_marginal = NaN; row.R2_conditional = NaN;

row.n_rows = 0; row.n_participants = 0; row.n_missing_rows_removed = 0;
row.participants_excluded_for_this_model = '';

row.AIC = NaN; row.BIC = NaN;

row.converged = false; row.singular_fit = NaN;
row.residual_normality_flag = NaN;
row.homoscedasticity_flag = NaN;
row.influential_points_flag = false;
row.random_effect_normality_flag = NaN;
row.warning_message = '';
row.diagnostic_warning_message = '';

% outcome_column_used documents which underlying z-scored column this row
% actually modeled (e.g. 'z_SwingTimeVariability' for a raw primary/
% follow-up row vs. 'z_log_SwingTimeVariability' for a log-outcome
% sensitivity row) -- set by the caller. Combined with inferential_role
% below, this makes a log-outcome sensitivity row unmistakable even if it
% is ever viewed alongside primary/follow-up rows in a combined report.
row.outcome_column_used = '';

% ---- Detailed diagnostic breakdown (defaults; populated from
% run_model_diagnostics.m's output struct via a field-copy loop in
% run_primary_models.m / run_followup_models.m / run_log_sensitivity_models.m).
row.residual_normality_test_name = '';
row.residual_normality_stat = NaN;
row.residual_normality_p = NaN;
row.residual_normality_skewness = NaN;
row.residual_normality_kurtosis = NaN;
row.residual_normality_n = NaN;

row.homoscedasticity_test_name = '';
row.homoscedasticity_p = NaN;
row.homoscedasticity_residual_sd_speed_1 = NaN;
row.homoscedasticity_residual_sd_speed_4 = NaN;
row.homoscedasticity_residual_sd_task_BW = NaN;
row.homoscedasticity_residual_sd_task_FWW = NaN;
row.homoscedasticity_residual_sd_BW_1kmh = NaN;
row.homoscedasticity_residual_sd_BW_4kmh = NaN;
row.homoscedasticity_residual_sd_FWW_1kmh = NaN;
row.homoscedasticity_residual_sd_FWW_4kmh = NaN;
row.homoscedasticity_speed_variance_ratio = NaN;
row.homoscedasticity_cell_variance_ratio = NaN;

row.influential_points_threshold_z = NaN;
row.influential_points_n_over_threshold = 0;
row.influential_points_max_abs_standardized_residual = NaN;
row.influential_points_participant_ids = '';
row.influential_points_observation_context = '';
row.influential_points_loo_flag = NaN;
row.influential_points_loo_max_abs_delta = NaN;
row.influential_points_loo_flagged_participants = '';
row.influential_points_detail = '';

row.random_effect_intercept_normality_p = NaN;
row.random_effect_intercept_skewness = NaN;
row.random_effect_intercept_kurtosis = NaN;
row.random_effect_intercept_sd = NaN;
row.random_effect_slope_normality_p = NaN;
row.random_effect_slope_skewness = NaN;
row.random_effect_slope_kurtosis = NaN;
row.random_effect_slope_sd = NaN;
row.random_effect_intercept_slope_correlation = NaN;

row.diagnostic_summary = '';

end
