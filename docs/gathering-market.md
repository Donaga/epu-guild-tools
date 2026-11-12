# Gathering market pilot

Open **Market** in the EPU sidebar or type `/epu market`. It starts on **Craft** with **All my professions** selected. The profession menu lists the current character's crafting skills, including secondary crafting and smelting. Herbalism, Skinning and Fishing have no recipes, so they appear under **Gather** only. **Open to scan** opens the selected profession so EPU can read the character's learned recipes. **Profession guides** opens the guide list for all the character's learned professions.

## Where prices come from

EPU never scans the auction house. It reads one of three optional addons, and the button for the one in use stays pressed.

- **AHledger** supplies the current lowest listing, the median, units listed and estimated units sold per day for your Forever market. [AHledger API and data credit](https://ahledger.com/developers)
- **TSM** supplies its lowest buyout when it has one, otherwise the regional sale average, plus regional units sold per day and sell-through. [TSM price sources](https://support.tradeskillmaster.com/custom-strings/which-price-sources-can-i-use-and-what-do-they-mean) · [TSM sale metrics](https://support.tradeskillmaster.com/en_US/custom-strings/which-value-sources-can-i-use-and-what-do-they-mean)
- **Auctionator** supplies the lowest listing from your own last scan. It has no sales volume, so Buy & Craft needs AHledger or TSM.

The line under the buttons says how fresh the selected source is. It turns amber when AHledger is using its bundled snapshot instead of live prices, when its prices are more than six hours old, or when your last Auctionator scan was not today. AHledger Sync downloads updated price tables every 30 minutes and WoW loads them at the next login or `/reload`. [AHledger sync](https://ahledger.com/guides/scanning-and-uploading) **Refresh** rereads the selected addon.

## What the profit means

Profit is what you would make **now**: the sale price is the current lowest listing, less the 5% faction AH cut, minus the ingredients.

- If nothing is listed, EPU uses the median and tags the row **No listings**.
- If the only listings are above the median, EPU uses the median, so one overpriced auction cannot inflate profit.
- Hover a row to see which price was used.
- **Craft** prices ingredients at their lowest listing. **Buy & Craft** budgets each ingredient at the higher of its lowest listing and the median, because you rarely get the whole quantity at the lowest price. The footer names the basis for the open tab.
- Ingredients a vendor sells (thread, flux, vials, dyes, spices and similar) use the vendor price when it is cheaper or when the market has no price. The shopping list marks them **(vendor)**. Reputation discounts are not applied.
- Deposits are not included: the deposit comes back when an item sells, and only an unsold listing loses it. Slow and Thin margin tags flag where that risk matters.

Rows carry one short tag when it applies:

| Tag | Meaning |
|---|---|
| **Sells now** | A day or less of stock is listed |
| **Slow** | More than three days of stock is listed, or under one sale a day |
| **Thin margin** | Under 1s or under 10% profit per craft |
| **No listings** | Nothing listed; the price is a median |
| **Loss** | Loses money at the current price (Craft only) |

## Craft

Open each learned profession after installing the update. **Craft** lists tradable recipes with a fixed output and one fixed ingredient list. The header shows how many learned recipes are compared; recipes with variable output, optional or alternative reagents, and services such as enchants are left out. When two learned recipes make the same item, EPU compares the cheaper one.

**Sort: Profit** ranks by gold per craft. **Sort: Skill-ups** keeps orange and yellow recipes and puts the cheapest way to gain a point first: crafts that earn money, then the smallest loss per expected skill-up (yellow recipes count as three skill-ups in four crafts). Difficulty colours are read when you open the profession, so reopen it after a few points.

Select a recipe and enter a batch size to see which ingredients you lack, what you can make from known recipes, and the remaining base materials. Carried items reduce what you need to obtain. Gathered ingredients still count at market value in the margin. Missing prices leave the corresponding estimate blank. Catalogued base materials link back to Gather and show an approximate gathering time when you have saved a yield for that material and zone.

## Guild scope

**Scope: Guild** (on Craft and Buy & Craft) lists every tradable item your guildmates can craft, priced the same way, with who can make it. Online crafters are green and guild crafters are starred. The profession menu switches to the guild's professions. Select a recipe to see its ingredients and crafters, then **Ask a crafter** to open it in Recipes and send a craft request. **Scope: Mine** returns to your own professions.

Members who have left the guild are never listed as crafters. The guild view only includes recipes whose crafters have EPU 0.22.0 or later and have opened that profession since updating, because older versions don't share which recipes have a fixed output. The header counts recipes still waiting for that. Skill-ups are personal, so that sort is only on your own scope.

## Guild focus

Officers mark the professions the guild wants more of in **Officer → Profession coverage**: **Set as focus** on a profession, with or without a skill goal of 75, 150, 225 or 300. The coverage page then shows each focus with how many players have it and how many have reached the goal, counting alts once at their best skill.

Every member sees the guild focus at the bottom of Craft and Gather, with their own skill in any focus profession they have. A member with a free primary profession slot is told so when a focus profession could fill it. The Craft and Gather profession menus mark focus professions.

## Buy & Craft

**Buy & Craft** shows learned recipes with positive profit and positive daily sales. Sort by **Sold/day**, **Profit/craft**, **Profit %**, **Sale price**, or **Profit + demand**. That last one is profit per finished unit times market-wide units sold per day, reduced when more than a day of stock is already listed. It is a ranking signal, not an income forecast. The gold highlight marks the top three for whichever sort is active.

Both crafting views show **profit %** as profit after the faction AH cut divided by total ingredient cost. For example, spending 1g on ingredients and making 25s after the cut is a +25% return. Check the actual price and quantity at the auction house before buying.

## Gather

**Gather** starts on a learned gathering profession and lets you compare herbs, mining materials, skins, and fish. **My skill** uses known requirements for Mining and Herbalism. Skinning and Fishing requirements depend on the creature or water. Forever's new herbs, whose skill requirement isn't published yet, stay in the list while **My skill** is on and are marked as unconfirmed. The highest three priced materials in the current results are marked **Top price**.

With AHledger the list sorts by estimated market gold per day and hollow chart points mean sell-through is unavailable. With TSM it sorts by price times sell-through. With Auctionator it sorts by price and nothing is plotted.

Selecting a material also says how many guildmates can gather it at their current skill, and hovering a row names them, online members first.

Click a gathering material to save your observed **Units/hour** for the current zone. If you gather 15 units in 30 minutes, enter 30. Use **Sort: My gold/hr** to compare saved yields at current prices. The estimate is gross sale value, before fees, and assumes the full haul sells. The yield is private to this character.

## Routes

Herbalism and Mining have routes. When your current zone has recorded spots, Gather opens with **This zone: On** so the list shows what you can pick up where you stand; turn it off to see every material. Click a material to preview its spots and **Start route**, or use the overview button or `/epu route` (herbs) and `/epu route ore` (mining) for a pass through every recorded spot in the zone. Drag the EPU arrow to move it, choose **Next spot** or `/epu route next` to skip, and **Stop** or `/epu route stop` to end. The arrow points toward the nearest unvisited spot and advances when you arrive. A pass ends after the last spot or when you leave the zone. Use WoW's **Find Herbs** or **Find Minerals** to check for live nodes.

**Record spot** saves your current position for the selected material, whatever your skill. Recorded spots are shared with the guild: guildmates' routes and previews include them after the next sync, up to 400 spots per member. Type `/epu sharespots off` to stop sharing yours (guildmates' copies are cleared at their next sync) and `/epu sharespots on` to share again. EPU also reads GatherMate2's recorded nodes when it is installed.

The bundled spots come from what players have reported so far, so coverage is uneven: Durotar, the Barrens, Tirisfal Glades and Silverpine Forest are well covered, while Elwynn Forest, Westfall, Teldrassil, Dun Morogh and Loch Modan have only a handful each. Points show where players approached a node, so the exact plant or vein may be a short distance away.

## Data credit

Bundled gathering spots and vendor prices are from Efficient Games (https://efficient.games), licensed under CC BY 4.0. EPU took herb and ore observations and vendor listings from the live WoW: Forever builds in the dataset, grouped the observations by map and item, merged nearby ones, and kept the undiscounted per-unit price of goods at least two vendors sell in unlimited stock. Regenerate `EPUGuild/GatheringSpots.lua` with `tools/build_gathering_data.py`. [Source dataset](https://github.com/JIVESCORP/eg-link-output-wowf) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
