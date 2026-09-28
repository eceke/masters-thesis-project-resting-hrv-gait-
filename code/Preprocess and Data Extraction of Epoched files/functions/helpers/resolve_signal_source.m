function file_info = resolve_signal_source(participant_id, segment_name, segment_path, expected_name)
%RESOLVE_SIGNAL_SOURCE Resolve raw and Physical paths for one expected file.
%
% RULES
%   - For CSV signal/data files:
%       raw path exists in segment root
%       physical path is expected in Physical/ with participant+segment prefix
%       preferred source = physical
%
%   - For unisens.xml:
%       only raw XML is required
%       preferred source = raw
%       no physical XML is expected
%
% INPUT
%   participant_id : e.g. 'VP1'
%   segment_name   : e.g. 'BW_1KMH'
%   segment_path   : full path to segment folder
%   expected_name  : e.g. 'acc.csv' or 'unisens.xml'
%
% OUTPUT
%   file_info : struct with fields
%       .expected_name
%       .raw_path
%       .raw_exists
%       .physical_path
%       .physical_exists
%       .preferred_source
%       .preferred_path
%       .status

file_info = struct();
file_info.expected_name = expected_name;

% Raw path
raw_path = fullfile(segment_path, expected_name);
raw_exists = exist(raw_path, 'file') == 2;

file_info.raw_path = raw_path;
file_info.raw_exists = raw_exists;

% Special rule for XML
if strcmpi(expected_name, 'unisens.xml')
    file_info.physical_path = '';
    file_info.physical_exists = false;
    file_info.preferred_source = 'raw';
    file_info.preferred_path = raw_path;

    if raw_exists
        file_info.status = 'complete_xml_raw_only';
    else
        file_info.status = 'missing_raw_xml';
    end
    return;
end

% Physical path for CSV/data files
physical_dir = fullfile(segment_path, 'Physical');
physical_name = sprintf('%s_%s_%s', participant_id, segment_name, expected_name);
physical_path = fullfile(physical_dir, physical_name);
physical_exists = exist(physical_path, 'file') == 2;

file_info.physical_path = physical_path;
file_info.physical_exists = physical_exists;

% Preferred source
if physical_exists
    file_info.preferred_source = 'physical';
    file_info.preferred_path = physical_path;
else
    file_info.preferred_source = 'raw';
    file_info.preferred_path = raw_path;
end

% Status
if raw_exists && physical_exists
    file_info.status = 'complete';
elseif ~raw_exists && ~physical_exists
    file_info.status = 'missing_both';
elseif ~raw_exists
    file_info.status = 'missing_raw';
elseif ~physical_exists
    file_info.status = 'missing_physical';
else
    file_info.status = 'unknown';
end

end