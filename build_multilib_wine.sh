#!/bin/bash


#### General Helper Functions Definition Block ####

# cleanup ()
function cleanup ()
{
	sleep 1
	if [[ -p "${__FIFO_LOG_PIPE}" ]]; then
		rm "${__FIFO_LOG_PIPE}" &>/dev/null
	fi
	if [[ ! -z "${__LOGGING_PID}" ]]; then
		kill -9 ${__LOGGING_PID} &>/dev/null
	fi
	schroot -e -c "${SESSION_WINE_INITIALISE}" &>/dev/null
	schroot -e -c "${SESSION_WINE32}" &>/dev/null
	schroot -e -c "${SESSION_WINE64}" &>/dev/null
	[[ "${LOGGING}" == false || -z "${COMPRESSOR_CMD}" || -z "${LOG}" || ! -f "${LOG}" ]] \
		&& return 0

	${COMPRESSOR_CMD} "${LOG}"
}

# trap_exit ()
function trap_exit ()
{
	trap '' ABRT INT QUIT KILL TERM
	printf "\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYRED_BOLD}" "${TTYRESET}"
	cleanup
	exit
}

# die ()
#   1>  : Error Message
#   2>  : Error Code (default: 1)
#	3>  : Display usage (default: false)
function die ()
{
	local error_message="${1}"
	local error_code=${2:-1}
	local usage=${3:-false}
	local function_call="${FUNCNAME[ 1 ]}"

	trap '' ABRT INT QUIT KILL TERM
	[[ -p "${__FIFO_LOG_PIPE}" ]] && printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
	printf "${1}" | awk -vttycyan_bold="${TTYCYAN_BOLD}" -vttyred_bold="${TTYRED_BOLD}" -vttypurple_bold="${TTYPURPLE_BOLD}" \
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
	cleanup
	exit "${error_code}"
}

# setup_tty_colours ()
#  >1  Enable colour support for console (TRUE/FALSE)
function setup_tty_colours ()
{
	local output="/dev/null"
	[[ "${1}" == true ]] &&	output="/dev/stdout"

	export	TTYRED="$( tput setaf 1 >${output} )"
	export	TTYGREEN="$( tput setaf 2 >${output} )"
	export	TTYYELLOW="$( tput setaf 3 >${output} )"
	export	TTYBLUE="$( tput setaf 4 >${output} )"
	export	TTYPURPLE="$( tput setaf 5 >${output} )"
	export	TTYCYAN="$( tput setaf 6 >${output} )"
	export	TTYWHITE="$( tput setaf 7 >${output} )"
	export	TTYBOLD="$( tput bold >${output} )"
	export	TTYRESET="$( tput sgr0 >${output} )"
	export	TTYRED_BOLD="${TTYRED}${TTYBOLD}"
	export	TTYGREEN_BOLD="${TTYGREEN}${TTYBOLD}"
	export	TTYYELLOW_BOLD="${TTYYELLOW}${TTYBOLD}"
	export	TTYBLUE_BOLD="${TTYBLUE}${TTYBOLD}"
	export	TTYPURPLE_BOLD="${TTYPURPLE}${TTYBOLD}"
	export	TTYCYAN_BOLD="${TTYCYAN}${TTYBOLD}"
	export	TTYWHITE_BOLD="${TTYWHITE}${TTYBOLD}"
}

# pushd_wrapper ()
#  >1	directory to pass to pushd
function pushd_wrapper ()
{
	local directory="${1}"

	printf "${TTYBLUE_BOLD}" &>"${__FIFO_LOG_PIPE}"
	pushd "${directory}" &>"${__FIFO_LOG_PIPE}" || die "pushd \"${directory}\" failed" $?
	printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
}

# popd_wrapper ()
function popd_wrapper ()
{
	printf "${TTYBLUE_BOLD}" &>"${__FIFO_LOG_PIPE}"
	popd &>"${__FIFO_LOG_PIPE}" || die "popd failed" $?
	printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
}

# set_wine_git_tag ()
function set_wine_git_tag ()
{
	# Setup Wine version to build
	if [[ ! -z "${WINE_BRANCH}" ]]; then
		if [[ ! "${WINE_BRANCH}" =~ ^(master|origin/master|origin/stable)$ ]]; then
			die "invalid WINE_BRANCH=\"${WINE_BRANCH}\" specified"
		fi
		export	__WINE_GIT_TAG="${WINE_BRANCH}"
		unset -v WINE_COMMIT WINE_VERSION
	elif [[ ! -z "${WINE_COMMIT}" ]]; then
		if [[ ! "${WINE_BRANCH}" =~ ${SHA1_REGEXP} ]]; then
			die "invalid WINE_COMMIT=\"${WINE_BRANCH}\" specified (SHA1 commit hash)"
		fi
		export	__WINE_GIT_TAG="${WINE_COMMIT}"
		unset -v WINE_VERSION
	else
		if [[ ! "${WINE_VERSION}" =~ ${VERSION_REGEXP} ]]; then
			die "invalid WINE_VERSION=\"${WINE_VERSION}\" specified"
		fi
		export	__WINE_GIT_TAG="${WINE_PREFIX}${WINE_VERSION}"
	fi
}

# set_wine_staging_git_tag ()
function set_wine_staging_git_tag ()
{
	# Setup Wine-Staging version to build
	if [[ ! -z "${WINE_STAGING_BRANCH}" ]]; then
		if [[ ! "${WINE_STAGING_BRANCH}" =~ ^(master|latest-release|origin/master|origin/stable)$ ]]; then
			die "invalid WINE_STAGING_BRANCH=\"${WINE_STAGING_BRANCH}\" specified"
		fi
		export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_BRANCH}"
		unset -v WINE_STAGING_COMMIT WINE_VERSION
	elif [[ ! -z "${WINE_STAGING_COMMIT}" ]]; then
		if [[ ! "${WINE_STAGING_BRANCH}" =~ ${SHA1_REGEXP} ]]; then
			die "invalid WINE_STAGING_COMMIT=\"${WINE_STAGING_BRANCH}\" specified (SHA1 commit hash)"
		fi
		export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_COMMIT}"
		unset -v WINE_VERSION
	else
		if [[ ! "${WINE_VERSION}" =~ ${VERSION_REGEXP} ]]; then
			die "invalid WINE_VERSION=\"${WINE_VERSION}\" specified"
		fi
		if [[ "${WINE_VERSION}" =~ 1\.8\.[1-9]*[0-9] ]]; then
			export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_PREFIX}${WINE_VERSION}${WINE_STAGING_SUFFIX}"
		else
			export	__WINE_STAGING_GIT_TAG="${WINE_STAGING_PREFIX}${WINE_VERSION}"
		fi
		export	__WINE_GIT_TAG="${WINE_PREFIX}${WINE_VERSION}"
	fi
}

# parse_boolean_option ()
#	  1>	boolean option string (value)
#   ( 2<	option variable to set to value )
function parse_boolean_option ()
{
	local	__option="${1}"
	local	__option_name_retvar="${2}"
	local	__valid_options="([1|0|yes|no|true|false])"
	local	__option_value

	if [[ -z "${__option}" ]]; then
		die "no ${__option_name_retvar,,} option value specified ${__valid_options}" "" true
	fi
	case "${__option}" in
		0|[Nn][Oo]|[Nn]|[Ff][Aa][Ll][Ss][Ee]|[Ff])
			__option_value=false;;
		1|[Yy][Ee][Ss]|[Yy]|[Tt][Rr][Uu][Ee]|[Tt])
			__option_value=true;;
		*)
			local __option_name="${__option_name_retvar,,}"
			die "unknown ${__option_name//_/-} option value specified: \"${__option}\" ${__valid_options}" "" true;;
	esac

	if [[ -z "${__option_name_retvar}" ]]; then
		echo "${__option_value}"
	else
		eval export $__option_name_retvar="'${__option_value}'"
	fi

}

