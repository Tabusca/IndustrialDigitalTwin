classdef EFilter < Equipment
    % EFilter  Industrial fluid filter.
    %
    %   Tracks clogging and pressure drop.

    methods
        function obj = EFilter(options)
            arguments
                options.ID string
                options.CleanResistance (1,1) double = 100
            end
            
            obj.ID = options.ID;
            obj.Type = "Filter";
            obj.Description = "Process Filter";
            
            obj.Parameters.CleanResistance = options.CleanResistance;
            
            obj.State.Clogging = 0; % 0 to 1
            obj.State.PressureDrop = 0;
            
            obj.Inputs.Flow = 0;
            
            obj.Faults.Rupture = false;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function update(obj, dt)
            if obj.Faults.Rupture
                obj.State.Clogging = 0;
                R = obj.Parameters.CleanResistance * 0.1; % Very low resistance
            else
                % Flow causes clogging over time
                obj.State.Clogging = min(1.0, obj.State.Clogging + obj.Inputs.Flow * 0.01 * dt);
                
                % Resistance increases exponentially with clogging
                R = obj.Parameters.CleanResistance * (1 + 10 * obj.State.Clogging^2);
            end
            
            obj.State.PressureDrop = R * obj.Inputs.Flow^2;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function reset(obj)
            obj.State.Clogging = 0;
            obj.State.PressureDrop = 0;
            obj.Inputs.Flow = 0;
            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function tags = getTags(obj)
            now = datetime("now");
            Tag = [obj.ID + ".CLOGGING"; obj.ID + ".DP"];
            Value = [obj.Outputs.Clogging * 100; obj.Outputs.PressureDrop];
            Unit = ["%"; "Pa"];
            Quality = repmat("GOOD", 2, 1);
            Timestamp = repmat(now, 2, 1);
            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end
    end
    
    methods (Access = protected)
        function faults = getSupportedFaults(~)
            faults = ["Rupture"];
        end
        function updateOutputs(obj)
            obj.Outputs.Clogging = obj.State.Clogging;
            obj.Outputs.PressureDrop = obj.State.PressureDrop;
        end
        function updateStatus(obj)
            if obj.hasAnyFault(), obj.Status = "FAULTED";
            elseif obj.State.Clogging > 0.9, obj.Status = "MAINTENANCE";
            else, obj.Status = "OK"; end
        end
    end
end
