function [results, warnings_log, models] = run_primary_models(T, cfg)
%RUN_PRIMARY_MODELS Stage 1 (Steps 6-8): fit
%   3 HRV metrics x 7 gait outcomes x 3 resting conditions = 63 HRV-gait
%   combinations, one resting condition at a time. Both configured
%   random-effects structures are fit for every combination and exported
%   as separate rows, giving
%   63 x 2 = 126 model rows:
%     model_variant = 'random_slope'          -- (1 + speed_factor | participant_id)
%     model_variant = 'random_intercept_only' -- (1 | participant_id)
%   The fixed-effects structure is identical between the two variants; only
%   the random-effects term differs. Neither variant is ever chosen for a
%   combination based on p-value or significance.
%
%   Inferential roles: random_slope rows are labelled
%   inferential_role = 'primary' -- the confirmatory basis for candidate
%   selection and the main results. random_intercept_only rows are
%   labelled inferential_role = 'exploratory_sensitivity' -- they show how
%   much a result depends on allowing participant-specific speed
%   variability, and are never substituted for the primary result, never
%   used to select candidates on their own, and never treated as
%   confirmatory. For every combination, both rows also carry
%   primary_model_available / primary_model_issue / sensitivity_model_available,
%   describing whether the random-slope (primary) and random-intercept-only
%   (sensitivity) fits are each usable: fit successfully, converged, not
%   singular, and with extractable HRV coefficients. If the primary
%   specification is unavailable for a combination, the sensitivity result
%   is still fit, diagnosed, and reported (flagged via
%   primary_model_available = false), but it is not reclassified as
%   primary.
%
%   For each model, the HRV simple slope at 4 km/h (the non-reference speed
%   level) is also computed as a linear combination of the HRV main effect
%   and the HRV x speed interaction (compute_hrv_simple_slope_4kmh.m),
%   alongside the existing 1 km/h HRV slope and the HRV x speed interaction
%   itself. Benjamini-Hochberg FDR correction is applied separately within
%   each model_variant (63 tests each) for the HRV main effect (1 km/h),
%   the HRV x speed interaction, the walking_task effect, and the HRV
%   simple slope at 4 km/h -- four independent families per variant, so
%   the primary (random_slope) and sensitivity (random_intercept_only)
%   corrections never mix, and the primary FDR result is never replaced by
%   the sensitivity one.

rows = {};
models = {};
warnings_log = {};
model_id = 0;

variant_specs = { ...
    struct('model_variant', 'random_slope', 'inferential_role', 'primary', ...
           'structure_label', 'random_intercept_plus_speed_slope', 're_term', cfg.re_full), ...
    struct('model_variant', 'random_intercept_only', 'inferential_role', 'exploratory_sensitivity', ...
           'structure_label', 'random_intercept_only', 're_term', cfg.re_fallback) ...
};

n_total = numel(cfg.rest_condition_levels) * numel(cfg.hrv_var_names) * numel(cfg.gait_vars) * numel(variant_specs);

