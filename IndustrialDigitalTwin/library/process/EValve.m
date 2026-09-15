classdef EValve < Equipment
    % EValve  Industrial on/off valve model.
    %
    %   EValve models a binary (open/close) valve with linear actuator
    %   travel time and fault injection.
    %
    %   Physics:
    %     Position ramps linearly between 0 (closed) and 1 (open)
    %     over the StrokeTime parameter.
    %
    %     Flow modulation:
    %       Q_out = Position * Q_in
    %
    %     During transition, flow is proportional to position,
    %     modeling the gradual opening/closing of the valve disc.
    %
    %   Assumptions:
    %     - Linear relationship between position and flow area
    %     - No pressure-dependent flow calculation (simplified model)
    %     - Instantaneous position change if StrokeTime = 0
    %     - No hysteresis in actuator
    %
    %   Limitations:
    %     - No Cv-based flow calculation (use EControlValve for that)
    %     - No seat leakage when closed
    %     - No dynamic pressure drop model
    %
    %   Parameters:
    %     StrokeTime    [s] - Time for full open/close travel (default 2s)
    %
    %   Inputs:
    %     Command  [logical] - true=open, false=close
    %     FlowRate [m³/s]   - upstream available flow
    %
    %   Outputs:
    %     Position [0−1]    - current valve position
    %     FlowRate [m³/s]  - flow through valve
    %     IsOpen   [logical] - true when fully open
    %     IsClosed [logical] - true when fully closed
    %
    %   Faults:
    %     StuckOpen   - valve stays fully open regardless of command
    %     StuckClosed - valve stays fully closed regardless of command
    %
    %   Example:
    %     Valve101 = EValve("ID","Valve101","StrokeTime",3);
    %     Valve101.open();
    %     Valve101.setInput("FlowRate", 0.5);
    %     for k = 1:50, Valve101.update(0.1); end
    %     fprintf('Position = %.2f\n', Valve101.Outputs.Position);
    %
    %   See also: Equipment, EControlValve, EPump


    methods

        function obj = EValve(options)
            % EValve  Construct an on/off valve.

            arguments
                options.ID string
                options.StrokeTime (1,1) double {mustBeNonnegative} = 2.0
                options.InitialPosition (1,1) double {mustBeNonnegative} = 0
            end

            if options.InitialPosition > 1
                error("EValve:InvalidPosition", ...
                    "InitialPosition must be between 0 and 1 (got %.2f).", ...
                    options.InitialPosition);
            end

            % Identity
            obj.ID = options.ID;
            obj.Type = "Valve";
            obj.Description = sprintf("On/off valve, stroke=%.1fs", ...
                options.StrokeTime);

            % Parameters
            obj.Parameters.Actuator.StrokeTime = options.StrokeTime;
            obj.Parameters.InitialConditions.Position = ...
                options.InitialPosition;

            % State
            obj.State.Position = options.InitialPosition;
            obj.State.FlowRate = 0;

            % Inputs
            obj.Inputs.Command = (options.InitialPosition > 0.5);
            obj.Inputs.FlowRate = 0;

            % Faults
            obj.Faults.StuckOpen = false;
            obj.Faults.StuckClosed = false;

            % Initialize
            obj.updateOutputs();
            obj.updateStatus();
        end


        function open(obj)
            % open  Command the valve to open.
            obj.Inputs.Command = true;
        end


        function close(obj)
            % close  Command the valve to close.
            obj.Inputs.Command = false;
        end


        function update(obj, dt)
            % update  Advance valve actuator and compute flow.
            %
            %   The valve position ramps linearly toward the target
            %   at a rate of 1/StrokeTime per second.

            arguments
                obj
                dt (1,1) double {mustBePositive}
            end

            % Determine target position (fault override)
            if obj.Faults.StuckOpen
                target = 1;
            elseif obj.Faults.StuckClosed
                target = 0;
            else
                target = double(obj.Inputs.Command);
            end

            % Actuator dynamics: linear ramp
            strokeTime = obj.Parameters.Actuator.StrokeTime;
            currentPos = obj.State.Position;

            if strokeTime > 0
                % Rate of position change [1/s]
                rate = 1.0 / strokeTime;
                maxChange = rate * dt;

                posError = target - currentPos;

                if abs(posError) <= maxChange
                    newPos = target;
                else
                    newPos = currentPos + sign(posError) * maxChange;
                end
            else
                % Instantaneous actuation
                newPos = target;
            end

            % Clamp position to [0, 1]
            newPos = max(0, min(1, newPos));
            obj.State.Position = newPos;

            % Flow modulation: Q_out = Position * Q_in
            Qin = obj.Inputs.FlowRate;
            obj.State.FlowRate = newPos * Qin;

            obj.updateOutputs();
            obj.updateStatus();
        end


        function reset(obj)
            % reset  Restore valve to initial conditions.

            initPos = obj.Parameters.InitialConditions.Position;

            obj.State.Position = initPos;
            obj.State.FlowRate = 0;

            obj.Inputs.Command = (initPos > 0.5);
            obj.Inputs.FlowRate = 0;

            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end


        function tags = getTags(obj)
            % getTags  Return valve industrial tags.

            now = datetime("now");
            statusCode = 0;
            if obj.hasAnyFault(), statusCode = 3; end

            Tag = [
                obj.ID + ".POSITION"
                obj.ID + ".FLOW_RATE"
                obj.ID + ".COMMAND"
                obj.ID + ".IS_OPEN"
                obj.ID + ".IS_CLOSED"
                obj.ID + ".FAULT_STUCK_OPEN"
                obj.ID + ".FAULT_STUCK_CLOSED"
                obj.ID + ".STATUS"
            ];

            Value = [
                obj.Outputs.Position
                obj.Outputs.FlowRate
                double(obj.Inputs.Command)
                double(obj.Outputs.IsOpen)
                double(obj.Outputs.IsClosed)
                double(obj.Faults.StuckOpen)
                double(obj.Faults.StuckClosed)
                statusCode
            ];

            Unit = ["-";"m3/s";"-";"-";"-";"-";"-";"-"];
            Quality = repmat("GOOD", length(Tag), 1);
            Timestamp = repmat(now, length(Tag), 1);

            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end

    end


    methods (Access = protected)

        function faults = getSupportedFaults(~)
            faults = ["StuckOpen", "StuckClosed"];
        end

        function updateOutputs(obj)
            obj.Outputs.Position = obj.State.Position;
            obj.Outputs.FlowRate = obj.State.FlowRate;
            obj.Outputs.IsOpen = (obj.State.Position >= 1.0);
            obj.Outputs.IsClosed = (obj.State.Position <= 0.0);
        end

        function updateStatus(obj)
            if obj.hasAnyFault()
                obj.Status = "FAULTED";
            elseif obj.Outputs.IsOpen
                obj.Status = "OPEN";
            elseif obj.Outputs.IsClosed
                obj.Status = "CLOSED";
            else
                obj.Status = "TRANSIT";
            end
        end

    end

end
