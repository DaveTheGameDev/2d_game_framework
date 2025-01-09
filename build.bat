@echo off

aseprite -b ./res/img/art.ase --script ./tools/export_all_layers.lua
odin run tools/asset_processor.odin -file