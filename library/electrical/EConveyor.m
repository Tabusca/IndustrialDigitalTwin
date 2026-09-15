classdef EConveyor < Equipment
    % EConveyor  Industrial conveyor belt.
    %
    %   Models transport delay and discrete items or continuous flow.

    methods
        function obj = EConveyor(options)
            arguments
                options.ID string
                options.Length (1,1) double = 10 % meters
                options.Speed (1,1) double = 1.0 % m/s
            end
            
            obj.ID = options.ID;
            obj.Type = "Conveyor";
            obj.Description = "Conveyor Belt";
            
            obj.Parameters.Length = options.Length;
            obj.Parameters.Speed = options.Speed;
            
            obj.State.Running = false;
            obj.State.MaterialLoad = 0; % kg/m
            
            obj.Inputs.Command = false;
            obj.Inputs.MassIn = 0; % kg/s
            
            obj.Faults.BeltSlip = false;
            obj.Faults.MotorTrip = false;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function start(obj), obj.Inputs.Command = true; end
        function stop(obj), obj.Inputs.Command = false; end
        
        function update(obj, dt)
            if obj.Faults.MotorTrip
                obj.State.Running = false;
            else
                obj.State.Running = obj.Inputs.Command;
            end
            
            v = obj.Parameters.Speed;
            if obj.Faults.BeltSlip
                v = v * 0.5;
            end
            
            if obj.State.Running
                % Simple mass balance
                % Mass on belt changes based on input and output
                % Output is load * speed
                m_out = obj.State.MaterialLoad * v;
                dm = (obj.Inputs.MassIn - m_out) / obj.Parameters.Length;
                obj.State.MaterialLoad = max(0, obj.State.MaterialLoad + dm * dt);
            else
                m_out = 0;
            end
            
            obj.Outputs.MassOut = m_out;
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function reset(obj)
            obj.State.Running = false;
            obj.State.MaterialLoad = 0;
            obj.Inputs.Command = false;
            obj.Inputs.MassIn = 0;
            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function tags = getTags(obj)
            now = datetime("now");
            Tag = [obj.ID + ".RUNNING"; obj.ID + ".LOAD"; obj.ID + ".MASSOUT"];
            Value = [double(obj.Outputs.Running); obj.Outputs.MaterialLoad; obj.Outputs.MassOut];
            Unit = ["-"; "kg/m"; "kg/s"];
            Quality = repmat("GOOD", 3, 1);
            Timestamp = repmat(now, 3, 1);
            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end
    end
    
    methods (Access = protected)
        function faults = getSupportedFaults(~)
            faults = ["BeltSlip", "MotorTrip"];
        end
        function updateOutputs(obj)
            obj.Outputs.Running = obj.State.Running;
            obj.Outputs.MaterialLoad = obj.State.MaterialLoad;
        end
        function updateStatus(obj)
            if obj.hasAnyFault(), obj.Status = "FAULTED";
            elseif obj.State.Running, obj.Status = "RUNNING";
            else, obj.Status = "STOPPED"; end
        end
    end
end
