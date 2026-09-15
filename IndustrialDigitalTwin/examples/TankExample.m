%% TankExample
%
%  Demonstrates the ETank class capabilities:
%    1. Creating tanks with different geometry
%    2. Running a fill/hold/drain simulation
%    3. Injecting a leakage fault mid-simulation
%    4. Injecting a sensor failure
%    5. Plotting level, volume, alarm states
%    6. Displaying industrial tag tables
%
%  This example uses two tanks:
%    Tank101 - Large storage tank (D=5m, H=10m)
%    Tank102 - Small process tank (D=3m, H=6m)
%
%  Run from IndustrialDigitalTwin/ directory after running main.m
%  to set up paths, or run main.m first.

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================\n');
fprintf('       TANK EXAMPLE - DIGITAL TWIN\n');
fprintf('============================================\n\n');

% Add paths (in case running standalone)
thisDir = fileparts(mfilename('fullpath'));
projectRoot = fullfile(thisDir, '..');
addpath(fullfile(projectRoot, 'library', 'core'));
addpath(fullfile(projectRoot, 'library', 'process'));


%% 1. CREATE TANKS

fprintf('Creating tanks...\n');

Tank101 = ETank( ...
    "ID", "Tank101", ...
    "Diameter", 5, ...
    "Height", 10, ...
    "InitialLevel", 2, ...
    "Density", 998);

Tank102 = ETank( ...
    "ID", "Tank102", ...
    "Diameter", 3, ...
    "Height", 6, ...
    "InitialLevel", 0, ...
    "Density", 998);

fprintf('  Tank101: D=5m, H=10m, Initial Level=2m\n');
fprintf('  Tank102: D=3m, H=6m,  Initial Level=0m\n\n');


%% 2. SIMULATION SETUP

dt = 0.1;         % Timestep [s]
simTime = 300;     % Total simulation time [s]

time = 0:dt:simTime;
N = length(time);

% Pre-allocate data arrays
level101 = zeros(1, N);
level102 = zeros(1, N);
volume101 = zeros(1, N);
alarm_L_101 = zeros(1, N);
alarm_H_101 = zeros(1, N);
outputLevel101 = zeros(1, N);

% Fault injection schedule
leakageStart = 120;   % Inject leakage at t=120s
sensorFailStart = 200; % Inject sensor failure at t=200s
sensorFailEnd = 250;   % Clear sensor failure at t=250s


%% 3. RUN SIMULATION

fprintf('Running simulation (%.0f seconds)...\n', simTime);

for k = 1:N

    t = time(k);

    % --- Tank101: Fill / Hold / Drain profile ---
    if t < 60
        % Phase 1: FILL
        Tank101.setFlows(0.8, 0.1);
    elseif t < 120
        % Phase 2: HOLD (balanced)
        Tank101.setFlows(0.3, 0.3);
    else
        % Phase 3: DRAIN
        Tank101.setFlows(0.1, 0.5);
    end

    % --- Tank102: Constant slow fill ---
    Tank102.setFlows(0.15, 0.05);

    % --- Fault injection schedule ---
    if t >= leakageStart && ~Tank101.hasFault("Leakage")
        fprintf('  [t=%.0fs] Injecting LEAKAGE fault on Tank101\n', t);
        Tank101.injectFault("Leakage");
    end

    if t >= sensorFailStart && t < sensorFailEnd ...
            && ~Tank101.hasFault("SensorFailure")
        fprintf('  [t=%.0fs] Injecting SENSOR FAILURE on Tank101\n', t);
        Tank101.injectFault("SensorFailure");
    end

    if t >= sensorFailEnd && Tank101.hasFault("SensorFailure")
        fprintf('  [t=%.0fs] Clearing SENSOR FAILURE on Tank101\n', t);
        Tank101.clearFault("SensorFailure");
    end

    % --- Update both tanks ---
    Tank101.update(dt);
    Tank102.update(dt);

    % --- Record data ---
    level101(k) = Tank101.State.Level;
    level102(k) = Tank102.State.Level;
    volume101(k) = Tank101.State.Volume;
    alarm_L_101(k) = double(Tank101.Alarms.LEVEL_L);
    alarm_H_101(k) = double(Tank101.Alarms.LEVEL_H);
    outputLevel101(k) = Tank101.Outputs.Level;

end

fprintf('Simulation complete.\n\n');


%% 4. DISPLAY FINAL STATE

fprintf('--- FINAL STATE ---\n\n');

