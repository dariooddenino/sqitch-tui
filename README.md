# SQITCH TUI

A simple tui to manage Sqitch migrations while working on different git branches.

Currently the only functionality is to migrate in '--log-only' mode by pressing 'w' over a migration.

Currently there are a lot of assumptions happening:
- sqitch is in path
- git is in path
- sqitch has been initialized
- the sqitch files are under the 'migrations' folder


## TODO
- [ ] Parse sqitch config
- [ ] Status bar with async messages
- [ ] Confirm modals
- [ ] Commit migrations
- [ ] Nicer styling
- [ ] Open migration files in side panel
- [ ] Make the code robust to errors
- [ ] Diff of migration files at different branches
- [ ] git as a dependency instead of calling the executable
- [ ] Improve sqitch interactions (can it be a dep?)
- [ ] Fork vaxis for the scrollview fix and remove the copied files
- [ ] Memory profiling, the arena is covering a lot of bad stuff
