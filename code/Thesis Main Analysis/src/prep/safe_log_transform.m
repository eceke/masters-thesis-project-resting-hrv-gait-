function [logx, n_invalid, invalid_mask] = safe_log_transform(x)
%SAFE_LOG_TRANSFORM Natural-log transform that treats non-positive values as
%   invalid (NaN) rather than producing -Inf/complex results. HRV metrics
%   such as RMSSD and HF power must be strictly positive for ln() to be
%   defined; any x <= 0 is flagged as missing for QC reporting.

invalid_mask = ~isnan(x) & (x <= 0);
logx = x;
logx(invalid_mask) = NaN;
logx = log(logx);
n_invalid = sum(invalid_mask);

end
