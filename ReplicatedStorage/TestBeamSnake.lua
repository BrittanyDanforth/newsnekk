-- TEST BEAM SNAKE - Simple version to verify beams work
local TestBeamSnake = {}

function TestBeamSnake.create(character)
	print("Creating test beam snake...")
	
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local model = Instance.new("Model")
	model.Name = "TestBeamSnake"
	model.Parent = workspace
	
	-- Create 5 parts in a line
	local parts = {}
	local attachments = {}
	
	for i = 1, 5 do
		local part = Instance.new("Part")
		part.Name = "BeamPart" .. i
		part.Size = Vector3.new(2, 2, 2)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = Color3.new(0, 1, 0)
		part.Anchored = true
		part.CanCollide = false
		part.Position = rootPart.Position + Vector3.new(0, 5, i * 5)
		part.Parent = model
		
		local attachment = Instance.new("Attachment")
		attachment.Parent = part
		
		table.insert(parts, part)
		table.insert(attachments, attachment)
	end
	
	-- Create beams between attachments
	for i = 1, #attachments - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "TestBeam" .. i
		beam.Attachment0 = attachments[i]
		beam.Attachment1 = attachments[i + 1]
		beam.Width0 = 10
		beam.Width1 = 10
		beam.Color = ColorSequence.new(Color3.new(0, 1, 0))
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0)
		beam.FaceCamera = true
		beam.Enabled = true
		beam.Parent = model
		
		print("Created beam", i, "between parts")
	end
	
	print("Test beam snake created! You should see green beams above you.")
	
	-- Make it follow the player
	game:GetService("RunService").Heartbeat:Connect(function()
		for i, part in ipairs(parts) do
			part.Position = rootPart.Position + Vector3.new(0, 5, i * 5) - rootPart.CFrame.LookVector * i * 5
		end
	end)
	
	return model
end

return TestBeamSnake