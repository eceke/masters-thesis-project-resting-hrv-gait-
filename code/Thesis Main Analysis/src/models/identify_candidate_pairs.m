function [candidates, sensitivity_only_patterns] = identify_candidate_pairs(primary_results, cfg)
%IDENTIFY_CANDIDATE_PAIRS Stage 2 screening rule: an HRV-gait pair
%   enters the follow-up model if, in at least one of EO1/EC/EO2,
%   its HRV simple slope at EITHER speed level meets the rule:
%     1 km/h: p_HRV_raw      < .05  AND |estimate_HRV|      >= .30
%     4 km/h: p_HRV_4kmh_raw < .05  AND |estimate_HRV_4kmh| >= .30
%   (the HRV x speed interaction p-value is never itself a candidacy
%   criterion -- it only tests whether the two slopes differ from each
%   other). Screening deliberately uses p_raw (not p_FDR) for both speeds
%   here -- FDR correction is applied to the follow-up models' own results
%   instead, so real candidates aren't lost to the stricter 63-test
%   correction at the screening stage. 
%
%   Candidate selection uses only the primary (model_variant =
%   'random_slope') rows -- `candidates` is the confirmatory candidate
%   list that drives follow-up modelling, with candidate_source =
%   'primary_random_slope' on every row. If a pair meets the rule under
%   the exploratory sensitivity (random_intercept_only) rows but NOT under
%   the primary rows, it does not become a follow-up candidate; instead it
%   is returned separately in `sensitivity_only_patterns`, labelled
%   'sensitivity_only_candidate_pattern', so it is never lost, but also
%   never used to trigger a follow-up model or treated as a confirmatory
%   finding. `candidates.sensitivity_only_pattern_present` is a single
%   run-level flag (true/false, same value on every row) noting whether
%   ANY sensitivity-only pattern was found anywhere in this run -- it does
%   not mean this specific pair also has one, since by definition a pair
%   cannot be both a primary candidate and a sensitivity-only pattern.
%
%   Availability gate: a row can only contribute a "hit" (and therefore a
%   candidate or a sensitivity-only pattern) when its OWN model is usable --
%   random_slope/primary rows require primary_model_available;
%   random_intercept_only/exploratory_sensitivity rows require
%   sensitivity_model_available. A singular, non-converged, or failed fit
%   never produces a candidate or a sensitivity-only pattern, even if its
%   coefficient/p-value columns happen to be non-NaN. The HRV x speed
%   interaction p-value is never used as part of this availability check
%   or the candidacy rule itself.

if height(primary_results) == 0
    candidates = table();
    sensitivity_only_patterns = local_empty_sensitivity_only_table();
    return;
end

is_random_slope_primary = strcmp(primary_results.model_variant, 'random_slope') & ...
                           strcmp(primary_results.inferential_role, 'primary');
is_random_intercept_sensitivity = strcmp(primary_results.model_variant, 'random_intercept_only') & ...
                                   strcmp(primary_results.inferential_role, 'exploratory_sensitivity');
row_available = (is_random_slope_primary & primary_results.primary_model_available == 1) | ...
                (is_random_intercept_sensitivity & primary_results.sensitivity_model_available == 1);

hit_1kmh = row_available & ...
           primary_results.p_HRV_raw < cfg.candidate_p_threshold & ...
           abs(primary_results.estimate_HRV) >= cfg.candidate_effect_threshold;
hit_4kmh = row_available & ...
           primary_results.p_HRV_4kmh_raw < cfg.candidate_p_threshold & ...
           abs(primary_results.estimate_HRV_4kmh) >= cfg.candidate_effect_threshold;
hit = hit_1kmh | hit_4kmh;

pairs = unique(primary_results(:, {'model_variant', 'hrv_predictor', 'gait_outcome'}));
n = height(pairs);

is_candidate = false(n, 1);
triggering_rest_conditions = cell(n, 1);
triggering_speeds = cell(n, 1);
triggering_condition_speed_pairs = cell(n, 1);
best_simple_slope_p_raw = nan(n, 1);
best_simple_slope_estimate = nan(n, 1);
best_p = nan(n, 1);        % backward-compatible: 1 km/h slope only
best_estimate = nan(n, 1); % backward-compatible: 1 km/h slope only

