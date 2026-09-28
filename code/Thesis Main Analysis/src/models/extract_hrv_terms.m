function terms = extract_hrv_terms(m, hrv_col, speed_col, rest_col)
%EXTRACT_HRV_TERMS Pull the HRV main-effect row, the HRV x speed
%   interaction row, and (optionally) the HRV x rest_condition interaction
%   row(s) out of a fitted LinearMixedModel's coefficient table.
%
%   Two-way interaction terms are matched by splitting each coefficient
%   name on ':' and checking, order-independently, that one side equals
%   the continuous HRV column exactly and the other side starts with
%   "<factor>_" (its dummy-level suffix). fitlme's Wilkinson-notation term
%   ordering is not guaranteed to preserve the left-to-right order written
%   in the formula string (e.g. "HRV_z * speed_factor" can surface as the
%   coefficient "speed_factor_4:z_RMSSD_ecg" rather than
%   "z_RMSSD_ecg:speed_factor_4") -- anchoring a regex to one fixed order
%   silently returned zero rows (and therefore NaN) for every interaction
%   whenever fitlme happened to emit the other order, while leaving the
%   HRV main effect (no colon, order-independent) unaffected.

coefT = m.Coefficients;
if ~istable(coefT)
    coefT = dataset2table(coefT);
end

main_rows = coefT(strcmp(coefT.Name, hrv_col), :);
terms.main = summarize_coef_rows(main_rows);

int_speed_rows = find_interaction_rows(coefT, hrv_col, [speed_col '_']);
terms.hrv_x_speed = summarize_coef_rows(int_speed_rows);

terms.hrv_x_rest = table();
if nargin >= 4 && ~isempty(rest_col)
    terms.hrv_x_rest = find_interaction_rows(coefT, hrv_col, [rest_col '_']);
end

end

function rows = find_interaction_rows(coefT, var_exact, var_prefix)
%FIND_INTERACTION_ROWS Match a two-way interaction coefficient regardless
%   of which side of the ':' fitlme placed each term on.
    names = coefT.Name;
    mask = false(numel(names), 1);
    for i = 1:numel(names)
        parts = strsplit(names{i}, ':');
        if numel(parts) ~= 2
            continue;
        end
        has_exact  = any(strcmp(parts, var_exact));
        has_prefix = any(strncmp(parts, var_prefix, numel(var_prefix)));
        if has_exact && has_prefix
            mask(i) = true;
        end
    end
    rows = coefT(mask, :);
end
