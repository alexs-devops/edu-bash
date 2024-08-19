#!/bin/bash
#set -x
##########################################################################################
###
### Script to deploy ts-app. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Restart (YES|NO -- whether to execute `kubectl rollout restart deployment`)
###  $3 -> Tag (Docker image tag; the same as branch name) 
###  $4 -> Base image (if 'default', then will be used base image from Dockerfile)
###
##########################################################################################

### Define variables
TAG=$3
TYPE="ts"
RESTART=$2
BASEIMAGE="$4"
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9"
DOCKERFILE_DIR="${WRK_DIR}/scripts/docker_file/ts"
XML_DIR="${WRK_DIR}/source/hclcommerce/WC/xml/config"
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
   DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9|DEV10|TST10|STG|PRD)
      env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      GC_PREFIX="ecomenv"
   ;;&

   #####################################################################################
   # PURPOSE SECTION: Evironment auth or live
   #####################################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
     env_purp="auth"
   ;;&

   TST1|TST2|TST3|TST9|TST10|PRD)
     env_purp="live"
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   TST1|DEV1|TST2|DEV2|DEV3|TST3|DEV9|TST9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_GA4_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-app"
      GC_WRKLOAD="${GC_PREFIX}${env_num}${env_purp}ts-app"
      GC_NAMESPC="${ENV,,}"
   ;;

   TST10|DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_GA4_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-app"
      GC_WRKLOAD="${GC_PREFIX}${env_num}${env_purp}ts-app"
      GC_NAMESPC="${ENV,,}"
   ;;

   STG|PRD)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_GA4_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-app"
      GC_WRKLOAD="ecomprod${env_purp}ts-app"
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

###################################################
### Copy Dockerfile
### $1 -> Dockerfile name
###################################################
dockerfile_deploy (){

   dockerfile="$1"
   cp -a ${dockerfile} ${dockerfile}.bk

   if [[ "${BASEIMAGE}" != "default" ]];
   then
      sed -i "/FROM.*ts-app:/ s/:.*/:${BASEIMAGE}/g" ${dockerfile}
   fi

   print_message "INFO" "dockerfile_deploy: Dockerfile and base image:" "" "no_frame"
   ls -lhtr ${dockerfile}; head -1 ${dockerfile}
   docker cp ${dockerfile} ts-util-build-temp:${CICD_DIR}/${ts_dir}/Dockerfile
   cp ${dockerfile} ${DOCKERFILE_DIR}

   mv ${dockerfile}.bk ${dockerfile}
}

