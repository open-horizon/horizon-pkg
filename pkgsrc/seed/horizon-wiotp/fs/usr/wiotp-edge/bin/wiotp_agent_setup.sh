# This scripts install the ANAX Horizon agent and configures it to run the WIoTP Edge IoT Core Worload
# 
# Pre-requisite to run:
#  wget
#  curl 
#  Openssl

#!/bin/bash

usage() {
    cat <<EOF
Usage: $0 [options] 

Arguments:
  
  -h, --help
    Display this usage message and exit.

  -o <val>, --org <val>, --org=<val>
    (Required) Organization Id.

  -dt <val>, --deviceType <val>, --deviceType=<val>
    (Required) Device or Gateway type.

  -di <val>, --deviceId <val>, --deviceId=<val>
    (Required) Device or Gateway Id.

  -dp <val>, --deviceToken <val>, --deviceToken=<val>
    (Required) Device or Gateway Token.

  -r <val>, --region <val>, --region=<val>
    (Optional) Organization Region: us | uk | ch | de . Default is us.
    Use us for US South and East
    Use uk for United Kingdom
    Use ch for China
    Use de for Germany

  -dm <val>, --domain <val>, -domain=<val>
    (Optional) WIoTP internet domain. Default is internetofthings.ibmcloud.com.

  -cn <val>, --edgeCN <val>, -edgeCN=<val>
    (Optional) Common Name (CN) to be used when generating the Server Certificate for the Edge Connector.

  --cloudDisableCertCheck <true|false>, --cloudDisableCertCheck=<true|false>
    (Optional) Sets the CloudDisableCertCheck property for the Edge Connector configuration file. Using true will ignore non-trusted server certificates. 
    Enabling this property on production environments is not recommended.

EOF
}

# handy logging and error handling functions
log() { printf '%s\n' "$*"; }
error() { log "ERROR: $*" >&2; }
fatal() { error "$*"; exit 1; }
usage_fatal() { error "$*"; usage >&2; exit 1; }

fancyLog() {
	echo ""
	echo "**************************************************************"
	echo $1
	echo "**************************************************************"
	echo ""
}

# Optional arguments
WIOTP_INSTALL_REGION="us"
WIOTP_INSTALL_DOMAIN="internetofthings.ibmcloud.com"

while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # convert "--opt=the value" to --opt "the value".
        # the quotes around the equals sign is to work around a
        # bug in emacs' syntax parsing
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -o|--org) shift; WIOTP_INSTALL_ORGID=$1;;
        -dt|--deviceType) shift; WIOTP_INSTALL_DEVICE_TYPE=$1;;
        -di|--deviceId) shift; WIOTP_INSTALL_DEVICE_ID=$1;;
        -dp|--deviceToken) shift; WIOTP_INSTALL_DEVICE_TOKEN=$1;;
        -te|--testEnv) shift; WIOTP_INSTALL_TEST_ENV=$1;;
        -r|--region) shift; WIOTP_INSTALL_REGION=$1;;
        -dm|--domain) shift; WIOTP_INSTALL_DOMAIN=$1;;
        -cdc|--cloudDisableCertCheck) shift; CDCC_TEMP=$1;;
        -cn|--edgeCN) shift; WIOTP_INSTALL_EDGE_CN=$1;;
        -h|--help) usage; exit 0;;
        -*) usage_fatal "unknown option: '$1'";;
        *) break;; # reached the list of file names
    esac
    shift || usage_fatal "option '${arg}' requires a value"
done

# Check if a required option was not set
#if [[ -z $WIOTP_INSTALL_DEVICE_ID || -z  $WIOTP_INSTALL_DEVICE_TYPE || -z $WIOTP_INSTALL_DEVICE_ID  || -z $WIOTP_INSTALL_DEVICE_TOKEN ]]; then
if [[ -z $WIOTP_INSTALL_DEVICE_ID ]] || [[ -z $WIOTP_INSTALL_DEVICE_TYPE ]] || [[ -z $WIOTP_INSTALL_DEVICE_ID ]] || [[ -z $WIOTP_INSTALL_DEVICE_TOKEN ]]; then
  usage_fatal "Values for the following options are required: --org, --deviceType, --deviceId, --deviceToken"