# set_log_compression ()
#   1>	: compressor executable or extension
function set_log_compression ()
{
	local compressor="${1}"
	case "${compressor}" in
		bzip2|bz2)
			which bzip2 &>/dev/null || die "bzip2 log compression unsupported - bzip2 compressor not detected"
			export COMPRESSOR_CMD="bzip2 -fq -9"
			;;
		gzip|gz)
			which gzip &>/dev/null || die "gzip log compression unsupported - gzip compressor not installed"
			export COMPRESSOR_CMD="gzip -fq -9"
			;;
		lzma)
			which gzip &>/dev/null || die "lzma log compression unsupported - xz compressor not installed"
			export COMPRESSOR_CMD="xz --format=lzma -fq"
			;;
		lzop)
			which lzop &>/dev/null || die "lzop log compression unsupported - lzop compressor not installed"
			export COMPRESSOR_CMD="lzop -fqU -9"
			;;
		lzop)
			which lzop &>/dev/null || die "lzop log compression unsupported - lzop compressor not installed"
			export COMPRESSOR_CMD="lzop -fqU -9"
			;;
		lz4)
			which lz4 &>/dev/null || die "lz4 log compression unsupported - lz4 compressor not installed"
			export COMPRESSOR_CMD="lz4 -cfq -BD -9"
			;;
		xz)
			which lz4 &>/dev/null || die "xz log compression unsupported - xz compressor not installed"
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

# setup_logging ()
function setup_logging ()
{
	local command="${1}"
	mkfifo -m=600 "${__FIFO_LOG_PIPE}" &>/dev/null || die "mkfifo \"${__FIFO_LOG_PIPE}\" failed" $?
	# Use a FIFO to compress all log file output in a background shell
	if [[ "${LOGGING}" == true ]]; then
		# Make Log directory
		LOG=$(date --iso-8601=seconds)
		case "${command}" in
			setup)
				export LOG="${LOG_DIRECTORY}/chroot-setup_${LOG}.log";;
			upgrade)
				export LOG="${LOG_DIRECTORY}/chroot-upgrade_${LOG}.log";;
			build)
				if [[ "${WINE_STAGING}" == true ]]; then
					export LOG="${LOG_DIRECTORY}/wine-staging-${WINE_STAGING_BRANCH:-${WINE_STAGING_COMMIT:-${WINE_VERSION}}}_${LOG}.log"
				else
					export LOG="${LOG_DIRECTORY}/wine-${WINE_BRANCH:-${WINE_COMMIT:-${WINE_VERSION}}}_${LOG}.log"
				fi;;
		esac
		[[ -d "${LOG_DIRECTORY}" ]] || mkdir -p "${LOG_DIRECTORY}" &>/dev/null
		rm "${LOG}" &>/dev/null
	fi
	(
		trap "cleanup" ABRT INT QUIT KILL TERM
		while [[ -p "${__FIFO_LOG_PIPE}" ]]; do
			if [[ "${logging}" == true ]]; then
				cat < "${__FIFO_LOG_PIPE}" | tee -a "${LOG}"
			else
				cat < "${__FIFO_LOG_PIPE}"
			fi
		done
		printf "\n%sLogging completed!!%s\n" "${TTYYELLOW_BOLD}" "${TTYRESET}"
	) &
	__LOGGING_PID=$!
}

# check_package_dependencies ()
function check_package_dependencies ()
{
	local -a array_executables=( "awk" "bzip2" "debootstrap" "git" "lsb_release" "mkfifo" "md5sum" "schroot" "sed" "wget" )
	local executable

	for executable in "${array_executables[@]}"; do
		which "${executable}" &>/dev/null &&	continue
		
		case "${executable}" in
			md5sum|mkfifo)
				package_list="${package_list} coreutils";;
			*)
				package_list="${package_list} ${executable}";;
		esac
	done
	if [[ ! -z "${package_list}" ]]; then
		printf "sudo apt-get install %s${package_list}%s\n" "${TTYCYAN}" "${TTYRESET}" >&2
	elif ! which netselect &>/dev/null; then
		package_list="${package_list} netselect"
		printf "Please manually install the %snetselect%s package from this Debian repository:\n" \
				"${TTYCYAN_BOLD}" "${TTYRESET}" >&2
		printf "  %shttps://packages.debian.org/jessie/amd64/netselect/download%s\n\n" \
				"${TTYBLUE_BOLD}" "${TTYRESET}" >&2
		printf "For example to install the %snetselect%s %sdeb%s package file from the main Debian USA mirror use:\n" \
				"${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYCYAN}" "${TTYRESET}" >&2
		printf "  URL='%shttp://ftp.us.debian.org/debian/pool/main/n/netselect/netselect_0.3.ds1-26_amd64.deb%s' %s;%s\n" \
				"${TTYBLUE_BOLD}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" >&2
		printf "  FILE=\$(%smktemp%s) %s;%s %swget%s \"\${URL}\" -qO \"\${FILE}\" && %ssudo dpkg%s -i \"\${FILE}\" %s;%s %srm%s \"\${FILE}\"\n\n" \
				"${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" \
				"${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
	fi
	[[ -z "${package_list}" ]] || die "please install the (above) required package(s) and re-run this script"
}

# usage_information ()
function usage_information ()
{
	local indent=-2 col_width=-15 bopt_col_width=-20 gopt_col_width=-20

	printf "Usage:\n" >&2
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] %ssetup-chroot%s\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] %supgrade-chroot%s\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] [%sBUILD-OPTION%s(s)] %ssrc-fetch | src-prepare | src-configure | src-compile | src-install%s\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYYELLOW}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
	printf "%*s%s%s%s  [%sGLOBAL-OPTION%s(s)] [%sBUILD-OPTION%s(s)] %sbuild-all%s\n\n" \
		${indent} "" "${TTYPURPLE_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYGREEN}" "${TTYRESET}" "${TTYYELLOW}" "${TTYRESET}" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
		
	printf "Utility to build dual-architecture, multilib Wine on Ubuntu(tm).\n" >&2
	printf "Uses dual (32-bit and 64-bit) Chroot (schroot) Environments.\n\n" >&2
	printf "Consecutive build phases can be selected, chained, and re-run.\n\n" >&2

	printf "%scommand%s(s) :\n" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "generate-conf" "${TTYRESET}" ${indent} "" "Generate default \"${SCRIPT_CONFIG}\" configuration file." >&2
	printf "%*s%s%*s%s%*s%s%s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "setup-chroot" "${TTYRESET}" ${indent} "" "Setup 32-bit and 64-bit Chroot Environments." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "Install Ubuntu base development libraries for Wine" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "in the dual Chroot Environments. " >&2
	printf "%*s%s%*s%s%*s%s%s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "upgrade-chroot" "${TTYRESET}" ${indent} "" "Upgrade Ubuntu base development libraries for Wine" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "in the dual Chroot Environments. " >&2
	printf "%*s%s%*s%s%*s%s%s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "${TTYRED_BOLD}" "This command runs as root." "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYCYAN_BOLD}" ${col_width} "version" "${TTYRESET}" ${indent} "" "Display build version of ${SCRIPT_NAME} ." >&2
	printf "\n\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "(${SRC_FETCH})" "${TTYCYAN_BOLD}" ${col_width} "src-fetch" "${TTYRESET}" ${indent} "" "Run (Git) source fetch phase." >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "(${SRC_PREPARE})" "${TTYCYAN_BOLD}" ${col_width} "src-prepare" "${TTYRESET}" ${indent} "" "Run source preparation (patching) phase." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "If building Wine-Staging - the Staging patches will be" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "applied during this phase." >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "(${SRC_CONFIGURE})" "${TTYCYAN_BOLD}" ${col_width} "src-configure" "${TTYRESET}" ${indent} "" "Run source configuration phase." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "This phase is executed in the dual Chroot Environments." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "Phase includes a make clean operation (if required)." >&2	
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "(${SRC_COMPILE})" "${TTYCYAN_BOLD}" ${col_width} "src-compile" "${TTYRESET}" ${indent} "" "Run source compilation phase." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "This phase is executed in the dual Chroot Environments." >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "(${SRC_INSTALL})" "${TTYCYAN_BOLD}" ${col_width} "src-install" "${TTYRESET}" ${indent} "" "Run installation phase." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "This phase is executed in the dual Chroot Environments." >&2

	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "(${SRC_FETCH})-(${SRC_INSTALL})" "${TTYCYAN_BOLD}" ${col_width} "build-all" "${TTYRESET}" ${indent} "" "Specifies that all phases (see above)" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "will be executed in a chain." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "Note: multiple phases can be specified" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent-6)) "" "${TTYCYAN_BOLD}" ${col_width} "" "${TTYRESET}" ${indent} "" "individually and will be chained together." >&2
	printf "%sGLOBAL-OPTION%s :\n" "${TTYGREEN}" "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--colour[=][y|n|yes|no] | -c[=][y|n|yes|no] " "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Enable/disable colourised console output. [default=no]" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--logging[=][y|n|yes|no]" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Enable/disable logging of operations.     [default=yes]" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--log-compression[=][bzip2|gzip|lzma|lzop|none|lz4|xz]" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify (optional) log file compression.  [default=gzip]" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--log-directory" "${TTYRESET}" ${indent} "" "Specify directory in which log files will be created during build." >&2
	printf "\n" >&2
	printf "%sBUILD-OPTION%s :\n" "${TTYYELLOW}" "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-staging[=][y|n|yes|no]" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify whether to build Wine or Wine-Staging." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-branch[=]branch" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine Git branch to build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-commit[=]SHA-1 commit hash" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine Git commit to build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Use 40 character hexidecimal SHA-1 hash." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-staging-branch[=]branch" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine-Staging Git branch to build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-staging-commit[=]SHA-1 commit hash" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine-Staging Git commit to build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Use 40 character hexidecimal SHA-1 hash." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--wine-version[=]numeric-version" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine (or Wine-Staging) version to build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Use numeric version string (e.g. 1.9.20 1.8.5-rc1)" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--build-directory" "${TTYRESET}" ${indent} "" "Specify build (binaries) target directory." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--patch-directory" "${TTYRESET}" ${indent} "" "Specify directory containing user patch files." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Can be specified more than once." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--source-directory" "${TTYRESET}" ${indent} "" "Specify directory to store source files." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Note: this can be specified more than once." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${gopt_col_width} "--prefix" "${TTYRESET}" ${indent} "" "Specify prefix directory for installation phase." >&2
	printf "\n" >&2
}

