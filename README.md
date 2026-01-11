# 🗡️ Auto Element – Monster Hunter: Wilds Mod

![REFramework](https://img.shields.io/badge/REFramework-Required-red)

Automatically adjusts your weapon’s elemental attribute for maximum damage. This mod works per-monster or per-part for optimal elemental effectiveness.

---

## ⚡ Features

- **Automatic Element Switching** – Optimizes your weapon’s element for the target monster.  
- **Per-Part Optimization** – Target specific monster parts for maximum elemental damage.  
- **Original Element Restoration** – Restores your weapon’s original element when changing weapons or disabling the mod.  
- **Hotkey Toggle** – Enable or disable the mod in-game (keyboard/controller).  
- **Configurable Options** – Adjust behaviour through the REFramework UI.

---

## 🛠️ Installation

1. Make sure **REFramework** is installed.  
2. Place the files in your `REFramework` folder.  
3. Launch **Monster Hunter: Wilds** and open the Script User Interfaces.

---

## ⚙️ Configuration Example

Edit the settings in the Lua script or use the REFramework UI:

```lua
-- AutoElement settings
Enabled = true               -- Turn the mod on/off
PerPart = true               -- Optimize per monster part
OnlyChangeIfElemental = true -- Only modify weapons that already have an element
````
---

## 🎮 Usage

1. Enable the mod via your configured hotkey or the REFramework UI.  
2. Attack monsters normally — your weapon’s element will update automatically.  
3. Adjust settings for per-part targeting or restricting changes to only elemental weapons.

---

## ⚠️ Notes

- Works with all weapons but can be configured to only work with a weapon that has elemental attributes.  
- Caches element values for better performance and to prevent unnecessary recalculations.  
- Disabling the mod restores your weapon’s original element automatically.
