# ForeverSkillManager

**Version:** 1.4.1  
**Author:** merlointhesky (Merlointhesky)  
**License:** GNU General Public License v3.0 (GPL-3.0)  
**WoW Version:** WoW Forever Beta (Interface `16001`)  
**Repository:** [https://github.com/Merlointhesky/wowf-skillmanager](https://github.com/Merlointhesky/wowf-skillmanager)

---

## Overview

**ForeverSkillManager** is a World of Warcraft addon tailored for the **WoW Forever Beta** (Interface `16001`). It automates action bar maintenance by automatically placing newly learned abilities and equipped "Use" gear onto your action bars, upgrading existing spell ranks in-place, and keeping track of class trainer abilities and unspent talent points as your character levels up.

---

## Features

- **Auto-Place New Spells** – Automatically finds open action bar slots (across Action Bars 1 through 6) and slots newly learned spells upon learning them.
- **In-Place Rank Upgrades** – When learning a new rank of an ability already on your bars, ForeverSkillManager replaces the existing slot with the highest rank without disrupting your action bar layout.
- **On-Use Equipment Automation** – Automatically places equipped items with "Use:" effects (such as trinkets or on-use armor) into open slots, and swaps them out on your bar when equipment is changed.
- **Level-Up Trainer Alerts** – Caches class trainer spell lists and displays a reminder notification/popup on level-up when new spells are available for purchase.
- **Trainer Spells Preview Dialog** – Displays available and upcoming class trainer spells, level requirements, ranks, and total training costs in gold/silver/copper.
- **Auto-Train Spells** – Optional one-click auto-learning of all available spells when speaking to your class trainer.
- **Unspent Talent Reminders** – Prominently alerts you when unspent talent points are available.
- **Minimap Button & Notification Badge** – Custom draggable minimap icon with a glowing indicator badge whenever new spells or talents are waiting.
- **Safe Combat Handling** – Buffers spell and gear placement during combat to prevent protected action bar UI taints, applying changes immediately once combat ends.

---

## Installation

1. Clone or download this repository into your WoW Forever `AddOns` directory:
   ```text
   c:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ForeverSkillManager
   ```
2. Ensure the folder is named `ForeverSkillManager`.
3. Launch or reload World of Warcraft (`/reload`).

---

## Slash Commands & Usage

| Command | Action |
| :--- | :--- |
| `/fsm` or `/skillmanager` | Toggle the configuration settings panel |
| `/fsm trainer` or `/fsm spells` | View cached and upcoming trainer spells |
| `/fsm scan` or `/fsm gear` | Manually scan and place equipped on-use gear |
| `/fsm debug` | Toggle diagnostic debug logging |
| `/fsm help` | Print command help to chat |

### Minimap Controls
- **Left-Click:** Open/close the configuration options dialog.
- **Right-Click:** Open the Trainer Spells reminder window.
- **Drag:** Move the minimap button around the minimap perimeter.

---

## Configuration

Settings are persistently stored per-account in `ForeverSkillManagerDB`:

- `autoAddSpells`: Automatically place newly learned spells in free action bar slots. *(Default: On)*
- `autoUpgradeSpells`: Automatically upgrade existing spell ranks in place. *(Default: On)*
- `autoAddGear`: Automatically place equipped "Use" gear & trinkets onto bars. *(Default: On)*
- `autoUpgradeGear`: Automatically update swapped "Use" gear on action bars. *(Default: On)*
- `trainerAlert`: Show a reminder popup on level-up when new spells can be trained. *(Default: On)*
- `talentAlert`: Reminder notification when unspent talent points are available. *(Default: On)*
- `autoTrainSpells`: Automatically learn all available spells when opening a trainer. *(Default: Off)*
- `debugMode`: Enable verbose debug logging to chat. *(Default: Off)*

---

## License

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0). See the [LICENSE](LICENSE) file for complete details.

