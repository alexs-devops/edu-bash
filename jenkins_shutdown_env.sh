#!/bin/bash
##############################################################
#### Sript to shutdown speific env.
#### Usage:
####  $1 -> Environment name
####  $2 -> Start/Stop environment
##############################################################
# set -x

#### FUNCTION DEFINITION START

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
### Define initial variables. Accepts parameter:
###  $1 -> Environment
###  $2 -> Start/Stop environment
###################################################
def_env (){

   action="$2"
   WRK_DIR="/usr/opt/app/Ecom_V9/scripts"

   ## GIT
   . /usr/opt/app/Ecom_V9/scripts/.ssh_git/.token
   GIT_USER="as511-devops"
   GIT_REPO="github.com/path2gitkey/ecom-helmcharts.git"
   GIT_URL="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO}"
   GIT_DIR="/usr/opt/app/Ecom_V9/helmchart"
   GIT_MESSAGE="$1: Environment ${action}."
   FILE_BRANCH_PATH="hcl-commerce/values.yaml"

   ## Environment should be added to each section
   ENV=$1
   case ${ENV} in

      #####################################################################
      # GENERAL SECTION: to difine ArgoCD App; GC namespace; GIT branch name;
      # environment store name for environments with HelmCharts stored under master
      # ALL environments should be added here
      #####################################################################
      DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9|DEV10|TST10|STG|PRD)
         env_def=`echo ${ENV,,}`
         env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
         env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
         ARGO_APP="${ENV,,}-hcl-commerce"
         gcp_suffix="ecomenv"
         GC_NAMESPC="${ENV,,}"
         GIT_BRANCH="master"
      ;;&

      #######################################################################
      # ARGO SECTION:Argo CD Application overload for App using different naming templates
      #######################################################################
      TST3|TST9)
         ARGO_APP="${ENV,,}--commerce"
      ;;&

      STG|PRD)
         gcp_suffix="ecomprod"
      ;;&

      #####################################################################################
      # HELMCHART SECTION
      #####################################################################################

      # HelmCharts based on dir template under master branch
      DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9|DEV10|TST10)
      FILE="${GIT_DIR}/${GIT_BRANCH}/9.1.15.0/non-prod/hcl-commerce/${env_def}-values.yaml"
      ;;&

      # PRD/STG
      STG)
         FILE="${GIT_DIR}/${GIT_BRANCH}/9.1.15.0/prod/hcl-commerce/${env_def}-values.yaml"
      ;;&

      PRD)
         FILE="${GIT_DIR}/${GIT_BRANCH}/9.1.15.0/prod/hcl-commerce/prod-values.yaml"
      ;;&

      #####################################################################################
      # PURPOSE SECTION: Evironment auth or live
      #####################################################################################
      DEV1|DEV2|DEV3|DEV9|DEV10|STG)
         env_purp="auth"
      ;;

      TST1|TST2|TST3|TST9|TST10|PRD)
         env_purp="live"
      ;;

      *)
        print_message ERROR "def_env: Env name is incorrect!" 1; exit 1;
      ;;
   esac

   GC_WRKLOAD_SFX="${gcp_suffix}${env_num}"

}

###################################################
### Define GCP credentials. Accepts parameter: (used for auth to GCP)
###  $1 -> Environment
###################################################
def_env_gcp (){

   GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"

   ## Environment should be added to each section
   ENV=$1
   case ${ENV} in

      #####################################################################
      # GENERAL SECTION: to difine ArgoCD App; GC namespace; GIT branch name;
      # environment store name for environments with HelmCharts stored under master
      # ALL environments should be added here
      #####################################################################
      DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9|DEV10|TST10|STG|PRD)
         env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
         env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
         env_def="${ENV,,}"
         ARGO_APP="${env_def}-hcl-commerce"
         gcp_suffix="ecomenv"
         GC_NAMESPC="${env_def}"
         env_store=""
         GIT_BRANCH="master"
      ;;&

      TST3|TST9)
         ARGO_APP="${env_def}--commerce"
      ;;&
   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
      DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9)
         GC_PROJ=""
         GC_CL=""
         GC_SA="@.iam.gserviceaccount.com"
         GC_SA_KEY="${GC_SDK_DIR}/.json"
      ;;

      DEV10|TST10)
         GC_PROJ=""
         GC_CL=""
         GC_SA="@.iam.gserviceaccount.com"
         GC_SA_KEY="${GC_SDK_DIR}/.json"
      ;;

      STG|PRD)
         GC_PROJ=""
         GC_CL=""
         GC_SA="@.iam.gserviceaccount.com"
         GC_SA_KEY="${GC_SDK_DIR}/.json"
         GC_NAMESPC="${env_sym}"
      ;;

      *)
        print_message ERROR "def_env: Env name is incorrect!" 1; exit 1;
      ;;
   esac

}

