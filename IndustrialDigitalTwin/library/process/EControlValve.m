classdef EControlValve < Equipment
    % EControlValve  Industrial modulating control valve model.
    %
    %   EControlValve models a continuously adjustable valve with
    %   first-order actuator dynamics and configurable flow
    %   characteristics.
    %
    %   Physics:
    %     Actuator (first-order lag):
    %       dPos/dt = (Command/100 − Position) / τ
    %
    %     Flow modulation:
    %       Q_out = f(Position) * Q_in
    %
    %     where f(x) is the inherent flow characteristic:
    %       Linear:           f(x) = x
    %       Equal percentage: f(x) = R^(x−1)  (R = rangeability)
    %       Quick opening:    f(x) = √x
    %
    %   Assumptions:
    %     - First-order actuator response (no deadband, no hysteresis)
    %     - Inherent characteristic (installed characteristic may differ)
    %     - No pressure-dependent flow (simplified flow-fraction model)
    %     - Rangeability applies only to equal-percentage characteristic
    %
    %   Limitations:
    %     - No Cv/Kv-based pressure-flow calculation in this version
    %     - No positioner model
    %     - No seat leakage
    %     - No cavitation or flashing model
    %
    %   Parameters:
    %     Characteristic       - "linear","equalpercentage","quickopening"
    %     Actuator.TimeConstant [s] - First-order time constant (default 1s)
    %     Rangeability         [-]  - For equal-percentage (default 50)
    %     FailPosition         [-]  - 0=fail-closed, 1=fail-open (default 0)
    %
    %   Inputs:
    %     Command  [0−100 %] - Desired valve position in percent
    %     FlowRate [m³/s]   - Upstream available flow
    %
    %   Outputs:
    %     Position [0−1]    - Actual valve position (fraction)
    %     FlowRate [m³/s]  - Modulated output flow
    %
    %   Faults:
    %     StuckOpen      - Position forced to 1.0
    %     StuckClosed    - Position forced to 0.0
    %     Stuck          - Position frozen at current value
    %     ActuatorFailure - Position drives to FailPosition
    %
    %   Example:
    %     CV101 = EControlValve("ID","CV101","Characteristic","linear");
    %     CV101.setCommand(50);
    %     CV101.setInput("FlowRate", 0.5);
    %     for k = 1:50, CV101.update(0.1); end
    %     fprintf('Position = %.1f%%\n', CV101.Outputs.Position * 100);
    %
    %   See also: Equipment, EValve, EPump


    methods

        function obj = EControlValve(options)
            % EControlValve  Construct a modulating control valve.

            arguments
                options.ID string
                options.Characteristic string = "linear"
                options.TimeConstant (1,1) double {mustBePositive} = 1.0
                options.Rangeability (1,1) double {mustBePositive} = 50
                options.FailPosition (1,1) double {mustBeNonnegative} = 0
                options.InitialPosition (1,1) double {mustBeNonnegative} = 0
            end

            validChars = ["linear", "equalpercentage", "quickopening"];
            if ~ismember(options.Characteristic, validChars)
                error("EControlValve:InvalidCharacteristic", ...
                    "Characteristic must be one of: %s (got '%s').", ...
                    strjoin(validChars, ", "), options.Characteristic);
            end

            if options.FailPosition > 1
                error("EControlValve:InvalidFailPosition", ...
                    "FailPosition must be 0 or 1 (got %.2f).", ...
                    options.FailPosition);
            end

            if options.InitialPosition > 1
                error("EControlValve:InvalidInitialPosition", ...
                    "InitialPosition must be between 0 and 1 (got %.2f).", ...
                    options.InitialPosition);
            end

            % Identity
            obj.ID = options.ID;
            obj.Type = "ControlValve";
            obj.Description = sprintf("Control valve, %s, τ=%.1fs", ...
                options.Characteristic, options.TimeConstant);

            % Parameters
            obj.Parameters.Characteristic = options.Characteristic;
            obj.Parameters.Actuator.TimeConstant = options.TimeConstant;
            obj.Parameters.Rangeability = options.Rangeability;
            obj.Parameters.FailPosition = options.FailPosition;
            obj.Parameters.InitialConditions.Position = ...
                options.InitialPosition;

            % State
            obj.State.Position = options.InitialPosition;
            obj.State.FlowRate = 0;

            % Inputs
            obj.Inputs.Command = options.InitialPosition * 100;
            obj.Inputs.FlowRate = 0;

            % Faults
            obj.Faults.StuckOpen = false;
            obj.Faults.StuckClosed = false;
            obj.Faults.Stuck = false;
            obj.Faults.ActuatorFailure = false;

            % Initialize
            obj.updateOutputs();
            obj.updateStatus();
        end


        function setCommand(obj, percent)
            % setCommand  Set valve command in percent (0−100%).
            %
            %   obj.setCommand(pct) where pct is 0 to 100.

            arguments
                obj
                percent (1,1) double
            end

            if percent < 0 || percent > 100
                error("EControlValve:InvalidCommand", ...
                    "Command must be 0−100%% (got %.1f).", percent);
            end

            obj.Inputs.Command = percent;
        end


        function update(obj, dt)
            % update  Advance actuator and compute flow.
            %
            %   Actuator follows first-order dynamics toward target.
            %   Flow is modulated by the inherent characteristic.

            arguments
                obj
                dt (1,1) double {mustBePositive}
            end

            tau = obj.Parameters.Actuator.TimeConstant;
            currentPos = obj.State.Position;

            % --- Determine target position (fault overrides) ---
            if obj.Faults.StuckOpen
                target = 1.0;
            elseif obj.Faults.StuckClosed
                target = 0.0;
            elseif obj.Faults.Stuck
                target = currentPos;  % frozen at current position
            elseif obj.Faults.ActuatorFailure
                target = obj.Parameters.FailPosition;
            else
                target = obj.Inputs.Command / 100.0;
            end

            % --- Actuator dynamics (first-order lag) ---
            if obj.Faults.Stuck
                newPos = currentPos;  % no movement at all
            else
                dPos = (target - currentPos) / tau * dt;
                newPos = currentPos + dPos;
            end

            % Clamp to physical range [0, 1]
            newPos = max(0, min(1, newPos));
            obj.State.Position = newPos;

            % --- Flow modulation ---
            Qin = obj.Inputs.FlowRate;
            f = obj.computeCharacteristic(newPos);
            obj.State.FlowRate = f * Qin;

            obj.updateOutputs();
            obj.updateStatus();
        end


        function reset(obj)
            % reset  Restore control valve to initial conditions.

            initPos = obj.Parameters.InitialConditions.Position;

            obj.State.Position = initPos;
            obj.State.FlowRate = 0;

            obj.Inputs.Command = initPos * 100;
            obj.Inputs.FlowRate = 0;

            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end


        function tags = getTags(obj)
            % getTags  Return control valve industrial tags.

            now = datetime("now");
            statusCode = 0;
            if obj.hasAnyFault(), statusCode = 3; end

            Tag = [
                obj.ID + ".POSITION"
                obj.ID + ".COMMAND"
                obj.ID + ".FLOW_RATE"
                obj.ID + ".FAULT_STUCK_OPEN"
                obj.ID + ".FAULT_STUCK_CLOSED"
                obj.ID + ".FAULT_STUCK"
                obj.ID + ".FAULT_ACTUATOR"
                obj.ID + ".STATUS"
            ];

            Value = [
                obj.Outputs.Position * 100
                obj.Inputs.Command
                obj.Outputs.FlowRate
                double(obj.Faults.StuckOpen)
                double(obj.Faults.StuckClosed)
                double(obj.Faults.Stuck)
                double(obj.Faults.ActuatorFailure)
                statusCode
            ];

            Unit = ["%";"%";"m3/s";"-";"-";"-";"-";"-"];
            Quality = repmat("GOOD", length(Tag), 1);
            Timestamp = repmat(now, length(Tag), 1);

            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end


        function f = computeCharacteristic(obj, x)
            % computeCharacteristic  Evaluate inherent flow characteristic.
            %
            %   f = obj.computeCharacteristic(x) returns the flow
            %   fraction [0−1] for position x [0−1].
            %
            %   Linear:           f = x
            %   Equal percentage: f = R^(x−1)  (approaches 1/R at x=0)
            %   Quick opening:    f = √x

            switch obj.Parameters.Characteristic
                case "linear"
                    f = x;

                case "equalpercentage"
                    R = obj.Parameters.Rangeability;
                    if x <= 0
                        f = 1 / R;  % minimum controllable flow
                    else
                        f = R^(x - 1);
                    end

                case "quickopening"
                    f = sqrt(max(0, x));

                otherwise
                    f = x;
            end

            % Clamp to [0, 1]
            f = max(0, min(1, f));
        end

    end


    methods (Access = protected)

        function faults = getSupportedFaults(~)
            faults = ["StuckOpen", "StuckClosed", "Stuck", "ActuatorFailure"];
        end

        function updateOutputs(obj)
            obj.Outputs.Position = obj.State.Position;
            obj.Outputs.FlowRate = obj.State.FlowRate;
        end

        function updateStatus(obj)
            if obj.hasAnyFault()
                obj.Status = "FAULTED";
            else
                obj.Status = "OK";
            end
        end

    end

end
