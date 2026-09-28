function q = fdr_bh(p)
%FDR_BH Benjamini-Hochberg FDR-adjusted p-values (step-up procedure).

p = p(:);
q = nan(size(p));
valid = ~isnan(p);
pv = p(valid);
m = numel(pv);

if m == 0
    return;
end

[ps, idx] = sort(pv);
ranks = (1:m)';
q_sorted = ps .* m ./ ranks;

% enforce monotonicity required by the step-up procedure
q_sorted = flipud(cummin(flipud(q_sorted)));
q_sorted = min(q_sorted, 1);

q_valid = nan(m, 1);
q_valid(idx) = q_sorted;
q(valid) = q_valid;

end
