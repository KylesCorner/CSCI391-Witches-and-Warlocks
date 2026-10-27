## Phase 1 — Player names and health bars
- [x] Create a reusable PlayerTag scene for overhead UI
- [x] Move the existing NameLabel into PlayerTag
- [x] Center player names above their sprites
- [x] Add a small health bar beneath each name
- [x] Add max_health, current_health and health_changed to PlayerController
- [x] Display overhead information for other players, with configurable local-player visibility
- [x] Synchronize health changes across multiplayer clients
- [x] Ensure the bars follow players correctly and remain readable at different zoom levels
- [x] Test with two clients using different names and classes

## Phase 2 — Shared in-game HUD
- [ ] Create scenes/ui/player_hud.tscn using CanvasLayer
- [ ] Add a larger local-player health bar
- [ ] Display the local player's class and name
- [ ] Create a shared bottom-center ability bar with four slots
- [ ] Add a task/objective panel
- [ ] Connect HUD updates through player signals rather than per-frame polling
- [ ] Only instantiate the local player's HUD on each client

## Phase 3 — Class-specific UI
- [ ] Create data definitions for four Warlock spells and four Witch potions
- [ ] Populate the shared ability bar from the selected class
- [ ] Assign icons, names, tooltips and descriptions for each ability
- [ ] Give Warlock and Witch distinct UI colors and styling
- [ ] Add selectable ability highlighting and keyboard shortcuts
- [ ] Display locked, available, active and consumed ability states
- [ ] Add cooldown/cast progress indicators where applicable

## Phase 4 — Tasks and consumables
- [ ] Build a four-task checklist that changes by class
- [ ] Show task progress using signals from the gameplay system
- [ ] Implement the existing task-pair-to-consumable unlock rules
- [ ] Notify the player when a new spell or potion is awarded
- [ ] Show the number of consumable charges available
- [ ] Add contextual interaction prompts for E
- [ ] Synchronize task completion and earned consumables

## Phase 5 — Gameplay effects and feedback
- [ ] Show health loss immediately in the HUD and overhead bar
- [ ] Add casting wind-up feedback for Fireball
- [ ] Add placement indicators for trap potions
- [ ] Indicate whether summoned Husk/Cat is active
- [ ] Show invisibility duration or expiration status
- [ ] Display damage, death and respawn feedback
- [ ] Add ability unavailable/error feedback

## Phase 6 — UI polish and testing
- [ ] Add pixel-art UI panels and consistent fonts
- [ ] Add status colors and animations
- [ ] Add scalable UI anchors and viewport-safe margins
- [ ] Prevent world-space name tags from overlapping excessively
- [ ] Test overlapping players, healing, death and disconnections
- [ ] Test Witch and Warlock on separate clients
- [ ] Verify HUD events never directly change authoritative gameplay state
