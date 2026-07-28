rm -rf /home/pigu/.var/app/cc.craftos_pc.CraftOS-PC/data/craftos-pc/computer/4/*
cp ./* -r /home/pigu/.var/app/cc.craftos_pc.CraftOS-PC/data/craftos-pc/computer/4/
flatpak run cc.craftos_pc.CraftOS-PC --id 4 --exec "shell.run(\"clear\");shell.run(\"demo.lua\")"