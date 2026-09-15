classdef EValveTest < matlab.unittest.TestCase
    % EValveTest  Comprehensive test suite for the EValve class.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
        end
    end

    methods (Test)
        function testConstruction(testCase)
            V1 = EValve("ID", "V1", "StrokeTime", 5.0, "InitialPosition", 0);
            testCase.verifyEqual(V1.ID, "V1");
            testCase.verifyEqual(V1.Parameters.Actuator.StrokeTime, 5.0);
            testCase.verifyEqual(V1.Outputs.Position, 0);
            testCase.verifyTrue(V1.Outputs.IsClosed);
        end

        function testOpenDynamics(testCase)
            V1 = EValve("ID", "V1", "StrokeTime", 4.0);
            V1.open();
            
            V1.update(1.0); % 25% open
            testCase.verifyEqual(V1.Outputs.Position, 0.25, 'RelTol', 1e-12);
            testCase.verifyFalse(V1.Outputs.IsOpen);
            testCase.verifyEqual(V1.Status, "TRANSIT");
            
            V1.update(3.0); % 100% open
            testCase.verifyEqual(V1.Outputs.Position, 1.0, 'RelTol', 1e-12);
            testCase.verifyTrue(V1.Outputs.IsOpen);
            testCase.verifyEqual(V1.Status, "OPEN");
        end

        function testFlowModulation(testCase)
            V1 = EValve("ID", "V1", "StrokeTime", 2.0);
            V1.open();
            V1.setInput("FlowRate", 10.0);
            
            V1.update(1.0); % 50% open
            testCase.verifyEqual(V1.Outputs.FlowRate, 5.0, 'RelTol', 1e-12);
            
            V1.update(1.0); % 100% open
            testCase.verifyEqual(V1.Outputs.FlowRate, 10.0, 'RelTol', 1e-12);
        end

        function testStuckOpenFault(testCase)
            V1 = EValve("ID", "V1", "StrokeTime", 2.0);
            V1.injectFault("StuckOpen");
            
            % Even without open command, it should go to open
            V1.update(1.0); 
            testCase.verifyEqual(V1.Outputs.Position, 0.5, 'RelTol', 1e-12);
            V1.update(1.0);
            testCase.verifyEqual(V1.Outputs.Position, 1.0, 'RelTol', 1e-12);
            
            % Close command should be ignored
            V1.close();
            V1.update(1.0);
            testCase.verifyEqual(V1.Outputs.Position, 1.0, 'RelTol', 1e-12);
            testCase.verifyEqual(V1.Status, "FAULTED");
        end

        function testStuckClosedFault(testCase)
            V1 = EValve("ID", "V1", "StrokeTime", 2.0, "InitialPosition", 1.0);
            V1.injectFault("StuckClosed");
            
            % Even with command open (since init pos is 1), it should close
            V1.open(); 
            V1.update(1.0); 
            testCase.verifyEqual(V1.Outputs.Position, 0.5, 'RelTol', 1e-12);
            V1.update(1.0);
            testCase.verifyEqual(V1.Outputs.Position, 0.0, 'RelTol', 1e-12);
        end

        function testReset(testCase)
            V1 = EValve("ID", "V1", "StrokeTime", 2.0, "InitialPosition", 0);
            V1.open();
            V1.update(2.0);
            testCase.verifyEqual(V1.Outputs.Position, 1.0);
            
            V1.reset();
            testCase.verifyEqual(V1.Outputs.Position, 0);
            testCase.verifyTrue(V1.Outputs.IsClosed);
        end
        
        function testTags(testCase)
            V1 = EValve("ID", "V1");
            tags = V1.getTags();
            testCase.verifyEqual(height(tags), 8);
            testCase.verifyTrue(any(tags.Tag == "V1.POSITION"));
            testCase.verifyTrue(any(tags.Tag == "V1.IS_OPEN"));
        end
    end
end
