#!/bin/bash

#/Applications/Aseprite.app/Contents/MacOS/aseprite -b ./res_workbench/art/art.ase --script ./tools/export_all_layers.lua

#'/Applications/FMOD Studio.app/Contents/MacOS/fmodstudio' -build ./res_workbench/audio/noct_01/noct_01.fspro

mkdir -p bin  bin/res/fonts #bin/res/audio

#/Users/davey/Tools/Odin/odin build tools/asset_processor.odin -file -debug -use-separate-modules -o:none -out:tools/asset_processor
#./tools/asset_processor

#cp res_workbench/audio/noct_01/Build/Desktop/*.bank bin/res/audio/
#cp res_workbench/fmod/*.dylib bin/
#cp res_workbench/fonts/*.ttf bin/res/fonts/

#COMMIT_HASH=$(git rev-parse --short HEAD)
#echo $COMMIT_HASH > commit_hash.txt

/Users/davey/Tools/Odin/odin build src -debug -o:none -out:bin/game.bin -use-separate-modules -define:PROFILE_ENABLE=true -vet