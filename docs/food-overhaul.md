# Food overhaul (version 8)

The plan for reworking the Food tab, the food logger and the Targets page. Written before the work started; "What shipped" at the end records what was built.

## What was wrong

| Area | Problem |
| --- | --- |
| Add buttons | Seven ways to add on one screen: a `+` on each of four meals, a floating "Add food" bar with its own scan and quick-add buttons, the dock's `+`, and "Add to snack" on each suggestion card. CLAUDE.md next step 1 asks for one. |
| The week | The tab showed only today. Nothing said how the week was going, whether protein was being hit, or how many days were logged (the burn estimate learns from logged days). |
| Weight | A raw 7-day change ("−0.20 this week") with no sense of noise, and no comparison with the goal rate the targets are built on. |
| Logger | Tapping a recent food added it at once; tapping a search result opened the amount sheet. Suggestions ("Fits what's left", "Same as yesterday", "Copy a meal") lived on the tab, away from where food is added. Recent foods ignored which meal you were logging. |
| Food list | 115 foods; search missed "doner" for "Döner" and British spellings like "yoghurt". |

## Goals

1. **One add button.** On the Food tab the dock's `+` adds food. Meals are rows you tap to add to that meal.
2. **See the week.** Calories against target each day, protein days hit, days logged, with a forgiving logging streak.
3. **Honest weight progress.** Weekly rate from a fitted line through weigh-ins, labelled Clear, Likely or Not clear yet, compared with the goal rate.
4. **A logger that starts where you are.** Same as yesterday, your usual for this meal, what fits what's left, then recent. Tap a name to choose the amount, tap `+` for your usual.

## Scope

### Engine
- `C.nutritionWeek(mon)` and `C.nutritionWeeks(d, n)`: per Monday-to-Sunday week, each day's intake, target and protein; logged days (at least 40% of the target eaten, today excluded until it's over), average calories against average target, protein days hit (90% of target or more), days within 10% of the calorie target.
- `C.loggingStreak(d)`: logged days in a row, with one missed day in any seven forgiven; today never breaks it.
- `C.weightRate(d)`: `E.trendFit` over the last 28 days of weigh-ins, as kg a week with an 80% range, and a verdict against the goal rate: on track, faster, slower or not clear yet.
- `C.usualFoods(d, meal)`: what you log most at this meal over 4 weeks, with your usual amount.
- About 28 foods added **at the end** of the list (stored entries refer to foods by position), and search that ignores accents and knows a few alternative spellings.

### Food tab
1. Day card: calories left or eaten, macros, fiber, and the training extra when there is one.
2. Meals: tap a meal to add to it, tap a food to change it. No `+` buttons.
3. This week: seven days of calories against target with protein hits, averages, and the logging streak. Tap a day to open it.
4. Weight: trend weight, weekly rate with its label, the goal rate, and the burn estimate.
5. The floating "Add food" bar and the suggestion cards are gone; the dock's `+` adds food on this tab.

### Logger
- Landing (empty search): Same as yesterday, Usual for this meal, Fits what's left, Recent, Copy a meal from another day. Everything goes onto the plate first, so nothing is logged by accident.
- Tap a food's name to choose the amount (your usual amount pre-selected); tap `+` to add your usual straight to the plate.

### Targets page
- Weight card: rate per week with label and range, the goal rate, a weigh-in button.
- Weekly averages for 8 weeks instead of a single week of bars.

### Claude coach
- The week's nutrition and the weight rate added to its context.

## Data model

Additive only. New foods are appended so existing `foodId`s keep pointing at the same food.

## Verification

Headless Chromium at 390 px and 360 px, dark and light, sample data and an empty log: every food screen renders with no console errors, no horizontal overflow and no text under 11 px; a meal is logged from the dock button through the plate; the fitness checks from the previous overhaul still pass.

## What shipped

Everything in the scope above, in `index.html`:

- Engine: `loggedDay`, `nutritionWeek`, `nutritionWeeks`, `loggingStreak`, `usualFoods` and `weightRate` on the context. 28 foods appended to the list (143 in all) and accent-insensitive search with a few alternative spellings.
- Food tab: day card (now with fiber and the training extra), tappable meals, This week, Weight. The dock's `+` is labelled "Add food" here and opens the logger for the current meal; the floating log bar, per-meal `+` buttons, suggestion cards and the copy button are gone.
- Logger: the landing view and the consistent taps described above. `Sheet.portion` takes the previous amount (`grams`, or `qty` for your own foods); `Sheet.copyMeal` can hand a meal to the plate.
- Targets: Weight card with the fitted rate and verdict, Weekly averages for 8 weeks with protein hits.
- Claude coach: two weeks of nutrition and the weight rate.

## Merged with the iPhone app branch (version 1.5)

Carried onto the branch with the iPhone app, Open Food Facts, the USDA food list, water, saved meals and favourites. Where both had changed the same screen, the fuller version was kept:

- **Food tab:** the other branch's day card, water card and meals (empty meals folded into one line, "Save as a meal", "Same as yesterday") stay. This overhaul's week strip replaces the "Last 7 days" strip and keeps its fibre figure; the Weight card replaces the target row. The day card gains fibre and the extra-activity note.
- **Food log:** the other branch's saved meals, favourites, packaged foods and USDA results stay. Before you type, the list now runs: same as yesterday, saved meals, favourites, your usual for this meal, fits what's left, recent, then Copy a meal and Create a food. Tapping a name opens the amount sheet at the amount you had; `+` still adds your usual amount.
- **Foods:** 18 of the 28 foods added here were already in the other branch's list; the other 10 are appended. Search keeps the other branch's alternative words and everyday matches, and now ignores accents.

Dropped from the other branch's Food tab: the "Fits what's left" carousel, the "Last 7 days" strip, the target row and the "Copy a meal" button (all now in the food log or the Weight card). On Targets, the 7-day bars are replaced by eight weekly averages.
