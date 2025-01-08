# Odin 2D Game Framework

A 2D "game" framework written in Odin, leveraging DirectX 11 for rendering and Win32 for window management.
It is designed to be a simple starting point for my future projects.

Currently you can only draw coloured rects to the screen. This is done through a big ass vertex buffer and single shader.

## Features

- 2D rendering using DirectX 11
- Native Window using Win32 API
- Entirely self contained API because I wanted to avoid splitting up the game from the rendering/platform

## TODO
- Build step to export aseprite layers
- Build step to generate a texture atlas from said layers and info for said atlas
- Draw texture to quad
- Metal/Mac support

## Thanks To
- Ginger Bill for Odin
- Karl for rectangle code because I am lazy
- [Cody Duncan](https://gist.github.com/Cody-Duncan/d85740563ceea99f6619 "for a cool way to generate a d3d11 input layout")