fi
# Check valid regions
if [[ "${WIOTP_INSTALL_REGION}" != "us" && "${WIOTP_INSTALL_REGION}" != "uk" && "${WIOTP_INSTALL_REGION}" != "de" && "${WIOTP_INSTALL_REGION}" != "ch" ]];then
    usage_fatal "Invalid region."
fi

WIOTP_INSTALL_EC_DISABLE_CERT_CHECK=false
case $CDCC_TEMP in
  (true)    WIOTP_INSTALL_EC_DISABLE_CERT_CHECK=true;;
esac

# fancyLog "$0 script arguments:"
# echo WIOTP_INSTALL_ORGID=$WIOTP_INSTALL_ORGID
# echo WIOTP_INSTALL_DEVICE_TYPE=$WIOTP_INSTALL_DEVICE_TYPE
# echo WIOTP_INSTALL_DEVICE_ID=$WIOTP_INSTALL_DEVICE_ID
# echo WIOTP_INSTALL_DEVICE_TOKEN=$WIOTP_INSTALL_DEVICE_TOKEN
# if [ ! -z WIOTP_INSTALL_TEST_ENV ]; then
#   echo WIOTP_INSTALL_TEST_ENV=$WIOTP_INSTALL_TEST_ENV
# fi
# echo WIOTP_INSTALL_REGION=$WIOTP_INSTALL_REGION
# echo WIOTP_INSTALL_DOMAIN=$WIOTP_INSTALL_DOMAIN
# echo WIOTP_INSTALL_EC_DISABLE_CERT_CHECK=$WIOTP_INSTALL_EC_DISABLE_CERT_CHECK
# echo WIOTP_INSTALL_EDGE_CN=$WIOTP_INSTALL_EDGE_CN

function checkrc {
	if [[ $1 -ne 0 ]]; then
		echo "Last command exited with rc $1, exiting."
		exit $1
	fi
}

fancyLog "WIoTP Horizon agent setup"

VAR_DIR="/var"
ETC_DIR="/etc"

if [ -z $WIOTP_INSTALL_TEST_ENV ]; then
  httpDomainPrefix=$WIOTP_INSTALL_ORGID
  httpDomain=$WIOTP_INSTALL_DOMAIN
  mqttDomainPrefix=$WIOTP_INSTALL_ORGID.messaging
  regionPrefix=$WIOTP_INSTALL_REGION
else
  httpDomainPrefix=$WIOTP_INSTALL_ORGID.$WIOTP_INSTALL_TEST_ENV
  httpDomain=$WIOTP_INSTALL_TEST_ENV.$WIOTP_INSTALL_DOMAIN
  mqttDomainPrefix=$WIOTP_INSTALL_ORGID.messaging.$WIOTP_INSTALL_TEST_ENV
  regionPrefix=$WIOTP_INSTALL_REGION.$WIOTP_INSTALL_TEST_ENV
fi

