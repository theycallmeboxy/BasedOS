# screen.sh: BasedOS's screens on stock, for what runs from stock's Ports (BasedOS's menu there,
# and setup from a setup card: basedos-setup.sh --screen). Sourced, with UI set to the folder that
# holds this file and BasedOS's two screen programs (basedos-splash, basedos-keys), copied there
# from BasedOS's system layer by the Ports file that started it.
#
# They draw on the framebuffer, as in BasedOS's maintenance menu. Stock's sway owns the display
# while it runs, so screen_on stops stock's frontend (sway and EmulationStation) and screen_off
# starts it again. What stops the frontend can't be its child (stopping it stops what it
# started), so the Ports file runs this as a service of its own (systemd-run).
#
# Every name here starts with ui_ or is a function's: the scripts that source it have their own
# short names (_a, _p, ...), and shell variables are all global.
SPLASH_INFO=/run/basedos/splash
# The pad's codes (BasedOS's button_code); UI_ names, as the scripts have their own A and B.
UI_A=305 UI_B=304 UI_X=307 UI_Y=308 UI_UP=544 UI_DOWN=545
TAB=$(printf '\t')

# screen <status> <line>...: the whole screen: its lines, in basedos-splash's kinds ("!" first a
# heading, "!> " the selected entry, "   " an entry, key<TAB>value, an empty one a half-line
# gap), and the status along the bottom.
screen() {
	ui_st=$1; shift
	printf '%s\n' "$@" > $SPLASH_INFO
	"$UI/basedos-splash" "$ui_st" >/dev/null 2>&1
}

ui_stopped=""
# screen_on: stock's frontend stopped, so the panel shows the framebuffer.
screen_on() {
	mkdir -p /run/basedos
	if systemctl -q is-active essway 2>/dev/null || systemctl -q is-active sway 2>/dev/null; then
		systemctl stop essway sway 2>/dev/null
		ui_stopped=1
		# The text console clears the screen when the seat comes back to it, just after: that
		# waited for, then the console kept off the screen (basedos-splash --console).
		"$UI/basedos-splash" --console graphics
	fi
}
# screen_off: stock's frontend started again, if screen_on stopped it.
screen_off() {
	unlisten
	if [ -n "$ui_stopped" ]; then
		"$UI/basedos-splash" --console text
		systemctl start sway essway 2>/dev/null
	fi
	ui_stopped=""
}

# Keys come from one basedos-keys --watch through a FIFO on fd 5, as in BasedOS's menu: every tap
# is read in order. listen starts a fresh reader, so presses from before it don't count.
ui_kw="" ui_keys=/run/basedos/stock-keys
listen() {
	[ -n "$ui_kw" ] && unlisten
	rm -f $ui_keys; mkfifo $ui_keys
	"$UI/basedos-keys" --watch > $ui_keys 2>/dev/null & ui_kw=$!
	exec 5< $ui_keys
}
unlisten() {
	[ -n "$ui_kw" ] || return 0
	kill $ui_kw 2>/dev/null; wait $ui_kw 2>/dev/null
	exec 5<&-
	rm -f $ui_keys
	ui_kw=""
}
# key [<s>]: the code of the next key pressed (since listen), or nothing if none within <s>
# seconds (none or 0: wait for one).
key() {
	ui_k=""
	if [ "${1:-0}" -gt 0 ]; then read -r -t "$1" ui_k <&5
	else read -r ui_k <&5 || sleep 1; fi
	echo "$ui_k"
}

# message <status> <line>...: a screen until A or B is tapped.
message() {
	screen "$@"
	listen
	while :; do case "$(key)" in "$UI_A"|"$UI_B") break ;; esac; done
	unlisten
}

# pick <title> <line>... - <label>...: a list to choose from, under the title and the lines before
# the "-" argument. Up/Down choose, A picks. PICKED is the chosen label's number (from 1); 1 (and
# PICKED empty) when B goes back.
pick() {
	ui_t=$1; shift
	ui_pre=""
	while [ $# -gt 0 ] && [ "$1" != - ]; do ui_pre="$ui_pre$1
"; shift; done
	shift
	ui_n=$# ui_s=1 PICKED=""
	listen
	while :; do
		{
			echo "!$ui_t"
			printf '%s' "$ui_pre"
			ui_i=0
			for ui_l in "$@"; do
				ui_i=$((ui_i + 1))
				if [ $ui_i = $ui_s ]; then echo "!> $ui_l"; else echo "   $ui_l"; fi
			done
		} > $SPLASH_INFO
		"$UI/basedos-splash" "Up/Down: choose    A: select    B: back" >/dev/null 2>&1
		case "$(key)" in
		"$UI_UP") ui_s=$((ui_s > 1 ? ui_s - 1 : ui_n)) ;;
		"$UI_DOWN") ui_s=$((ui_s < ui_n ? ui_s + 1 : 1)) ;;
		"$UI_A") PICKED=$ui_s; unlisten; return 0 ;;
		"$UI_B") unlisten; return 1 ;;
		esac
	done
}

# confirm <question> <line>...: 0 once A, B, X, Y are tapped in that order; 1 on any other button,
# or 10 s without one (as BasedOS's maintenance menu). The lines say what happens; the status
# shows how far it's got.
confirm() {
	ui_q=$1; shift
	ui_i=0
	listen
	while :; do
		case $ui_i in 0) ui_tap="_ _ _ _" ;; 1) ui_tap="A _ _ _" ;; 2) ui_tap="A B _ _" ;; *) ui_tap="A B X _" ;; esac
		screen "Tapped: $ui_tap" "!$ui_q" "$@" "" "Tap A, B, X, Y to confirm." "Any other button cancels."
		case "$ui_i:$(key 10)" in
		0:$UI_A|1:$UI_B|2:$UI_X) ui_i=$((ui_i + 1)) ;;
		3:$UI_Y) unlisten; return 0 ;;
		*) unlisten; return 1 ;;
		esac
	done
}