# display_completion_message ()
function display_completion_message ()
{
	if [[ "${COMMAND}" != "build" ]]; then
		printf "\n%s%s%s: %sChroot-${COMMAND} has completed successfully%s ...\n" \
			"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
	else
		local	-a build_phases=("" "src-fetch" "src-prepare" "src-configure" "src-compile" "src-install")

		local phases_completed="" 
		local i count=0
		for (( i=SRC_FETCH ; i<=SRC_INSTALL ; ++i)); do
			[[ "${SUBCOMMANDS[i]}" == false ]] && continue
			
			phases_completed="${phases_completed},${build_phases[i]}"
			: $((++count))
		done
		((count==1)) && phases_completed="Build phase: ${phases_completed:1}; has completed successfully, "
		((count!=1)) && phases_completed="Build phases: ${phases_completed:1}; have completed successfully, "
		[[ "${WINE_STAGING}" == false ]] && local	wine_version="${__WINE_VERSION}"
		[[ "${WINE_STAGING}" == true  ]] && local	wine_version="(Staging) ${__WINE_STAGING_VERSION}"
		printf "\n%s%s%s: %s${phases_completed} for Wine ${wine_version}%s ...\n" \
				"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
	fi
}

#### Build Helper Functions Definition Block ####

# create_main_directories ()
#	1...N>	: array of directories to create
function create_main_directories ()
{
	local -a directories_array=( "${@}" )
	local i
	for i in ${!directories_array[*]}; do
		[[ -d "${directories_array[i]}" ]] || continue

		mkdir -p "${directories_array[i]}" &>"${__FIFO_LOG_PIPE}" || die "mkdir -p \"${directories_array[i]}\" failed"
	done
}

# clean_build_directories ()
#   1...N>  : array of build directories to wipe the contents of
clean_build_directories ()
{
	local -a directories_array=( "${@}" )
	local i
	for i in ${!directories_array[*]}; do
		[[ -d "${directories_array[i]}" ]] || continue

		rm -rf "${directories_array[i]}"/* &>"${__FIFO_LOG_PIPE}" \
			|| die "rm -rf \"${directories_array[i]}\"/* failed"
	done	
}

# git_clone ()
# ( 1>  : Git directory )
#   2>  : Git repository URL
function git_clone ()
{
	local git_directory="${SOURCE_ROOT}/${1}"
	local git_repository_url="${@: -1:1}"
	if (($# == 1)); then
		git_directory="${git_repository_url##*/}"
		git_directory="${SOURCE_ROOT}/${git_directory%.*}"
	fi
	[[ -d "${git_directory}/.git" ]] && return 0

	git clone "${git_repository_url}" &>"${__FIFO_LOG_PIPE}" \
		|| die "git clone \"${git_repository_url}\" failed (\"${1}\")" $?
}

# git_pull_and_checkout ()
#   1>  : Git directory
#   2>  : Git commit, branch, or tag
function git_pull_and_checkout ()
{
	local git_directory="${SOURCE_ROOT}/${1}"
	local git_version="${2}"

	pushd_wrapper "${git_directory}"
	git clean -f &>"${__FIFO_LOG_PIPE}" || die "git clean -f failed (\"${1}\")" $?
	git reset --hard "master" &>"${__FIFO_LOG_PIPE}"  || die "git reset --hard \"master\" failed (\"${1}\")" $?
	git checkout "master" &>"${__FIFO_LOG_PIPE}" || die "git checkout \"master\" failed (\"${1}\")" $?
	git pull &>"${__FIFO_LOG_PIPE}" || die "git pull failed (\"${1}\")" $?
	git checkout "${git_version}" &>"${__FIFO_LOG_PIPE}" || die "git checkout \"${git_version}\" failed (\"${1}\")" $?
	git reset --hard "${git_version}" &>"${__FIFO_LOG_PIPE}" || die "git reset --hard \"${git_version}\" failed (\"${1}\")" $?
	popd_wrapper
}

# git_get_commit ()
#   1>  : Git directory
#   2<  : Git commit
function git_get_commit ()
{
	local	git_directory="${SOURCE_ROOT}/${1}"
	local	__git_commit_retvar="${2}"
	local	__git_commit
	
	pushd_wrapper "${git_directory}"
	__git_commit=$(git rev-parse HEAD)
	[[ "${__git_commit}" =~ ${SHA1_REGEXP} ]] || die "git rev-parse HEAD failed (\"${1}\")"
	popd_wrapper

	if [[ -z "${__git_commit_retvar}" ]]; then
		echo "${__git_commit}"
	else
		eval $__git_commit_retvar="'${__git_commit}'"
	fi
}

# git_get_tag ()
#   1>  : Git directory
#   2<  : Git tag
function git_get_tag ()
{
	local	git_directory="${SOURCE_ROOT}/${1}"
	local	__git_tag_retvar="${2}"
	local	__git_tag

	pushd_wrapper "${git_directory}"
	__git_tag=$(git describe --abbrev=0 --tags || die "git describe --abbrev=0 --tags failed")
	popd_wrapper

	if [[ -z "${__git_tag_retvar}" ]]; then
		echo "${__git_tag}"
	else
		eval $__git_tag_retvar="'${__git_tag}'"
	fi
}

