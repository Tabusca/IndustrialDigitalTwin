classdef EMotor < Equipment
    % EMotor  Industrial electric motor model.
    %
    %   Models a basic induction motor with speed dynamics.
    %
    %   Parameters:
    %     RatedSpeed [rpm]
    %     RatedPower [kW]
    %     TimeConstant [s] - spin up/down time
    %
    %   Inputs:
    %     Command [logical] - Start/Stop
    %
    %   Outputs:
    %     Speed [rpm]
    %     Running [logical]
    %     Power [kW]

    methods
        function obj = EMotor(options)
            arguments
                options.ID string
                options.RatedSpeed (1,1) double = 1450
                options.RatedPower (1,1) double = 10
                options.TimeConstant (1,1) double = 1.0
            end
            
            obj.ID = options.ID;
            obj.Type = "Motor";
            obj.Description = sprintf("Motor %.1f kW", options.RatedPower);
            
            obj.Parameters.RatedSpeed = options.RatedSpeed;
            obj.Parameters.RatedPower = options.RatedPower;
            obj.Parameters.TimeConstant = options.TimeConstant;
            
            obj.State.Speed = 0;
            obj.State.Running = false;
            obj.State.Power = 0;
            
            obj.Inputs.Command = false;
            
            obj.Faults.Overheat = false;
            obj.Faults.Tripped = false;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function start(obj), obj.Inputs.Command = true; end
        function stop(obj), obj.Inputs.Command = false; end
        
        function update(obj, dt)
            tau = obj.Parameters.TimeConstant;
            
            if obj.Faults.Tripped
                target = 0;
                obj.Inputs.Command = false;
            elseif obj.Inputs.Command
                target = obj.Parameters.RatedSpeed;
            else
                target = 0;
            end
            
            % First order dynamics
            dSpeed = (target - obj.State.Speed) / tau;
            obj.State.Speed = max(0, obj.State.Speed + dSpeed * dt);
            
            obj.State.Running = obj.State.Speed > 0.05 * obj.Parameters.RatedSpeed;
            
            if obj.State.Running
                obj.State.Power = obj.Parameters.RatedPower * (obj.State.Speed / obj.Parameters.RatedSpeed)^3;
            else
                obj.State.Power = 0;
            end
            
            if obj.Faults.Overheat
                obj.State.Power = obj.State.Power * 1.5; % Draws more power
            end
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function reset(obj)
            obj.State.Speed = 0;
            obj.State.Running = false;
            obj.State.Power = 0;
            obj.Inputs.Command = false;
            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function tags = getTags(obj)
            now = datetime("now");
            Tag = [obj.ID + ".SPEED"; obj.ID + ".RUNNING"; obj.ID + ".POWER"];
            Value = [obj.Outputs.Speed; double(obj.Outputs.Running); obj.Outputs.Power];
            Unit = ["rpm"; "-"; "kW"];
            Quality = repmat("GOOD", 3, 1);
            Timestamp = repmat(now, 3, 1);
            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end
    end
    
    methods (Access = protected)
        function faults = getSupportedFaults(~)
            faults = ["Overheat", "Tripped"];
        end
        function updateOutputs(obj)
            obj.Outputs.Speed = obj.State.Speed;
            obj.Outputs.Running = obj.State.Running;
            obj.Outputs.Power = obj.State.Power;
        end
        function updateStatus(obj)
            if obj.hasAnyFault(), obj.Status = "FAULTED";
            elseif obj.State.Running, obj.Status = "RUNNING";
            else, obj.Status = "STOPPED"; end
        end
    end
end