#############################################################
### Overload creadentials for envs which located @ np-ecom-1
### project, but image registry located @ np-ecom-2
#############################################################
gc_overload_cred () {

   ## NOTE: Such envs should be added here 
   if [[ "${ENV}" =~ ^(TST9|DEV9)$ ]];
   then
      # save current workload name
      gc_wrkload_current="${GC_WRKLOAD}"
      gc_namespc_current="${GC_NAMESPC}"

      # reload credentials for restart deployment ${GC_WRKLOAD} @ tstn/devn
      # we can use any namespace in same cluster where tstn/devn workload located
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
. /usr/opt/app/Ecom_V9/scripts/jenkins_deployment_count.sh $1 tsApp build

gc_env $1

if [ ! -z "${TAG}" ]; then
   ### Prepare ${WRK_DIR}
   cd ${WRK_DIR}/source/hclcommerce
   rm -rf WC LOBTools
   mv WC_Custom WC
   mv WC_LOBTools LOBTools
   cp -f ${XML_DIR}/wc-server-runtime.xml ${XML_DIR}/wc-server.xml

   ### Prepare ts-util-build-temp using us.gcr.io//commerce/ts-utils as base
   docker container stop ts-util-build-temp || print_message "INFO" "ts-util-build-temp not running." "" "no"
   docker container rm ts-util-build-temp || print_message "INFO" "ts-util-build-temp doesn't exist."  "" "no"

   ts_dir="scripts/docker_file/ts"
   docker run --env LICENSE=accept -d --name=ts-util-build-temp us.gcr.io//commerce/ts-utils:9.1.11.0
   docker exec  ts-util-build-temp bash -c 'mkdir -p /opt/cicd/scripts; mkdir -p /opt/cicd/source; mkdir -p /opt/cicd/scripts/docker_file/ts; mkdir -p /opt/cicd/properties/'
   docker cp ${WRK_DIR}/source/hclcommerce ts-util-build-temp:${CICD_DIR}/source
   docker cp ${WRK_DIR}/scripts/build-ts.bash ts-util-build-temp:${CICD_DIR}/scripts
   #docker cp ${WRK_DIR}/source/hclcommerce/Dockerfile ts-util-build-temp:${CICD_DIR}/${ts_dir}/Dockerfile
   docker cp ${WRK_DIR}/${ts_dir}/updateExtDataEJB.py ts-util-build-temp:${CICD_DIR}/${ts_dir}/updateExtDataEJB.py
   docker cp ${WRK_DIR}/properties/build--ts.private.properties ts-util-build-temp:${CICD_DIR}/properties/build--ts.private.properties
   docker cp ${WRK_DIR}/properties/wcbd-build-shared-classpath.xml ts-util-build-temp:/opt/WebSphere/CommerceServer90/wcbd/wcbd-build-shared-classpath.xml

   ##DEVOPS-2242
   #docker cp ${WRK_DIR}/${ts_dir}/googleAnalyticsServiceAccount.json ts-util-build-temp:${CICD_DIR}/${ts_dir}/googleAnalyticsServiceAccount.json
   #will not work for env9
   cp ${GC_GA4_KEY} /${WRK_DIR}/${ts_dir}/googleAnalyticsServiceAccount.json;
   docker cp ${WRK_DIR}/${ts_dir}/googleAnalyticsServiceAccount.json ts-util-build-temp:${CICD_DIR}/${ts_dir}

   ##DEVOPS-1897
   docker cp ${WRK_DIR}/${ts_dir}/trusted_certs ts-util-build-temp:${CICD_DIR}/${ts_dir}

   ## DEVOPS-1504
   # if [[ "${store_name}" == "" ]];
   # then
      # docker cp ${WRK_DIR}/properties/build--ts.properties ts-util-build-temp:${CICD_DIR}/properties/build--ts.properties
   # elif [[ "${store_name}" == "" ]];
   # then
      docker cp ${WRK_DIR}/properties/build--ts.properties ts-util-build-temp:${CICD_DIR}/properties/build--ts.properties
   # else
      # print_message "ERROR" "store_name was not defined for current environment !" "1"
   # fi

   ## Dockerfile copy
   dockerfile="${WRK_DIR}/source/hclcommerce/Dockerfile"
   dockerfile_deploy ${dockerfile}

   ### Building code
   ts_zip="dir/server/wcbd-deploy-server--ts-${TAG}.zip"
   print_message "INFO" "Building code and preparing ${ts_zip}:"
   docker exec ts-util-build-temp ${CICD_DIR}/scripts/build-ts.bash $TAG;
   docker cp ts-util-build-temp:${CICD_DIR}/${ts_zip} ${WRK_DIR}/${ts_zip}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "Command 'docker cp' failed!" "${rc}"
      exit ${rc};
   fi
   
   ### Building image
   print_message "INFO" "Image build ts-app-build-lang:${TAG} about to begin:"
   sh  ${WRK_DIR}/scripts/build_docker_ts.bash ${TAG} ${ENV}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "${WRK_DIR}/scripts/build_docker_ts.bash failed!" "${rc}"
      exit ${rc};
   fi

   if docker images ts-app-build-lang:${TAG}
   then
      print_message "INFO" "Docker image build ts-app-build-lang:${TAG} completed." "" "no_frame"
   else
      print_message "ERROR" "Docker image build ts-app-build-lang:${TAG} NOT found."; exit 1;
   fi

   ### Tag & Push
   print_message "INFO" "Docker image tag and push"
   print_message "INFO" "ts-app-build-lang:$TAG -> ${GC_IMAGE}:$TAG" "" "no_frame"
   docker tag ts-app-build-lang:${TAG} ${GC_IMAGE}:${TAG}

   gc_auth
   cat ${GC_SA_KEY} | docker login -u _json_key --password-stdin https://us.gcr.io
   docker push ${GC_IMAGE}:${TAG}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "docker push failed!" "${rc}"
      exit ${rc};
   fi

   ### Clean up
   print_message "INFO" "Removing old images"
   docker container stop ts-util-build-temp || print_message "WARN" "ts-util-build-temp not running." "" "no"
   docker container rm ts-util-build-temp || print_message "WARN" "ts-util-build-temp doesn't exist." "" "no"
   docker rmi ts-app-build-lang:${TAG}
   docker rmi ${GC_IMAGE}:$TAG

   ### Check image tag
   APP_NAME="ts-app"
   
   ## Overload creadentials for envs which located @ np-ecom-1
   ## project, but image registry located @ np-ecom-2
   #gc_overload_cred

   # Correct $PATH
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
     export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
   fi

   GET_IMAGE=$(${GC_SDK_DIR}/bin/kubectl get deployment -n ${GC_NAMESPC} -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.template.spec.containers[*].image}{"\n"}{end}' | grep ${APP_NAME}); echo ${GET_IMAGE}
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

