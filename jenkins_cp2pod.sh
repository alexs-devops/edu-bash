#!/bin/bash
#set -x
##########################################################################################
###
### Script to copy files to ts-util pod. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Absolute file path location
###  $3 -> Upload from local (Optional; if provided WRK_DIR will be changed)
###
##########################################################################################

### Define variables
ABS_PATH=$2
OPT=$3
Datetime=`date '+%Y%m%d_%H%M%S'`
FILE_NAME=`basename ${ABS_PATH}`
UPLOAD_DIR="/usr/opt/app/feed2util"
WRK_DIR="/usr/opt/app/Ecom_V9/source/ecomutil"
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
CICD_DIR="/opt/cicd"

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###################################################
gc_env (){
ENV=$1

case ${ENV} in

   DEV1|DEV2|DEV3|DEV9|DEV10)
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      GC_NAMESPC="${ENV,,}"
      GC_WRKLOAD="ecomenv${env_num}authts-utils"
   ;;&

   DEV1|DEV2|DEV3|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
   ;;

   DEV10)
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
### Check exit status
### $1 -> exit status
#########################################################
exit_stat (){
   rc="$1"
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "exit_stat: kubectl exec failed!" "${rc}"
      exit ${rc};
   fi
}

#########################################################
### Sent alert mail
### $1 -> location
#########################################################
mail_send (){
   loc=$1
   mail_to="-WebAdmins@.com"
   mail_subj="[WARN]: ${GC_NAMESPC}/${GC_WRKLOAD} file copied"
   mail_body="[${Datetime}]: ${ABS_PATH} file copied.(from ${loc}) No actions required."

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
utils_pod=`${GC_SDK_DIR}/bin/kubectl get pods -n ${GC_NAMESPC} | grep ${GC_WRKLOAD} | grep Running | tail -1 | awk '{print $1}'`

## Copy
print_message "INFO" "Copying to ${utils_pod}:${ABS_PATH}:"

if [[ "${OPT}" != "local" ]];
then
   file_dir="${WRK_DIR}${ABS_PATH}";
elif [[ "${OPT}" == "local" ]];
then
   file_dir="${UPLOAD_DIR}/${FILE_NAME}"
else
   print_message "ERROR" "Incorrect OPT value provided!";
   exit 1
fi

kubectl cp ${file_dir} ${utils_pod}:${ABS_PATH} -n ${GC_NAMESPC}; 
rc="$?"; exit_stat ${rc}

# grant execute permissions
${GC_SDK_DIR}/bin/kubectl exec -n ${GC_NAMESPC} -it ${utils_pod} -- /bin/bash -c "chmod 755 ${ABS_PATH}";
rc="$?";  exit_stat ${rc}

## Sent email notification   
if [[ "${ENV}" =~ ^(STG)$ ]];
then
   if [[ "${OPT}" == "local" ]];
   then
      mail_send "local"
   else
      mail_send "repo"
   fi
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."