# wine_staging_get_upstream_commit ()
#   1>  : Wine-Staging Git directory
#	2>	: Wine-Staging Git commit
# ( 3<  : Upstream (Wine) Git commit )
function wine_staging_get_upstream_commit ()
{
	local	git_directory="${SOURCE_ROOT}/${1}"
	local	__wine_staging_git_commit="${2}"
	local	__git_commit_retvar="${3}"
	local 	__git_commit

	pushd_wrapper "${git_directory}"
	[[ "${__wine_staging_git_commit}" =~ ${SHA1_REGEXP} ]] \
		|| die "invalid Wine-Staging SHA-1 hash commit: \"${__wine_staging_git_commit}\""
	__git_commit=$( patches/patchinstall.sh --upstream-commit )
	[[ "${__git_commit}" =~ ${SHA1_REGEXP} ]] \
		|| die "unable to get Wine commit corresponding to Wine-Staging commit: \"${__wine_staging_git_commit}\""
	printf "%sChecking out Wine commit: %s${__git_commit}%s ; corresponding to Wine-Staging commit: %s${__wine_staging_git_commit}%s\n" \
				"${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
	popd_wrapper

	if [[ -z "${__git_commit_retvar}" ]]; then
		echo "${__git_commit}"
	else
		eval $__git_commit_retvar="'${__git_commit}'"
	fi
}

# process_staging_exclude ()
#	1>	Staging exclude list
# ( 2<	Processed staging exclude list )
function process_staging_exclude ()
{
	local __staging_exclude="${1}"
	local __staging_exclude_retvar="${2}"

	local __processed_staging_exclude=$( echo "${__staging_exclude}" | awk ' \
		{
			for (i=1;i<=NF;++i)
			{
				i += ($i=="-W") ? 1 : 0
				printf("-W %s ", $i)
			}
		}
		END{
			printf("\n")
		}'
	)

	if [[ -z "${__staging_exclude_retvar}" ]]; then
		echo "${__processed_staging_exclude}"
	else
		eval $__staging_exclude_retvar="'${__processed_staging_exclude}'"
	fi
}

# apply_patch_array ()
#	1>  	: Source root directory to which to apply p1 formatted patchset
#	2...N>	: Array of patches to apply to Source root directory
function apply_patch_array ()
{
	local		__source_directory="${SOURCE_ROOT}/${1}"
	local -a	__array_patch_files=("${!2}")
	local		__patch_file
	local		__patch_log
	
	pushd_wrapper "${__source_directory}"
	for __patch_file in "${__array_patch_files[@]}"; do
		[[ -z "${__patch_file}" ]] && continue
		[[ -f "${__patch_file}" ]] || die "patch file \"${__patch_file}\" does not exist"

		printf "%sApplying patch file%s: \"%s${__patch_file}%s\" ...\n" \
			"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
		__patch_log="$(patch --verbose -p1 < "${__patch_file}" || false)"
		if (($?)); then
			printf "${TTYYELLOW}${__patch_log}${TTYRESET}\n" &>"${__FIFO_LOG_PIPE}"
			die "patch file: \"${__patch_file}\" failed to apply\n" $?
		fi
	done
	popd_wrapper
}

# apply_patch_directory ()
#	1>  : Source root directory to which to apply p1 formatted patchset
#	2>	: Patch directory to apply patches from
function apply_patch_directory ()
{
	local source_directory="${1}"
	local patch_directory="${2}"
	local __patch_file

	if [[ ! -d "${patch_directory}" ]]; then
		printf "%sIgnoring non-existent patch directory%s: \"%s${patch_directory}%s\"\n" \
				"${TTYRED_BOLD}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
		return 1
	else
		printf "%sApplying patches from patch directory%s: \"%s${patch_directory}%s\" ...\n" \
				"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYBLUE}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
		local array_patch_files=( "$(find "${patch_directory}" -type f -name "*.patch")" )
		apply_patch_array "${source_directory}" array_patch_files[@]
	fi
}

# apply_user_patches ()
# 1>  : Source root directory to which to apply p1 formatted patchset
function apply_user_patches ()
{
	local source_directory="${1}"
	local patch_directories_count="${#USER_PATCH_DIRECTORIES[@]}"
	local patch_directory

	local i
	for ((i=0;i<patch_directories_count;++i)); do
		[[ "${USER_PATCH_DIRECTORIES[i]+valid}" ]] || continue

		patch_directory="${USER_PATCH_DIRECTORIES[i]}"
		apply_patch_directory "${source_directory}" "${patch_directory}"
	done
}


#### Network Helper Functions Definition Block ####

# get_ubuntu_mirror ()
#	1>	: Minimum number of connection tries
#	2>  : Maximum TTL
# ( 3<  : Fastest local Ubuntu Mirror )
get_ubuntu_mirror ()
{
	local __min_conn_attempts="${1:-10}"
	local __max_TTL="${2:-32}"
	local __ubuntu_mirror_uri_retvar="${3}"
	local __ubuntu_mirror_list __ubuntu_mirror_uri


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
		netselect -s1 -t${__min_conn_attempts} -m${__max_TTL} ${__ubuntu_mirror_list} 2>/dev/null | awk '{print $2}'
	)
	if [[ -z "${__ubuntu_mirror_uri_retvar}" ]]; then
		echo "${__ubuntu_mirror_uri}"
	else
		eval $__ubuntu_mirror_uri_retvar="'${__ubuntu_mirror_uri}'"
	fi
}


#### Schroot / Chroot Function Definition Block ####

# schroot_session_start ()
#	1>	: Schroot session name
#	2>  : Schroot session user
#	3>  : Schroot chroot name
function schroot_session_start ()
{
	local	session="${1#session:}" \
			user="${2}" \
			chroot="chroot:${3#chroot:}"

	printf "${TTYPURPLE}" &>"${__FIFO_LOG_PIPE}"
	schroot -b -c "${chroot}" -u "${user}" -n "${session}" &>"${__FIFO_LOG_PIPE}"
	(($?==0)) || die "schroot -b -c \"${chroot}\" -u \"${user}\" -n \"${session}\" (session start) failed"
	printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
}

