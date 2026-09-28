function [selected, selectedCanonical] = local_select_predictors(candidates, maxN, predictorLabel)
%LOCAL_SELECT_PREDICTORS Let user select 0..maxN candidate predictors.
% Returns both source column names and their canonical names when available.

if isempty(candidates) || height(candidates) == 0
    fprintf('No %s candidates are available. Selecting none.\n', predictorLabel);
    selected = strings(0, 1);
    selectedCanonical = strings(0, 1);
    return;
end

while true
    fprintf('\nSelect up to %d %s predictor(s).\n', maxN, predictorLabel);
    fprintf('Enter 0 for none, or enter numbers separated by spaces/commas.\n');
    raw = strtrim(input(sprintf('%s selection: ', upper(predictorLabel)), 's'));

    if strcmp(raw, '0')
        selected = strings(0, 1);
        selectedCanonical = strings(0, 1);
        return;
    end

    tokens = regexp(raw, '\d+', 'match');
    if isempty(tokens)
        fprintf('Invalid input. Example: 1 2 3, or 0 for none.\n');
        continue;
    end

    nums = str2double(tokens);
    nums = unique(nums, 'stable');

    if any(isnan(nums)) || any(nums < 1) || any(nums > height(candidates))
        fprintf('Invalid selection. Please choose numbers between 1 and %d, or 0.\n', height(candidates));
        continue;
    end

    if numel(nums) > maxN
        fprintf('You selected %d predictors. Maximum allowed is %d. Please select again.\n', numel(nums), maxN);
        continue;
    end

    selected = string(candidates.ColumnName(nums));
    selected = selected(:);

    if ismember('CanonicalName', candidates.Properties.VariableNames)
        selectedCanonical = string(candidates.CanonicalName(nums));
        selectedCanonical = selectedCanonical(:);

        % Prevent the same conceptual predictor from being selected twice via
        % two source aliases (e.g., RMSSD and RMSSD_ecg).
        if numel(unique(selectedCanonical, 'stable')) ~= numel(selectedCanonical)
            fprintf(['The same canonical %s predictor was selected more than once via different source columns.\n' ...
                     'Please choose only one source column for each conceptual predictor.\n'], predictorLabel);
            continue;
        end
    else
        selectedCanonical = selected;
    end

    return;
end
end
