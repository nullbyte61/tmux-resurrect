# Floating panes (tmux 3.6+)
#
# tmux appends every floating pane to #{window_layout} as an extra child of
# the root cell, and usually once more in a trailing "<...>" section:
#
#   232x63,0,0{116x63,0,0,0,115x63,117,0,1,83x41,66,7,2}<83x41,66,7,2>
#
# While a floating pane is zoomed the "<...>" section is omitted, but the
# extra child is still there. select-layout rejects both forms, and it also
# rejects the layout without the floating cells while floating panes are
# present. Floating panes are therefore skipped while panes are created, the
# layout is applied without them, and they are recreated afterwards from the
# geometry in the layout.
#
# Tiled children fill the root cell exactly, so every child that follows once
# the root is full is a floating pane. Floating panes always have the highest
# pane indexes in a window, in the same order as their cells, so no extra data
# needs to be saved: the layout alone identifies them.

layout_cell_regex='[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+'

# Layout without its checksum and without the "<...>" section.
_layout_body() {
	local layout="$1"
	layout="${layout%%<*}"
	echo "${layout#*,}"
}

# Prints the direct children of the root cell, one per line.
_layout_root_children() {
	local body="$1"
	local inner="${body#*[\[\{]}"
	inner="${inner%?}"
	local depth=0 child="" char i
	for ((i = 0; i < ${#inner}; i++)); do
		char="${inner:i:1}"
		case "$char" in
			'['|'{') depth=$((depth + 1)) ;;
			']'|'}') depth=$((depth - 1)) ;;
		esac
		if [ "$char" = "," ] && [ "$depth" -eq 0 ] && [[ "${inner:i+1}" =~ ^[0-9]+x ]]; then
			echo "$child"
			child=""
		else
			child="${child}${char}"
		fi
	done
	[ -n "$child" ] && echo "$child"
}

# Prints the floating pane cells of a layout, one per line, in pane index order.
layout_floating_cells() {
	local body="$(_layout_body "$1")"
	if ! [[ "$body" =~ ^([0-9]+)x([0-9]+),[0-9]+,[0-9]+([\[\{]) ]]; then
		return # a single pane, no container
	fi
	local root_size="${BASH_REMATCH[1]}"
	[ "${BASH_REMATCH[3]}" = "[" ] && root_size="${BASH_REMATCH[2]}"
	local container="${BASH_REMATCH[3]}"
	local filled=-1 child width height
	while read child; do
		if [ "$filled" -ge "$root_size" ]; then
			echo "$child"
			continue
		fi
		IFS='x,' read width height _ <<< "$child"
		if [ "$container" = "[" ]; then
			filled=$((filled + height + 1))
		else
			filled=$((filled + width + 1))
		fi
	done < <(_layout_root_children "$body")
}

layout_floating_count() {
	layout_floating_cells "$1" | wc -l | sed 's/ //g'
}

# Same algorithm as layout_checksum() in tmux's layout-custom.c.
layout_checksum() {
	local layout="$1"
	local csum=0
	local char i
	for ((i = 0; i < ${#layout}; i++)); do
		printf -v char '%d' "'${layout:i:1}"
		csum=$(( ((csum >> 1) + ((csum & 1) << 15) + char) & 0xffff ))
	done
	printf '%04x' "$csum"
}

# Prints the layout with floating panes removed and the checksum recomputed.
# Layouts without floating panes are printed unchanged.
layout_without_floating_panes() {
	local layout="$1"
	local floating_count="$(layout_floating_count "$layout")"
	if [ "$floating_count" -eq 0 ]; then
		echo "$layout"
		return
	fi
	local body="$(_layout_body "$layout")"
	local suffix="$(layout_floating_cells "$layout" | tr '\n' ',' | sed 's/,$//')"
	local closing="${body: -1}"
	local inner="${body%?}"
	body="${inner%,$suffix}${closing}"
	# a root container left with a single pane collapses to that pane
	if [[ "$body" =~ ^[0-9]+x[0-9]+,[0-9]+,[0-9]+[\[\{](${layout_cell_regex})[]}]$ ]]; then
		body="${BASH_REMATCH[1]}"
	fi
	echo "$(layout_checksum "$body"),${body}"
}
