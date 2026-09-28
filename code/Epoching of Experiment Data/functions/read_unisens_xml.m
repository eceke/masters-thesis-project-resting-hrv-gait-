function meta = read_unisens_xml(xmlPath)
% Parse Movisens/Unisens XML metadata for CSV channels.
% Returns a struct with:
%   meta.timestampStart   (datetime, or [])
%   meta.durationSec      (double, or NaN)
%   meta.measurementId    (char, or '')
%   meta.files.(field)    struct for each CSV id, with:
%       .id              original file id (e.g., 'ecg.csv')
%       .entryType       'signalEntry' or 'valuesEntry'
%       .contentClass
%       .comment
%       .dataType
%       .sampleRate      double
%       .lsbValue        double (default 1 if missing)
%       .baseline        double (default NaN if missing)
%       .unit            char
%       .csv.separator   char
%       .csv.decimalSeparator char
%       .channels        cellstr of channel names
%   meta.fileIds          cellstr original ids (in order)
%   meta.fileFieldNames   cellstr corresponding struct field names
%
% Notes:
% - Uses xmlread (DOM). Works with both <signalEntry> and <valuesEntry>.
% - If an attribute is missing, safe defaults are used.

    arguments
        xmlPath (1,:) char
    end

    if ~isfile(xmlPath)
        error('read_unisens_xml:FileNotFound', 'XML not found: %s', xmlPath);
    end

    % --- Read DOM
    try
        doc = xmlread(xmlPath);
    catch ME
        error('read_unisens_xml:XmlReadFailed', ...
            'Failed to read XML. Path: %s\n%s', xmlPath, ME.message);
    end

    root = doc.getDocumentElement(); % e.g., <unisens ...>

    % --- Root-level attributes (common in Unisens)
    meta = struct();
    meta.xmlPath = xmlPath;

    meta.measurementId  = getAttrAsChar(root, 'measurementId', '');
    meta.durationSec    = getAttrAsDouble(root, 'duration', NaN);

    % timestampStart can look like "2025-03-20T10:38:59.455"
    tsStr = getAttrAsChar(root, 'timestampStart', '');
    meta.timestampStart = parseTimestamp(tsStr);

    % --- Collect entries: signalEntry + valuesEntry
    entries = {};
    entries = [entries; nodeListToCell(root.getElementsByTagName('signalEntry'))];
    entries = [entries; nodeListToCell(root.getElementsByTagName('valuesEntry'))];

    meta.files = struct();
    meta.fileIds = {};
    meta.fileFieldNames = {};

    for i = 1:numel(entries)
        node = entries{i};

        id = getAttrAsChar(node, 'id', '');
        if isempty(id)
            continue; % skip malformed
        end

        % Make a safe field name for struct usage
        f = matlab.lang.makeValidName(id);
        % If collision, disambiguate
        f = ensureUniqueField(meta.files, f);

        info = struct();
        info.id         = id;
        info.entryType  = char(node.getNodeName());

        info.comment     = getAttrAsChar(node, 'comment', '');
        info.contentClass= getAttrAsChar(node, 'contentClass', '');
        info.dataType    = getAttrAsChar(node, 'dataType', '');

        info.sampleRate  = getAttrAsDouble(node, 'sampleRate', NaN);
        info.lsbValue    = getAttrAsDouble(node, 'lsbValue', 1.0);
        info.baseline    = getAttrAsDouble(node, 'baseline', NaN);
        info.unit        = getAttrAsChar(node, 'unit', '');

        % csvFileFormat child (optional)
        info.csv = struct('separator', '', 'decimalSeparator', '');
        cffList = node.getElementsByTagName('csvFileFormat');
        if cffList.getLength() > 0
            cff = cffList.item(0);
            info.csv.separator        = getAttrAsChar(cff, 'separator', '');
            info.csv.decimalSeparator = getAttrAsChar(cff, 'decimalSeparator', '');
        end

        % channel children
        info.channels = {};
        chList = node.getElementsByTagName('channel');
        for k = 0:(chList.getLength()-1)
            chNode = chList.item(k);
            chName = getAttrAsChar(chNode, 'name', '');
            if ~isempty(chName)
                info.channels{end+1,1} = chName; %#ok<AGROW>
            end
        end

        % Save
        meta.files.(f) = info;
        meta.fileIds{end+1,1} = id; %#ok<AGROW>
        meta.fileFieldNames{end+1,1} = f; %#ok<AGROW>
    end

    % Convenience lookup map: id -> field name
    meta.idToField = containers.Map(meta.fileIds, meta.fileFieldNames);

end

%% ===== Helpers =====

function out = nodeListToCell(nodeList)
    out = cell(nodeList.getLength(), 1);
    for ii = 0:(nodeList.getLength()-1)
        out{ii+1} = nodeList.item(ii);
    end
end

function s = getAttrAsChar(node, attrName, defaultValue)
    s = defaultValue;
    if isempty(node) || ~node.hasAttributes()
        return;
    end
    attrs = node.getAttributes();
    if isempty(attrs)
        return;
    end
    a = attrs.getNamedItem(attrName);
    if isempty(a)
        return;
    end
    s = char(a.getValue());
end

function v = getAttrAsDouble(node, attrName, defaultValue)
    str = getAttrAsChar(node, attrName, '');
    if isempty(str)
        v = defaultValue;
        return;
    end
    v = str2double(str);
    if isnan(v)
        v = defaultValue;
    end
end

function dt = parseTimestamp(tsStr)
    if isempty(tsStr)
        dt = [];
        return;
    end

    % Common format: 2025-03-20T10:38:59.455
    % Try with milliseconds first, then without.
    try
        dt = datetime(tsStr, 'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSS', 'TimeZone','local');
        return;
    catch
    end
    try
        dt = datetime(tsStr, 'InputFormat','yyyy-MM-dd''T''HH:mm:ss', 'TimeZone','local');
        return;
    catch
    end

    % Fallback: let MATLAB try
    try
        dt = datetime(tsStr, 'TimeZone','local');
    catch
        dt = [];
    end
end

function f = ensureUniqueField(s, f)
    if ~isfield(s, f)
        return;
    end
    base = f;
    n = 2;
    while isfield(s, sprintf('%s_%d', base, n))
        n = n + 1;
    end
    f = sprintf('%s_%d', base, n);
end