# schroot_session_run ()
#	1>		: Schroot session name
#	2>		: Schroot session user
#	3>		: Schroot start directory
#	4...N>	: Array of commands to run in Schroot environment
function schroot_session_run ()
{
	local -r	session="session:${1#session:}" \
				user="${2}" \
				directory="${3:-${PWD}}"
	shift 3
	local -a commands_array=( "${@}" )

	local -r command_count=${#commands_array[@]}
	local i
	printf "${TTYCYAN}" &>"${__FIFO_LOG_PIPE}"
	for i in ${!commands_array[*]}; do
		schroot -r -c "${session}" -d "${directory}" -- sh -c "${commands_array[i]}" &>"${__FIFO_LOG_PIPE}"
		(($?==0)) || die "schroot -r -c \"${session}\" -d \"${directory}\" -- ${commands_array[i]} (session run) failed"
	done
	printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
}

# schroot_session_cleanup ()
#	1...N>	: Array of Schroot session name(s) to delete
function schroot_session_cleanup ()
{
	local -r sessions_array=( "${@}" )
	local sessions

	printf "${TTYPURPLE}" &>"${__FIFO_LOG_PIPE}"
	for session in "${sessions_array[@]}"; do
		sessions="${sessions} -c session:${session#session:}"
	done
	schroot -e ${sessions} &>"${__FIFO_LOG_PIPE}"
	printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
}

# bootstrap_schroot_image()
#	1>  : Schroot chroot name
#	2>  : Schroot architecture (32-bit or 64-bit)
bootstrap_schroot_image ()
{
	local -r chroot_name="${1}"
	local -r architecture="${2}"
	local -r lsb_description="$(lsb_release -sd)"
	local -r chroot_path="/srv/chroot/${chroot_name}"

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
directory=/srv/chroot/${chroot_name}
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
		sed -i -e "\|${path}|h; \${x;s|${path}||;{g;t};a\\" -e "${path}" -e "}" "/etc/schroot/default/copyfiles"
	done
	printf "${TTYPURPLE}" &>"${__FIFO_LOG_PIPE}"
	debootstrap --variant=buildd --arch=${architecture} ${LSB_CODENAME} \
			"/srv/chroot/${chroot_name}" "${UBUNTU_MIRROR_URI}" &>"${__FIFO_LOG_PIPE}"
	printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
}

# setup_chroot_build_env()
#	1>  : Schroot chroot name
setup_chroot_build_env ()
{
	local -r	chroot_name="${1}"
	local -r	session="${SESSION_WINE_INITIALISE}"
	local -r	session_directory="/var/lib/schroot/session/"
	local -r	locale_lang="$( locale | awk -F'=' '$1=="LANG" { print $2 }' )"
	local -r	chroot_path="/srv/chroot/${chroot_name}"
	
	[[ -d "${session_directory}" ]] || mkdir -p "${session_directory}"
	schroot_session_start "${session}" "root" "${chroot_name}"
	rm "${chroot_path}"/etc/{protocols,services} &>/dev/null
	schroot_session_run "${session}" "root" "/" \
		"apt-get install -q=2 ubuntu-minimal software-properties-common" \
		"dpkg-reconfigure --frontend=noninteractive locales" \
		"update-locale LANG=${locale_lang}"
	schroot_session_run "${session}" "root" "/" \
		"add-apt-repository -y 'deb ${UBUNTU_MIRROR_URI} ${LSB_CODENAME} main universe'"
	schroot_session_cleanup "${session}"
}

#		"dpkg-reconfigure locales" \
#		"locale-gen ${locale_lang}" \
		
# upgrade_chroot_build_env()
#	1>  : Schroot chroot name
upgrade_chroot_build_env ()
{
	local -r	chroot_name="${1}"
	local -r	session="${SESSION_WINE_INITIALISE}"
	local -r	chroot_path="/srv/chroot/${chroot_name}"
	
	sed -i	-e 's/^#[[:blank:]]*deb-src[[:blank:]]\+/deb-src /g' \
			-e '/^deb[[:blank:]]\+.*[[:blank:]]\+${LSB_CODENAME}[[:blank:]]\+main[[:blank:]]*$/d' \
			"${chroot_path}/etc/apt/sources.list"
	schroot_session_start "${session}" "root" "${chroot_name}"
	schroot_session_run "${session}" "root" "/" \
		"apt-get update    -q=2" \
		"apt-get install   -q=2 ubuntu-minimal" \
		"apt-get install   -q=2 libva-dev libgtk-3-dev libudev-dev libgphoto2-dev libcapi20-dev libsane-dev" \
		"apt-get build-dep -q=2 wine-development" \
		"apt-get upgrade   -q=2"
	schroot_session_cleanup "${session}"
}

#### Package Phases Function Definition Block ####

# src_fetch ()
function src_fetch ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
	
	clean_build_directories "${BUILD_ROOT}/wine64" "${BUILD_ROOT}/wine32" "${BUILD_ROOT}/wine32_tools" \
							"${SOURCE_ROOT}/wine" "${SOURCE_ROOT}/wine-staging"
	pushd_wrapper "${SOURCE_ROOT}"
	# Fetch Wine-Staging Git Source (if required).
	# Checkout desired Wine version in Wine-Staging Git tree (clean and update first!!)
	if [[ "${WINE_STAGING}" == true ]]; then
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

# src_prepare ()
function src_prepare ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"

	local	wine_regex="{s/[^[:blank:]]$/& /;s/([[:xdigit:]]{40}|$)/${__WINE_COMMIT}/}"	
	local	md5hash="$(md5sum "${SOURCE_ROOT}/wine/server/protocol.def" || die "md5sum failed")"

	# (1) Apply base (bundled) & working patches (Wine version dependent)
	local -a	array_patch_files=(
					"${SCRIPT_DIRECTORY}/Patches/wine-1.5.26-winegcc.patch"
					"${SCRIPT_DIRECTORY}/Patches/wine-1.6-memset-O3.patch"
					"${SCRIPT_DIRECTORY}/Patches/wine-1.7.12-osmesa-check.patch"
					"${SCRIPT_DIRECTORY}/Patches/wine_winecfg_detailed_version.patch"
				)
	if [[ "${__WINE_VERSION}" =~ ^(1\.8|1\.8\.[123](\-unofficial|)|1\.9\.[0-9]|1\.9\.1[0-2])$ ]]; then
		array_patch_files+=( "${SCRIPT_DIRECTORY}/Patches/wine-1.8-gnutls-3.5-compat.patch" )
	fi
	if [[ "${__WINE_VERSION}" =~ ^(1\.8|1\.8\.[12](\-unofficial|)|1\.9\.[0-8])$ ]]; then
		array_patch_files+=( "${SCRIPT_DIRECTORY}/Patches/wine-sysmacros.patch" )
	fi
	mkdir -p "${WORKING_PATCHES_DIRECTORY}"	
	if [[ "${__WINE_VERSION}" =~ ^(1\.8|1\.8\..*|1\.9\.[01])$ ]]; then
		# Apply Gentoo patch to enable support for GStreamer 1.0 libraries (vs. obsolete GStreamer 0.1 libraries)
		pushd_wrapper "${WORKING_PATCHES_DIRECTORY}"
		wget -c "${GSTREAMER_PATCH_URL}" &>"${__FIFO_LOG_PIPE}" || die "wget -c \"${GSTREAMER_PATCH_URL}\" failed"
		bunzip2 -fq "${__GSTREAMER10_PATCH}.patch.bz2"  &>"${__FIFO_LOG_PIPE}" || die "bunzip2 -fq \"${__GSTREAMER10_PATCH}.patch.bz2\" failed"
		if [[ "${__WINE_VERSION}" == "1.9.1" ]]; then
			sed -i -e '1,71d' "${__GSTREAMER10_PATCH}.patch" &>"${__FIFO_LOG_PIPE}" || die "sed failed"
		fi
		popd_wrapper
		array_patch_files+=( "${WORKING_PATCHES_DIRECTORY}/${__GSTREAMER10_PATCH}.patch")
	fi
	apply_patch_array "wine" array_patch_files[@]

	# (2) Apply Wine-Staging patchset
	if [[ "${WINE_STAGING}" == true && -d "${SOURCE_ROOT}/wine-staging" ]]; then
		(
			local	staging_exclude
			process_staging_exclude "${WINE_STAGING_EXCLUDE}" "staging_exclude"
			pushd_wrapper "${SOURCE_ROOT}/wine-staging"
			printf "%sApplying Wine-Staging patchset %s...\n%spatchinstall.sh %sDESTDIR=\"%s${SOURCE_ROOT}/wine%s\" --no-autoconf --all ${staging_exclude}%s\n" \
					"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYCYAN_BOLD}" "${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYGREEN_BOLD}" "${TTYCYAN}" &>"${__FIFO_LOG_PIPE}"
			patches/patchinstall.sh DESTDIR="${SOURCE_ROOT}/wine" --no-autoconf --all ${staging_exclude} &>"${__FIFO_LOG_PIPE}" \
				|| die "Wine-Staging \"${SOURCE_ROOT}/wine-staging/patches/patchinstall.sh\" failed" $?
			printf "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"
			popd_wrapper
		)
		if [[ "${WINE_STAGING_VERSION}" =~ ${VERSION_REGEXP} && "${WINE_STAGING_VERSION}" =~ ${STABLE_VERSION_REGEXP} ]]; then
			# Handle "unofficial" stable Staging versions
			sed -i -e "s/(Staging)/(Staging${WINE_STAGING_SUFFIX})/" "${SOURCE_ROOT}/wine/libs/wine/Makefile.in" || die "sed failed" $?
		fi
		# Update Wine package name for Staging patchset
 		sed -r -i -e '/^AC_INIT\(.*\)$/{s/\[Wine\]/\[Wine \(Staging\)\]/}' "${SOURCE_ROOT}/wine/configure.ac" || die "sed failed" $?
		sed -r -i -e "s/Wine (\\(Staging\\) |)/Wine \\(Staging\\) /" "${SOURCE_ROOT}/wine/VERSION" || die "sed failed" $?
	fi
	# Update Wine version to include git commit
	sed -r -i -e '/^m4_define\(WINE_VERSION.+\)$/{s/\\\(\[\-\.0\-9A\-Za\-z]\+\\\)/\\([-.0-9A-Za-z ]+\\)/}' "${SOURCE_ROOT}/wine/configure.ac" || die "sed failed" $?
	sed -r -i -e "{s/\\-[[:xdigit:]]{40}//; s/[[:blank:]]*$/ ${__WINE_COMMIT}/}" "${SOURCE_ROOT}/wine/VERSION" || die "sed failed" $?

	# (3) Apply user patches. Stored in directories specified in the USER_PATCH_DIRECTORIES[0...N-1] directories array ...
	apply_user_patches "wine"

	pushd_wrapper "${SOURCE_ROOT}/wine"
	# Run autoreconf to update configuration - post application of all patches
	autoreconf &>"${__FIFO_LOG_PIPE}"
	if ! $(md5sum -c - <<<"${md5hash}" &>/dev/null); then
		printf "\"%s${PWD}/protocol.def%s\"%s was patched; running \"%s${PWD}/tools/make_requests%s\" ... \n" \
			"${TTYBLUE_BOLD}" "${TTYRESET}" "${TTYCYAN}" "${TTYCYAN_BOLD}" "${TTYRESET}"  &>"${__FIFO_LOG_PIPE}"
		tools/make_requests || die "\"${PWD}/tools/make_requests\" failed"
	fi
 	popd_wrapper
}

