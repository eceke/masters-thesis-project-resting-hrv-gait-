function [results, warnings_log, models, simple_slopes_table, contrasts_table] = ...
    run_followup_models(T, candidates, cfg)
%RUN_FOLLOWUP_MODELS Stage 2 (Steps 10-11): for each PRIMARY
%   candidate HRV-gait pair (candidates is already restricted to
%   model_variant = 'random_slope' by identify_candidate_pairs.m -- a
%   sensitivity-only candidate-like pattern never reaches this function),
%   fit BOTH follow-up random-effects variants on the combined (all
%   rest_condition) dataset, with EO1 coded as the reference level:
%     inferential_role = 'primary'               -- random_slope
%     inferential_role = 'exploratory_sensitivity' -- random_intercept_only
%   Every candidate pair therefore produces exactly two follow-up model
%   rows, linked by followup_pair_id. The primary follow-up result is the
%   confirmatory one; the sensitivity follow-up result is diagnostic only
%   and never substitutes for it, regardless of which is significant.
%
%   For each fitted follow-up model, compute_hrv_simple_slope_4kmh.m still
%   reports the HRV simple slope at 4 km/h under EO1 (backward compatible
%   with estimate_HRV_4kmh), and compute_followup_rest_condition_analysis.m
%   extracts three distinct kinds of test, forming a reporting hierarchy
%   rather than three independent findings:
%     1) The HRV x rest_condition OMNIBUS test (H0: the HRV x EC and HRV x
%        EO2 interaction coefficients are jointly zero) is the PRIMARY
%        follow-up inferential test for a candidate pair, when it comes
%        from the primary (random_slope) model: "does the HRV-gait
%        association differ anywhere across EO1, EC, EO2?" -- added as
%        omnibus_HRVxRestCondition_* columns on `results`.
%     2) The THREE pairwise resting-condition contrasts (EC vs EO1, EO2 vs
%        EO1, EC vs EO2; contrasts_table, 3 rows/model) are gated by that
%        same primary model's omnibus result: eligible for confirmatory
%        interpretation only when the primary omnibus is FDR-significant,
%        otherwise exploratory only. They are always computed and
%        reported regardless of the gate -- the gate only changes
%        pairwise_interpretation_status, never the p-values themselves.
%     3) The SIX condition-by-speed simple slopes (simple_slopes_table, 6
%        rows/model) characterize direction/magnitude/pattern and are
%        always reported regardless of the omnibus result, but a
%        significant slope in one condition and a non-significant slope in
%        another must never, by themselves, be read as a resting-condition
%        difference -- that claim belongs to the omnibus test and (when
%        eligible) the pairwise contrasts above.
%   Sensitivity (random_intercept_only) follow-up pairwise/simple-slope
%   results are always labelled exploratory ('sensitivity_model_only' /
%   'exploratory_sensitivity'), even when their own
%   omnibus test is significant. If the primary omnibus is not significant
%   (or unavailable) while the sensitivity follow-up's omnibus is
%   FDR-significant, that combination's followup_inferential_status is
%   marked 'sensitivity_only_nonrobust' rather than treated as a positive
%   finding on its own.
%
%   Benjamini-Hochberg FDR correction is applied separately within each
%   model_variant present in the results, as eight independent families:
%   the HRV main effect (1 km/h), HRV x speed interaction, walking_task
%   effect, HRV simple slope at 4 km/h, HRV x rest_condition interaction
%   family, and the omnibus test (all on `results`), plus the
%   resting-condition pairwise contrasts (contrasts_table, all three
%   contrast types pooled) and the condition-by-speed simple slopes
%   (simple_slopes_table, all six slopes pooled). 
%   results/simple_slopes_table/contrasts_table only ever contain rows for
%   successfully fitted models; if `candidates` is empty, or every
%   candidate's fits fail, all three are returned as valid empty tables
%   and the pipeline continues normally.

