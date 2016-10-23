#!/bin/bash


declare -r	SCRIPT_PATH=$(readlink -f $0)
export SCRIPT_NAME=$(basename "${SCRIPT_PATH}")

#### Global Environment Variables - change these as desired!! ####
#export 		LOG_COMPRESSOR="cat"
export 		SOURCE_ROOT="${HOME}/Packages/Ubuntu/Wine/Source"
export 		BUILD_ROOT="${HOME}/Packages/Ubuntu/Wine/Build"
export 		WINE_VERSION="master"
export		STAGING=true

#### Global Environment Variable defaults ####

# Global build options and directories
[[ -z "${THREADS}" ]] && declare -r THREADS="$(awk '{ threads+=($0 ~ "^processor") }END{ print threads+1 }' /proc/cpuinfo)"
declare -r	PREFIX="${PREFIX:-${HOME}/usr}"
declare -r	SOURCE_ROOT="${SOURCE_ROOT:-${HOME}/Wine/Source}"
declare -r	BUILD_ROOT="${BUILD_ROOT:-${HOME}/Wine/Build}"
declare -a	USER_PATCHES_DIRECTORY_ARRAY[0]="${USER_PATCHES_DIRECTORY:-${SOURCE_ROOT}/Patches}"
declare -r	BUILD_LOG_DIRECTORY="${BUILD_LOG_DIRECTORY:-${BUILD_ROOT}/Logs}"
declare -r	WINE_CONFIG_OPTIONS="${WINE_CONFIG_OPTIONS} --without-hal --without-v4l --without-oss"
declare -r	WINE_CFLAGS="${WINE_CFLAGS} -march=native -mtune=native"
declare -r	WINE_MAKE_OPTIONS="${WINE_MAKE_OPTIONS} -j${THREADS}"


# Schroot global constants
export		LSB_CODENAME="$(lsb_release -sc)"
export		CHROOT32_NAME="chroot:${LSB_CODENAME}_wine_32bit"
export		CHROOT64_NAME="chroot:${LSB_CODENAME}_wine_64bit"
export		SESSION_WINE_INITIALISE="session:wine_initialise"
export		SESSION_WINE32="session:wine32"
export		SESSION_WINE64="session:wine64"
export 		USERNAME="${USER}"

# Global build phase constants
declare -r	SRC_FETCH=1 SRC_PREPARE=2 SRC_CONFIGURE=3 SRC_COMPILE=4 SRC_INSTALL=5


# Logging global constants
export 		GLOBAL_LOGGING=true
export		FIFO_LOG_PIPE="${BUILD_LOG_DIRECTORY}/fifo_log_pipe"
export		logging_PID


# Gemeral global constants
declare -r	SHA1_REGEXP="^[[:xdigit:]]{40}$"
declare -r	VERSION_REGEXP="^[[:digit:]]{1,2}\.[[:digit:]]{1,2}(\.[[:digit:]]{1,2}|)(\-rc[[:digit:]]{1}|)$"
declare -r	STABLE_VERSION_REGEXP="^1\.8\.[[:digit:]]{1,2}$"

#### General Helper Functions Definition Block ####

# cleanup ()
function cleanup ()
{
	sleep 1
	if [[ -p "${FIFO_LOG_PIPE}" ]]; then
		rm "${FIFO_LOG_PIPE}"
	fi
	if [[ ! -z "${logging_PID}" ]]; then
		kill -9 ${logging_PID}
	fi
	schroot -e --all-sessions  &>/dev/null
	[[ "${GLOBAL_LOGGING}" == false || -z "${COMPRESSOR_CMD}" || -z "${BUILD_LOG}" || ! -f "${BUILD_LOG}" ]] \
		&& return 0

	${COMPRESSOR_CMD} "${BUILD_LOG}"
}

# trap_exit ()
function trap_exit ()
{
	printf "\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYRED_BOLD}" "${TTYRESET}"
	cleanup
	exit
}

