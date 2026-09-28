function T = prepare_categorical_variables(T, cfg)
%PREPARE_CATEGORICAL_VARIABLES Cast design columns to categorical (Step 3).
%   The category order given to `categorical()` fixes the reference
%   (omitted) level used by fitlme's dummy coding, so reference levels are
%   set explicitly and logged rather than left to alphabetical default.

T.(cfg.participant_col) = categorical(T.(cfg.participant_col));

T.(cfg.rest_condition_col) = categorical(cellstr(string(T.(cfg.rest_condition_col))), ...
    cfg.rest_condition_levels);

speed_levels = cfg.speed_levels;
if ~strcmp(speed_levels{1}, cfg.speed_reference)
    speed_levels = [{cfg.speed_reference}, setdiff(speed_levels, cfg.speed_reference, 'stable')];
end
T.(cfg.speed_col) = categorical(cellstr(string(T.(cfg.speed_col))), speed_levels);

T.(cfg.walking_task_col) = categorical( ...
    cellstr(string(T.(cfg.walking_task_col))), ...
    cfg.walking_task_levels);

T.(cfg.kinesis_col) = categorical( ...
    cellstr(string(T.(cfg.kinesis_col))), ...
    cfg.kinesis_levels);

walking_task_cats = categories(T.(cfg.walking_task_col));
kinesis_cats = categories(T.(cfg.kinesis_col));

fprintf('  speed_factor reference level    = %s\n', speed_levels{1});
fprintf('  rest_condition reference level  = %s\n', cfg.rest_condition_levels{1});
fprintf('  walking_task reference level    = %s\n', walking_task_cats{1});
fprintf('  kinesis_condition reference lvl = %s\n', kinesis_cats{1});

end
