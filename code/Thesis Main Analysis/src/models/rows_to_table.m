function T = rows_to_table(rows)
%ROWS_TO_TABLE Convert a cell array of per-model result structs into a
%   single results table. Normalizes field sets/order across rows first so
%   struct concatenation is always well-defined, even if a caller added a
%   field to only some rows.

if isempty(rows)
    T = table();
    return;
end

all_fields = fieldnames(rows{1});
for i = 2:numel(rows)
    all_fields = union(all_fields, fieldnames(rows{i}), 'stable');
end

for i = 1:numel(rows)
    for f = 1:numel(all_fields)
        if ~isfield(rows{i}, all_fields{f})
            rows{i}.(all_fields{f}) = NaN;
        end
    end
    rows{i} = orderfields(rows{i}, all_fields);
end

S = [rows{:}];
if isscalar(S)
    % Treat a single result struct as one table row. Without AsArray=true,
    % MATLAB may interpret fields with different lengths as separate rows.
    T = struct2table(S, 'AsArray', true);
else
    T = struct2table(S);
end

end
