classdef EVFD < Equipment
    % EVFD  Variable Frequency Drive.
    %
    %   Controls an EMotor's speed setpoint.

    properties (SetAccess = protected)
        Motor
    end
    
    methods
        function obj = EVFD(options)
            arguments
                options.ID string
                options.Motor (1,1) handle
            end
            
            obj.ID = options.ID;
            obj.Type = "VFD";
            obj.Description = sprintf("VFD for %s", options.Motor.ID);
            obj.Motor = options.Motor;
            
            obj.Inputs.SpeedSetpoint = 0; % 0 to 100%
            obj.State.OutputFreq = 0;
            
            obj.Faults.DriveFault = false;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function setSetpoint(obj, pct)
            obj.Inputs.SpeedSetpoint = max(0, min(100, pct));
        end
        
        function update(obj, dt)
            if obj.Faults.DriveFault
                obj.Motor.stop();
                obj.State.OutputFreq = 0;
            else
                % VFD writes directly to motor's rated speed to simulate VFD control
                % A real VFD changes frequency. 100% = 50Hz/60Hz.
                rpmTarget = obj.Motor.Parameters.RatedSpeed * (obj.Inputs.SpeedSetpoint / 100);
                
                if obj.Inputs.SpeedSetpoint > 0
                    obj.Motor.start();
                    % Cheat by temporarily changing the motor's internal target logic
                    % or just overriding its speed directly if we want to be simple.
                    % Proper way: Motor should take a SpeedSetpoint input.
                    obj.Motor.Parameters.RatedSpeed = max(0.1, rpmTarget); % simplistic control
                else
                    obj.Motor.stop();
                end
                
                obj.State.OutputFreq = 50 * (obj.Inputs.SpeedSetpoint / 100);
            end
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function reset(obj)
            obj.Inputs.SpeedSetpoint = 0;
            obj.State.OutputFreq = 0;
            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function tags = getTags(obj)
            now = datetime("now");
            Tag = [obj.ID + ".SETPOINT"; obj.ID + ".FREQ"];
            Value = [obj.Inputs.SpeedSetpoint; obj.Outputs.OutputFreq];
            Unit = ["%"; "Hz"];
            Quality = repmat("GOOD", 2, 1);
            Timestamp = repmat(now, 2, 1);
            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end
    end
    
    methods (Access = protected)
        function faults = getSupportedFaults(~)
            faults = ["DriveFault"];
        end
        function updateOutputs(obj)
            obj.Outputs.OutputFreq = obj.State.OutputFreq;
        end
        function updateStatus(obj)
            if obj.hasAnyFault(), obj.Status = "FAULTED"; else, obj.Status = "OK"; end
        end
    end
end
