local function downloadfile(name)
    shell.run("wget https://github.com/piguman3/PineJam2026Demo/raw/refs/heads/main/" .. name)
end

print("Downloading files!")
downloadfile("demo.lua")
downloadfile("janecut.dfpwm")
downloadfile("betterblittle.lua")
downloadfile("anim.bin")
downloadfile("Pine3D.lua")

print("Would you like to run the demo now? (y/n)")
local answer = read()

if answer:sub(1, 1):lower() == "y" then
    shell.run("demo.lua")
else
    print("You can run demo.lua to start the demo!")
end