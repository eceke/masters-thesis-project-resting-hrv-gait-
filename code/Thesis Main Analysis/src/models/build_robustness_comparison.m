function robustness = build_robustness_comparison(primary_results, cfg)
%BUILD_ROBUSTNESS_COMPARISON For every rest_condition x HRV
%   predictor x gait outcome combination (all 63, independent of whether
%   any candidates were identified), compare the primary (random_slope)
%   and exploratory sensitivity (random_intercept_only) primary-model rows
%   side by side, for four effects: the HRV slope at 1 km/h, the HRV slope
%   at 4 km/h, the HRV x speed interaction, and the walking_task effect.
%
%   Per effect and per combination, reports: both models' estimates and
%   their difference, whether the two estimates' signs agree
%   (<effect>_direction_consistent), whether each model's raw p-value is
%   below cfg.alpha (<effect>_robustness_raw_p) and whether each model's
%   FDR-adjusted p-value is below cfg.alpha (<effect>_robustness_FDR), and
%   -- for the two HRV slopes only -- whether each model meets the
%   candidate criterion (<effect>_robustness_candidate_criterion).
%   None of these introduce a new threshold: cfg.alpha is the same
%   significance level already used elsewhere in this pipeline (e.g.
%   diagnostics), and the candidate criterion is exactly
%   identify_candidate_pairs.m's existing rule (p_raw < cfg.candidate_p_threshold
%   AND |estimate| >= cfg.candidate_effect_threshold), evaluated here
%   read-only for comparison purposes -- this function does not affect
%   candidate selection.
%
%   overall_robustness_classification (one of five categories based
%   on candidate support) is derived only from: (a)
%   whether the primary model was available for this combination, and (b)
%   whether the candidate criterion (either HRV slope) is met under each
%   model -- i.e. it is a summary of the same inputs already used for
%   primary candidate selection, not a new statistical decision:
%     primary_model_unavailable    -- primary_model_available is false
%     supported_in_both_models     -- candidate criterion met by both
%     primary_only                 -- candidate criterion met by primary only
%     sensitivity_only_nonrobust   -- candidate criterion met by sensitivity only
%     not_supported_in_either_model -- candidate criterion met by neither
%   This priority order is purely candidate-support-based so that a
%   near-zero, noise-driven sign flip between two non-candidate estimates
%   (neither of which meets the candidate criterion) is never misread as
%   something other than not_supported_in_either_model.
%
%   opposite_effect_directions_flag is a SEPARATE descriptive flag (not a
%   classification category): true only when both HRV slope estimates are
%   non-NaN, non-zero, and have different signs. It can co-occur with any
%   of the five classifications above, including sensitivity_only_nonrobust
%   -- direction disagreement is reported alongside candidate-support
%   classification, never in place of it. An estimate of exactly 0 has no
%   defined sign, so it is never treated as agreeing or disagreeing with
%   the other model's direction: direction_consistent_<label> (per effect)
%   and this aggregate flag are both left NaN/false (undetermined) rather
%   than a specific positive/negative call whenever either estimate is
%   exactly zero.

if height(primary_results) == 0
    robustness = table();
    return;
end

combos = unique(primary_results(:, {'rest_condition', 'hrv_predictor', 'gait_outcome'}));
n = height(combos);

% {label, estimate_col, p_raw_col, p_fdr_col, is_hrv_slope}
effect_defs = { ...
    '1kmh',        'estimate_HRV',        'p_HRV_raw',        'p_HRV_FDR',        true ; ...
    '4kmh',        'estimate_HRV_4kmh',   'p_HRV_4kmh_raw',   'p_HRV_4kmh_FDR',   true ; ...
    'HRVxSpeed',   'estimate_HRVxSpeed',  'p_HRVxSpeed_raw',  'p_HRVxSpeed_FDR',  false; ...
    'WalkingTask', 'estimate_WalkingTask','p_WalkingTask_raw','p_WalkingTask_FDR', false ...
};

