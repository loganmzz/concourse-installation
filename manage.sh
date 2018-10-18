#!/usr/bin/env bash

set -euo pipefail

basedir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

all_services=(db s3 vault web worker)

function __require_container() {
    local container="$1"
    local filters=(-f "name=^/${container}\$")
    while [[ $# > 1 ]]; do
        filters+=(-f "$1"); shift
    done
    [[ "$(docker container ls -qa "${filters[@]}" | wc -l)" > 0 ]]
}

function __get_status() {
    local container="$1"
    case "$(docker container ls -a -f "name=^/${container}\$" --format "{{.Status}}")" in
        Up\ *\(Paused\))
            echo "paused"
            ;;
        Up\ *)
            echo "running"
            ;;
        Exited\ *|Created)
            echo "stopped"
            ;;
        '')
            echo "removed"
            ;;
        *)
            echo "unknown"
            ;;
    esac

}

function __get_image() {
    local container="$1"
    docker container ls -a -f "name=^/${container}$" --format "{{.Image}}"
}

service_network='concourse'
function __check_network() {
    [[ "$(docker network ls -q -f "name=^${service_network}$" | wc -l)" == 1 ]]
}
function __clear_network() {
    local rc=0
    __check_network && {
        echo "Remove network '${service_network}'"
        docker network rm "${service_network}"; rc=$?
    }
    return "${rc}"
}
function __create_network() {
    local rc=$?
    if [[ "${rc}" == 0 ]] && ! __check_network; then
        echo "Create network '${service_network}'"
        docker network create --label 'project=concourse' "${service_network}"; rc=$?
    fi
    return "${rc}"
}

function __load_service_definition() {
    [[ ! -f "${basedir}/.service-${service}.shrc" ]] && {
        echo "Unknown service: ${service}" >&2
        return 1
    }
    . "${basedir}/.service-${service}.shrc"
}

function __do_cmd_start() {
    opt_clear=false
    opt_pull=false
    opt_services=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --clear)
                opt_clear=true
                shift
                ;;
            --pull)
                opt_pull=true
                shift
                ;;
            --*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
            *)
                opt_services=("$@")
                break
                ;;
        esac
    done

    if [[ "${#opt_services[@]}" == 0 ]]; then
        opt_services=("${all_services[@]}")
    fi
    __create_network
    for service in "${opt_services[@]}"; do
        (
            function do_post_clear() { :; }
            function do_post_start() { :; }
            function do_create() {
                echo "Service creation has not been implemented" >&2
                return 1
            }
            __load_service_definition
            __start_service
        )
    done
}

function __clear_service() {
    local clear="${1}"
    local rc=0
    __require_container "${service_container}" && {
        echo "  ¤  Remove container ${service_container}"
        local opt_rm=(-f)
        [[ "${clear}" == 'true' ]] && opt_rm+=(-v)
        docker rm "${opt_rm[@]}" "${service_container}"; rc=$?
        [[ "${clear}" == 'true' ]] && do_post_clear
    }
    return "${rc}"
}

function __start_service() {
    local clear="${opt_clear}"
    "${opt_pull}" && {
        echo "  ¤  Update image ${service_image}"
        docker pull "${service_image}"
    }
    ! "${clear}" && __require_container "${service_container}" && {
        local current_image="$(__get_image "${service_container}")"
        [[ "${current_image}" != "${service_image}" ]] && {
            echo "  ¤  Container ${service_container} image is outdated: '${current_image}' -> '${service_image}'"
            clear='update'
        }
    }

    [[ "${clear}" != 'false' ]] && __clear_service "${clear}"

    case "$(__get_status "${service_container}")" in
        running)
            echo "  ¤  Container ${service_container} is already started"
            ;;
        stopped)
            echo "  ¤  Start container ${service_container}"
            docker start "${service_container}"
            do_post_start
            ;;
        removed)
            echo "  ¤  Create container ${service_container}"
            do_create
            ;;
        paused)
            echo "  ¤  Unpause container ${service_container}"
            docker unpause "${service_container}"
            ;;
        *)
            echo "Can't start service ${service}: current status is not known" >&2
            return 1
            ;;
    esac
}

function __do_cmd_stop() {
    local opt_services=("$@")
    [[ "${#opt_services[@]}" == 0 ]] && opt_services=("${all_services[@]}")

    local errors=()
    for service in "${opt_services[@]}"; do
        __load_service_definition 2>/dev/null || {
            errors+=("'${service}'")
            continue
        }
        echo "  ¤  Stop container ${service_container}"
        docker stop "${service_container}"
    done
    [[ "${#errors[@]}" > 0 ]] && {
        echo "Unsupported services: ${errors[@]}" >&2
    }
}

function __do_cmd_status() {
    local opt_services=("$@")
    [[ "${#opt_services[@]}" == 0 ]] && opt_services=("${all_services[@]}")

    local format="%-20s   %-10s\n"
    printf "${format}" "SERVICE" "STATUS"
    local errors=()
    for service in "${opt_services[@]}"; do
        __load_service_definition 2>/dev/null || {
            errors+=("'${service}'")
            continue
        }
        printf "${format}" "${service}" "$(__get_status "${service_container}")"
    done
    [[ "${#errors[@]}" > 0 ]] && {
        echo "Unsupported services: ${errors[@]}" >&2
    }
}

function __do_cmd_clear() {
    opt_services=("$@")
    if [[ "${#opt_services[@]}" == 0 ]]; then
        opt_services=("${all_services[@]}")
    fi
    for service in "${opt_services[@]}"; do
        (
            function do_post_clear() { :; }
            __load_service_definition
            __clear_service true || true
        )
    done
    __clear_network || true
}


function __do_cmd_get_fly() {
    local fly="${1:-./fly}"
    wget 'http://concourse.dev.localhost/api/v1/cli?arch=amd64&platform=linux' -O "${fly}" && chmod +x "${fly}"
}

function __do_cmd_vault() {
    docker exec -i 'concourse-vault' vault "$@"
}

function __do_cmd_s3() {
    service=s3
    __load_service_definition
    do_exec_mc_operate_file "$@"
}

function __do_cmd_help() {
    cat <<EOF
Helps managing Concourse environment

Commands:

  - help: Displays this help message

  - start: Start containers in background

  - stop: Stop containers

  - status: Print containers status

  - get-fly: Download fly

  - vault: Execute a vault command

  - s3 ls   [options] <path>: List "path"
       cat  [options] <path>: Print "path" content
       pipe [options] <path>: Write from STDIN to target "path"
       rm   [options] <path>: Remove "path"

EOF
}

function __main() {
    local command=""
    if [ $# -gt 0 ]; then
        command="$1"
        shift
    fi

    local command_fn="__do_cmd_${command/-/_}"
    if [[ "$(type -t "${command_fn}")" == "function" ]]; then
        "${command_fn}" "$@"
        echo
        echo "*** SUCCESSFUL ***"
        echo
    else
        echo "Unsupported command '${command}'" >&2
        __do_cmd_help >&2
        exit 1
    fi
}

__main "$@"
