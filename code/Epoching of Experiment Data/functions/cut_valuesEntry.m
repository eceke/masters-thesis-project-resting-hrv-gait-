function cutData = cut_valuesEntry(data, startTime, endTime, refFs)
%CUT_SPECIAL_INDEXED_CHANNEL
% Cuts nn_live / bpmbxb_live using first-column index values.

    if isempty(data) || size(data,2) < 1
        cutData = [];
        return;
    end

    startIdx = floor(startTime * refFs) + 1;
    endIdx   = ceil(endTime * refFs);

    firstCol = data(:,1);

    mask = firstCol >= startIdx & firstCol <= endIdx;
    cutData = data(mask, :);
end