rows = {};
models = {};
warnings_log = {};
slope_rows = {};
contrast_rows_all = {};
model_id = 0;

followup_variant_specs = { ...
    struct('model_variant', 'random_slope', 'inferential_role', 'primary', ...
           'structure_label', 'random_intercept_plus_speed_slope', 're_term', cfg.re_full), ...
    struct('model_variant', 'random_intercept_only', 'inferential_role', 'exploratory_sensitivity', ...
           'structure_label', 'random_intercept_only', 're_term', cfg.re_fallback) ...
};

for i = 1:height(candidates)
    hrv_raw = candidates.hrv_predictor{i};
    gait_raw = candidates.gait_outcome{i};
    hrv_col = ['z_' hrv_raw];
    gait_col = ['z_' gait_raw];
    pair_id = i;

    needed_cols = {gait_col, hrv_col, cfg.rest_condition_col, cfg.speed_col, ...
                   cfg.walking_task_col, cfg.kinesis_col, cfg.participant_col};
    [T_model, n_removed, participants_excluded, n_participants_used] = ...
        complete_case_subset(T, needed_cols, cfg.participant_col);

    for vi = 1:numel(followup_variant_specs)
        vs = followup_variant_specs{vi};
        model_id = model_id + 1;

        row = init_result_row(model_id, 'rest_condition_followup', 'EO1_ref_EC_EO2', gait_raw, hrv_raw, vs.model_variant);
        row.random_effect_structure_used = vs.structure_label;
        row.inferential_role = vs.inferential_role;
        row.outcome_column_used = gait_col;
        row.followup_pair_id = pair_id;
        row.n_rows = height(T_model);
        row.n_missing_rows_removed = n_removed;
        row.n_participants = n_participants_used;
        row.participants_excluded_for_this_model = strjoin(participants_excluded, ';');

        formula = sprintf('%s ~ %s * %s + %s * %s + %s + %s + %s', ...
            gait_col, hrv_col, cfg.rest_condition_col, hrv_col, cfg.speed_col, ...
            cfg.walking_task_col, cfg.kinesis_col, vs.re_term);

        if row.n_participants < cfg.min_participants_per_model || row.n_rows < cfg.min_rows_per_model
            row.warning_message = 'skipped: insufficient non-missing data for this follow-up model';
            skip_fitres = struct('model', [], 'converged', false, 'singular_fit', NaN);
            [row.followup_model_available, row.followup_model_issue] = ...
                local_check_followup_availability(skip_fitres, row);
            rows{end+1} = row; %#ok<AGROW>
            models{end+1} = []; %#ok<AGROW>
            warnings_log{end+1} = sprintf('Followup %d (%s~%s, %s): %s', model_id, hrv_raw, gait_raw, vs.model_variant, row.warning_message); %#ok<AGROW>
            continue;
        end

        fitres = fit_one_lmm(T_model, formula, cfg);
        row.converged = fitres.converged;
        row.singular_fit = fitres.singular_fit;
        row.warning_message = fitres.warning_message;

        if isempty(fitres.model)
            row.warning_message = [row.warning_message ' | model fitting failed entirely'];
            [row.followup_model_available, row.followup_model_issue] = ...
                local_check_followup_availability(fitres, row);
            rows{end+1} = row; %#ok<AGROW>
            models{end+1} = []; %#ok<AGROW>
            warnings_log{end+1} = sprintf('Followup %d (%s~%s, %s): fitting failed', model_id, hrv_raw, gait_raw, vs.model_variant); %#ok<AGROW>
            continue;
        end

        m = fitres.model;
        terms = extract_hrv_terms(m, hrv_col, cfg.speed_col, cfg.rest_condition_col);

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

        % Reported under EO1 (the follow-up model's reference resting condition),
        % for consistency with the primary-model 4 km/h simple slope columns.
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

        hrv_x_rest = terms.hrv_x_rest;
        if height(hrv_x_rest) > 0
            row.hrv_x_restcondition_terms = strjoin(hrv_x_rest.Name(:)', ';');
            row.p_HRVxRestCondition_raw_min = min(hrv_x_rest.pValue);
            row.estimate_HRVxRestCondition_list = strjoin( ...
                arrayfun(@(x) sprintf('%.4f', x), hrv_x_rest.Estimate, 'UniformOutput', false), ';');
            row.p_HRVxRestCondition_raw_list = strjoin( ...
                arrayfun(@(x) sprintf('%.6g', x), hrv_x_rest.pValue, 'UniformOutput', false), ';');
        end

        % ---- condition-by-speed simple slopes, resting-condition pairwise
        % contrasts, and the HRV x rest_condition omnibus test ----
        fc = compute_followup_rest_condition_analysis(m, hrv_col, cfg);

        row.omnibus_HRVxRestCondition_F = fc.omnibus.F;
        row.omnibus_HRVxRestCondition_df1 = fc.omnibus.df1;
        row.omnibus_HRVxRestCondition_df2 = fc.omnibus.df2;
        row.omnibus_HRVxRestCondition_p_raw = fc.omnibus.pValue;
        % p_FDR, omnibus_passed_FDR, and followup_inferential_status are
        % filled in the post-FDR gating pass below (they need the
        % FDR-corrected p-value, which is only known once every follow-up
        % model's raw p-value has been collected).

        [row.followup_model_available, row.followup_model_issue] = ...
            local_check_followup_availability(fitres, row);

        for si = 1:numel(fc.simple_slopes)
            s = fc.simple_slopes(si);
            slope_rows{end+1} = struct( ...
                'followup_model_id', model_id, 'followup_pair_id', pair_id, 'model_variant', vs.model_variant, ...
                'hrv_predictor', hrv_raw, 'gait_outcome', gait_raw, ...
                'rest_condition', s.rest_condition, 'speed', s.speed, ...
                'estimate', s.estimate, 'SE', s.se, 'tStat', s.tStat, 'df', s.df, ...
                'p_raw', s.pValue, 'p_FDR', NaN, ...
                'CI_lower', s.ci_lower, 'CI_upper', s.ci_upper); %#ok<AGROW>
        end

        for ci = 1:numel(fc.contrasts)
            ctr = fc.contrasts(ci);
            contrast_rows_all{end+1} = struct( ...
                'followup_model_id', model_id, 'followup_pair_id', pair_id, 'model_variant', vs.model_variant, ...
                'hrv_predictor', hrv_raw, 'gait_outcome', gait_raw, ...
                'contrast_name', ctr.contrast_name, ...
                'estimate', ctr.estimate, 'SE', ctr.se, 'tStat', ctr.tStat, 'df', ctr.df, ...
                'p_raw', ctr.pValue, 'p_FDR', NaN, ...
                'CI_lower', ctr.ci_lower, 'CI_upper', ctr.ci_upper); %#ok<AGROW>
        end

        [r2m, r2c] = compute_r2_glmm(m);
        row.R2_marginal = r2m;
        row.R2_conditional = r2c;

        row.AIC = m.ModelCriterion.AIC;
        row.BIC = m.ModelCriterion.BIC;

        diag_opts = struct('do_loo_influence', true, 'hrv_col', hrv_col, ...
                            'participant_col', cfg.participant_col);
        d = run_model_diagnostics(m, cfg, diag_opts);
        % See run_primary_models.m for why this is a field-copy loop. identical resulting values for
        % the five original fields, plus the new detailed breakdown.
        d_fields = fieldnames(d);
        for fi = 1:numel(d_fields)
            row.(d_fields{fi}) = d.(d_fields{fi});
        end

        rows{end+1} = row; %#ok<AGROW>
        models{end+1} = m; %#ok<AGROW>
        fprintf('  [followup %d/%d pairs] %s ~ %s | %s  (n=%d, participants=%d)\n', ...
            i, height(candidates), gait_raw, hrv_raw, vs.model_variant, row.n_rows, row.n_participants);
    end
end

results = rows_to_table(rows);
simple_slopes_table = rows_to_table(slope_rows);
contrasts_table = rows_to_table(contrast_rows_all);

if height(results) > 0
    results.p_HRV_FDR = nan(height(results), 1);
    results.p_HRVxSpeed_FDR = nan(height(results), 1);
    results.p_WalkingTask_FDR = nan(height(results), 1);
    results.p_HRV_4kmh_FDR = nan(height(results), 1);
    results.p_HRVxRestCondition_FDR_min = nan(height(results), 1);
    results.omnibus_HRVxRestCondition_p_FDR = nan(height(results), 1);

    variant_names = unique(results.model_variant, 'stable');
    for vi = 1:numel(variant_names)
        vmask = strcmp(results.model_variant, variant_names{vi});
        vidx = find(vmask);

        results.p_HRV_FDR(vmask) = fdr_bh(results.p_HRV_raw(vmask));
        results.p_HRVxSpeed_FDR(vmask) = fdr_bh(results.p_HRVxSpeed_raw(vmask));
        results.p_WalkingTask_FDR(vmask) = fdr_bh(results.p_WalkingTask_raw(vmask));
        % p_HRV_4kmh_raw is its own separate BH-FDR family, never mixed
        % with the families above or with the HRV x rest_condition family.
        results.p_HRV_4kmh_FDR(vmask) = fdr_bh(results.p_HRV_4kmh_raw(vmask));
        % Omnibus interaction tests: their own separate BH-FDR family --
        % this is the primary follow-up inferential test's correction.
        results.omnibus_HRVxRestCondition_p_FDR(vmask) = ...
            fdr_bh(results.omnibus_HRVxRestCondition_p_raw(vmask));

        all_rest_p = [];
        row_p_index = cell(numel(vidx), 1);
        idx = 1;
        for k = 1:numel(vidx)
            i = vidx(k); %#ok<FXSET>
            plist = str2double(strsplit(results.p_HRVxRestCondition_raw_list{i}, ';'));
            row_p_index{k} = idx:(idx + numel(plist) - 1);
            all_rest_p = [all_rest_p, plist]; %#ok<AGROW>
            idx = idx + numel(plist);
        end
        q_all = fdr_bh(all_rest_p);
        for k = 1:numel(vidx)
            i = vidx(k); %#ok<FXSET>
            results.p_HRVxRestCondition_FDR_min(i) = min(q_all(row_p_index{k}));
        end
    end
end

% Resting-condition pairwise contrasts: their own separate BH-FDR family,
% all three contrast types (EC-vs-EO1, EO2-vs-EO1, EC-vs-EO2) pooled
% together within each model_variant.
if height(contrasts_table) > 0
    contrasts_table.p_FDR = nan(height(contrasts_table), 1);
    contrast_variants = unique(contrasts_table.model_variant, 'stable');
    for vi = 1:numel(contrast_variants)
        cmask = strcmp(contrasts_table.model_variant, contrast_variants{vi});
        contrasts_table.p_FDR(cmask) = fdr_bh(contrasts_table.p_raw(cmask));
    end
end

% Condition-by-speed simple slopes: their own separate BH-FDR family, all
% six condition-speed combinations pooled together within each
% model_variant.
if height(simple_slopes_table) > 0
    simple_slopes_table.p_FDR = nan(height(simple_slopes_table), 1);
    slope_variants = unique(simple_slopes_table.model_variant, 'stable');
    for vi = 1:numel(slope_variants)
        smask = strcmp(simple_slopes_table.model_variant, slope_variants{vi});
        simple_slopes_table.p_FDR(smask) = fdr_bh(simple_slopes_table.p_raw(smask));
    end
end

% ---- Post-FDR interpretation hierarchy (gating only ----
% never changes any estimate, SE, p-value, or FDR value computed above) ----
[results, contrasts_table, simple_slopes_table] = ...
    local_apply_interpretation_hierarchy(results, contrasts_table, simple_slopes_table, cfg);

end

function [available, issue] = local_check_followup_availability(fitres, row)
%LOCAL_CHECK_FOLLOWUP_AVAILABILITY Whether one follow-up row's own fit is
%   usable at all for interpretation purposes: it must have fit,
%   converged, not be singular/boundary, have extractable HRV main-effect
%   and HRV x speed coefficients, and have a computable omnibus
%   HRV x rest_condition test (including a non-NaN p-value). Mirrors
%   run_primary_models.m's local_check_availability, extended with the
%   omnibus-computability check that is specific to follow-up models.
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
    if isnan(row.estimate_HRV) || isnan(row.estimate_HRVxSpeed)
        available = false;
        issue = 'required HRV coefficients could not be extracted';
        return;
    end
    if isnan(row.omnibus_HRVxRestCondition_F) || isnan(row.omnibus_HRVxRestCondition_p_raw)
        available = false;
        issue = 'omnibus test could not be computed';
        return;
    end
    available = true;
    issue = '';
end

function [results, contrasts_table, simple_slopes_table] = ...
    local_apply_interpretation_hierarchy(results, contrasts_table, simple_slopes_table, cfg)
%LOCAL_APPLY_INTERPRETATION_HIERARCHY The omnibus test is
%   the primary follow-up inferential test; pairwise contrasts and simple
%   slopes are labelled with where they stand relative to it, gated by
%   followup_model_available. Purely a labelling pass over already-computed, already-FDR-corrected results --
%   no estimate, SE, p-value, or FDR value is ever changed or recomputed here.

if height(results) > 0
    % omnibus_passed_FDR is forced to NaN whenever this row's own follow-up
    % model is unavailable, regardless of what the raw/FDR omnibus p-value
    % columns show -- an unavailable model must never read as confirmatory.
    results.omnibus_passed_FDR = nan(height(results), 1);
    ok = results.followup_model_available == 1 & ~isnan(results.omnibus_HRVxRestCondition_p_FDR);
    results.omnibus_passed_FDR(ok) = double(results.omnibus_HRVxRestCondition_p_FDR(ok) < cfg.alpha);

    results.followup_inferential_status = repmat({''}, height(results), 1);
    for r = 1:height(results)
        available = results.followup_model_available(r) == 1;
        if strcmp(results.inferential_role{r}, 'primary')
            if ~available
                results.followup_inferential_status{r} = 'primary_followup_model_unavailable';
            elseif results.omnibus_passed_FDR(r) == 1
                results.followup_inferential_status{r} = 'primary_confirmatory_omnibus_significant';
            else
                results.followup_inferential_status{r} = 'primary_confirmatory_omnibus_nonsignificant';
            end
        else
            % Sensitivity row: never itself confirmatory. Only flagged
            % 'sensitivity_only_nonrobust' when THIS sensitivity model is
            % available and FDR-significant, AND the sibling primary
            % follow-up model (same followup_pair_id) is not itself
            % available-and-significant otherwise it stays the
            % default exploratory label. If this sensitivity model is
            % itself unavailable, 'sensitivity_only_nonrobust' can never be
            % assigned, since this_confirmed is then false.
            sib_mask = results.followup_pair_id == results.followup_pair_id(r) & ...
                       strcmp(results.inferential_role, 'primary');
            sib_confirmed = false;
            if any(sib_mask)
                sib_avail = results.followup_model_available(sib_mask);
                sib_omnibus = results.omnibus_passed_FDR(sib_mask);
                sib_confirmed = sib_avail(1) == 1 && ~isnan(sib_omnibus(1)) && sib_omnibus(1) == 1;
            end
            this_confirmed = available && results.omnibus_passed_FDR(r) == 1;
            if this_confirmed && ~sib_confirmed
                results.followup_inferential_status{r} = 'sensitivity_only_nonrobust';
            else
                results.followup_inferential_status{r} = 'exploratory_sensitivity';
            end
        end
    end
end

avail_by_model_id = containers.Map('KeyType', 'double', 'ValueType', 'any');
omnibus_by_model_id = containers.Map('KeyType', 'double', 'ValueType', 'any');
if height(results) > 0
    for r = 1:height(results)
        avail_by_model_id(results.model_id(r)) = results.followup_model_available(r) == 1;
        omnibus_by_model_id(results.model_id(r)) = results.omnibus_passed_FDR(r);
    end
end

if height(contrasts_table) > 0
    contrasts_table.inferential_role = cell(height(contrasts_table), 1);
    contrasts_table.omnibus_passed_FDR = nan(height(contrasts_table), 1);
    contrasts_table.pairwise_interpretation_status = cell(height(contrasts_table), 1);
    for r = 1:height(contrasts_table)
        role = local_role_from_variant(contrasts_table.model_variant{r});
        contrasts_table.inferential_role{r} = role;
        avail = local_lookup_logical(avail_by_model_id, contrasts_table.followup_model_id(r));
        op = local_lookup(omnibus_by_model_id, contrasts_table.followup_model_id(r));
        contrasts_table.omnibus_passed_FDR(r) = op;
        if strcmp(role, 'primary')
            if ~avail
                contrasts_table.pairwise_interpretation_status{r} = 'exploratory_only_primary_model_unavailable';
            elseif ~isnan(op) && op == 1
                contrasts_table.pairwise_interpretation_status{r} = 'confirmatory_after_significant_omnibus';
            else
                contrasts_table.pairwise_interpretation_status{r} = 'exploratory_only_due_to_nonsignificant_omnibus';
            end
        else
            contrasts_table.pairwise_interpretation_status{r} = 'sensitivity_model_only';
        end
    end
end

if height(simple_slopes_table) > 0
    simple_slopes_table.inferential_role = cell(height(simple_slopes_table), 1);
    simple_slopes_table.omnibus_passed_FDR = nan(height(simple_slopes_table), 1);
    simple_slopes_table.simple_slope_interpretation_status = cell(height(simple_slopes_table), 1);
    for r = 1:height(simple_slopes_table)
        role = local_role_from_variant(simple_slopes_table.model_variant{r});
        simple_slopes_table.inferential_role{r} = role;
        avail = local_lookup_logical(avail_by_model_id, simple_slopes_table.followup_model_id(r));
        op = local_lookup(omnibus_by_model_id, simple_slopes_table.followup_model_id(r));
        simple_slopes_table.omnibus_passed_FDR(r) = op;
        if strcmp(role, 'primary')
            if ~avail
                simple_slopes_table.simple_slope_interpretation_status{r} = 'exploratory_characterization_primary_model_unavailable';
            elseif ~isnan(op) && op == 1
                simple_slopes_table.simple_slope_interpretation_status{r} = 'characterization_after_significant_omnibus';
            else
                simple_slopes_table.simple_slope_interpretation_status{r} = 'exploratory_characterization_due_to_nonsignificant_omnibus';
            end
        else
            simple_slopes_table.simple_slope_interpretation_status{r} = 'exploratory_sensitivity';
        end
    end
end

end

function role = local_role_from_variant(variant)
    if strcmp(variant, 'random_slope')
        role = 'primary';
    else
        role = 'exploratory_sensitivity';
    end
end

function v = local_lookup(map, key)
    if isKey(map, key)
        v = map(key);
        if isempty(v) || isnan(v)
            v = NaN;
        end
    else
        v = NaN;
    end
end

function v = local_lookup_logical(map, key)
%LOCAL_LOOKUP_LOGICAL Like local_lookup, but for the availability map:
%   missing keys default to false (unavailable) rather than NaN, 
    if isKey(map, key)
        v = map(key);
        if isempty(v)
            v = false;
        else
            v = logical(v);
        end
    else
        v = false;
    end
end