for rc = 1:numel(cfg.rest_condition_levels)
    rest_level = cfg.rest_condition_levels{rc};
    T_rc = T(T.(cfg.rest_condition_col) == rest_level, :);

    for hv = 1:numel(cfg.hrv_var_names)
        hrv_raw = cfg.hrv_var_names{hv};
        hrv_col = ['z_' hrv_raw];

        for gv = 1:numel(cfg.gait_vars)
            gait_raw = cfg.gait_vars{gv};
            gait_col = ['z_' gait_raw];
            family = sprintf('%s_only', rest_level);

            needed_cols = {gait_col, hrv_col, cfg.speed_col, cfg.walking_task_col, ...
                           cfg.kinesis_col, cfg.participant_col};
            [T_model, n_removed, participants_excluded, n_participants_used] = ...
                complete_case_subset(T_rc, needed_cols, cfg.participant_col);
            n_rows_model = height(T_model);
            insufficient_data = n_participants_used < cfg.min_participants_per_model || ...
                                 n_rows_model < cfg.min_rows_per_model;

            variant_rows = cell(1, numel(variant_specs));
            variant_fitres = cell(1, numel(variant_specs));
            variant_models = cell(1, numel(variant_specs));

            for vi = 1:numel(variant_specs)
                vs = variant_specs{vi};
                model_id = model_id + 1;

                row = init_result_row(model_id, family, rest_level, gait_raw, hrv_raw, vs.model_variant);
                row.random_effect_structure_used = vs.structure_label;
                row.inferential_role = vs.inferential_role;
                row.outcome_column_used = gait_col;
                row.n_rows = n_rows_model;
                row.n_missing_rows_removed = n_removed;
                row.n_participants = n_participants_used;
                row.participants_excluded_for_this_model = strjoin(participants_excluded, ';');

                formula = sprintf('%s ~ %s * %s + %s + %s + %s', ...
                    gait_col, hrv_col, cfg.speed_col, cfg.walking_task_col, cfg.kinesis_col, vs.re_term);

                if insufficient_data
                    row.warning_message = 'skipped: insufficient non-missing data for this HRV-gait-rest combination';
                    fitres = struct('model', [], 'converged', false, 'singular_fit', NaN, ...
                                     'warning_message', row.warning_message, 'AIC', NaN, 'BIC', NaN);
                    warnings_log{end+1} = sprintf('Model %d (%s): %s', model_id, row.model_label, row.warning_message); %#ok<AGROW>
                else
                    fitres = fit_one_lmm(T_model, formula, cfg);
                    row.converged = fitres.converged;
                    row.singular_fit = fitres.singular_fit;
                    row.warning_message = fitres.warning_message;

                    if isempty(fitres.model)
                        row.warning_message = [row.warning_message ' | model fitting failed entirely'];
                        warnings_log{end+1} = sprintf('Model %d (%s): fitting failed', model_id, row.model_label); %#ok<AGROW>
                    else
                        m = fitres.model;
                        terms = extract_hrv_terms(m, hrv_col, cfg.speed_col);

                        row.estimate_HRV = terms.main.estimate;
                        row.SE_HRV = terms.main.se;
                        row.t_HRV = terms.main.tStat;
                        row.p_HRV_raw = terms.main.pValue;
                        row.CI_HRV_lower = terms.main.ci_lower;
                        row.CI_HRV_upper = terms.main.ci_upper;

                        row.estimate_HRVxSpeed = terms.hrv_x_speed.estimate;
                        row.SE_HRVxSpeed = terms.hrv_x_speed.se;
                        row.t_HRVxSpeed = terms.hrv_x_speed.tStat;
                        row.p_HRVxSpeed_raw = terms.hrv_x_speed.pValue;
                        row.CI_HRVxSpeed_lower = terms.hrv_x_speed.ci_lower;
                        row.CI_HRVxSpeed_upper = terms.hrv_x_speed.ci_upper;

                        slope_4kmh = compute_hrv_simple_slope_4kmh(m, hrv_col, cfg.speed_col);
                        row.estimate_HRV_4kmh = slope_4kmh.estimate;
                        row.SE_HRV_4kmh = slope_4kmh.se;
                        row.t_HRV_4kmh = slope_4kmh.tStat;
                        row.p_HRV_4kmh_raw = slope_4kmh.pValue;
                        row.CI_HRV_4kmh_lower = slope_4kmh.ci_lower;
                        row.CI_HRV_4kmh_upper = slope_4kmh.ci_upper;

                        wt_term = extract_fixed_effect_term(m, cfg.walking_task_col);
                        row.walking_task_term_name = wt_term.name;
                        row.estimate_WalkingTask = wt_term.estimate;
                        row.SE_WalkingTask = wt_term.se;
                        row.t_WalkingTask = wt_term.tStat;
                        row.p_WalkingTask_raw = wt_term.pValue;
                        row.CI_WalkingTask_lower = wt_term.ci_lower;
                        row.CI_WalkingTask_upper = wt_term.ci_upper;

                        [r2m, r2c] = compute_r2_glmm(m);
                        row.R2_marginal = r2m;
                        row.R2_conditional = r2c;

                        row.AIC = m.ModelCriterion.AIC;
                        row.BIC = m.ModelCriterion.BIC;

                        diag_opts = struct('do_loo_influence', false, 'hrv_col', hrv_col, ...
                                            'participant_col', cfg.participant_col);
                        d = run_model_diagnostics(m, cfg, diag_opts);
                        % Copies every field run_model_diagnostics.m returns
                        d_fields = fieldnames(d);
                        for fi = 1:numel(d_fields)
                            row.(d_fields{fi}) = d.(d_fields{fi});
                        end

                        if ~isempty(fitres.warning_message)
                            warnings_log{end+1} = sprintf('Model %d (%s): %s', model_id, row.model_label, fitres.warning_message); %#ok<AGROW>
                        end

                        fprintf('  [%d/%d] %s | %s ~ %s | %s  (n=%d, participants=%d)\n', ...
                            model_id, n_total, rest_level, gait_raw, hrv_raw, vs.model_variant, ...
                            row.n_rows, row.n_participants);
                    end
                end

                variant_rows{vi} = row;
                variant_fitres{vi} = fitres;
                variant_models{vi} = fitres.model;
            end

            % Cross-reference availability across both variants of this
            % combination: primary_model_available describes
            % the random_slope (variant_specs{1}) fit; sensitivity_model_available
            % describes the random_intercept_only (variant_specs{2}) fit.
            % Both flags are written onto BOTH of this combination's rows.
            [avail_primary, issue_primary] = local_check_availability(variant_fitres{1}, variant_rows{1});
            avail_sensitivity = false;
            if numel(variant_specs) >= 2
                avail_sensitivity = local_check_availability(variant_fitres{2}, variant_rows{2});
            end
            for vi = 1:numel(variant_specs)
                variant_rows{vi}.primary_model_available = avail_primary;
                variant_rows{vi}.primary_model_issue = issue_primary;
                variant_rows{vi}.sensitivity_model_available = avail_sensitivity;
                rows{end+1} = variant_rows{vi}; %#ok<AGROW>
                models{end+1} = variant_models{vi}; %#ok<AGROW>
            end
        end
    end
