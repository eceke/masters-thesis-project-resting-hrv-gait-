function s = summarize_coef_rows(rows)
%SUMMARIZE_COEF_ROWS Collapse a 1-row (or empty) slice of a
%   LinearMixedModel Coefficients table into a plain struct, defaulting to
%   NaN/'' fields when the term wasn't found (skipped model, absent
%   interaction, etc). If more than one row is passed, only the first is
%   summarized -- callers needing every row of a multi-level interaction
%   (e.g. HRV x rest_condition with 3 levels) should keep the raw table
%   instead, as done for terms.hrv_x_rest in extract_hrv_terms.m.

s = struct('estimate', NaN, 'se', NaN, 'tStat', NaN, 'df', NaN, ...
            'pValue', NaN, 'ci_lower', NaN, 'ci_upper', NaN, 'name', '');
if isempty(rows) || height(rows) == 0
    return;
end
r = rows(1, :);
s.estimate = r.Estimate;
s.se = r.SE;
s.tStat = r.tStat;
s.df = r.DF;
s.pValue = r.pValue;
s.ci_lower = r.Lower;
s.ci_upper = r.Upper;
s.name = r.Name{1};

end
