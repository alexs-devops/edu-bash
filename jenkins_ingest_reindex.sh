#!/bin/bash
#set -x
##########################################################################################
###
### Script re-build ingest-app index. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Environment type (auth|live)
###  $3 -> Store ID (10151|12751)
###  $4 -> Restart (YES|NO -- whether to execute `kubectl rollout restart deployment`)
###
##########################################################################################

### Define variables
ENV_TYPE=$2
STORE_ID=$3
RESTART=$4
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9/source/ingestapp"
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

   #####################################################################
   # GENERAL SECTION: ALL environments should be added here
   #####################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
      env_purp="auth"
      env_def="${ENV,,}"
      GC_PREFIX="ecomenv"
   ;;&

   #####################################################################
   # INGEST URL SECTION: Credentials, App pod name
   #####################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      INGEST_URL="${ENV,,}-ingest.clothing.ca"
   ;;&

   DEV1)
      INGEST_URL="${env_sym}-ingest.clothing.ca"
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   DEV1|DEV2|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/search-ingest-app"
      GC_WRKLOAD="${GC_PREFIX}${env_num}ingest-app"
      GC_NAMESPC="${env_def}"
   ;;

   DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/search-ingest-app"
      GC_WRKLOAD="${GC_PREFIX}${env_num}ingest-app"
      GC_NAMESPC="${env_def}"
   ;;

   STG)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/search-ingest-app"
      GC_WRKLOAD="ecomprodingest-app"
      GC_NAMESPC="${env_sym}"
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

#############################################################
### Overload creadentials for envs which located @ np-ecom-1
### project, but image ingest located @ np-ecom-2
#############################################################
gc_overload_cred () {

   ## NOTE: Such envs should be added here 
   if [[ "${ENV}" =~ ^(TST9|DEV9)$ ]];
   then
      # save current workload name
      gc_wrkload_current="${GC_WRKLOAD}"
      gc_namespc_current="${GC_NAMESPC}"

      # reload credentials for restart deployment ${GC_WRKLOAD} @ tstn/devn
      # we can use any namespace in same cluster where current workload located
      gc_env DEV2
      gc_auth

      # roll back current workload name
      GC_WRKLOAD="${gc_wrkload_current}"
      GC_NAMESPC="${gc_namespc_current}"
   fi
}

#########################################################
### Restart through 'kubectl rollout restart deployment'
### $1 -> sleep time between restarts
#########################################################
gc_restart (){

   ${GC_SDK_DIR}/bin/kubectl rollout restart deployment ${GC_WRKLOAD} -n ${GC_NAMESPC}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "WARN" "gc_restart: Command 'kubectl rollout restart deployment ${GC_WRKLOAD} -n ${GC_NAMESPC}' failed!" "${rc}"
   else

      step_max=4
      step_ini=0
      time_sleep="$1"

      # Get new replica set
      rs="$(${GC_SDK_DIR}/bin/kubectl describe deploy ${GC_WRKLOAD} -n ${GC_NAMESPC} | grep "NewReplicaSet:" | awk '{print $2}')"

      while [ ${step_ini} -lt ${step_max} ]; do
         step_ini=$((step_ini+1))

         # Get replica set status
         rs_stat=$(${GC_SDK_DIR}/bin/kubectl get rs -n ${GC_NAMESPC} | grep ${rs})
         print_message "INFO" "gc_restart: Replica set status: ${rs_stat}" "" "no"

         desired="$(echo ${rs_stat} | awk '{ print $2 }')"
         current="$(echo ${rs_stat} | awk '{ print $3 }')"
         ready="$(echo ${rs_stat} | awk '{ print $4 }')"

         if [[ "${desired}" != "0" && "${current}" != "0" && "${ready}" != "0" ]];
         then
            step_ini=${step_max};
            print_message "SUCCESS" "gc_restart: Pod restart ${GC_WRKLOAD} @ ${GC_NAMESPC} completed."
         elif [ "${step_ini}" == "${step_max}" ];
         then
            print_message "WARN" "gc_restart: Pod restart ${GC_WRKLOAD} @ ${GC_NAMESPC} NOT completed. Please check logs."
            ${GC_SDK_DIR}/bin/kubectl get pods -n ${GC_NAMESPC} | grep ${GC_WRKLOAD}
            echo "Replica set status: ${rs_stat} "
         else
            print_message "INFO" "gc_restart: Waiting ${time_sleep}..." "" "no"
            sleep ${time_sleep}
         fi

      done
   fi

}


