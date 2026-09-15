classdef EPump < Equipment
    % EPump  Industrial centrifugal pump model.
    %
    %   EPump models a centrifugal pump with a quadratic head-flow
    %   characteristic curve, speed dynamics, and power calculation.
    %
    %   Physics:
    %     Pump curve (at speed N):
    %       H = H_shutoff * (N/N_rated)² − k * Q²
    %
    %     where:
    %       k = (H_shutoff − H_rated) / Q_rated²
    %
    %     This follows from the affinity laws:
    %       Q ∝ N,  H ∝ N²,  P ∝ N³
    %
    %     Hydraulic power:
    %       P_hyd = ρ * g * Q * H
    %
    %     Shaft power (accounting for efficiency):
    %       P_shaft = P_hyd / η
    %
    %     The pump has an idle power consumption when running at zero
    %     flow, modeled as 10% of rated power.
    %
    %     Speed dynamics (first-order):
    %       dN/dt = (N_target − N) / τ
    %
    %   Assumptions:
    %     - Single-stage centrifugal pump
    %     - Quadratic head-flow characteristic
    %     - Affinity laws hold (no cavitation, no recirculation)
    %     - Constant efficiency across operating range
    %     - First-order speed response (motor/VFD dynamics lumped)
    %
    %   Limitations:
    %     - Efficiency does not vary with flow (real pumps have BEP)
    %     - No NPSH or cavitation modeling
    %     - No mechanical seal or bearing temperature model
    %     - Pump curve is quadratic (real curves may differ)
    %
    %   Parameters:
    %     RatedFlow       [m³/s]  - Flow at rated operating point
    %     RatedHead       [m]     - Head at rated operating point
    %     RatedSpeed      [rpm]   - Rated rotational speed
    %     Efficiency      [-]     - Pump efficiency (0−1)
    %     FluidDensity    [kg/m³] - Fluid density
    %     ShutoffHead     [m]     - Head at zero flow (default 1.25×RatedHead)
    %     SpeedTimeConst  [s]     - Speed response time constant (default 2s)
    %
    %   Inputs (set externally):
    %     Command        [logical] - Start/stop command
    %     SpeedSetpoint  [rpm]     - Desired speed (default: RatedSpeed)
    %     FlowRate       [m³/s]   - Actual flow (set by system/connection)
    %
    %   Outputs:
    %     Running     [logical] - Pump running state
    %     Speed       [rpm]     - Current speed
    %     FlowRate    [m³/s]   - Delivered flow (0 when stopped)
    %     Head        [m]       - Generated head at current flow & speed
    %     Power       [W]       - Shaft power consumption
    %
    %   Faults:
    %     BearingFault  - Efficiency reduced by 30%
    %     MotorFailure  - Pump stops immediately (speed → 0)
    %
    %   Example:
    %     Pump101 = EPump("ID","Pump101","RatedFlow",0.5,...
    %         "RatedHead",20,"RatedSpeed",1450,"Efficiency",0.75);
    %     Pump101.start();
    %     Pump101.setInput("FlowRate", 0.3);
    %     for k = 1:100, Pump101.update(0.1); end
    %     fprintf('Head = %.1f m, Power = %.0f W\n', ...
    %         Pump101.Outputs.Head, Pump101.Outputs.Power);
    %
    %   See also: Equipment, ETank, EValve


    methods

        function obj = EPump(options)
            % EPump  Construct a centrifugal pump model.

            arguments
                options.ID string
                options.RatedFlow (1,1) double {mustBePositive}
                options.RatedHead (1,1) double {mustBePositive}
                options.RatedSpeed (1,1) double {mustBePositive} = 1450
                options.Efficiency (1,1) double {mustBePositive} = 0.75
                options.FluidDensity (1,1) double {mustBePositive} = 998
                options.ShutoffHead (1,1) double = NaN
                options.SpeedTimeConstant (1,1) double {mustBePositive} = 2.0
            end

            if options.Efficiency > 1
                error("EPump:InvalidEfficiency", ...
                    "Efficiency must be between 0 and 1 (got %.2f).", ...
                    options.Efficiency);
            end

            % Identity
            obj.ID = options.ID;
            obj.Type = "Pump";
            obj.Description = sprintf( ...
                "Centrifugal pump, Q=%.3f m3/s, H=%.1f m", ...
                options.RatedFlow, options.RatedHead);

            % Operating parameters
            obj.Parameters.Rated.Flow = options.RatedFlow;
            obj.Parameters.Rated.Head = options.RatedHead;
            obj.Parameters.Rated.Speed = options.RatedSpeed;
            obj.Parameters.Rated.Efficiency = options.Efficiency;

            % Shutoff head (default: 125% of rated head)
            if isnan(options.ShutoffHead)
                H0 = 1.25 * options.RatedHead;
            else
                H0 = options.ShutoffHead;
            end

            if H0 <= options.RatedHead
                error("EPump:InvalidShutoffHead", ...
                    "ShutoffHead (%.1f m) must exceed RatedHead (%.1f m).", ...
                    H0, options.RatedHead);
            end

            obj.Parameters.Curve.ShutoffHead = H0;

            % Pump curve coefficient: H = H0*(N/N0)² - k*Q²
            % At rated point: H_rated = H0 - k*Q_rated²
            % → k = (H0 - H_rated) / Q_rated²
            k = (H0 - options.RatedHead) / options.RatedFlow^2;
            obj.Parameters.Curve.Coefficient = k;

            % Rated power for idle power calculation
            rho = options.FluidDensity;
            Prated = rho * 9.81 * options.RatedFlow * options.RatedHead ...
                / options.Efficiency;
            obj.Parameters.Rated.Power = Prated;

            % Fluid
            obj.Parameters.Fluid.Density = options.FluidDensity;

            % Dynamics
            obj.Parameters.Dynamics.SpeedTimeConstant = ...
                options.SpeedTimeConstant;

            % State
            obj.State.Running = false;
            obj.State.Speed = 0;
            obj.State.FlowRate = 0;
            obj.State.Head = 0;
            obj.State.Power = 0;

            % Inputs
            obj.Inputs.Command = false;
            obj.Inputs.SpeedSetpoint = options.RatedSpeed;
            obj.Inputs.FlowRate = 0;

            % Faults
            obj.Faults.BearingFault = false;
            obj.Faults.MotorFailure = false;

            % Initialize
            obj.updateOutputs();
            obj.updateStatus();
        end


        function start(obj)
            % start  Issue start command to the pump.
            obj.Inputs.Command = true;
        end


        function stop(obj)
            % stop  Issue stop command to the pump.
            obj.Inputs.Command = false;
        end


        function update(obj, dt)
            % update  Advance pump state by one timestep.
            %
            %   Pump speed follows first-order dynamics toward the
            %   target speed. Head is computed from the pump curve.
            %   Power is computed from hydraulic power and efficiency.

            arguments
                obj
                dt (1,1) double {mustBePositive}
            end

            N0 = obj.Parameters.Rated.Speed;
            tau = obj.Parameters.Dynamics.SpeedTimeConstant;

            % --- Determine speed target ---
            if obj.Faults.MotorFailure
                % Motor failure: pump coasts down to zero
                Ntarget = 0;
                obj.State.Running = false;
            elseif obj.Inputs.Command
                Ntarget = obj.Inputs.SpeedSetpoint;
                obj.State.Running = true;
            else
                Ntarget = 0;
                obj.State.Running = false;
            end

            % --- Speed dynamics (first-order) ---
            % dN/dt = (Ntarget - N) / τ
            dN = (Ntarget - obj.State.Speed) / tau;
            newSpeed = obj.State.Speed + dN * dt;

            % Clamp speed to non-negative
            newSpeed = max(0, newSpeed);
            obj.State.Speed = newSpeed;

            % Running state: consider pump running if speed > 1% of rated
            if newSpeed < 0.01 * N0
                obj.State.Running = false;
            end

            % --- Flow ---
            % When pump is not running, no flow is delivered
            if obj.State.Running && newSpeed > 0
                Q = obj.Inputs.FlowRate;
            else
                Q = 0;
            end
            obj.State.FlowRate = Q;

            % --- Pump curve: H = H0*(N/N0)² - k*Q² ---
            H0 = obj.Parameters.Curve.ShutoffHead;
            k = obj.Parameters.Curve.Coefficient;

            if newSpeed > 0
                r = newSpeed / N0;  % speed ratio
                H = H0 * r^2 - k * Q^2;
                H = max(0, H);  % head cannot be negative physically
            else
                H = 0;
            end
            obj.State.Head = H;

            % --- Power ---
            % P = ρ*g*Q*H/η  (hydraulic power / efficiency)
            rho = obj.Parameters.Fluid.Density;
            eta = obj.Parameters.Rated.Efficiency;

            % BearingFault reduces efficiency by 30%
            if obj.Faults.BearingFault
                eta = eta * 0.7;
            end

            if Q > 0 && H > 0 && eta > 0
                Phydraulic = rho * 9.81 * Q * H;
                Pshaft = Phydraulic / eta;
            else
                Pshaft = 0;
            end

            % Idle power when running but no useful work
            % (bearing friction, windage, recirculation)
            Pidle = 0.10 * obj.Parameters.Rated.Power ...
                * (newSpeed / N0)^3;

            obj.State.Power = max(Pshaft, Pidle);

            if ~obj.State.Running
                obj.State.Power = 0;
            end

            obj.updateOutputs();
            obj.updateStatus();
        end


        function reset(obj)
            % reset  Restore pump to initial conditions.

            obj.State.Running = false;
            obj.State.Speed = 0;
            obj.State.FlowRate = 0;
            obj.State.Head = 0;
            obj.State.Power = 0;

            obj.Inputs.Command = false;
            obj.Inputs.SpeedSetpoint = obj.Parameters.Rated.Speed;
            obj.Inputs.FlowRate = 0;

            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end


        function tags = getTags(obj)
            % getTags  Return pump industrial tags.

            now = datetime("now");
            statusCode = 0;
            if obj.Status == "STOPPED", statusCode = 1;
            elseif obj.Status == "FAULTED", statusCode = 3;
            end

            Tag = [
                obj.ID + ".RUNNING"
                obj.ID + ".SPEED"
                obj.ID + ".FLOW_RATE"
                obj.ID + ".HEAD"
                obj.ID + ".POWER"
                obj.ID + ".COMMAND"
                obj.ID + ".FAULT_BEARING"
                obj.ID + ".FAULT_MOTOR"
                obj.ID + ".STATUS"
            ];

            Value = [
                double(obj.Outputs.Running)
                obj.Outputs.Speed
                obj.Outputs.FlowRate
                obj.Outputs.Head
                obj.Outputs.Power
                double(obj.Inputs.Command)
                double(obj.Faults.BearingFault)
                double(obj.Faults.MotorFailure)
                statusCode
            ];

            Unit = ["-";"rpm";"m3/s";"m";"W";"-";"-";"-";"-"];
            Quality = repmat("GOOD", length(Tag), 1);
            Timestamp = repmat(now, length(Tag), 1);

            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end


        function H = computeHead(obj, Q, N)
            % computeHead  Calculate head for given flow and speed.
            %
            %   H = obj.computeHead(Q, N) returns the pump head [m]
            %   for flow Q [m³/s] at speed N [rpm].

            H0 = obj.Parameters.Curve.ShutoffHead;
            k = obj.Parameters.Curve.Coefficient;
            N0 = obj.Parameters.Rated.Speed;

            r = N / N0;
            H = H0 * r^2 - k * Q^2;
            H = max(0, H);
        end

    end


    methods (Access = protected)

        function faults = getSupportedFaults(~)
            faults = ["BearingFault", "MotorFailure"];
        end

        function updateOutputs(obj)
            obj.Outputs.Running = obj.State.Running;
            obj.Outputs.Speed = obj.State.Speed;
            obj.Outputs.FlowRate = obj.State.FlowRate;
            obj.Outputs.Head = obj.State.Head;
            obj.Outputs.Power = obj.State.Power;
        end

        function updateStatus(obj)
            if obj.hasAnyFault()
                obj.Status = "FAULTED";
            elseif obj.State.Running
                obj.Status = "RUNNING";
            else
                obj.Status = "STOPPED";
            end
        end

    end

end
