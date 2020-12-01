-------------------------------
--Copyright (c) 2018 DasEtwas--
-------------------------------

Airfoil = class()
Airfoil.airDensity = 0.6465      -- air density in kg/m³/2. This is a convenient constant to apply coefficients to, which is why this is divided by 2.
Airfoil.sleepTime = 5           -- how many updates it takes for a wing to fall asleep
Airfoil.maxJerk = (72.0) / 40.0 -- lift change clamp in (N/tick/sec or 40N/s²) per (m/s) = 40*N/(m*s)
Airfoil.maxVel = 600            -- velocity at which wings are turned off
Airfoil.maxVelTimeout = 400     -- how long in ticks wings are shut off if they exceed max velocity
Airfoil.stallAngle = 0.19
Airfoil.stallTransition = 0.15
Airfoil.stallLift = 0.4
Airfoil.stallDrag = 0.02

function Airfoil:server_onCreate()
    self.area = self.data.area
    -- angle gives rotation about the local z axis (getUp)
    self.angle = math.rad(self.data.angle)
    self.sleepTimer = 0
end

function Airfoil:server_onFixedUpdate(deltaTime)
    local globalVel = sm.shape.getVelocity(self.shape)
    local globalVelLength = globalVel:length()

    if globalVelLength > 0.08 then
        self.sleepTimer = self.sleepTimer + 1
    else
        self.sleepTimer = math.max(-self.sleepTime, math.min(self.sleepTimer - 1, 0))
    end

    -- spazzing out protection
    if globalVelLength > self.maxVel and self.sleepTimer > -self.sleepTime then
        self.sleepTimer = -self.maxVelTimeout
        print("[Wings] Disabled wing for " .. (self.maxVelTimeout * deltaTime) .. " seconds due to high velocity (>" .. self.maxVel .. "m/s)")
    end
	
	-- This is reset here so that if the wing is sleeping it's not considered stalled.
	-- Technically just for debugging purposes.
	self.stalled = false

    if self.sleepTimer > 0 then
        local lastLift = self.liftMagnitude or 0
		
        local aSin = math.sin(self.angle)
        local aCos = math.cos(self.angle)

		-- globalUp factors in the inherent angle of the wing.
        local globalUp = sm.shape.getRight(self.shape) * aSin + sm.shape.getAt(self.shape) * aCos
		local normalizedVel = globalVel:normalize()
		local velSquared = globalVelLength * globalVelLength
		
		-- Stall calculation
		local angleOfAttack = -normalizedVel:dot(globalUp)

		self.stalled = math.abs(angleOfAttack) > self.stallAngle
		
		--print(angleOfAttack)
		--print(self.stalled)
		
		-- On a scale of 0 to 1, how stalled is this surface?
		local stallDegree = math.min(math.max((math.abs(angleOfAttack) - self.stallAngle) / self.stallTransition, 0), 1)
		
		local stallLiftCoefficient = 1 - stallDegree * (1 - self.stallLift)
		local stallDragCoefficient = stallDegree * self.stallDrag

		--print(stallLiftCoefficient)
		--print(stallDragCoefficient)
		
        -- lift magnitude along wing normal vector
        self.liftMagnitude = self.airDensity * angleOfAttack * velSquared * self.area * stallLiftCoefficient
		-- drag magnitude along negative velocity vector
		local dragMagnitude = self.airDensity * math.abs(angleOfAttack) * velSquared * self.area * stallDragCoefficient
		
		--print(self.liftMagnitude)
		--print(dragMagnitude)

        if math.abs(self.liftMagnitude) - math.abs(lastLift) > 0 then
            -- lift magnitude has increased
            self.liftMagnitude = lastLift + math.max(-self.maxJerk * globalVelLength, math.min(self.maxJerk * globalVelLength, self.liftMagnitude - lastLift))
        end

        local lift = sm.vec3.new(aSin, aCos, 0) * (self.liftMagnitude * deltaTime * 40)
		local drag = normalizedVel * -dragMagnitude * deltaTime * 40
		-- Lift is applied relative to the angle of the wing
        sm.physics.applyImpulse(self.shape, lift)
		-- Drag is applied relative to the world
		sm.physics.applyImpulse(self.shape, drag, true)
    end
end
