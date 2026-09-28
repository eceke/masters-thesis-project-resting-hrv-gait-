function [T, report] = load_gait_hrv_data(csv_path, cfg)
%LOAD_GAIT_HRV_DATA Read the long-format HRV-gait CSV (Step 1) and validate
%   its schema (Step 2).

if ~isfile(csv_path)
    error('load_gait_hrv_data:fileNotFound', ...
        ['Data file not found: %s\n', ...
         'Place the long-format LMM_HRV_GAIT_long.csv in the data/ folder, ', ...
         'or pass a path explicitly via run_analysis(''DataFile'', path).'], csv_path);
end

opts = detectImportOptions(csv_path);

numeric_candidates = intersect([cfg.hrv_var_names(:); cfg.gait_vars(:)], opts.VariableNames);
if ~isempty(numeric_candidates)
    opts = setvartype(opts, numeric_candidates(:)', 'double');
end

T = readtable(csv_path, opts);

[T, report] = validate_required_columns(T, cfg);

fprintf('  Loaded %d rows, %d participants from %s\n', ...
    report.n_rows, report.n_participants, csv_path);
if ~isempty(report.derived_columns)
    fprintf('  Derived columns: %s\n', strjoin(report.derived_columns, ', '));
end

end
