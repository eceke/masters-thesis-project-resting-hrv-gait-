function out = load_event_csv(file_path, varargin)
%LOAD_EVENT_CSV Load an event-based CSV such as nn_live.csv or bpmbxb_live.csv.
%
% PURPOSE
%   Reads event-style CSV files that typically contain:
%   - column 1: sample index / event index
%   - column 2: event value
%
% INPUT
%   file_path : full path to CSV file
%
% OPTIONAL NAME-VALUE PAIRS
%   'Delimiter'        : delimiter, default ';'
%   'ExpectedCols'     : default 2
%   'SampleRateHz'     : used to compute time_sec from column 1, default []
%   'Col1Name'         : default 'event_idx'
%   'Col2Name'         : default 'value'
%
% OUTPUT
%   out : struct with fields:
%       .file_path
%       .exists
%       .delimiter
%       .sample_rate_hz
%       .table
%       .n_rows
%       .n_cols
%       .warning_messages
%
% OUTPUT TABLE COLUMNS
%   col1 name        : event/sample index
%   col2 name        : event value
%   time_sec         : computed if SampleRateHz given and valid
%
% NOTES
%   - Event-based data must not be treated as regularly sampled time series.
%   - This loader only prepares the data cleanly for later event-specific QC.

p = inputParser;
addRequired(p, 'file_path', @(x) ischar(x) || isstring(x));
addParameter(p, 'Delimiter', ';', @(x) ischar(x) || isstring(x));
addParameter(p, 'ExpectedCols', 2, @(x) isempty(x) || (isscalar(x) && x >= 1));
addParameter(p, 'SampleRateHz', [], @(x) isempty(x) || (isscalar(x) && x > 0));
addParameter(p, 'Col1Name', 'event_idx', @(x) ischar(x) || isstring(x));
addParameter(p, 'Col2Name', 'value', @(x) ischar(x) || isstring(x));
parse(p, file_path, varargin{:});

file_path = char(p.Results.file_path);
delimiter = char(p.Results.Delimiter);
expected_cols = p.Results.ExpectedCols;
sample_rate_hz = p.Results.SampleRateHz;
col1_name = matlab.lang.makeValidName(char(p.Results.Col1Name));
col2_name = matlab.lang.makeValidName(char(p.Results.Col2Name));

out = struct();
out.file_path = file_path;
out.exists = exist(file_path, 'file') == 2;
out.delimiter = delimiter;
out.sample_rate_hz = sample_rate_hz;
out.table = table();
out.n_rows = 0;
out.n_cols = 0;
out.warning_messages = {};

if ~out.exists
    error('load_event_csv:FileNotFound', ...
        'Event CSV file not found: %s', file_path);
end

opts = detectImportOptions(file_path, ...
    'FileType', 'text', ...
    'Delimiter', delimiter);

opts.VariableNamesLine = 0;
opts.DataLine = 1;
opts = setvartype(opts, 'double');

try
    T = readtable(file_path, opts);
catch ME
    error('load_event_csv:ReadFailed', ...
        'Failed to read %s\nReason: %s', file_path, ME.message);
end

if isempty(T)
    out.warning_messages{end+1} = 'Readtable returned an empty event table.';
    out.table = table();
    return;
end

data = table2array(T);

if ~isnumeric(data)
    error('load_event_csv:NonNumericData', ...
        'Loaded data from %s is not numeric after parsing.', file_path);
end

out.n_rows = size(data, 1);
out.n_cols = size(data, 2);

if ~isempty(expected_cols) && out.n_cols ~= expected_cols
    out.warning_messages{end+1} = sprintf( ...
        'Expected %d columns but found %d.', expected_cols, out.n_cols);
end

% Keep at least first two columns if present
if out.n_cols < 2
    error('load_event_csv:TooFewColumns', ...
        'Event file %s has fewer than 2 columns.', file_path);
end

Tclean = table();
Tclean.(col1_name) = data(:,1);
Tclean.(col2_name) = data(:,2);

if ~isempty(sample_rate_hz) && isfinite(sample_rate_hz) && sample_rate_hz > 0
    Tclean.time_sec = Tclean.(col1_name) ./ sample_rate_hz;
else
    Tclean.time_sec = nan(height(Tclean), 1);
    out.warning_messages{end+1} = ...
        'No valid sample rate provided; time_sec set to NaN.';
end

% Keep extra columns if they exist, for transparency
if out.n_cols > 2
    for k = 3:out.n_cols
        extra_name = sprintf('extra_col_%d', k);
        Tclean.(extra_name) = data(:,k);
    end
    out.warning_messages{end+1} = ...
        sprintf('Event file has %d columns; extra columns preserved.', out.n_cols);
end

if any(diff(Tclean.(col1_name)) < 0)
    out.warning_messages{end+1} = ...
        'Event index/sample index is not monotonically increasing.';
end

if all(isnan(Tclean.(col2_name)))
    out.warning_messages{end+1} = ...
        'All event values are NaN.';
end

out.table = Tclean;

end