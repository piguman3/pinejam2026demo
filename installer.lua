local function downloadfile(name)
    local absPath = shell.resolve(name)

    print("Downloading " .. name .. "...")

    local request = http.get("https://github.com/piguman3/pinejam2026demo/raw/refs/heads/main/" .. name)
    local newContents = request.readAll()
    request.close()

    local f = fs.open(absPath, "wb")
    f.write(newContents)
    f.close()
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