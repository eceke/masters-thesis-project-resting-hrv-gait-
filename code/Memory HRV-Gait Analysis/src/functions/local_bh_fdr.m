function T = local_bh_fdr(T)
%LOCAL_BH_FDR Benjamini-Hochberg FDR correction for result table.

if isempty(T) || height(T) == 0
    return;
end

if ~ismember('p', T.Properties.VariableNames)
    return;
end

if ~ismember('p_FDR', T.Properties.VariableNames)
    T.p_FDR = NaN(height(T), 1);
else
    T.p_FDR(:) = NaN;
end

p = T.p;
valid = isfinite(p) & p >= 0 & p <= 1;

if ~any(valid)
    return;
end

pValid = p(valid);
[sortedP, order] = sort(pValid);
m = numel(sortedP);
rawQ = sortedP .* m ./ (1:m)';

% Enforce monotonicity from largest to smallest p-value.
qSorted = rawQ;
for i = m-1:-1:1
    qSorted(i) = min(qSorted(i), qSorted(i+1));
end
qSorted = min(qSorted, 1);

qValid = NaN(size(pValid));
qValid(order) = qSorted;

idxValid = find(valid);
T.p_FDR(idxValid) = qValid;
end
