function res = fit_one_lmm(T, formula, cfg)
%FIT_ONE_LMM Fit a single LMM formula and report convergence, singularity,
%   warnings, and fit statistics. Never throws -- always returns a
%   populated struct so the caller can export a full results row even when
%   fitting fails.
%
%   Both configured random-effects structures (random intercept +
%   speed slope, and random intercept only) are fit as fully independent
%   models by calling this function once per structure; each gets its own
%   complete results row rather than one being used only as a fallback for
%   AIC/BIC comparison.
%
%   A fit is treated as "singular" using the same criterion lme4::isSingular
%   uses in R: any random-effect standard deviation is ~0, or any
%   random-effect correlation is ~+/-1 (a boundary estimate).

res = struct('model', [], 'converged', false, 'singular_fit', NaN, ...
             'warning_message', '', 'AIC', NaN, 'BIC', NaN);

lastwarn('');
try
    m = fitlme(T, formula, 'FitMethod', 'REML');
catch ME
    res.warning_message = ME.message;
    return;
end

[warn_msg, ~] = lastwarn();
res.model = m;
res.singular_fit = model_is_singular(m, cfg);
has_conv_warning = ~isempty(warn_msg) && contains_convergence_issue(warn_msg);
res.converged = ~has_conv_warning;
res.warning_message = strtrim(warn_msg);
res.AIC = m.ModelCriterion.AIC;
res.BIC = m.ModelCriterion.BIC;

end

function tf = contains_convergence_issue(msg)
    keywords = {'converge', 'Hessian', 'iteration limit', 'not positive definite', ...
                'failed to converge', 'gradient'};
    tf = any(cellfun(@(k) ~isempty(regexpi(msg, k, 'once')), keywords));
end

function tf = model_is_singular(m, cfg)
%MODEL_IS_SINGULAR Boundary/singular-fit heuristic: a random-effect standard
%   deviation near zero, or a random-effects correlation near +/-1.
%   Reads the actual covariance matrix straight from covarianceParameters'
%   FIRST output (PSI) -- one matrix per grouping variable, containing
%   ONLY the random-effects covariance (never the residual/error term) --
%   rather than parsing the STATS (3rd output) table.
    tf = false;
    try
        PSI = covarianceParameters(m);
    catch
        return;
    end
    for g = 1:numel(PSI)
        try
            Psi_g = PSI{g};
            sd_g = sqrt(diag(Psi_g)); % random-effect standard deviations
            if any(sd_g < sqrt(cfg.singular_var_tol))
                tf = true;
            end
            k = size(Psi_g, 1);
            if k > 1
                % Correlation matrix from the covariance matrix itself
                % (corr(i,j) = cov(i,j) / (sd_i*sd_j)); the diagonal is
                % excluded since a variable's correlation with itself (1)
                % is not a boundary/singular-fit indicator.
                corr_g = Psi_g ./ (sd_g * sd_g');
                corr_g(1:k+1:end) = 0;
                if any(abs(corr_g(:)) > cfg.singular_corr_tol)
                    tf = true;
                end
            end
        catch
            continue;
        end
    end
end
