# Fitness overhaul (version 8)

The plan for reworking the fitness parts of Baseline: the Train tab, the workout logger and every page behind them. Written before the work started; "What shipped" at the end records what was built.

## What was wrong

| Area | Problem |
| --- | --- |
| Train tab | Today's plan showed twice (a "Start a workout" card and again in the schedule). The readiness headline and the session to do were separate cards. The subtitle added up daily strain across the week, which isn't a meaningful number on a curved 0–21 scale. About three screens long. |
| Cardio | No progress view at all. VO₂ max, running pace, heart rate during runs and time in zones were stored but only used for strain. A person who runs twice a week saw nothing about getting fitter. |
| Strength progress | Charts drew raw best-set estimates, which jump around session to session. "+0.7 kg in 8 weeks" was shown as fact even when the noise was ten times bigger. |
| Muscle volume | Weekly sets per muscle existed but had no reference, so 4 sets and 24 sets looked equally fine. |
| Training load | Labels overclaimed: "Detraining" after one light week, "Overreaching" and "raise injury risk" from a 7-day/28-day ratio whose link to injury is weak. |
| Logger | Loads shown as 76.25 in the input and 76.3 in "Previous" and the hint. A long progression paragraph on every exercise before you start. Rest timer changed by tapping through presets blind. Narrow RPE column squeezed the "Previous" column. Several controls under 44 px. |
| Exercise library | Equipment and timed holds guessed from the exercise name with regexes; 45 moves. |
| Exercise page | Rep-range control overflowed its row on phone widths. Bar weight shown but not editable. |

## Goals

1. **One decision on the Train tab.** What to do today, why, and one button to start it.
2. **Cardio gets the same care as lifting.** Fitness trend, how hard the training actually is, running progress.
3. **Honest progress.** Every trend says how sure it is: *Clear*, *Likely* or *Not clear yet*, with a range (CLAUDE.md, next step 2).
4. **Measured against the person.** Muscle volume and load compared with their own 4-week normal, with general guides shown as guides.
5. **Logger polish.** Consistent numbers, less text, 44 px targets, quicker rest changes.

## Scope

### Engine (`E`, pure functions)

- **Exercise library v2.** Each move carries equipment (barbell, dumbbell, cable, machine, bodyweight, other) and a timed flag. About 20 common moves added. Names stay the keys, so stored workouts keep working.
- **`E.trendFit(points, horizon)`.** Least-squares line with a confidence label: *Clear* when the 95 % range of the change excludes zero, *Likely* at 80 %, otherwise *Not clear yet*. Returns the change over the horizon and its 80 % range.
- **`C.liftTrend(name, d)`** and **`C.strengthSummary(d)`**: estimated 1-rep max (or reps for bodyweight moves) per session over 8 weeks, fitted.
- **`C.trainingWeeks(d, n)`**: per Monday-to-Sunday week, sessions, strength vs cardio, hard sets, volume, cardio minutes, minutes in each heart-rate zone, running distance, planned vs done.
- **`C.weekGoal(d)`**: weekly session goal (set by the person, else the weekly plan capped at 5, else 3) and a **forgiving streak**: one missed week in any six doesn't break it.
- **`C.muscleVolume(d)`**: hard sets per muscle this week, the 4-week weekly average, and a general guide range.
- **`C.cardioFitness(d)`**: VO₂ max trend against the age and sex norm already used by health age; running efficiency (metres per heartbeat) per run, fitted; intensity mix over 4 weeks (easy zones 1–2, moderate zone 3, hard zones 4–5).
- **Load labels**: Lighter, Maintaining, Building, High, Spike, with plainer wording.

### Train tab

1. Header: sessions this week against the goal, and the streak.
2. **Today** card: recovery and strain target, then the planned session (or the best-suited routine), one line of advice tuned to recovery and muscle freshness, the start button, and *Swap* / *Something else*.
3. **This week**: done vs planned, hard sets, cardio time, then the existing schedule calendar.
4. **Progress**: a Strength card (top lifts with trend and label) and a Cardio card (VO₂ max, running efficiency, intensity mix).
5. Training load, recent sessions, and the library links.

### New pages

- **Strength**: weekly hard sets (12 weeks), every lift with its trend, muscle balance against the guide.
- **Cardio fitness**: VO₂ max over 6 months, weekly minutes by zone, intensity mix, running distance and efficiency.

### Existing pages

- **Logger**: loads formatted the same everywhere; one-line target with the full explanation on tap; rest picker sheet with "use for this exercise"; scroll to the next exercise when one is finished; warm-up ramp for heavy first lifts; RPE column on when you use it; 44 px targets.
- **Finish summary**: "Compared with last time" for each exercise.
- **Exercise**: fitted trend line and label on the chart, rep maxes on Records, editable bar weight, layout fix.
- **Muscles**: weekly volume mode shows the guide and your 4-week average.
- **Load**: new labels and explanation.
- **Claude coach**: training summary added to the context it gets.

## Data model

Additive only. Nothing existing is renamed or migrated.

- `state.training.weeklyGoal` (number, optional).
- `state.training.exercises[name].bar` is now editable (already read).

## Verification

Headless Chromium at 390 px and 360 px, dark and light, sample data and an empty log: every fitness screen renders with no console errors and no horizontal overflow, and a workout runs from start to save.

## What shipped

Everything in the scope above, in `index.html`:

- Engine: `E.trendFit`, `E.vo2Norm`, `E.volumeGuide`, `E.isLift`, rep maxes in `records`, and on the context `liftTrend`, `strengthSummary`, `sessionZones`, `week`, `trainingWeeks`, `weekGoal`, `muscleVolume`, `cardioFitness`. The exercise library has 70 moves with equipment and timed flags.
- Train tab: Today card, schedule with week stats, Progress (Strength and Cardio fitness cards), training load, and one library list (history, weekly plan, exercises, muscles, routines). The routine carousel and the Recent card are gone; routines live in the *Choose a workout* sheet, ranked by how ready their muscles are.
- New pages `strength` and `cardio`; new sheets `chooseWorkout` and `restPicker`; new chart `Charts.stackBars`.
- Logger, summary, exercise, muscles, load and plan pages updated as listed. The weekly goal is edited on the Weekly plan page.

Left for later: the Today tab's ring labels are still 10 px (outside the fitness sections), and progress labels for habits (CLAUDE.md next step 2) can reuse `E.trendFit`.