# die ()
#   1>  : Error Message
#   2>  : Error Code (default: 1)
function die ()
{
	local error_code=${2:-1}
	local function_call="${FUNCNAME[ 1 ]:-main}"
	local error_message="${1}"
	
	[[ -p "${FIFO_LOG_PIPE}" ]] && printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
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
	if [[ "${1}" == true ]]; then
		export	TTYRED="$( tput setaf 1 )"
		export	TTYGREEN="$( tput setaf 2 )"
		export	TTYYELLOW="$( tput setaf 3 )"
		export	TTYBLUE="$( tput setaf 4 )"
		export	TTYPURPLE="$( tput setaf 5 )"
		export	TTYCYAN="$( tput setaf 6 )"
		export	TTYWHITE="$( tput setaf 7 )"
		export	TTYRED_BOLD="$( tput setaf 1 ; tput bold )"
		export	TTYGREEN_BOLD="$( tput setaf 2 ; tput bold )"
		export	TTYYELLOW_BOLD="$( tput setaf 3 ; tput bold )"
		export	TTYBLUE_BOLD="$( tput setaf 4 ; tput bold )"
		export	TTYPURPLE_BOLD="$( tput setaf 5 ; tput bold )"
		export	TTYCYAN_BOLD="$( tput setaf 6 ; tput bold )"
		export	TTYWHITE_BOLD="$( tput setaf 7 ; tput bold )"
		export	TTYRESET="$( tput sgr0 )"
		export	TTYBOLD_on="$( tput bold )"
	else
		export	TTYRED=""
		export	TTYGREEN=""
		export	TTYYELLOW=""
		export	TTYBLUE=""
		export	TTYPURPLE=""
		export	TTYCYAN=""
		export	TTYWHITE=""
		export	TTYRED_BOLD=""
		export	TTYGREEN_BOLD=""
		export	TTYYELLOW_BOLD=""
		export	TTYBLUE_BOLD=""
		export	TTYPURPLE_BOLD=""
		export	TTYCYAN_BOLD=""
		export	TTYWHITE_BOLD=""
		export	TTYRESET=""
		export	TTYBOLD_on=""
	fi
}

# pushd_wrapper ()
#  >1	directory to pass to pushd
function pushd_wrapper ()
{
	local directory="${1}"

	printf "${TTYBLUE_BOLD}" &>"${FIFO_LOG_PIPE}"
	pushd "${directory}" &>"${FIFO_LOG_PIPE}" || die "pushd \"${directory}\" failed" $?
	printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
}

# popd_wrapper ()
function popd_wrapper ()
{
	printf "${TTYBLUE_BOLD}" &>"${FIFO_LOG_PIPE}"
	popd &>"${FIFO_LOG_PIPE}" || die "popd failed" $?
	printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
}

# set_wine_version ()
#	>1	: Wine (or Wine-Staging) version (SHA-1 commit hash, branch or version)
#	>2	: Enable Wine-Staging support? [true|false]
function set_wine_version ()
{
	local	wine_version="${1}"
	local	staging_enabled="${2}"

	# Setup Wine or Wine-Staging version to build
	if [[ "${wine_version}" =~ SHA1_REGEXP && "${wine_version}" =~ VERSION_REGEXP && "${wine_version}" != "master" ]]; then
		[[ "${staging_enabled}" == true  ]] && die "Unsupported Wine-Staging version specified: \"${wine_version}\""
		[[ "${staging_enabled}" == false ]] && die "Unsupported Wine version specified: \"${wine_version}\""
	fi
	if [[ "${staging_enabled}" == false ]]; then
		# Disable Wine-Staging support
		unset -v	WINE_STAGING_VERSION
		export		STAGING=false
		export		WINE_VERSION="${wine_version}"
	else
		# Enable Wine-Staging support
		export		STAGING=true
		export		WINE_STAGING_VERSION="${wine_version}"
		export		WINE_VERSION="${wine_version}"
	fi
}

# set_global_colour
#  >1  set global colour [yes | no]
set_global_colour ()
{
	local option="${1}"
	if [ -z "${option}" ]; then
		usage_information
		die "no colour option ([yes|no]) specified"
	fi
	case "${option}" in
		[Nn][Oo]|[Nn])
			export GLOBAL_COLOUR=false;;
		[Yy][Ee][Ss]|[Yy])
			export GLOBAL_COLOUR=true;;
		*)
			usage_information
			die "unknown colour specifier \"${option}\"";;
	esac
}

# set_global_logging ()
#  >1  set_global_logging [yes | no]
set_global_logging ()
{
	local option="${1}"
	if [ -z "${option}" ]; then
		usage_information
		die "no logging option ([yes|no]) specified"
	fi
	case "${option}" in
		[Nn][Oo]|[Nn])
			export GLOBAL_LOGGING=false;;
		[Yy][Ee][Ss]|[Yy])
			export GLOBAL_LOGGING=true;;
		*)
			usage_information
			die "unknown logging specifier \"${option}\"";;
	esac
}

