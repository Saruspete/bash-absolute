#!/usr/bin/env bash

export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$PATH"
export PS4=' (${BASH_SOURCE##*/}::${FUNCNAME[0]:-main}::$LINENO)  '

for __inputfile in "$@"; do

	echo >&2 "Processing '$__inputfile'"

	echo >&2 "== Syntax validation..."
	bash -n "$__inputfile"
	r=$?
	echo >&2 "== Validation return code: $r"


	(
		typeset __dstfile="$__inputfile.fixed"
		typeset -a __binaries=
		cp "$__inputfile" "$__dstfile"
		echo >&2 "==Processing file '$__inputfile' to '$__dstfile'"

		# Avoid debug display
		exec 99>/dev/null
		export BASH_XTRACEFD=99

		# Processing function
		function checkFunc {
			set +x
			typeset srcfile="${BASH_SOURCE[1]}"
			typeset srcline="${BASH_LINENO[0]}"
			typeset srccmd="${BASH_COMMAND%% *}"
			typeset abstype="$(type -t "$srccmd" 2>/dev/null)"

			# Unknown command: fail
			if [[ -z "$abstype" ]] && ! [[ "$srccmd" =~ [a-zA-Z0-9_]+= ]]; then
				echo >&2 "!! Error: Unknown command: $srccmd (from '$BASH_COMMAND' in $srcfile:$srcline')"
				#exit 1
			fi

			typeset abscmd="$(type -p "$srccmd")"

			# Absolute file: Replace the line in script
			if [[ -n "$abscmd" ]]; then
				echo >&2 "== DEBUG: Replacing '$srccmd' to '$abscmd'"
				sed -Ee "${srcline}s#(^|[\t ]|\(|\`)+$srccmd#\1$abscmd#" -i "$__dstfile"
				__binaries+=("$abscmd")
				echo "$abscmd" >> "$__dstfile.bins"
			fi

			set -x
		}

		# Enable debugging
		trap checkFunc DEBUG
		shopt -s extdebug
		set -x

		# Source the file for processing
		source "$__inputfile"

		# Disable debugging
		set +x
		trap '' DEBUG

		# Add the listing at start
		mapfile __binaries < <(cat $__dstfile.bins|sort -u)
		typeset __binaries_str="$(typeset -p __binaries)"
		__binaries_str="${__binaries_str//|/\\|}"
		__binaries_str="${__binaries_str//\\n/}"

		typeset __binaries_chk='for s in ${__binaries[@]}; do [[ -x "$s" ]] || err+="$s"; done; [[ -n "$err" ]] && { echo >&2 "Missing binaries $err"; exit 1;}'
		__binaries_chk="${__binaries_chk//|/\\|}"
		__binaries_chk="${__binaries_chk//&/\\&}"
		__binaries_chk="${__binaries_chk//\{/\\{}"
		__binaries_chk="${__binaries_chk//\}/\}}"

		sed -i "$__dstfile" -Ee '2s|(.+)|# Check added by bash-absolute\n\1|'
		sed -i "$__dstfile" -Ee '3s|(.+)|'"${__binaries_str}"'\n\1|'
		sed -i "$__dstfile" -Ee '4s|(.+)|'"${__binaries_chk}"'\n\1|'
	)

	echo >&2 "== Done with '$__inputfile'. Ret: $?"
done

