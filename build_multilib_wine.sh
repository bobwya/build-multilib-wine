#!/bin/bash


#### General Helper Functions Definition Block ####

# cleanup()
function cleanup()
{
	local PGID

	sleep 1
	if [[ -p "${__FIFO_LOG_PIPE}" ]]; then
		rm "${__FIFO_LOG_PIPE}" &>/dev/null
	fi
	schroot -e -c "${SESSION_WINE_INITIALISE}" &>/dev/null
	schroot -e -c "${SESSION_WINE32}" &>/dev/null
	schroot -e -c "${SESSION_WINE64}" &>/dev/null
	if ((LOGGING)) && [[ ! -z "${COMPRESSOR_CMD}" && ! -z "${LOG}" && -f "${LOG}" ]]; then
		${COMPRESSOR_CMD} "${LOG}"
	fi
	PGID="$( ps -o pgid "${SCRIPT_PID}" | awk '{ if ($1 ~ /[[:digit:]]+/) print $1 }' )"
	kill -9 -"${PGID}" &>/dev/null
}

# trap_exit()
function trap_exit()
{
	# shellcheck disable=SC2173
	trap '' ABRT INT QUIT TERM KILL STOP
	printf "\\n%s${FUNCNAME[ 0 ]} ()%s ... \\n" "${TTYRED_BOLD}" "${TTYRESET}"
	cleanup
	exit
}

# die()
#   1>  : Error Message
#   2>  : Error Code (default: 1)
#	3>  : Display usage (default: 0)
function die()
{
	local error_message="${1}"
	local error_code=${2:-1}
	local usage=${3:-0}
	local function_call="${FUNCNAME[ 1 ]}"

	# shellcheck disable=SC2173
	trap '' ABRT INT QUIT TERM KILL STOP
	[[ -p "${__FIFO_LOG_PIPE}" ]] && printf "%s" "${TTYRESET}"
	printf "%s" "${error_message}" | awk \
						-vttycyan_bold="${TTYCYAN_BOLD}" -vttyred_bold="${TTYRED_BOLD}" -vttypurple_bold="${TTYPURPLE_BOLD}" \
						-vttygreen_bold="${TTYGREEN_BOLD}" -vttyreset="${TTYRESET}" \
						-vscript_name="${SCRIPT_NAME}" -vfunction_call="${function_call}"	-F'"' \
		'BEGIN{
			printf("%s%s%s : %s%s ()%s : ", ttygreen_bold, script_name, ttyreset, ttypurple_bold, function_call, ttyreset)
		}
		{
			for (i=1; i<=NF; ++i)
			{
				if (i%2 == 1)
					printf("%s%s%s", ttyred_bold, $i, ttyreset)
				else
					printf("%s\"%s%s%s\"", ttyreset, ttycyan_bold, $i, ttyreset)
			}
			printf("\n")
		}' >&2
		((usage)) 	&& usage_information >&2
	cleanup
	exit "${error_code}"
}

# setup_tty_colours()
#  >1  Enable colour support for console (1/0)
function setup_tty_colours()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local enable_colour="${1}" output
	if ((enable_colour)); then
		output="/dev/stdout"
	else
		output="/dev/null"
	fi

	export	TTYRED
	export	TTYGREEN
	export	TTYYELLOW
	export	TTYBLUE
	export	TTYPURPLE
	export	TTYCYAN
	export	TTYWHITE
	export	TTYBOLD
	export	TTYRESET
	export	TTYRED_BOLD
	export	TTYGREEN_BOLD
	export	TTYYELLOW_BOLD
	export	TTYBLUE_BOLD
	export	TTYPURPLE_BOLD
	export	TTYCYAN_BOLD
	export	TTYWHITE_BOLD
	TTYRED="$( tput setaf 1 >${output} )"
	TTYGREEN="$( tput setaf 2 >${output} )"
	TTYYELLOW="$( tput setaf 3 >${output} )"
	TTYBLUE="$( tput setaf 4 >${output} )"
	TTYPURPLE="$( tput setaf 5 >${output} )"
	TTYCYAN="$( tput setaf 6 >${output} )"
	TTYWHITE="$( tput setaf 7 >${output} )"
	TTYBOLD="$( tput bold >${output} )"
	TTYRESET="$( tput sgr0 >${output} )"
	TTYRED_BOLD="${TTYRED}${TTYBOLD}"
	TTYGREEN_BOLD="${TTYGREEN}${TTYBOLD}"
	TTYYELLOW_BOLD="${TTYYELLOW}${TTYBOLD}"
	TTYBLUE_BOLD="${TTYBLUE}${TTYBOLD}"
	TTYPURPLE_BOLD="${TTYPURPLE}${TTYBOLD}"
	TTYCYAN_BOLD="${TTYCYAN}${TTYBOLD}"
	TTYWHITE_BOLD="${TTYWHITE}${TTYBOLD}"
}

# pushd_wrapper()
#  >1	directory to pass to pushd
function pushd_wrapper()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local directory="${1}"

	printf "%s" "${TTYBLUE_BOLD}"
	pushd "${directory}" || die "pushd \"${directory}\" failed" $?
	printf "%s" "${TTYRESET}"
}

# popd_wrapper()
function popd_wrapper()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	printf "%s" "${TTYBLUE_BOLD}"
	popd || die "popd failed" $?
	printf "%s" "${TTYRESET}"
}

# set_wine_git_tag()
# ( 1>	: fail on error (1) )
function set_wine_git_tag()
{
	(($# <= 1)) || die "Invalid parameter count: ${#} (0-1)"

	local fail_on_error="${1:-1}"

	# Setup Wine version to build
	if [[ ! -z "${WINE_BRANCH}" ]]; then
		if [[ ! "${WINE_BRANCH}" =~ ^(master|origin/master|origin/stable)$ ]]; then
			((fail_on_error)) && die "invalid WINE_BRANCH=\"${WINE_BRANCH}\" specified"
		fi
		export	__WINE_GIT_TAG="${WINE_BRANCH}"
		unset -v WINE_COMMIT WINE_VERSION
	elif [[ ! -z "${WINE_COMMIT}" ]]; then
		if [[ ! "${WINE_BRANCH}" =~ ${SHA1_REGEXP} ]]; then
			((fail_on_error)) && die "invalid WINE_COMMIT=\"${WINE_BRANCH}\" specified (SHA1 commit hash)"
		fi
		export	__WINE_GIT_TAG="${WINE_COMMIT}"
		unset -v WINE_VERSION
	else
		if [[ -z "${WINE_VERSION}" ]]; then
			((fail_on_error)) && die "No WINE_VERSION=\"${WINE_VERSION}\" specified"
		elif [[ ! "${WINE_VERSION}" =~ ${VERSION_REGEXP} ]]; then
			((fail_on_error)) && die "invalid WINE_VERSION=\"${WINE_VERSION}\" specified"
		fi
		export	__WINE_GIT_TAG="${WINE_PREFIX}${WINE_VERSION}"
	fi
}

# set_wine_staging_git_tag()
# ( 1>	: fail on error (1) )
function set_wine_staging_git_tag()
{
	(($# <= 1)) || die "Invalid parameter count: ${#} (0-1)"

	local fail_on_error="${1:-1}"

	# Setup Wine-Staging version to build
	if [[ ! -z "${WINE_STAGING_BRANCH}" ]]; then
		if [[ ! "${WINE_STAGING_BRANCH}" =~ ^(master|latest-release|origin/master|origin/stable)$ ]]; then
			((fail_on_error)) && die "invalid WINE_STAGING_BRANCH=\"${WINE_STAGING_BRANCH}\" specified"
		fi
		export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_BRANCH}"
		unset -v WINE_STAGING_COMMIT WINE_VERSION
	elif [[ ! -z "${WINE_STAGING_COMMIT}" ]]; then
		if [[ ! "${WINE_STAGING_BRANCH}" =~ ${SHA1_REGEXP} ]]; then
			((fail_on_error)) && die "invalid WINE_STAGING_COMMIT=\"${WINE_STAGING_BRANCH}\" specified (SHA1 commit hash)"
		fi
		export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_COMMIT}"
		unset -v WINE_VERSION
	else
		if [[ ! "${WINE_VERSION}" =~ ${VERSION_REGEXP} ]]; then
			((fail_on_error)) && die "invalid WINE_VERSION=\"${WINE_VERSION}\" specified"
		fi
		if [[ "${WINE_VERSION}" =~ 1\.8\.[1-9]*[0-9] ]]; then
			export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_PREFIX}${WINE_VERSION}${WINE_STAGING_SUFFIX}"
		else
			export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_PREFIX}${WINE_VERSION}"
		fi
		export	__WINE_GIT_TAG="${WINE_PREFIX}${WINE_VERSION}"
	fi
}

# parse_boolean_option()
#	  1>	boolean option string (value)
#   ( 2<	option variable to set to value )
function parse_boolean_option()
{
	(((1 <= $#) && ($# <= 2))) || die "Invalid parameter count: ${#} (1-2)"

	local	__option="${1}" __option_name_reference="${2}"
	local	__valid_options="([1|0|yes|no|true|false])"
	local	__option_value

	if [[ -z "${__option}" ]]; then
		die "no ${__option_name_reference,,} option value specified ${__valid_options}" "" 1
	fi
	case "${__option}" in
		0|[Nn][Oo]|[Nn]|[Ff][Aa][Ll][Ss][Ee]|[Ff])
			__option_value=0;;
		1|[Yy][Ee][Ss]|[Yy]|[Tt][Rr][Uu][Ee]|[Tt])
			__option_value=1;;
		*)
			local __option_name="${__option_name_reference,,}"
			die "unknown ${__option_name//_/-} option value specified: \"${__option}\" ${__valid_options}" "" 1;;
	esac

	if [[ -z "${__option_name_reference}" ]]; then
		echo "${__option_value}"
	elif [[ "${__option_name_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
		declare -n option_name="${__option_name_reference}"
		# shellcheck disable=SC2034
		option_name="${__option_value}"
	else
		die "Parameter (3): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__option_name_reference}'"
	fi
}

# set_log_compression()
#   1>	: compressor executable (or file extension)
function set_log_compression()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local compressor="${1}"
	case "${compressor}" in
		bzip2|bz2)
			command -v bzip2 &>/dev/null || die "bzip2 log compression unsupported - bzip2 compressor not detected"
			export COMPRESSOR_CMD="bzip2 -fq -9"
			;;
		gzip|gz)
			command -v gzip &>/dev/null || die "gzip log compression unsupported - gzip compressor not installed"
			export COMPRESSOR_CMD="gzip -fq -9"
			;;
		lzma)
			if command -v lzma &>/dev/null; then
				export COMPRESSOR_CMD="lzma -fq"
			elif command -v xz &>/dev/null; then
				export COMPRESSOR_CMD="xz --format=lzma -fq"
			else
				die "lzma log compression unsupported - neither of the lzma or xz compressors are installed"
			fi
			;;
		lzop)
			command -v lzop &>/dev/null || die "lzop log compression unsupported - lzop compressor not installed"
			export COMPRESSOR_CMD="lzop -fqU -9"
			;;
		lz4)
			command -v lz4 &>/dev/null || die "lz4 log compression unsupported - lz4 compressor not installed"
			export COMPRESSOR_CMD="lz4 -cfq -BD -9"
			;;
		xz)
			command -v xz &>/dev/null || die "xz log compression unsupported - xz compressor not installed"
			export COMPRESSOR_CMD="xz -fq"
			;;
		cat|none|no|disabled)
			export COMPRESSOR_CMD=""
			;;
		*)
			die "${compressor} compressor is unsupported"
			;;
	esac
}