fprintf('Tank101:\n');
fprintf('  Physical Level: %.3f m\n', Tank101.State.Level);
fprintf('  Measured Level:  ');
if isnan(Tank101.Outputs.Level)
    fprintf('NaN (sensor failure)\n');
else
    fprintf('%.3f m\n', Tank101.Outputs.Level);
end
fprintf('  Volume:          %.3f m^3\n', Tank101.State.Volume);
fprintf('  Status:          %s\n', Tank101.Status);
fprintf('  Leakage Fault:   %s\n', string(Tank101.Faults.Leakage));
fprintf('  Sensor Fault:    %s\n\n', string(Tank101.Faults.SensorFailure));

fprintf('Tank102:\n');
fprintf('  Physical Level: %.3f m\n', Tank102.State.Level);
fprintf('  Volume:          %.3f m^3\n', Tank102.State.Volume);
fprintf('  Status:          %s\n\n', Tank102.Status);


%% 5. DISPLAY INDUSTRIAL TAGS

fprintf('--- INDUSTRIAL TAGS ---\n\n');
fprintf('Tank101 Tags:\n');
disp(Tank101.getTags());

fprintf('Tank102 Tags:\n');
disp(Tank102.getTags());


%% 6. PLOTS

% --- Figure 1: Tank Levels ---
figure('Name', 'Tank Levels', 'Position', [100 500 900 400]);

subplot(2,1,1);
plot(time, level101, 'b-', 'LineWidth', 1.5);
hold on;
yline(Tank101.Parameters.Limits.LL, 'r--', 'LL', 'LineWidth', 0.8);
yline(Tank101.Parameters.Limits.L, 'r:', 'L', 'LineWidth', 0.8);
yline(Tank101.Parameters.Limits.H, 'm:', 'H', 'LineWidth', 0.8);
yline(Tank101.Parameters.Limits.HH, 'm--', 'HH', 'LineWidth', 0.8);
xline(leakageStart, 'k--', 'Leakage Start', 'LineWidth', 0.8);
xline(sensorFailStart, 'g--', 'Sensor Fail', 'LineWidth', 0.8);
xline(sensorFailEnd, 'g-.', 'Sensor OK', 'LineWidth', 0.8);
ylabel('Level [m]');
title('Tank101 - Level with Alarm Limits');
grid on;
legend('Level', 'Location', 'best');
xlim([0 simTime]);
ylim([0 Tank101.Parameters.Geometry.Height]);

subplot(2,1,2);
plot(time, level102, 'r-', 'LineWidth', 1.5);
hold on;
yline(Tank102.Parameters.Limits.H, 'm:', 'H', 'LineWidth', 0.8);
yline(Tank102.Parameters.Limits.HH, 'm--', 'HH', 'LineWidth', 0.8);
xlabel('Time [s]');
ylabel('Level [m]');
title('Tank102 - Level');
grid on;
xlim([0 simTime]);
ylim([0 Tank102.Parameters.Geometry.Height]);


% --- Figure 2: Physical vs Measured Level ---
figure('Name', 'Physical vs Measured', 'Position', [100 50 900 350]);

plot(time, level101, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Physical Level');
hold on;
plot(time, outputLevel101, 'r.', 'MarkerSize', 2, 'DisplayName', 'Measured Level');
xline(sensorFailStart, 'g--', 'Sensor Fail', 'LineWidth', 0.8);
xline(sensorFailEnd, 'g-.', 'Sensor OK', 'LineWidth', 0.8);
xlabel('Time [s]');
ylabel('Level [m]');
title('Tank101 - Physical vs Measured Level (Sensor Failure Effect)');
legend('Location', 'best');
grid on;
xlim([0 simTime]);


% --- Figure 3: Alarm States ---
figure('Name', 'Alarm States', 'Position', [550 500 500 300]);

area(time, alarm_H_101 * 2, 'FaceColor', [1 0.8 0.8], ...
    'EdgeColor', 'none', 'DisplayName', 'HIGH Alarm');
hold on;
area(time, alarm_L_101, 'FaceColor', [0.8 0.8 1], ...
    'EdgeColor', 'none', 'DisplayName', 'LOW Alarm');
xlabel('Time [s]');
ylabel('Alarm Active');
title('Tank101 - Alarm History');
legend('Location', 'best');
grid on;
xlim([0 simTime]);
ylim([0 2.5]);


fprintf('\n============================================\n');
fprintf('       EXAMPLE COMPLETE\n');
fprintf('============================================\n\n');
