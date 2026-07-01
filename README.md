# Vostok Mod Exporter
- Exports the selected folder as a `.vmz` mod.
- Exports the imported assets and converts text resources to binary resources on demand.
- Supports blacklists and various options.
- Unlike exporting through the editor with only selected resources and scenes, it doesn't pull in any unnecessary dependencies like the splash screen, autoloads and any resources referenced by your files outside of the selected directory.

## How To Install
- Create a `res://addons/mod_exporter` directory.
- Search for ["VostokMods Exporter"](https://godotengine.org/asset-library/asset/3764) in the AssetLib and download it.
- **During installation, press "Change Install Folder" and select the `mod_exporter` folder.**
- Enable the plugin in Project > Project Settings... > Plugins.
- New dock panel "Vostok Mod Exporter" will be added to the editor, it will scan for any files named `mod.txt` and add them to the list of mods.

## Remaps
Remaps for existing files can be defined by creating a `[remaps]` section in the mod.txt you are exporting. The target path will automatically be resolved to the imported asset path.   
Example:
```conf
[remaps]
"res://MyFile.tres"="res://mods/MyMod/ModdedFile.tres"
```