rows = cell(n, 1);
for i = 1:n
    rc = combos.rest_condition{i};
    hp = combos.hrv_predictor{i};
    go = combos.gait_outcome{i};

    mask_primary = strcmp(primary_results.rest_condition, rc) & strcmp(primary_results.hrv_predictor, hp) & ...
                   strcmp(primary_results.gait_outcome, go) & strcmp(primary_results.model_variant, 'random_slope');
    mask_sens = strcmp(primary_results.rest_condition, rc) & strcmp(primary_results.hrv_predictor, hp) & ...
                strcmp(primary_results.gait_outcome, go) & strcmp(primary_results.model_variant, 'random_intercept_only');

    row = struct();
    row.rest_condition = rc;
    row.hrv_predictor = hp;
    row.gait_outcome = go;
    row.primary_model_variant = 'random_slope';
    row.sensitivity_model_variant = 'random_intercept_only';

    if any(mask_primary)
        rp = primary_results(mask_primary, :);
        primary_available = rp.primary_model_available(1) == 1;
        primary_issue = rp.primary_model_issue{1};
    else
        primary_available = false;
        primary_issue = 'no primary model row found for this combination';
    end
    row.primary_model_available = primary_available;
    row.primary_model_issue = primary_issue;

    if any(mask_sens)
        rs = primary_results(mask_sens, :);
        sensitivity_available = rs.sensitivity_model_available(1) == 1;
    else
        sensitivity_available = false;
    end
    row.sensitivity_model_available = sensitivity_available;


    hrv_candidate_primary = false;
    hrv_candidate_sensitivity = false;
    hrv_direction_consistent_all = true;
    hrv_direction_checked = false;

    for e = 1:size(effect_defs, 1)
        label = effect_defs{e, 1};
        est_col = effect_defs{e, 2};
        praw_col = effect_defs{e, 3};
        pfdr_col = effect_defs{e, 4};
        is_hrv_slope = effect_defs{e, 5};

        [est_p, praw_p, pfdr_p] = local_get(primary_results, mask_primary, est_col, praw_col, pfdr_col);
        [est_s, praw_s, pfdr_s] = local_get(primary_results, mask_sens, est_col, praw_col, pfdr_col);

        row.(['estimate_primary_' label]) = est_p;
        row.(['estimate_sensitivity_' label]) = est_s;
        row.(['estimate_diff_' label]) = est_s - est_p;

        % An estimate of exactly 0 has no defined sign, so it can never
        % agree or disagree with the other model's direction -- left NaN
        % (undetermined) rather than forced into a positive/negative call.
        dir_consistent = NaN;
        if ~isnan(est_p) && ~isnan(est_s) && est_p ~= 0 && est_s ~= 0
            dir_consistent = double(sign(est_p) == sign(est_s));
        end
        row.(['direction_consistent_' label]) = dir_consistent;

        raw_sig_p = ~isnan(praw_p) && praw_p < cfg.alpha;
        raw_sig_s = ~isnan(praw_s) && praw_s < cfg.alpha;
        row.(['robustness_raw_p_' label]) = local_status(raw_sig_p, raw_sig_s, ~isnan(praw_p), ~isnan(praw_s));

        fdr_sig_p = ~isnan(pfdr_p) && pfdr_p < cfg.alpha;
        fdr_sig_s = ~isnan(pfdr_s) && pfdr_s < cfg.alpha;
        row.(['robustness_FDR_' label]) = local_status(fdr_sig_p, fdr_sig_s, ~isnan(pfdr_p), ~isnan(pfdr_s));

        if is_hrv_slope
            cand_p = primary_available && raw_sig_p && ...
                ~isnan(est_p) && abs(est_p) >= cfg.candidate_effect_threshold;
            cand_s = sensitivity_available && raw_sig_s && ...
                ~isnan(est_s) && abs(est_s) >= cfg.candidate_effect_threshold;

            row.(['candidate_criterion_primary_' label]) = cand_p;
            row.(['candidate_criterion_sensitivity_' label]) = cand_s;
            row.(['robustness_candidate_criterion_' label]) = ...
                local_status(cand_p, cand_s, primary_available, sensitivity_available);

            if cand_p; hrv_candidate_primary = true; end %#ok<SEPEX>
            if cand_s; hrv_candidate_sensitivity = true; end %#ok<SEPEX>
            % Sign-of-zero: an exactly-zero estimate is excluded from the
            % direction check entirely (see per-effect comment above).
            if ~isnan(est_p) && ~isnan(est_s) && est_p ~= 0 && est_s ~= 0
                hrv_direction_checked = true;
                if sign(est_p) ~= sign(est_s)
                    hrv_direction_consistent_all = false;
                end
            end
        end
    end

    % Summary fields for robustness interpretation.
    row.robustness_HRVxSpeed = row.robustness_raw_p_HRVxSpeed;
    row.robustness_candidate_criterion = ...
        local_status(hrv_candidate_primary, hrv_candidate_sensitivity, ...
            primary_available, sensitivity_available);
    if hrv_direction_checked
        row.estimate_direction_consistency = double(hrv_direction_consistent_all);
    else
        row.estimate_direction_consistency = NaN;
    end
    % Separate descriptive flag, not a classification category -- can
    % co-occur with any of the five classifications below (see docstring).
    row.opposite_effect_directions_flag = hrv_direction_checked && ~hrv_direction_consistent_all;

    % Priority order is purely candidate-support-based (five categories):
    % a near-zero, noise-driven sign flip between two non-candidate
    % estimates never pre-empts this classification -- direction agreement
    % is reported separately via opposite_effect_directions_flag above.
    if ~primary_available
        row.overall_robustness_classification = 'primary_model_unavailable';
    elseif hrv_candidate_primary && hrv_candidate_sensitivity
        row.overall_robustness_classification = 'supported_in_both_models';
    elseif hrv_candidate_primary && ~hrv_candidate_sensitivity
        row.overall_robustness_classification = 'primary_only';
    elseif ~hrv_candidate_primary && hrv_candidate_sensitivity
        row.overall_robustness_classification = 'sensitivity_only_nonrobust';
    else
        row.overall_robustness_classification = 'not_supported_in_either_model';
    end

    rows{i} = row;
end

robustness = rows_to_table(rows);

end

function [est, praw, pfdr] = local_get(T, mask, est_col, praw_col, pfdr_col)
    if ~any(mask)
        est = NaN; praw = NaN; pfdr = NaN;
        return;
    end
    sub = T(mask, :);
    est = sub.(est_col)(1);
    praw = sub.(praw_col)(1);
    pfdr = sub.(pfdr_col)(1);
end

function status = local_status(sig_p, sig_s, avail_p, avail_s)
%LOCAL_STATUS Categorical raw/FDR/candidate-criterion comparison label.
    if ~avail_p || ~avail_s
        status = 'undetermined';
    elseif sig_p && sig_s
        status = 'consistent_significant';
    elseif ~sig_p && ~sig_s
        status = 'consistent_nonsignificant';
    elseif sig_p && ~sig_s
        status = 'primary_only_significant';
    else
        status = 'sensitivity_only_significant';
    end
end
