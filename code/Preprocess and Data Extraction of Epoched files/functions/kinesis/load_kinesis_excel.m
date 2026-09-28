function out = load_kinesis_excel(cfg)
%LOAD_KINESIS_EXCEL Load Kinesis gait Excel file.
%
% This function only loads the Excel file and performs basic structural checks.
% It does NOT clean or merge the data yet.

%% Validate config
if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'kinesis_file')
    error('load_kinesis_excel:MissingConfigPath', ...
        'cfg.paths.kinesis_file is missing.');
end

file_path = cfg.paths.kinesis_file;

if ~isfile(file_path)
    error('load_kinesis_excel:FileNotFound', ...
        'Kinesis Excel file not found: %s', file_path);
end

%% Init output
out = struct();
out.file_path = file_path;
out.sheet_name = '';
out.raw_table = table();
out.variable_names_original = {};
out.variable_names_matlab = {};
out.n_rows = 0;
out.n_cols = 0;
out.required_columns_present = false;
out.missing_required_columns = {};
out.warnings = {};

%% Detect sheets
sheets = sheetnames(file_path);

if isempty(sheets)
    error('load_kinesis_excel:NoSheets', ...
        'No sheets found in Kinesis Excel file.');
end

% Prefer Report Results if it exists.
preferred_sheet = 'Report Results';

if any(strcmp(sheets, preferred_sheet))
    sheet_to_read = preferred_sheet;
else
    sheet_to_read = sheets{1};
    out.warnings{end+1} = sprintf( ...
        'Preferred sheet "%s" not found. Using first sheet "%s".', ...
        preferred_sheet, sheet_to_read);
end

out.sheet_name = sheet_to_read;

%% Read table
opts = detectImportOptions(file_path, 'Sheet', sheet_to_read);

% Preserve readable variable names as much as MATLAB allows.
opts.VariableNamingRule = 'modify';

T = readtable(file_path, opts);

out.raw_table = T;
out.variable_names_matlab = T.Properties.VariableNames;
out.variable_names_original = opts.VariableNames;
out.n_rows = height(T);
out.n_cols = width(T);

%% Required structural columns
required_cols = { ...
    'PatientID', ...
    'Condition', ...
    'Task', ...
    'Speed'};

missing = {};

for i = 1:numel(required_cols)
    if ~ismember(required_cols{i}, T.Properties.VariableNames)
        missing{end+1} = required_cols{i}; %#ok<AGROW>
    end
end

out.missing_required_columns = missing;
out.required_columns_present = isempty(missing);

if ~out.required_columns_present
    out.warnings{end+1} = sprintf( ...
        'Missing required Kinesis columns: %s', ...
        strjoin(missing, ', '));
end

end