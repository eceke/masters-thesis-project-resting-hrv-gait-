function meta = parse_unisens_xml(xml_file)
%PARSE_UNISENS_XML Parse relevant metadata from a Unisens XML file.
%
% PURPOSE
%   Reads unisens.xml and extracts metadata needed later for loading and
%   preprocessing signal files.
%
% INPUT
%   xml_file : full path to unisens.xml
%
% OUTPUT
%   meta : struct with fields:
%       .xml_file
%       .exists
%       .measurement_id
%       .timestamp_start
%       .duration_sec
%       .entries
%       .entry_lookup
%
% Each entry in meta.entries contains:
%   .id
%   .entryType
%   .sampleRate
%   .lsbValue
%   .baseline
%   .unit
%   .dataType
%   .contentClass
%   .comment
%   .separator
%   .decimalSeparator
%   .channelNames
%
% NOTES
%   - Missing attributes are returned as NaN, '' or {} as appropriate.
%   - This function is intentionally conservative and metadata-focused.

meta = struct();
meta.xml_file = xml_file;
meta.exists = exist(xml_file, 'file') == 2;
meta.measurement_id = '';
meta.timestamp_start = '';
meta.duration_sec = NaN;
meta.entries = local_empty_entry_struct();
meta.entry_lookup = struct();

if ~meta.exists
    error('parse_unisens_xml:FileNotFound', ...
        'Unisens XML file not found: %s', xml_file);
end

try
    xDoc = xmlread(xml_file);
catch ME
    error('parse_unisens_xml:XMLReadFailed', ...
        'Failed to read XML file %s\nReason: %s', xml_file, ME.message);
end

root = xDoc.getDocumentElement();

% Root-level attributes
meta.measurement_id = local_get_attr(root, 'measurementId');
meta.timestamp_start = local_get_attr(root, 'timestampStart');
duration_str = local_get_attr(root, 'duration');
meta.duration_sec = local_str2double_or_nan(duration_str);

children = root.getChildNodes();

entries_cell = {};

for i = 0:children.getLength()-1
    node = children.item(i);

    if node.getNodeType() ~= node.ELEMENT_NODE
        continue;
    end

    node_name = char(node.getNodeName());

    if ~ismember(node_name, {'signalEntry', 'valuesEntry'})
        continue;
    end

    entry = local_empty_entry_struct();
    entry.entryType = node_name;
    entry.id = local_get_attr(node, 'id');
    entry.sampleRate = local_str2double_or_nan(local_get_attr(node, 'sampleRate'));
    entry.lsbValue = local_str2double_or_nan(local_get_attr(node, 'lsbValue'));
    entry.baseline = local_str2double_or_nan(local_get_attr(node, 'baseline'));
    entry.unit = local_get_attr(node, 'unit');
    entry.dataType = local_get_attr(node, 'dataType');
    entry.contentClass = local_get_attr(node, 'contentClass');
    entry.comment = local_get_attr(node, 'comment');

    grandchildren = node.getChildNodes();
    for j = 0:grandchildren.getLength()-1
        subnode = grandchildren.item(j);

        if subnode.getNodeType() ~= subnode.ELEMENT_NODE
            continue;
        end

        subnode_name = char(subnode.getNodeName());

        if strcmp(subnode_name, 'csvFileFormat')
            entry.separator = local_get_attr(subnode, 'separator');
            entry.decimalSeparator = local_get_attr(subnode, 'decimalSeparator');

        elseif strcmp(subnode_name, 'channel')
            ch_name = local_get_attr(subnode, 'name');
            if ~isempty(ch_name)
                entry.channelNames{end+1} = ch_name; %#ok<AGROW>
            end
        end
    end

    entries_cell{end+1} = entry; %#ok<AGROW>

    if ~isempty(entry.id)
        field_name = matlab.lang.makeValidName(entry.id);
        meta.entry_lookup.(field_name) = entry;
    end
end

if isempty(entries_cell)
    meta.entries = local_empty_entry_struct();
    meta.entries = meta.entries([]); % proper empty struct array with fixed fields
else
    meta.entries = [entries_cell{:}];
end

end

%% ------------------------------------------------------------------------
function entry = local_empty_entry_struct()
% Return an entry struct with fixed fields to avoid structure mismatch.

entry = struct( ...
    'id', '', ...
    'entryType', '', ...
    'sampleRate', NaN, ...
    'lsbValue', NaN, ...
    'baseline', NaN, ...
    'unit', '', ...
    'dataType', '', ...
    'contentClass', '', ...
    'comment', '', ...
    'separator', '', ...
    'decimalSeparator', '', ...
    'channelNames', {{}});
end

%% ------------------------------------------------------------------------
function value = local_get_attr(node, attr_name)
% Safely read XML attribute, return '' if absent.

value = '';

if isempty(node) || ~node.hasAttributes()
    return;
end

attrs = node.getAttributes();
attr = attrs.getNamedItem(attr_name);

if isempty(attr)
    return;
end

value = char(attr.getValue());
end

%% ------------------------------------------------------------------------
function x = local_str2double_or_nan(s)
% Convert string to double, return NaN if conversion fails.

if isempty(s)
    x = NaN;
    return;
end

x = str2double(s);
if isnan(x)
    x = NaN;
end
end