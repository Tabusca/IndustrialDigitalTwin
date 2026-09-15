%% PumpTankExample
%
%  Demonstrates an integrated system:
%    Tank1 -> Valve1 -> Pump1 -> CV1 -> Tank2
%
%  Features demonstrated:
%    - Multi-component integration
%    - System state logging
%    - Control valve modulation
%    - Fault injection across multiple components

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================\n');
fprintf('       PUMP-TANK INTEGRATION EXAMPLE\n');
fprintf('============================================\n\n');

% Add paths
thisDir = fileparts(mfilename('fullpath'));
projectRoot = fullfile(thisDir, '..');
addpath(fullfile(projectRoot, 'library', 'core'));
addpath(fullfile(projectRoot, 'library', 'process'));

%% 1. CREATE COMPONENTS

fprintf('Creating components...\n');

% Tanks
Tank1 = ETank("ID", "Tank1", "Diameter", 5, "Height", 10, "InitialLevel", 8);
Tank2 = ETank("ID", "Tank2", "Diameter", 5, "Height", 10, "InitialLevel", 1);

% Valve & Pump
Valve1 = EValve("ID", "V101", "StrokeTime", 2);
Pump1 = EPump("ID", "P101", "RatedFlow", 0.5, "RatedHead", 20, "RatedSpeed", 3000, "SpeedTimeConstant", 2.0);

% Control Valve
CV1 = EControlValve("ID", "CV101", "Characteristic", "linear", "TimeConstant", 1.0);

fprintf('System: Tank1 -> V101 -> P101 -> CV101 -> Tank2\n\n');

%% 2. SIMULATION SETUP

dt = 0.1;
simTime = 120;
time = 0:dt:simTime;
N = length(time);

% Data arrays
level1 = zeros(1, N);
level2 = zeros(1, N);
pumpSpeed = zeros(1, N);
cvPos = zeros(1, N);
flow = zeros(1, N);

%% 3. RUN SIMULATION

fprintf('Running simulation (%.0f seconds)...\n', simTime);

for k = 1:N
    t = time(k);
    
    % --- Automation Sequence ---
    if t == 5
        fprintf('  [t=%.1fs] Opening V101\n', t);
        Valve1.open();
    end
    if t == 10
        fprintf('  [t=%.1fs] Starting P101\n', t);
        Pump1.start();
    end
    if t == 15
        fprintf('  [t=%.1fs] Modulating CV101 to 75%%\n', t);
        CV1.setCommand(75);
    end
    
    % --- Fault Injection ---
    if t == 60
        fprintf('  [t=%.1fs] INJECTING: Pump Bearing Fault\n', t);
        Pump1.injectFault("BearingFault");
    end
    if t == 80
        fprintf('  [t=%.1fs] INJECTING: Valve Stuck (CV101)\n', t);
        CV1.injectFault("Stuck");
        fprintf('  [t=%.1fs] Command CV101 to 0%% (Should ignore due to fault)\n', t);
        CV1.setCommand(0);
    end
    if t == 100
        fprintf('  [t=%.1fs] INJECTING: Motor Failure (P101)\n', t);
        Pump1.injectFault("MotorFailure");
    end
    
    % --- Interconnections ---
    % In this simplified integration model without a hydraulic solver, 
    % flow is determined by pump nominal flow modified by valve positions.
    
    % 1. Actuate equipment
    Valve1.update(dt);
    Pump1.update(dt);
    CV1.update(dt);
    
    % 2. Calculate system flow
    % Max flow is Pump flow when running
    availableFlow = 0;
    if Pump1.Outputs.Running
        availableFlow = 0.5; % simplified, assuming rated flow
    end
    
    % Actual flow is limited by V101 and modulated by CV101
    actualFlow = availableFlow * double(Valve1.Outputs.IsOpen) * CV1.Outputs.Position;
    
    % Send actual flow back to components for power calculation / logging
    Pump1.setInput("FlowRate", actualFlow);
    
    % 3. Update Tanks
    Tank1.setFlows(0, actualFlow);
    Tank2.setFlows(actualFlow, 0);
    
    Tank1.update(dt);
    Tank2.update(dt);
    
    % --- Record data ---
    level1(k) = Tank1.Outputs.Level;
    level2(k) = Tank2.Outputs.Level;
    pumpSpeed(k) = Pump1.Outputs.Speed;
    cvPos(k) = CV1.Outputs.Position;
    flow(k) = actualFlow;
end

fprintf('Simulation complete.\n\n');

%% 4. PLOTS

figure('Name', 'System Integration', 'Position', [100 100 800 600]);

subplot(4,1,1);
plot(time, level1, 'b-', time, level2, 'r-', 'LineWidth', 1.5);
ylabel('Level [m]');
title('Tank Levels');
legend('Tank1 (Supply)', 'Tank2 (Receive)');
grid on;

subplot(4,1,2);
plot(time, pumpSpeed, 'k-', 'LineWidth', 1.5);
ylabel('Speed [rpm]');
title('P101 Speed');
grid on;

subplot(4,1,3);
plot(time, cvPos * 100, 'g-', 'LineWidth', 1.5);
ylabel('Position [%]');
title('CV101 Position');
grid on;

subplot(4,1,4);
plot(time, flow, 'm-', 'LineWidth', 1.5);
xlabel('Time [s]');
ylabel('Flow [m3/s]');
title('System Flow');
grid on;

fprintf('\n============================================\n');
fprintf('       EXAMPLE COMPLETE\n');
fprintf('============================================\n\n');
