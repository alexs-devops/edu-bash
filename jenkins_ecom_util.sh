#!/bin/bash
#set -x
##########################################################################################
###
### Script to deploy reactjs Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Restart (YES|NO -- whether to execute `kubectl rollout restart deployment`)
###  $3 -> Tag (Docker image tag; the same as branch name) 
###
##########################################################################################

### Define variables
TAG=$3
RESTART=$2
Datetime=`date '+%Y%m%d_%H%M%S'`
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
      GC_WRKLOAD="ecomenv${env_num}authts-utils"
      GC_NAMESPC="${ENV,,}"
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

#############################################################
### Overload creadentials for envs which located @ np-ecom-1
### project, but image registry located @ np-ecom-2
#############################################################
gc_overload_cred () {
    
   ## NOTE: Such envs should be added here 
   if [[ "${ENV}" =~ ^(DEV1|DEV7|DEV9)$ ]];
   then
      # save current workload name
      gc_wrkload_current="${GC_WRKLOAD}"
      gc_namespc_current="${GC_NAMESPC}"

      # reload credentials for restart deployment ${GC_WRKLOAD} @ current
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

### DEVOPS-1214: Build/Deployment count
. /usr/opt/app/Ecom_V9/scripts/jenkins_deployment_count.sh $1 tsUtils build

gc_env $1

### reactjs build and push
if [ ! -z "${TAG}" ]; then
   ### Prepare ${WRK_DIR}
   cd ${WRK_DIR}

   ### Pre-build
   print_message "INFO" "Pre-build steps:"

   # DEVOPS-1523
   cp -av ${GC_SDK_DIR}/ecom-ga-reporting.json ${WRK_DIR}/PageViewCounter/src/main/resources/keyfile.json

   # DEVOPS-519
   if [[ "${ENV}" =~ ^(STG|PRD)$ ]];
   then
      cp -av ${WRK_DIR}/../../properties/wc-dataload-env.xml.stg ${WRK_DIR}/DeploymentAssets/dataload/acp/acp-dataload-env
      cp -av ${WRK_DIR}/../../properties/wc-dataload-env.xml.prd ${WRK_DIR}/DeploymentAssets/dataload/acp/acp-dataload-env
   fi

   # DEVOPS-2095
   # IBM Data Server Runtime Client https://www.ibm.com/support/pages/node/6525008
   cp -av ${WRK_DIR}/../../properties/v11.5.7_linuxx64_rtcl.tar.gz ${WRK_DIR}/

   ### Building image
   print_message "INFO" "Image build ${GC_IMAGE}:${TAG} about to begin:"
   docker build -t ${GC_IMAGE}:${TAG} .
   rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "'docker build -t ${GC_IMAGE}:${TAG}' failed!" "${rc}"
      exit ${rc};
   fi

   if docker images ${GC_IMAGE}:${TAG}
   then
      print_message "INFO" "Docker image build completed." "" "no_frame"
   else
      print_message "ERROR" "Docker image ${GC_IMAGE}:${TAG} NOT found."; exit 1;
   fi

   ### Push
   print_message "INFO" "Docker image push"
   gc_auth
   cat ${GC_SA_KEY} | docker login -u _json_key --password-stdin https://us.gcr.io
   docker push ${GC_IMAGE}:${TAG}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "docker push failed!" "${rc}"
      exit ${rc};
   fi

   ### Clean up
   print_message "INFO" "Removing old images"
   docker rmi ${GC_IMAGE}:${TAG}

   if [ -d ${WRK_DIR} ];
   then 
      cd ${WRK_DIR}; rm -rf *;
   fi

   ### Check image tag
   APP_NAME="util"

   ## Overload creadentials for envs which located @ np-ecom-1
   ## project, but image registry located @ np-ecom-2
   #gc_overload_cred

   # Correct $PATH
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
     export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
   fi

   GET_IMAGE=$(${GC_SDK_DIR}/bin/kubectl get deployment -n ${GC_NAMESPC} -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.template.spec.containers[*].image}{"\n"}{end}' | grep ${APP_NAME}); echo "${GET_IMAGE}"
   GET_IMAGE_TAG="${GET_IMAGE#*:}"

   if [[ "${GET_IMAGE_TAG}" = "${TAG}" ]];
   then
      print_message "INFO" "Image tag:'${TAG}' the same as already deployed:'${GET_IMAGE_TAG}'. To apply changes pod will be restated."
      RESTART="YES"
   else
      print_message "INFO" "Image tag:'${TAG}' differs from already deployed:'${GET_IMAGE_TAG}'. To apply changes use deployment job."
      RESTART="NO"
   fi

fi

### Restart
if [[ "${RESTART}" = "YES" ]];
then

   ## Correct $PATH in cases when sript used only for restart
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
     export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
   fi

   ## Overload creadentials for envs which located @ np-ecom-1
   ## project, but image registry located @ np-ecom-2
   #gc_overload_cred

   gc_auth
   gc_restart "5m"

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

