function out = compute_lmm_contrast(m, c)
%COMPUTE_LMM_CONTRAST Estimate, SE, test statistic, denominator degrees of
%   freedom, two-sided p-value, and 95% CI for an arbitrary linear
%   combination c'*beta of a fitted LinearMixedModel's fixed-effects
%   coefficients.
%
%   SE is computed as sqrt(c' * CoefficientCovariance * c) -- the standard
%   linear-combination variance formula, which correctly includes the
%   covariance between any coefficients touched by c (never a sum of their
%   individual SEs. The test statistic, its denominator df, and the two-sided
%   p-value come from fitlme's own coefTest linear-hypothesis machinery
%   (H*beta = 0 for H = c'), using whichever DF method
%   (Satterthwaite/residual) the model was fit with.
%
%   This is the same method compute_hrv_simple_slope_4kmh.m uses for the
%   primary-model 4 km/h simple slope; this generic version is reused by
%   compute_followup_rest_condition_analysis.m for the follow-up model's
%   other condition-by-speed simple slopes and resting-condition pairwise
%   contrasts.
%
%   Never errors: returns an all-NaN struct if the covariance is
%   degenerate for this contrast or coefTest fails.

out = struct('estimate', NaN, 'se', NaN, 'tStat', NaN, 'df', NaN, ...
              'pValue', NaN, 'ci_lower', NaN, 'ci_upper', NaN);

try
    coefT = m.Coefficients;
    if ~istable(coefT)
        coefT = dataset2table(coefT);
    end
    beta = coefT.Estimate;
    estimate = c' * beta;

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

    out.estimate = estimate;
    out.se = se;
    out.tStat = tStat;
    out.df = df;
    out.pValue = pValue;
    out.ci_lower = ci_lower;
    out.ci_upper = ci_upper;
catch
    % leave out as all-NaN -- never propagate an error from here
end

end
