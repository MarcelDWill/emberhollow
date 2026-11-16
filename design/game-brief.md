# Emberhollow: Game Brief

Working title: *Emberhollow*. Source of truth for design decisions: the "Blacksmith Game: Design Doc" in the Gametime project. This file is the build copy; if the two disagree, ask Marcel.

## Pitch

Coral Island with an anvil instead of a hoe. You start your own smithy in a frontier village. You forge gear, sell it, befriend the townsfolk, and fight monsters for the materials you need.

## Design pillars

Every feature must serve at least one.

1. **Forging feels great.** Every item is made through a short, skill-based forge job of three stages. Better play makes better gear, up to what the smith has earned: quality tiers are locked behind smithing level, quests, and blueprints. Difficulty is relative to the character's smithing level: gear above it is harder, and once mastery is unlocked, gear below it gets easier. Forging gets the most polish.
2. **Cozy on top, creepy underneath.** The village is warm and funny, with crude adventurers and pleasant townsfolk. Thornwood Forest (the "Hollow") is eerie and the lore is dark. Cute-versus-sinister contrast, like Cult of the Lamb.
3. **What you make, you use.** Weapons you forge are the weapons you fight with. You make weapons, armor, and miscellaneous items for townsfolk.
4. **A town that grows with you.** Orders, friendships, and building projects visibly change the village over the seasons.

## Core loop

Forge → Shop (forged gear) → Village (coin and reputation) → the wilds (upgrades, new areas) → Forge (ore and monster parts).

A typical day: check the order board and stock the shop in the morning, forge through midday, visit the village in the afternoon, head into the wilds in the evening. The shop sells while you are away; sales are tallied when you sleep. One in-game day is about 15 real minutes.

## Setting and story

- **Premise:** Emberhollow is a new frontier village and you are a new settler. The adventurers' guild has its own blacksmith, but you are starting your own forge. Monsters push back against the town, so supplies are scarce and expensive. You gather your own or post requests with the guild.
- **Tone:** cozy with light humor, dark underneath. Wrongness in the details: candles that flicker toward Thornwood, a festival nobody explains, a well that hums.
- **Comic mentor:** the anvil talks. It was a gift from your mentor and holds the ghost of a sarcastic, antagonistic ancestor who started an old smithy and bound himself into the iron. It has been passed (dumped) from master to apprentice. It teaches forging, roasts bad hammer timing, and tells how his own mentor messed up and grew. Funny but encouraging. Later he just shows up to harass you, which is his way of approving. He comments on every forge result.
- **Story arc (draft):**
  1. Act 1: learn the craft, forge to bring in clients, open your shop (player names it).
  2. Act 2: deeper areas open, monster parts unlock stranger recipes, guild adventurers arrive once your skill levels up.
  3. Act 3: higher-quality weapons for higher-tier adventurers, fame across regions, custom gear requests.
- **Seasons:** four seasons of 28 days, a festival each season, some ores and monsters seasonal.

## Races

The player picks a race, then customizes colors, face, horns or ears, outfit, and apron. No race is required for any content. Races and perks live in data so more can be added without code changes.

| Race | Look | Traits | Bends |
| --- | --- | --- | --- |
| Human | Typical human | Dexterous fingers: better foraging (more herbs per node, better chance of rare herbs); high aptitude customizing pieces and using different weapons | Gathering (foraging) |
| Dwarf | Short, stocky, lots of facial hair | Master smith: hammer skill makes forging easier and raises quality. Deep digger: +1 ore per node, mining costs less stamina. Better with axes, hammers, blunt weapons | Forging and mining |
| Elf | Shorter and slimmer than humans | Natural beauty: better shop prices, faster friendship. Prefers rapiers, bows, one-handed swords. Average stamina, so forging takes longer at lower skill levels except for specialty weapons. Sharp eyes by day, poor sight at night | Shop and village, day exploration |
| Beastkin | Big eyes, fur | Night sight: dark areas are brighter, hidden gem veins visible. Good with spears, polearms, halberds, maces. Sensory strain: foraging drains extra stamina | Combat, night exploration (weak foraging) |

Strength ratings (1 weak to 5 strong). Use these as the starting balance values in data:

| Bend | Human | Dwarf | Elf | Beastkin |
| --- | --- | --- | --- | --- |
| Forging | 4 | 5 | 3 | 3 |
| Mining | 4 | 5 | 2 | 4 |
| Foraging | 5 | 3 | 4 | 3 |
| Shop and village | 4 | 4 | 5 | 2 |
| Stamina | 3 | 4 | 3 | 4 |
| Day exploration | 4 | 3 | 5 | 5 |
| Night exploration | 3 | 3 | 2 | 5 |
| Combat | 4 | 4 | 4 | 4 |
| Total | 31 | 31 | 28 | 30 |

