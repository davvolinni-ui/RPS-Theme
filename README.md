# Studio Graphite Console

Studio Graphite Console is a REAPER 7 theme with configurable transport buttons and folder controls for the track panel and mixer.

## Install with ReaPack

1. In the REAPER install where you want the theme, open **Extensions → ReaPack → Import repositories**. Paste this repository's raw `index.xml` URL. On GitHub, open `index.xml` and use **Raw** to get the URL. [Install ReaPack](https://reapack.com/) first if you do not see the menu.
2. Open **Extensions → ReaPack → Browse packages**. Mark **Studio Graphite Console** for installation. ReaPack installs the theme in `ColorThemes`, places its scripts and libraries together in `Scripts/Studio Graphite Console/RPS Transport`, and registers the button actions.
3. For the full transport and folder controls, also mark any missing packages below. All three are available in [ReaTeam Extensions](https://github.com/ReaTeam/Extensions).

   | Package | Used by |
   | --- | --- |
   | ReaImGui 0.10 or later | Transport Buttons settings |
   | js_ReaScriptAPI | Both Folder Annex buttons and focusing app windows |
   | SWS/S&M Extension | Mixer Folder Annex |

4. Click **Apply**. Restart REAPER if you installed an extension, then select **Options → Themes → Studio Graphite Console**.
5. Open the transport's **Settings** button to choose which buttons to show and how they launch. You can also open **Studio Graphite Console - Transport Buttons** from the Main Action List.

Repeat the ReaPack setup inside a portable install to use the package there. **Default** discovers ReaBrowse, ReaDrumXT, ReaSpect, and ReaRoll if you separately install them in that REAPER instance and register them in its Main Action List. **Native** is available for the browser and piano roll. Use **Custom** for another action in the Main Action List.

The RPS transport icons use fixed artwork. The Folder Annex keeps its overlay aligned while enabled.

## Fonts

Install [Roboto Condensed Regular and Medium](https://fonts.google.com/specimen/Roboto+Condensed). Regular is used for media item labels, FX inserts, and sends. Medium is used for track labels and other controls. Recent REAPER versions supply Inter Regular and Medium. The transport clock and playback status use Inter SemiBold where installed.

The typography was checked on Windows with REAPER 7.84. The send tint adjustment uses the control introduced in [REAPER 7.78](https://www.reaper.fm/download-old.php?ver=7x).

## Credits

The theme's WALTER configuration derives from the REAPER default theme by Cockos. The original copyright and license notices are in `rtconfig.txt` inside the theme archive. See [LGPL 2.1](LICENSE-WALTER).
