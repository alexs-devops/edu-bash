#!/bin/bash
#set -x
##########################################################################################
###
### Script to :
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Restart (YES|NO -- whether to execute `kubectl rollout restart deployment`)
###  $3 -> Execute ALL files from ${JSON_FILES_LIST[@]} or separately
### Jira ticket: https://jira.tailoredbrands.com/browse/R-4184
###
##########################################################################################

### Define variables
RESTART=$2
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9/source/ecom-nifi-ingest-add-cust-proc/AUTO_PATCH"
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
CICD_DIR="/opt/cicd"

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###  $2 -> Execute ALL files from ${JSON_FILES_LIST[@]} or separately
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
   # NIFI URL SECTION: Specify nifi App URL
   #####################################################################
   DEV4)
      NIFI_HOSTNAME="${env_def}-nifi.gcp.wearhouse.com"
   ;;&

   DEV1)
      NIFI_HOSTNAME="${env_sym}-nifi.clothing.ca"
   ;;&

   DEV2|DEV3|DEV9|DEV10|STG)
      NIFI_HOSTNAME="${env_def}-nifi.clothing.ca"
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   DEV1|DEV2|DEV3|DEV9)
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

JSON_NAME="$2"
echo "[INFO]: _$2_ selected."

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
### Check PATH environment variable
###################################################
chk_env_path (){
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
      export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
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
    fi

    ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
}

###################################################
### Prapare, exec command on pod; check logs
###################################################
exec_curl_cmd () {

   dos2unix ${JSON_NAME}
   if [[ ${JSON_NAME} == auth* ]];
   then
      env_type="auth"
   elif [[ ${JSON_NAME} == live* ]];
   then
      env_type="live"
   else
      print_message "ERROR" "exec_curl_cmd: Env file incorrect! Should starts from auth|live"
   fi

   gc_auth

   # Correct $PATH
   chk_env_path

   # Get ${ingest_pod} pod
   ingest_pod=`${GC_SDK_DIR}/bin/kubectl get pods -n ${GC_NAMESPC} | grep Running | grep ${GC_WRKLOAD} | awk '{print $1}'`
   print_message "INFO" "exec_curl_cmd: Ingest pod: ${ingest_pod}"
   #${GC_SDK_DIR}/bin/kubectl get pods -n ${GC_NAMESPC} | grep ${GC_WRKLOAD}

   # Copy curl commands to ${ingest_pod}
   ${GC_SDK_DIR}/bin/kubectl cp ${WRK_DIR}/${JSON_NAME} ${GC_NAMESPC}/${ingest_pod}:/${env_type}.json; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "exec_curl_cmd: kubectl cp sh: command failed." $?;
      exit 1
   fi

   # Execute curl commands on ${ingest_pod}
   ${GC_SDK_DIR}/bin/kubectl exec -it --namespace=${GC_NAMESPC} ${ingest_pod} -- bash -c "curl --location --request POST http://localhost:30800/connectors/${env_type}.reindex/upgrade --header 'Content-Type: application/json' -d @${env_type}.json -v > /curl_cmd_list.log 2>&1"; rc_exec="$?";

   # Copy curl output
   ${GC_SDK_DIR}/bin/kubectl cp ${GC_NAMESPC}/${ingest_pod}:/curl_cmd_list.log ${WRK_DIR}/curl_cmd_list.log; rc="$?";
   if [ "${rc}" != "0" ]; then 
      print_message "ERROR" "exec_curl_cmd: kubectl cp log: command failed." $?;
      exit 1
   fi

   # Check 'kubectl exec' exit status
   if [ "${rc_exec}" != "0" ]; then
      print_message "ERROR" "exec_curl_cmd: kubectl exec: command failed. curl_cmd_list.log:" $?;
      cat ${WRK_DIR}/curl_cmd_list.log
      exit 1
   fi

   # Check curl output log
   if grep -q "curl: (" ${WRK_DIR}/curl_cmd_list.log ;
   then
      print_message "ERROR" "exec_curl_cmd: curl_cmd_list.log: Errors found in log:"
      cat ${WRK_DIR}/curl_cmd_list.log
      exit 1
   else
      print_message "INFO" "exec_curl_cmd: curl_cmd_list.log: No errors found:"
      cat ${WRK_DIR}/curl_cmd_list.log
   fi

}

###################################################
### Check re-index status
### $1 -> sleep time between checks
###################################################
chk_index_status () {

   index_stat="index_status.json"
   nifi_stat_url="https://${NIFI_HOSTNAME}/nifi-api/flow/status/"

   step_max=5
   step_ini=0
   time_sleep="$1"
   while [ ${step_ini} -lt ${step_max} ]; do
      step_ini=$((step_ini+1))

      # Get content of ${nifi_stat_url}
      wget --no-check-certificate -q -O ${index_stat} ${nifi_stat_url}
      rc="$?"
      if [ "${rc}" != "0" ]; then
         print_message "ERROR" "chk_index_status: wget --no-check-certificate -q -O ${index_stat} ${nifi_url} command failed." $?;
         exit 1
      else
         print_message "INFO" "chk_index_status: wget --no-check-certificate -q -O ${index_stat} ${nifi_url}:";
         cat index_status.json
      fi

      # Get runningCount/stoppedCount/invalidCount
      runn_count=$(yq .controllerStatus.runningCount ${index_stat})
      stop_count=$(yq .controllerStatus.stoppedCount ${index_stat})
      invl_count=$(yq .controllerStatus.invalidCount ${index_stat})

      if [[ "${runn_count}" -ge "14000" && "${stop_count}" = "0" && "${invl_count}" = "0" ]];
      then
         step_ini=${step_max};
         print_message "SUCCESS" "chk_index_status: Re-index completed."
      elif [ "${step_ini}" == "${step_max}" ];
      then
         print_message "WARN" "chk_index_status: Retry limit reached. Exiting..."
         exit 1
      else
         print_message "INFO" "chk_index_status: Waiting ${time_sleep}..." "" "no"
         sleep ${time_sleep}
      fi


   done
}

###################################################
### Restart deploymentl; check pod status:
### $1 -> sleep time between restarts
### $2 -> ${GC_WRKLOAD} name
###################################################
gc_restart_deploy (){
   GC_WRKLOAD=$2

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

##############################
### MAIN
##############################

print_message "INFO" "Date: ${Datetime}."

gc_env $1 $3

### Execute 'curl' commands
cd ${WRK_DIR}


if [[ "${JSON_NAME}" = "ALL_reindex-IngestPatch" ]];
then
   JSON_INGEST_FILES_LIST=("auth.reindex-IngestPatch.CURL.json" "live.reindex-IngestPatch.CURL.json");

   for file in ${JSON_INGEST_FILES_LIST[@]};
   do
     JSON_FILES_LIST=("${file}");
     exec_curl_cmd
     chk_index_status 3m
   done
else
   exec_curl_cmd
   nifi_stat_url="https://${NIFI_HOSTNAME}/nifi-api/flow/status/"
   print_message "INFO" "Please monitor: ${nifi_stat_url}"
   chk_index_status 3m
fi

### Clean up
if [ -d ${WRK_DIR} ];
then 
   cd ${WRK_DIR}; rm -rf *;
fi
echo ""

### Restart
if [[ "${RESTART}" = "YES" ]];
then
   gc_auth
   gc_restart_deploy "3m" ${GC_WRKLOAD}
else
   print_message "INFO" "Command 'kubectl rollout restart deployment ${GC_WRKLOAD}' WILL NOT be executed ."
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."

