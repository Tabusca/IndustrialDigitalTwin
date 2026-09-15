classdef TankPumpValveTest < matlab.unittest.TestCase
    % TankPumpValveTest  Integration tests for process equipment.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
        end
    end

    methods (Test)
        function testPumpTankTransfer(testCase)
            % Test transfer from Tank1 to Tank2 via a pump and pipe
            %
            % Layout:
            % Tank1 (Supply) -> Pipe1 -> Pump1 -> Pipe2 -> Tank2 (Receiver)
            
            Tank1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, "InitialLevel", 8);
            Tank2 = ETank("ID", "T2", "Diameter", 5, "Height", 10, "InitialLevel", 0);
            
            % Pump delivering 0.5 m3/s at 20m head
            Pump1 = EPump("ID", "P1", "RatedFlow", 0.5, "RatedHead", 20, "SpeedTimeConstant", 0.5);
            
            % Start simulation
            dt = 0.1;
            Pump1.start();
            
            for k=1:200
                % Update pump to get flow (assuming pump delivers rated flow when fully running)
                % In a real system, flow would depend on head curve and system curve.
                % Here, we just use a simplified coupling:
                
                Pump1.setInput("FlowRate", 0.5); 
                Pump1.update(dt);
                
                % Flow is delivered if pump is running
                actualFlow = Pump1.Outputs.FlowRate;
                
                % Tank1 drains, Tank2 fills
                Tank1.setFlows(0, actualFlow);
                Tank2.setFlows(actualFlow, 0);
                
                Tank1.update(dt);
                Tank2.update(dt);
            end
            
            % Tank1 level should have dropped, Tank2 should have risen
            testCase.verifyLessThan(Tank1.Outputs.Level, 8);
            testCase.verifyGreaterThan(Tank2.Outputs.Level, 0);
            
            % Volume conservation
            V1_initial = pi * 5^2 / 4 * 8;
            V2_initial = 0;
            V_total_initial = V1_initial + V2_initial;
            
            V_total_final = Tank1.Outputs.Volume + Tank2.Outputs.Volume;
            
            testCase.verifyEqual(V_total_final, V_total_initial, 'RelTol', 1e-10);
        end
        
        function testControlValveRegulation(testCase)
            % Tank emptying via control valve
            
            Tank1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, "InitialLevel", 8);
            CV1 = EControlValve("ID", "CV1", "Characteristic", "linear", "TimeConstant", 1.0);
            
            dt = 0.1;
            
            % Set CV to 50%
            CV1.setCommand(50);
            
            for k=1:200
                CV1.setInput("FlowRate", 1.0); % 1.0 m3/s available flow
                CV1.update(dt);
                
                % Tank1 drains with modulated flow
                Tank1.setFlows(0, CV1.Outputs.FlowRate);
                Tank1.update(dt);
            end
            
            % CV reached 50%
            testCase.verifyEqual(CV1.Outputs.Position, 0.5, 'RelTol', 1e-3);
            
            % Tank drained for 200 steps at 0.1s = 20s. 
            % Available flow is 1.0 m3/s, CV modulates to 0.5, so flow is ~0.5 m3/s.
            % Total volume drained is ~10 m3.
            V_initial = pi * 5^2 / 4 * 8;
            V_final = Tank1.Outputs.Volume;
            dV = V_initial - V_final;
            
            % First seconds CV was opening (from 0 to 0.5), so dV is slightly less than 10
            testCase.verifyGreaterThan(dV, 9.0);
            testCase.verifyLessThan(dV, 10.0);
        end
    end
end
