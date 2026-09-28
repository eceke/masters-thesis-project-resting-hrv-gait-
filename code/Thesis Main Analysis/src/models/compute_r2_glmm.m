function [R2_marginal, R2_conditional] = compute_r2_glmm(m)
%COMPUTE_R2_GLMM Marginal/conditional R^2 for a fitted LinearMixedModel,
%   following the Nakagawa & Schielzeth (2013) variance-partitioning logic:
%     R2_marginal    = variance explained by fixed effects alone
%     R2_conditional = variance explained by fixed + random effects
%
%   V_fixed    = Var(X*beta), computed via fitted(m,'Conditional',false),
%                which is exactly X*beta for a linear mixed model (this
%                part was already correct and is unchanged).
%   V_random   = mean(diag(Z*G*Z')), computed WITHOUT forming the full
%                (potentially huge) sparse Z*G*Z' matrix: G is
%                block-diagonal with the SAME estimated covariance matrix
%                Psi repeated once per group (the standard LMM assumption
%                -- Psi does not vary by group), so diag(Z*G*Z')_i reduces
%                to z_i*Psi*z_i' using only observation i's own k-length
%                random-effects design row z_i (e.g. [1, speed_dummy_i]
%                for the random-intercept-plus-speed-slope structure), not
%                the full q-column sparse row. Psi itself is
%                covarianceParameters(m)'s own first output (the model's
%                estimated random-effects covariance matrix -- never
%                reconstructed from a standard deviation or correlation
%                value by hand); z_i's non-intercept entries are read
%                verbatim from the model's own fixed-effects design matrix
%                column of the matching name (fitlme uses identical dummy
%                coding for a factor whether it is a fixed or a random
%                term in this pipeline's formulas, which always include
%                speed_factor as a fixed effect alongside the random
%                slope), so this matches MATLAB's own speed_factor coding
%                exactly rather than re-deriving it.
%   
%                V_residual = m.MSE (the fitted residual variance estimate).
%
%   Handles both the random-intercept-only structure (k=1: a single
%   variance term, no correlation) and the random-intercept-plus-slope
%   structure (k=2) with the same code path -- neither the term count nor
%   which terms exist is hard-coded.
%
%   Never errors and never returns an approximate/guessed value: if any
%   step of the covariance-structure extraction is not reliable, both
%   outputs are NaN so the caller (run_primary_models.m /
%   run_followup_models.m / run_log_sensitivity_models.m) can continue the
%   pipeline unaffected. Read-only: never touches model coefficients,
%   p-values, FDR results, or candidate selection.

R2_marginal = NaN;
R2_conditional = NaN;

try
    yhat_fixed = fitted(m, 'Conditional', false); % = X*beta
    var_fixed = var(yhat_fixed);
    n = numel(yhat_fixed);

    [PSI, ~, covStats] = covarianceParameters(m);

    coefT = m.Coefficients;
    if ~istable(coefT)
        coefT = dataset2table(coefT);
    end
    coefNames = coefT.Name;
    Xfixed = designMatrix(m, 'Fixed');

    var_random_total = 0;
    for g = 1:numel(PSI)
        Psi_g = PSI{g};

        statsTbl = covStats{g};
        if ~istable(statsTbl)
            statsTbl = dataset2table(statsTbl);
        end
        isStd = strcmpi(statsTbl.Type, 'std');
        term_names = statsTbl.Name1(isStd);
        k = numel(term_names);

        if k == 0 || ~isequal(size(Psi_g), [k k])
            error('compute_r2_glmm:covarianceShapeMismatch', ...
                'covarianceParameters std-row count does not match the Psi matrix dimensions.');
        end

        % Self-check (see docstring): confirms the assumed term order
        % actually reproduces Psi_g's own diagonal before it is used.
        expected_var = statsTbl.Estimate(isStd) .^ 2;
        actual_var = diag(Psi_g);
        if any(abs(expected_var(:) - actual_var(:)) > 1e-6 * max(1, max(abs(expected_var(:)))))
            error('compute_r2_glmm:covarianceOrderMismatch', ...
                'covarianceParameters STATS row order does not match the Psi diagonal -- cannot reliably map random-effect terms.');
        end

        Zlocal = nan(n, k);
        for j = 1:k
            tn = term_names{j};
            if strcmpi(tn, '(Intercept)')
                Zlocal(:, j) = 1;
            else
                idx = find(strcmp(coefNames, tn), 1);
                if isempty(idx)
                    error('compute_r2_glmm:randomTermNotInFixedDesign', ...
                        'Random-effect term "%s" has no matching fixed-effects design column.', tn);
                end
                Zlocal(:, j) = Xfixed(:, idx);
            end
        end

        var_random_total = var_random_total + mean(sum((Zlocal * Psi_g) .* Zlocal, 2));
    end

    var_residual = m.MSE;

    denom = var_fixed + var_random_total + var_residual;
    if ~(denom > 0) || ~isfinite(denom)
        R2_marginal = NaN;
        R2_conditional = NaN;
        return;
    end

    R2_marginal = var_fixed / denom;
    R2_conditional = (var_fixed + var_random_total) / denom;
catch
    R2_marginal = NaN;
    R2_conditional = NaN;
end

end