# set_log_compression ()
#   >1	: compressor executable or extension
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
	[[ -p "${FIFO_LOG_PIPE}" ]] && rm -f "${FIFO_LOG_PIPE}"
	mkfifo -m=rw "${FIFO_LOG_PIPE}" &>/dev/null || die "mkfifo failed"
	# Use a FIFO to compress all log file output in a background shell
	if [[ "${GLOBAL_LOGGING}" == true ]]; then
		# Make Log directory
		if [[ "${command}" == "setup" ]]; then
			export BUILD_LOG="${BUILD_LOG_DIRECTORY}/chroot-setup_$(date --iso-8601=seconds).log"
		elif [[ "${command}" == "upgrade" ]]; then
			export BUILD_LOG="${BUILD_LOG_DIRECTORY}/chroot-upgrade_$(date --iso-8601=seconds).log"
		elif [[ "${STAGING}" == true ]]; then
			export BUILD_LOG="${BUILD_LOG_DIRECTORY}/wine-staging-${WINE_STAGING_VERSION}_$(date --iso-8601=seconds).log"
		else
			export BUILD_LOG="${BUILD_LOG_DIRECTORY}/wine-staging-${WINE_VERSION}_$(date --iso-8601=seconds).log"
		fi
		[[ -d "${BUILD_LOG_DIRECTORY}" ]] || mkdir -p "${BUILD_LOG_DIRECTORY}" &>/dev/null
		rm "${BUILD_LOG}" &>/dev/null
		(
			trap "cleanup" ABRT INT QUIT KILL TERM
			while [[ -p "${FIFO_LOG_PIPE}" ]]; do
				cat < "${FIFO_LOG_PIPE}" | tee -a "${BUILD_LOG}"
			done
			printf "\n%sCompleted!!%s\n" "${TTYYELLOW_BOLD}" "${TTYRESET}"
		) &
	else
		(
			trap "cleanup" ABRT INT QUIT KILL TERM
			while [[ -p "${FIFO_LOG_PIPE}" ]]; do
				cat < "${FIFO_LOG_PIPE}"
			done
			printf "\n%sCompleted!!%s\n" "${TTYYELLOW_BOLD}" "${TTYRESET}"
		) &
	fi
	logging_PID=$!
}

# check_package_dependencies ()
check_package_dependencies ()
{
	local package_list package

	for package in "awk" "debootstrap" "git" "mkfifo" "schroot" "sed" "wget"; do
		which "${package}" &>/dev/null || package_list="${package_list} ${package}"
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
	[[ -z "${package_list}" ]] || die "please install the (above) required packages and re-run this script"
}

# usage_information ()
usage_information ()
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
	printf "Using dual (32-bit and 64-bit) Chroot (schroot) Environments.\n\n" >&2
	printf "Build phases can be individually selected/specified.\n\n" >&2

	printf "%scommand%s(s) :\n" "${TTYCYAN_BOLD}" "${TTYRESET}" >&2
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
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "--wine-version[=][SHA-1|branch|version] | --wine-staging-version[=][SHA-1|branch|version]" "${TTYRESET}" ${indent} "" "" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Specify Wine (or Wine-Staging) version to build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "Using one of:" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" " • SHA-1 Git hash" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" " • Git branch name" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" " • Numeric version (e.g. 1.9.20 1.8.5-rc1)" >&2

	printf "%*s%s%*s%s%*s%s\n\n" \
		$((indent)) "" "${TTYGREEN}" ${gopt_col_width} "" "${TTYRESET}" ${indent} "" "are all supported.                        [default=Wine master]" >&2
	printf "\n" >&2
	printf "%sBUILD-OPTION%s :\n" "${TTYYELLOW}" "${TTYRESET}" >&2
	printf "\n" >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "--build-directory" "${TTYRESET}" ${indent} "" "Specify build (binaries) target directory." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "--log-directory" "${TTYRESET}" ${indent} "" "Specify directory in which log files will be created during build." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "--patch-directory" "${TTYRESET}" ${indent} "" "Specify directory containing user patch files." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "" "${TTYRESET}" ${indent} "" "Can be specified more than once." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "--source-directory" "${TTYRESET}" ${indent} "" "Specify directory to store source files." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "" "${TTYRESET}" ${indent} "" "Note: this can be specified more than once." >&2
	printf "%*s%s%*s%s%*s%s\n" \
		$((indent)) "" "${TTYYELLOW}" ${bopt_col_width} "--prefix" "${TTYRESET}" ${indent} "" "Specify prefix directory for installation phase." >&2
	printf "\n" >&2
}

