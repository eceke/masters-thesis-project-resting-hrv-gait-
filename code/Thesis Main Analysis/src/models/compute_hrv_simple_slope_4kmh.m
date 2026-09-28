function slope = compute_hrv_simple_slope_4kmh(m, hrv_col, speed_col)
%COMPUTE_HRV_SIMPLE_SLOPE_4KMH HRV simple slope at the non-reference
%   (4 km/h) speed level, from a fitted LinearMixedModel whose fixed
%   effects include HRV_z * speed_factor (speed_factor reference = 1 km/h):
%
%       beta_4kmh = beta_HRV + beta_HRVxSpeed
%
%   Var(beta_4kmh) is NOT the sum of the two coefficients' own variances --
%   it must include their covariance:
%
%       Var(beta_4kmh) = Var(beta_HRV) + Var(beta_HRVxSpeed)
%                        + 2*Cov(beta_HRV, beta_HRVxSpeed)
%
%   This is computed as c' * CoefficientCovariance * c for a contrast
%   vector c (1 at the HRV main-effect position, 1 at the HRV x speed
%   interaction position, 0 elsewhere) -- the standard linear-combination
%   variance formula, using the model's own fixed-effects coefficient
%   covariance matrix. 
%
%   Never errors: if either coefficient can't be found, or the contrast
%   test fails for any reason, all fields are returned as NaN so the
%   caller (run_primary_models.m / run_followup_models.m) can continue
%   the pipeline unaffected.

slope = struct('estimate', NaN, 'se', NaN, 'tStat', NaN, 'df', NaN, ...
                'pValue', NaN, 'ci_lower', NaN, 'ci_upper', NaN);

try
    terms = extract_hrv_terms(m, hrv_col, speed_col);
    if isnan(terms.main.estimate) || isnan(terms.hrv_x_speed.estimate)
        return; % HRV main effect and/or HRV x speed term not found in this model
    end

    coefT = m.Coefficients;
    if ~istable(coefT)
        coefT = dataset2table(coefT);
    end

    idx_main = find(strcmp(coefT.Name, terms.main.name));
    idx_int  = find(strcmp(coefT.Name, terms.hrv_x_speed.name));
    if numel(idx_main) ~= 1 || numel(idx_int) ~= 1
        return;
    end

    p = height(coefT);
    c = zeros(p, 1);
    c(idx_main) = 1;
    c(idx_int) = 1;

    beta = coefT.Estimate;
    estimate = c' * beta; % = beta_HRV + beta_HRVxSpeed, exactly the reported estimate_HRV + estimate_HRVxSpeed

    Sigma = m.CoefficientCovariance;
    var_est = c' * Sigma * c;
    if ~(var_est > 0)
        return;
    end
    se = sqrt(var_est);

    [pValue, F, ~, df2] = coefTest(m, c');
    tStat = sign(estimate) * sqrt(F);
    df = df2;

    tcrit = tinv(1 - 0.05 / 2, df);
    ci_lower = estimate - tcrit * se;
    ci_upper = estimate + tcrit * se;

    slope.estimate = estimate;
    slope.se = se;
    slope.tStat = tStat;
    slope.df = df;
    slope.pValue = pValue;
    slope.ci_lower = ci_lower;
    slope.ci_upper = ci_upper;
catch
    % leave slope as all-NaN -- never propagate an error from here
end

end
