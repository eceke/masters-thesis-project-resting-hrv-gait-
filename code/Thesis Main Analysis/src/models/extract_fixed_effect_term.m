function s = extract_fixed_effect_term(m, var_col)
%EXTRACT_FIXED_EFFECT_TERM Pull a categorical fixed-effect coefficient
%   (e.g. walking_task) out of a fitted LinearMixedModel's coefficient
%   table, matched by "<var_col>_" name prefix. Assumes the factor is
%   two-level (a single non-reference dummy), matching the configured
%   walking_task design (BW vs FWW); if the factor ever has more
%   than one non-reference level only the first matching row is
%   summarized -- see extract_hrv_terms.m's find_interaction_rows/raw-table
%   pattern for the multi-row-aware alternative.

coefT = m.Coefficients;
if ~istable(coefT)
    coefT = dataset2table(coefT);
end

prefix = [var_col '_'];
mask = strncmp(coefT.Name, prefix, numel(prefix));
s = summarize_coef_rows(coefT(mask, :));

end
