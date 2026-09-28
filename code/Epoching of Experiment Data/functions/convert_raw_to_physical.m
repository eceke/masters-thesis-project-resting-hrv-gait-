function phys = convert_raw_to_physical(raw, baseline, lsbValue)
% Convert raw numeric samples to physical units using
% Unisens XML parameters.
% Inputs:
%   raw      : numeric matrix (NxC) read from CSV (often int16 saved as double)
%   baseline : numeric scalar (e.g., 2048). If NaN/empty -> treated as "no baseline"
%   lsbValue : numeric scalar (e.g., 0.00268...). If empty/NaN -> defaults to 1
% Output:
%   phys     : double matrix (NxC) in physical units

    arguments
        raw (:,:) double
        baseline (1,1) double = NaN
        lsbValue (1,1) double = NaN
    end

    if isnan(lsbValue) || isempty(lsbValue) || lsbValue == 0
        lsbValue = 1.0;
    end

    if isnan(baseline) || isempty(baseline)
        phys = raw .* lsbValue;
    else
        phys = (raw - baseline) .* lsbValue;
    end
end
