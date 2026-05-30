
-- Vape Library Initialization (Use shared.vape if injecting into an existing vape s
-- 1. Create the custom Category
local babftCategory = vape:CreateCategory({
    Name = 'BABFT Tools',
    Icon = 'rbxassetid://0', -- Replace with your desired icon if needed
    Size = UDim2.fromOffset(16, 16)
})

-- UI Component Variables
local autoBuilderModule
local fileDropdown
local refreshButton
local speedSlider
local useScaleToggle
local usePaintToggle
local usePropToggle

-- File Fetching Helper
local function getBuildFiles()
    local files = {}
    if listfiles then
        for _, f in ipairs(listfiles("") or listfiles("workspace") or {}) do
            -- Look for .build or .txt files in the executor workspace
            if f:lower():match("%.build$") or f:lower():match("%.txt$") then
                table.insert(files, f:match("([^/%\\]+)$"))
            end
        end
    end
    if #files == 0 then table.insert(files, "build.txt") end -- Fallback default
    return files
end

-- 2. Create the Module
autoBuilderModule = vape.Categories['BABFT Tools']:CreateModule({
    Name = 'AutoBuilder',
    Tooltip = 'Automatically loads and builds your BABFT structures.',
    Function = function(callback)
        if not callback then return end -- Only run when toggled ON
        
        task.spawn(function()
            local HttpService = game:GetService("HttpService")
            local repStorage = game:GetService("ReplicatedStorage")
            local lp = game:GetService("Players").LocalPlayer
            local char = lp.Character or lp.CharacterAdded:Wait()
            local dataFolder = lp:WaitForChild("Data")
            local buildingParts = repStorage:WaitForChild("BuildingParts")

            -- Read from the dropdown selection
            local targetFile = fileDropdown.Value
            if not targetFile or targetFile == "" then targetFile = "build.txt" end

            if not isfile(targetFile) then 
                warn("❌ No build file found named: " .. targetFile)
                autoBuilderModule:Toggle() -- Turn module off if file fails
                return 
            end
            local buildData = HttpService:JSONDecode(readfile(targetFile))

            local function getTool(toolName, equip)
                local tool = char:FindFirstChild(toolName) or lp.Backpack:FindFirstChild(toolName)
                if tool then
                    if equip and tool.Parent ~= char then
                        tool.Parent = char 
                    elseif not equip and tool.Parent == char then
                        tool.Parent = lp.Backpack 
                    end
                end
                return tool
            end

            -- REWRITE: Equip NOTHING at the start
            local buildTool = getTool("BuildingTool", false)
            local scaleTool = getTool("ScalingTool", false)
            local paintTool = getTool("PaintingTool", false)
            local propTool = getTool("PropertiesTool", false)

            if not buildTool then 
                warn("❌ Missing Building Tool!") 
                autoBuilderModule:Toggle()
                return 
            end

            local buildRF = buildTool:WaitForChild("RF")
            local scaleRF = scaleTool and scaleTool:FindFirstChild("RF")
            local propRF = propTool and propTool:WaitForChild("SetPropertieRF")

            local t = tostring(lp.Team)
            local plotName = "WhiteZone"
            if t=="red" then plotName="Really redZone" elseif t=="blue" then plotName="Really blueZone" elseif t=="black" then plotName="BlackZone" elseif t=="yellow" then plotName="New YellerZone" elseif t=="magenta" then plotName="MagentaZone" elseif t=="green" then plotName="CamoZone" end
            local plotZone = workspace:WaitForChild(plotName)
            local playerBlocksFolder = workspace:WaitForChild("Blocks"):WaitForChild(lp.Name)

            pcall(function() workspace:WaitForChild("InstaLoadFunction", 1):InvokeServer() end)

            -- Fetch speed from UI Slider
            local spawningPartsPerSecond = speedSlider.Value
            local spawnDelayRate = 1 / spawningPartsPerSecond
            local spawnBatchSize = math.max(1, math.ceil(0.015 / spawnDelayRate))

            local paintArgs = {}
            local propBatches = {
                Unanchor = {}, Uncollide = {}, NoShadow = {},
                Transparency = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }, 
                Toggles = { Aim = {}, ReverseSpin = {} },
                Values = {
                    ["Delay time"] = {}, ["Piston speed"] = {}, ["Piston length"] = {},
                    ["Target length"] = {}, ["Max length"] = {}, ["Min length"] = {},
                    ["Stiffness"] = {}, ["Damping"] = {}, ["Length"] = {}, ["Angle limit"] = {}
                },
                WheelSpeed = {}, WheelTorque = {}
            }

            local threadsCompleted, totalExpected = 0, #buildData

            local function getCount(name)
                local d = dataFolder:FindFirstChild(name)
                return (d and d:IsA("IntValue")) and d.Value or 0
            end

            local function checkIsScalable(name)
                local noScale = {"Seat","Chair","Motor","Wheel","Hinge","Glue","Portal","Thruster","Bread","Sign","Camera","Piston","Harpoon","Magnet","Balloon","Cannon","Switch","Button","Lever","Spring","Suspension","Servo","Chest","Firework","Jetpack","Shield","Wedge"}
                for _, word in ipairs(noScale) do if string.find(name, word) then return false end end
                return string.find(name, "Block") ~= nil
            end

            local unprocessedBlocks = {}
            local processedBlocks = {}

            -- Hook cleanup into Vape module so it disconnects if toggled off
            local blockAddedConn = playerBlocksFolder.ChildAdded:Connect(function(b)
                if not processedBlocks[b] then
                    if not unprocessedBlocks[b.Name] then unprocessedBlocks[b.Name] = {} end
                    table.insert(unprocessedBlocks[b.Name], b)
                end
            end)
            autoBuilderModule:Clean(blockAddedConn)

            for _, b in ipairs(playerBlocksFolder:GetChildren()) do
                if not unprocessedBlocks[b.Name] then unprocessedBlocks[b.Name] = {} end
                table.insert(unprocessedBlocks[b.Name], b)
            end

            print(string.format("🚀 Initiating INSANE LOAD for %d items using file: %s", totalExpected, targetFile))

            for i, data in ipairs(buildData) do
                if not autoBuilderModule.Enabled then break end -- Stop loop if module is toggled off

                local savedRelativeCFrame = CFrame.new(unpack(data.CFrame))
                local absoluteTargetCFrame = plotZone.CFrame:ToWorldSpace(savedRelativeCFrame)
                
                local targetSize = Vector3.new(unpack(data.Size))
                local targetColor = Color3.new(unpack(data.Color))
                local blockType, props = data.Type, data.Props
                local isScalable = checkIsScalable(blockType)
                
                task.spawn(function()
                    local amt = getCount(blockType)
                    if amt > 0 then
                        buildRF:InvokeServer(blockType, amt, plotZone, savedRelativeCFrame, true, absoluteTargetCFrame, false)
                        
                        local spawnedBlock = nil
                        for attempt = 1, 15 do 
                            local list = unprocessedBlocks[blockType]
                            if list and #list > 0 then
                                for idx, b in ipairs(list) do
                                    if b.Parent and (b:GetPivot().Position - absoluteTargetCFrame.Position).Magnitude < 10 then
                                        spawnedBlock = b
                                        processedBlocks[b] = true
                                        table.remove(list, idx)
                                        break
                                    end
                                end
                            end
                            if spawnedBlock then break end
                            task.wait() 
                        end
                        
                        if spawnedBlock then
                            -- Validate with Scale Toggle Check
                            if isScalable and scaleRF and useScaleToggle.Enabled then 
                                task.spawn(function() scaleRF:InvokeServer(spawnedBlock, targetSize, absoluteTargetCFrame) end)
                            end
                            
                            -- Validate with Paint Toggle Check
                            if usePaintToggle.Enabled then
                                local defColor = Color3.new(1,1,1)
                                local template = buildingParts:FindFirstChild(blockType)
                                if template then
                                    local p = template:IsA("BasePart") and template or template:FindFirstChildWhichIsA("BasePart", true)
                                    if p then defColor = p.Color end
                                end
                                if math.abs(targetColor.R - defColor.R) > 0.01 or math.abs(targetColor.G - defColor.G) > 0.01 or math.abs(targetColor.B - defColor.B) > 0.01 then
                                    table.insert(paintArgs, {spawnedBlock, targetColor})
                                end
                            end
                            
                            -- Property Checks
                            if usePropToggle.Enabled then
                                if props.Anc == false then table.insert(propBatches.Unanchor, spawnedBlock) end
                                if props.Col == false then table.insert(propBatches.Uncollide, spawnedBlock) end
                                if props.CS == false then table.insert(propBatches.NoShadow, spawnedBlock) end
                                
                                if props.Tr and props.Tr > 0 then
                                    local steps = math.floor((props.Tr / 0.25) + 0.5)
                                    if steps > 0 and steps <= 4 then table.insert(propBatches.Transparency[steps], spawnedBlock) end
                                end
                                
                                local function addVal(cat, val)
                                    if val then
                                        propBatches.Values[cat][val] = propBatches.Values[cat][val] or {}
                                        table.insert(propBatches.Values[cat][val], spawnedBlock)
                                    end
                                end
                                
                                addVal("Delay time", props.Delay)
                                addVal("Piston speed", props.PistonSpeed)
                                addVal("Piston length", props.PistonLength)
                                addVal("Target length", props.SpringTarget)
                                addVal("Max length", props.SpringMax)
                                addVal("Min length", props.SpringMin)
                                addVal("Stiffness", props.SpringStiff)
                                addVal("Damping", props.SpringDamp)
                                addVal("Length", props.RodLength or props.RopeLength)
                                addVal("Angle limit", props.RodAngle)
                                
                                if props.Aim == false then table.insert(propBatches.Toggles.Aim, spawnedBlock) end
                                if props.ReverseSpin == true then table.insert(propBatches.Toggles.ReverseSpin, spawnedBlock) end
                                if props.WheelSpeed and props.WheelSpeed ~= 40 then table.insert(propBatches.WheelSpeed, {spawnedBlock, props.WheelSpeed}) end
                                if props.WheelTorque and props.WheelTorque ~= 1000000 then table.insert(propBatches.WheelTorque, {spawnedBlock, props.WheelTorque}) end
                            end
                        end
                    end
                    threadsCompleted = threadsCompleted + 1
                end)
                
                if spawnDelayRate >= 0.015 then
                    task.wait(spawnDelayRate)
                else
                    if i % spawnBatchSize == 0 then
                        task.wait()
                    end
                end
            end

            print("⏳ Waiting for spawning threads to finish...")
            while threadsCompleted < totalExpected and autoBuilderModule.Enabled do task.wait() end

            if not autoBuilderModule.Enabled then return end

            print("⚙️ Blasting Physics & Mechanics Instantly...")

            -- REWRITE: Equip Property Tool EXCLUSIVELY at this specific moment
            if usePropToggle.Enabled and propTool then
                getTool("PropertiesTool", true)
            end

            local function fireProp(cat, batch, val)
                if #batch > 0 and usePropToggle.Enabled and propRF then 
                    task.spawn(function() propRF:InvokeServer(cat, batch, val) end) 
                end
            end

            fireProp("Anchored", propBatches.Unanchor)
            fireProp("Collision", propBatches.Uncollide)
            fireProp("Cast shadow", propBatches.NoShadow)
            fireProp("Aim", propBatches.Toggles.Aim)
            fireProp("Reverse spin", propBatches.Toggles.ReverseSpin)

            for step = 1, 4 do
                local transBatch = {}
                for targetStep = step, 4 do
                    for _, b in ipairs(propBatches.Transparency[targetStep]) do table.insert(transBatch, b) end
                end
                fireProp("Transparency", transBatch)
            end

            for category, valueGroups in pairs(propBatches.Values) do
                for value, blockArray in pairs(valueGroups) do 
                    fireProp(category, blockArray, value) 
                end
            end

            if #propBatches.WheelSpeed > 0 and usePropToggle.Enabled and propRF then
                local speedMap = {[40]=0, [30]=1, [20]=2, [10]=3, [5]=4, [4]=5, [3]=6, [2]=7, [1]=8, [0.5]=9, [50]=10}
                for _, data in ipairs(propBatches.WheelSpeed) do
                    local block, targetSpeed = data[1], data[2]
                    local fires = speedMap[targetSpeed] or 0
                    for _ = 1, fires do task.spawn(function() propRF:InvokeServer("Wheel speed", {block}) end) end
                end
            end

            if #propBatches.WheelTorque > 0 and usePropToggle.Enabled and propRF then
                for _, data in ipairs(propBatches.WheelTorque) do
                    local block, targetTorque = data[1], data[2]
                    local fires = 0
                    if targetTorque == 10000000 then fires = 1 elseif targetTorque == 100000000 then fires = 2 elseif targetTorque == 1000000000 then fires = 3 elseif targetTorque == 10000000000 then fires = 4 end
                    for _ = 1, fires do task.spawn(function() propRF:InvokeServer("Wheel torque", {block}) end) end
                end
            end

            if paintTool and #paintArgs > 0 and usePaintToggle.Enabled then
                task.spawn(function()
                    paintTool:WaitForChild("RF"):InvokeServer(paintArgs)
                end)
            end

            print("✅ All requests fired!")
            -- Turn off module when done
            autoBuilderModule:Toggle()
        end)
    end
})

