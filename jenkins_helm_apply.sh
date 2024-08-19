#!/bin/bash
##########################################################
#### Sript to apply/deploy Helm Charts changes
#### Usage:
####  $1 -> Environment name
####  $2 -> Application name (from values.yaml)
####  $3 -> Branch name (tag to be updated)
####  $4 -> Username (from Jenkins)
##########################################################
# set -x

#### FUNCTION DEFINITION START

# Correct $PATH
if ! echo $PATH | grep ${GC_SDK_DIR};
then
   export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
fi

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
### Define initial variables. Accepts parameters:
###  $1 -> Environment
###  $2 -> Application
###  $3 -> Branch
###  $4 -> Username
###################################################
def_env (){
   VALUES_APP="$2"
   VALUES_TAG="$3"

   # Jenkins $BUILD_USER_EMAIL env variable
   if [ ! -z "$4" ]; then USER_EMAIL="$4"; fi

   VALUES_APP_LIST=(tsDb tsApp tsUtils searchAppMaster searchAppRepeater searchAppSlave tsWeb toolingWeb storeWeb crsApp csrApp xcApp nifiApp registryApp ingestApp queryApp cacheApp supportC nextjs nodejs nodejsMC nodejs reactjs appD nginx)
   if [[ ! ${VALUES_APP_LIST[*]} =~ "$VALUES_APP" ]];
   then
      print_message ERROR "def_env: App name $VALUES_APP is incorrect!" 1; exit 1;
   fi

   ## GIT
   . /usr/opt/app/Ecom_V9/scripts/.ssh_git/.token
   GIT_USER="as511-devops"
   GIT_REPO="github.com/Wearhouse/ecom-helmcharts.git"
   GIT_URL="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO}"
   GIT_DIR="/usr/opt/app/Ecom_V9/helmchart"
   GIT_MESSAGE="${VALUES_APP}: Updated tag to ${VALUES_TAG} by ${USER_EMAIL}."
   FILE_BRANCH_PATH="hcl-commerce/values.yaml"

   ## Env specific
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
         GIT_BRANCH="master"
      ;;&

      #####################################################################################
      # HELMCHART SECTION
      #####################################################################################
      # HelmCharts based on single dir for multiple templates under master branch
      DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9|DEV10|TST10)
      FILE="${GIT_DIR}/${GIT_BRANCH}/9.1.15.0/non-prod/hcl-commerce/${env_def}-values.yaml"
      ;;

      # PRD/STG
      STG)
         FILE="${GIT_DIR}/${GIT_BRANCH}/9.1.15.0/prod/hcl-commerce/${env_def}-values.yaml"
      ;;

      PRD)
         FILE="${GIT_DIR}/${GIT_BRANCH}/9.1.15.0/prod/hcl-commerce/prod-values.yaml"
      ;;

      *)
        print_message ERROR "def_env: Env name is incorrect!" 1; exit 1;
      ;;

   esac

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
### Edit ${FILE} YAML ;
###################################################
yaml_update (){
   ## Edit YAML
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
   if [ ! -d ${GIT_DIR}/archive ];
   then
      mkdir "${GIT_DIR}/archive"
   elif [ ! -f "${GIT_DIR}/archive/values.${GIT_DIR}.before_yq.yaml" ];
   then
      cp -av ${FILE} "${GIT_DIR}/archive/values.${GIT_BRANCH}.before_yq.yaml"
   fi

   ## Note: yq: https://github.com/mikefarah/yq/#install
   ## Version: https://github.com/mikefarah/yq/releases/tag/v4.25.2
   WRK_FILE="${GIT_DIR}/${GIT_BRANCH}/values.yaml"

   # yq: removes NOT NEEDED spaces/tabs/newlines in any case
   # to keep file readable replace empty lines with '##'
   sed -i -e 's/^$/##/' ${FILE}

   cp -av ${FILE} ${WRK_FILE}.orig
   cp -av ${FILE} ${WRK_FILE}.yqmod

   # Dynamically update a path from an environment variable:
   # mytag="tsApp" newtag="asfdghjb" yq -i '.[env(mytag)].tag = env(newtag)' values.yaml
   app_tag_orig=$(appName="${VALUES_APP}" yq '.[env(appName)].tag' ${WRK_FILE}.orig);
   if [ "${app_tag_orig}" == "${VALUES_TAG}" ];
   then
      print_message WARN "yaml_update: tag ${app_tag_orig} already applied."
      exit 0
   fi
   appName="${VALUES_APP}" \
   newTag="${VALUES_TAG}" \
   yq -i '.[env(appName)].tag = env(newTag)' ${WRK_FILE}.yqmod >/dev/null 2>&1

   # Save diff original file and yq modified
   diff ${WRK_FILE}.orig ${WRK_FILE}.yqmod > ${WRK_FILE}.diff

   # Patch required to fix: yq removing of all comments
   patch -o ${WRK_FILE}.patch ${WRK_FILE}.orig < ${WRK_FILE}.diff
   cp -av ${WRK_FILE}.patch ${FILE}

   # Git repo clean up
   rm ${WRK_FILE}.orig ${WRK_FILE}.yqmod ${WRK_FILE}.diff ${WRK_FILE}.patch

   ## Pre-commit check
   values_lineNum_new=`cat ${FILE} | wc -l`
   if [[ "${values_lineNum}" != "${values_lineNum_new}" ]];
   then
      print_message WARN "yaml_update: Lines quantity differs! Old: ${values_lineNum}. New: ${values_lineNum_new}." ;
      #exit 1;
   fi  
}

###################################################
### Commit Helm chart repo ;
###################################################
git_commit (){
   ## Commit changes
   cd ${GIT_DIR}/${GIT_BRANCH}
   git commit -am "${GIT_MESSAGE}" --author "${USER_EMAIL%@*} <${USER_EMAIL}>"
   # instead of git-push: git cherry-pick ${GIT_BRANCH}
   git push #origin ${GIT_BRANCH}
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

#### FUNCTION DEFINITION END

###################################################
#### MAIN
###################################################
def_env $1 $2 $3 $4
git_clone
yaml_update
git_commit
clean_up
