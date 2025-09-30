# mac-diskspace-guard
A launchagent and script to check for disk space running out and take remedial action 

# diskspace-guard.sh
Save this to: ~/bin/diskspace_guard.sh (or another path you like; just keep it consistent with the plist).

# Launch agent
com.craig.diskspace-guard.plist
Save this to: ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
If you saved the script somewhere else, update the ProgramArguments path accordingly.

# Install and load
# 1) Put the files in place (if you haven’t already)
mkdir -p ~/Library/LaunchAgents

# (Save the plist to ~/Library/LaunchAgents and the script to ~/bin)

# 2) Load the agent
launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.craig.diskspace-guard.plist

# 3) (Optional) Kick it right now for a test
bash -lc '~/bin/diskspace_guard.sh --threshold-gb 9999 --percent-free 101'

You should see a macOS notification and a log entry in ~/Library/Logs/diskspace-guard.log. Then revert your thresholds in the plist (or just wait for the next scheduled run with the normal values).

# Tuning & notes

Change thresholds: Edit the plist line with --threshold-gb and/or --percent-free, then launchctl unload + load again.

Disable any cleanup step: Set the corresponding RUN_…=0 env var at the top of the script (or add them into the ProgramArguments command like RUN_CLEANMYMAC=0 ~/bin/diskspace_guard.sh …).

No sudo prompts: LaunchAgents can’t use sudo. Everything here runs as your user and is safe.

Time Machine thinning: Only happens if tmutil is available. It won’t touch your external backup drive — it only trims local snapshots.

CleanMyMac X run: The --scan --clean args are best-effort; if your build doesn’t support them, the app is still opened to let its own background agent do its thing. If you want, I can swap this to an AppleScript that tells CleanMyMac X to start Smart Scan directly.