# multilib_src_configure ()
function multilib_src_configure ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"

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

# multilib_src_compile ()
function multilib_src_compile ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"

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

# multilib_src_install ()
function multilib_src_install ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${__FIFO_LOG_PIPE}"

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

# screen_conf_file ()
#	1>	Global configuration file to screen for errors and exploits
function screen_conf_file ()
{
	local __script_conf_file="${1}"

	[[ -z ${__script_conf_file} || ! -f "${__script_conf_file}" ]] \
		&& die "script configuration file: \"${__script_conf_file}\" does not exist"

	awk 'BEGIN{
			regex_whitespace="(^[[:blank:]]*|[[:blank:]]*$)"
			regex_blank_comment_line="^[[:blank:]]*(\#|$)"
			regex_boolean_variables="^(COLOUR|LOGGING|WINE_STAGING)$"
			regex_string_variables="^((BUILD|SOURCE)_ROOT|LOG_(COMPRESSION|DIRECTORY)|PREFIX|THREADS|"\
"WINE_(CFLAGS|CONFIGURATION|MAKE_OPTIONS|VERSION|BRANCH|COMMIT)|WINE_STAGING_(BRANCH|COMMIT|EXCLUDE))$"
			regex_array_string_variables="^(USER_PATCH_DIRECTORIES)$"
			regex_string_value="^\"[^\"]*\"$"
			regex_boolean_value="^(0|1|false|true|no|yes)$"
			regex_array_string_value="^\\([[:blank:]]*(\"[^\"]*\"[[:blank:]]*)+\\)$"
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
				printf("%s(%04d)%s %s%s%s=%s%s%s\n", ttycyan_bold, NR, ttyreset,
										(error1 ? ttyred_bold : ""), variable, (error1 ? ttyreset : ""),
										(error2 ? ttyred_bold : ""), value, (error2 ? ttyreset : ""))
			}
		}
		END{
			exit invalid
		}' "${__script_conf_file}" 2>/dev/null

	return
}

		
# process_command ()
#  	1...N>	:  Array of commands and options (passed as CLI parameters)
function process_command ()
{	
	# Process options
	local option="${1}"
	local build_options
	while (($#)); do
		case "${option}" in
			--build-directory|--build-dir|--log-directory|--log-dir|--patch-directory|--patch-dir|--source-directory|--source-dir|--prefix|--prefix-directory|--prefix-dir)
				local	directory_type=$(echo "${option}" | sed -r 's:(^\-\-|\-directory$|\-dir$)::g')
				[[ "${directory_type}" != "log" ]] && build_options="${build_options} ${option}"
				shift
 				(($#)) ||	 die "invalid option syntax: ${directory_type} directory not specified" "" true
				local directory=$(readlink -f "${1}")
				local parent_directory=$(get_parent_directory "${directory}")
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
				setup_tty_colours ${COLOUR}
				;;

			-c|--color|--colour)
				shift
 				(($#)) ||	die "invalid option syntax: no colour option specified" "" true
				parse_boolean_option "${1}" "COLOUR"
				setup_tty_colours ${COLOUR}
				;;

			--logging=*|--log=*)
				parse_boolean_option "${option#*=}" "LOGGING"
				;;

			-logging|--log)
				shift
 				(($#)) ||	die "invalid option syntax: no logging option specified" "" true
				parse_boolean_option "${1}" "LOGGING"
				;;

			--log-compression=*)
				set_log_compression "${option#*=}"
				;;

			--log-compression)
				shift
				(($#)) ||	die "invalid option syntax: no compression option specified" "" true
				set_log_compression "${1}"
				;;

			--wine-version=*)
				build_options="${build_options} ${option%=*}"
				WINE_VERSION="${option#*=}"
				set_wine_git_tag
				set_wine_staging_git_tag
				;;

			--wine-version)
				build_options="${build_options} ${option}"
				shift
				if (($#==0)); then
					[[ "${WINE_STAGING}" == true ]]  &&	die "invalid option syntax: Wine-Staging version not specified" "" true
					[[ "${WINE_STAGING}" == false ]] &&	die "invalid option syntax: Wine version not specified" "" true
				fi
				WINE_VERSION="${1}"
				set_wine_git_tag
				set_wine_staging_git_tag
				;;

			--wine-staging-branch=*|--wine-staging-commit=*)
				build_options="${build_options} ${option%=*}"
				[[ "${option%=*}" =~ branch$ ]] && WINE_STAGING_BRANCH="${option#*=}"
				[[ "${option%=*}" =~ commit$ ]] && WINE_STAGING_COMMIT="${option#*=}"
				set_wine_staging_git_tag
				;;
				
			--wine-staging-branch|--wine-staging-commit)
				build_options="${build_options} ${option}"
				shift
				(($#)) || die "invalid option syntax: Wine-Staging ${option##*-} not specified" "" true
				[[ "${option}" =~ branch$ ]] && WINE_STAGING_BRANCH="${1}"
				[[ "${option}" =~ commit$ ]] && WINE_STAGING_COMMIT="${1}"
				set_wine_staging_git_tag
				;;

			--wine-branch=*|--wine-commit=*)
				build_options="${build_options} ${option%=*}"
				[[ "${option%=*}" =~ branch$ ]] && WINE_BRANCH="${option#*=}"
				[[ "${option%=*}" =~ commit$ ]] && WINE_COMMIT="${option#*=}"
				set_wine_git_tag
				;;
				
			--wine-branch|--wine-commit)
				build_options="${build_options} ${option}"
				shift
				(($#)) || die "invalid option syntax: Wine ${option##*-} not specified" "" true
				[[ "${option}" =~ branch$ ]] && WINE_BRANCH="${1}"
				[[ "${option}" =~ commit$ ]] && WINE_COMMIT="${1}"
				set_wine_git_tag
				;;
				
			--wine-staging=*|--staging=*)
				build_options="${build_options} ${option%=*}"
				parse_boolean_option "${option#*=}" "WINE_STAGING"
				[[ "${WINE_STAGING}" == true ]] 	&& set_wine_staging_git_tag
				[[ "${WINE_STAGING}" == false ]]	&& set_wine_git_tag
				;;

			--wine-staging|--staging)
				build_options="${build_options} ${option}"
				shift
 				(($#)) || die "invalid option syntax: Wine-Staging option not specified ([yes|no])" "" true
				parse_boolean_option "S{1}" "WINE_STAGING"
				[[ "${WINE_STAGING}" == true ]] 	&& set_wine_staging_git_tag
				[[ "${WINE_STAGING}" == false ]]	&& set_wine_git_tag
				;;


			--)
				unset -v option
				shift
				break 2
				;;

			--*)
				die "unknown option specified: \"${option}\"" "" true
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
 	(($# < 1)) &&	die "no command specified" "" true
	for ((i=SRC_FETCH; i<=SRC_INSTALL; ++i)); do
		SUBCOMMANDS[i]=false
	done
	local	new_command prev_command
	while (( $# > 0 )); do
		new_command="${1}"
		case "${new_command}" in

		help|h)
			usage_information
			exit 0
			;;

		generate-conf|conf)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" true
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" true
			fi
			export	COMMAND="conf"
			;;

		setup-chroot|setup)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" true
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" true
			fi
			export	COMMAND="setup"
			;;
		
		upgrade-chroot|upgrade|update-chroot|update)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""  "" true
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" true
			fi
			export	COMMAND="upgrade"
			;;

		version)
			if [[ ! -z "${COMMAND}" ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""  "" true
			elif [[ ! -z "${build_options}" ]]; then
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\"" "" true
			fi
			export	COMMAND="version"
			;;

		src-fetch|src-prepare|src-configure|src-compile|src-install|build|build-all)
			if [[ "${COMMAND}" =~ setup|upgrade ]]; then
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\"" "" true
			fi
			export	COMMAND="build"
			case "${new_command}" in
				src-fetch)
					SUBCOMMANDS[SRC_FETCH]=true;;
				src-prepare)
					SUBCOMMANDS[SRC_PREPARE]=true;;
				src-configure)
					SUBCOMMANDS[SRC_CONFIGURE]=true;;
				src-compile)
					SUBCOMMANDS[SRC_COMPILE]=true;;
				src-install)
					SUBCOMMANDS[SRC_INSTALL]=true;;
				build|build-all)
					for ((i=SRC_FETCH; i<=SRC_INSTALL; ++i)); do
						SUBCOMMANDS[i]=true
					done;;
			esac
			;;

		*)
			die "unknown command specified: \"${new_command}\""  "" true
			;;

		esac
		prev_command="${new_command}"
		shift 1
	done
}

