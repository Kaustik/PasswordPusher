#!/usr/bin/env bash

# Bash version check.
if [ "$(echo "$BASH_VERSION" |cut -b1)" -lt 4 ]; then
	if [ ! -x /usr/local/bin/bash ]; then
		echo "Please install bash version 4 or higher."
		exit 1
	fi

	if [ "$(/usr/local/bin/bash -c 'echo "$BASH_VERSION" |cut -b1')" -lt 4 ]; then
		echo "Please install bash version 4 or higher."
		exit 1
	fi

	exec /usr/local/bin/bash "$0" "$@"
fi

# Check for specified executable.
function require {
	local bin="$1"

	if ! hash "$bin" 2>/dev/null; then
		echo "Please install $bin"
		exit 1
	fi
}

# D'uh...
function help {
	[[ -n "$1" ]] && echo -e "$1\n"

	cat <<EOF

Usage: $0 [--options] [password]

OPTIONS:
	--gen   <length> Generate password N characters long
	--days  <days>   Number of days before link expires (default: 1)
	--views <views>  Number of views allowed before link expires (default: 2)

Examples:
	$0 LongDifficultPassword
	$0 "Password with spaces"
	$0 'PasswordWithDollar\$ign'
	$0 --days 3 --views 1 --gen 32

EOF

	exit 1
}


require "jq"
require "curl"
require "openssl"

base_url="https://pwpush.allevi.se"
#base_url="http://yourls1.kaustik.tech:5000"

# Parse command options and arguments from input.
declare -A opts
declare -a args
while (("$#")); do
	[[ $1 == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"
	case "$1" in
		--gen)
			opts[gen]="$2"
			shift 2
			;;
		--days)
			opts[days]="$2"
			shift 2
			;;
		--views)
			opts[views]="$2"
			shift 2
			;;
		--help)
			help
			;;
		--) # end argument parsing
			shift
			break
			;;
		-*) # unsupported flags
			echo "Error: Unsupported flag $1" >&2
			exit 1
			;;
		*) # preserve positional arguments in array
			args+=("$1")
			shift
			;;
		esac
done

# Set option defaults if not provided.
[[ -z "${opts[days]}" ]] && opts[days]=1
[[ -z "${opts[views]}" ]] && opts[views]=2

# Input sanity checks.
[[ ! ${opts[days]} =~ ^[0-9]+$ ]] && help "Days must be a digit"
[[ ! ${opts[views]} =~ ^[0-9]+$ ]] && help "Views must be a digit"
[[ "${opts[days]}" -ge 7 ]] && help "Maximum allowed expiration is 7 days"
[[ "${opts[views]}" -ge 100 ]] && help "Maximum allowed views are 100"
[[ "${#args[@]}" -gt 1 ]] && help "Passwords with spaces must be enclosed in quotes"
[[ -z "${opts[gen]}" ]] && [[ -z ${args[0]} ]] && help "Must either provide password or --gen option"
[[ -n "${opts[gen]}" ]] && [[ ! ${opts[gen]} =~ ^[0-9]+$ ]] && help "Password length must be a digit"


# If password was specified, use it, otherwise generate one with specified length.
if [ -z "${opts[gen]}" ]; then
	passwd="${args[0]}"
else
	rand_passwd=""
	special_chars=".-_+=/"

	pos=1
	next_rand=$((pos + $((6 + $((RANDOM %5)) )) ))
	while read -r -n1 char; do
		[[ -z "$char" ]] && continue

		if [[ ! $char =~ [A-Za-z0-9] ]]; then
			next_rand=$((pos + $((6 + $((RANDOM %5)) )) ))
			rand_passwd+="${special_chars:$((RANDOM % ${#special_chars})):1}"

			continue
		fi

		if [ "$pos" -ne "$next_rand" ]; then
			rand_passwd+="$char"
		else
			next_rand=$((pos + $((6 + $((RANDOM %5)) )) ))
			rand_passwd+="${special_chars:$((RANDOM % ${#special_chars})):1}"
		fi


		: $((pos++))
	done < <(openssl rand -base64 "${opts[gen]}" |xargs |tr -d ' ' |head -c "${opts[gen]}")

	passwd="$rand_passwd"
fi

# Push password to server.
readarray -t out < <(curl -w '\n%{http_code}' -s \
	--data-urlencode "password[payload]=${passwd}" \
	--data-urlencode "password[expire_after_days]=${opts[days]}" \
	--data-urlencode "password[expire_after_views]=${opts[views]}" "$base_url/p.json")

# Print full JSON output and exit if HTTP response wasn't 201.
if [ "${out[-1]}" -ne "201" ]; then
	echo -e "Failed to push password\n"
	printf '%s\n' "${out[@]::${#out[@]}-1}" |jq

	exit 2
fi

# If we got this far, all went well, and we print link.
link=$(printf "%s\n" "${out[@]::${#out[@]}-1}" |jq -r '.url_token')

echo -e "\nPassword: $passwd"
echo "Password link: $base_url/p/$link"
echo -e "\nThis link expires in ${opts[days]} days or ${opts[views]} views, whichever comes first."



