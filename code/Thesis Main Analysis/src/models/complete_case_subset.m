function [T_sub, n_removed, participants_excluded, n_participants_used] = ...
    complete_case_subset(T, needed_cols, participant_col)
%COMPLETE_CASE_SUBSET Model-wise complete-case filtering: drop rows
%   missing any value needed by the current model without changing the
%   data used by other models. No imputation is performed in the pipeline.

sub = T(:, needed_cols);
complete_mask = true(height(T), 1);
for i = 1:numel(needed_cols)
    col = sub.(needed_cols{i});
    if iscategorical(col)
        complete_mask = complete_mask & ~isundefined(col);
    else
        complete_mask = complete_mask & ~isnan(col);
    end
end

T_sub = T(complete_mask, :);
n_removed = height(T) - height(T_sub);

all_participants = unique(T.(participant_col));
kept_participants = unique(T_sub.(participant_col));
excluded = setdiff(all_participants, kept_participants);
participants_excluded = cellstr(excluded);
n_participants_used = numel(kept_participants);

end
