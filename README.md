# Studio Graphite Console

A graphite-and-teal theme built on REAPER 7’s Default theme, with color-coded track folders and configurable transport buttons.

## Install

1. Copy the **Studio Graphite Console ReaPack URL** below and paste it into **Extensions → ReaPack → Import repositories**. [Get ReaPack](https://reapack.com/)

   ```text
   https://raw.githubusercontent.com/davvolinni-ui/RPS-Theme/main/index.xml
   ```

2. Open **ReaPack → Browse packages**. Mark **Studio Graphite Console** for installation and click **Apply**. This installs the theme and its companion scripts.
3. Install the fonts and any add-ons you want from the lists below. Restart REAPER and select **Options → Themes → Studio Graphite Console**.

Update from **ReaPack → Synchronize packages**. For portable REAPER, install from inside that copy.

## Fonts

Download these two ZIPs and install the listed desktop fonts.

| Install | Download |
| --- | --- |
| **Roboto Condensed Regular and Medium** from `hinted/static` | [Roboto Condensed ZIP](https://github.com/googlefonts/roboto-3-classic/releases/download/v3.005/Roboto_v3.005.zip) |
| **Inter SemiBold** from `extras/ttf`. Add Regular and Medium if your REAPER build does not already supply them. | [Inter ZIP](https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip) |

## Features

- **Folder Annex** draws color-tinted outlines alongside tracks and beneath mixer channels so you can follow nested folders. Toggle the track panel and mixer annexes independently. [Restore their state at startup](#restore-the-annexes-at-startup)
- **RPS transport buttons** open or focus your installed production apps. Each app installs separately. [ReaBrowse](https://forum.cockos.com/showthread.php?t=310757) · [ReaDrumXT](https://forum.cockos.com/showthread.php?t=310870) · [ReaRoll](https://forum.cockos.com/showthread.php?t=311021) · [ReaSpect](https://forum.cockos.com/showthread.php?t=311132)
- **iQ** applies the current project grid to MIDI input quantize across all tracks. Click again after changing the grid or adding tracks. Use **Shift-click** or **Turn iQ off** in Settings to restore the previous track settings.
- **Docker buttons** toggle the left, bottom, and right dockers. The buttons have their own far-left or far-right placement. Enable **Align Gridbox with iQ** in Settings to place FTC Gridbox beside iQ.

Open **Settings** beside the transport, or run **Studio Graphite Console - Transport Buttons** from the Actions list. Place RPS buttons next to the transport or at either far edge. Place iQ with the main controls or on either side.

In **Advanced**, use **Default** for the detected action, **Native** where available, or **Custom** to enter a Main Action List command ID. **Appearance** controls arrange gridline brightness, base meter color, and meter interlacing.

## Optional add-ons

| Feature | Install |
| --- | --- |
| Transport Buttons settings | [ReaImGui 0.10+](https://github.com/ReaTeam/Extensions/blob/master/API/reaper_imgui.ext) |
| Both Folder Annexes, FTC dockers and Gridbox, RPS window focus, or Shift-click iQ | [js_ReaScriptAPI](https://github.com/ReaTeam/Extensions/blob/master/API/js_ReaScriptAPI.ext) |
| Mixer Folder Annex or docked Mixer focus | [SWS/S&M Extension](https://sws-extension.org/) |

Find these extensions in **ReaPack → Browse packages**. [ReaTeam Extensions index](https://raw.githubusercontent.com/ReaTeam/Extensions/master/index.xml)

For the FTC controls, import **FTC Tools** in ReaPack. [FTC Tools index](https://raw.githubusercontent.com/iliaspoulakis/Reaper-Tools/master/index.xml)

- **Dockers** — install [Toggle show left docker](https://github.com/iliaspoulakis/Reaper-Tools/blob/master/Dockers/Toggle%20show%20left%20docker.lua), [Toggle show bottom docker](https://github.com/iliaspoulakis/Reaper-Tools/blob/master/Dockers/Toggle%20show%20bottom%20docker.lua), and [Toggle show right docker](https://github.com/iliaspoulakis/Reaper-Tools/blob/master/Dockers/Toggle%20show%20right%20docker.lua).
- **Gridbox** — install [Gridbox](https://github.com/iliaspoulakis/Reaper-Tools/blob/master/Adaptive%20grid/Gridbox.lua) and [Adaptive Grid](https://github.com/iliaspoulakis/Reaper-Tools/blob/master/Adaptive%20grid/Adaptive%20grid.lua). Open Gridbox from the Actions list before aligning it.

## Restore the annexes at startup

Open **Options → Show REAPER resource path**, then add this block to `Scripts/__startup.lua`. Create the file if needed. The hook restores each annex’s last on/off choice when REAPER starts with this theme.

```lua
do
  local folder = reaper.GetResourcePath() .. "/Scripts/Studio Graphite Console/RPS Transport/"
  local transport = loadfile(folder .. "Studio Graphite Console - Transport Buttons.lua")
  if transport then transport("startup") end
end
```

## Full REAPER 7 Theme Adjuster

Open **Options → Themes → Theme adjuster/Color controls**. If the basic panel opens, choose **Debugging → Attempt to use the Default 7.0 theme’s controls** and confirm.

## Credits

Based on Cockos’ REAPER 7 Default theme. The original WALTER notices are in the theme archive. Thanks to White Tie for the Folder Annex inspiration and to FeedTheCat for Gridbox and the docker actions. [LGPL 2.1](LICENSE-WALTER) · [White Tie’s Graphical Annex](https://www.houseofwhitetie.com/graphical_annex.html)
