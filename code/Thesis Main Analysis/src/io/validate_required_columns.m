function [T, report] = validate_required_columns(T, cfg)
%VALIDATE_REQUIRED_COLUMNS Check that every column the pipeline needs is
%   present, deriving speed_factor from walking_speed_kmh when the raw file
%   uses that alias instead. Errors out (with the full list of missing
%   columns) if anything required is still absent.

report = struct();
report.missing_columns = {};
report.derived_columns = {};

if ~ismember(cfg.speed_col, T.Properties.VariableNames)
    if ismember('walking_speed_kmh', T.Properties.VariableNames)
        spd = T.walking_speed_kmh;
        factor_str = cell(height(T), 1);
        factor_str(spd == 1) = {'1'};
        factor_str(spd == 4) = {'4'};
        unmapped = cellfun(@isempty, factor_str);
        if any(unmapped)
            error('validate_required_columns:unexpectedSpeedValue', ...
                ['walking_speed_kmh contains value(s) other than 1 or 4 ', ...
                 '(expected exactly two speed levels: 1 km/h and 4 km/h).']);
        end
        T.(cfg.speed_col) = factor_str;
        report.derived_columns{end+1} = sprintf('%s <- walking_speed_kmh', cfg.speed_col);
    else
        report.missing_columns{end+1} = cfg.speed_col;
    end
end

required_core = {cfg.participant_col, cfg.rest_condition_col, ...
                  cfg.walking_task_col, cfg.speed_col, cfg.kinesis_col};
required_hrv  = cfg.hrv_var_names(:)';
required_gait = cfg.gait_vars;

all_required = [required_core, required_hrv, required_gait];
present = ismember(all_required, T.Properties.VariableNames);
report.missing_columns = unique([report.missing_columns, all_required(~present)], 'stable');

if ~isempty(report.missing_columns)
    error('validate_required_columns:missingColumns', ...
        'Missing required column(s): %s', strjoin(report.missing_columns, ', '));
end

report.n_rows = height(T);
report.n_participants = numel(unique(T.(cfg.participant_col)));
report.columns_found = T.Properties.VariableNames;

end
