function T = local_read_table_preserve_names(filePath)
%LOCAL_READ_TABLE_PRESERVE_NAMES Read table while preserving source variable names when possible.

if ~exist(filePath, 'file')
    error('File not found: %s', filePath);
end

try
    opts = detectImportOptions(filePath, 'VariableNamingRule', 'preserve');
    T = readtable(filePath, opts);
catch
    try
        T = readtable(filePath, 'VariableNamingRule', 'preserve');
    catch
        T = readtable(filePath);
    end
end
end
