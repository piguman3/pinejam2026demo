local function downloadfile(name)
    shell.run("wget https://github.com/piguman3/PineJam2026Demo/raw/refs/heads/main/" .. name)
end

print("Downloading files!")
downloadfile("demo.lua")
downloadfile("janecut.dfpwm")
downloadfile("betterblittle.lua")
downloadfile("anim.bin")
downloadfile("Pine3D.lua")

term.clear()
term.setCursorPos(1, 1)
print("You can run demo.lua to start the demo!")