# display_completion_message ()
function display_completion_message ()
{
	if [[ "${COMMAND}" != "build" ]]; then
		printf "\n%s%s%s: %sChroot-${COMMAND} has completed successfully%s ...\n" \
			"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
	else
		local	-a build_phases
		build_phases[SRC_FETCH]="src-fetch"
		build_phases[SRC_PREPARE]="src-prepare"
		build_phases[SRC_CONFIGURE]="src-configure"
		build_phases[SRC_COMPILE]="src-compile"
		build_phases[SRC_INSTALL]="src-install"

		local phases_completed="" 
		local i count=0
		for (( i=SRC_FETCH ; i<=SRC_INSTALL ; ++i)); do
			[[ "${SUBCOMMANDS[i]}" == false ]] && continue
			
			phases_completed="${phases_completed},${build_phases[i]}"
			: $((++count))
		done
		((count==1)) && phases_completed="Build phase: ${phases_completed:1}; has completed successfully, "
		((count!=1)) && phases_completed="Build phases: ${phases_completed:1}; have completed successfully, "
		if [[ -f "${SOURCE_ROOT}/wine/VERSION" ]]; then
			local	wine_version=$( cat "${SOURCE_ROOT}/wine/VERSION" )
			printf "\n%s%s%s: %s${phases_completed} for ${wine_version}%s ...\n" \
					"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
		else
			printf "\n%s%s%s: %s${phases_completed}%s ...\n" \
				"${TTYGREEN_BOLD}" "${SCRIPT_NAME}" "${TTYRESET}" "${TTYWHITE}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
		fi
	fi
}

#### Build Helper Functions Definition Block ####

# create_main_directories ()
function create_main_directories ()
{
	local directory
	for directory in "${SOURCE_ROOT}" "${BUILD_ROOT}"/{wine32,wine64,wine32_tools}; do
		# Make Source & Build directories
		[[ -d "${directory}" ]] && continue

		mkdir -p "${directory}" &>"${FIFO_LOG_PIPE}" \
			|| die "mkdir -p \"${directory}\" failed"
	done
}

