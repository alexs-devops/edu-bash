#!/bin/bash
#set -x
##########################################################################################
###
### Script to execute acpload. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> acp file name
###
##########################################################################################

### Define variables
RESTART=$2
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9/source/ecomutil"
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###################################################
gc_env (){

   ENV=$1
   case ${ENV} in

   #####################################################################
   # GCP SECTION1: Environment pod and namespace
   #####################################################################
   DEV1|DEV2|DEV3|DEV4|DEV6|DEV7|DEV8|DEV9|DEV10)
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      GC_WRKLOAD="ecomenv${env_num}authts-utils"
      GC_NAMESPC="${ENV,,}"
   ;;&

   #####################################################################
   # GCP SECTION2: Credentials, App pod name
   #####################################################################
   DEV1|DEV2|DEV4|DEV6|DEV7|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
   ;;

   DEV3|DEV8|DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
   ;;

   STG)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
      GC_NAMESPC="stg"
      GC_WRKLOAD="ecomprodauthts-utils"
   ;;

   *)
     echo "[ERROR]: Env name incorrect!"; exit 1;
   ;;

   esac
}

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> error severity (e.g Error; Warning; etc)
###  $2 -> message
###  $3 -> exit status (optional)
###  $4 -> if not null, frame will not be printed
###################################################
print_message (){
   if [ ! -z "$3" ]; then exit_stat="(Exit status: $3)"; fi

   message="[$1]: $2 ${exit_stat}"; exit_stat="";

   if [ -z "$4" ]; then
      echo "************************************************************************************"
      echo "${message}";
      echo "************************************************************************************"
   else
      echo "${message}";
   fi
}

###################################################
### Executes gcloud auth and gcloud get-credentials
###################################################
gc_auth (){
    if ${GC_SDK_DIR}/bin/gcloud auth list --filter=status:ACTIVE | grep ${GC_SA} ;
    then
       print_message "INFO" "gc_auth: ${GC_SA} account is active." "" "no_frame"
    else
       ${GC_SDK_DIR}/bin/gcloud auth activate-service-account ${GC_SA} --key-file=${GC_SA_KEY}
       #${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
    fi
    ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
}

#########################################################
### Sent alert mail
#########################################################
mail_send (){
   mail_to="-WebAdmins@.com"
   mail_subj="[WARN]: ${GC_NAMESPC}/${GC_WRKLOAD} ACP Data load triggered"
   mail_body="[${Datetime}]: No actions required."

   echo "${mail_body}" | mutt -s "${mail_subj}" -- ${mail_to}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "WARN" "mail_send: Sent mail failed!" "${rc}"
   fi

}

##############################
### MAIN
##############################

print_message "INFO" "Date: ${Datetime}."

gc_env $1

# Correct $PATH
if ! echo $PATH | grep ${GC_SDK_DIR};
then
   export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
fi

gc_auth

## Get util pod
utils_pod=`kubectl get pods -n ${GC_NAMESPC} | grep ${GC_WRKLOAD} | grep Running | tail -n +1 | awk '{print $1}'`

## Execute StageProp:
if [[ "${ENV}" =~ ^(STG|PRD)$ ]];
then
   mail_send
fi

print_message "INFO" "Executing StageProp on ${ENV}:"

kubectl exec -n ${GC_NAMESPC} -it ${utils_pod} -- /bin/bash -c \
    'host=$(cat /etc/hostname); num=${host%%-*}; num=${num//[^0-9]/}
    dbPasswordS=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/auth/dbPassword" | jq -r .data.value`; \
    dbHostS=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/auth/dbHost" | jq -r .data.value`; \
    dbNameS=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/auth/dbName" | jq -r .data.value`; \
    dbPortS=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/auth/dbPort" | jq -r .data.value`; \
    dbPasswordT=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/live/dbPassword" | jq -r .data.value`; \
    dbHostT=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/live/dbHost" | jq -r .data.value`; \
    dbNameT=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/live/dbName" | jq -r .data.value`; \
    dbPortT=`curl -m 60 -s -X GET -H "X-Vault-Token:$VAULT_TOKEN" "${VAULT_URL}/ecom/env${num}/live/dbPort" | jq -r .data.value`; \
    echo "[INFO]: Executing: stagingprop.sh -scope _all_ -sourcedb ${dbHostS}:${dbPortS}/${dbNameS} -sourcedb_user wcs -sourcedb_passwd --- -destdb ${dbHostT}:${dbPortT}/${dbNameT} -destdb_user wcs -destdb_passwd --- -dbtype db2 -transaction 10000 -batchsize 1000 -destdb_locktimeout 0  -lockStaglog 0 -log /opt/WebSphere/CommerceServer90/logs/stagingprop_dev${num}.log"
    /opt/WebSphere/CommerceServer90/bin/stagingprop.sh -scope _all_ -sourcedb ${dbHostS}:${dbPortS}/${dbNameS} -sourcedb_user wcs -sourcedb_passwd ${dbPasswordS} -destdb ${dbHostT}:${dbPortT}/${dbNameT} -destdb_user wcs -destdb_passwd ${dbPasswordT} -dbtype db2 -transaction 10000 -batchsize 1000 -destdb_locktimeout 0  -lockStaglog 0 -log /opt/WebSphere/CommerceServer90/logs/stagingprop_dev${num}.log'; rc="$?";

kubectl exec -n ${GC_NAMESPC} -it ${utils_pod} -- /bin/bash -c "cat /opt/WebSphere/CommerceServer90/logs/stagingprop_dev${env_num}.log"
if [ "${rc}" != "0" ]; then
   print_message "ERROR" "Execution of 'stagingprop.sh' utility failed!" "${rc}"
   exit ${rc};
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."