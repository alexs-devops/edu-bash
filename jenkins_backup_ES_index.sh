#!/bin/bash
#set -x
##########################################################################################
###
### Script backup/restore ES index. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Environment type (auth|live)
###  $3 -> Store ID (10151|12751)
###
##########################################################################################

### Define variables
ENV_TYPE=$2
STORE_ID=$3

Datetime=`date '+%Y%m%d_%H%M%S'`
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
   # GENERAL SECTION: ALL environments should be added here
   #####################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
      env_purp="auth"
      env_def="${ENV,,}"
   ;;&

   #####################################################################
   # ES POD SECTION: App pod name
   #####################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      GC_WRKLOAD="hcl-commerce-elasticsearch"
      ES_POD="hcl-commerce-elasticsearch-0"
      GC_BUCKET=""
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   DEV1|DEV2|DEV3|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_NAMESPC="${env_def}"
   ;;

   DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_NAMESPC="${env_def}"
      GC_BUCKET=""
   ;;

   STG)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_NAMESPC="${env_sym}"
      GC_BUCKET=""
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
### $1 -> ES backup index/ ES restore index/
#########################################################
mail_send (){
   mail_to="-WebAdmins@.com"
   mail_subj="[WARN]: ${GC_NAMESPC}/${GC_WRKLOAD} $1 about to be re-started"
   mail_body="[${Datetime}]:  No actions required."

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

LOG_OUT=/tmp/es_backup.log

## Step 1: Remove old backups
max_snapshot_count=10
snapshot_count=`kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X GET 'http://localhost:9200/_snapshot/backup/*' | jq -r ".snapshots[].snapshot" | wc -l`
if [ ${snapshot_count} -gt ${max_snapshot_count} ];
then
   diff_count=$((snapshot_count-max_snapshot_count))
   for (( i=1; i<=${diff_count}; i++ ))
   do
      snapshot_name=`kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X GET 'http://localhost:9200/_snapshot/backup/*' | jq -r ".snapshots[].snapshot" | head -1`
      print_message "INFO" "Deleting ${snapshot_name} ..."
      kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X DELETE "localhost:9200/_snapshot/backup/${snapshot_name}?pretty" > ${LOG_OUT} 2>&1
      rc="$?"; cat ${LOG_OUT};
      if [ "${rc}" != "0" ] || ! grep -q '"acknowledged" : true' ${LOG_OUT};
      then
         print_message "ERROR" "kubectl: delete snapshot failed!" "${rc}";
         exit 1;
      fi
   done
fi

## Step 2: Create backup
print_message "INFO" "Create backup dir:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X PUT "localhost:9200/_snapshot/backup" -H "Content-Type: application/json" -d "{ \"type\": \"gcs\", \"settings\": { \"bucket\": \"${GC_BUCKET}\", \"base_path\": \"es_backup\" } }" > ${LOG_OUT} 2>&1;
rc="$?";
cat ${LOG_OUT}; echo " ";
if [ "${rc}" != "0" ] || ! grep -q '"acknowledged":true' ${LOG_OUT};
then
   print_message "ERROR" "kubectl: create backup dir failed!" "${rc}";
   exit 1;
fi

## Step 3: Manually create a snapshot based on store_id and environment
BACKUP_PREFIX="backup_`date +'%Y_%m_%d_%T'`"
print_message "INFO" "Manually create a ${ENV_TYPE}_${STORE_ID}_${BACKUP_PREFIX} snapshot based on store_id and environment"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X PUT "localhost:9200/_snapshot/backup/${ENV_TYPE}_${STORE_ID}_${BACKUP_PREFIX}?pretty&wait_for_completion=true" --header 'Content-Type: application/json' --data "{ \"indices\": \"*${ENV_TYPE}.${STORE_ID}*,${ENV_TYPE}.store,${ENV_TYPE}.inventory,${ENV_TYPE}.price,${ENV_TYPE}.workspace\", \"ignore_unavailable\": true, \"include_global_state\": false, \"retention\": { \"expire_after\": \"1d\", \"max_count\": 10  }}" > ${LOG_OUT} 2>&1
rc="$?"; cat ${LOG_OUT};
if [ "${rc}" != "0" ] || ! grep -q '"state" : "SUCCESS"' ${LOG_OUT};
then
   print_message "ERROR" "kubectl: create snapshot failed!" "${rc}";
   exit 1;
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."