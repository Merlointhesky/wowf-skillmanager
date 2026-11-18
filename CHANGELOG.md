# Changelog

All notable changes to **ForeverSkillManager** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.5.0] - 2026-11-18

### Added
- **Talent Abilities Placement Toggle**:
  - Added `autoAddTalentSpells = false` configuration setting so spells learned through talent specialization (e.g. Feral Charge, Cold Snap, Conflagrate, Shadowform, etc.) are not automatically placed into empty action bar slots by default.
  - Added "Auto-add talent abilities to bar" checkbox to the `/fsm` options panel.
  - Added dynamic talent detection supporting `C_Traits`, `GetTalentInfo`, `C_Spell.IsClassTalentSpell`, `C_SpellBook.IsClassTalentSpellBookItem`, and static Classic talent ability references.
- **Cache Cleaning Command**:
  - Added `/fsm clean` (or `/fsm cleancache`) slash command to purge corrupt, duplicate, or stale status-text entries from the trainer cache.

### Fixed
- **Hunter Beast Training Filter**:
  - Filtered out pet abilities learned from the hunter "Beast Training" window (Growl, Bite, Claw, Great Stamina, Resistances, etc.) from action bar auto-placement, spellbook snapshots, and class trainer caching.
  - Added listener hooks for `CRAFT_SHOW` and `CRAFT_CLOSE` to suppress event noise during pet training.
- **Stance & Form Switching Re-Evaluation**:
  - Retained known spell IDs across shapeshifting, forms, and stance changes so abilities are not repeatedly re-evaluated as newly learned spells on form swaps.
- **Corrupt Spell Status in Trainer Frame**:
  - Purged legacy entries with status keywords (`unavailable`, `available`, `used`, `header`) from rank subtexts and cache keys.
  - Ensured unique deduplication across numeric `spellID` and string keys, preventing status keywords from rendering as spell ranks.
- **Client Secret-Value Safety**:
  - Added `IsSecret`, `SafeString`, and `SafeGetText` defensive wrappers in `core.lua` and `skills.lua` to ensure safety with protected/secret UI values on modern WoW Forever clients.
- **Irrelevant Trainer Spells**:
  - Prevented spells offered by trainers of irrelevant classes from being cached into character trainer previews.

---

## [1.4.1] - 2026-11-05

### Added
- Initial tracking and automatic placement of newly learned spells and equipped on-use gear into action bar slots.
- Automatic upgrading of existing spell ranks in place.
- Trainer level-up popup reminders and unspent talent point alerts.
- Configurable settings panel via `/fsm` and draggable minimap button.