end

results = rows_to_table(rows);

results.p_HRV_FDR = nan(height(results), 1);
results.p_HRVxSpeed_FDR = nan(height(results), 1);
results.p_WalkingTask_FDR = nan(height(results), 1);
results.p_HRV_4kmh_FDR = nan(height(results), 1);

variant_names = unique(results.model_variant, 'stable');
for vi = 1:numel(variant_names)
    vmask = strcmp(results.model_variant, variant_names{vi});
    results.p_HRV_FDR(vmask) = fdr_bh(results.p_HRV_raw(vmask));
    results.p_HRVxSpeed_FDR(vmask) = fdr_bh(results.p_HRVxSpeed_raw(vmask));
    results.p_WalkingTask_FDR(vmask) = fdr_bh(results.p_WalkingTask_raw(vmask));
    % p_HRV_4kmh_raw is its own separate BH-FDR family (63 tests per
    % variant), never mixed with the 1 km/h HRV, HRV x speed, or
    % walking_task families above -- and (per model_variant masking here)
    % never mixed between the primary and sensitivity variants either.
    results.p_HRV_4kmh_FDR(vmask) = fdr_bh(results.p_HRV_4kmh_raw(vmask));
end

end

function [available, issue] = local_check_availability(fitres, row)
%LOCAL_CHECK_AVAILABILITY Whether one variant's fit for one combination is
%   usable as a confirmatory (primary) or trustworthy (sensitivity)
%   result: it must have fit, converged, not be singular, and have
%   produced the core HRV fixed-effect coefficients. Never based on
%   p-value or significance.
    if isempty(fitres.model)
        available = false;
        issue = 'model fitting failed entirely';
        return;
    end
    if ~fitres.converged
        available = false;
        issue = 'model did not converge';
        return;
    end
    if islogical(fitres.singular_fit) && fitres.singular_fit
        available = false;
        issue = 'singular/boundary random-effects fit';
        return;
    end
    if isnan(row.estimate_HRV) || isnan(row.estimate_HRV_4kmh) || isnan(row.estimate_HRVxSpeed)
        available = false;
        issue = 'required HRV fixed-effect coefficients could not be extracted';
        return;
    end
    available = true;
    issue = '';
end
