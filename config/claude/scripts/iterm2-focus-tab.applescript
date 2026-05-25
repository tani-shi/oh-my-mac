-- Bring the iTerm2 tab matching the given session id to the foreground.
-- Usage: osascript iterm2-focus-tab.applescript <ITERM_SESSION_ID>

on run argv
	if (count of argv) < 1 then return
	set targetId to item 1 of argv
	tell application "iTerm2"
		repeat with w in windows
			repeat with t in tabs of w
				repeat with s in sessions of t
					if (id of s as string) is targetId then
						tell w to select
						tell t to select
						activate
						return
					end if
				end repeat
			end repeat
		end repeat
	end tell
end run
