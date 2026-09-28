function write_unisens_xml_segment(segmentDir, segName, segStartSec, segDurationSec, savedChannels, dataStruct, cfg, ...
    templateDoc, nsUri, templateStartTs, templateStartUtc)
%WRITE_UNISENS_XML_SEGMENT
% Creates a new unisens.xml inside a cut segment folder so that DataAnalyzer
% can open the segment as a standalone Unisens measurement.
%
% - Keeps existing CSV filenames (e.g., VP01_BW_1KMH_ecg.csv).
% - Copies the matching signalEntry/valuesEntry nodes from the original
%   unisens.xml, preserving baseline/lsbValue/unit/sampleRate/etc.
% - Updates root duration and timestamps.
% - Updates each entry's id to the segment CSV filename.

    arguments
        segmentDir (1,:) char
        segName (1,:) char
        segStartSec (1,1) double
        segDurationSec (1,1) double
        savedChannels cell
        dataStruct struct
        cfg (1,1) struct
        templateDoc
        nsUri (1,:) char
        templateStartTs (1,:) char
        templateStartUtc (1,:) char
    end

    if ~exist(segmentDir, 'dir')
        error('Segment directory not found: %s', segmentDir);
    end

    % Clone template document
    segDoc = templateDoc.cloneNode(true);
    root = segDoc.getDocumentElement;

    % Update duration
    root.setAttribute('duration', num2str(segDurationSec, '%.15g'));

    % Update timestampStart
    newStart = add_seconds_to_iso(templateStartTs, segStartSec);
    if ~isempty(newStart)
        root.setAttribute('timestampStart', newStart);
    end

    % Update timestampStartUTC custom attribute if present
    if ~isempty(templateStartUtc)
        newStartUtc = add_seconds_to_iso(templateStartUtc, segStartSec);
        if ~isempty(newStartUtc)
            ca = root.getElementsByTagNameNS(nsUri, 'customAttribute');
            for k = 0:ca.getLength-1
                node = ca.item(k);
                if node.hasAttribute('key') && strcmp(char(node.getAttribute('key')), 'timestampStartUTC')
                    node.setAttribute('value', newStartUtc);
                    break;
                end
            end
        end
    end

    % Remove all existing entries
    remove_all_by_tag(root, nsUri, 'signalEntry');
    remove_all_by_tag(root, nsUri, 'valuesEntry');

    % Re-add only entries for saved channels
    for i = 1:numel(savedChannels)
        chan = savedChannels{i};
        if ~isfield(dataStruct, chan) || ~isfield(dataStruct.(chan), 'originalFile')
            continue;
        end

        originalId = dataStruct.(chan).originalFile; % e.g., 'ecg.csv'
        segCsvName = sprintf('%s_%s_%s.csv', cfg.participantId, segName, chan);

        entryNode = find_entry_by_id(templateDoc, nsUri, originalId);
        if isempty(entryNode)
            continue;
        end

        imported = segDoc.importNode(entryNode, true);
        imported.setAttribute('id', segCsvName);
        root.appendChild(imported);
    end

    % Write unisens.xml into the segment folder
    outPath = fullfile(segmentDir, 'unisens.xml');
    xmlwrite(outPath, segDoc);
end

% ========================= Helpers =========================

function entryNode = find_entry_by_id(doc, nsUri, idStr)
    entryNode = [];

    sig = doc.getElementsByTagNameNS(nsUri, 'signalEntry');
    for k = 0:sig.getLength-1
        n = sig.item(k);
        if n.hasAttribute('id') && strcmp(char(n.getAttribute('id')), idStr)
            entryNode = n;
            return;
        end
    end

    val = doc.getElementsByTagNameNS(nsUri, 'valuesEntry');
    for k = 0:val.getLength-1
        n = val.item(k);
        if n.hasAttribute('id') && strcmp(char(n.getAttribute('id')), idStr)
            entryNode = n;
            return;
        end
    end
end

function remove_all_by_tag(root, nsUri, tagName)
    nodes = root.getElementsByTagNameNS(nsUri, tagName);

    % NodeList is live -> collect first
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

function outIso = add_seconds_to_iso(inIso, addSec)
    outIso = '';
    if isempty(inIso)
        return;
    end

    fmts = {
        'yyyy-MM-dd''T''HH:mm:ss.SSS'
        'yyyy-MM-dd''T''HH:mm:ss'
        'yyyy-MM-dd HH.mm.ss'
        'yyyy-MM-dd HH:mm:ss'
    };

    dt = [];
    for i = 1:numel(fmts)
        try
            dt = datetime(inIso, 'InputFormat', fmts{i}, 'TimeZone', '');
            break;
        catch
        end
    end

    if isempty(dt)
        try
            dt = datetime(inIso, 'TimeZone', '');
        catch
            return;
        end
    end

    dt2 = dt + seconds(addSec);
    outIso = char(datetime(dt2, 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));
end