#########################################################
### Sent alert mail
#########################################################
mail_send (){
   mail_to="-WebAdmins@.com"
   mail_subj="[WARN]: ${GC_NAMESPC}/${GC_WRKLOAD} about to be restarted"
   mail_body="[${Datetime}]: ${GC_NAMESPC}/${GC_WRKLOAD} about to be restarted from Jenkins. No actions required."

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
gc_auth

# Correct $PATH
if ! echo $PATH | grep ${GC_SDK_DIR};
then
   export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
fi


print_message "INFO" "Image re-index about to begin:"
INGEST_POD=`kubectl get pods -n ${GC_NAMESPC} | grep ingest-app| grep Running | tail -n +1 | awk '{print $1}'`
rc="$?";
if [ "${rc}" != "0" ]; then
print_message "ERROR" "'kubectl get pods' failed!" "${rc}"
exit ${rc};
fi

## Prepare log
LOG="/tmp/es_${ENV}.log"
if [ -f  ${LOG} ]; then rm -f ${LOG}; fi

## Building Index
kubectl exec ${INGEST_POD} -n ${GC_NAMESPC} -- bash -c "curl -k -X post  https://${INGEST_URL}/connectors/${ENV_TYPE}.reindex/run?storeId=${STORE_ID}&envType=${ENV_TYPE}" > ${LOG}

RUN_ID=`cat ${LOG} | awk -F '"' '{print $4}'`

# Clean up
if [ -f  ${LOG} ]; then rm -f ${LOG}; fi

print_message "INFO" "Re-index status: https://${INGEST_URL}/connectors/${ENV_TYPE}.reindex/runs/${RUN_ID}/status"

counter=0; totalTime=0
timeOut=6; indexTime=$((timeOut*5))
while [ ${counter} -lt 1 ]; do
   print_message "INFO" "Current re-index status:"
   fullStatus=`curl -k -s https://${INGEST_URL}/connectors/${ENV_TYPE}.reindex/runs/${RUN_ID}/status`
   echo "${fullStatus}"

   status=`echo ${fullStatus} | awk -F '"' '{print $16}' | awk -F '.' '{print $1}'`
   if [ "${status}" = "Indexing Job is Completed" ];
   then
     counter=1
     print_message "INFO" "Completion re-index status: ${status}"
     break;
   fi

   ## If re-index not moving under 0%
   status_percent=`echo ${fullStatus} | awk -F '"' '{print $22}' | awk '{print $1}'`
   if [[ "${totalTime}" = "${timeOut}" && "${status_percent}" = "0%" ]];
   then
      print_message "ERROR" "Re-index status are not changed from ${status_percent} for ${timeOut} minutes."
      exit 1
   fi

   ## If index is running for ${indexTime} minutes
   if [ "${totalTime}" = "${indexTime}" ]
   then
      print_message "WARN" "Re-index status are not changed for ${indexTime} minutes. If timeout too short, please send message to as511@.com."
      print_message "INFO" "Check status manually: https://${INGEST_URL}/connectors/${ENV_TYPE}.reindex/runs/${RUN_ID}/status"
      exit 1
   fi

   sleep 120
   totalTime=$((totalTime+2))
   print_message "INFO" "Total execution time: ${totalTime} mins."
done

### Restart
if [[ "${RESTART}" = "YES" ]];
then

   ## Correct $PATH in cases when sript used only for restart
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
     export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
   fi


   ## Overload creadentials for envs which located @ np-ecom-1
   ## project, but image ingest located @ np-ecom-2
   #gc_overload_cred

   gc_auth
   gc_restart "3m"

   ## Sent email notification   
   if [[ "${ENV}" =~ ^(STG|PRD)$ ]];
   then
      mail_send
   fi

else
   print_message "INFO" "Command 'kubectl rollout restart deployment ${GC_WRKLOAD}' WILL NOT be executed ."
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."

