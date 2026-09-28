function write_unisens_xml_aligned(outputDir, keptIds, commonStart, commonDurationSec, templateXmlPath)
%WRITE_UNISENS_XML_ALIGNED Write aligned unisens.xml for an output folder.
%
% INPUT
%   outputDir          : target aligned folder
%   keptIds            : cell array of kept file ids, e.g. {'ecg.csv','acc.csv'}
%   commonStart        : datetime
%   commonDurationSec  : double
%   templateXmlPath    : original source unisens.xml path

    arguments
        outputDir (1,:) char
        keptIds cell
        commonStart datetime
        commonDurationSec (1,1) double
        templateXmlPath (1,:) char
    end

    if ~isfolder(outputDir)
        error('write_unisens_xml_aligned:OutputDirMissing', ...
            'Output directory not found: %s', outputDir);
    end

    if ~isfile(templateXmlPath)
        error('write_unisens_xml_aligned:TemplateMissing', ...
            'Template XML not found: %s', templateXmlPath);
    end

    doc = xmlread(templateXmlPath);
    root = doc.getDocumentElement;
    nsUri = char(root.getNamespaceURI);

    % Update duration
    root.setAttribute('duration', num2str(commonDurationSec, '%.15g'));

    % Update timestampStart
    commonStartStr = char(datetime(commonStart, 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));
    root.setAttribute('timestampStart', commonStartStr);

    % Update timestampStartUTC custom attribute if present
    ca = root.getElementsByTagNameNS(nsUri, 'customAttribute');
    for k = 0:ca.getLength-1
        node = ca.item(k);
        if node.hasAttribute('key') && strcmp(char(node.getAttribute('key')), 'timestampStartUTC')
            node.setAttribute('value', commonStartStr);
        end
    end

    % Remove all entries first
    remove_all_by_tag_local(root, nsUri, 'signalEntry');
    remove_all_by_tag_local(root, nsUri, 'valuesEntry');

    % Re-add only kept ids from template
    templateDoc = xmlread(templateXmlPath);
    for i = 1:numel(keptIds)
        idStr = keptIds{i};
        entryNode = find_entry_by_id_local(templateDoc, nsUri, idStr);
        if isempty(entryNode)
            warning('write_unisens_xml_aligned:MissingEntry', ...
                'Entry %s not found in template XML.', idStr);
            continue;
        end

        imported = doc.importNode(entryNode, true);
        root.appendChild(imported);
    end

    outPath = fullfile(outputDir, 'unisens.xml');
    xmlwrite(outPath, doc);
end

function entryNode = find_entry_by_id_local(doc, ~, idStr)
    entryNode = [];

    sig = doc.getElementsByTagName('signalEntry');
    for k = 0:sig.getLength-1
        n = sig.item(k);
        if n.hasAttribute('id') && strcmp(char(n.getAttribute('id')), idStr)
            entryNode = n;
            return;
        end
    end

    val = doc.getElementsByTagName('valuesEntry');
    for k = 0:val.getLength-1
        n = val.item(k);
        if n.hasAttribute('id') && strcmp(char(n.getAttribute('id')), idStr)
            entryNode = n;
            return;
        end
    end
end

function remove_all_by_tag_local(root, ~, tagName)
    nodes = root.getElementsByTagName(tagName);

    toRemove = cell(nodes.getLength, 1);
    for k = 0:nodes.getLength-1
        toRemove{k+1} = nodes.item(k);
    end

    for k = 1:numel(toRemove)
        n = toRemove{k};
        if ~isempty(n) && ~isempty(n.getParentNode)
            n.getParentNode.removeChild(n);
        end
    end
end