-- 3. Add Component UI Settings

fileDropdown = autoBuilderModule:CreateDropdown({
    Name = 'Build File',
    List = getBuildFiles(),
    Function = function(val) print('Selected File: ' .. val) end,
    Tooltip = 'Select the workspace file to load.'
})

refreshButton = autoBuilderModule:CreateButton({
    Name = 'Refresh File List',
    Function = function() 
        -- Vape API doesn't have a native list-refresh method, but we can try to re-assign or inform the user
        local newFiles = getBuildFiles()
        fileDropdown.List = newFiles 
        print("Files Refreshed. Check Dropdown again!")
    end
})

speedSlider = autoBuilderModule:CreateSlider({
    Name = 'Spawn Speed',
    Min = 100,
    Max = 1000,
    Default = 250,
    Function = function(val) print('Set Spawn Speed: ' .. val) end,
    Tooltip = 'How fast the blocks spawn in.'
})

-- Individual Tool Toggles (Replaces dropdown as it handles multi-state validation perfectly)
useScaleToggle = autoBuilderModule:CreateToggle({
    Name = 'Use Scale Tool',
    Default = true,
    Function = function(val) end,
    Tooltip = 'If disabled, blocks will not be scaled to their correct sizes.'
})

usePaintToggle = autoBuilderModule:CreateToggle({
    Name = 'Use Paint Tool',
    Default = true,
    Function = function(val) end,
    Tooltip = 'If disabled, blocks will spawn in default colors and skip painting.'
})

usePropToggle = autoBuilderModule:CreateToggle({
    Name = 'Use Property Tool',
    Default = true,
    Function = function(val) end,
    Tooltip = 'If disabled, physics and block property mechanics will not be applied.'
})
              