# execute_commands ()
function execute_commands ()
{
	case "${COMMAND}" in
	conf)
		export DATE_STAMP=$(date)
		printf "\n${TTYWHITE}Generating default configuration file: \"${TTYCYAN_BOLD}${SCRIPT_CONFIG}${TTYRESET}${TTYWHITE}\"${TTYRESET} ...\n"
		su -p -c '
			(
				cat <<EOF_script_config
# 
# ${SCRIPT_CONFIG} - Configuration file for ${SCRIPT_NAME}
#
# Generated by ${SCRIPT_NAME} (${SCRIPT_VERSION}) on ${DATE_STAMP} (build version: ${SCRIPT_VERSION})
#
# Uncomment the default,example options and change these as desired.
#
# Global
#
# COLOUR=${COLOUR}					# default
#
# Directories
#
# Installation prefix directory in which Wine libraries, binaries, etc. are installed.
# PREFIX="${PREFIX}"									# default
#
# Root directory where sources are stored i.e. clones of Wine (and Wine-Staging) Git trees.
# SOURCE_ROOT="${SOURCE_ROOT}"							# default
#
# Root directory where the binary builds are stored - "out-of-tree" build.
# BUILD_ROOT="${BUILD_ROOT}"							# default
#
# Patch files (in -p1 diff format), in these directories, are applied to the Wine source.
# USER_PATCH_DIRECTORIES=( "dir1" "dir2" )
# USER_PATCH_DIRECTORIES+=( "dir3" "dir4" )
#
#
# Versioning
#
# Enable / disable Wine-Staging patchset support.
# WINE_STAGING=${WINE_STAGING}							# default
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
# LOGGING=true											# default
#
# Directory to hold log files - recording all the script operations.
# LOG_DIRECTORY="${LOG_DIRECTORY}"						# default
#
# Compression to be applied to new log files.
# LOG_COMPRESSION="gzip"								# default
#
#
# Building
#
# Number of processor threads to use.
# THREADS="${THREADS}"									# default
#
# Wine-Staging subpatchsets to optionally disable. 		[src-prepare]
# WINE_STAGING_EXCLUDE=""								# default
#
# Configuration options for wine.						[src-configure]
# WINE_CONFIGURATION="${WINE_CONFIGURATION}"			# default
#
# CFLAGS (compile flags) to pass to wine. 				[src-configure]
# WINE_CFLAGS="${WINE_CFLAGS}"							# default
#
# Make options to use when compiling wine. 				[src-compile]
# WINE_MAKE_OPTIONS="${WINE_MAKE_OPTIONS}"				# default
#
EOF_script_config
				) > "${SCRIPT_CONFIG}"
		' root || die "Failed to generate default configuration file: \"${SCRIPT_CONFIG}\""
		;;
	setup)
		if [[ ! -z "${OPTIONS}" ]]; then
			die "invalid option(s) specified: ${OPTIONS}" "" true
		fi
		setup_logging "${COMMAND}"
		export -f schroot_session_start schroot_session_run schroot_session_cleanup \
					cleanup die get_ubuntu_mirror bootstrap_schroot_image \
					setup_chroot_build_env upgrade_chroot_build_env
		su -p -c '
			printf "\n${TTYWHITE_BOLD}Detecting Ubuntu Mirror (with the lowest ping)${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			declare		UBUNTU_MIRROR_URI
			UBUNTU_MIRROR_URI="$(get_ubuntu_mirror)"
			printf "\n${TTYWHITE_BOLD}Creating 32-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			bootstrap_schroot_image ''"${LSB_CODENAME}_wine_32bit"'' "i386"
			printf "\n${TTYWHITE_BOLD}Creating 64-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			bootstrap_schroot_image ''"${LSB_CODENAME}_wine_64bit"'' "amd64"
			printf "\n${TTYWHITE_BOLD}Installing Ubuntu image to 32-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			setup_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
			printf "\n${TTYWHITE_BOLD}Installing Ubuntu image to 64-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			setup_chroot_build_env ''"${LSB_CODENAME}_wine_64bit"''
			printf "\n${TTYWHITE_BOLD}Install Updated Wine Development packages to 32-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
			printf "\n${TTYWHITE_BOLD}Install Updated Wine Development packages to 64-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_64bit"''
		' root || die "Failed to setup Chroot environments"
		;;
	upgrade)
		setup_logging "${COMMAND}"
		export -f schroot_session_start schroot_session_run schroot_session_cleanup \
					cleanup die upgrade_chroot_build_env
		local chroot_name found32bit_chroot=false found64bit_chroot=false
		while read -r chroot_name; do
			[[ "${chroot_name}" == "${CHROOT32_NAME}" ]] && found32bit_chroot=true
			[[ "${chroot_name}" == "${CHROOT64_NAME}" ]] && found64bit_chroot=true
		done < <(schroot -l)
		if [[ "${found32bit_chroot}" == false && "${found64bit_chroot}" == false ]]; then
			if [[ "${found32bit_chroot}" == false ]]; then
				printf "%sChroot Environment%s: \"%s${CHROOT32_NAME}%s\"%s ; has not yet been created.%s\n" \
						"${TTYRED_BOLD}" "${TTYRESET}" "${TTYWHITE_BOLD}" "${TTYRESET}" "${TTYRED_BOLD}" >&2
			fi
			if [[ "${found64bit_chroot}" == false ]]; then
				printf "%sChroot Environment%s: \"%s${CHROOT64_NAME}%s\"%s ; has not yet been created.%s\n" \
						"${TTYRED_BOLD}" "${TTYRESET}" "${TTYWHITE_BOLD}" "${TTYRESET}" "${TTYRED_BOLD}" >&2
			fi
			die "Please run: \"${SCRIPT_NAME} setup-chroot\" ; initially - to setup Chroot Environments"
		fi
		su -p -c '
			printf "\n${TTYWHITE_BOLD}Upgrade Wine Development packages in 32-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
			printf "\n${TTYWHITE_BOLD}Upgrade Wine Development packages in 64-bit Chroot Environment${TTYRESET} ...\n" &>"${__FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_64bit"''
		' root || die "Failed to upgrade Chroot environments"
		;;
	version)
		printf "\n%s${SCRIPT_NAME} version%s: %s${SCRIPT_VERSION}%s ...\n" \
				"${TTYCYAN}" "${TTYRESET}" "${TTYWHITE_BOLD}" "${TTYRESET}"
		;;			
	build)
		(( EUID == 0 )) && die "do not run this script as root, when building Wine!!"
		setup_logging "${COMMAND}"
		create_main_directories "${SOURCE_ROOT}" "${BUILD_ROOT}/wine32" "${BUILD_ROOT}/wine32_tools" "${BUILD_ROOT}/wine64" 
		if [[ "${SUBCOMMANDS[SRC_CONFIGURE]}" == true || "${SUBCOMMANDS[SRC_COMPILE]}" == true || "${SUBCOMMANDS[SRC_INSTALL]}" == true ]]; then
			schroot_session_start "${SESSION_WINE32}" "${USERNAME}" "${CHROOT32_NAME}"
			schroot_session_start "${SESSION_WINE64}" "${USERNAME}" "${CHROOT64_NAME}"
		fi
		[[ "${SUBCOMMANDS[SRC_FETCH]}" == true ]]		&& src_fetch
		if [[ "${WINE_STAGING}" == true ]]; then
			git_get_tag "wine-staging" "__WINE_STAGING_VERSION"
			export __WINE_STAGING_VERSION="${__WINE_STAGING_VERSION#${WINE_STAGING_PREFIX}}"
			git_get_commit "wine-staging" "__WINE_STAGING_COMMIT"
		fi
		git_get_tag "wine" "__WINE_VERSION"
		export __WINE_VERSION="${__WINE_VERSION#${WINE_PREFIX}}"
		git_get_commit "wine" "__WINE_COMMIT"
		[[ "${SUBCOMMANDS[SRC_PREPARE]}" == true ]]		&& src_prepare
		[[ "${SUBCOMMANDS[SRC_CONFIGURE]}" == true ]]	&& multilib_src_configure
		[[ "${SUBCOMMANDS[SRC_COMPILE]}" == true ]]		&& multilib_src_compile
		[[ "${SUBCOMMANDS[SRC_INSTALL]}" == true ]]		&& multilib_src_install
		;;
	esac
}