for i = 1:n
    mask = strcmp(primary_results.model_variant, pairs.model_variant{i}) & ...
           strcmp(primary_results.hrv_predictor, pairs.hrv_predictor{i}) & ...
           strcmp(primary_results.gait_outcome, pairs.gait_outcome{i});
    sub_rows = primary_results(mask, :);
    sub_hit = hit(mask);
    sub_hit_1kmh = hit_1kmh(mask);
    sub_hit_4kmh = hit_4kmh(mask);

    is_candidate(i) = any(sub_hit);
    if ~is_candidate(i)
        triggering_rest_conditions{i} = '';
        triggering_speeds{i} = '';
        triggering_condition_speed_pairs{i} = '';
        continue;
    end

    % One entry per (rest_condition, speed) combination that individually
    % met the candidacy rule -- a single rest_condition row can contribute
    % both a 1 km/h and a 4 km/h entry if both slopes qualify.
    combo_rc = {};
    combo_speed = {};
    combo_p = [];
    combo_estimate = [];
    for r = 1:height(sub_rows)
        if sub_hit_1kmh(r)
            combo_rc{end+1} = sub_rows.rest_condition{r}; %#ok<AGROW>
            combo_speed{end+1} = '1'; %#ok<AGROW>
            combo_p(end+1) = sub_rows.p_HRV_raw(r); %#ok<AGROW>
            combo_estimate(end+1) = sub_rows.estimate_HRV(r); %#ok<AGROW>
        end
        if sub_hit_4kmh(r)
            combo_rc{end+1} = sub_rows.rest_condition{r}; %#ok<AGROW>
            combo_speed{end+1} = '4'; %#ok<AGROW>
            combo_p(end+1) = sub_rows.p_HRV_4kmh_raw(r); %#ok<AGROW>
            combo_estimate(end+1) = sub_rows.estimate_HRV_4kmh(r); %#ok<AGROW>
        end
    end

    triggering_rest_conditions{i} = strjoin(unique(combo_rc, 'stable'), ';');
    triggering_speeds{i} = strjoin(unique(combo_speed, 'stable'), ';');
    triggering_condition_speed_pairs{i} = strjoin( ...
        cellfun(@(rc, sp) sprintf('%s_%skmh', rc, sp), combo_rc, combo_speed, 'UniformOutput', false), ';');

    [~, best_idx] = min(combo_p);
    best_simple_slope_p_raw(i) = combo_p(best_idx);
    best_simple_slope_estimate(i) = combo_estimate(best_idx);

    % Backward-compatible columns: unchanged definition (best raw
    % p-value/estimate among rows whose 1 km/h slope met the rule) -- NaN
    % when this pair is a candidate purely because of its 4 km/h slope.
    if any(sub_hit_1kmh)
        rows_1kmh = sub_rows(sub_hit_1kmh, :);
        [~, bi] = min(rows_1kmh.p_HRV_raw);
        best_p(i) = rows_1kmh.p_HRV_raw(bi);
        best_estimate(i) = rows_1kmh.estimate_HRV(bi);
    end
end

pairs.is_candidate = is_candidate;
pairs.triggering_rest_conditions = triggering_rest_conditions;
pairs.triggering_speeds = triggering_speeds;
pairs.triggering_condition_speed_pairs = triggering_condition_speed_pairs;
pairs.best_simple_slope_p_raw = best_simple_slope_p_raw;
pairs.best_simple_slope_estimate = best_simple_slope_estimate;
pairs.best_p_HRV_raw = best_p;
pairs.best_estimate_HRV = best_estimate;

% ---- Candidates from primary (random_slope) rows ----
rs_mask = strcmp(pairs.model_variant, 'random_slope') & pairs.is_candidate;
candidates = pairs(rs_mask, :);
candidates.candidate_source = repmat({'primary_random_slope'}, height(candidates), 1);
% Every row reaching `candidates` was, by construction of hit_1kmh/hit_4kmh
% above, drawn only from rows with primary_model_available == true, and
% therefore always satisfies the full availability + candidacy rule --
% both new columns are true on every candidate row.
candidates.primary_model_available = true(height(candidates), 1);
candidates.candidate_model_valid = true(height(candidates), 1);

% ---- Sensitivity-only candidate-like patterns ----
ri_mask = strcmp(pairs.model_variant, 'random_intercept_only') & pairs.is_candidate;
sensitivity_hits = pairs(ri_mask, :);

sens_only_mask = true(height(sensitivity_hits), 1);
for r = 1:height(sensitivity_hits)
    already_primary = strcmp(candidates.hrv_predictor, sensitivity_hits.hrv_predictor{r}) & ...
                       strcmp(candidates.gait_outcome, sensitivity_hits.gait_outcome{r});
    sens_only_mask(r) = ~any(already_primary);
end
sensitivity_only_patterns = sensitivity_hits(sens_only_mask, :);
% classification/explanation/sensitivity_model_available are always
% assigned, regardless of row count, so the table's schema (14 columns,
% fixed types) never changes shape between an empty and a non-empty run --
% repmat(..., 0, 1) below is valid and produces the correctly-typed empty
% column when there are zero rows.
sensitivity_only_patterns.classification = ...
    repmat({'sensitivity_only_candidate_pattern'}, height(sensitivity_only_patterns), 1);
sensitivity_only_patterns.explanation = repmat({[ ...
    'The candidate criterion was met only under the simplified random-intercept-only ' ...
    'specification and was therefore treated as a sensitivity-only, non-robust pattern.']}, ...
    height(sensitivity_only_patterns), 1);
% Every row reaching `sensitivity_only_patterns` was drawn only from rows
% with sensitivity_model_available == true (see row_available above), so
% this column is true on every row here too.
sensitivity_only_patterns.sensitivity_model_available = true(height(sensitivity_only_patterns), 1);

% Run-level flag, broadcast onto every candidate row (see docstring above
% for why this is NOT a per-pair "this pair also has one" indicator).
candidates.sensitivity_only_pattern_present = ...
    repmat(height(sensitivity_only_patterns) > 0, height(candidates), 1);

end

function T = local_empty_sensitivity_only_table()
%LOCAL_EMPTY_SENSITIVITY_ONLY_TABLE Fixed 14-column/correctly-typed empty
%   sensitivity_only_patterns table for the degenerate case where
%   primary_results itself has zero rows -- keeps the exported schema
%   identical to the non-degenerate zero-pattern case below.
T = table('Size', [0, 14], ...
    'VariableTypes', {'cell', 'cell', 'cell', 'logical', 'cell', 'cell', 'cell', ...
                       'double', 'double', 'double', 'double', 'cell', 'cell', 'logical'}, ...
    'VariableNames', {'model_variant', 'hrv_predictor', 'gait_outcome', 'is_candidate', ...
                       'triggering_rest_conditions', 'triggering_speeds', 'triggering_condition_speed_pairs', ...
                       'best_simple_slope_p_raw', 'best_simple_slope_estimate', 'best_p_HRV_raw', 'best_estimate_HRV', ...
                       'classification', 'explanation', 'sensitivity_model_available'});
end