## Forging

Every item is one forge job: three stages played in order, about 75 to 90 seconds in total. Each stage scores 0 to 100, and the job's score is the weighted average of the three (equal weights to start). Two buttons plus movement.

| Stage | What you do | Keyboard / gamepad | Skill tested |
| --- | --- | --- | --- |
| 1. Blade Trace | Guide a weighted hammer along the item's outline at your own pace and strike at each ring. Going past par time costs points | WASD / left stick, Space / A to strike | Steadiness |
| 2. Anvil Song | Press as each note reaches its ring: bellows on the top lane, hammer on the bottom lane, long notes held and released on time | F / X (bellows), Space / A (hammer) | Rhythm |
| 3. One Heat | Hold to heat the bar in the fire, let go, then strike while the heat sits in the bright band. Every strike cools the bar, and overheating scorches it | Hold F / X to heat, Space / A to strike | Judgement under time pressure |

One Heat is the heart of the forge and gets the most polish: the bar glows with its heat, it pulses when it is ready to strike, strikes build a streak, and the anvil comments as you work. Space / A is the main button and F / X is the second button everywhere in the forge.

- **Quality tiers:** Crude, Fine, Superior, Masterwork, Legendary. Starting cutoffs: Crude 0, Fine 40, Superior 60, Masterwork 78, Legendary 96.
- **Tier locks:** skill alone is not enough. Each tier above Crude is locked behind a smithing level, quests, and (for the top tiers) a blueprint for that item. The score earns a tier, then the award climbs from Crude and stops at the first locked tier, so a low-level player who is good at rhythm games cannot make Legendary items. A capped result tells the player what they earned and what would unlock the next tier. Starting locks:

| Tier | Smithing level | Quest | Blueprint for the item |
| --- | --- | --- | --- |
| Crude | 1 | none | no |
| Fine | 2 | none | no |
| Superior | 4 | Open your shop | no |
| Masterwork | 7 | A commission from the guild | yes |
| Legendary | 10 | The anvil's true name | yes |

- **Difficulty by level:** every item has a gear level. Gear above the player's smithing level is harder to forge: timing windows and target sizes shrink and the bar cools faster, by 15% per level above, up to five levels. Gear at the player's level plays at the baseline.
- **Mastery:** gear below the player's smithing level gets easier (6% per level below, up to five levels), but only after mastery is unlocked. Starting requirements: smithing level 3 and the quest "The anvil's first lesson". Until then, lower gear plays at the baseline.
- **Tuning lives in data:** every cutoff, lock, requirement, difficulty step, stage timing, and line of anvil dialogue is in JSON under `data/` (see `data/README.md`). The quest names above are placeholders until quests exist.
- **Rune slot:** left out for now.
- **Mass production:** after making an item enough times, it can be produced faster, but with a capped quality tier.
- **Recipe design:** players design and save recipes by desired attributes. The game shows required materials and skill level. Results are never guaranteed; stats depend on skill.
- **Recycling:** items break down into part of their materials. A Knowledge stat raises the percentage returned and also helps minigames and recipe development.
- **Materials:** metals set the base (copper, iron, silver, rarer metals from the Stormspine Mountains). Monster parts add modifiers (bone for lighter weapons, ichor for poison, ember gland for fire).
- **Recipes:** weapons (dagger, sword, axe, spear, hammer), tools (pickaxe, sickle, fishing hook), limited armor (leatherwork comes in a later installment), and village orders (horseshoes, lantern frame, chapel bell).

## Village, shop, relationships

- **Shop:** display racks with player-set prices. Customers browse and react with emote bubbles (too high, fair, a steal). Sells while you are out.
- **Customers:** villagers (tools and household items; pay in coin, barter, and friendship), adventurers (weapons and armor; bring stories, rare drops, bad news), special orders on a board.
- **Relationships:** 12 to 15 named villagers at full scope, loved and hated items, a handshake meter, short story events. No romance for now.
- **Building up the town:** forged items build things (bridge brackets, chapel bell, mine lift gears). Each opens new areas, shops, or villagers.
- **Apothecary side quest:** refine monster materials with the town apothecary so they can be embedded in weapons. Pay with foraged herbs.

## Gathering and combat