# logging_thread()
function logging_thread()
{
	# shellcheck disable=SC2173
	trap "cleanup" ABRT INT QUIT TERM KILL STOP
	while [[ -p "${__FIFO_LOG_PIPE}" ]]; do
		((LOGGING))		&& cat < "${__FIFO_LOG_PIPE}" | tee -a "${LOG}"
		((LOGGING))		|| cat < "${__FIFO_LOG_PIPE}"
	done
	printf "\\n%sLogging completed!!%s\\n" "${TTYYELLOW_BOLD}" "${TTYRESET}"
}

# setup_logging()
#	1>	: main script command being executed
function setup_logging()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local command="${1}"
	mkfifo -m=600 "${__FIFO_LOG_PIPE}" &>/dev/null || die "mkfifo \"${__FIFO_LOG_PIPE}\" failed" $?
	# Use a FIFO to compress all log file output in a background shell
	if ((LOGGING)); then
		# Make Log directory
		LOG=$(date --iso-8601=seconds)
		case "${command}" in
			runtime)
				export LOG="${LOG_DIRECTORY}/install-runtime_${LOG}.log";;
			setup)
				export LOG="${LOG_DIRECTORY}/chroot-setup_${LOG}.log";;
			upgrade)
				export LOG="${LOG_DIRECTORY}/chroot-upgrade_${LOG}.log";;
			build)
				if ((WINE_STAGING)); then
					export LOG="${LOG_DIRECTORY}/wine-staging-${WINE_STAGING_BRANCH:-${WINE_STAGING_COMMIT:-${WINE_VERSION}}}_${LOG}.log"
				else
					export LOG="${LOG_DIRECTORY}/wine-${WINE_BRANCH:-${WINE_COMMIT:-${WINE_VERSION}}}_${LOG}.log"
				fi;;
			*)
				die "Invalid command specified"
		esac
		[[ -d "${LOG_DIRECTORY}" ]] || mkdir -p "${LOG_DIRECTORY}" &>/dev/null
		rm "${LOG}" &>/dev/null
		printf "%s\\n" "${TTYCYAN_BOLD}Finished setting up FIFO logging using: ${TTYBLUE_BOLD}${LOG}${TTYRESET}"
	else
		printf "%s\\n" "${TTYCYAN_BOLD}Logging disabled${TTYRESET}"
	fi

	logging_thread &
	__LOGGING_PID=$!
}

# fetch_wine_staging_patchbin()
#	1>	: directory to download scripts to
function fetch_wine_staging_patchbin_script()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local __scripts_directory="${1}"
	if [[ ! -d "${__scripts_directory}" ]]; then
		die "Script download directory does not exist: \"${__scripts_directory}\""
	fi

	pushd_wrapper "${__scripts_directory}"
	wget -O "${WINE_STAGING_PATCHBIN_SCRIPT}" "${WINE_STAGING_BINPATCH_URL}" \
		|| die "wget failed: unable to download Wine Staging gitapply.sh script: \"${WINE_STAGING_BINPATCH_URL}\""
	sed -E -i "s/(\\.\\/)?gitapply(\\.sh)?/${WINE_STAGING_PATCHBIN_SCRIPT}/g" "${WINE_STAGING_PATCHBIN_SCRIPT}" \
		|| die "sed failed: patching Wine Staging gitapply.sh (${WINE_STAGING_PATCHBIN_SCRIPT}) script"
	chmod +x "${WINE_STAGING_PATCHBIN_SCRIPT}" \
		|| die "chmod +x failed"
	popd_wrapper
}

# check_package_dependencies()
function check_package_dependencies()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	local -a array_executables=( "awk" "bzip2" "debootstrap" "git" "lsb_release" "mkfifo" "md5sum" "schroot" "sed" "wget" )
	local executable

	for executable in "${array_executables[@]}"; do
		command -v "${executable}" &>/dev/null &&	continue

		case "${executable}" in
			md5sum|mkfifo)
				package_list="${package_list} coreutils";;
			*)
				package_list="${package_list} ${executable}";;
		esac
	done
	if [[ ! -z "${package_list}" ]]; then
		printf "sudo apt-get install %s${package_list}%s\\n" "${TTYCYAN}" "${TTYRESET}" >&2
	elif ! command -v netselect &>/dev/null; then
		package_list="${package_list} netselect"
		printf "Please manually install the %snetselect%s package from this Debian repository:\\n" \
				"${TTYCYAN_BOLD}" "${TTYRESET}" >&2
		printf "  %shttps://packages.debian.org/stretch/amd64/netselect/download%s\\n\\n" \
				"${TTYBLUE_BOLD}" "${TTYRESET}" >&2
		printf "For example to install the %snetselect%s %sdeb%s package file from the main Debian USA mirror use:\\n" \
				"${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYCYAN}" "${TTYRESET}" >&2
		printf "  URL='%shttp://ftp.debian.org/debian/pool/main/n/netselect/netselect_0.3.ds1-28+b1_amd64.deb%s' %s;%s\\n" \
				"${TTYBLUE_BOLD}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" >&2
		printf "  FILE=\$(%smktemp%s) %s;%s %swget%s \"\${URL}\" -qO \"\${FILE}\" && %ssudo dpkg%s -i \"\${FILE}\" %s;%s %srm%s \"\${FILE}\"\\n\\n" \
				"${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" \
				"${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
	fi
	[[ -z "${package_list}" ]] || die "please install the (above) required package(s) and re-run this script"
}

# usage_information()
function usage_information()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	local indent=-2 col_width=-15 gopt_col_width=-20

	printf "Usage:\\n"
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] %ssetup-chroot%s\\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}"
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] %supgrade-chroot%s\\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}"
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] [%sBUILD-OPTION%s(s)] %ssrc-fetch | src-prepare | src-configure | src-compile | src-install%s\\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYYELLOW}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}"
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] [%sBUILD-OPTION%s(s)] %sbuild-all%s\\n\\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYYELLOW}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}"

	printf "Utility to build dual-architecture, multilib Wine on Ubuntu(tm).\\n"
	printf "Uses dual (32-bit and 64-bit) Chroot (schroot) Environments.\\n\\n"
	printf "Consecutive build phases can be selected, chained, and re-run.\\n\\n"

	printf "%scommand%s(s) :\\n" "${TTYCYAN_BOLD}" "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "generate-conf" "${TTYRESET}" ${indent} "" "Generate default \"${SCRIPT_CONFIG}\" configuration file."
	printf "%*s%s%*s%s%*s%s%s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "host-runtime" "${TTYRESET}" ${indent} "" "Install Wine runtime packages for host system (alternative to installing winehq-staging / winehq-vanilla packages)."
	printf "%*s%s%*s%s%*s%s%s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "setup-chroot" "${TTYRESET}" ${indent} "" "Setup 32-bit and 64-bit Chroot Environments."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "Install Ubuntu base development libraries for Wine"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "in the dual Chroot Environments. "
	printf "%*s%s%*s%s%*s%s%s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "upgrade-chroot" "${TTYRESET}" ${indent} "" "Upgrade Ubuntu base development libraries for Wine"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "in the dual Chroot Environments. "
	printf "%*s%s%*s%s%*s%s%s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "version" "${TTYRESET}" ${indent} "" "Display build version of ${SCRIPT_NAME} ."
	printf "\\n\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "(${SRC_FETCH})" "${TTYCYAN_BOLD}" ${col_width} "src-fetch" "${TTYRESET}" ${indent} "" "Run (Git) source fetch phase."
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "(${SRC_PREPARE})" "${TTYCYAN_BOLD}" ${col_width} "src-prepare" "${TTYRESET}" ${indent} "" "Run source preparation (patching) phase."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "If building Wine-Staging - the Staging patches will be"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "applied during this phase."
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "(${SRC_CONFIGURE})" "${TTYCYAN_BOLD}" ${col_width} "src-configure" "${TTYRESET}" ${indent} "" "Run source configuration phase."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "This phase is executed in the dual Chroot Environments."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "Phase includes a make clean operation (if required)."
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "(${SRC_COMPILE})" "${TTYCYAN_BOLD}" ${col_width} "src-compile" "${TTYRESET}" ${indent} "" "Run source compilation phase."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "This phase is executed in the dual Chroot Environments."
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "(${SRC_INSTALL})" "${TTYCYAN_BOLD}" ${col_width} "src-install" "${TTYRESET}" ${indent} "" "Run installation phase."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "This phase is executed in the dual Chroot Environments."

	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "(${SRC_FETCH})-(${SRC_INSTALL})" "${TTYCYAN_BOLD}" ${col_width} "build-all" "${TTYRESET}" ${indent} "" "Specifies that all phases (see above)"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "will be executed in a chain."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "Note: multiple phases can also be specified"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "individually and these will be chained together."
	printf "%sGLOBAL-OPTION%s :\\n" "${TTYGREEN}" "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--colour[=][y|n|yes|no] | -c[=][y|n|yes|no] " "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Enable/disable colourised console output. [default=no]"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--logging[=][y|n|yes|no]" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Enable/disable logging of operations.	 [default=yes]"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--log-compression[=][bzip2|gzip|lzma|lzop|none|lz4|xz]" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify (optional) log file compression.  [default=gzip]"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--log-directory" "${TTYRESET}" ${indent} "" "Specify directory in which log files will be created during build."
	printf "\\n"
	printf "%sRUNTIME-OPTION%s :\\n" "${TTYYELLOW}" "${TTYRESET}"
	printf "\\n"
		printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--base" "${TTYRESET}" ${indent} "" "Specify to only install base Wine runtime packages on host system (not recommended)."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--full" "${TTYRESET}" ${indent} "" "Specify to install full Wine runtime on host system [default]."
	printf "\\n"
	printf "%sBUILD-OPTION%s :\\n" "${TTYYELLOW}" "${TTYRESET}"
	printf "\\n"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-staging[=][y|n|yes|no]" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify whether to build Wine or Wine-Staging."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-branch[=]branch" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine Git branch to build."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-commit[=]SHA-1 commit hash" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine Git commit to build."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Use 40 character hexidecimal SHA-1 hash."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-staging-branch[=]branch" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine-Staging Git branch to build."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-staging-commit[=]SHA-1 commit hash" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine-Staging Git commit to build."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Use 40 character hexidecimal SHA-1 hash."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-version[=]numeric-version" "${TTYRESET}" ${indent} "" ""
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine (or Wine-Staging) version to build."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Use numeric version string (e.g. 1.9.20 1.8.5-rc1)"
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--build-directory" "${TTYRESET}" ${indent} "" "Specify build (binaries) target directory."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--patch-directory" "${TTYRESET}" ${indent} "" "Specify directory containing user patch files."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Can be specified more than once."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--source-directory" "${TTYRESET}" ${indent} "" "Specify directory to store source files."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Note: this can be specified more than once."
	printf "%*s%s%*s%s%*s%s\\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--prefix" "${TTYRESET}" ${indent} "" "Specify prefix directory for installation phase."
	printf "\\n"
}

# display_completion_message()
function display_completion_message()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	if [[ "${COMMAND}" == "runtime" ]]; then
		printf "\\n%s%s%s: %sInstall host-${COMMAND} has completed successfully%s ...\\n" \
			"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}"
	elif [[ "${COMMAND}" != "build" ]]; then
		printf "\\n%s%s%s: %sChroot-${COMMAND} has completed successfully%s ...\\n" \
			"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}"
	else
		local	-a build_phases=("" "src-fetch" "src-prepare" "src-configure" "src-compile" "src-install")

		local phases_completed=""
		local i count=0
		for (( i=SRC_FETCH ; i<=SRC_INSTALL ; ++i)); do
			((SUBCOMMANDS[i]))	|| continue

			phases_completed="${phases_completed},${build_phases[i]}"
			: $((++count))
		done
		((count==1)) && phases_completed="Build phase: ${phases_completed:1}; has completed successfully, "
		((count!=1)) && phases_completed="Build phases: ${phases_completed:1}; have completed successfully, "
		((WINE_STAGING))	|| local	wine_version="${__WINE_VERSION}"
		((WINE_STAGING))	&& local	wine_version="(Staging) ${__WINE_STAGING_VERSION}"
		printf "\\n%s%s%s: %s${phases_completed} for Wine ${wine_version}%s ...\\n" \
				"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}"
	fi
}