# main()
function main ()
{
	declare -r	SCRIPT_PATH=$(readlink -f $0)
	declare -r	SCRIPT_DIRECTORY=$(dirname "${SCRIPT_PATH}")
	export		SCRIPT_NAME=$(basename "${SCRIPT_PATH}")
	pushd "${SCRIPT_PATH}" &>/dev/null
	declare	-r	SCRIPT_VERSION="git-$(git log -1 --date=short --format=%cd "${SCRIPT_NAME}")"
	popd &>/dev/null
	export		SCRIPT_CONFIG="/etc/${SCRIPT_NAME%.sh}.conf"

	declare -a	USER_PATCH_DIRECTORIES

	# Read in main parameters from global .conf file for script (default: /etc/build_multilib_wine.conf)
	if [[ -f "${SCRIPT_CONFIG}" ]]; then
		if ! screen_conf_file "${SCRIPT_CONFIG}"; then
			die "invalid lines detected in configuration file \"${SCRIPT_CONFIG}\""
		else
			. "${SCRIPT_CONFIG}"
		fi
	fi

	#### Global Environment Variable defaults ####

	# Global general
	declare		COLOUR="${COLOUR:-false}"
	parse_boolean_option "${COLOUR}" "COLOUR"
	setup_tty_colours ${COLOUR}

	# Global versioning defaults
	declare		WINE_STAGING="${WINE_STAGING:-false}"
	declare		__WINE_COMMIT	__WINE_STAGING_COMMIT
	declare		__WINE_GIT_TAG	__WINE_STAGING_GIT_TAG
	declare		__WINE_VERSION	__WINE_STAGING_VERSION
	
	# Global patch constants
	declare -r 	__GSTREAMER10_PATCH="wine-1.8-gstreamer-1.0"

	# Global URL constants
	declare -r	GSTREAMER_PATCH_URL="https://dev.gentoo.org/~np-hardass/distfiles/wine/${__GSTREAMER10_PATCH}.patch.bz2"
	declare	-r	WINE_STAGING_GIT_URL="https://github.com/wine-compholio/wine-staging.git"
	declare -r	WINE_GIT_URL="git://source.winehq.org/git/wine.git"
	
	# Global versioning constants
	declare -r	SHA1_REGEXP="^[[:xdigit:]]{40}$"
	declare -r	VERSION_REGEXP="^[[:digit:]]{1,2}\.[[:digit:]]{1,2}(\.[[:digit:]]{1,2}|)(\-rc[[:digit:]]{1}|)$"
	declare -r	STABLE_VERSION_REGEXP="^1\.8\.[[:digit:]]{1,2}$"
	declare -r	WINE_STAGING_PREFIX="v"
	declare -r	WINE_STAGING_SUFFIX="-unofficial"
	declare -r	WINE_PREFIX="wine-"
	[[ "${WINE_STAGING}" == true ]] 	&& set_wine_staging_git_tag
	[[ "${WINE_STAGING}" == false ]]	&& set_wine_git_tag
	
	# Global build options and directory defaults
	[[ -z "${THREADS}" ]] && export THREADS="$(awk '{ threads+=($0 ~ "^processor") }END{ print threads+1 }' /proc/cpuinfo)"
	export		PREFIX="${PREFIX:-${HOME}/usr}"
	export		SOURCE_ROOT="${SOURCE_ROOT:-${HOME}/Wine/Source}"
	export		WORKING_PATCHES_DIRECTORY="${WORKING_PATCHES_DIRECTORY:-${SOURCE_ROOT}/Patches}"
	export		BUILD_ROOT="${BUILD_ROOT:-${HOME}/Wine/Build}"
	export		LOG_DIRECTORY="${LOG_DIRECTORY:-${BUILD_ROOT}/Logs}"
	export		WINE_CONFIGURATION="${WINE_CONFIGURATION:---without-hal --without-v4l --without-oss}"
	export		WINE_CFLAGS="${WINE_CFLAGS:--march=native -mtune=native}"
	export		WINE_MAKE_OPTIONS="${WINE_MAKE_OPTIONS:--j${THREADS}}"
	
	# Global schroot constants
	export		LSB_CODENAME="$(lsb_release -sc)"
	export		CHROOT32_NAME="chroot:${LSB_CODENAME}_wine_32bit"
	export		CHROOT64_NAME="chroot:${LSB_CODENAME}_wine_64bit"
	export		SESSION_WINE_INITIALISE="session:wine_initialise"
	export		SESSION_WINE32="session:wine32"
	export		SESSION_WINE64="session:wine64"
	export 		USERNAME="${USER}"

	# Global build phase constants
	declare -r	SRC_FETCH=1 SRC_PREPARE=2 SRC_CONFIGURE=3 SRC_COMPILE=4 SRC_INSTALL=5

	# Global logging constants
	export 		LOGGING="${LOGGING:-true}"
	export		__FIFO_LOG_PIPE="$( mktemp -u )"
	export		__LOGGING_PID

	# Run whole process set at lowest priority
	renice +19 -p $$ &>/dev/null

	# Cleanup after ourselves with function cleanup ()
	trap "trap_exit" ABRT INT QUIT KILL TERM

	# Cleanup any remaining schroot sessions from previous run
	schroot -e -c "${SESSION_WINE_INITIALISE}" &>/dev/null
	schroot -e -c "${SESSION_WINE32}" &>/dev/null
	schroot -e -c "${SESSION_WINE64}" &>/dev/null
	
	# Process script parameters: options and commands
	if [[ ! -z "${LOG_COMPRESSION}" ]]; then
		set_log_compression "${LOG_COMPRESSION}"
	elif which gzip &>/dev/null; then
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