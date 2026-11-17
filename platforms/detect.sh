# shellcheck shell=bash
# Sourced by the host scripts (start-browsers.sh, hermes-run.sh). Sets:
#   HERMES_PLATFORM  macos | linux | windows | unknown (an exported value wins over detection)
#   PLATFORM_ENV     platforms/<platform>.env; the file is optional, unset keys are auto-detected
if [[ -z "${HERMES_PLATFORM:-}" ]]; then
  case "$(uname -s)" in
    Darwin) HERMES_PLATFORM=macos ;;
    Linux) HERMES_PLATFORM=linux ;;
    MINGW* | MSYS* | CYGWIN*) HERMES_PLATFORM=windows ;;
    *) HERMES_PLATFORM=unknown ;;
  esac
fi
PLATFORM_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$HERMES_PLATFORM.env"
