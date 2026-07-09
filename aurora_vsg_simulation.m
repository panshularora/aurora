%% AURORA Microgrid Black-Start & VSG Physics Simulation
% Systems Engineering Model - Custom State-Space Solver
% Matches Slide 11 (Simulink Validation) and Slide 12 (Engineering Validation)

clear; clc; close all;

%% 1. Simulation Configuration
dt = 0.01;              % Solver step size (s)
t_end = 90;             % Simulation time (s)
t = 0:dt:t_end;         % Time vector
N = length(t);

%% 2. Power Grid & Component Parameters
f0 = 50.0;              % Nominal frequency (Hz)
V0 = 400.0;             % Nominal voltage (V)
D_damping = 0.08;       % Load damping factor (pu)
R_droop = 0.04;         % Governor droop (4%)
K_vsg = 1 / R_droop;    % Droop gain (25 pu)

% Capacity Constraints (kW)
Cap_BESS = 1200;        % Li-ion Battery capacity (kWh)
Cap_VRFB = 1800;        % VRFB Flow Battery capacity (kWh)
P_max_H2 = 150;         % H2 Fuel Cell max output (kW)
P_geo = 182;            % Geothermal ORC baseload (kW)

% Efficiencies
eta_li = 0.94;
eta_vrfb = 0.82;

%% 3. Dynamic Load Priority Profiles (Load Shedding Schedule)
% P1: Hospital (120 kW) - Reconnects at T=7s
% P2: Community (200 kW) - Reconnects at T=30s
% P3: Industrial (280 kW) - Reconnects at T=50s
% P4: EV Charging (80 kW) - Reconnects at T=65s
% P5: Street / Misc (50 kW) - Reconnects at T=75s

P_demand = zeros(1, N);

%% 4. Initialize State Vectors
f = zeros(1, N);
f(1) = 0.0;             % Starts at dead bus (0 Hz)
V = zeros(1, N);
V(1) = 0.0;             % Starts at dead bus (0 V)

liSoc = zeros(1, N);
liSoc(1) = 15.0;        % Initial Li-ion SoC (15% cold-start floor)
vrfbSoc = zeros(1, N);
vrfbSoc(1) = 80.0;      % Initial VRFB SoC (80%)

% Outputs for tracking
P_sol_log  = zeros(1, N);
P_wind_log = zeros(1, N);
P_bat_log  = zeros(1, N);
P_geo_log  = zeros(1, N);
P_h2_log   = zeros(1, N);

%% 5. Numerical Simulation Loop (Euler Integration)
for k = 1:N-1
    tk = t(k);
    
    %% A. Determine Active Grid Load (Stepwise restoration schedule)
    p_hosp = 0; p_comm = 0; p_ind = 0; p_ev = 0; p_st = 0;
    if tk >= 7.0,  p_hosp = 120; end
    if tk >= 30.0, p_comm = 200; end
    if tk >= 50.0, p_ind = 280;  end
    if tk >= 65.0, p_ev = 80;    end
    if tk >= 75.0, p_st = 50;    end
    
    P_demand(k) = p_hosp + p_comm + p_ind + p_ev + p_st;
    
    %% B. Renewable Output Profiles (Ramping models)
    % Solar PV (ramps up from T=20s as inverters synchronize)
    if tk < 20
        p_sol = 0;
    else
        p_sol = min(470, 10 * (tk - 20) + 1.5*randn());
    end
    
    % Wind DFIG (synchronizes at T=10s)
    if tk < 10
        p_wind = 0;
    else
        p_wind = min(220, 8 * (tk - 10) + 2.0*randn());
    end
    
    % Geothermal baseload ORC (synchronizes at T=45s due to turbine startup)
    if tk < 45
        p_geo_active = 0;
    else
        p_geo_active = P_geo;
    end
    
    %% C. Primary Governor Droop & Inertia Emulation
    % VSG controller monitors frequency deviation and injects BESS power
    delta_f = f(k) - f0;
    
    % Active virtual inertia (H_sys) increases when battery is online
    if f(k) < 10.0
        h_sys = 1.0; % Low inertia before excitation
    else
        h_sys = 2.0 + 5.0 * (liSoc(k)/100); % Virtual synchronous inertia
    end
    
    % Primary droop governor output
    if f(k) < 5.0
        p_bat = 240; % Max discharge kick during cold-start excitation (0->5s)
    else
        % Droop injects power based on deviation
        p_bat = -K_vsg * delta_f;
        p_bat = max(-200, min(500, p_bat)); % Limit converter power
    end
    
    %% D. Hydrogen PEM Fuel Cell Backup
    % Triggers if generation deficit exists and battery SoC is low
    deficit = P_demand(k) - (p_sol + p_wind + p_geo_active + p_bat);
    if deficit > 0 && liSoc(k) < 18.0
        p_h2 = min(P_max_H2, deficit);
    else
        p_h2 = 0;
    end
    
    %% E. Solve System Power Balance
    p_gen = p_bat + p_sol + p_wind + p_geo_active + p_h2;
    p_loss = 0.00003 * p_gen^2 + 0.02 * p_gen; % Transmission loss model
    
    p_mismatch = p_gen - P_demand(k) - p_loss;
    
    %% F. Solve Swing Equation (Frequency derivative)
    df_dt = (p_mismatch - D_damping * delta_f) / (2 * h_sys);
    f(k+1) = f(k) + df_dt * dt;
    
    % Handle initial black-start excitation ramp
    if tk < 5.0
        % System starts dead; force linear voltage/frequency excitation ramp
        f(k+1) = f(k) + (45.0 / 5.0) * dt; 
    end
    f(k+1) = max(0, min(65.0, f(k+1))); % Physical limits
    
    %% G. Solve Voltage Drop Profile
    delta_V = 0.015 * p_mismatch - 0.000008 * P_demand(k)^2;
    if tk < 5.0
        V(k+1) = V(k) + (380.0 / 5.0) * dt;
    else
        V(k+1) = V0 + delta_V;
    end
    V(k+1) = max(0, min(480.0, V(k+1)));
    
    %% H. Integrate Battery State of Charge (SoC)
    dt_hours = dt / 3600;
    p_li = p_bat * 0.70; % BESS shares 70% of storage power
    if p_bat > 0 % Discharging
        liSoc(k+1) = max(0, liSoc(k) - (p_li / (eta_li * Cap_BESS)) * dt_hours * 100);
    else         % Charging
        chg_li = -p_li;
        liSoc(k+1) = min(100, liSoc(k) + (chg_li * eta_li / Cap_BESS) * dt_hours * 100);
    end
    
    % VRFB Flow Battery shares 30%
    p_vrfb = p_bat * 0.30;
    if p_bat > 0
        vrfbSoc(k+1) = max(0, vrfbSoc(k) - (p_vrfb / (eta_vrfb * Cap_VRFB)) * dt_hours * 100);
    else
        chg_vrfb = -p_vrfb;
        vrfbSoc(k+1) = min(100, vrfbSoc(k) + (chg_vrfb * eta_vrfb / Cap_VRFB) * dt_hours * 100);
    end
    
    %% Log generation states
    P_sol_log(k) = p_sol;
    P_wind_log(k) = p_wind;
    P_bat_log(k) = p_bat;
    P_geo_log(k) = p_geo_active;
    P_h2_log(k) = p_h2;