- **Combat style:** like Cult of the Lamb. Fast and dodge-heavy, light and heavy attacks, a dodge-roll with brief invincibility, clear enemy wind-ups, short rooms cleared one at a time. Fights stay short so every trip feeds the forge.
- **Controls (top-down, 3/4 view):** move, light attack, heavy attack, dodge-roll, use tool, quick-item.
- **Gear matters:** weapon damage, speed, and modifiers come from what you forged. Pickaxe tier gates ore types.
- **Risk and stamina:** stamina drains as you mine and fight. Knocked out means back to the village, losing some of what you carried. Monsters get tougher at night. You can hire guild guards; pay depends on their rank (which sets their ability) and can be bartered based on relationship.
- **Topside gathering:** wood, charcoal, occasional surface ore.

**The Ember Frontier** (map: `design/reference/ember-frontier-map.png`). Explored on foot from town; danger and material quality rise with distance. Mines are deep dungeons built in floors, with a lift checkpoint every five floors and hand-made room chunks arranged at random. Ruins are short one-off dungeons ending in a reward room. Frontier camps are guild outposts: rest, save, hire guards, post supply requests.

| Zone | Where | Danger | Materials (draft) | Monsters (draft) | Points of interest |
| --- | --- | --- | --- | --- | --- |
| Emberhollow Plains | Around town, south to the coast | Low | Wood, stone, surface copper, hides | Slimes, wild boars | 1 mine in the southern hills, ruins, frontier camps |
| Coast and cliffs | Southwest shore | Low to medium | Salt, shells, driftwood, pearls | Shore crabs, gulls | Sea stacks, cliff paths |
| River and lake | East, along the river | Medium | Clay, sand, river silver | Eels, bog toads | Lakeside ruins, bridge, frontier camp |
| Thornwood Forest | North of town | Medium | Hardwood, charcoal, iron, monster parts | Twig wraiths, wolves | 2 mines, ruined gate; the eerie "Hollow" |
| Stormspine Mountains | Northeast | High | Silver, gems, rare metals | Harpies, stone golems | 1 mine, waterfall fortress, dark tower (endgame) |

## Progression and economy

| Currency | Earned by | Spent on |
| --- | --- | --- |
| Coin | Shop sales, orders | Materials, forge upgrades, shop furniture, house |
| Reputation | Quality items, finished orders, town projects | New customer types, recipes, harder orders |
| Frontier Resources | Monster drops, deep floors | Runes, enchanted modifiers, story items |

- **Forge upgrades:** bellows (wider heat zone), anvil tier (more metals), quench trough (gentler timing), display racks (more stock).
- **Skills:** Smithing, Mining, Combat, Trade level with use and stack with race traits.
- **Pacing:** a first season should feel complete: forge relit, first zone done, two town projects.

## Art direction

Inspired by Cult of the Lamb, with entirely original characters and assets. Chibi proportions, thick dark outlines, paper-cutout puppet animation. Top-down 3/4 camera over flat painted layers, soft drop shadows, gentle vignette. Village palette: cream, amber, forge orange. Wilds palette: dusty purples, deep reds, sickly greens. The forge glow is the brightest thing on screen. Lots of juice: sparks, screen shake on good hits, pop-in quality text.

- **Animation:** characters split into parts and rigged with Godot's 2D skeleton tools (Skeleton2D / Bone2D) so outfits swap per part.
- **Art source:** Marcel makes art in ArtCraft. Until final art exists, use clean placeholder shapes in the final palette and camera.

## Platforms

Godot 4 and GDScript. Targets: web (itch.io, Cloudflare) for the demo, Steam on PC, Android, and PlayStation 5 as the end goal (via W4 Games, later). Solo at launch; co-op may come later.

## Demo scope (vertical slice, three in-game days)

In:
- Character creator: four races, three color slots, two outfits
- Forge with all three stages (Blade Trace, Anvil Song, One Heat), tier locks, and the talking anvil
- Three recipes (dagger, sword, pickaxe upgrade), three metals (copper, iron, silver)
- Shop with display racks and three customer types
- One village map, two named villagers with friendship, one special order
- Emberhollow Plains with the southern hills mine: five floors, two monster types, a mini-boss
- Day and night clock, stamina, saving
- Placeholder art in the final palette and camera

Out: seasons, romance, other zones, town projects, final art.

## Build order

1. Forging prototypes: three to five tiny, independent takes on the minigame in `prototypes/`. Marcel plays and picks one. (Done: the forge combines Blade Trace, Anvil Song, and One Heat.)
2. Core project: GameState and EventBus autoloads, input map, text state dump, save system.
3. Scenes in order: Forge, Shop, Village, Mine, Character Creator.
4. Web export and deploy.

## Open questions

- Art pipeline is leaning skeletal cutout but not locked.
- Business model: paid on itch.io/Steam, free with tips, or undecided.