#### Build Helper Functions Definition Block ####

# fetch_extract_tarball()
#	1>	: directory to extract archive to (. = pwd)
#	2>	: tarball archive URL
function fetch_and_extract_tarball()
{
	(( ($# == 2) || ($# == 3) )) || die "Invalid parameter count: ${#} (2-3)"
	local __directory="${1:-.}" __download_url="${2}" __tarball
	if (($# == 3)); then
		__tarball="${3}"
	else
		__tarball="$(basename "${__download_url}")"
	fi
	[[ "${__directory}" != "." ]] && pushd_wrapper "${__directory}"
	wget -O "${__tarball}" "${__download_url}" || die "wget \"${__download_url}\" failed"
	tar xvfa "${__tarball}" || die "tar e(x)tract failed"
	rm "${__tarball}" || die "rm failed"
	[[ "${__directory}" != "." ]] && popd_wrapper
}

# create_main_directories()
#	1...N>	: array of directories to create
function create_main_directories()
{
	(($# >= 1)) || die "Invalid parameter count: ${#} (1-)"

	local -a directories_array=( "${@}" )
	local i
	for i in ${!directories_array[*]}; do
		[[ -d "${directories_array[i]}" ]] || continue

		mkdir -p "${directories_array[i]}" \
			|| die "mkdir -p \"${directories_array[i]}\" failed"
	done
}

# clean_source_directories()
#   1...N>  : array of source directories to wipe
clean_source_directories()
{
	(($# >= 1)) || die "Invalid parameter count: ${#} (1-)"

	local -a directories_array=( "${@}" )
	local i
	for i in ${!directories_array[*]}; do
		[[ -d "${directories_array[i]}" ]] || continue

		rm -rf "${directories_array[i]}" \
				|| die "rm -rf \"${directories_array[i]}\" failed"
	done
}

# clean_build_directories()
#   1...N>  : array of build directories to wipe the contents of
clean_build_directories()
{
	(($# >= 1)) || die "Invalid parameter count: ${#} (1-)"

	local -a directories_array=( "${@}" )
	local i
	for i in ${!directories_array[*]}; do
		if [[ -d "${directories_array[i]}" ]]; then
			rm -rf "${directories_array[i]:?}"/* \
				|| die "rm -rf \"${directories_array[i]}\"/* failed"
		else
			mkdir -p "${directories_array[i]}" \
				|| die "mkdir -p \"${directories_array[i]}\" failed"
		fi
	done
}

# git_clone()
# ( 1>  : Git directory )
#   2>  : Git repository URL
function git_clone()
{
	(((1 <= $#) && ($# <= 2))) || die "Invalid parameter count: ${#} (1-2)"

	# shellcheck disable=SC2124
	local git_directory="${SOURCE_ROOT}/${1}" git_repository_url="${@: -1:1}"

	if (($# == 1)); then
		git_directory="${git_repository_url##*/}"
		git_directory="${SOURCE_ROOT}/${git_directory%.*}"
	fi
	[[ -d "${git_directory}/.git" ]] && return 0

	printf "%s\\n" "${TTYCYAN_BOLD}Cloning \"${TTYBLUE_BOLD}${git_repository_url}${TTYRESET}\" into ${TTYBLUE_BOLD}${git_directory}${TTYRESET} ..."
	git clone "${git_repository_url}" \
		|| die "git clone \"${git_repository_url}\" failed (\"${1}\")" $?
}

# git_pull_and_checkout()
#   1>  : Git directory
#   2>  : Git commit, branch, or tag
function git_pull_and_checkout()
{
	(($# == 2)) || die "Invalid parameter count: ${#} (2)"

	local git_directory="${SOURCE_ROOT}/${1}" git_version="${2}"

	pushd_wrapper "${git_directory}"
	git clean -f -d -q || die "git clean -f -d -q failed (\"${1}\")" $?
	git reset --hard "master"  || die "git reset --hard \"master\" failed (\"${1}\")" $?
	git checkout "master" || die "git checkout \"master\" failed (\"${1}\")" $?
	git pull || die "git pull failed (\"${1}\")" $?
	git checkout "${git_version}" || die "git checkout \"${git_version}\" failed (\"${1}\")" $?
	git reset --hard "${git_version}" || die "git reset --hard \"${git_version}\" failed (\"${1}\")" $?
	popd_wrapper
}

# git_get_commit()
#   1>  : Git directory
#   2<  : Git commit
function git_get_commit()
{
	(((1 <= $#) && ($# <= 2))) || die "Invalid parameter count: ${#} (1-2)"

	local	git_directory="${SOURCE_ROOT}/${1}" __git_commit_reference="${2}" __git_commit

	pushd_wrapper "${git_directory}"
	__git_commit=$(git rev-parse HEAD)
	[[ "${__git_commit}" =~ ${SHA1_REGEXP} ]] || die "git rev-parse HEAD failed (\"${1}\")"
	popd_wrapper

	if [[ -z "${__git_commit_reference}" ]]; then
		echo "${__git_commit}"
	elif [[ "${__git_commit_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
		declare -n git_commit="${__git_commit_reference}"
		# shellcheck disable=SC2034
		git_commit="${__git_commit}"
	else
		die "Parameter (2): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__git_commit_reference}'"
	fi
}

# git_get_tag()
#   1>  : Git directory
#   2<  : Git tag
function git_get_tag()
{
	(((1 <= $#) && ($# <= 2))) || die "Invalid parameter count: ${#} (1-2)"

	local	git_directory="${SOURCE_ROOT}/${1}" __git_tag_reference="${2}" __git_tag

	pushd_wrapper "${git_directory}"
	__git_tag=$(git describe --abbrev=0 --tags || die "git describe --abbrev=0 --tags failed")
	popd_wrapper

	if [[ -z "${__git_tag_reference}" ]]; then
		echo "${__git_tag}"
	elif [[ "${__git_tag_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
		declare -n git_tag="${__git_tag_reference}"
		# shellcheck disable=SC2034
		git_tag="${__git_tag}"
	else
		die "Parameter (2): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__git_tag_reference}'"
	fi
}

# wine_staging_get_upstream_commit()
#   1>  : Wine-Staging Git directory
#	2>	: Wine-Staging Git commit
# ( 3<  : Upstream (Wine) Git commit )
function wine_staging_get_upstream_commit()
{
	(((2 <= $#) && ($# <= 3))) || die "Invalid parameter count: ${#} (2-3)"

	local	git_directory="${SOURCE_ROOT}/${1}" __wine_staging_git_commit="${2}" __git_commit_reference="${3}" \
			__git_commit

	pushd_wrapper "${git_directory}"
	[[ "${__wine_staging_git_commit}" =~ ${SHA1_REGEXP} ]] \
		|| die "invalid Wine-Staging SHA-1 hash commit: \"${__wine_staging_git_commit}\""
	__git_commit=$( patches/patchinstall.sh --upstream-commit )
	[[ "${__git_commit}" =~ ${SHA1_REGEXP} ]] \
		|| die "unable to get Wine commit corresponding to Wine-Staging commit: \"${__wine_staging_git_commit}\""
	printf "%sChecking out Wine commit: %s${__git_commit}%s ; corresponding to Wine-Staging commit: %s${__wine_staging_git_commit}%s\\n" \
				"${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYRESET}"
	popd_wrapper

	if [[ -z "${__git_commit_reference}" ]]; then
		echo "${__git_commit}"
	elif [[ "${__git_commit_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
		declare -n git_commit="${__git_commit_reference}"
		# shellcheck disable=SC2034
		git_commit="${__git_commit}"
	else
		die "Parameter (3): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__git_commit_reference}'"
	fi
}

# sieve_patchset_array_by_git_commit()
#	1>  : Git Source directory
#	2[-N]>  : Patch-set array(s) (reference(s))
sieve_patchset_array_by_git_commit() {
	(($# >= 2))	|| die "invalid parameter count: ${#} (2-)"

	local __commit_hash __git_directory __git_log __patch_array_reference i_arg i_array __line

	__git_directory="${1%/}"
	if [[ ! -d "${__git_directory}/.git" ]]; then
		die "argument (1): path \"${__git_directory}\" is not a valid Git repository directory"
	fi
	pushd_wrapper "${__git_directory}"
	__git_log="$( git log --pretty=format:%H 2>/dev/null || die "git log failed" )"
	popd_wrapper

	for (( i_arg=1 ; $# > 1 ; ++i_arg)); do
		shift 1
		__patch_array_reference="${1}"
		if [[ ! "${__patch_array_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
			die "argument (${i_arg}): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__patch_array_reference}'"
		fi

		declare -n patch_array="${__patch_array_reference}"
		for i_array in "${!patch_array[@]}"; do
			[[ -f "${patch_array[i_array]}" ]] || die "patch file: \"${patch_array[i_array]}\" does not exist"

			__line=0
			while
				: $((++__line))
				__commit_hash="$( sed -n -e "${__line}"'s/^.*\([[:xdigit:]]\{40\}\).*$/\1/p' "${patch_array[i_array]}" )"
				[[ "${__commit_hash}" =~ ${SHA1_REGEXP} ]]
			do
				[[ "${__git_log}" =~ ${__commit_hash} ]] || continue

				printf "%sExcluding patch: %s%s\"%s${patch_array[i_array]}%s%s\"%s ; parent Wine Git commit: %s${__commit_hash}%s\\n" \
				"${TTYGREEN_BOLD}" "${TTYRESET}" "${TTYGREEN}" "${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYGREEN}" "${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYRESET}"
				unset 'patch_array[i_array]'
				break
			done
		done
	done
}

# process_staging_exclude()
#	1>	Staging exclude list
# ( 2<	Processed staging exclude list )
function process_staging_exclude()
{
	(((1 <= $#) && ($# <= 2))) || die "Invalid parameter count: ${#} (1-2)"

	local	__staging_exclude="${1}" __staging_exclude_reference="${2}" \
			__staging_patch_file __processed_staging_exclude
	__staging_patch_file="patches/patchinstall.sh"

	__processed_staging_exclude=$( printf "%s" "${__staging_exclude}" \
		| awk -vstaging_patch_file="${__staging_patch_file}" 				\
		'
			function check_patchset_support(patchset,
				found)
			{
				gsub("(\\.|\\-|\\_)", "\\\\&", patchset)
				while ((getline line < staging_patch_file) > 0)
				{
					if (line ~ (patchset "\\)"))
					{
						found=1
						break
					}
				}
				close (staging_patch_file)
				return (found)
			}

			{
				for (i=1;i<=NF;++i)
				{
					i += ($i=="-W") ? 1 : 0
					if (check_patchset_support($i))
						printf("-W %s ", $i)
				}
			}
			END{
				printf("\n")
			}' 2>/dev/null
	)

	if [[ -z "${__staging_exclude_reference}" ]]; then
		echo "${__processed_staging_exclude}"
	elif [[ "${__staging_exclude_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
		declare -n __staging_exclude="${__staging_exclude_reference}"
		# shellcheck disable=SC2034
		__staging_exclude="${__processed_staging_exclude}"
	else
		die "Parameter (2): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__staging_exclude_reference}'"
	fi
}

# apply_binpatch_array()
#	1>  	: Source root directory to which to apply p1 formatted binary patchset
#	2...N>	: Array of binary patches to apply to Source root directory
function apply_binpatch_array()
{
	((2 <= $#)) || die "Invalid parameter count: ${#} (2-)"

	local		__source_directory="${SOURCE_ROOT}/${1}"
	local -a	__array_patch_files=("${!2}")
	local	__binary_patch_file __patch_log

	pushd_wrapper "${__source_directory}"
	for __binary_patch_file in "${__array_patch_files[@]}"; do
		[[ -z "${__binary_patch_file}" ]] && continue
		[[ -f "${__binary_patch_file}" ]] || die "binary patch file \"${__binary_patch_file}\" does not exist"

		printf "%sApplying binary patch file%s: \"%s${__binary_patch_file}%s\" ...\\n" \
			"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYRESET}"
		"${SOURCE_ROOT}/${WINE_STAGING_PATCHBIN_SCRIPT}" --nogit < "${__binary_patch_file}" \
			|| die "binary patch file: \"${__binary_patch_file}\" failed to apply"
	done
	popd_wrapper
}

# apply_patch_array()
#	1>  	: Source root directory to which to apply p1 formatted patchset
#	2...N>	: Array of patches to apply to Source root directory
function apply_patch_array()
{
	((2 <= $#)) || die "Invalid parameter count: ${#} (2-)"

	local		__source_directory="${SOURCE_ROOT}/${1}"
	local -a	__array_patch_files=("${!2}")
	local -a	__array_sorted_patch_files
	local	__count __patch_file __patch_log

	printf "%sUsing Source Directory%s: \"%s${__source_directory}%s\" ...\\n" \
		"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYRESET}"
	pushd_wrapper "${__source_directory}"
	__count=0
	# shellcheck disable=SC2068
	for __patch_file in ${__array_sorted_patch_files[@]}; do
		[[ -z "${__patch_file}" ]] && continue
		[[ -f "${__patch_file}" ]] || die "patch file \"${__patch_file}\" does not exist"

		printf "%s(%03d) Applying patch file%s: \"%s${__patch_file}%s\" ...\\n" \
			"${TTYCYAN}" "$((__count+=1))" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYRESET}"
		__patch_log="$(patch --verbose -p1 < "${__patch_file}" || false)"
		# shellcheck disable=SC2181
		if (($?)); then
			printf "%s\\n" "${TTYYELLOW}${__patch_log}${TTYRESET}"
			die "patch file: \"${__patch_file}\" failed to apply\\n" $?
		fi
	done
	popd_wrapper
}

# apply_patch_directory()
#	1>  : Source root directory to which to apply p1 formatted patchset
#	2>	: Patch directory to apply patches from
function apply_patch_directory()
{
	((2 == $#)) || die "Invalid parameter count: ${#} (2)"

	local	source_directory="${1}" patch_directory="${2}" \
			__patch_file

	if [[ ! -d "${patch_directory}" ]]; then
		printf "%sIgnoring non-existent patch directory%s: \"%s${patch_directory}%s\"\\n" \
				"${TTYRED_BOLD}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYRESET}"
		return 1
	else
		printf "%sApplying patches from patch directory%s: \"%s${patch_directory}%s\" ...\\n" \
				"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYBLUE}" "${TTYRESET}"
		local array_patch_files=()
		while IFS=  read -r -d $'\0' __patch_file; do
			array_patch_files+=("${__patch_file}")
		done < <(find "${patch_directory}" -type f -name "*.patch" -print0)

		apply_patch_array "${source_directory}" array_patch_files[@]
	fi
}

# apply_user_patches()
# 1>  : Source root directory to which to apply p1 formatted patchset
function apply_user_patches()
{
	((1 == $#)) || die "Invalid parameter count: ${#} (1)"

	local	source_directory="${1}" \
			patch_directories_count="${#USER_PATCH_DIRECTORIES[@]}" \
			patch_directory

	local i
	for ((i=0;i<patch_directories_count;++i)); do
		[[ "${USER_PATCH_DIRECTORIES[i]+valid}" ]] || continue

		patch_directory="${USER_PATCH_DIRECTORIES[i]}"
		apply_patch_directory "${source_directory}" "${patch_directory}"
	done
}


#### Network Helper Functions Definition Block ####

# get_fastest_package_mirror()
# ( 1>	: Minimum number of connection tries )
# ( 2>	: Maximum TTL )
# ( 3<	: Fastest local Ubuntu Mirror )
get_fastest_package_mirror()
{
	(($# <= 3)) || die "Invalid parameter count: ${#} (0-3)"

	local	__min_conn_attempts="${1:-50}" __max_TTL="${2:-16}" __ubuntu_mirror_uri_reference="${3}" \
			__ubuntu_mirror_list __ubuntu_mirror_uri

	__ubuntu_mirror_list="$(
		wget -q -O- https://launchpad.net/ubuntu/+archivemirrors | \
		awk '
		{
			array[++lines]=$0
		}
		END{
			for (i=1;i<=lines;++i)
			{
				match(array[i], /<a href=\"(ftp|http).*\/ubuntu\/\">/)
				uri=RSTART ? substr(array[i],RSTART+9,RLENGTH-11) : uri
				if ((array[i] ~ /statusUP/) && (uri != "")) {
					printf("%s ", uri)
					uri=""
				}
			}
		}'
	)"
	__ubuntu_mirror_uri=$(
		# shellcheck disable=SC2086
		netselect -s1 -t"${__min_conn_attempts}" -m"${__max_TTL}" ${__ubuntu_mirror_list} 2>/dev/null | awk '{print $2}'
	)
	if [[ -z "${__ubuntu_mirror_uri_reference}" ]]; then
		echo "${__ubuntu_mirror_uri}"
	elif [[ "${__ubuntu_mirror_uri_reference}" =~ ${VARIABLE_NAME_REGEXP} ]]; then
		declare -n ubuntu_mirror_uri="${__ubuntu_mirror_uri_reference}"
		# shellcheck disable=SC2034
		ubuntu_mirror_uri="${__ubuntu_mirror_uri}"
	else
		die "Parameter (3): invalid reference name (${VARIABLE_NAME_REGEXP}): '${__ubuntu_mirror_uri_reference}'"
	fi
}

manual_install_package_set()
{
	(($# >= 2)) || die "Invalid parameter count: ${#} (2-)"

	local set_type="${1}"

	printf "%s\\nInstalling Wine runtime %s%s%s set ...\\n" \
		"${TTYWHITE_BOLD}" "${TTYBLUE_BOLD}" "${set_type}" "${TTYRESET}"
	for package in ${@:2}; do
		printf "%s\\nProcessing package: %s%s%s ...\\n" \
				"${TTYWHITE_BOLD}" "${TTYBLUE_BOLD}" "${package}" "${TTYRESET}"
		aptitude install -q -y "${package}" \
			|| die "aptitude failed to install Wine ${set_type} package: ${package}"
		apt-mark manual "${package}" \
			|| die "apt-mark manual failed for Wine ${set_type} package: ${package}"
	done
}

install_host_wine_runtime()
{
	(($# == 2)) || die "Invalid parameter count: ${#} (2)"

	local architecture="${1}" option="${2,,}"
	local libpng
	local -a array_package_list_base array_package_list_optional array_package_list_recommends

	libpng="$(aptitude search -F "%p" "libpng1[0-9]" | head -n 1)"
	array_package_list_base=( "libasound2" "libc6" "libglib2.0-0" "libgphoto2-6" "libgphoto2-port12" "libgstreamer-plugins-base1.0-0" "libgstreamer1.0-0"
		"liblcms2-2" "libldap-2.4-2" "libmpg123-0" "libopenal1" "libpulse0" "libudev1" "libx11-6" "libxext6" "libxml2" "zlib1g" "libasound2-plugins" "libncurses5"
	)
	array_package_list_recommends=( "libcairo2" "libcapi20-3" "libcups2" "libdbus-1-3" "libfontconfig1" "libfreetype6" "libglu1-mesa" "libglu1" "libgnutls30" "libgsm1"
		"libgssapi-krb5-2" "libgstreamer-plugins-bad1.0-0" "libgstreamer-plugins-good1.0-0" "libgtk-3-0" "libjpeg8" "libkrb5-3" "libncurses5" "libodbc1" "libosmesa6"
		"libpcap0.8" "${libpng}" "libsane" "libsdl2-2.0-0" "libtiff5" "libtxc-dxtn-s2tc0" "libv4l-0" "libva-drm1" "libva-x11-1" "libva1" "libvulkan1" "libxcomposite1"
		"libxcursor1" "libxfixes3" "libxi6" "libxinerama1" "libxrandr2" "libxrender1" "libxslt1.1" "libxxf86vm1"
	)
	array_package_list_optional=( "winbind" )

	case "${architecture}" in
		i386)
			dpkg --add-architecture i386 \
				|| die "dpkg failed to add i386 architecture"
			;;
		amd64)
			;;
		*)
			die "unknown package architecture specified: \"${architecture}\""
			;;
	esac
	apt-get install aptitude \
		|| die "apt failed to install aptitude package"
	aptitude update -q -y
	# shellcheck disable=SC2068
	manual_install_package_set "${architecture} base library" ${array_package_list_base[@]/%/:${architecture}}
	case "${option}" in
		--full)
			# shellcheck disable=SC2068
			manual_install_package_set "${architecture} recommended library" ${array_package_list_base[@]/%/:${architecture}}
			if [[ "${architecture}" = "amd64" ]]; then
				manual_install_package_set "${architecture} optional package" ${array_package_list_optional[@]}
			fi
			;;
		--base)
			;;
		*)
			die "Unknown option: \"${option}\", specify: \"--base\" or \"--full\""
			;;
	esac
}

#### Schroot / Chroot Function Definition Block ####

# schroot_session_start()
#	1>	: Schroot session name
#	2>  : Schroot session user
#	3>  : Schroot chroot name
function schroot_session_start()
{
	(($# == 3)) || die "Invalid parameter count: ${#} (3)"

	local	session="${1#session:}" \
			user="${2}" \
			chroot="chroot:${3#chroot:}"

	schroot -e -c "session:${session}" &>/dev/null
	printf "%s" "${TTYPURPLE}"
	schroot -b -c "${chroot}" -u "${user}" -n "${session}"
	# shellcheck disable=SC2181
	(($?)) && die "schroot -b -c \"${chroot}\" -u \"${user}\" -n \"${session}\" (session start) failed"
	printf "%s" "${TTYRESET}"
}

# schroot_session_run()
#	1>		: Schroot session name
#	2>		: Schroot session user
#	3>		: Schroot start directory
#	4...N>	: Array of commands to run in Schroot environment
function schroot_session_run()
{
	(($# >= 4)) || die "Invalid parameter count: ${#} (4-)"

	local -r	session="session:${1#session:}" \
				user="${2}" \
				directory="${3:-${PWD}}"
	local -a commands_array=( "${@:4}" )

	local i
	printf "%s" "${TTYCYAN}"
	for i in ${!commands_array[*]}; do
		schroot -r -c "${session}" -d "${directory}" -- sh -c "${commands_array[i]}"
		# shellcheck disable=SC2181
		(($?)) && die "schroot -r -c \"${session}\" -d \"${directory}\" -- ${commands_array[i]} (session run) failed"
	done
	printf "%s" "${TTYRESET}"
}

# schroot_session_cleanup()
#	1...N>	: Array of Schroot session name(s) to delete
function schroot_session_cleanup()
{
	(($# >= 1)) || die "Invalid parameter count: ${#} (1-)"

	local -r sessions_array=( "${@}" )
	local sessions

	printf "%s" "${TTYPURPLE}"
	# shellcheck disable=SC2068
	for session in ${sessions_array[@]}; do
		sessions="${sessions} -c session:${session#session:}"
	done
	# shellcheck disable=SC2086
	schroot -e ${sessions}
	printf "%s" "${TTYRESET}"
}

# bootstrap_schroot_image()
#	1>  : Schroot chroot name
#	2>  : Schroot architecture (32-bit or 64-bit)
bootstrap_schroot_image()
{
	(($# == 2)) || die "Invalid parameter count: ${#} (2)"

	local -r	chroot_name="${1}" architecture="${2}"
	local -r	lsb_description="$(lsb_release -sd)" \
			chroot_path="/srv/chroot/${chroot_name}"

	[[ -d "/etc/schroot/chroot.d" ]] || mkdir -p "/etc/schroot/chroot.d"
	case "${architecture}" in
		i386)	(
	cat <<EOF_Schroot_wine32
[${chroot_name}]
description=${lsb_description} (32-bit)
personality=linux32
EOF_Schroot_wine32
				) > /etc/schroot/chroot.d/"${chroot_name}".conf
			;;
		amd64)	(
	cat <<EOF_Schroot_wine64
[${chroot_name}]
description=${lsb_description} (64-bit)
EOF_Schroot_wine64
				) > /etc/schroot/chroot.d/"${chroot_name}".conf
			;;
	esac
	(
		cat <<EOF_Schroot_wine
directory=${chroot_path}
message-verbosity=verbose
root-users=root
type=directory
users=${USERNAME}
preserve-environment=true
EOF_Schroot_wine
	) >> /etc/schroot/chroot.d/"${chroot_name}".conf
	local path
	for path in /etc/{locale.gen,timezone} /etc/default/{console-setup,keyboard,locale}; do
		# Append host locale & keyboard default configuration files to schroot copyfiles configuration file.
		# sed command only appends file names - if not already present.
		if [[ -f "${path}" ]]; then
			sed -i -e "\\|${path}|h; \${x;s|${path}||;{g;t};a\\" -e "${path}" -e "}" "/etc/schroot/default/copyfiles"
		else
			sed -i "\\|${path}|d" "/etc/schroot/default/copyfiles"
		fi
	done
	printf "%s" "${TTYPURPLE}"
	# shellcheck disable=SC2153
	debootstrap --variant=buildd --arch"=${architecture}" "${LSB_CODENAME}" \
			"${chroot_path}" "${UBUNTU_MIRROR_URI}"
	printf "%s" "${TTYRESET}"
}

# setup_chroot_build_env()
#	1>  : Schroot chroot name
setup_chroot_build_env()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local -r	chroot_name="${1}"
	local	session="${SESSION_WINE_INITIALISE}"
	local -r	session_directory="/var/lib/schroot/session/" \
			locale_lang="$( locale | awk -F'=' '$1=="LANG" { print $2 }' )" \
			chroot_path="/srv/chroot/${chroot_name}"

	[[ -d "${session_directory}" ]] || mkdir -p "${session_directory}"
	if [[ ! -f "${chroot_path}/etc/locale.gen" ]]; then
		# Generate a dummy /etc/locale.gen file for Schroot (as host system does not have a candidate file)
		grep -s "${locale_lang}" "${chroot_path}/usr/share/i18n/SUPPORTED" > "${chroot_path}/etc/locale.gen"
		printf "en_US.UTF-8 UTF-8\\n" >> "${chroot_path}/etc/locale.gen"
	else
		# Set valid locales in /etc/locale.gen file for Schroot (as host system does not have a candidate file)
		sed -i -e "\\|${locale_lang}|{s|^\\#[[:blank:]]\\+||}" -e "\\|en_US.UTF-8|{s|^\\#[[:blank:]]\\+||}" \
			"${chroot_path}/etc/locale.gen"
	fi
	schroot_session_start "${session}" "root" "${chroot_name}"
	rm "${chroot_path}"/etc/{protocols,services} &>/dev/null

	cat > "${chroot_path}/etc/apt/sources.list" <<EOF
deb ${UBUNTU_MIRROR_URI} ${LSB_CODENAME} main restricted multiverse universe
deb-src ${UBUNTU_MIRROR_URI} ${LSB_CODENAME} main restricted multiverse universe
EOF
	schroot_session_run "${session}" "root" "/" \
		"apt-get install -q -y aptitude apt-utils locales" \
		"locale-gen ${locale_lang}" \
		"apt-get update -q -y" \
		"apt-get upgrade -q -y" \
		"rm -f \"${chroot_path}/etc/systemd/resolved.conf\"" \
		"aptitude install -q -y ubuntu-minimal software-properties-common" \
		"dpkg-reconfigure --frontend=noninteractive locales" \
		"update-locale LANG=${locale_lang}"
	schroot_session_cleanup "${session}"
}

#		"dpkg-reconfigure locales" \

# upgrade_chroot_build_env()
#	1>  : Schroot chroot name
upgrade_chroot_build_env()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local -r	chroot_name="${1}"
	local	  	session="${SESSION_WINE_INITIALISE}"
	local -r	chroot_path="/srv/chroot/${chroot_name}"

	schroot_session_start "${session}" "root" "${chroot_name}"
	schroot_session_run "${session}" "root" "/" \
		"aptitude update -q -y" \
		"aptitude upgrade -q -y" \
		"aptitude install -q -y autoconf libva-dev libgtk-3-dev libudev-dev libgphoto2-dev libcapi20-dev libsane-dev libkrb5-dev libsdl2-dev libvulkan-dev" \
		"apt-get build-dep -q -y -f wine-development" \
		"aptitude upgrade -q -y"
	schroot_session_cleanup "${session}"
}

#### Package Phases Function Definition Block ####

# src_fetch()
function src_fetch()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	printf "\\n\\n%s${FUNCNAME[ 0 ]} ()%s ... \\n" "${TTYWHITE_BOLD}" "${TTYRESET}"

	clean_build_directories "${BUILD_ROOT}/wine64" "${BUILD_ROOT}/wine32" "${BUILD_ROOT}/wine32_tools"
	pushd_wrapper "${SOURCE_ROOT}"
	fetch_and_extract_tarball . "${GENTOO_WINE_EBUILD_COMMON_PACKAGE_URL}" "${GENTOO_WINE_EBUILD_COMMON_PACKAGE}"

	# Fetch Wine-Staging Git Source (if required).
	# Checkout desired Wine version in Wine-Staging Git tree (clean and update first!!)
	if ((WINE_STAGING)); then
		git_clone "${WINE_STAGING_GIT_URL}"
		git_pull_and_checkout "wine-staging" "${__WINE_STAGING_GIT_TAG}"
		git_get_commit "wine-staging" "__WINE_STAGING_COMMIT"
		if [[ ! -z "${WINE_STAGING_BRANCH}" || ! -z "${WINE_STAGING_COMMIT}" ]]; then
			wine_staging_get_upstream_commit "wine-staging" "${__WINE_STAGING_COMMIT}" "__WINE_GIT_TAG"
		fi
	fi

	# Fetch Wine Git Source (if required). Checkout desired Wine version in Wine Git tree (clean and update first!!)
	git_clone "${WINE_GIT_URL}"
	git_pull_and_checkout "wine" "${__WINE_GIT_TAG}"
	popd_wrapper
}

# src_prepare()
function src_prepare()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	printf "\\n\\n%s${FUNCNAME[ 0 ]} ()%s ... \\n" "${TTYWHITE_BOLD}" "${TTYRESET}"

	local	md5hash
	md5hash="$(md5sum "${SOURCE_ROOT}/wine/server/protocol.def" || die "md5sum failed")"

	# (1) Apply base (bundled) & working patches (Wine version dependent)
	local -a	array_patch_files=(
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.5.26-winegcc.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.6-memset-O3.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.8-gstreamer-1.0_"{01,02,03,04,05,06,07,08,09,10,11}".patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.8_winecfg_detailed_version.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.9.13-gnutls-3.5-compat.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.9.14-cups-2.2-cupsgetppd-build-fix.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-1.9.9-sysmacros.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-2.18-freetype-2.8.1-drop-glyphs.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-2.18-freetype-2.8.1-segfault.patch"
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-2.7-osmesa-configure_support_recent_versions.patch"
	)
	# shellcheck disable=SC2034
	local -a	array_binpatch_files=(
		"${SOURCE_ROOT}/${WINE_EBUILD_COMMON}/patches/wine-2.18-freetype-2.8.1-implement_minimum_em_size_required_by_opentype_1.8.2.patch"
	)

	mkdir -p "${WORKING_PATCHES_DIRECTORY}"
	sieve_patchset_array_by_git_commit "${SOURCE_ROOT}/wine" array_patch_files array_binpatch_files
	apply_patch_array "wine" array_patch_files[@]
	apply_binpatch_array "wine" array_binpatch_files[@]

	# (2) Apply Wine-Staging patchset
	if ((WINE_STAGING)) && [[ -d "${SOURCE_ROOT}/wine-staging" ]]; then
		(
			local	staging_exclude

			pushd_wrapper "${SOURCE_ROOT}/wine-staging"
			# shellcheck disable=SC2030
			WINE_STAGING_EXCLUDE="${WINE_STAGING_EXCLUDE} configure-OSMesa winhlp32-Flex_Workaround"
			process_staging_exclude "${WINE_STAGING_EXCLUDE}" "staging_exclude"
			# Disable Upstream (Wine Staging) about tab customisation, for winecfg utility, to support our own version
			if [[ -f "patches/winecfg-Staging/0001-winecfg-Add-staging-tab-for-CSMT.patch" ]]; then
				sed -i '\|^diff \-\-git a/programs/winecfg/about.c|,+12d' \
					"patches/winecfg-Staging/0001-winecfg-Add-staging-tab-for-CSMT.patch" &>/dev/null
			fi
			printf "%sApplying Wine-Staging patchset %s...\\n%spatchinstall.sh %sDESTDIR=\"%s${SOURCE_ROOT}/wine%s\" --no-autoconf --all ${staging_exclude}%s\\n" \
					"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYGREEN_BOLD}" "${TTYCYAN}"
			# shellcheck disable=SC2086
			patches/patchinstall.sh DESTDIR="${SOURCE_ROOT}/wine" --no-autoconf --all ${staging_exclude} \
				|| die "Wine-Staging \"${SOURCE_ROOT}/wine-staging/patches/patchinstall.sh\" failed" $?
			printf "%s" "${TTYRESET}"
			popd_wrapper
		)
		if [[ "${__WINE_STAGING_VERSION}" =~ ${VERSION_REGEXP} && "${__WINE_STAGING_VERSION}" =~ ${STABLE_VERSION_REGEXP} ]]; then
			# Handle "unofficial" stable Staging versions
			sed -i "s/(Staging)/(Staging${WINE_STAGING_SUFFIX})/" "${SOURCE_ROOT}/wine/libs/wine/Makefile.in" || die "sed failed" $?
		fi
		# Update Wine package name for Staging patchset
 		sed -r -i '/^AC_INIT\(.*\)$/{s/\[Wine\]/\[Wine \(Staging\)\]/}' "${SOURCE_ROOT}/wine/configure.ac" || die "sed failed" $?
		sed -r -i "s/Wine (\\(Staging\\) |)/Wine \\(Staging\\) /" "${SOURCE_ROOT}/wine/VERSION" || die "sed failed" $?
	fi

	# (3) Apply user patches. Stored in directories specified in the USER_PATCH_DIRECTORIES[0...N-1] directories array ...
	apply_user_patches "wine"

	pushd_wrapper "${SOURCE_ROOT}/wine"
	# Run autoreconf to update configuration - post application of all patches
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"autoreconf"
	if ! md5sum -c - <<<"${md5hash}" &>/dev/null; then
		printf "\"%s${PWD}/protocol.def%s\"%s was patched; running \"%s${PWD}/tools/make_requests%s\" ... \\n" \
			"${TTYBLUE_BOLD}" "${TTYRESET}" "${TTYCYAN}" "${TTYCYAN_BOLD}" "${TTYRESET}"
		tools/make_requests || die "\"${PWD}/tools/make_requests\" failed"
	fi
 	popd_wrapper
}

# multilib_src_configure()
function multilib_src_configure()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	printf "\\n\\n%s${FUNCNAME[ 0 ]} ()%s ... \\n" "${TTYWHITE_BOLD}" "${TTYRESET}"

	export	CFLAGS="${WINE_CFLAGS}"

	# Configure 64-bit wine64
	pushd_wrapper "${BUILD_ROOT}/wine64"
	[[ -f "Makefile" ]] && schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
								"make clean"
	schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
		"'${SOURCE_ROOT}/wine/configure' ${WINE_CONFIGURATION} --enable-win64 --prefix='${PREFIX}'"
	popd_wrapper

	# Configure 32-bit wine32_tools
	pushd_wrapper "${BUILD_ROOT}/wine32_tools"
	[[ -f "Makefile" ]] && schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
								"make clean"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"'${SOURCE_ROOT}/wine/configure' ${WINE_CONFIGURATION} --prefix='${PREFIX}'"
	popd_wrapper
}

# multilib_src_compile()
function multilib_src_compile()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	printf "\\n\\n%s${FUNCNAME[ 0 ]} ()%s ... \\n" "${TTYWHITE_BOLD}" "${TTYRESET}"

	# Build 64-bit wine64
	pushd_wrapper "${BUILD_ROOT}/wine64"
	schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
		"make ${WINE_MAKE_OPTIONS}"
	popd_wrapper

	# Build 32-bit wine32_tools
	pushd_wrapper "${BUILD_ROOT}/wine32_tools"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"make ${WINE_MAKE_OPTIONS}"
	popd_wrapper

	# Configure & Build multilib wine32(64)
	pushd_wrapper "${BUILD_ROOT}/wine32"
	[[ -f "Makefile" ]] && schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"make clean"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"'${SOURCE_ROOT}/wine/configure' ${WINE_CONFIGURATION} --with-wine64='${BUILD_ROOT}/wine64' --with-wine-tools='${BUILD_ROOT}/wine32_tools' --prefix='${PREFIX}'" \
		"make ${WINE_MAKE_OPTIONS}"
	popd_wrapper
}

# multilib_src_install()
function multilib_src_install()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	printf "\\n\\n%s${FUNCNAME[ 0 ]} ()%s ... \\n" "${TTYWHITE_BOLD}" "${TTYRESET}"

	# Install Wine (32-bit) binaries in specified PREFIX path
	pushd_wrapper "${BUILD_ROOT}/wine32"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"make install"
	popd_wrapper

	pushd_wrapper "${BUILD_ROOT}/wine64"
	# Install Wine (64-bit) binaries in specified PREFIX path
	schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
		"make install"
	popd_wrapper
}

#### Command line processing functions ####

# screen_conf_file()
#	1>	Global configuration file to screen for errors and exploits
function screen_conf_file()
{
	(($# == 1)) || die "Invalid parameter count: ${#} (1)"

	local __script_conf_file="${1}"

	[[ -z ${__script_conf_file} || ! -f "${__script_conf_file}" ]] \
		&& die "script configuration file: \"${__script_conf_file}\" does not exist"

	# shellcheck disable=SC1004
	awk 'BEGIN{
			regex_whitespace="(^[[:blank:]]*|[[:blank:]]*$)"
			regex_blank_comment_line="^[[:blank:]]*(\#|$)"
			regex_boolean_variables="^(COLOUR|LOGGING|WINE_STAGING)[[:blank:]]*(#|$)"
			regex_string_variables="^((BUILD|SOURCE)_ROOT|LOG_(COMPRESSION|DIRECTORY)|PREFIX|THREADS|"\
"WINE_(CFLAGS|CONFIGURATION|MAKE_OPTIONS|VERSION|BRANCH|COMMIT)|WINE_STAGING_(BRANCH|COMMIT|EXCLUDE))[[:blank:]]*(#|$)"
			regex_array_string_variables="^(USER_PATCH_DIRECTORIES)[[:blank:]]*(#|$)"
			regex_string_value="^\"[^\"]*\"[[:blank:]]*(#|$)"
			regex_boolean_value="^(0|1|false|true|no|yes)[[:blank:]]*(#|$)"
			regex_array_string_value="^\\([[:blank:]]*(\"[^\"]*\"[[:blank:]]*)+\\)[[:blank:]]*(#|$)"
			regex_shell_command="\$\\([^\)]+\\)"
			command_tput="tput setaf 1 ; tput bold"
			command_tput | getline ttyred_bold
			close(command_tput)
			command_tput="tput setaf 6 ; tput bold"
			command_tput | getline ttycyan_bold
			close(command_tput)
			command_tput="tput sgr0"
			command_tput | getline ttyreset
			close(command_tput)
		}
		{
			if ($0 ~ regex_blank_comment_line)
				next

			match($0, "^[^\=]+\=")
			error1=error2=0
			variable=substr($0,1,RSTART+RLENGTH-2)
			gsub(regex_whitespace, "", variable)
			value=substr($0,RSTART+RLENGTH)
			gsub(regex_whitespace, "", value)
			if (!RSTART)
				error1=1
			else if (variable ~ regex_shell_command)
				error1=1
			else if (value ~ regex_shell_command)
				error2=1
			else if (variable ~ regex_boolean_variables)
				error2=(value !~ regex_boolean_value)
			else if (variable ~ regex_string_variables) {
				error2=(value !~ regex_string_value)
			}
			else if (variable ~ regex_array_string_variables) {
				error2=(value !~ regex_array_string_value)
				sub("\\$$", "([[:blank:]])*\\+?&", regex_array_string_variables)
			}
			else
				error1=1
			invalid=invalid || error1 || error2
			if (error1 || error2) {
				printf("%s(%04d)%s %s%s%s=%s%s%s\\n", ttycyan_bold, NR, ttyreset,
										(error1 ? ttyred_bold : ""), variable, (error1 ? ttyreset : ""),
										(error2 ? ttyred_bold : ""), value, (error2 ? ttyreset : ""))
			}
		}
		END{
			exit invalid
		}' "${__script_conf_file}" 2>/dev/null

	return
}


# process_command()
#  	1...N>	:  Array of commands and options (passed as CLI parameters)
function process_command()
{
	# Process options
	local option="${1}"
	local build_options directory directory_type parent_directory host_runtime_option
	while (($#)); do
		case "${option}" in
			--full|--base)
				host_runtime_option="${option}"
				shift
				;;

			--build-directory|--build-dir|--log-directory|--log-dir|--patch-directory|--patch-dir|--source-directory|--source-dir|--prefix|--prefix-directory|--prefix-dir)
				directory_type=$(echo "${option}" | sed -r 's:(^\-\-|\-directory$|\-dir$)::g')
				[[ "${directory_type}" != "log" ]] && build_options="${build_options} ${option}"
				shift
 				(($#)) ||	 die "invalid option syntax: ${directory_type} directory not specified" "" 1
				directory=$(readlink -f "${1}")
				parent_directory=$(get_parent_directory "${directory}")
				[[ -d "${parent_directory}" ]] || die "${directory_type} directory parent: \"{parent_directory}\" does exist"
				case "${directory_type}" in
					build)		export BUILD_ROOT="${directory}";;
					log)		export LOG_DIRECTORY="${directory}";;
					patch)		export USER_PATCH_DIRECTORIES[${#USER_PATCH_DIRECTORIES[@]}]="${directory}";;
					source)		export SOURCE_ROOT="${directory}";;
					prefix)		export PREFIX="${directory}";;
				esac
				;;

			-c=*|--color=*|--colour=*)
				parse_boolean_option "${option#*=}" "COLOUR"
				setup_tty_colours "${COLOUR}"
				;;

			-c|--color|--colour)
				shift
 				(($#)) ||	die "invalid option syntax: no colour option specified" "" 1
				parse_boolean_option "${1}" "COLOUR"
				setup_tty_colours "${COLOUR}"
				;;

			--logging=*|--log=*)
				parse_boolean_option "${option#*=}" "LOGGING"
				;;

			--logging|--log)
				shift
 				(($#)) ||	die "invalid option syntax: no logging option specified" "" 1
				parse_boolean_option "${1}" "LOGGING"
				;;

			--log-compression=*)
				set_log_compression "${option#*=}"
				;;

			--log-compression)
				shift
				(($#)) ||	die "invalid option syntax: no compression option specified" "" 1
				set_log_compression "${1}"
				;;

			--wine-version=*)
				build_options="${build_options} ${option%=*}"
				export WINE_VERSION="${option#*=}"
				;;

			--wine-version)
				build_options="${build_options} ${option}"
				shift
				if (($#==0)); then
					((WINE_STAGING))   && die "invalid option syntax: Wine-Staging version not specified" "" 1
					((WINE_STAGING))   || die "invalid option syntax: Wine version not specified" "" 1
				fi
				WINE_VERSION="${1}"
				;;

			--wine-staging-branch=*|--wine-staging-commit=*)
				build_options="${build_options} ${option%=*}"
				[[ "${option%=*}" =~ branch$ ]] && WINE_STAGING_BRANCH="${option#*=}"
				[[ "${option%=*}" =~ commit$ ]] && WINE_STAGING_COMMIT="${option#*=}"
				;;

			--wine-staging-branch|--wine-staging-commit)
				build_options="${build_options} ${option}"
				shift
				(($#)) || die "invalid option syntax: Wine-Staging ${option##*-} not specified" "" 1
				[[ "${option}" =~ branch$ ]] && WINE_STAGING_BRANCH="${1}"
				[[ "${option}" =~ commit$ ]] && WINE_STAGING_COMMIT="${1}"
				;;

			--wine-branch=*|--wine-commit=*)
				build_options="${build_options} ${option%=*}"
				[[ "${option%=*}" =~ branch$ ]] && WINE_BRANCH="${option#*=}"
				[[ "${option%=*}" =~ commit$ ]] && WINE_COMMIT="${option#*=}"
				;;

			--wine-branch|--wine-commit)
				build_options="${build_options} ${option}"
				shift
				(($#)) || die "invalid option syntax: Wine ${option##*-} not specified" "" 1
				[[ "${option}" =~ branch$ ]] && WINE_BRANCH="${1}"
				[[ "${option}" =~ commit$ ]] && WINE_COMMIT="${1}"
				;;

			--wine-staging=*|--staging=*)
				build_options="${build_options} ${option%=*}"
				parse_boolean_option "${option#*=}" "WINE_STAGING"

				;;

			--wine-staging|--staging)
				build_options="${build_options} ${option}"
				shift
 				(($#)) || die "invalid option syntax: Wine-Staging option not specified ([yes|no])" "" 1
				parse_boolean_option "S{1}" "WINE_STAGING"
				;;


			--)
				unset -v option
				shift
				break 2
				;;

			--*)
				die "unknown option specified: \"${option}\"" "" 1
				;;

			*)
				unset -v option
				break 2
				;;
		esac
		if [[ ! -z "${option}" ]]; then
			shift
			option="${1}"
		fi
	done
	build_options="${build_options:1}"

	# Process commands
 	(($# < 1)) &&	die "no command specified" "" 1
	for ((i=SRC_FETCH; i<=SRC_INSTALL; ++i)); do
		SUBCOMMANDS[i]=0
	done
	local	new_command prev_command
	while (( $# > 0 )); do
		new_command="${1}"
		case "${new_command}" in

		help|h)
			usage_information >&2
			exit 0
			;;

		generate-conf|conf)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" 1
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" 1
			elif [[ ! -z "${host_runtime_option}" ]]; then
				die "host-runtime-option(s): \"${host_runtime_option}\" ; are incompatible with command: \"${new_command}\"" "" 1
			fi
			export	COMMAND="conf"
			;;

		host-runtime|runtime)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" 1
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" 1
			fi
			export	COMMAND="runtime"
			;;

		setup-chroot|setup)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" 1
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" 1
			elif [[ ! -z "${host_runtime_option}" ]]; then
				die "host-runtime-option(s): \"${host_runtime_option}\" ; are incompatible with command: \"${new_command}\"" "" 1
			fi
			export	COMMAND="setup"
			;;

		upgrade-chroot|upgrade|update-chroot|update)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""  "" 1
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" 1
			elif [[ ! -z "${host_runtime_option}" ]]; then
				die "host-runtime-option(s): \"${host_runtime_option}\" ; are incompatible with command: \"${new_command}\"" "" 1
			fi
			export	COMMAND="upgrade"
			;;

		version)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""  "" 1
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" 1
			elif [[ ! -z "${host_runtime_option}" ]]; then
				die "host-runtime-option(s): \"${host_runtime_option}\" ; are incompatible with command: \"${new_command}\"" "" 1
			fi
			export	COMMAND="version"
			;;

		src-fetch|src-prepare|src-configure|src-compile|src-install|build|build-all)
			((WINE_STAGING))	&& set_wine_staging_git_tag
			((WINE_STAGING))	|| set_wine_git_tag
			if [[ "${COMMAND}" =~ setup|upgrade ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" 1
			elif [[ ! -z "${host_runtime_option}" ]]; then
				die "host-runtime-option(s): \"${host_runtime_option}\" ; are incompatible with command: \"${new_command}\"" "" 1
			fi
			export	COMMAND="build"
			case "${new_command}" in
				src-fetch)
					SUBCOMMANDS[SRC_FETCH]=1;;
				src-prepare)
					SUBCOMMANDS[SRC_PREPARE]=1;;
				src-configure)
					SUBCOMMANDS[SRC_CONFIGURE]=1;;
				src-compile)
					SUBCOMMANDS[SRC_COMPILE]=1;;
				src-install)
					SUBCOMMANDS[SRC_INSTALL]=1;;
				build|build-all)
					for ((i=SRC_FETCH; i<=SRC_INSTALL; ++i)); do
						SUBCOMMANDS[i]=1
					done;;
			esac
			;;

		*)
			die "unknown command specified: \"${new_command}\""  "" 1
			;;

		esac
		prev_command="${new_command}"
		shift 1
	done
}

# execute_commands()
function execute_commands()
{
	(($# == 0)) || die "Invalid parameter count: ${#} (0)"

	case "${COMMAND}" in
	conf)
		export DATE_STAMP
		DATE_STAMP=$(date)
		printf "\\n%s\\n" "${TTYWHITE}Generating default configuration file: \"${TTYCYAN_BOLD}${SCRIPT_CONFIG}${TTYRESET}${TTYWHITE}\"${TTYRESET} ..."
		# shellcheck disable=SC2016
		su -p -c '
			(
				export wine_staging_enabled
				((WINE_STAGING)) && wine_staging_enabled="true"
				((WINE_STAGING)) || wine_staging_enabled="false"
				cat <<EOF_script_config
#
# ${SCRIPT_CONFIG} - Configuration file for ${SCRIPT_NAME}
#
# Generated by ${SCRIPT_NAME} (${SCRIPT_VERSION}) on ${DATE_STAMP} (build version: ${SCRIPT_VERSION})
#
# Uncomment the default, example options and change these as desired.
#
# Global
#
# COLOUR=${COLOUR} # default
#
# Directories
#
# Installation prefix directory in which Wine libraries, binaries, etc. are installed.
# PREFIX="${PREFIX}" # default
#
# Root directory where sources are stored i.e. clones of Wine (and Wine-Staging) Git trees.
# SOURCE_ROOT="${SOURCE_ROOT}" # default
#
# Root directory where the binary builds are stored - "out-of-tree" build.
# BUILD_ROOT="${BUILD_ROOT}" # default
#
# Patch files (in -p1 diff format), in these directories, are applied to the Wine source.
# USER_PATCH_DIRECTORIES=( "dir1" "dir2" )
# USER_PATCH_DIRECTORIES+=( "dir3" "dir4" )
#
#
# Versioning
#
# Enable / disable Wine-Staging patchset support.
# WINE_STAGING=${wine_staging_enabled} # default
#
# Wine / Wine-Staging version to build.
# WINE_VERSION="1.9.20"
#
# Git branch of Wine to build (WINE_STAGING=no).
# WINE_BRANCH="master"
#
# Git commit (SHA-1 hash) of Wine to build (WINE_STAGING=no).
# WINE_COMMIT=""
#
# Git branch of Wine-Staging to build (WINE_STAGING=yes).
# WINE_STAGING_BRANCH="master"
#
# Git commit (SHA-1 hash) of Wine-Staging to build (WINE_STAGING=yes).
# WINE_STAGING_COMMIT=""
#
#
# Logging
#
# Enable / disable operation logging for commands: setup-chroot; upgrade-chroot; build-all (and sub-phases).
# LOGGING=1 # default
#
# Directory to hold log files - recording all the script operations.
# LOG_DIRECTORY="${LOG_DIRECTORY}" # default
#
# Compression to be applied to new log files.
# LOG_COMPRESSION="gzip" # default
#
#
# Building
#
# Number of processor threads to use.
# THREADS="${THREADS}" # default
#
# Wine-Staging subpatchsets to optionally disable.		[src-prepare]
# WINE_STAGING_EXCLUDE="" # default
#
# Configuration options for wine.						 [src-configure]
# WINE_CONFIGURATION="${WINE_CONFIGURATION}" # default
#
# CFLAGS (compile flags) to pass to wine.				 [src-configure]
# WINE_CFLAGS="${WINE_CFLAGS}" # default
#
# Make options to use when compiling wine.				[src-compile]
# WINE_MAKE_OPTIONS="${WINE_MAKE_OPTIONS}" # default
#
#
# OS Version Override (e.g. cross-building for another Debian / Ubuntu version)
# LSB_CODENAME="" # default: lsb_release -sc
EOF_script_config
				) > "${SCRIPT_CONFIG}"
		' root || die "Failed to generate default configuration file: \"${SCRIPT_CONFIG}\""
		;;
	runtime)
		setup_logging "${COMMAND}"
		{
			export -f cleanup die install_host_wine_runtime manual_install_package_set
			export host_runtime_option="${host_runtime_option:---full}"

			# shellcheck disable=SC1004,SC2016
			su -p -c '
				printf "\\n%sAttempting to install host runtime for Wine%s ...\\n" "${TTYWHITE_BOLD}" "${TTYRESET}"
				if [[ ! "${host_runtime_option}" = "--base" ]]; then
					printf "\\n%sPlease ensure you have the: %suniverse%s, %smultiverse%s and %srestricted%s repositories enabled, for your package manager%s ...\\n" \
						"${TTYWHITE_BOLD}" "${TTYBLUE_BOLD}" "${TTYWHITE_BOLD}" "${TTYBLUE_BOLD}" "${TTYWHITE_BOLD}" "${TTYBLUE_BOLD}" "${TTYWHITE_BOLD}" "${TTYRESET}"
				fi
				install_host_wine_runtime "i386" "${host_runtime_option}"
				install_host_wine_runtime "amd64" "${host_runtime_option}"
			' root || die "Failed to install ${host_runtime_option#--} Wine runtime environment"
		} &>"${__FIFO_LOG_PIPE}"
		;;
	setup)
		if [[ ! -z "${OPTIONS}" ]]; then
			die "invalid option(s) specified: ${OPTIONS}" "" 1
		fi
		setup_logging "${COMMAND}"
		{
			export -f schroot_session_start schroot_session_run schroot_session_cleanup \
						cleanup die get_fastest_package_mirror bootstrap_schroot_image \
						setup_chroot_build_env upgrade_chroot_build_env

			# shellcheck disable=SC2016
			su -p -c '
				printf "\\n%s\\n" "${TTYWHITE_BOLD}Detecting Ubuntu Mirror (with the lowest ping)${TTYRESET} ..."
				export		UBUNTU_MIRROR_URI
				UBUNTU_MIRROR_URI="$(get_fastest_package_mirror)"
				printf "\\n${TTYWHITE_BOLD}Creating 32-bit Chroot Environment${TTYRESET} ...\\n"
				bootstrap_schroot_image "'"${LSB_CODENAME}_wine_32bit"'" "i386"
				printf "\\n${TTYWHITE_BOLD}Creating 64-bit Chroot Environment${TTYRESET} ...\\n"
				bootstrap_schroot_image "'"${LSB_CODENAME}_wine_64bit"'" "amd64"
				printf "\\n${TTYWHITE_BOLD}Installing Ubuntu image to 32-bit Chroot Environment${TTYRESET} ...\\n"
				setup_chroot_build_env "'"${LSB_CODENAME}_wine_32bit"'"
				printf "\\n${TTYWHITE_BOLD}Installing Ubuntu image to 64-bit Chroot Environment${TTYRESET} ...\\n"
				setup_chroot_build_env "'"${LSB_CODENAME}_wine_64bit"'"
				printf "\\n${TTYWHITE_BOLD}Install Updated Wine Development packages to 32-bit Chroot Environment${TTYRESET} ...\\n"
				upgrade_chroot_build_env "'"${LSB_CODENAME}_wine_32bit"'"
				printf "\\n${TTYWHITE_BOLD}Install Updated Wine Development packages to 64-bit Chroot Environment${TTYRESET} ...\\n"
				upgrade_chroot_build_env "'"${LSB_CODENAME}_wine_64bit"'"
			' root || die "Failed to setup Chroot environments"
		} &>"${__FIFO_LOG_PIPE}"
		;;
	upgrade)
		setup_logging "${COMMAND}"
		{
			export -f schroot_session_start schroot_session_run schroot_session_cleanup \
						cleanup die upgrade_chroot_build_env
			local chroot_name found32bit_chroot=0 found64bit_chroot=0

			while read -r chroot_name; do
				[[ "${chroot_name}" == "${CHROOT32_NAME}" ]] && found32bit_chroot=1
				[[ "${chroot_name}" == "${CHROOT64_NAME}" ]] && found64bit_chroot=1
			done < <(schroot -l)
			if ((!found32bit_chroot && !found64bit_chroot)); then
				if ((!found32bit_chroot)); then
					printf "%sChroot Environment%s: \"%s${CHROOT32_NAME}%s\"%s ; has not yet been created.%s\\n" \
							"${TTYRED_BOLD}" "${TTYRESET}" "${TTYWHITE_BOLD}" "${TTYRESET}" "${TTYRED_BOLD}" >&2
				fi
				if ((!found64bit_chroot)); then
					printf "%sChroot Environment%s: \"%s${CHROOT64_NAME}%s\"%s ; has not yet been created.%s\\n" \
							"${TTYRED_BOLD}" "${TTYRESET}" "${TTYWHITE_BOLD}" "${TTYRESET}" "${TTYRED_BOLD}" >&2
				fi
				die "Please run: \"${SCRIPT_NAME} setup-chroot\" ; initially - to setup Chroot Environments"
			fi
			# shellcheck disable=SC2016
			su -p -c '
				printf "\\n${TTYWHITE_BOLD}Upgrade Wine Development packages in 32-bit Chroot Environment${TTYRESET} ...\\n"
				upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
				printf "\\n${TTYWHITE_BOLD}Upgrade Wine Development packages in 64-bit Chroot Environment${TTYRESET} ...\\n"
				upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_64bit"''
			' root || die "Failed to upgrade Chroot environments"
		} &>"${__FIFO_LOG_PIPE}"
		;;
	version)
		printf "\\n%s${SCRIPT_NAME} version%s: %s${SCRIPT_VERSION}%s ...\\n" \
				"${TTYCYAN}" "${TTYRESET}" "${TTYWHITE_BOLD}" "${TTYRESET}"
		;;
	build)
		setup_logging "${COMMAND}"
		{
			create_main_directories "${SOURCE_ROOT}" "${BUILD_ROOT}/wine32" "${BUILD_ROOT}/wine32_tools" "${BUILD_ROOT}/wine64"
			if ((SUBCOMMANDS[SRC_PREPARE] || SUBCOMMANDS[SRC_CONFIGURE] || SUBCOMMANDS[SRC_COMPILE] || SUBCOMMANDS[SRC_INSTALL])); then
				schroot_session_start "${SESSION_WINE32}" "${USERNAME}" "${CHROOT32_NAME}"
				schroot_session_start "${SESSION_WINE64}" "${USERNAME}" "${CHROOT64_NAME}"
			fi
			fetch_wine_staging_patchbin_script "${SOURCE_ROOT}"
			((SUBCOMMANDS[SRC_FETCH]))		&& src_fetch
			if ((WINE_STAGING)); then
				git_get_tag "wine-staging" "__WINE_STAGING_VERSION"
				export __WINE_STAGING_VERSION="${__WINE_STAGING_VERSION#${WINE_STAGING_PREFIX}}"
				git_get_commit "wine-staging" "__WINE_STAGING_COMMIT"
			fi
			git_get_tag "wine" "__WINE_VERSION"
			export __WINE_VERSION="${__WINE_VERSION#${WINE_PREFIX}}"
			git_get_commit "wine" "__WINE_COMMIT"
			((SUBCOMMANDS[SRC_PREPARE]))	&& src_prepare
			((SUBCOMMANDS[SRC_CONFIGURE]))	&& multilib_src_configure
			((SUBCOMMANDS[SRC_COMPILE]))	&& multilib_src_compile
			((SUBCOMMANDS[SRC_INSTALL]))	&& multilib_src_install
		} &>"${__FIFO_LOG_PIPE}"
		[[ -f "${SOUND_COMPLETION}" ]] && paplay "${SOUND_COMPLETION}" &>"/dev/null"
		;;
	esac
}

# main()
function main()
{
	export		SCRIPT_PID
	export		SCRIPT_PATH
	export		SCRIPT_DIRECTORY
	export		SCRIPT_NAME
	export		SCRIPT_VERSION

	SCRIPT_PID=$$
	SCRIPT_PATH="$(readlink -f "${0}")"
	SCRIPT_DIRECTORY="$(dirname "${SCRIPT_PATH}")"
	SCRIPT_NAME="$(basename "${SCRIPT_PATH}")"
	if pushd "${SCRIPT_PATH}" &>/dev/null; then
		SCRIPT_VERSION="git-$(git log -1 --date=short --format=%cd "${SCRIPT_NAME}")"
		# shellcheck disable=SC2164
		popd &>/dev/null
	fi
	export		SCRIPT_CONFIG="/etc/${SCRIPT_NAME%.sh}.conf"

	declare -a	USER_PATCH_DIRECTORIES
	export  USER_PATCH_DIRECTORIES

	# Global versioning constants
	export	WINE_STAGING="${WINE_STAGING:-0}"
	export  WINE_VERSION
	export	WINE_BRANCH WINE_STAGING_BRANCH
	export	WINE_COMMIT WINE_STAGING_COMMIT

	# Global patch constants
	# shellcheck disable=SC2031
	export  WINE_STAGING_EXCLUDE

	# Read in main parameters from global .conf file for script (default: /etc/build_multilib_wine.conf)
	if [[ -f "${SCRIPT_CONFIG}" ]]; then
		if ! screen_conf_file "${SCRIPT_CONFIG}"; then
			die "invalid lines detected in configuration file \"${SCRIPT_CONFIG}\""
		else
			# shellcheck disable=SC1090
			. "${SCRIPT_CONFIG}"
		fi
	fi

	#### Global Environment Variable defaults ####

	# Global general
	export		COLOUR="${COLOUR:-0}"
	parse_boolean_option "${COLOUR}" "COLOUR"
	setup_tty_colours "${COLOUR}"
	if (( EUID == 0 )); then
			die "do not run this script as root - you will asked for full root privileges as required!!"
	else
		printf "%s\\n" "${TTYRED_BOLD}warning${TTYRESET}: ${TTYCYAN_BOLD}this script may require to run as ${TTYRED_BOLD}root${TTYRESET} - ${TTYCYAN_BOLD}you must therefore have a ${TTYRED_BOLD}root${TTYCYAN_BOLD} password set${TTYRESET}..."
	fi
	if [[ -f "${SCRIPT_CONFIG}" ]]; then
		printf "Read global configuration file: \"%s\"...\\n" "${TTYBLUE_BOLD}${SCRIPT_CONFIG}${TTYRESET}"
	fi
	# Global name constants
	export 	GENTOO_WINE_EBUILD_COMMON_PACKAGE="gentoo-wine-ebuild-common"

	# Global versioning defaults
	parse_boolean_option "${WINE_STAGING}" "WINE_STAGING"
	export		__WINE_COMMIT	__WINE_STAGING_COMMIT
	export		__WINE_VERSION	__WINE_STAGING_VERSION

	# Global script constants
	export	WINE_STAGING_PATCHBIN_SCRIPT="patchbin.sh"
	export  SOUND_COMPLETION="/usr/share/sounds/freedesktop/stereo/complete.oga"

	# Global versioning constants
	export	SHA1_REGEXP="^[[:xdigit:]]{40}$"
	export	VARIABLE_NAME_REGEXP="^[_[:alpha:]][_[:alnum:]]+$"
	export	VERSION_REGEXP="^[[:digit:]]{1,2}\\.[[:digit:]]{1,2}(\\.[[:digit:]]{1,2}|)(\\-rc[[:digit:]]{1}|)$"
	export	STABLE_VERSION_REGEXP="^1\\.8\\.[[:digit:]]{1,2}$"
	export	WINE_STAGING_PREFIX="v"
	export	WINE_STAGING_SUFFIX="-unofficial"
	export	WINE_PREFIX="wine-"
	export	GENTOO_WINE_EBUILD_COMMON_PACKAGE_VERSION="20171106"

	# Global URL constants
	export	WINE_STAGING_GIT_URL="https://github.com/wine-staging/wine-staging.git"
	export	WINE_GIT_URL="git://source.winehq.org/git/wine.git"
	export	GENTOO_WINE_EBUILD_COMMON_PACKAGE_URL="https://github.com/bobwya/${GENTOO_WINE_EBUILD_COMMON_PACKAGE}/archive/${GENTOO_WINE_EBUILD_COMMON_PACKAGE_VERSION}.tar.gz"
	export	WINE_STAGING_BINPATCH_URL="https://raw.githubusercontent.com/wine-staging/wine-staging/master/patches/gitapply.sh"

	export	WINE_EBUILD_COMMON="${GENTOO_WINE_EBUILD_COMMON_PACKAGE}-${GENTOO_WINE_EBUILD_COMMON_PACKAGE_VERSION}"

	if ((WINE_STAGING)); then
		set_wine_staging_git_tag 0
		export	__WINE_STAGING_GIT_TAG
	else
		set_wine_git_tag 0
		export	__WINE_GIT_TAG
	fi

	# Global build options and directory defaults
	if [[ -z "${THREADS}" ]]; then
		export THREADS
		THREADS="$(awk '{ threads+=($0 ~ "^processor") }END{ print threads+1 }' /proc/cpuinfo)"
	fi
	export		PREFIX="${PREFIX:-${HOME}/usr}"
	export		SOURCE_ROOT="${SOURCE_ROOT:-${HOME}/Wine/Source}"
	export		WORKING_PATCHES_DIRECTORY="${WORKING_PATCHES_DIRECTORY:-${SOURCE_ROOT}/Patches}"
	export		BUILD_ROOT="${BUILD_ROOT:-${HOME}/Wine/Build}"
	export		LOG_DIRECTORY="${LOG_DIRECTORY:-${BUILD_ROOT}/Logs}"
	export		WINE_CONFIGURATION="${WINE_CONFIGURATION:---without-hal --without-v4l --without-oss}"
	export		WINE_CFLAGS="${WINE_CFLAGS:--march=native -mtune=native}"
	export		WINE_MAKE_OPTIONS="${WINE_MAKE_OPTIONS:--j${THREADS}}"

	# Global schroot constants
	export		LSB_CODENAME
	if [[ -z "${LSB_CODENAME}" ]]; then
		LSB_CODENAME="$(lsb_release -sc)"
		LSB_CODENAME="${LSB_CODENAME,,}"
	fi
	# Reverse-mangle the stupid Linux Mint Release Code Name overrides
	case "${LSB_CODENAME}" in
		tara)
			LSB_CODENAME="bionic";;
		sylvia|sonya|serena|sarah)
			LSB_CODENAME="xenial";;
		rosa|rafaela|rebecca|qiana)
			LSB_CODENAME="trusty";;
		betsy)
			LSB_CODENAME="jessie";;
	esac
	export		CHROOT32_NAME="chroot:${LSB_CODENAME}_wine_32bit"
	export		CHROOT64_NAME="chroot:${LSB_CODENAME}_wine_64bit"
	export		SESSION_WINE_INITIALISE="session:wine_initialise"
	export		SESSION_WINE32="session:wine32"
	export		SESSION_WINE64="session:wine64"
	export 		USERNAME="${USER}"

	# Global build phase constants
	export	SRC_FETCH=1 SRC_PREPARE=2 SRC_CONFIGURE=3 SRC_COMPILE=4 SRC_INSTALL=5

	# Global logging constants
	export 		LOGGING="${LOGGING:-1}"
	parse_boolean_option "${LOGGING}" "LOGGING"
	export		__FIFO_LOG_PIPE
	export		__LOGGING_PID
	__FIFO_LOG_PIPE="$( mktemp -u )"

	# Run whole process set at lowest priority
	renice +19 -p $$ &>/dev/null

	# Cleanup after ourselves with function cleanup()
	# shellcheck disable=SC2173
	trap "trap_exit" ABRT INT QUIT TERM KILL STOP

	# Cleanup any remaining schroot sessions from previous run
	schroot -e -c "${SESSION_WINE_INITIALISE}" &>/dev/null
	schroot -e -c "${SESSION_WINE32}" &>/dev/null
	schroot -e -c "${SESSION_WINE64}" &>/dev/null

	# Process script parameters: options and commands
	if [[ ! -z "${LOG_COMPRESSION}" ]]; then
		set_log_compression "${LOG_COMPRESSION}"
	elif command -v gzip &>/dev/null; then
		set_log_compression "gzip"
	else
		set_log_compression "none"
	fi
	process_command	"${@}"
	check_package_dependencies
	execute_commands

	display_completion_message

	cleanup
}


#### Global Block ####

main "${@}"

exit 0
