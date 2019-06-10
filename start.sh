#!/bin/bash

set -o errexit -o pipefail -o noclobber -o nounset
cd "$(dirname "$0")"

# Import our helper functions
. ./utils.sh

printHelp() {
	echo "Usage:   ./start.sh [environment]"
	echo "Starts ioFog environments and optionally sets up demo and tutorial environment"
	echo ""
	echo "Arguments:"
	echo "    -h, --help        print this help / usage"
	echo "    [environment]     setup demo application, optional, default: iofog"
	echo "                      supported values: iofog, tutorial"
}

checkComposeFile() {
    local ENVIRONMENT="$1"
    local COMPOSE_FILE="docker-compose-${ENVIRONMENT}.yml"
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        echoError "Environment configuration for \"${ENVIRONMENT}\" does not exist!"
        exit 2
    fi
}

startIofog() {
    echoInfo "Building containers for iofog stack..."
    if [ ! -z "$IOFOG_BUILD_NO_CACHE" ]; then
        docker-compose -f "docker-compose-iofog.yml" build --no-cache > /dev/null
    else
        docker-compose -f "docker-compose-iofog.yml" build > /dev/null
    fi

    echoInfo "Spinning up containers for iofog stack..."
    docker-compose -f "docker-compose-iofog.yml" up --detach --no-recreate

    echoInfo "Initializing iofog stack..."
    docker logs -f "iofog-init" # wait for the ioFog stack initialization
    RET=$(docker wait "iofog-init")
    if [[ "$RET" != "0" ]]; then
        echoError "Failed to initialize iofog stack!"
        exit 3
    fi
    echoInfo "Successfully initialized iofog stack."
}

startEnvironment() {
    local ENVIRONMENT="$1"
    local COMPOSE_PARAM="-f docker-compose-${ENVIRONMENT}.yml"

    echoInfo "Building containers for ${ENVIRONMENT} environment..."
    docker-compose -f "docker-compose-iofog.yml" -f "docker-compose-${ENVIRONMENT}.yml" \
        build "${ENVIRONMENT}-init" > /dev/null

    echoInfo "Spinning up containers for ${ENVIRONMENT} environment..."
    docker-compose -f "docker-compose-iofog.yml" -f "docker-compose-${ENVIRONMENT}.yml" \
        up --detach --no-recreate "${ENVIRONMENT}-init"

    echoInfo "Initializing ${ENVIRONMENT} environment..."
    docker logs -f "${ENVIRONMENT}-init" # wait for the ioFog stack initialization
    RET=$(docker wait "${ENVIRONMENT}-init")
    if [[ "$RET" != "0" ]]; then
        echoError "Failed to initialize ${ENVIRONMENT} environment!"
        exit 3
    fi
    echoInfo "Successfully setup ${ENVIRONMENT} environment."
    echoInfo "It may take a while before ioFog stack creates all ${ENVIRONMENT} microservices."
}

ENVIRONMENT=''
while [[ "$#" -ge 1 ]]; do
    case "$1" in
        -h|--help)
            printHelp
            exit 0
            ;;
        *)
            if [[ -n "${ENVIRONMENT}" ]]; then
                echoError "Cannot specify more than one environment!"
                printHelp
                exit 1
            fi
            ENVIRONMENT=$1
            shift
            ;;
    esac
done
IOFOG_BUILD_NO_CACHE=${IOFOG_BUILD_NO_CACHE:=""} # by default, use docker cache to build images
ENVIRONMENT=${ENVIRONMENT:="iofog"} # by default, setup only the ioFog stack

prettyHeader "Starting ioFog Demo (\"${ENVIRONMENT}\" environment)..."

checkComposeFile "iofog"
if [[ "${ENVIRONMENT}" != "iofog" ]]; then checkComposeFile "${ENVIRONMENT}"; fi

# Create a new ssh key
echoInfo "Creating new ssh key for tests..."
rm -f test/conf/id_ecdsa*
ssh-keygen -t ecdsa -N "" -f test/conf/id_ecdsa -q
cp -f test/conf/id_ecdsa.pub services/iofog/iofog-agent/

# Start ioFog stack
# TODO check if this environment is up or not
startIofog

# Optionally start another environment
if [[ "${ENVIRONMENT}" != "iofog" ]]; then
    # TODO check if this environment is up or not
    startEnvironment "${ENVIRONMENT}";
fi

# Display the running environment
prettyTitle "ioFog Demo Environment is now running"
echoInfo "  $(docker ps)"
echo
echoSuccess "## iofog-controller is running at http://localhost:$(docker port iofog-controller | awk '{print $1}' | cut -b 1-5)"
if [[ "${ENVIRONMENT}" == "tutorial" ]]; then
    echoSuccess "## Visit https://iofog.org/docs/1.0.0/tutorial/introduction.html to continue with the ioFog tutorial."
fi
