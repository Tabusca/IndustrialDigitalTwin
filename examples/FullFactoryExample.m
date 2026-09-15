%% Full Factory Example
%
%  Demonstrates the complete Industrial Digital Twin framework integrating:
%  - Core architecture (Equipment, IndustrialObject)
%  - Process units (Tanks, Pumps, Valves, Mixers, Heaters, Filters)
%  - Electrical units (Motors, VFDs)
%  - Instrumentation (Transmitters with noise and faults)
%  - System architecture (Factory, Connections, Simulation Engine)
%  - Tag Database & Historian

clear; clc; close all;

fprintf('============================================\n');
fprintf('       FULL FACTORY SIMULATION\n');
fprintf('============================================\n\n');

% Add paths
thisDir = fileparts(mfilename('fullpath'));
projectRoot = fullfile(thisDir, '..');
addpath(genpath(fullfile(projectRoot, 'library')));

%% 1. INITIALIZE FACTORY
factory = EFactory();

%% 2. CREATE EQUIPMENT

% Process Units
TankA = ETank("ID", "TK101", "Diameter", 5, "Height", 10, "InitialLevel", 8);
TankB = ETank("ID", "TK102", "Diameter", 3, "Height", 8, "InitialLevel", 5);
Mixer = EMixer("ID", "MX101", "Volume", 15);
Heater = EHeater("ID", "HT101", "Capacity", 150000); % 150 kW
Filter = EFilter("ID", "FL101");
TankProduct = ETank("ID", "TK201", "Diameter", 6, "Height", 12, "InitialLevel", 1);

% Electrical & Fluid Movers
MotorA = EMotor("ID", "MTR101", "RatedSpeed", 1500, "RatedPower", 15);
VFD_A = EVFD("ID", "VFD101", "Motor", MotorA);
PumpA = EPump("ID", "PMP101", "RatedFlow", 2.0, "RatedHead", 50, "RatedSpeed", 1500);

MotorB = EMotor("ID", "MTR102", "RatedSpeed", 1500, "RatedPower", 10);
VFD_B = EVFD("ID", "VFD102", "Motor", MotorB);
PumpB = EPump("ID", "PMP102", "RatedFlow", 1.0, "RatedHead", 30, "RatedSpeed", 1500);

ValveA = EControlValve("ID", "CV101");
ValveB = EControlValve("ID", "CV102");

% Sensors
LT_A = ELevelTransmitter("ID", "LT101", "Target", TankA, "RangeMax", 10);
LT_B = ELevelTransmitter("ID", "LT102", "Target", TankB, "RangeMax", 8);
FT_A = EFlowTransmitter("ID", "FT101", "Target", PumpA, "RangeMax", 3.0);
FT_B = EFlowTransmitter("ID", "FT102", "Target", PumpB, "RangeMax", 1.5);
LT_Prod = ELevelTransmitter("ID", "LT201", "Target", TankProduct, "RangeMax", 12);

%% 3. ADD TO FACTORY
factory.add(TankA); factory.add(TankB); factory.add(Mixer);
factory.add(Heater); factory.add(Filter); factory.add(TankProduct);
factory.add(MotorA); factory.add(VFD_A); factory.add(PumpA);
factory.add(MotorB); factory.add(VFD_B); factory.add(PumpB);
factory.add(ValveA); factory.add(ValveB);
factory.add(LT_A); factory.add(LT_B);
factory.add(FT_A); factory.add(FT_B); factory.add(LT_Prod);

%% 4. SETUP CONNECTIONS (Simple Physics linking)
% VFD speed dictates Pump speed
factory.add(EConnection(MotorA, 'Speed', PumpA, 'Speed'));
factory.add(EConnection(MotorB, 'Speed', PumpB, 'Speed'));

% We will handle flow routing manually in a custom update loop hook,
% or we can just write a wrapper for the physics.
% For true modularity, we would use EConnection for everything, but 
% hydraulic networks are complex to solve. Here we do simplified forward-flow.

% Initial conditions and setpoints
VFD_A.setSetpoint(80); % 80% speed
VFD_B.setSetpoint(100); % 100% speed
ValveA.setInput('Command', 100); % 100% open
ValveB.setInput('Command', 50); % 50% open

Heater.setInput('Command', 100); % 100% heating
Heater.setInput('TemperatureIn', 20); % Ambient water

%% 5. CUSTOM SIMULATION LOOP
fprintf('Running 60-second simulation...\n');

dt = 0.5;
engine = ESimulationEngine(factory, dt);

simTime = 60;
steps = simTime / dt;

for k = 1:steps
    % --- 1. Custom Hydraulic Routing (Simplified) ---
    % Calculate flows based on pump speed and valve position
    flowA = PumpA.Parameters.Rated.Flow * (PumpA.Outputs.Speed / PumpA.Parameters.Rated.Speed) * (ValveA.Outputs.Position / 100);
    flowB = PumpB.Parameters.Rated.Flow * (PumpB.Outputs.Speed / PumpB.Parameters.Rated.Speed) * (ValveB.Outputs.Position / 100);
    
    TankA.setFlows(0, flowA);
    PumpA.setInput('FlowRate', flowA);
    
    TankB.setFlows(0, flowB);
    PumpB.setInput('FlowRate', flowB);
    
    Mixer.setInput('FlowA', flowA);
    Mixer.setInput('ConcA', 1.0); % Tank A is pure product
    Mixer.setInput('FlowB', flowB);
    Mixer.setInput('ConcB', 0.0); % Tank B is pure water
    Mixer.setInput('FlowOut', flowA + flowB);
    
    Heater.setInput('Flow', flowA + flowB);
    Filter.setInput('Flow', flowA + flowB);
    
    TankProduct.setFlows(flowA + flowB, 0);
    
    % Inject a fault midway
    if k == floor(steps/2)
        fprintf('  --> Injecting Heater Element Failure!\n');
        Heater.injectFault('ElementFailure');
        fprintf('  --> Injecting Filter Rupture!\n');
        Filter.injectFault('Rupture');
    end
    
    % --- 2. Factory Update ---
    factory.update(dt);
end

fprintf('Simulation complete!\n\n');

%% 6. VISUALIZE RESULTS
fprintf('Extracting Historian Data...\n');

ttMixer = factory.Historian.getHistory("MX101.CONC");
ttHeater = factory.Historian.getHistory("HT101.TEMP_OUT");
ttFilter = factory.Historian.getHistory("FL101.DP");
ttTank = factory.Historian.getHistory("TK201.VOLUME");

figure('Name', 'Full Factory Run', 'Position', [100, 100, 1000, 800]);

subplot(4,1,1);
plot(ttTank.Time, ttTank.Value, 'LineWidth', 1.5);
ylabel('Vol [m3]'); title('Product Tank Volume'); grid on;

subplot(4,1,2);
plot(ttMixer.Time, ttMixer.Value, 'LineWidth', 1.5);
ylabel('Conc [%]'); title('Mixer Concentration'); grid on;

subplot(4,1,3);
plot(ttHeater.Time, ttHeater.Value, 'r-', 'LineWidth', 1.5);
ylabel('Temp [°C]'); title('Heater Outlet Temperature (Fault injected at t=30s)'); grid on;

subplot(4,1,4);
plot(ttFilter.Time, ttFilter.Value, 'k-', 'LineWidth', 1.5);
ylabel('DP [Pa]'); title('Filter Pressure Drop (Rupture at t=30s)'); grid on;

fprintf('Done.\n');