# Check if domain exists
log "Checking domain..."
output=$(curl -Is -o /dev/null -w "%{http_code}" https://$httpDomain)
if [[ $output -ne 200 ]]; then
  fatal "Invalid domain $httpDomain. Could not reach https://$httpDomain"
fi

log "Domain is valid."

# Check if org exists
log "Checking org..."
output=$(curl -Is -o /dev/null -w "%{http_code}" https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN)
if [[ $output -ne 200 ]]; then
  fatal "Invalid org $WIOTP_INSTALL_ORGID. Could not reach https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN. Check the value passed to --org"
fi

log "Org is valid."

log "Checking device id and device type..."
output=$(curl -s -o /dev/null -w "%{http_code}" -u "$WIOTP_INSTALL_ORGID/g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID:$WIOTP_INSTALL_DEVICE_TOKEN" https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN/api/v0002/edgenode/orgs/$WIOTP_INSTALL_ORGID/nodes/g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID)
if [[ $output -ne 200 ]]; then
  log "ERROR: Could not access device $WIOTP_INSTALL_DEVICE_ID of type $WIOTP_INSTALL_DEVICE_TYPE."
  log "  Troubleshooting:"
  log "    1. Check if the device type was created in Watson IoT Platform."
  log "    2. Make sure that when device type was created, 'Gateway' type was selected and 'Edge Cababilities' toggle was enabled."
  log "    3. Check if a device was created under that device type."
  log "    4. Make sure the device credentials are correct."
  exit 1
fi

log "Device id, device type and device authentication token are valid."

# Read the json object in /etc/horizon/anax.json
anaxJson=$(jq '.' $ETC_DIR/horizon/anax.json)
checkrc $?

# Change the value of ExchangeURL in /etc/horizon/anax.json
anaxJson=$(jq ".Edge.ExchangeURL = \"https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN/api/v0002/edgenode/\" " <<< $anaxJson)
checkrc $?

# Write the new json back to /etc/horizon/anax.json
echo "$anaxJson" > $ETC_DIR/horizon/anax.json

# Restart the horizon service so that the new exchange URL can take effect
log "Restarting Horizon service ..."
systemctl restart horizon.service

# Adjusting edge.conf for enabling/disabling cloud server certificate checks
etc_default_edge_conf_path="${ETC_DIR}/wiotp-edge/edge.conf"
log "Setting $etc_default_edge_conf_path[EC.CloudDisableCertCheck=$WIOTP_INSTALL_EC_DISABLE_CERT_CHECK]"
sed -i.bak "/EC.CloudDisableCertCheck.*/c\EC.CloudDisableCertCheck $WIOTP_INSTALL_EC_DISABLE_CERT_CHECK" $etc_default_edge_conf_path
rm $etc_default_edge_conf_path.bak

# Create the config.json using the emptyConfig.json template and user inputs
log "Creating hzn config input file ..."
emptyConfigJson=$(jq '.' $ETC_DIR/wiotp-edge/hznEdgeCoreIoTInput.json.template)
checkrc $?

configJson=$(jq ".global[0].sensor_urls[0] = \"https://$regionPrefix.$WIOTP_INSTALL_DOMAIN/api/v0002/horizon-image/common\" " <<< $emptyConfigJson)
checkrc $?

configJson=$(jq ".global[0].variables.username = \"$WIOTP_INSTALL_ORGID/g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID\" " <<< $configJson)
checkrc $?

configJson=$(jq ".global[0].variables.password = \"$WIOTP_INSTALL_DEVICE_TOKEN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_CERTS_PASSWORD = \"$WIOTP_INSTALL_DEVICE_TOKEN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_CLIENT_ID = \"g:$WIOTP_INSTALL_ORGID:$WIOTP_INSTALL_DEVICE_TYPE:$WIOTP_INSTALL_DEVICE_ID\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_DEVICE_AUTH_TOKEN = \"$WIOTP_INSTALL_DEVICE_TOKEN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_DOMAIN = \"$mqttDomainPrefix.$WIOTP_INSTALL_DOMAIN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_LOCAL_BROKER_PORT = \"2883\" " <<< $configJson)
checkrc $?
              
# Write the workload json definition file
echo "$configJson" > $ETC_DIR/wiotp-edge/hznEdgeCoreIoTInput.json

# Generate edge-mqttbroker certificates
mkdir -p ${VAR_DIR}/wiotp-edge/persist/
fancyLog "Generating Edge internal certificates" 
if [[ -z $WIOTP_INSTALL_EDGE_CN ]]; then
  wiotp_create_certificate -p $WIOTP_INSTALL_DEVICE_TOKEN
else  
  wiotp_create_certificate -p $WIOTP_INSTALL_DEVICE_TOKEN -cn $WIOTP_INSTALL_EDGE_CN
fi

fancyLog "Waiting for Horizon service to restart ..."
sleep 1

fancyLog "Registering Edge node ..."
cmd="hzn register -n g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID:$WIOTP_INSTALL_DEVICE_TOKEN -f ${ETC_DIR}/wiotp-edge/hznEdgeCoreIoTInput.json $WIOTP_INSTALL_ORGID $WIOTP_INSTALL_DEVICE_TYPE"
echo $cmd
eval $cmd
checkrc $?

fancyLog "Agent setup complete."
