function level = get_file_requirement_level(cfg, sensor, file_name)

if strcmpi(file_name, 'unisens.xml')
    level = 'xml';
    return;
end

if ismember(file_name, cfg.files.log_only)
    level = 'log_only';
    return;
end

if strcmpi(sensor, 'Heart')
    if ismember(file_name, cfg.files.hard_required.Heart)
        level = 'hard';
        return;
    elseif ismember(file_name, cfg.files.soft_required.Heart)
        level = 'soft';
        return;
    end
elseif strcmpi(sensor, 'Hip')
    if ismember(file_name, cfg.files.hard_required.Hip)
        level = 'hard';
        return;
    elseif ismember(file_name, cfg.files.soft_required.Hip)
        level = 'soft';
        return;
    end
end

level = 'unknown';
end