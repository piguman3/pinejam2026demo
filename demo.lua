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

    - [ ] THE ACTUAL ANIMATION!!

    - [ ] Aspect ratios (aka, make sure the animation looks correct on all monitors)
    - [ ] License + README
    - [ ] Pinejam post + Installer

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
        output.keyframes[modelID] = {}
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

local function updateModelFrame(model, prevKeyframe, nextKeyframe, channel, lerpVal, isvisible)
    local valuePrev = prevKeyframe[channel]
    local valueNext = nextKeyframe[channel]

    local valueLerp
    if valuePrev and valueNext then
        valueLerp = lerp(valuePrev, valueNext, lerpVal)
    end

    local type = math.floor(channel/3)
    local axis = channel%3

    if type==0 then -- Location
        model[channel+1] = valueLerp
    elseif type==1 then -- Rotation
        model[channel+1] = valueLerp
    elseif type==2 then -- Scale
        model[channel+4] = valueLerp
    elseif type==3 then -- Hide
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
            ThreeDFrame.camera[channel+1] = valueLerp
        elseif type==1 then -- Rotation
            ThreeDFrame.camera[channel+1] = valueLerp
        elseif type==2 then -- FOV
            ThreeDFrame:setFoV(valueLerp)
        end
    end
end

local function easeInOutSine(x)
    return -(math.cos(math.pi * x) - 1) / 2;
end

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

    local startTime = os.epoch("utc")
    while 1 do
        local currentFrame = math.floor((os.epoch("utc") - startTime) / 50) + anim.frameStart

        if currentFrame>anim.frameEnd then
            for x=0,15 do
                term.setPaletteColor(2^x, term.getNativeColor(2^x))
            end
            return
        end

        for modelID,keyframes in pairs(anim.keyframes) do
            for channel=0,9 do
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
                    if nextFrame>=1000 then -- TODO: make this actually know what the last frame is
                        nextFrame = prevFrame
                        break
                    end
                    nextFrame = nextFrame + 1 
                end

                local lerpVal
                if nextFrame~=prevFrame then
                    lerpVal = (currentFrame - prevFrame) / (nextFrame - prevFrame)
                else
                    lerpVal = 0
                end
                if modelID>0 then
                    updateModelFrame(objects[modelID], keyframes[prevFrame], keyframes[nextFrame], channel, easeInOutSine(lerpVal))
                else
                    updateCameraFrame(ThreeDFrame, keyframes[prevFrame], keyframes[nextFrame], channel, easeInOutSine(lerpVal))
                end
            end
        end

        local visibleobjects = {}
        for k,v in pairs(objects) do
            if v.visible then
                visibleobjects[k] = objects[k]
            end
        end

        ThreeDFrame:drawObjects(visibleobjects)
        ThreeDFrame:drawBuffer()
        sleep()
    end
end

local function music()
    if periphemu then -- For CraftOS-PC users
        periphemu.create("right", "speaker")
    end

    local dfpwm = require("cc.audio.dfpwm")
    local speaker = peripheral.find("speaker")

    local decoder = dfpwm.make_decoder()

    local time = os.epoch("utc")
    local nextTime = math.ceil(time/1000) * 1000
    sleep((nextTime-time)/1000) -- Weird idea, not sure if it actually does anything
    musicReady = true
    repeat sleep() until graphicsReady
    for chunk in io.lines("janecut.dfpwm", 16 * 1024) do
        local buffer = decoder(chunk)

        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

parallel.waitForAll(graphics, music)