function comparison = build_swing_time_log_comparison(primary_results, log_sensitivity_results, cfg)
%BUILD_SWING_TIME_LOG_COMPARISON Pairs each of the nine raw
%   cfg.log_sensitivity_outcome (SwingTimeVariability) primary random_slope
%   models with its corresponding log-outcome sensitivity model
%   (run_log_sensitivity_models.m, matched on rest_condition x
%   hrv_predictor), side by side, to answer: does the natural-log
%   transform of this outcome change the model's diagnostic picture
%   (residual normality, homoscedasticity, influential points) or the
%   direction of the HRV-gait association?
%
%   Read-only: never changes any primary or log-sensitivity model result,
%   and never feeds back into candidate selection or follow-up modelling.
%
%   AIC/BIC are intentionally NOT compared here -- the raw and
%   log-transformed outcomes are on different scales, so their information
%   criteria are not comparable and are never used to declare either
%   specification superior.

outcome = cfg.log_sensitivity_outcome;

if height(primary_results) == 0 || height(log_sensitivity_results) == 0
    comparison = table();
    return;
end

raw_mask = strcmp(primary_results.gait_outcome, outcome) & ...
           strcmp(primary_results.model_variant, 'random_slope');
raw_rows = primary_results(raw_mask, :);

rows = {};
for i = 1:height(raw_rows)
    rr = raw_rows(i, :);
    log_mask = strcmp(log_sensitivity_results.rest_condition, rr.rest_condition{1}) & ...
               strcmp(log_sensitivity_results.hrv_predictor, rr.hrv_predictor{1});
    if ~any(log_mask)
        continue;
    end
    lr = log_sensitivity_results(find(log_mask, 1), :);

    row = struct();
    row.rest_condition = rr.rest_condition{1};
    row.hrv_predictor = rr.hrv_predictor{1};
    row.gait_outcome = outcome;

    row.estimate_HRV_raw = rr.estimate_HRV;
    row.estimate_HRV_log = lr.estimate_HRV;
    row.estimate_HRV_4kmh_raw = rr.estimate_HRV_4kmh;
    row.estimate_HRV_4kmh_log = lr.estimate_HRV_4kmh;
    row.estimate_HRVxSpeed_raw = rr.estimate_HRVxSpeed;
    row.estimate_HRVxSpeed_log = lr.estimate_HRVxSpeed;

    row.p_HRV_raw_scale = rr.p_HRV_raw;
    row.p_HRV_log_scale = lr.p_HRV_raw;
    row.p_HRV_4kmh_raw_scale = rr.p_HRV_4kmh_raw;
    row.p_HRV_4kmh_log_scale = lr.p_HRV_4kmh_raw;
    row.p_HRVxSpeed_raw_scale = rr.p_HRVxSpeed_raw;
    row.p_HRVxSpeed_log_scale = lr.p_HRVxSpeed_raw;

    % An estimate of exactly 0 has no defined sign (same convention as
    % build_robustness_comparison.m) -- left NaN (undetermined) rather
    % than forced into a positive/negative call.
    est_raw = rr.estimate_HRV;
    est_log = lr.estimate_HRV;
    if ~isnan(est_raw) && ~isnan(est_log) && est_raw ~= 0 && est_log ~= 0
        row.effect_direction_consistent = double(sign(est_raw) == sign(est_log));
    else
        row.effect_direction_consistent = NaN;
    end

    row.converged_raw = rr.converged;
    row.converged_log = lr.converged;
    row.singular_fit_raw = rr.singular_fit;
    row.singular_fit_log = lr.singular_fit;

    row.residual_normality_flag_raw = rr.residual_normality_flag;
    row.residual_normality_flag_log = lr.residual_normality_flag;
    row.residual_skewness_raw = rr.residual_normality_skewness;
    row.residual_skewness_log = lr.residual_normality_skewness;
    row.residual_skewness_change = lr.residual_normality_skewness - rr.residual_normality_skewness;
    row.residual_kurtosis_raw = rr.residual_normality_kurtosis;
    row.residual_kurtosis_log = lr.residual_normality_kurtosis;
    row.residual_kurtosis_change = lr.residual_normality_kurtosis - rr.residual_normality_kurtosis;

    row.homoscedasticity_flag_raw = rr.homoscedasticity_flag;
    row.homoscedasticity_flag_log = lr.homoscedasticity_flag;
    row.speed_variance_ratio_raw = rr.homoscedasticity_speed_variance_ratio;
    row.speed_variance_ratio_log = lr.homoscedasticity_speed_variance_ratio;
    row.speed_variance_ratio_change = ...
        lr.homoscedasticity_speed_variance_ratio - rr.homoscedasticity_speed_variance_ratio;
    row.cell_variance_ratio_raw = rr.homoscedasticity_cell_variance_ratio;
    row.cell_variance_ratio_log = lr.homoscedasticity_cell_variance_ratio;
    row.cell_variance_ratio_change = ...
        lr.homoscedasticity_cell_variance_ratio - rr.homoscedasticity_cell_variance_ratio;

    row.n_extreme_residuals_raw = rr.influential_points_n_over_threshold;
    row.n_extreme_residuals_log = lr.influential_points_n_over_threshold;
    row.n_extreme_residuals_change = lr.influential_points_n_over_threshold - rr.influential_points_n_over_threshold;
    row.max_abs_standardized_residual_raw = rr.influential_points_max_abs_standardized_residual;
    row.max_abs_standardized_residual_log = lr.influential_points_max_abs_standardized_residual;
    row.max_abs_standardized_residual_change = ...
        lr.influential_points_max_abs_standardized_residual - rr.influential_points_max_abs_standardized_residual;

    rows{end+1} = row; %#ok<AGROW>
end

comparison = rows_to_table(rows);

end
