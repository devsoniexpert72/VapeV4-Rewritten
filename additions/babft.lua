run(function()
    -- 1. Create the custom Category
    local babftCategory = vape:CreateCategory({
        Name = 'BABFT Tools',
        Icon = 'rbxassetid://0', 
        Size = UDim2.fromOffset(16, 16)
    })

    -- UI Component Variables
    local autoBuilderModule
    local previewBuilderModule
    local fileDropdown
    local refreshButton
    local speedSlider
    local useScaleToggle
    local usePaintToggle
    local usePropToggle

    -- Offset Sliders for Preview & Building
    local offX, offY, offZ
    local rotX, rotY, rotZ

    -- Preview Globals
    local previewFolderName = "Blueprint_Preview"
    local previewFolder = workspace:FindFirstChild(previewFolderName) or Instance.new("Folder")
    previewFolder.Name = previewFolderName
    previewFolder.Parent = workspace
    local previewParts = {} -- Stores { part = Instance, baseCF = CFrame }

    -- Utility: Vape Notification Wrapper
    local function notify(title, text, duration, typeTheme)
        if vape and vape.CreateNotification then
            vape:CreateNotification(title, text, duration or 5, typeTheme or 'info')
        end
    end

    -- Utility: Fetch Files
    local function getBuildFiles()
        local files = {}
        local suc, res = pcall(function() return listfiles("") end)
        if suc and res then
            for _, f in ipairs(res) do
                if f:lower():match("%.build$") or f:lower():match("%.txt$") then
                    table.insert(files, f:match("([^/%\\]+)$"))
                end
            end
        end
        if #files == 0 then table.insert(files, "build.txt") end
        return files
    end

    -- =========================================================================
    -- MODULE 1: PREVIEW BUILDER
    -- =========================================================================

    local function updatePreview()
        if not previewBuilderModule.Enabled then return end
        
        local plotName = "WhiteZone"
        local t = tostring(game:GetService("Players").LocalPlayer.Team)
        if t=="red" then plotName="Really redZone" elseif t=="blue" then plotName="Really blueZone" elseif t=="black" then plotName="BlackZone" elseif t=="yellow" then plotName="New YellerZone" elseif t=="magenta" then plotName="MagentaZone" elseif t=="green" then plotName="CamoZone" end
        local plotZone = workspace:FindFirstChild(plotName)
        if not plotZone then return end

        -- Apply Sliders to offset
        local buildOffset = CFrame.new(offX.Value, offY.Value, offZ.Value) * CFrame.Angles(math.rad(rotX.Value), math.rad(rotY.Value), math.rad(rotZ.Value))
        
        for _, pData in ipairs(previewParts) do
            if pData.part and pData.part.Parent then
                local absoluteTargetCFrame = plotZone.CFrame:ToWorldSpace(buildOffset * pData.baseCF)
                if pData.part:IsA("Model") then
                    pData.part:PivotTo(absoluteTargetCFrame)
                else
                    pData.part.CFrame = absoluteTargetCFrame
                end
            end
        end
    end

    local function triggerUpdate()
        if previewBuilderModule.Enabled then updatePreview() end
    end

    previewBuilderModule = vape.Categories['BABFT Tools']:CreateModule({
        Name = 'Preview Builder',
        Tooltip = 'Shows a hologram of your build. Adjust offsets before loading.',
        Function = function(callback)
            if callback then
                local HttpService = game:GetService("HttpService")
                local targetFile = fileDropdown.Value
                if not targetFile or targetFile == "" then targetFile = "build.txt" end

                if not isfile(targetFile) then 
                    notify('Preview Error', 'Could not find file: ' .. targetFile, 5, 'alert')
                    previewBuilderModule:Toggle()
                    return 
                end
                
                local suc, buildData = pcall(function() return HttpService:JSONDecode(readfile(targetFile)) end)
                if not suc then 
                    notify('Preview Error', 'Failed to decode JSON data.', 5, 'alert')
                    previewBuilderModule:Toggle()
                    return 
                end

                previewFolder:ClearAllChildren()
                table.clear(previewParts)

                local buildingParts = game:GetService("ReplicatedStorage"):WaitForChild("BuildingParts")
                local totalBlocks = 0
                
                for i, data in ipairs(buildData) do
                    local template = buildingParts:FindFirstChild(data.Type)
                    if template then
                        local ghost = template:Clone()
                        
                        -- Strip scripts
                        for _, s in ipairs(ghost:GetDescendants()) do 
                            if s:IsA("LuaSourceContainer") then s:Destroy() end 
                        end

                        -- Force Visual Hologram Properties
                        local function setVisuals(part)
                            if part:IsA("BasePart") then
                                part.Anchored = true
                                part.CanCollide = false
                                part.Transparency = 0.6
                                if data.Color then part.Color = Color3.new(unpack(data.Color)) end
                                if data.Size then part.Size = Vector3.new(unpack(data.Size)) end
                            end
                        end
                        
                        setVisuals(ghost)
                        for _, child in ipairs(ghost:GetDescendants()) do setVisuals(child) end

                        ghost.Name = "Preview_" .. data.Type
                        ghost.Parent = previewFolder
                        
                        table.insert(previewParts, {
                            part = ghost,
                            baseCF = CFrame.new(unpack(data.CFrame))
                        })
                        totalBlocks = totalBlocks + 1
                    end
                end
                
                notify('Preview Loaded', 'Rendered ' .. totalBlocks .. ' blueprint parts.', 5, 'info')
                updatePreview()
            else
                previewFolder:ClearAllChildren()
                table.clear(previewParts)
            end
        end
    })

    offX = previewBuilderModule:CreateSlider({ Name = 'Offset X', Min = -500, Max = 500, Default = 0, Function = triggerUpdate })
    offY = previewBuilderModule:CreateSlider({ Name = 'Offset Y', Min = -500, Max = 500, Default = 0, Function = triggerUpdate })
    offZ = previewBuilderModule:CreateSlider({ Name = 'Offset Z', Min = -500, Max = 500, Default = 0, Function = triggerUpdate })
    rotX = previewBuilderModule:CreateSlider({ Name = 'Rotate X', Min = -180, Max = 180, Default = 0, Function = triggerUpdate })
    rotY = previewBuilderModule:CreateSlider({ Name = 'Rotate Y', Min = -180, Max = 180, Default = 0, Function = triggerUpdate })
    rotZ = previewBuilderModule:CreateSlider({ Name = 'Rotate Z', Min = -180, Max = 180, Default = 0, Function = triggerUpdate })


    -- =========================================================================
    -- MODULE 2: AUTO BUILDER
    -- =========================================================================

    autoBuilderModule = vape.Categories['BABFT Tools']:CreateModule({
        Name = 'AutoBuilder',
        Tooltip = 'Automatically loads and builds your BABFT structures.',
        Function = function(callback)
            if not callback then return end
            
            task.spawn(function()
                local HttpService = game:GetService("HttpService")
                local repStorage = game:GetService("ReplicatedStorage")
                local lp = game:GetService("Players").LocalPlayer
                local char = lp.Character or lp.CharacterAdded:Wait()
                local dataFolder = lp:WaitForChild("Data")
                local buildingParts = repStorage:WaitForChild("BuildingParts")

                local targetFile = fileDropdown.Value
                if not targetFile or targetFile == "" then targetFile = "build.txt" end

                if not isfile(targetFile) then 
                    notify('AutoBuilder', 'No build file found named: ' .. targetFile, 5, 'alert')
                    autoBuilderModule:Toggle()
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

                -- Ensure absolutely nothing is equipped to start
                local buildTool = getTool("BuildingTool", false)
                local scaleTool = getTool("ScalingTool", false)
                local paintTool = getTool("PaintingTool", false)
                local propTool = getTool("PropertiesTool", false)

                if not buildTool then 
                    notify('AutoBuilder', 'Missing Building Tool! Check your inventory.', 5, 'alert')
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

                local function getCount(name)
                    local d = dataFolder:FindFirstChild(name)
                    return (d and d:IsA("IntValue")) and d.Value or 0
                end

                -- INVENTORY CHECK logic
                local requiredBlocks = {}
                for _, data in ipairs(buildData) do
                    requiredBlocks[data.Type] = (requiredBlocks[data.Type] or 0) + 1
                end
                
                local missingMsg = {}
                for bType, reqAmt in pairs(requiredBlocks) do
                    local hasAmt = getCount(bType)
                    if hasAmt < reqAmt then
                        table.insert(missingMsg, (reqAmt - hasAmt) .. "x " .. bType)
                    end
                end
                
                if #missingMsg > 0 then
                    notify('Missing Blocks', 'Missing: ' .. table.concat(missingMsg, ", "), 10, 'warning')
                end

                pcall(function() workspace:WaitForChild("InstaLoadFunction", 1):InvokeServer() end)

                notify('AutoBuilder', 'Placing blocks from ' .. targetFile, 5, 'info')

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

                local function checkIsScalable(name)
                    local noScale = {"Seat","Chair","Motor","Wheel","Hinge","Glue","Portal","Thruster","Bread","Sign","Camera","Piston","Harpoon","Magnet","Balloon","Cannon","Switch","Button","Lever","Spring","Suspension","Servo","Chest","Firework","Jetpack","Shield","Wedge"}
                    for _, word in ipairs(noScale) do if string.find(name, word) then return false end end
                    return string.find(name, "Block") ~= nil
                end

                local unprocessedBlocks = {}
                local processedBlocks = {}

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

                -- Capture the exact offset configuration from the preview module sliders
                local rotXC, rotYC, rotZC = rotX.Value, rotY.Value, rotZ.Value
                local offXC, offYC, offZC = offX.Value, offY.Value, offZ.Value
                local buildOffset = CFrame.new(offXC, offYC, offZC) * CFrame.Angles(math.rad(rotXC), math.rad(rotYC), math.rad(rotZC))

                for i, data in ipairs(buildData) do
                    if not autoBuilderModule.Enabled then break end

                    -- Coordinate Calculation System using Offset CFrames
                    local savedRelativeCFrame = buildOffset * CFrame.new(unpack(data.CFrame))
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
                                if isScalable and scaleRF and useScaleToggle.Enabled then 
                                    task.spawn(function() scaleRF:InvokeServer(spawnedBlock, targetSize, absoluteTargetCFrame) end)
                                end
                                
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

                while threadsCompleted < totalExpected and autoBuilderModule.Enabled do task.wait() end
                if not autoBuilderModule.Enabled then return end

                -- Equip the Property Tool EXCLUSIVELY for mechanics applying
                if usePropToggle.Enabled and propTool then
                    notify('AutoBuilder', 'Applying physical properties...', 5, 'info')
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
                
                -- Re-unequip after property applications
                if usePropToggle.Enabled and propTool then
                    getTool("PropertiesTool", false) 
                end

                if paintTool and #paintArgs > 0 and usePaintToggle.Enabled then
                    notify('AutoBuilder', 'Painting loaded structures...', 5, 'info')
                    task.spawn(function()
                        paintTool:WaitForChild("RF"):InvokeServer(paintArgs)
                    end)
                end

                notify('AutoBuilder', '✅ Build Complete!', 5, 'info')
                autoBuilderModule:Toggle()
            end)
        end
    })

    -- Component Attachments
    fileDropdown = autoBuilderModule:CreateDropdown({
        Name = 'Build File',
        List = getBuildFiles(),
        Function = function(val) 
            notify('File Selected', 'Target Build File changed to: ' .. val, 3, 'info')
        end,
        Tooltip = 'Select the workspace file to load.'
    })

    refreshButton = autoBuilderModule:CreateButton({
        Name = 'Refresh File List',
        Function = function() 
            fileDropdown:Change(getBuildFiles())
            notify('Refreshed', 'Workspace files refreshed successfully!', 3, 'info')
        end
    })

    speedSlider = autoBuilderModule:CreateSlider({
        Name = 'Spawn Speed',
        Min = 100,
        Max = 1000,
        Default = 250,
        Function = function(val) end,
        Tooltip = 'How fast the blocks spawn in.'
    })

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
end)