###################################################
### Check bash exait status. Accepts param:
### $1 -> exit stat
### $2 -> command
###################################################
check_exit_stat (){

   exit_stat="$1"
   if [[ "${exit_stat}" != "0" ]];
   then
      print_message "ERROR" "$2: Command failed." "${rc}"; exit 1;
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
### ArgoCD: Login
###################################################
argocd_auth (){
   ## Obtain '' credetials
   ARGO_PROJ=""
   ARGO_CLUSTER=""
   GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
   ARGO_EXEC="/usr/opt/app/argocd"
   ARGO_SA="@${ARGO_PROJ}.iam.gserviceaccount.com"

   # Check if ${ARGO_SA} status:ACTIVE
   if ${GC_SDK_DIR}/bin/gcloud auth list --filter=status:ACTIVE | grep ${ARGO_SA} ;
   then
      print_message "INFO" "agrocd_auth: ${ARGO_SA} account is active." "" "no_frame"
   else
      ${GC_SDK_DIR}/bin/gcloud auth activate-service-account  --key-file=${GC_SDK_DIR}/${ARGO_PROJ}.json
   fi

   ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${ARGO_CLUSTER} --region us-east4 --project ${ARGO_PROJ}

   # Correct $PATH
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
      export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
   fi
   
   ## Get pwd
   argo_pass=`${GC_SDK_DIR}/bin/kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
   if [[ -z ${argo_pass} ]];
   then
      print_message "ERROR" "agrocd_auth: ArgoCD password ${argo_pass} is empty." ""
   fi

   ## Login
   ${ARGO_EXEC} login argocd.gcp.tailoredbrands.com --grpc-web --username admin --password ${argo_pass}
   rc="$?"; #check_exit_stat "${rc}" "argocd login"
   if [[ "${exit_stat}" != "0" ]];
   then
      print_message "ERROR" "argocd_auth: login argocd.gcp.tailoredbrands.com failed." "${rc}";
      sleep 5m
   fi

}

###################################################
### ArgoCD: Sync
###################################################
argocd_sync (){

   if [[ "argo_flag" != "failed" ]];
   then

      ## ArgoCD: update resource
      if [[ $(${ARGO_EXEC} app get ${ARGO_APP} --grpc-web | grep Deployment | grep ${GC_WRKLOAD} | grep "OutOfSync") ]];
      then   
         ${ARGO_EXEC} app get ${ARGO_APP} --grpc-web --refresh | grep "Deployment" | grep ${GC_WRKLOAD}
         print_message "INFO" "agrocd_sync: Sync about to begin..."
         ${ARGO_EXEC} app sync ${ARGO_APP} --grpc-web --resource apps:Deployment:${GC_NAMESPC}/${GC_WRKLOAD}
         rc="$?"; check_exit_stat "${rc}" "argocd sync"

         ## queryApp: need to be updated both data and auth query-apps
         if [[ ${VALUES_APP} == "queryApp" ]];
         then 
            ${ARGO_EXEC} app sync ${ARGO_APP} --grpc-web --resourse apps:Deployment:${GC_NAMESPC}/${GC_WRKLOAD2}
            rc="$?"; check_exit_stat "${rc}" "argocd sync(2)"
         fi
      fi

   else
      print_message "WARN" "argocd_sync: Login failed. Skipping.." "" "no";
   fi

}

###################################################
### ArgoCD: check sync or health status
### $1 -> time to sleep
###################################################
argocd_check_sync_stat (){

   if [[ "argo_flag" != "failed" ]];
   then
      step_max=4
      step_ini=0
      time_sleep="$1"

      while [ ${step_ini} -lt ${step_max} ]; do
         step_ini=$((step_ini+1))

         if [[ $(${ARGO_EXEC} app get ${ARGO_APP} --grpc-web | grep "FATA\|failed") ]];
         then
            print_message "ERROR" "argocd_check_sync: ${ARGO_EXEC} app get ${ARGO_APP} --grpc-web failed. Please check logs."
            step_ini=${step_max};

            # timeout for scheduled job
            if [[ "${OPT}" == "ALL_SCHEDULE" ]];
            then
               print_message "INFO" "argocd_check_sync: Waiting for next time auto-sync...(${time_sleep})"
               sleep ${time_sleep}
            fi

         elif [[ ! $(${ARGO_EXEC} app get ${ARGO_APP} --grpc-web | grep Deployment | grep ${GC_WRKLOAD_SFX} | grep "OutOfSync\|Progressing\|Suspended\|Degraded") ]];
         then
            step_ini=${step_max};
            print_message "SUCCESS" "argocd_check_sync: Pods ${GC_NAMESPC}/${GC_WRKLOAD_SFX} status: Synced/Healthy."

         elif [ "${step_ini}" == "${step_max}" ];
         then
            print_message "WARN" "argocd_check_sync: Pods ${GC_NAMESPC}/${GC_WRKLOAD_SFX} NOT synced/healthy. Please check logs."

         else
            print_message "INFO" "argocd_check_sync: Waiting ${time_sleep}..." "" "no"
            ${ARGO_EXEC} app get ${ARGO_APP} --grpc-web | grep Deployment | grep ${GC_WRKLOAD_SFX}
            sleep ${time_sleep}
         fi

      done

   else print_message "WARN" "argocd_check_sync: Login failed. Skipping.." "" "no";

   fi

}

###################################################
### Checkout Helm chart repo ;
###################################################
git_clone (){

   ## Clone repo
   if [ ! -d ${GIT_DIR} ];
   then
      mkdir ${GIT_DIR}; chmod -R 755 ${GIT_DIR};
   elif [ -d ${GIT_DIR}/${GIT_BRANCH} ];
   then
      rm -rf ${GIT_DIR}/${GIT_BRANCH}/
   fi

   cd ${GIT_DIR}
   git clone ${GIT_URL} --branch=${GIT_BRANCH} ${GIT_BRANCH}

}

###################################################
### Commit Helm chart repo ;
###################################################
git_commit (){

   ## Commit changes
   cd ${GIT_DIR}/${GIT_BRANCH}
   git commit -am "${GIT_MESSAGE}" #--author "${USER_EMAIL%@*} <${USER_EMAIL}>"
   # instead of git-push: git cherry-pick ${GIT_BRANCH}
   git push #origin ${GIT_BRANCH}

}

###################################################
### Set enabled flag stateful sets 
### $1 -> action
### $2 -> environment
### $3 -> values.yaml file
###################################################
set_enabled_stateful_set (){

   action="$1"
   ss_env="$2"
   values_yaml="$3"
   ss_array=(redis) ## app name at valyes.yaml

   ## stateful set located at uath envs only
   if [[ ${ENV_ARRAY_DEV[@]} =~ ${ss_env} ]];
   then

      for stateful_set in ${ss_array[@]}
      do

         print_message INFO "enabled_flag_stateful_set: Action ${action}: ${stateful_set}...";

         if [[ "${action}" == "stop" ]];
         then
            sed -z "s/${stateful_set}:\n  enabled: true/${stateful_set}:\n  enabled: false/" -i ${values_yaml}
         elif [[ "${action}" == "start" ]];
         then
            sed -z "s/${stateful_set}:\n  enabled: false/${stateful_set}:\n  enabled: true/" -i ${values_yaml}
         else
            print_message ERROR "enabled_flag_stateful_set: Action ${action} incorrect!";
            exit 1;
         fi

      done

   fi
}

###################################################
### Edit ${FILE} YAML ;
###################################################
yaml_update (){

   ## Edit YAML
   current_ts=`date +%FT%H%M%S`
   FILE_PREF="${WRK_DIR}/archive/values.${ENV}.${GIT_BRANCH}"
   FILE_BEFORE="${FILE_PREF}.before_stop.yaml"
   FILE_AFTER="${FILE_PREF}.after_stop.yaml"

   values_lineNum=`cat ${FILE} | wc -l`
   if [ ! -d ${GIT_DIR}/${GIT_BRANCH} ];
   then
      print_message ERROR "yaml_update: ${GIT_DIR}/${GIT_BRANCH}/ not found!" 1; 
      exit 1;
   elif [ ! -f ${FILE} ];
   then
      print_message ERROR "yaml_update: ${FILE} not found!" 1;
      exit 1;   
   fi

   ## Archive original
   if [ ! -d ${WRK_DIR}/archive ];
   then
      mkdir "${WRK_DIR}/archive"
   fi

   ## STOP ENV
   if [[ "${action}" == "stop" ]];
   then

      # Back up/ clean up previous backup
      if  [ -f ${FILE_BEFORE} ];
      then
         cp -av ${FILE_BEFORE} ${FILE_BEFORE}.${current_ts}
         find ${WRK_DIR}/archive/ -name "values.*.yaml.*" -mtime +90 -print -delete
      fi

      cp -av ${FILE} ${FILE_BEFORE}
      rc="$?"; check_exit_stat ${rc} "yaml_update"

      sed -i -E "s|(replica: )[0-9]+|\10|g" ${FILE}
      sed -i -E "s|(replicas: )[0-9]+|\10|g" ${FILE}
      sed -i -E "s|(replicaCount: )[0-9]+|\10|g" ${FILE}

      ## for Query App:
      sed -i -E "s|(auth: )[0-9]+|\10|g" ${FILE}
      sed -i -E "s|(live: )[0-9]+|\10|g" ${FILE}
      sed -i -E "s|(data: )[0-9]+|\10|g" ${FILE}

      ## for Stateful sets (applied only for auth envs)
      set_enabled_stateful_set ${action} ${ENV} ${FILE}

      print_message INFO "yaml_update: file diff ${FILE_BEFORE}:"
      diff --suppress-common-lines -y ${FILE} ${FILE_BEFORE}

      # Restore 'previous' backup if GCP environment was already stopped
      DIFF_FLAG=0
      if cmp -s ${FILE} ${FILE_BEFORE}
      then
         print_message ERROR "yaml_update: FILE not differs FILE_BEFORE! Restoring values.yaml..."
         cp -av ${FILE_BEFORE}.${current_ts} ${FILE_BEFORE}
         cp -av ${FILE_BEFORE}.${current_ts} ${FILE}
         DIFF_FLAG=1
      fi

      # Save stopped env yaml
      if [[ "${DIFF_FLAG}" -eq "0" ]];
      then
         cp -av ${FILE} ${FILE_AFTER}
      fi

   ## START ENV
   elif [[ "${action}" == "start" ]];
   then

      # Backup file before start
      cp -av ${FILE} ${FILE_PREF}.before_start.yaml

      print_message INFO "yaml_update: file diff current values.yaml from GIT and before ${ENV} shutdown:"
      diff --suppress-common-lines -y ${FILE} ${FILE_BEFORE}

      print_message INFO "yaml_update: file diff current values.yaml and after ${ENV} shutdown:"
      diff --suppress-common-lines -y ${FILE} ${FILE_AFTER}

      print_message INFO "yaml_update: patching ${FILE}."

      # Save diff
      diff -u ${FILE} ${FILE_AFTER} > ${FILE}.patch

      # Patch required in case if changes were applied during the stop
      cp -av ${FILE_BEFORE} ${FILE}

      patch -uR ${FILE} < ${FILE}.patch; rc="$?";

#      DIFF_FLAG=0
      if [[ "${rc}" != "0" ]];
      then
         print_message WARN "yaml_update: patch cmd failed! Check logs. Skipping ${ENV} patch...
NOTE1: File will be restored without patching changes happened after ${ENV} shutdown.
NOTE2: 'Unreversed patch detected' message -- means that patch not needed!"
         rm ${FILE}.rej

#         DIFF_FLAG=1
      fi

      print_message INFO "yaml_update: file diff patched values.yaml and after ${ENV} shutdown:"
      diff --suppress-common-lines -y ${FILE} ${FILE_AFTER}

      # Clean up GIT
      rm ${FILE}.patch 

   fi

}

###################################################
### Clean up 
###################################################
clean_up (){

   if [ -d ${GIT_DIR}/${GIT_BRANCH} ];
   then 
      cd ${GIT_DIR} && rm -rf ${GIT_DIR}/${GIT_BRANCH};
   fi

}

#########################################################
### Sent alert mail
###  $1 -> subject
###  $2 -> body
#########################################################
mail_send (){

   mail_to=""
   mail_subj="$1"
   mail_body="$2"

   echo "${mail_body}" | mutt -s "${mail_subj}" -- ${mail_to}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "WARN" "mail_send: Sent mail failed!" "${rc}"
   fi

}

###################################################
### Force scale deployments
### $1 -> action
###################################################
scale_replica_deployment (){

   action="$1"
   app_array=(nifi-app) ## Deployment name at  GCP namespace
   replica_num_array=(1)

   print_message INFO "scale_replica_deployment: Manual Deployment processing...";

   for dev_env in ${ENV_ARRAY_DEV[@]};
   do

      def_env_gcp ${dev_env};

      # correct $PATH
      if ! echo $PATH | grep ${GC_SDK_DIR};
      then
          export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
      fi

      gc_auth;

      ## stateful set start|stop
      i=0
      for app_name in ${app_array[@]};
      do
        deployment_name="${gcp_suffix}${env_num}${app_name}"
        print_message INFO "scale_replica_deployment: ${deployment_name}: ${action}...";

        if [[ "${action}" -eq "stop" ]];
        then
           # scale
           print_message INFO "kubectl scale deployment ${deployment_name} --replicas=0 -n ${GC_NAMESPC}" "" no_frame;
           ${GC_SDK_DIR}/bin/kubectl scale deployment ${deployment_name} --replicas=0 -n ${GC_NAMESPC}
           sleep 10
           # drop
           #print_message INFO "kubectl delete statefulsets ${deployment_name} -n ${GC_NAMESPC}" "" no_frame;
           #${GC_SDK_DIR}/bin/kubectl delete statefulsets ${deployment_name} -n ${GC_NAMESPC}
        elif [[ "${action}" -eq "start" ]];
        then
           print_message WARN "scale_replica_deployment: Check Helm charts and sync from ArgoCD. Exiting...";
           exit 1;
           #${GC_SDK_DIR}/bin/kubectl scale deployment ${deployment_name} --replicas=${replica_num_array[$i]} -n ${GC_NAMESPC}
        else
           print_message ERROR "scale_replica_deployment: Action incorrect!(${action})";
           exit 1;
        fi

        i=$((i+1))
      done

   done

}

###################################################
### Force scale/delete stateful sets 
### $1 -> action
###################################################
drop_replica_stateful_set (){

   action="$1"
   stateful_set_array=(hcl-commerce-zookeeper hcl-commerce-redis-master) ## Stateful set name at  GCP namespace
   replica_num_array=(1 1)

   print_message INFO "scale_replica_stateful_set: Processing Stateful Sets...";

   for dev_env in ${ENV_ARRAY_DEV[@]};
   do

      def_env_gcp ${dev_env};

      # correct $PATH
      if ! echo $PATH | grep ${GC_SDK_DIR};
      then
          export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
      fi

      gc_auth;

      ## stateful set start|stop
      i=0
      for stateful_set in ${stateful_set_array[@]};
      do
        print_message INFO "scale_replica_stateful_set: ${dev_env} ${stateful_set}: ${action}...";

        if [[ "${action}" -eq "stop" ]];
        then
           # scale
           print_message INFO "kubectl scale deployment ${stateful_set} --replicas=0 -n ${GC_NAMESPC}" "" no_frame;
           ${GC_SDK_DIR}/bin/kubectl scale deployment ${stateful_set} --replicas=0 -n ${GC_NAMESPC}
           sleep 10
           # drop
           print_message INFO "kubectl delete statefulsets ${stateful_set} -n ${GC_NAMESPC}" "" no_frame;
           ${GC_SDK_DIR}/bin/kubectl delete statefulsets ${stateful_set} -n ${GC_NAMESPC}
        elif [[ "${action}" -eq "start" ]];
        then
           print_message WARN "scale_replica_stateful_set: Check Helm charts and sync from ArgoCD. Exiting...";
           exit 1;
           #${GC_SDK_DIR}/bin/kubectl scale deployment ${stateful_set} --replicas=${replica_num_array[$i]} -n ${GC_NAMESPC}
        else
           print_message ERROR "scale_replica_stateful_set: Action incorrect!(${action})";
           exit 1;
        fi

        i=$((i+1))
      done

   done

}

ENV_ARRAY=()
ENV_ARRAY_DEV=()
ENV_ARRAY_TST=()
###################################################
### Process envs in list
### $1 -> action
###################################################
process_env_list (){

   ## Define env order
   if [[ "$1" == "stop" ]];
   then

      # Start "stop" from TST envs
      if [ ${#ENV_ARRAY_TST[@]} -ne 0 ]; then
      ENV_ARRAY+=(${ENV_ARRAY_TST[@]})
      fi

      if [ ${#ENV_ARRAY_DEV[@]} -ne 0 ]; then
      ENV_ARRAY+=(${ENV_ARRAY_DEV[@]})
      fi

   elif [[ "$1" == "start" ]];
   then

      # Start "start" from DEV envs
      if [ ${#ENV_ARRAY_DEV[@]} -ne 0 ]; then
      ENV_ARRAY+=(${ENV_ARRAY_DEV[@]})
      fi

      if [ ${#ENV_ARRAY_TST[@]} -ne 0 ]; then
      ENV_ARRAY+=(${ENV_ARRAY_TST[@]})
      fi

   fi

   if [ ${#ENV_ARRAY[@]} -eq 0 ]; then
      print_message ERROR "process_env_list: Env list array  is empty! Check logs."; echo "${ENV_ARRAY[@]}"
      exit 1
   fi

   print_message INFO "process_env_list: Below envs will be proceeded:"; echo "${ENV_ARRAY[@]}"

   mail_subj="[INFO]: v9 / Re-plaform environmets: $1"
   mail_body="Below environments will be proceeded: 
${ENV_ARRAY[@]}"
   mail_send "${mail_subj}" "${mail_body}"

   for environment in ${ENV_ARRAY[@]}
   do
      def_env ${environment} $1

      git_clone
      yaml_update

      git_commit
      clean_up
      argocd_auth

   done

   ## Check sync status
   for environment in ${ENV_ARRAY[@]}
   do
      def_env ${environment} $1
      argocd_check_sync_stat "3m"
   done

   ## Forcefully stop Stateful set
   if [[ "$1" == "stop" ]];
   then
      drop_replica_stateful_set stop;
      scale_replica_deployment stop;
   fi

}

#### FUNCTION DEFINITION END

###################################################
#### MAIN
###################################################
OPT="$1"
case ${OPT} in 
   ALL)
      ENV_ARRAY_DEV=(DEV1 DEV2 DEV3 DEV9 DEV10)
      ENV_ARRAY_TST=(TST1 TST2 TST3 TST9 TST10)
      process_env_list $2
   ;;

   ALL_SCHEDULE)
      ENV_ARRAY_DEV=(DEV1 DEV2 DEV3 DEV9 DEV10)
      ENV_ARRAY_TST=(TST1 TST2 TST3 TST9 TST10)
      process_env_list $2
   ;;

   DEV1_TST1)
      ENV_ARRAY_DEV=(DEV1)
      ENV_ARRAY_TST=(TST1)
      process_env_list $2
   ;;

   DEV2_TST2)
      ENV_ARRAY_DEV=(DEV2)
      ENV_ARRAY_TST=(TST2)
      process_env_list $2
   ;;

   DEV3_TST3)
      ENV_ARRAY_DEV=(DEV2)
      ENV_ARRAY_TST=(TST2)
      process_env_list $2
   ;;

   DEV9_TST9)
      ENV_ARRAY_DEV=(DEV9)
      ENV_ARRAY_TST=(TST9)
      process_env_list $2
   ;;

   DEV10_TST10)
      ENV_ARRAY_DEV=(DEV10)
      ENV_ARRAY_TST=(TST10)
      process_env_list $2
   ;;

   DROP_STATEFUL_SET)
      ENV_ARRAY_DEV=(DEV1 DEV2 DEV9 DEV10)
      drop_replica_stateful_set stop;
   ;;

   SCALE_DOWN_DEPLOY)
      ENV_ARRAY_DEV=(DEV1 DEV2 DEV9 DEV10)
      scale_replica_deployment stop;
   ;;

   *)
      def_env $1 $2

      mail_subj="[INFO]: v9 $1 environmet: $2"
      mail_body="No actions required."
      mail_send "${mail_subj}" "${mail_body}"

      git_clone
      yaml_update
      git_commit
      clean_up

      argocd_auth
      if [[ "${ENV}" == "PRD" || "${ENV}" == "STG" ]]
      then
         argocd_sync
      fi
      argocd_check_sync_stat "3m" 

      ## Forcefully stop Stateful set
      if [[ "$1" == "stop" ]];
      then
         drop_replica_stateful_set stop;
         scale_replica_deployment stop;
      fi
   ;;

esac

