function out = load_simple_csv_column(file_path, varargin)
%LOAD_SIMPLE_CSV_COLUMN Load a simple numeric CSV file robustly.
%
% PURPOSE
%   Reads simple CSV-style files that usually contain one numeric column,
%   but may sometimes contain multiple columns. Returns raw numeric matrix
%   and convenience summaries for debugging.
%
% INPUT
%   file_path : full path to CSV file
%
% OPTIONAL NAME-VALUE PAIRS
%   'Delimiter'       : delimiter character, default ';'
%   'ExpectedCols'    : expected number of columns, default []
%   'HasHeader'       : true/false, default false
%   'VariableName'    : optional name label for output
%
% OUTPUT
%   out : struct with fields:
%       .file_path
%       .exists
%       .delimiter
%       .expected_cols
%       .variable_name
%       .data
%       .n_rows
%       .n_cols
%       .numeric_parse_success
%       .warning_messages
%
% NOTES
%   - This function is intentionally generic and transparent.
%   - It does not apply preprocessing decisions.

p = inputParser;
addRequired(p, 'file_path', @(x) ischar(x) || isstring(x));
addParameter(p, 'Delimiter', ';', @(x) ischar(x) || isstring(x));
addParameter(p, 'ExpectedCols', [], @(x) isempty(x) || (isscalar(x) && x >= 1));
addParameter(p, 'HasHeader', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'VariableName', '', @(x) ischar(x) || isstring(x));
parse(p, file_path, varargin{:});

file_path = char(p.Results.file_path);
delimiter = char(p.Results.Delimiter);
expected_cols = p.Results.ExpectedCols;
has_header = logical(p.Results.HasHeader);
variable_name = char(p.Results.VariableName);

out = struct();
out.file_path = file_path;
out.exists = exist(file_path, 'file') == 2;
out.delimiter = delimiter;
out.expected_cols = expected_cols;
out.variable_name = variable_name;
out.data = [];
out.n_rows = 0;
out.n_cols = 0;
out.numeric_parse_success = false;
out.warning_messages = {};

if ~out.exists
    error('load_simple_csv_column:FileNotFound', ...
        'CSV file not found: %s', file_path);
end

opts = detectImportOptions(file_path, ...
    'FileType', 'text', ...
    'Delimiter', delimiter);

opts = setvartype(opts, 'double');

if ~has_header
    opts.VariableNamesLine = 0;
    opts.DataLine = 1;
end

try
    T = readtable(file_path, opts);
catch ME
    error('load_simple_csv_column:ReadFailed', ...
        'Failed to read %s\nReason: %s', file_path, ME.message);
end

if isempty(T)
    out.warning_messages{end+1} = 'Readtable returned an empty table.';
    out.data = [];
    out.n_rows = 0;
    out.n_cols = 0;
    out.numeric_parse_success = true;
    return;
end

data = table2array(T);

if ~isnumeric(data)
    error('load_simple_csv_column:NonNumericData', ...
        'Loaded data from %s is not numeric after parsing.', file_path);
end

out.data = data;
out.n_rows = size(data, 1);
out.n_cols = size(data, 2);
out.numeric_parse_success = true;

if ~isempty(expected_cols) && out.n_cols ~= expected_cols
    out.warning_messages{end+1} = sprintf( ...
        'Expected %d columns but found %d.', expected_cols, out.n_cols);
end

if out.n_rows == 0
    out.warning_messages{end+1} = 'File contains zero rows.';
end

if all(all(isnan(out.data)))
    out.warning_messages{end+1} = 'All loaded values are NaN.';
end

end