local Pine3D = require("Pine3D")

--[[
    Things left to do: (that i can think of now)

    - [X] Scaling
    - [X] Frame interpolation (with easing!)
    - [X] Better text support in the python script
    - [X] Hide objects
    - [X] Export camera movement
    - [X] Timing, figure that out (seems fine? might look into this later again though.)
    - [X] Animation data block

    - [X] THE ACTUAL ANIMATION!!
        - [X] Grease pencil storyboard main actions + effects
        - [X] Main animation

    - [ ] In-game seems a little slow and off sync with the music
    - [X] Aspect ratios (aka, make sure the animation looks correct on all monitors)
    - [X] License + README
    - [X] Pinejam post + Installer

    proper rotation is ZYX, i think

]]--

local musicReady = false
local graphicsReady = false

local actions = {
    [1] = function(file, output) -- Create Model (u8 color, u16 tricount, [f32 tri.v1.x, f32 tri.v1.y, ...])
        local model = {}
        local color = 2^string.byte(file.read(1))
        local tricount = string.unpack(">I2", file.read(2))

        for x=1,tricount do
            local tri = {}

            tri.x1 = string.unpack(">f", file.read(4))
            tri.y1 = string.unpack(">f", file.read(4))
            tri.z1 = string.unpack(">f", file.read(4))

            tri.x2 = string.unpack(">f", file.read(4))
            tri.y2 = string.unpack(">f", file.read(4))
            tri.z2 = string.unpack(">f", file.read(4))

            tri.x3 = string.unpack(">f", file.read(4))
            tri.y3 = string.unpack(">f", file.read(4))
            tri.z3 = string.unpack(">f", file.read(4))

            tri.c = color
            tri.forceRender = true

            model[x] = tri
        end

        table.insert(output.models, model)
        output.keyframes[#output.models] = {}
    end,
    [2] = function(file, output) -- Add list of keyframes (u8 model_id, u8 channel, u16 keyframecount, [u16 frame_number, f32 value, ...])
        local modelID = string.byte(file.read(1))
        local channel = string.byte(file.read(1)) -- 0:location, 1:rotation, 2:scale, 3:hide_render (times 3)

        local count = string.unpack(">I2", file.read(2))

        for x=1,count do
            local framenum = string.unpack(">I2", file.read(2))
            local value = string.unpack(">f", file.read(4))

            if output.keyframes[modelID][framenum]==nil then
                output.keyframes[modelID][framenum] = {}
            end
            
            local keyframe = output.keyframes[modelID][framenum]
            keyframe[channel] = value
        end
    end,
    [3] = function(file, output) -- Add list of camera keyframes (u8 channel, u16 keyframecount, [u16 frame_number, f32 value, ...])
        -- Yes, this is repeated code. I don't know man.
        local modelID = -1
        if output.keyframes[modelID]==nil then
            output.keyframes[modelID] = {}
        end
        local channel = string.byte(file.read(1)) -- 0:location, 1:rotation, 2:fov in degrees (times 3)

        local count = string.unpack(">I2", file.read(2))

        for x=1,count do
            local framenum = string.unpack(">I2", file.read(2))
            local value = string.unpack(">f", file.read(4))

            if output.keyframes[modelID][framenum]==nil then
                output.keyframes[modelID][framenum] = {}
            end
            
            local keyframe = output.keyframes[modelID][framenum]
            keyframe[channel] = value
        end
    end,
    [4] = function(file, output) -- Global animation data block (u16 frame_start, u16 frame_end)
        output.frameStart = string.unpack(">I2", file.read(2))
        output.frameEnd = string.unpack(">I2", file.read(2))
    end
}

local function parseBinary(filename)
    local file = fs.open(filename, "r")
    local output = { 
        models = {},
        keyframes = {}
    }

    while 1 do
        local actionType = file.read(1)
        if actionType == nil then
            break
        end
        
        actions[string.byte(actionType)](file, output)
    end

    file.close()

    return output
end

local function lerp(a, b, t) return a + (b - a) * t end

local function updateModelFrame(model, prevKeyframe, nextKeyframe, channel, lerpVal)
    local valuePrev = prevKeyframe[channel]
    local valueNext = nextKeyframe[channel]

    local valueLerp
    if valuePrev and valueNext then
        valueLerp = lerp(valuePrev, valueNext, lerpVal)
    end

    local type = math.floor(channel/3)
    local axis = channel%3

    if valueLerp and (model.visible) then
        if type==0 then -- Location
            model[channel+1] = valueLerp
        elseif type==1 then -- Rotation
            model[channel+1] = valueLerp
        elseif type==2 then -- Scale
            model[channel+4] = valueLerp
        end
    end
    if type==3 then -- Hide
        model.visible = valuePrev==0
    end
end

local function updateCameraFrame(ThreeDFrame, prevKeyframe, nextKeyframe, channel, lerpVal)
    local valuePrev = prevKeyframe[channel]
    local valueNext = nextKeyframe[channel]

    local valueLerp
    if valuePrev and valueNext then
        valueLerp = lerp(valuePrev, valueNext, lerpVal)

        local type = math.floor(channel/3)
        local axis = channel%3

        if type==0 then -- Location
            if axis==0 then
                ThreeDFrame:setCamera(valueLerp, nil, nil)
            elseif axis==1 then
                ThreeDFrame:setCamera(nil, valueLerp, nil)
            elseif axis==2 then
                ThreeDFrame:setCamera(nil, nil, valueLerp)
            end
        elseif type==1 then -- Rotation
            if axis==0 then
                ThreeDFrame:setCamera(nil, nil, nil, valueLerp, nil, nil)
            elseif axis==1 then
                ThreeDFrame:setCamera(nil, nil, nil, nil, valueLerp, nil)
            elseif axis==2 then
                ThreeDFrame:setCamera(nil, nil, nil, nil, nil, valueLerp)
            end
        elseif type==2 then -- FOV
            ThreeDFrame:setFoV(valueLerp)
        end
    end
end

local function easeInOutSine(x)
    return -(math.cos(math.pi * x) - 1) / 2;
end

local startTime

local function drawText(x, y, text)
    term.setCursorPos(x, y)
    term.write(text)
end

local function drawRect(ThreeDFrame, x1, y1, x2, y2, col)
    for x=x1,x2 do
        for y=y1, y2 do
            ThreeDFrame.buffer:setPixel(x, y, col)
        end
    end
end

local nameList = {"RedToast", "Sima", "koolaid", "JackMacWindows", "Xella", "Sammy", 
                  "autumn", "9551dev ", "Minki the Avali", "Shrekshellraiser", "Lemmmy", 
                  "Rose", "Wojbie", "Level_YZ", "King green", "AlexDevs", "tehgreatdoge", 
                  "Fatboychummy", "awesomehome7_dj", "umnikos", "and YOU!"}

local function graphics()
    local newcolors = {
        0xffffff,
        0xf2b233,
        0xe57fd8,
        0x99b2f2,
        0xf8d407,
        0x00ff00,
        0xf2b2cc,
        0x4c4c4c,
        0x999999,
        0x4c99b2,
        0xb266e5,
        0x3366cc,
        0x7f664c,
        0x57a64e,
        0xdd0000,
        0x000000
    }

    for x=0,15 do
        term.setPaletteColor(2^x, newcolors[x+1])
    end

    local ThreeDFrame = Pine3D.newFrame()
    ThreeDFrame:setBackgroundColor(colors.red)
    ThreeDFrame:setCamera(0, 0, -50, 0, 90, 0)
    ThreeDFrame:setFoV(10) -- Sort of ortographic

    local anim = parseBinary("anim.bin")

    local objects = {}
    for k,v in pairs(anim.models) do
        objects[k] = ThreeDFrame:newObject(v, 0, 0, 0, 0, 0, 0)
        objects[k].visible = false
    end

    graphicsReady = true
    repeat sleep() until musicReady
    if not startTime then
        startTime = os.epoch("utc")
    end
    while 1 do
        local currentFrame = math.floor((os.epoch("utc") - startTime) / 50) + anim.frameStart

        if currentFrame>anim.frameEnd then
            for x=0,15 do
                term.setPaletteColor(2^x, term.getNativeColor(2^x))
            end
            return
        end

        for modelID,keyframes in pairs(anim.keyframes) do
            for channel=9,0,-1 do
                local prevFrame = currentFrame
                while (keyframes[prevFrame]==nil) or (keyframes[prevFrame][channel]==nil) do -- Find keyframe on the left
                    if prevFrame<=0 then
                        prevFrame = 0
                        break
                    end
                    prevFrame = prevFrame - 1 
                end

                local nextFrame = currentFrame
                while (keyframes[nextFrame]==nil) or (keyframes[nextFrame][channel]==nil) do -- Find keyframe on the right
                    if nextFrame>=anim.frameEnd then
                        nextFrame = prevFrame
                        break
                    end
                    nextFrame = nextFrame + 1 
                end

                local lerpVal = 0
                if nextFrame~=prevFrame then
                    lerpVal = (currentFrame - prevFrame) / (nextFrame - prevFrame)
                end
                if modelID>0 then
                    updateModelFrame(objects[modelID], keyframes[prevFrame], keyframes[nextFrame], channel, easeInOutSine(lerpVal))
                else
                    updateCameraFrame(ThreeDFrame, keyframes[prevFrame], keyframes[nextFrame], channel, easeInOutSine(lerpVal))
                end
            end
        end

        local visibleobjects = {}
        local i = 0
        for k,v in pairs(objects) do
            if v.visible then
                i = i + 1
                visibleobjects[i] = objects[k]
            end
        end

        ThreeDFrame:drawObjects(visibleobjects)

        -- Black bars
        local width = ThreeDFrame.buffer.width
        local height = ThreeDFrame.buffer.height
        local ratio = 114 / 200
        drawRect(ThreeDFrame, 1, 1, ThreeDFrame.buffer.width, height/2 - width*ratio/2, colors.black)
        drawRect(ThreeDFrame, 1, height/2 + width*ratio/2+1, width, height+1, colors.black)

        ThreeDFrame:drawBuffer()

        if currentFrame>=646 then
            local width, height = term.getSize()

            width = math.min(width-2, 85) 

            drawText(3, 3, "Salutes to:")
            local wx = 3
            local wy = 5
            for k,v in pairs(nameList) do
                local str = v .. "  "

                if wx+#str>width then
                    wx = 3
                    wy = wy + 2
                end

                drawText(wx, wy, str)
                wx = wx + #str
            end

            term.setCursorPos(1, height)
            return
        end

        os.queueEvent("pen")
        os.pullEvent("pen")
    end
end

local function music()
    if periphemu then -- For CraftOS-PC users
        periphemu.create("bottom", "speaker")
    end

    local dfpwm = require("cc.audio.dfpwm")
    local speaker = peripheral.find("speaker")

    if not speaker then
        error("No speaker found")
    end

    local decoder = dfpwm.make_decoder()

    sleep(0.105)
    musicReady = true
    repeat sleep() until graphicsReady
    if not startTime then
        startTime = os.epoch("utc")
    end
    for chunk in io.lines("janecut.dfpwm", 16 * 1024) do
        local buffer = decoder(chunk)

        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

parallel.waitForAll(graphics, music)