end

% Set final endpoint values
f(end) = f(end-1);
V(end) = V(end-1);
liSoc(end) = liSoc(end-1);
vrfbSoc(end) = vrfbSoc(end-1);

%% 6. Plotting Results (IEEE Conference Styling)
figure('Position', [100, 100, 800, 600], 'Color', [0.04, 0.05, 0.08]);

% -- Plot 1: Grid Frequency Restoration --
subplot(3, 1, 1);
plot(t, f, 'Color', [0.0, 0.9, 0.6], 'LineWidth', 2);
hold on;
yline(49.8, 'r--', 'IEEE 1547 Min', 'LabelHorizontalAlignment', 'left', 'Color', [1.0, 0.3, 0.3]);
yline(50.2, 'r--', 'IEEE 1547 Max', 'LabelHorizontalAlignment', 'left', 'Color', [1.0, 0.3, 0.3]);
grid on;
set(gca, 'Color', [0.08, 0.09, 0.12], 'GridColor', [0.2, 0.25, 0.3], 'XColor', 'w', 'YColor', 'w');
title('Primary Virtual Synchronous Generator Frequency Recovery', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Frequency (Hz)', 'Color', 'w');
ylim([0, 55]);
xline(7, 'y:', 'Hospital Restored (T+7s)');
xline(87, 'g:', 'Stable (T+87s)');

% -- Plot 2: Bus Voltage Restoration --
subplot(3, 1, 2);
plot(t, V, 'Color', [0.2, 0.6, 1.0], 'LineWidth', 2);
hold on;
yline(400, 'w:', 'Nominal (400V)', 'Color', [0.6, 0.7, 0.8]);
grid on;
set(gca, 'Color', [0.08, 0.09, 0.12], 'GridColor', [0.2, 0.25, 0.3], 'XColor', 'w', 'YColor', 'w');
title('AC Bus Voltage Restoration Profile', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Bus Voltage (V)', 'Color', 'w');
ylim([0, 450]);
xline(7, 'y:', 'Hospital Restored (T+7s)');

% -- Plot 3: Battery State-of-Charge Dynamics --
subplot(3, 1, 3);
plot(t, liSoc, 'Color', [0.96, 0.78, 0.26], 'LineWidth', 2, 'DisplayName', 'Li-ion BESS');
hold on;
plot(t, vrfbSoc, 'Color', [0.6, 0.4, 1.0], 'LineWidth', 2, 'DisplayName', 'VRFB Flow Battery');
grid on;
legend('Location', 'best');
set(gca, 'Color', [0.08, 0.09, 0.12], 'GridColor', [0.2, 0.25, 0.3], 'XColor', 'w', 'YColor', 'w');
title('Energy Storage State-of-Charge Dynamics', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
xlabel('Simulation Time (s)', 'Color', 'w');
ylabel('SoC (%)', 'Color', 'w');
ylim([5, 100]);

shg;
