classdef ESimulationEngine < handle
    % ESimulationEngine  Runs the main simulation loop.

    properties
        Factory (1,1) EFactory
        TimeStep (1,1) double = 0.1
        Time (1,1) double = 0
    end
    
    methods
        function obj = ESimulationEngine(factory, dt)
            obj.Factory = factory;
            if nargin > 1
                obj.TimeStep = dt;
            end
        end
        
        function run(obj, duration)
            steps = round(duration / obj.TimeStep);
            for i = 1:steps
                obj.Factory.update(obj.TimeStep);
                obj.Time = obj.Time + obj.TimeStep;
            end
        end
    end
end
