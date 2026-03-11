% GeoVault: The "Ultimate" Semantic Dictionary Suite
clc; clear;

% --- Fundamental Parameters ---
A_cell = 9e-6; % 3m x 3m cell in km^2
W_buffer = 0.1; % 100m orientable zone

% --- 1. Linear Dictionaries ---
L_coast = 1162306; 
A_coastline = L_coast * W_buffer; 

L_rivers = 3500000; 
A_rivers = L_rivers * 2 * W_buffer; 

% --- 2. Point Dictionaries (Area = Count * pi * r^2) ---
% UNESCO Sites (~1,200 sites)
N_unesco = 1200;
A_unesco = N_unesco * pi * (W_buffer^2);

% Prominent Peaks (~100,000 peaks)
N_peaks = 100000;
A_peaks = N_peaks * pi * (W_buffer^2);

% --- 3. Area Dictionaries ---
A_global    = 510065600; 
A_land      = 148940000; 
A_habitable = 25000000; 

% --- 4. The "Omnibus" Semantic Dictionary ---
% Summing all HPZs (Habitable + Coasts + Rivers + Points)
A_omnibus_HPZ = A_habitable + A_coastline + A_rivers + A_unesco + A_peaks;

% --- Data Organization ---
names = {'Global Nominal', 'Habitable HPZ', 'Global Coastline', ...
         'Global Rivers', 'UNESCO Sites', 'Major Peaks', ...
         'OMNIBUS HPZ (Total)', 'Urban (London)'};
areas = [A_global, A_habitable, A_coastline, A_rivers, ...
         A_unesco, A_peaks, A_omnibus_HPZ, 1572];

% --- Entropy Calculations ---
H_values = log2(areas ./ A_cell);
H_collapse = H_values(1) - H_values;

% --- Display ---
fprintf('%-22s | %-12s | %-12s | %-10s\n', 'Dictionary', 'Area (km2)', 'Entropy (H)', 'Collapse');
fprintf('%s\n', repmat('-', 1, 65));

for i = 1:length(areas)
    fprintf('%-22s | %-12.2e | %-12.2f | %-10.2f\n', ...
            names{i}, areas(i), H_values(i), H_collapse(i));
end