# clean_build_directories ()
#   1 .. N>  : Build directories
clean_build_directories ()
{
	local -a directories_array=( "${@}" )

	local -r directories_count=${#directories_array[@]}
	local i
	for i in ${!directories_array[*]}; do
		[[ -d "${directories_array[i]}" ]] || continue
		rm -rf "${directories_array[i]}"/* &>"${FIFO_LOG_PIPE}" || die "rm -rf \"${directories_array[i]}\"/* failed"
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
	[[ -d "${git_directory}" ]] && return 0

	git clone "${git_repository_url}" &>"${FIFO_LOG_PIPE}" || die "git clone \"${git_repository_url}\" failed" $?
}

# git_pull_and_checkout ()
#   1>  : Git directory
#   2<  : Git commit, branch, or tag
#   3>  : Prefix for Git tags
#   4>  : Suffix for Git tags
function git_pull_and_checkout ()
{
	local git_directory="${SOURCE_ROOT}/${1}"
	local git_version="${2}"
	local git_tag_prefix="${3:-wine-}"
	local git_tag_suffix="${4:-}"

	pushd_wrapper "${git_directory}"
	git clean -f &>"${FIFO_LOG_PIPE}" || die "git clean -f failed" $?
	git reset --hard "master" &>"${FIFO_LOG_PIPE}"  || die "git reset --hard \"master\" failed" $?
	git checkout "master" &>"${FIFO_LOG_PIPE}" || die "git checkout \"master\" failed" $?
	git pull &>"${FIFO_LOG_PIPE}" || die "git pull failed" $?
	if [[ "${git_version}" =~ ${VERSION_REGEXP} ]]; then
		if [[ "${git_version}" =~ ${STABLE_VERSION_REGEXP} ]]; then
			git_version="${git_tag_prefix}${git_version}${git_tag_suffix}"
		else
			git_version="${git_tag_prefix}${git_version}"
		fi
	fi
	git checkout "${git_version}" &>"${FIFO_LOG_PIPE}" || die "git checkout \"${git_version}\" failed" $?
	git reset --hard "${git_version}" &>"${FIFO_LOG_PIPE}" || die "git reset --hard \"${git_version}\" failed" $?
	popd_wrapper
}

# wine_staging_get_upstream_commit ()
#   1>  : Wine-Staging Git directory
#   2>  : Wine-Staging Git commit or branch
# ( 3<  : Upstream (Wine) Git commit )
function wine_staging_get_upstream_commit ()
{
	local git_directory="${SOURCE_ROOT}/${1}"
	local downstream_git_commit="${2}"
	local __git_commit_retvar="${3}"
	
	[[ "${WINE_STAGING_VERSION}" =~ ${SHA1_REGEXP} ]] || local wine_staging_type="branch"
	[[ "${WINE_STAGING_VERSION}" =~ ${SHA1_REGEXP} ]] && local wine_staging_type="commit"
	pushd_wrapper "${git_directory}"
	local git_commit=$( patches/patchinstall.sh --upstream-commit )
	if [[ ! "${git_commit}" =~ ${SHA1_REGEXP} ]]; then
		die "Unable to get Wine commit corresponding to Wine-Staging ${wine_staging_type} \"${downstream_git_commit}\""
	else
		printf "Checking out Wine commit: %s${git_commit}%s ; corresponding to Wine-Staging ${wine_staging_type}: %s${downstream_git_commit}%s\n" \
				"${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYGREEN_BOLD}" "${TTYBLUE_BOLD}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
	fi
	popd_wrapper

	if [[ -z "${__git_commit_retvar}" ]]; then
		echo "${git_commit}"
	else
		eval $__git_commit_retvar="'${git_commit}'"
	fi
}

# apply_user_patches ()
# 1>  : Source root directory to which to apply p1 formmatted patchset
# 2>  : Directory containing set of p1 format patches to apply
function apply_user_patches ()
{
	local source_directory="${SOURCE_ROOT}/${1}"
	local patches_directory="${2}"
	local patch_directories_count="${#USER_PATCHES_DIRECTORY_ARRAY[@]}"
	local patch_directory patch_file

	pushd_wrapper "${source_directory}"
	local i
	for ((i=0;i<patch_directories_count;++i)); do
		patch_directory="${USER_PATCHES_DIRECTORY_ARRAY[i]}"
		if [[ ! -d "${patch_directory}" ]]; then
			printf "%sIgnoring non-existent user patch directory%s: \"%s${patch_directory}%s\"\n" \
					"${TTYRED}" "${TTYGREEN_BOLD}" "${TTYBLUE}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
			continue
		fi
		printf "%sApplying patches from user patch directory%s: \"%s${patch_directory}%s\" ...\n\n" \
				"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYBLUE}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
		for patch_file in "${patch_directory}"/*.patch; do
			printf "%sApplying patch file%s: \"%s${patch_file}%s\" ...\n" \
				"${TTYCYAN}" "${TTYGREEN_BOLD}" "${TTYBLUE}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
			printf "${TTYYELLOW}" &>"${FIFO_LOG_PIPE}"
			if ! patch --dry-run --verbose -p1 < "${patch_file}" &>"${FIFO_LOG_PIPE}"; then
				die "patch file: ${patch_file} failed to apply\n" $?
			fi
			printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
			patch -p1 < "${patch_file}" &>/dev/null
		done
	done
	popd_wrapper
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

	printf "${TTYPURPLE}" &>"${FIFO_LOG_PIPE}"
	schroot -b -c "${chroot}" -u "${user}" -n "${session}"
	(($?==0)) || die "schroot -b -c \"${chroot}\" -u \"${user}\" -n \"${session}\" (session start) failed"
	printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
}

# schroot_session_run ()
#	1>	: Schroot session name
#	2>  : Schroot session user
#	3>  : Schroot start directory
function schroot_session_run ()
{
	local -r	session="session:${1#session:}" \
				user="${2}" \
				directory="${3:-${PWD}}"
	shift 3
	local -a commands_array=( "${@}" )

	local -r command_count=${#commands_array[@]}
	local i
	printf "${TTYCYAN}" &>"${FIFO_LOG_PIPE}"
	for i in ${!commands_array[*]}; do
		schroot -r -c "${session}" -d "${directory}" -- sh -c "${commands_array[i]}" &>"${FIFO_LOG_PIPE}"
		(($?==0)) || die "schroot -r -c \"${session}\" -d \"${directory}\" -- ${commands_array[i]} (session run) failed"
	done
	printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
}

# schroot_session_cleanup ()
#	1>	: Schroot session name
function schroot_session_cleanup ()
{
	local -r session="session:${1#session:}"

	printf "${TTYPURPLE}" &>"${FIFO_LOG_PIPE}"
	schroot -e -c "${session}" &>"${FIFO_LOG_PIPE}"
	printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
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
	printf "${TTYPURPLE}" &>"${FIFO_LOG_PIPE}"
	debootstrap --variant=buildd --arch=${architecture} ${LSB_CODENAME} \
			"/srv/chroot/${chroot_name}" "${UBUNTU_MIRROR_URI}" &>"${FIFO_LOG_PIPE}"
	printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
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
	sed -i -e 's:^#[[:blank:]]*deb-src :deb-src :g' "${chroot_path}/etc/apt/sources.list"
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
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
	
	clean_build_directories "${BUILD_ROOT}/wine64" "${BUILD_ROOT}/wine32" "${BUILD_ROOT}/wine32_tools" \
							"${SOURCE_ROOT}/wine" "${SOURCE_ROOT}/wine-staging"
	pushd_wrapper "${SOURCE_ROOT}"
	# Fetch Wine-Staging Git Source (if required).
	# Checkout desired Wine version in Wine-Staging Git tree (clean and update first!!)
	if [[ "${STAGING}" == true ]]; then
		git_clone "https://github.com/wine-compholio/wine-staging.git" &>"${FIFO_LOG_PIPE}"
		git_pull_and_checkout "wine-staging" "${WINE_STAGING_VERSION}" "v" "-unofficial"
		if [[ "${WINE_STAGING_VERSION}" =~ ${SHA1_REGEXP} || "${WINE_STAGING_VERSION}" == "master" ]]; then
			wine_staging_get_upstream_commit "wine-staging" "${WINE_STAGING_VERSION}" "WINE_VERSION"
		fi
	fi

	# Fetch Wine Git Source (if required). Checkout desired Wine version in Wine Git tree (clean and update first!!)
	git_clone "git://source.winehq.org/git/wine.git" &>"${FIFO_LOG_PIPE}"
	git_pull_and_checkout "wine" "${WINE_VERSION}"
	popd_wrapper
}

# src_prepare ()
function src_prepare ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
	
	# Apply Wine-Staging patchset first
	if [[ ! -z "${WINE_STAGING_VERSION}" && -d "${SOURCE_ROOT}/wine-staging" ]]; then
		(
			pushd_wrapper "${SOURCE_ROOT}/wine-staging"
			printf "${TTYCYAN}" &>"${FIFO_LOG_PIPE}"
			patches/patchinstall.sh DESTDIR="${SOURCE_ROOT}/wine" --all &>"${FIFO_LOG_PIPE}" \
				|| die "Wine-Staging patchinstall.sh failed" $?
			printf "${TTYRESET}" &>"${FIFO_LOG_PIPE}"
			popd_wrapper
		)
	fi

	# Apply any custom patches. Put these in your USER_PATCHES_DIRECTORY directory ...
	apply_user_patches "wine" "${USER_PATCHES_DIRECTORY}"
}

# multilib_src_configure ()
function multilib_src_configure ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"

	export	CFLAGS="${WINE_CFLAGS}"

	# Configure 64-bit wine64
	pushd_wrapper "${BUILD_ROOT}/wine64"
	[[ -f "Makefile" ]] && schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
								"make clean"
	schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
		"'${SOURCE_ROOT}/wine/configure' ${WINE_CONFIG_OPTIONS} --enable-win64 --prefix='${PREFIX}'"
	popd_wrapper
	
	# Configure 32-bit wine32_tools
	pushd_wrapper "${BUILD_ROOT}/wine32_tools"
	[[ -f "Makefile" ]] && schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
								"make clean"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"'${SOURCE_ROOT}/wine/configure' ${WINE_CONFIG_OPTIONS} --prefix='${PREFIX}'"
	popd_wrapper
	
	# Configure multilib wine32
	pushd_wrapper "${BUILD_ROOT}/wine32"
	[[ -f "Makefile" ]] && schroot_session_run "${SESSION_WINE64}" "${USERNAME}" "" \
								"make clean"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"'${SOURCE_ROOT}/wine/configure' ${WINE_CONFIG_OPTIONS} --with-wine64='${BUILD_ROOT}'/wine64"\
"										--with-wine-tools='${BUILD_ROOT}'/wine32_tools --prefix='${PREFIX}'"
	popd_wrapper
}

# multilib_src_compile ()
function multilib_src_compile ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"

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
	
	# Build multilib wine32
	pushd_wrapper "${BUILD_ROOT}/wine32"
	schroot_session_run "${SESSION_WINE32}" "${USERNAME}" "" \
		"make ${WINE_MAKE_OPTIONS}"
	popd_wrapper
}

# multilib_src_install ()
function multilib_src_install ()
{
	printf "\n\n%s${FUNCNAME[ 0 ]} ()%s ... \n" "${TTYGREEN_BOLD}" "${TTYRESET}" &>"${FIFO_LOG_PIPE}"

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

# process_command ()
#  >1-N		:  commands and options (passed as CLI parameters)
function process_command ()
{
	if which gzip &>/dev/null; then
		set_log_compression "gzip"
	else
		set_log_compression "none"
	fi
	
	# Process options
	local option="${1}"
	local build_options
	while (($# >= 1)); do
		case "${option}" in

			--build-directory|--build-dir|--log-directory|--log-dir|--patch-directory|--patch-dir|--source-directory|--source-dir|--prefix|--prefix-directory|--prefix-dir)
				local	directory_type=$(echo "${option}" | sed '{s:^\-\-::g;s:\-directory$::g}')
				if (($# == 1)); then
					usage_information
					die "${directory_type} directory not specified"
				fi
				local directory=$(readlink -f "${option}")
				parent_directory=$(get_parent_directory "${directory}")
				if [[ ! -d "${parent_directory}" ]]; then
					die "${directory_type} directory parent does exist"
				fi
				case "${directory_type}" in
					build)		export BUILD_ROOT="${directory}";;
					log)		export BUILD_LOG_DIRECTORY="${directory}";;
					patch)		export USER_PATCHES_DIRECTORY_ARRAY[${#USER_PATCHES_DIRECTORY_ARRAY[@]}]="${directory}";;
					source)		export SOURCE_ROOT="${directory}";;
					prefix)		export PREFIX="${directory}";;
				esac
				build_options="${build_options} ${option}"
				option="-"
				;;

			-c=*|--color=*|--colour=*)
				set_global_colour "${option#*=}"
				setup_tty_colours ${GLOBAL_COLOUR}
				option="-"
				;;

			-c|--color|--colour)
				if (($# == 1)); then
					usage_information
					die "no colour option specified"
				fi
				shift 1
				option="$1"
				set_global_colour "${option}"
				setup_tty_colours ${GLOBAL_COLOUR}
				option="-"
				;;

			--logging=*|--log=*)
				set_global_logging "${option#*=}"
				option="-"
				;;

			-logging|--log)
				if (($# == 1)); then
					usage_information
					die "no logging option specified"
				fi
				set_global_logging "${option}"
				option="-"
				;;

			--log-compression=*)
				set_log_compression "${option#*=}"
				option="-"
				;;

			--log-compression)
				if (($# == 1)); then
					usage_information
					die "no compression option specified"
				fi
				shift 1
				option="$1"
				set_log_compression "${option}"
				option="-"
				;;

			--wine-version=*|--wine-staging-version=*)				
				if [[ "${option}" =~ staging ]]; then
					local	staging=true
				else
					local 	staging=false
				fi
				set_wine_version "${option#*=}" ${staging}
				build_options="${build_options} ${option}"
				option="-"
				;;

			--wine-version|--wine-staging-version)
				if [[ "${option}" =~ staging ]]; then
					local	staging=true
				else
					local 	staging=false
				fi
				if (($# == 1)); then
					usage_information
					if [[ "${staging}" == true ]]; then
						die "Wine-Staging version not specified"
					else
						die "Wine version not specified"
					fi
				fi
				shift 1
				option="$1"
				set_wine_version "${option}"  ${staging}
				build_options="${build_options} ${option}"
				option="-"
				;;

			--)
				shift 1
				break 2
				;;
			--*)
				usage_information
				die "unknown option specified: \"${1}\""
				;;
			*)
				break 2
				;;
		esac
		if [[ "${option}" == "-" ]]; then
			shift 1
			option="${1}"
		fi
	done
	build_options="${build_options:1}"
	# Process commands
	if (($# < 1)); then
		usage_information
		die "no command specified"
	fi
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
			
		setup-chroot|setup)
			if [[ ! -z "${COMMAND}" ]]; then
				usage_information
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""
			elif [[ ! -z "${build_options}" ]]; then
				usage_information
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\""
			fi
			export	COMMAND="setup"
			;;
		
		upgrade-chroot|upgrade|update-chroot|update)
			if [[ ! -z "${COMMAND}" ]]; then
				usage_information
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""
			elif [[ ! -z "${build_options}" ]]; then
				usage_information
				die "build-option(s): \"${build_options}\" ; are incompatible with command: \"${new_command}\""
			fi
			export	COMMAND="upgrade"
			;;
			
		src-fetch|src-prepare|src-configure|src-compile|src-install|build|build-all)
			if [[ "${COMMAND}" =~ setup|upgrade ]]; then
				usage_information
				die "incompatible command(s) specified : \"${prev_command}\" \"${new_command}\""
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
			usage_information
			die "unknown command specified: \"${new_command}\""
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
	setup)
		if [[ ! -z "${OPTIONS}" ]]; then
			usage_information
			die "invalid option(s) specified: ${OPTIONS}"
		fi
		setup_logging "${COMMAND}"
		export -f schroot_session_start schroot_session_run schroot_session_cleanup \
					cleanup die get_ubuntu_mirror bootstrap_schroot_image \
					setup_chroot_build_env upgrade_chroot_build_env
		su -p -c '
			printf "\n${TTYWHITE_BOLD}Detecting Ubuntu Mirror (with the lowest ping)${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			declare		UBUNTU_MIRROR_URI
			UBUNTU_MIRROR_URI="$(get_ubuntu_mirror)"
			printf "\n${TTYWHITE_BOLD}Creating 32-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			bootstrap_schroot_image ''"${LSB_CODENAME}_wine_32bit"'' "i386"
			printf "\n${TTYWHITE_BOLD}Creating 64-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			bootstrap_schroot_image ''"${LSB_CODENAME}_wine_64bit"'' "amd64"
			printf "\n${TTYWHITE_BOLD}Installing Ubuntu image to 32-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			setup_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
			printf "\n${TTYWHITE_BOLD}Installing Ubuntu image to 64-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			setup_chroot_build_env ''"${LSB_CODENAME}_wine_64bit"''
			printf "\n${TTYWHITE_BOLD}Install Updated Wine Development packages to 32-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
			printf "\n${TTYWHITE_BOLD}Install Updated Wine Development packages to 64-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
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
			printf "\n${TTYWHITE_BOLD}Upgrade Wine Development packages in 32-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_32bit"''
			printf "\n${TTYWHITE_BOLD}Upgrade Wine Development packages in 64-bit Chroot Environment${TTYRESET} ...\n" &>"${FIFO_LOG_PIPE}"
			upgrade_chroot_build_env ''"${LSB_CODENAME}_wine_64bit"''
		' root || die "Failed to upgrade Chroot environments"
		;;
	build)
		(( EUID == 0 )) && die "do not run this script as root, when building Wine!!"
		setup_logging "${COMMAND}"
		create_main_directories
		if [[ "${SUBCOMMANDS[SRC_CONFIGURE]}" == true || "${SUBCOMMANDS[SRC_COMPILE]}" == true || "${SUBCOMMANDS[SRC_INSTALL]}" == true ]]; then
			schroot -e --all-sessions
			schroot_session_start "${SESSION_WINE32}" "${USERNAME}" "${CHROOT32_NAME}"
			schroot_session_start "${SESSION_WINE64}" "${USERNAME}" "${CHROOT64_NAME}"
		fi
		[[ "${SUBCOMMANDS[SRC_FETCH]}" == true ]]		&& src_fetch
		[[ "${SUBCOMMANDS[SRC_PREPARE]}" == true ]]		&& src_prepare
		[[ "${SUBCOMMANDS[SRC_CONFIGURE]}" == true ]]	&& multilib_src_configure
		[[ "${SUBCOMMANDS[SRC_COMPILE]}" == true ]]		&& multilib_src_compile
		[[ "${SUBCOMMANDS[SRC_INSTALL]}" == true ]]		&& multilib_src_install
		;;
	esac
}

#### Global Block ####

# Run whole process set at lowest priority
renice +19 -p $$ &>/dev/null

# Cleanup after ourselves with function cleanup ()
trap "trap_exit" ABRT INT QUIT KILL TERM

# Process script parameters: options and commands
set_wine_version "master" false
process_command	"${@}"
check_package_dependencies
execute_commands

display_completion_message

cleanup

exit 0
